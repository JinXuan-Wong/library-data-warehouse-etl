  -- dimension table
CREATE OR REPLACE TRIGGER trg_dimbook_unavail_to_copies
AFTER INSERT OR UPDATE OF bookStatus ON DimBook
FOR EACH ROW
BEGIN
  -- Fire only when the new status is UNAVAILABLE, and we weren't already UNAVAILABLE
  IF UPPER(:NEW.bookStatus) = 'UNAVAILABLE'
     AND (INSERTING OR UPPER(NVL(:OLD.bookStatus, '#')) <> 'UNAVAILABLE') THEN

    UPDATE BookCopies
       SET bookStatus = 'unavailable'
     WHERE bookId = :NEW.bookId
       AND UPPER(NVL(bookStatus, '#')) <> 'UNAVAILABLE'; -- avoid useless writes
  END IF;
END;
/


-- Drop & recreate
DROP PROCEDURE Prod_Update_DimBook;

CREATE OR REPLACE PROCEDURE Prod_Update_DimBook (
  p_book_id        IN DimBook.bookId%TYPE,
  p_new_price      IN DimBook.price%TYPE,
  p_new_status     IN DimBook.bookStatus%TYPE,
  p_effective_date IN DATE DEFAULT TRUNC(SYSDATE)
) IS
  ----------------------------------------------------------------
  -- Get the current ACTIVE ('Y') SCD row for this book (if any)
  ----------------------------------------------------------------
  CURSOR cur_curr IS
    SELECT *
    FROM DimBook
    WHERE bookId = p_book_id
      AND curr_ind = 'Y';

  v_curr_row cur_curr%ROWTYPE;
  v_has_curr BOOLEAN := FALSE;
BEGIN
  -- open/fetch so we can use %FOUND/%NOTFOUND like in your template
  OPEN cur_curr;
  FETCH cur_curr INTO v_curr_row;
  v_has_curr := cur_curr%FOUND;
  CLOSE cur_curr;

  IF v_has_curr THEN
    ----------------------------------------------------------------
    -- Compare tracked attributes (price, bookStatus)
    ----------------------------------------------------------------
    IF NVL(v_curr_row.price, -1e9) <> NVL(p_new_price, -1e9)
       OR UPPER(NVL(v_curr_row.bookStatus,'~')) <> UPPER(NVL(p_new_status,'~')) THEN

      -- Step 1: expire old version (avoid overlap by ending on day before)
      UPDATE DimBook
         SET expiration_date = LEAST(TRUNC(p_effective_date) - 1, expiration_date),
             curr_ind        = 'N'
       WHERE bookKey = v_curr_row.bookKey
         AND expiration_date = DATE '9999-12-31';

      -- Step 2: insert new ACTIVE version
      INSERT INTO DimBook (
        bookKey, bookId, bookStatus, title, author, genre, price, popularity,
        effective_date, expiration_date, curr_ind
      )
      VALUES (
        seq_dim_book.NEXTVAL,
        v_curr_row.bookId,
        UPPER(TRIM(p_new_status)),
        v_curr_row.title,
        v_curr_row.author,
        v_curr_row.genre,
        p_new_price,
        v_curr_row.popularity,
        TRUNC(p_effective_date),
        DATE '9999-12-31',
        'Y'
      );
    END IF;

  ELSE
    ----------------------------------------------------------------
    -- No active row exists yet → insert the first SCD row
    -- Pull static attributes from BookTitles as source-of-truth
    ----------------------------------------------------------------
    INSERT INTO DimBook (
      bookKey, bookId, bookStatus, title, author, genre, price, popularity,
      effective_date, expiration_date, curr_ind
    )
    SELECT
      seq_dim_book.NEXTVAL,
      bt.bookId,
      UPPER(TRIM(p_new_status)),
      UPPER(TRIM(bt.title)),
      UPPER(TRIM(bt.author)),
      UPPER(TRIM(bt.genre)),
      p_new_price,
      COALESCE(bt.popularity, 3.0),
      TRUNC(p_effective_date),
      DATE '9999-12-31',
      'Y'
    FROM BookTitles bt
    WHERE bt.bookId = p_book_id;
  END IF;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('DimBook SCD2 processed: '||p_book_id);

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Error in Prod_Update_DimBook: '||SQLERRM);
    RAISE;
END Prod_Update_DimBook;
/

BEGIN
  Prod_Update_DimBook(
    p_book_id        => 'B0011',
    p_new_price      => 59.90,
    p_new_status     => 'available',
    p_effective_date => SYSDATE
  );
END;
/

-- Recreate

select * from DIMBOOK where bookId ='B0011';