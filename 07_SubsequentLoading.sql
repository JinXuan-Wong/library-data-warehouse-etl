SET SERVEROUTPUT ON

/* Bind vars to share IDs across blocks */
VARIABLE v_sales   VARCHAR2(12)
VARIABLE v_borrow  VARCHAR2(10)
VARIABLE v_po      VARCHAR2(5)

/* ======= (optional) helpers already fine to keep ======= */
CREATE OR REPLACE FUNCTION norm_popularity(p IN NUMBER) RETURN NUMBER IS
BEGIN
  RETURN LEAST(GREATEST(NVL(p,0),0),5);
END norm_popularity;
/

CREATE OR REPLACE FUNCTION nonneg_money(p IN NUMBER) RETURN NUMBER IS
BEGIN
  RETURN GREATEST(NVL(p,0),0);
END nonneg_money;
/

/* ======= dimension loaders (your versions) ======= */
CREATE OR REPLACE PROCEDURE Prod_Insert_Book_Dim IS
BEGIN
  INSERT INTO DimBook (
      bookKey, bookId, bookStatus, title, author, genre, price, popularity
  )
  SELECT
      seq_dim_book.NEXTVAL,
      bt.bookId,
      'available',
      UPPER(TRIM(NVL(bt.title,  'UNKNOWN TITLE'))),
      UPPER(TRIM(NVL(bt.author, 'UNKNOWN AUTHOR'))),
      UPPER(TRIM(NVL(bt.genre,  'UNKNOWN GENRE'))),
      ROUND(GREATEST(NVL(bt.salesPrice, 0), 0), 2),
      LEAST(GREATEST(NVL(bt.popularity, 3.0), 1.0), 5.0)
  FROM BookTitles bt
  WHERE NOT EXISTS (SELECT 1 FROM DimBook d WHERE d.bookId = bt.bookId);

  DBMS_OUTPUT.PUT_LINE('Book dimension inserted: '||SQL%ROWCOUNT);
END;
/

CREATE OR REPLACE PROCEDURE Prod_Insert_Member_Dim IS
BEGIN
  INSERT INTO DimMembers (
      memberKey, memberId, memberName, memberAgeRange, memberGender, state, city, MemberDuration,
      effective_date
  )
  SELECT
      seq_dim_member.NEXTVAL,
      m.memberId,
      UPPER(TRIM(NVL(m.memberName, 'UNKNOWN MEMBER'))),
      CASE
        WHEN m.memberAge IS NULL OR m.memberAge = 100 THEN 'UNKNOWN'
        WHEN m.memberAge < 18                     THEN 'BELOW 18'
        WHEN m.memberAge BETWEEN 18 AND 25        THEN '18 TO 25'
        WHEN m.memberAge BETWEEN 26 AND 40        THEN '26 TO 40'
        WHEN m.memberAge BETWEEN 41 AND 55        THEN '41 TO 55'
        WHEN m.memberAge BETWEEN 56 AND 70        THEN '56 TO 70'
        WHEN m.memberAge >= 71                    THEN '71+'
        ELSE 'UNKNOWN'
      END memberAgeRange_,
      CASE
        WHEN LOWER(TRIM(m.memberGender)) = 'female' THEN 'F'
        WHEN LOWER(TRIM(m.memberGender)) = 'male'   THEN 'M'
        ELSE 'U'
      END memberGender_,
      CASE
        WHEN INSTR(NVL(m.memberAddress,''), ',', -1) > 0
          THEN UPPER(TRIM(SUBSTR(m.memberAddress, INSTR(m.memberAddress, ',', -1)+1)))
        ELSE 'UNKNOWN'
      END,
      CASE
        WHEN INSTR(NVL(m.memberAddress,''), ',', -1, 2) > 0
          THEN UPPER(TRIM(SUBSTR(
                 m.memberAddress,
                 INSTR(m.memberAddress, ',', -1, 2)+1,
                 INSTR(m.memberAddress, ',', -1, 1) - INSTR(m.memberAddress, ',', -1, 2) - 1)))
        ELSE 'UNKNOWN'
      END,
      CASE
        WHEN LOWER(NVL(m.memberStatus,'expire')) = 'active'
          THEN ROUND(MONTHS_BETWEEN(SYSDATE, NVL(m.registrationDate, SYSDATE))/12, 1) || ' years'
        ELSE ROUND(MONTHS_BETWEEN(NVL(m.expireDate, SYSDATE), NVL(m.registrationDate, SYSDATE))/12, 1) || ' years (expired)'
      END,
      TRUNC(m.registrationDate)
  FROM Members m
  WHERE NOT EXISTS (SELECT 1 FROM DimMembers d WHERE d.memberId = m.memberId);

  DBMS_OUTPUT.PUT_LINE('Member dimension inserted: '||SQL%ROWCOUNT);
END;
/

CREATE OR REPLACE PROCEDURE Prod_Insert_Supplier_Dim IS
BEGIN
  INSERT INTO DimSuppliers (
      supplierKey, supplierId, supplierName, State, City
  )
  SELECT
      seq_dim_supplier.NEXTVAL,
      s.supplierId,
      UPPER(TRIM(NVL(s.supplierName,'UNKNOWN SUPPLIER'))),
      CASE
        WHEN INSTR(NVL(s.suppliersAddress,''), ',', -1) > 0
          THEN UPPER(TRIM(SUBSTR(s.suppliersAddress, INSTR(s.suppliersAddress, ',', -1)+1)))
        ELSE 'UNKNOWN'
      END AS state_,
      CASE
        WHEN INSTR(NVL(s.suppliersAddress,''), ',', -1, 2) > 0
          THEN UPPER(TRIM(SUBSTR(
                 s.suppliersAddress,
                 INSTR(s.suppliersAddress, ',', -1, 2)+1,
                 INSTR(s.suppliersAddress, ',', -1, 1) - INSTR(s.suppliersAddress, ',', -1, 2) - 1)))
        ELSE 'UNKNOWN'
      END AS City_
  FROM Suppliers s
  WHERE NOT EXISTS (SELECT 1 FROM DimSuppliers d WHERE d.supplierId = s.supplierId);

  DBMS_OUTPUT.PUT_LINE('Supplier dimension inserted: '||SQL%ROWCOUNT);
END;
/

CREATE OR REPLACE PROCEDURE Prod_Insert_Date_Dim(
  p_start IN DATE,
  p_end   IN DATE
) IS
  v_cnt NUMBER := 0;
BEGIN
  FOR d IN (
    SELECT p_start + LEVEL - 1 AS cal_date
    FROM dual
    CONNECT BY p_start + LEVEL - 1 <= p_end
  ) LOOP
    INSERT INTO DimDate (
      dateKey, cal_date, full_desc, day_of_week, day_num_month, day_num_year,
      month_name, cal_month_year, cal_year_month, cal_quarter, cal_year_quarter,
      cal_year, holiday_indicator, weekday_indicator, festive_event, business_day_ind
    )
    SELECT
      seq_dim_date.NEXTVAL,
      d.cal_date,
      TO_CHAR(d.cal_date,'YYYY Month DD'),
      TO_NUMBER(TO_CHAR(d.cal_date,'D')),
      TO_NUMBER(TO_CHAR(d.cal_date,'DD')),
      TO_NUMBER(TO_CHAR(d.cal_date,'DDD')),
      UPPER(TO_CHAR(d.cal_date,'MONTH')),
      TO_NUMBER(TO_CHAR(d.cal_date,'MM')),
      TO_CHAR(d.cal_date,'YYYY')||'-'||TO_CHAR(d.cal_date,'MM'),
      'Q'||TO_CHAR(d.cal_date,'Q'),
      TO_CHAR(d.cal_date,'YYYY')||'-Q'||TO_CHAR(d.cal_date,'Q'),
      TO_NUMBER(TO_CHAR(d.cal_date,'YYYY')),
      'N',
      CASE WHEN TO_CHAR(d.cal_date,'DY','NLS_DATE_LANGUAGE=ENGLISH') IN ('MON','TUE','WED','THU','FRI') THEN 'Y' ELSE 'N' END,
      'Regular Day',
      CASE WHEN TO_CHAR(d.cal_date,'DY','NLS_DATE_LANGUAGE=ENGLISH') IN ('MON','TUE','WED','THU','FRI') THEN 'Y' ELSE 'N' END
    FROM dual
    WHERE NOT EXISTS (SELECT 1 FROM DimDate x WHERE x.cal_date = d.cal_date);

    v_cnt := v_cnt + SQL%ROWCOUNT;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Date dimension inserted: '||v_cnt);
END;
/

/* ======= Seed ONE sale/borrow/purchase and expose IDs to binds ======= */
BEGIN
  -- base rows (idempotent)
  BEGIN
    INSERT INTO BookTitles (bookId, title, author, genre, publicationYear, purchasePrice, salesPrice, popularity)
    VALUES ('B9956','CLEAN DATA ETL','AUTHOR X','FICTION',2023, 0.8*30.00, 30.00, 4.0);
  EXCEPTION WHEN DUP_VAL_ON_INDEX THEN NULL; END;

  BEGIN
    INSERT INTO Members (memberId, memberName, memberAge, memberGender, memberTel, memberEmail, memberAddress, memberStatus, registrationDate, expireDate)
    VALUES ('M9955','DEMO MEMBER',21,'female','019-5559950','m955@example.com','12 DEMO ST, DEMO CITY, DEMO STATE',
            'active', TRUNC(SYSDATE)-30, TRUNC(SYSDATE)+365);
  EXCEPTION WHEN DUP_VAL_ON_INDEX THEN NULL; END;

  BEGIN
    INSERT INTO Suppliers (supplierId, supplierName, contactPerson, supplierTel, suppliersAddress)
    VALUES ('S955','DEMO SUPPLIER','ALAN','012-1112250','88 SUPP RD, SUPP CITY, SUPP STATE');
  EXCEPTION WHEN DUP_VAL_ON_INDEX THEN NULL; END;

  COMMIT;

  -- one copy for the book (keep your style)
  DECLARE v_copy1 VARCHAR2(10); BEGIN
    v_copy1 := LPAD(MOD(seq_copy.NEXTVAL,10000),4,'0');
    BEGIN
      INSERT INTO BookCopies(copyId, bookId, bookStatus) VALUES (v_copy1, 'B9956', 'available');
    EXCEPTION WHEN DUP_VAL_ON_INDEX THEN NULL; END;

    -- Discount row (idempotent)
    BEGIN
      INSERT INTO Discounts(discountId, discountName, discountRate, discountStart, discountEnd)
      VALUES ('D100','ZERO',0, DATE '2025-01-01', DATE '2027-12-31');
    EXCEPTION WHEN DUP_VAL_ON_INDEX THEN NULL; END;

    /* SALE on 2026-02-10 (create ids and expose v_sales) */
    DECLARE
      v_sale_price NUMBER; v_sale_total NUMBER;
      v_pay  VARCHAR2(10); v_rcpt VARCHAR2(10);
      v_order VARCHAR2(9);
      v_sales_local VARCHAR2(12);
    BEGIN
      SELECT salesPrice INTO v_sale_price FROM BookTitles WHERE bookId='B9956';
      v_sale_total := ROUND(v_sale_price*2,2);

      v_pay    := 'P'||LPAD(seq_payment.NEXTVAL,8,'0');
      v_rcpt   := 'R'||LPAD(seq_receipt.NEXTVAL,8,'0');
      v_order  := 'O'||LPAD(seq_sorder.NEXTVAL,8,'0');
      v_sales_local := 'SD'||LPAD(seq_salesdetail.NEXTVAL,8,'0');

      INSERT INTO Payments(paymentId,memberId,paymentDate,payAmount,paymentMethod,paymentType,receiptNo)
      VALUES (v_pay,'M9955', DATE '2026-02-10', v_sale_total, 'Cash','Book Sale', v_rcpt);

      INSERT INTO BookOrders(orderId,paymentId,discountId,memberId,salesDate)
      VALUES (v_order, v_pay, 'D100', 'M9955', DATE '2026-02-10');

      INSERT INTO SalesDetails(salesId,orderId,bookId,quantitySold,discountAmount,totalAmount)
      VALUES (v_sales_local, v_order, 'B9956', 2, 0, v_sale_total);

      :v_sales := v_sales_local;  -- expose bind
      DBMS_OUTPUT.PUT_LINE('SALE seeded: '||v_order||'  salesId='||v_sales_local);
    END;

    /* BORROW on 2026-03-05 (expose v_borrow) */
    DECLARE v_borrow_local VARCHAR2(10);
    BEGIN
      v_borrow_local := 'B'||LPAD(seq_borrow.NEXTVAL,9,'0');
      INSERT INTO BorrowedBooks(borrowId,memberId,copyId,borrowDate,dueDate,returnDate,returnStatus)
      VALUES (v_borrow_local,'M9955',v_copy1, DATE '2026-03-05', DATE '2026-03-20', NULL, 'On loan');

      :v_borrow := v_borrow_local;  -- expose bind
      DBMS_OUTPUT.PUT_LINE('BORROW seeded: '||v_borrow_local);
    END;

    /* PURCHASE on 2026-04-15 (expose v_po) */
    DECLARE
      v_po_local  VARCHAR2(5);
      v_pod       VARCHAR2(5);
      v_po_total  NUMBER;
    BEGIN
      v_po_local := 'P'||LPAD(MOD(seq_order.NEXTVAL,10000),4,'0');
      v_pod      := 'D'||LPAD(MOD(seq_detail.NEXTVAL,10000),4,'0');

      INSERT INTO PurchaseOrders(purchaseOrderId,supplierId,purchaseDate,totalAmount,orderStatus)
      VALUES (v_po_local,'S955', DATE '2026-04-15', 0, 'Received');

      INSERT INTO PurchaseDetails(detailId,purchaseOrderId,bookId,quantity)
      VALUES (v_pod, v_po_local, 'B9956', 2);

      SELECT SUM(bt.purchasePrice * pd.quantity)
        INTO v_po_total
        FROM PurchaseDetails pd
        JOIN BookTitles bt ON bt.bookId = pd.bookId
       WHERE pd.purchaseOrderId = v_po_local;

      UPDATE PurchaseOrders
         SET totalAmount = ROUND(NVL(v_po_total,0),2)
       WHERE purchaseOrderId = v_po_local;

      :v_po := v_po_local;  -- expose bind
      DBMS_OUTPUT.PUT_LINE('PURCHASE seeded: '||v_po_local||' total='||TO_CHAR(NVL(v_po_total,0),'FM9990.00'));
    END;

  END; -- v_copy1 block

  COMMIT;
END;
/

/* Ensure needed date range & dims exist */
BEGIN
  Prod_Insert_Date_Dim(DATE '2026-01-01', DATE '2026-06-30');
  Prod_Insert_Book_Dim;
  Prod_Insert_Member_Dim;
  Prod_Insert_Supplier_Dim;
END;
/

/* ======= Load ONLY the just-seeded rows (use binds) ======= */
DECLARE
  v_sales_ins     NUMBER := 0;
  v_borrow_ins    NUMBER := 0;
  v_purchase_ins  NUMBER := 0;
BEGIN
  /* SALES only this salesId */
  MERGE INTO FactSales t
  USING (
    SELECT 
      dm.memberKey,
      db.bookKey,
      dd.dateKey,
      sd.salesId           AS sales_id,
      NVL(bt.salesPrice,0) AS salesPrice,
      NVL(sd.discountAmount,0) AS discount,
      NVL(d.discountName,'No Discount') AS discount_desc,
      ROUND(GREATEST(NVL(sd.totalAmount, NVL(bt.salesPrice,0)*NVL(sd.quantitySold,0)),0),2) AS line_total,
      GREATEST(NVL(sd.quantitySold,0),0) AS quantity
    FROM BookOrders bo
    JOIN SalesDetails sd  ON bo.orderId = sd.orderId
    JOIN BookTitles bt    ON bt.bookId  = sd.bookId
    LEFT JOIN Discounts d ON d.discountId = bo.discountId
    JOIN DimDate   dd     ON TRUNC(bo.salesDate) = dd.cal_date
    JOIN DimMembers dm    ON dm.memberId = bo.memberId
    JOIN DimBook    db    ON db.bookId   = sd.bookId
    WHERE sd.salesId = :v_sales
  ) s
  ON (t.sales_id = s.sales_id)
  WHEN NOT MATCHED THEN
    INSERT (memberKey, bookKey, dateKey, sales_id, salesPrice, discount, discount_desc, line_total, quantity)
    VALUES (s.memberKey, s.bookKey, s.dateKey, s.sales_id, s.salesPrice, s.discount, s.discount_desc, s.line_total, s.quantity);

  v_sales_ins := SQL%ROWCOUNT;

  /* BORROW only this borrowId */
  INSERT INTO FactBorrowing
    (dateKey, memberKey, bookKey, overdueDays, borrowDuration, returnRate)
  SELECT
    x.dateKey,
    x.memberKey,
    x.bookKey,
    MAX(x.overdueDays),
    MAX(x.borrowDuration),
    ROUND(AVG(x.returnRate),2)
  FROM (
    SELECT
      dd.dateKey,
      dm.memberKey,
      db.bookKey,
      NVL(CASE
            WHEN bb.returnDate IS NULL AND bb.dueDate < SYSDATE THEN TRUNC(SYSDATE - bb.dueDate)
            WHEN bb.returnDate > bb.dueDate                      THEN TRUNC(bb.returnDate - bb.dueDate)
            ELSE 0
          END, 0) AS overdueDays,
      NVL(CASE
            WHEN bb.returnDate IS NOT NULL THEN TRUNC(bb.returnDate - bb.borrowDate)
            ELSE TRUNC(SYSDATE - bb.borrowDate)
          END, 0) AS borrowDuration,
      CASE UPPER(NVL(bb.returnStatus,'ON LOAN'))
        WHEN 'RETURNED' THEN 100
        WHEN 'LOST'     THEN 0
        ELSE 50
      END AS returnRate
    FROM BorrowedBooks bb
    JOIN BookCopies bc ON bc.copyId = bb.copyId
    JOIN DimDate dd    ON TRUNC(bb.borrowDate) = dd.cal_date
    JOIN DimMembers dm ON dm.memberId = bb.memberId
    JOIN DimBook db    ON db.bookId  = bc.bookId
    WHERE bb.borrowId = :v_borrow
  ) x
  WHERE NOT EXISTS (
    SELECT 1
    FROM FactBorrowing fb
    WHERE fb.dateKey   = x.dateKey
      AND fb.memberKey = x.memberKey
      AND fb.bookKey   = x.bookKey
  )
  GROUP BY x.dateKey, x.memberKey, x.bookKey;

  v_borrow_ins := SQL%ROWCOUNT;

  /* PURCHASE only this purchaseOrderId */
  MERGE INTO FactPurchase t
  USING (
    SELECT
      dd.dateKey,
      db.bookKey,
      ds.supplierKey,
      SUM(NVL(pd.quantity,0))                           AS quantity,
      ROUND(NVL(po.totalAmount,0),2)                    AS totalAmount,
      CASE WHEN po.orderStatus='Received' THEN 'Y' ELSE 'N' END AS flag_ind,
      po.purchaseOrderId
    FROM PurchaseOrders po
    JOIN PurchaseDetails pd ON pd.purchaseOrderId = po.purchaseOrderId
    JOIN DimDate dd         ON TRUNC(po.purchaseDate) = dd.cal_date
    JOIN DimBook db         ON db.bookId  = pd.bookId
    JOIN DimSuppliers ds    ON ds.supplierId = po.supplierId
    WHERE po.purchaseOrderId = :v_po
    GROUP BY dd.dateKey, db.bookKey, ds.supplierKey, po.totalAmount, po.orderStatus, po.purchaseOrderId
  ) s
  ON (t.purchaseOrderId = s.purchaseOrderId
      AND t.bookKey     = s.bookKey
      AND t.supplierKey = s.supplierKey
      AND t.dateKey     = s.dateKey)
  WHEN NOT MATCHED THEN
    INSERT (dateKey, bookKey, supplierKey, quantity, totalAmount, flag_ind, purchaseOrderId)
    VALUES (s.dateKey, s.bookKey, s.supplierKey, s.quantity, s.totalAmount, s.flag_ind, s.purchaseOrderId);

  v_purchase_ins := SQL%ROWCOUNT;

  COMMIT;

  DBMS_OUTPUT.PUT_LINE('=== DW new rows (this run only) ===');
  DBMS_OUTPUT.PUT_LINE('FactSales: '||v_sales_ins);
  DBMS_OUTPUT.PUT_LINE('FactBorrowing: '||v_borrow_ins);
  DBMS_OUTPUT.PUT_LINE('FactPurchase: '||v_purchase_ins);
END;
/

-- (Optional) show the IDs we just used
PRINT v_sales
PRINT v_borrow
PRINT v_po
