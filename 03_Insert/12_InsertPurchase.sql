-- Purchase Details and Purchase Orders
------------------------------------------------------------
-- 3) Generator: Purchases (20 years)
--    - orderId = 'P' + 4 digits (fits VARCHAR2(5))
--    - detailId = 'D' + 4 digits (fits VARCHAR2(5))
--    - Ensures PurchaseOrders.totalAmount equals SUM(details)
------------------------------------------------------------

ALTER TRIGGER trg_check_purchase_total DISABLE;
ALTER TRIGGER trg_guard_po_total     DISABLE;

CREATE OR REPLACE FUNCTION rnd_date(p_lo DATE, p_hi DATE) RETURN DATE IS
BEGIN
  RETURN p_lo + TRUNC(DBMS_RANDOM.VALUE(0, (p_hi - p_lo) + 1));
END;
/

CREATE OR REPLACE FUNCTION fmt_id(p_prefix VARCHAR2, p_num NUMBER, p_width PLS_INTEGER) RETURN VARCHAR2 IS
BEGIN
  RETURN p_prefix || LPAD(p_num, p_width, '0');
END;
/

DECLARE
  e_exists EXCEPTION; PRAGMA EXCEPTION_INIT(e_exists, -955);
BEGIN
  BEGIN EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_order START WITH 1 INCREMENT BY 1 NOCACHE'; EXCEPTION WHEN e_exists THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_detail START WITH 1 INCREMENT BY 1 NOCACHE'; EXCEPTION WHEN e_exists THEN NULL; END;
END;
/

CREATE OR REPLACE PROCEDURE gen_purchases(
  p_years             NUMBER:= 20,
  p_avg_orders_per_mo NUMBER:= 6,
  p_min_lines         NUMBER:= 7,
  p_max_lines         NUMBER:= 10,
  p_min_qty           NUMBER:= 5,
  p_max_qty           NUMBER:= 40
) IS
  v_start       DATE := ADD_MONTHS(TRUNC(SYSDATE, 'YYYY'), -12*p_years);
  v_months      NUMBER:= p_years*12;
  v_supplier    Suppliers.supplierId%TYPE;
  v_orderId     PurchaseOrders.purchaseOrderId%TYPE;
  v_order_dt    DATE;
  v_lines       NUMBER;
  v_book        BookTitles.bookId%TYPE;
  v_qty         NUMBER;
  v_price       NUMBER(8,2);
  v_total       NUMBER(12,2);
  v_has_sup     NUMBER;
  v_has_books   NUMBER;
BEGIN
  -- sanity checks
  SELECT COUNT(*) INTO v_has_sup   FROM Suppliers;
  SELECT COUNT(*) INTO v_has_books FROM BookTitles;
  IF v_has_sup = 0 THEN
    RAISE_APPLICATION_ERROR(-20030, 'No suppliers found. Insert suppliers first.');
  END IF;
  IF v_has_books = 0 THEN
    RAISE_APPLICATION_ERROR(-20031, 'No book titles found.');
  END IF;

  FOR m IN 0..(v_months-1) LOOP
    DECLARE
      v_orders INTEGER := GREATEST(0, ROUND(p_avg_orders_per_mo + DBMS_RANDOM.NORMAL * 3));
      v_first  DATE := ADD_MONTHS(TRUNC(v_start, 'MM'), m);
      v_last   DATE := LAST_DAY(v_first);
    BEGIN
      FOR o IN 1..v_orders LOOP
        -- random supplier
        SELECT supplierId INTO v_supplier
          FROM (SELECT supplierId FROM Suppliers ORDER BY DBMS_RANDOM.VALUE)
         WHERE ROWNUM = 1;

        v_order_dt := rnd_date(v_first, v_last);

        v_orderId := fmt_id('P', seq_order.NEXTVAL, 4); -- 'P0001'
        INSERT INTO PurchaseOrders(purchaseOrderId, supplierId, purchaseDate, totalAmount, orderStatus)
        VALUES (v_orderId, v_supplier, v_order_dt, 0, 'Received');

        v_lines := TRUNC(DBMS_RANDOM.VALUE(p_min_lines, p_max_lines + 1));
        v_total := 0;

        FOR d IN 1..v_lines LOOP
          -- random book
          SELECT bookId, purchasePrice INTO v_book, v_price
            FROM (SELECT bookId, purchasePrice FROM BookTitles ORDER BY DBMS_RANDOM.VALUE)
           WHERE ROWNUM = 1;

          v_qty := TRUNC(DBMS_RANDOM.VALUE(p_min_qty, p_max_qty + 1));

          INSERT INTO PurchaseDetails(detailId, purchaseOrderId, bookId, quantity)
          VALUES (fmt_id('D', seq_detail.NEXTVAL, 5), v_orderId, v_book, v_qty);

          v_total := v_total + (v_price * v_qty);
        END LOOP;

        UPDATE PurchaseOrders
           SET totalAmount = ROUND(v_total, 2)
         WHERE purchaseOrderId = v_orderId;
      END LOOP;
    END;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Purchases generated for '||p_years||' years.');
END;
/
SHOW ERRORS

BEGIN
  gen_purchases(p_years => 20, p_avg_orders_per_mo => 2);
END;
/

ALTER TRIGGER trg_check_purchase_total ENABLE;
ALTER TRIGGER trg_guard_po_total     ENABLE;

-- 5) Sanity checks
SELECT COUNT(*) orders_cnt  FROM PurchaseOrders;
SELECT COUNT(*) details_cnt FROM PurchaseDetails;

COMMIT;
