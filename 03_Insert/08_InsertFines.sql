-- Fines (Depends on BorrowedBooks, Payments)
-- Creates/uses seq_fine; generates fines and links Fines payments.
-- Rules:
--   Lost  : fineAmount = purchasePrice + 20
--   Damage: fineAmount = purchasePrice (random small share of returned)
--   Late  : if overdue 1..7 days => 30
-- Payment linking:
--   For each Payments(paymentType='Fines'), attach up to 2 unpaid 'Lost Book' fines
--   for the same member, with fineDate <= paymentDate, and set status='Paid'.

-- Drop FK safely (name may differ; adjust if needed)
-- ALTER TABLE Fines DROP CONSTRAINT fk_Fines_BorrowedBooks;

-- Recreate FK
-- ALTER TABLE Fines ADD CONSTRAINT fk_Fines_BorrowedBooks
  -- FOREIGN KEY (borrowId) REFERENCES BorrowedBooks (borrowId);

CREATE OR REPLACE PROCEDURE gen_fines_and_linked_payments(
  p_start_date    DATE   := DATE '2004-07-01',
  p_end_date      DATE   := DATE '2024-06-30',
  p_damage_rate   NUMBER := 0.03,
  p_avg_pay_month NUMBER := 6
) IS
  v_dummy NUMBER;
  e_seq_missing EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_seq_missing, -2289);

  v_rows PLS_INTEGER;
  v_members_cnt NUMBER;
  v_months      NUMBER;
  v_first  DATE;
  v_last   DATE;
  v_cnt    NUMBER;
  v_member  Members.memberId%TYPE;
  v_method  Payments.paymentMethod%TYPE;
  v_pdate   DATE;
  v_pay_id  Payments.paymentId%TYPE;
  v_rcpt    Payments.receiptNo%TYPE;
BEGIN
  -- Ensure sequences exist (don’t recreate if present)
  BEGIN SELECT seq_fine.NEXTVAL    INTO v_dummy FROM dual; EXCEPTION WHEN e_seq_missing THEN EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_fine START WITH 1 INCREMENT BY 1 NOCACHE'; END;
  BEGIN SELECT seq_payment.NEXTVAL INTO v_dummy FROM dual; EXCEPTION WHEN OTHERS THEN RAISE_APPLICATION_ERROR(-22021,'seq_payment missing'); END;
  BEGIN SELECT seq_receipt.NEXTVAL INTO v_dummy FROM dual; EXCEPTION WHEN OTHERS THEN RAISE_APPLICATION_ERROR(-22022,'seq_receipt missing'); END;

  /* ================= LOST: purchasePrice + 20 ================= */
  MERGE INTO Fines f
  USING (
    SELECT b.borrowId                          AS borrowId,
           'Lost Book'                         AS fineType,
           (bt.purchasePrice + 20)             AS fineAmount,
           LEAST(NVL(b.returnDate, b.dueDate+1), p_end_date) AS fineDate
    FROM   BorrowedBooks b
    JOIN   BookCopies   c  ON c.copyId  = b.copyId
    JOIN   BookTitles   bt ON bt.bookId = c.bookId
    WHERE  UPPER(b.returnStatus) = 'LOST'
       AND b.borrowDate BETWEEN p_start_date AND p_end_date
  ) s
  ON (f.borrowId = s.borrowId AND f.fineType = s.fineType)
  WHEN NOT MATCHED THEN
    INSERT (fineId, borrowId, paymentId, fineType, fineAmount, fineDate, fineStatus)
    VALUES ('F'||LPAD(seq_fine.NEXTVAL, 6, '0'), s.borrowId, NULL, s.fineType, s.fineAmount, s.fineDate, 'Unpaid');

  v_rows := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Inserted LOST fines: '||v_rows);

  /* ================= LATE: 1..7 days late -> RM30 ================= */
  MERGE INTO Fines f
  USING (
    SELECT b.borrowId         AS borrowId,
           'Late Return'      AS fineType,
           30                 AS fineAmount,
           b.returnDate       AS fineDate
    FROM   BorrowedBooks b
    WHERE  b.returnDate IS NOT NULL
       AND UPPER(b.returnStatus) IN ('OVERDUE','RETURNED')
       AND b.borrowDate BETWEEN p_start_date AND p_end_date
       AND GREATEST(TRUNC(b.returnDate) - TRUNC(b.dueDate), 0) BETWEEN 1 AND 7
  ) s
  ON (f.borrowId = s.borrowId AND f.fineType = s.fineType)
  WHEN NOT MATCHED THEN
    INSERT (fineId, borrowId, paymentId, fineType, fineAmount, fineDate, fineStatus)
    VALUES ('F'||LPAD(seq_fine.NEXTVAL, 6, '0'), s.borrowId, NULL, s.fineType, s.fineAmount, s.fineDate, 'Unpaid');

  v_rows := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Inserted LATE fines: '||v_rows);

  /* ================= DAMAGE: ~p_damage_rate of RETURNED ================= */
  MERGE INTO Fines f
  USING (
    SELECT b.borrowId         AS borrowId,
           'Damage'           AS fineType,
           bt.purchasePrice   AS fineAmount,
           b.returnDate       AS fineDate
    FROM (
      SELECT /*+ MATERIALIZE */ b.*, DBMS_RANDOM.VALUE rnd
      FROM BorrowedBooks b
      WHERE UPPER(b.returnStatus) = 'RETURNED'
        AND b.returnDate IS NOT NULL
        AND b.borrowDate BETWEEN p_start_date AND p_end_date
    ) b
    JOIN   BookCopies   c  ON c.copyId  = b.copyId
    JOIN   BookTitles   bt ON bt.bookId = c.bookId
    WHERE  b.rnd < p_damage_rate
  ) s
  ON (f.borrowId = s.borrowId AND f.fineType = s.fineType)
  WHEN NOT MATCHED THEN
    INSERT (fineId, borrowId, paymentId, fineType, fineAmount, fineDate, fineStatus)
    VALUES ('F'||LPAD(seq_fine.NEXTVAL, 6, '0'), s.borrowId, NULL, s.fineType, s.fineAmount, s.fineDate, 'Unpaid');

  v_rows := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Inserted DAMAGE fines: '||v_rows);

  COMMIT;

  /* ====== PAYMENTS (top-2 by date without FETCH FIRST) ====== */
  SELECT COUNT(*) INTO v_members_cnt FROM Members;
  IF v_members_cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-22001,'Members table is empty.');
  END IF;

  v_months := MONTHS_BETWEEN( ADD_MONTHS(TRUNC(p_end_date,'MM'),1), TRUNC(p_start_date,'MM') );

  FOR m IN 0 .. v_months-1 LOOP
    v_first := ADD_MONTHS(TRUNC(p_start_date,'MM'), m);
    v_last  := LEAST(LAST_DAY(v_first), p_end_date);
    v_cnt   := GREATEST(0, ROUND(p_avg_pay_month + DBMS_RANDOM.NORMAL * 2));

    FOR i IN 1..v_cnt LOOP
      BEGIN
        SELECT memberId INTO v_member
        FROM (
          SELECT DISTINCT b.memberId
          FROM Fines f
          JOIN BorrowedBooks b ON b.borrowId = f.borrowId
          WHERE f.fineStatus = 'Unpaid'
            AND f.fineDate BETWEEN p_start_date AND p_end_date
        ) WHERE ROWNUM = 1;
      EXCEPTION WHEN NO_DATA_FOUND THEN
        CONTINUE;
      END;

      v_method := CASE TRUNC(DBMS_RANDOM.VALUE(0,3))
                    WHEN 0 THEN 'Tng'
                    WHEN 1 THEN 'Cash'
                    ELSE 'Duitnow' END;

      v_pdate := v_first + TRUNC(DBMS_RANDOM.VALUE(0, v_last - v_first + 1));

      v_pay_id := 'P'||LPAD(seq_payment.NEXTVAL, 8, '0');
      v_rcpt   := 'R'||LPAD(seq_receipt.NEXTVAL, 8, '0');

      DECLARE v_total NUMBER := 0; BEGIN
        -- LOST first (up to 2)  <<< fixed TOP-N
        FOR lf IN (
          SELECT fineId, fineAmount
          FROM (
            SELECT f.fineId, f.fineAmount
            FROM   Fines f
            JOIN   BorrowedBooks b ON b.borrowId = f.borrowId
            WHERE  f.fineStatus = 'Unpaid'
              AND  f.fineType   = 'Lost Book'
              AND  b.memberId   = v_member
              AND  f.fineDate  <= v_pdate
            ORDER  BY f.fineDate
          )
          WHERE ROWNUM <= 2
        ) LOOP
          v_total := v_total + lf.fineAmount;
          UPDATE Fines SET paymentId = v_pay_id, fineStatus = 'Paid'
          WHERE fineId = lf.fineId;
        END LOOP;

        -- If none, use Late/Damage (still max two total)  <<< fixed TOP-N
        IF v_total = 0 THEN
          FOR ofn IN (
            SELECT fineId, fineAmount
            FROM (
              SELECT f.fineId, f.fineAmount
              FROM   Fines f
              JOIN   BorrowedBooks b ON b.borrowId = f.borrowId
              WHERE  f.fineStatus = 'Unpaid'
                AND  f.fineType IN ('Late Return','Damage')
                AND  b.memberId   = v_member
                AND  f.fineDate  <= v_pdate
              ORDER  BY f.fineDate
            )
            WHERE ROWNUM <= 2
          ) LOOP
            v_total := v_total + ofn.fineAmount;
            UPDATE Fines SET paymentId = v_pay_id, fineStatus = 'Paid'
            WHERE fineId = ofn.fineId;
          END LOOP;
        END IF;

        IF v_total > 0 THEN
          INSERT INTO Payments(paymentId, memberId, paymentDate, payAmount,
                               paymentMethod, paymentType, receiptNo)
          VALUES (v_pay_id, v_member, v_pdate, v_total,
                  v_method, 'Fines', v_rcpt);
        END IF;
      END;
    END LOOP;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Done generating fines and linked payments.');
END;
/


SHOW ERRORS PROCEDURE gen_fines_and_linked_payments;

SET SERVEROUTPUT ON

BEGIN
  gen_fines_and_linked_payments(
    p_start_date    => DATE '2004-07-01',
    p_end_date      => DATE '2024-06-30',
    p_damage_rate   => 0.03,
    p_avg_pay_month => 6
  );
END;
/



SELECT COUNT(*) FROM Fines;

