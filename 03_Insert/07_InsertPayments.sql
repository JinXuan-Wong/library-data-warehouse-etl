-- Payments (Depends on Members)
CREATE OR REPLACE PROCEDURE gen_payments_members_fines(
  p_start_date    DATE   := DATE '2004-07-01',
  p_end_date      DATE   := DATE '2024-06-30',
  p_avg_per_month NUMBER := 25
) IS
  v_members_cnt NUMBER;
  v_months      NUMBER;

  v_first  DATE; 
  v_last   DATE; 
  v_cnt    NUMBER;

  v_member  Members.memberId%TYPE;
  v_type    Payments.paymentType%TYPE;
  v_method  Payments.paymentMethod%TYPE;
  v_amt     Payments.payAmount%TYPE;
  v_date    DATE;

  v_pay_id  Payments.paymentId%TYPE;
  v_rcpt    Payments.receiptNo%TYPE;
BEGIN
  -- sanity checks
  SELECT COUNT(*) INTO v_members_cnt FROM Members;
  IF v_members_cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-22001, 'Members table is empty.');
  END IF;

  -- Check if sequences exist
  BEGIN
    SELECT seq_payment.NEXTVAL INTO v_pay_id FROM dual;
    SELECT seq_receipt.NEXTVAL INTO v_rcpt FROM dual;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-22002, 'Sequence does not exist or is inaccessible');
  END;

  v_months := MONTHS_BETWEEN(
                ADD_MONTHS(TRUNC(p_end_date,'MM'),1),
                TRUNC(p_start_date,'MM'));

  FOR m IN 0 .. v_months-1 LOOP
    v_first := ADD_MONTHS(TRUNC(p_start_date,'MM'), m);
    v_last  := LEAST(LAST_DAY(v_first), p_end_date);
    v_cnt   := GREATEST(0, ROUND(p_avg_per_month + DBMS_RANDOM.NORMAL * 2));

    FOR i IN 1..v_cnt LOOP
      -- pick a random member
      SELECT memberId INTO v_member
      FROM (SELECT memberId FROM Members ORDER BY DBMS_RANDOM.VALUE)
      WHERE ROWNUM = 1;

      -- decide type and amount
      IF DBMS_RANDOM.VALUE < 0.6 THEN
        v_type := 'Membership Registration';
        v_amt  := ROUND(DBMS_RANDOM.VALUE(50,150), 2);
      ELSE
        v_type := 'Fines';
        v_amt  := ROUND(DBMS_RANDOM.VALUE(1,50), 2);
      END IF;

      -- method and date
      v_method := CASE TRUNC(DBMS_RANDOM.VALUE(0,3))
                    WHEN 0 THEN 'Tng'
                    WHEN 1 THEN 'Cash'
                    ELSE 'Duitnow' END;
      v_date := v_first + TRUNC(DBMS_RANDOM.VALUE(0, v_last - v_first + 1));

      -- Generate IDs with more digits to avoid collisions
      v_pay_id := 'P'||LPAD(seq_payment.NEXTVAL, 8, '0');  -- Increased to 8 digits
      v_rcpt   := 'R'||LPAD(seq_receipt.NEXTVAL, 8, '0');  -- Increased to 8 digits

      BEGIN
        INSERT INTO Payments(paymentId, memberId, paymentDate, payAmount,
                           paymentMethod, paymentType, receiptNo)
        VALUES (v_pay_id, v_member, v_date, v_amt, v_method, v_type, v_rcpt);
      EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
          -- If duplicate occurs, skip this record and continue
          NULL;
      END;
    END LOOP;
  END LOOP;

  COMMIT;
END;
/
SHOW ERRORS PROCEDURE gen_payments_members_fines;

-- Membership + fines (≈25 per month)
BEGIN
  gen_payments_members_fines(DATE '2004-07-01', DATE '2024-06-30', 25);
END;
/

select count(*) from Payments;