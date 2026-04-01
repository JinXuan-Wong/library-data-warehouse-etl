SET SERVEROUTPUT ON

CREATE OR REPLACE PROCEDURE gen_book_copies(p_target_total NUMBER := 45000) IS
  v_have   NUMBER;
  v_need   NUMBER;
  v_book   BookTitles.bookId%TYPE;
  v_base   NUMBER; -- next numeric suffix to use (from current MAX)
  v_idnum  NUMBER;
  v_copyid BOOKCOPIES.copyId%TYPE;
BEGIN
  -- sanity: format is Cnnn so 999 max
  IF p_target_total > 99999 THEN
    RAISE_APPLICATION_ERROR(-20021, 'copyId format Cnnn supports max 99999 rows. Reduce target_total.');
  END IF;

  -- how many exist now
  SELECT COUNT(*) INTO v_have FROM BookCopies;
  v_need := GREATEST(p_target_total - v_have, 0);

  IF v_need = 0 THEN
    DBMS_OUTPUT.put_line('BookCopies already >= target ('||v_have||'). Nothing to insert.');
    RETURN;
  END IF;

  -- find next suffix from current max, e.g. C123 -> base = 124
  SELECT NVL(MAX(TO_NUMBER(SUBSTR(copyId,2))), 0) + 1
  INTO   v_base
  FROM   BookCopies;

  FOR i IN 0 .. v_need-1 LOOP
    -- random existing bookId
    SELECT bookId INTO v_book
    FROM (SELECT bookId FROM BookTitles ORDER BY DBMS_RANDOM.VALUE)
    WHERE ROWNUM = 1;

    v_idnum  := v_base + i;                               -- e.g. 124,125,...
    v_copyid := 'C' || LPAD(v_idnum, 5, '0');             -- e.g. C124

    -- safety: should never exceed 999 due to earlier check
    IF v_idnum > 99999 THEN
      RAISE_APPLICATION_ERROR(-20022, 'Would exceed C99999. Aborting.');
    END IF;

    INSERT INTO BookCopies(copyId, bookId, bookStatus)
    VALUES (v_copyid, v_book, 'available');
  END LOOP;

  DBMS_OUTPUT.put_line('Inserted '||v_need||' BookCopies. Total is now '||(v_have+v_need)||'.');
  COMMIT;
END;
/

BEGIN
  gen_book_copies(45000);
  DBMS_OUTPUT.PUT_LINE('Done.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.format_error_backtrace);
END;
/


-- Validate Checks (Optional)
SELECT COUNT(*) FROM BookCopies;
SELECT MIN(copyId), MAX(copyId) FROM BookCopies;

SELECT bookStatus FROM BOOKCOPIES;
