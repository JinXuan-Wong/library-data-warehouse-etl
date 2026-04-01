-- SalesDetails and BookOrders

CREATE OR REPLACE PROCEDURE gen_sales_with_payments (
    p_start_date DATE,
    p_end_date   DATE,
    p_min_sales_per_day NUMBER := 5,
    p_max_sales_per_day NUMBER := 10
) IS
    v_books SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();

    v_member    Members.memberId%TYPE;
    v_disc      Discounts.discountId%TYPE;
    v_disc_pct  Discounts.discountRate%TYPE;
    v_pay_id    Payments.paymentId%TYPE;
    v_rcpt      Payments.receiptNo%TYPE;
    v_method    Payments.paymentMethod%TYPE;
    v_order_id  BookOrders.orderId%TYPE;
    v_book_id   BookTitles.bookId%TYPE;
    v_price     BookTitles.salesPrice%TYPE;
    v_qty       NUMBER;
    v_amount    NUMBER;
    v_index     PLS_INTEGER;
    v_days      NUMBER;
    v_sales_cnt NUMBER;
    v_seq_val   NUMBER;
    v_sales_id  SalesDetails.salesId%TYPE;
    v_dummy     NUMBER;
    v_max_id    NUMBER;
    v_book_count NUMBER;
    v_total_amount NUMBER;
    v_total_discount NUMBER;

    -- Pick discount if available in range
    FUNCTION pick_discount(p_sales_date DATE, p_disc_id OUT VARCHAR2) RETURN NUMBER IS
        v_disc_num NUMBER;
        v_disc_rec Discounts%ROWTYPE;
    BEGIN
        BEGIN
            SELECT * INTO v_disc_rec
            FROM (
                SELECT * 
                FROM Discounts
                WHERE p_sales_date BETWEEN discountStart AND discountEnd
                ORDER BY DBMS_RANDOM.VALUE
            )
            WHERE ROWNUM = 1;

            p_disc_id := v_disc_rec.discountId;
            RETURN v_disc_rec.discountRate;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_disc_num := TRUNC(DBMS_RANDOM.VALUE(101, 134));
                p_disc_id := 'D' || LPAD(v_disc_num, 3, '0');
                RETURN 0;
        END;
    END;

BEGIN
    -- Load books
    FOR r IN (SELECT bookId FROM BookTitles) LOOP
        v_books.EXTEND;
        v_books(v_books.LAST) := r.bookId;
    END LOOP;

    IF v_books.COUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'No books found in BookTitles table');
    END IF;

    -- Days to generate
    v_days := TRUNC(p_end_date) - TRUNC(p_start_date) + 1;

    FOR day_counter IN 0..v_days-1 LOOP
        v_sales_cnt := TRUNC(DBMS_RANDOM.VALUE(p_min_sales_per_day, p_max_sales_per_day + 1));

        FOR i IN 1..v_sales_cnt LOOP
            -- Generate unique order ID
            LOOP
                SELECT seq_sorder.NEXTVAL INTO v_seq_val FROM dual;
                v_order_id := 'O' || LPAD(seq_sorder.NEXTVAL, 8, '0');  -- column set to 9 (O + 8 digits)

                BEGIN
                    SELECT 1 INTO v_dummy FROM BookOrders WHERE orderId = v_order_id AND ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        EXIT;
                END;
            END LOOP;

            -- Pick random member
            BEGIN
                SELECT memberId
                INTO   v_member
                FROM (
                    SELECT m.memberId
                    FROM   Members m
                    WHERE  TRUNC(p_start_date + day_counter)
                        BETWEEN TRUNC(m.registrationDate) AND TRUNC(m.expireDate)
                    ORDER  BY DBMS_RANDOM.VALUE
                    )
                    WHERE  ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                     -- No member valid on this date; skip this one sale and continue
                    CONTINUE;
            END;

            -- Payment ID
            SELECT seq_payment.NEXTVAL INTO v_seq_val FROM dual;
            v_pay_id := 'P' || LPAD(seq_payment.NEXTVAL, 8, '0');   -- Payments.paymentId must fit 9

            -- Receipt number
            SELECT seq_receipt.NEXTVAL INTO v_seq_val FROM dual;
            v_rcpt   := 'R' || LPAD(seq_receipt.NEXTVAL, 8, '0');   -- receiptNo must fit 9
            -- Payment method
            v_method := CASE TRUNC(DBMS_RANDOM.VALUE(0,3))
                WHEN 0 THEN 'Cash'
                WHEN 1 THEN 'Tng'
                ELSE 'Duitnow'
            END;

            -- Pick discount for the whole order
            v_disc_pct := pick_discount(p_start_date + day_counter, v_disc);

            -- Random number of books for the order
            v_book_count := TRUNC(DBMS_RANDOM.VALUE(1, 7));
            v_total_amount := 0;
            v_total_discount := 0;

            -- Calculate totals first
            FOR book_num IN 1..v_book_count LOOP
                v_index := TRUNC(DBMS_RANDOM.VALUE(1, v_books.COUNT + 0.999999));
                v_book_id := v_books(v_index);
                v_qty := TRUNC(DBMS_RANDOM.VALUE(1, 5));

                BEGIN
                    SELECT salesPrice INTO v_price FROM BookTitles WHERE bookId = v_book_id;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_price := 10;
                END;

                v_amount := v_price * v_qty;
                v_total_amount := v_total_amount + v_amount;
                v_total_discount := v_total_discount + (v_amount * v_disc_pct / 100);
            END LOOP;

            -- 1️⃣ Insert into Payments
            INSERT INTO Payments(
                paymentId, memberId, paymentDate, payAmount,
                paymentMethod, paymentType, receiptNo
            ) VALUES (
                v_pay_id, v_member, p_start_date + day_counter,
                v_total_amount - v_total_discount,
                v_method, 'Book Sale', v_rcpt
            );

            -- 2️⃣ Insert into BookOrders (parent)
            INSERT INTO BookOrders(
                orderId, paymentId, discountId, memberId, salesDate
            ) VALUES (
                v_order_id, v_pay_id, v_disc, v_member, p_start_date + day_counter
            );

            -- 3️⃣ Insert into SalesDetails (child)
            FOR book_num IN 1..v_book_count LOOP
                v_index := TRUNC(DBMS_RANDOM.VALUE(1, v_books.COUNT + 0.999999));
                v_book_id := v_books(v_index);
                v_qty := TRUNC(DBMS_RANDOM.VALUE(1, 5));

                BEGIN
                    SELECT salesPrice INTO v_price FROM BookTitles WHERE bookId = v_book_id;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_price := 10;
                END;

                v_amount := v_price * v_qty;

                SELECT seq_salesdetail.NEXTVAL INTO v_seq_val FROM dual;
                v_sales_id := 'SD' || LPAD(v_seq_val, 8, '0');  -- << no MOD

                BEGIN
                INSERT INTO SalesDetails(
                    salesId, orderId, bookId, quantitySold, discountAmount, totalAmount
                ) VALUES (
                    v_sales_id, v_order_id, v_book_id, v_qty,
                    v_amount * v_disc_pct / 100,
                    v_amount - (v_amount * v_disc_pct / 100)
                );
                EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                    -- extremely rare, but just in case:
                    SELECT seq_salesdetail.NEXTVAL INTO v_seq_val FROM dual;
                    v_sales_id := 'SD' || LPAD(v_seq_val, 8, '0');
                    INSERT INTO SalesDetails(
                    salesId, orderId, bookId, quantitySold, discountAmount, totalAmount
                    ) VALUES (
                    v_sales_id, v_order_id, v_book_id, v_qty,
                    v_amount * v_disc_pct / 100,
                    v_amount - (v_amount * v_disc_pct / 100)
                    );
                END;
            END LOOP;
        END LOOP;
    END LOOP;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Procedure error: '||SQLERRM);
        RAISE;
END;
/


SHOW ERRORS PROCEDURE gen_sales_with_payments;


BEGIN
  gen_sales_with_payments(
    p_start_date => DATE '2004-07-01',
    p_end_date => DATE '2024-06-30',
    p_min_sales_per_day => 5,
    p_max_sales_per_day => 10
  );
END;
/

select count(*) from BookOrders;
select count(*) from SalesDetails;