SET SERVEROUTPUT ON

DROP SEQUENCE seq_borrow;

CREATE SEQUENCE seq_borrow
  START WITH 1
  INCREMENT BY 1
  NOCACHE;

CREATE OR REPLACE PROCEDURE gen_borrowed_books_20y IS
   /* ---- Collections ---- */
  TYPE t_member_rec IS RECORD (
    member_id Members.memberId%TYPE,
    reg_date  DATE,
    exp_date  DATE
  );
  TYPE t_member_tab IS TABLE OF t_member_rec;
  v_members t_member_tab;

  TYPE t_copy_tab IS TABLE OF BookCopies.copyId%TYPE;
  v_copies  t_copy_tab;

  v_start_date   DATE := DATE '2004-07-01';
  v_end_date     DATE := DATE '2024-06-30';
  v_target_count NUMBER := 200000;

  v_day DATE;
  v_is_weekend BOOLEAN;
  v_per_day NUMBER;
  v_cnt     NUMBER := 0;

  v_borrow_id     VARCHAR2(10);
  v_member_id     Members.memberId%TYPE;
  v_copy_id       BookCopies.copyId%TYPE;
  v_borrow_date   DATE;
  v_due_date      DATE;
  v_return_date   DATE;
  v_return_status BorrowedBooks.returnStatus%TYPE;
  v_extend_status BorrowedBooks.extendStatus%TYPE;

  FUNCTION choose_return_status RETURN VARCHAR2 IS
    r NUMBER := DBMS_RANDOM.VALUE(0,100);
  BEGIN
    IF r < 85 THEN
      RETURN 'Returned';
    ELSIF r < 93 THEN
      RETURN 'Overdue';
    ELSIF r < 95 THEN
      RETURN 'Lost';
    ELSE
      RETURN 'On loan';
    END IF;
  END;

  FUNCTION choose_extend_status RETURN VARCHAR2 IS
    r NUMBER := DBMS_RANDOM.VALUE(0,100);
    r2 NUMBER;
  BEGIN
    IF r < 97 THEN
      RETURN 'Unsubmitted';
    ELSE
      r2 := DBMS_RANDOM.VALUE(0,4);
      CASE TRUNC(r2)
        WHEN 0 THEN RETURN 'Pending';
        WHEN 1 THEN RETURN 'Approved';
        WHEN 2 THEN RETURN 'Rejected';
        WHEN 3 THEN RETURN 'Canceled';
        ELSE       RETURN 'Pending';
      END CASE;
    END IF;
  END;

 FUNCTION pick_valid_member(p_on_date DATE) RETURN Members.memberId%TYPE IS
    tries PLS_INTEGER := 0;
    idx   PLS_INTEGER;
  BEGIN
    LOOP
      tries := tries + 1;
      IF tries > 50 THEN
        RETURN NULL; -- no valid member found quickly; skip this borrow
      END IF;

      idx := TRUNC(DBMS_RANDOM.VALUE(1, v_members.COUNT + 1));
      IF v_members(idx).reg_date <= TRUNC(p_on_date)
         AND TRUNC(p_on_date) <= v_members(idx).exp_date THEN
        RETURN v_members(idx).member_id;
      END IF;
    END LOOP;
  END;

BEGIN
  /* 1) Load members with windows (do NOT filter by current memberStatus) */
  SELECT m.memberId, TRUNC(m.registrationDate), TRUNC(m.expireDate)
  BULK COLLECT INTO v_members
  FROM Members m
  WHERE m.memberId BETWEEN 'M0001' AND 'M7500';  -- adjust if you want wider range

  IF v_members.COUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20020, 'No members found.');
  END IF;

  -- 2) Load eligible copies once
  SELECT c.copyId
  BULK COLLECT INTO v_copies
  FROM BookCopies c
  WHERE c.copyId BETWEEN 'C00001' AND 'C45000';

  IF v_copies.COUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20021, 'No eligible book copies found.');
  END IF;

  v_day := v_start_date;

  WHILE v_day <= v_end_date AND v_cnt < v_target_count LOOP
    v_is_weekend := (TO_CHAR(v_day, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT','SUN'));
    IF NOT v_is_weekend THEN
      v_per_day := TRUNC(DBMS_RANDOM.VALUE(35,41));  -- 35 to 40 per weekday

      FOR i IN 1..v_per_day LOOP
        EXIT WHEN v_cnt >= v_target_count;

        -- Pick random member and copy from arrays
        -- inside the FOR i IN 1..v_per_day loop:
        v_member_id := pick_valid_member(v_day);
        IF v_member_id IS NULL THEN
          CONTINUE; -- couldn't find a valid member quickly; skip this attempt
        END IF;

        v_copy_id   := v_copies(TRUNC(DBMS_RANDOM.VALUE(1, v_copies.COUNT+1)));

        v_borrow_date := v_day;
        v_due_date    := v_borrow_date + 10;

        v_return_status := choose_return_status;

        IF v_return_status = 'Returned' THEN
          v_return_date := v_borrow_date + TRUNC(DBMS_RANDOM.VALUE(3,11));
        ELSIF v_return_status = 'Overdue' THEN
          v_return_date := v_due_date + TRUNC(DBMS_RANDOM.VALUE(1,15));
        ELSE
          v_return_date := NULL;
        END IF;

        v_extend_status := choose_extend_status;

        v_borrow_id := 'BB' || LPAD(TO_CHAR(seq_borrow.NEXTVAL), 8, '0');

        INSERT INTO BorrowedBooks(
          borrowId, memberId, copyId,
          borrowDate, dueDate, returnDate,
          returnStatus, extendStatus
        )
        VALUES(
          v_borrow_id, v_member_id, v_copy_id,
          v_borrow_date, v_due_date, v_return_date,
          v_return_status, v_extend_status
        );

        v_cnt := v_cnt + 1;
      END LOOP;
    END IF;

    v_day := v_day + 1;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Inserted rows: '||v_cnt);
  COMMIT;
END;
/

ALTER PROCEDURE gen_borrowed_books_20y COMPILE;

BEGIN
  gen_borrowed_books_20y;
END;
/

SELECT COUNT(*) FROM BorrowedBooks;

-- Distribution by returnStatus
SELECT UPPER(returnStatus) AS status, COUNT(*)
FROM BorrowedBooks
GROUP BY UPPER(returnStatus)
ORDER BY 2 DESC;