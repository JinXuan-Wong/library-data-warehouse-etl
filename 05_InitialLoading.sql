SET SERVEROUTPUT ON
SET DEFINE OFF
SET SQLBLANKLINES ON

-- =====================================
-- Clean up existing data first
-- =====================================
BEGIN
  -- Disable constraints
  FOR c IN (SELECT constraint_name, table_name FROM user_constraints WHERE constraint_type = 'R') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER TABLE ' || c.table_name || ' DISABLE CONSTRAINT ' || c.constraint_name;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error disabling constraint ' || c.constraint_name || ': ' || SQLERRM);
    END;
  END LOOP;

  -- Clear all fact and dimension tables
  EXECUTE IMMEDIATE 'DELETE FROM FactSales';
  EXECUTE IMMEDIATE 'DELETE FROM FactBorrowing';
  EXECUTE IMMEDIATE 'DELETE FROM FactPurchase';
  EXECUTE IMMEDIATE 'DELETE FROM DimBook';
  EXECUTE IMMEDIATE 'DELETE FROM DimMembers';
  EXECUTE IMMEDIATE 'DELETE FROM DimSuppliers';
  EXECUTE IMMEDIATE 'DELETE FROM DimDate';
  
  DBMS_OUTPUT.PUT_LINE('All existing data cleared from dimension and fact tables');
  
  -- Re-enable constraints
  FOR c IN (SELECT constraint_name, table_name FROM user_constraints WHERE constraint_type = 'R') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER TABLE ' || c.table_name || ' ENABLE CONSTRAINT ' || c.constraint_name;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error enabling constraint ' || c.constraint_name || ': ' || SQLERRM);
    END;
  END LOOP;
  
  COMMIT;
END;
/

-- =====================================
-- Sequences (DW surrogate key) - Drop and recreate
-- =====================================
BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_dim_date';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_dim_book';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_dim_member';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_dim_supplier';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE SEQUENCE seq_dim_date      START WITH 100001 INCREMENT BY 1;
CREATE SEQUENCE seq_dim_book      START WITH 100001 INCREMENT BY 1;
CREATE SEQUENCE seq_dim_member    START WITH 100001 INCREMENT BY 1;
CREATE SEQUENCE seq_dim_supplier  START WITH 100001 INCREMENT BY 1;

-- =====================================
-- Holiday List (Complete Malaysia Holidays 2000–2025)
-- =====================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE HOLIDAY_LIST PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE HOLIDAY_LIST (
  CAL_DATE      DATE PRIMARY KEY,
  FESTIVE_EVENT VARCHAR2(50),
  HOLIDAY_TYPE  VARCHAR2(20) DEFAULT 'National'
);

-- Function to calculate moving holidays (Hari Raya, Chinese New Year, etc.)
CREATE OR REPLACE FUNCTION get_moving_holiday(year_num NUMBER, holiday_type VARCHAR2) RETURN DATE
IS
  v_date DATE;
BEGIN
  CASE holiday_type
    WHEN 'HARI_RAYA_PUASA' THEN
      v_date := TO_DATE('01-01-' || year_num, 'DD-MM-YYYY') + 354 + (year_num - 2000) * 11;
    WHEN 'HARI_RAYA_HAJI' THEN
      v_date := TO_DATE('01-01-' || year_num, 'DD-MM-YYYY') + 280 + (year_num - 2000) * 11;
    WHEN 'CHINESE_NEW_YEAR' THEN
      v_date := TO_DATE('21-01-' || year_num, 'DD-MM-YYYY') + MOD((year_num - 1900) * 5 + 4, 60) * 0.48;
    WHEN 'DEEPAVALI' THEN
      v_date := TO_DATE('15-10-' || year_num, 'DD-MM-YYYY') + MOD(year_num, 19) * 11;
    WHEN 'WESAK' THEN
      v_date := TO_DATE('01-05-' || year_num, 'DD-MM-YYYY') + MOD(year_num, 19) * 11;
    ELSE
      v_date := NULL;
  END CASE;
  
  RETURN TRUNC(v_date);
END;
/

-- Fixed-date National Holidays
BEGIN
  -- New Year's Day
  FOR i IN 0..25 LOOP
    INSERT INTO HOLIDAY_LIST (CAL_DATE, FESTIVE_EVENT, HOLIDAY_TYPE)
    VALUES (TO_DATE('01-01-'||(2000+i),'DD-MM-YYYY'), 'New Year''s Day', 'National');
  END LOOP;

  -- Federal Territory Day
  FOR i IN 0..25 LOOP
    INSERT INTO HOLIDAY_LIST (CAL_DATE, FESTIVE_EVENT, HOLIDAY_TYPE)
    VALUES (TO_DATE('01-02-'||(2000+i),'DD-MM-YYYY'), 'Federal Territory Day', 'Regional');
  END LOOP;

  -- Labour Day
  FOR i IN 0..25 LOOP
    INSERT INTO HOLIDAY_LIST (CAL_DATE, FESTIVE_EVENT, HOLIDAY_TYPE)
    VALUES (TO_DATE('01-05-'||(2000+i),'DD-MM-YYYY'), 'Labour Day', 'National');
  END LOOP;

  -- National Day
  FOR i IN 0..25 LOOP
    INSERT INTO HOLIDAY_LIST (CAL_DATE, FESTIVE_EVENT, HOLIDAY_TYPE)
    VALUES (TO_DATE('31-08-'||(2000+i),'DD-MM-YYYY'), 'National Day', 'National');
  END LOOP;

  -- Malaysia Day (from 2010)
  FOR i IN 10..25 LOOP
    INSERT INTO HOLIDAY_LIST (CAL_DATE, FESTIVE_EVENT, HOLIDAY_TYPE)
    VALUES (TO_DATE('16-09-'||(2000+i),'DD-MM-YYYY'), 'Malaysia Day', 'National');
  END LOOP;

  -- Christmas
  FOR i IN 0..25 LOOP
    INSERT INTO HOLIDAY_LIST (CAL_DATE, FESTIVE_EVENT, HOLIDAY_TYPE)
    VALUES (TO_DATE('25-12-'||(2000+i),'DD-MM-YYYY'), 'Christmas', 'National');
  END LOOP;

  COMMIT;
END;
/

-- =====================================
-- Date Dimension with Data Standardization
-- =====================================
DECLARE
  STARTDATE DATE := TO_DATE('01/01/2000','DD/MM/YYYY');
  ENDDATE   DATE := TO_DATE('31/12/2025','DD/MM/YYYY');
  counter NUMBER := 0;
BEGIN
  FOR curr_date IN (
    SELECT STARTDATE + (LEVEL - 1) as cal_date
    FROM dual
    CONNECT BY STARTDATE + (LEVEL - 1) <= ENDDATE
  ) LOOP
    counter := counter + 1;

    INSERT INTO DimDate(
      dateKey, cal_date, full_desc, day_of_week, day_num_month, day_num_year,
      month_name, cal_month_year, cal_year_month, cal_quarter, cal_year_quarter,
      cal_year, holiday_indicator, weekday_indicator, festive_event, business_day_ind
    )
    SELECT 
      seq_dim_date.NEXTVAL,
      curr_date.cal_date,
      TO_CHAR(curr_date.cal_date,'YYYY Month DD'),
      TO_NUMBER(TO_CHAR(curr_date.cal_date,'D')),
      TO_NUMBER(TO_CHAR(curr_date.cal_date,'DD')),
      TO_NUMBER(TO_CHAR(curr_date.cal_date,'DDD')),
      UPPER(TO_CHAR(curr_date.cal_date,'MONTH')), -- Standardization: uppercase
      TO_NUMBER(TO_CHAR(curr_date.cal_date,'MM')), 
      TO_CHAR(curr_date.cal_date,'YYYY') || '-' || TO_CHAR(curr_date.cal_date,'MM'),
      'Q' || TO_CHAR(curr_date.cal_date,'Q'), 
      TO_CHAR(curr_date.cal_date,'YYYY') || '-Q' || TO_CHAR(curr_date.cal_date,'Q'),
      TO_NUMBER(TO_CHAR(curr_date.cal_date,'YYYY')), 
      COALESCE((SELECT 'Y' FROM HOLIDAY_LIST h WHERE h.CAL_DATE = curr_date.cal_date), 'N'),
      CASE WHEN TO_NUMBER(TO_CHAR(curr_date.cal_date,'D')) BETWEEN 2 AND 6 THEN 'Y' ELSE 'N' END,
      COALESCE((SELECT h.FESTIVE_EVENT FROM HOLIDAY_LIST h WHERE h.CAL_DATE = curr_date.cal_date), 'Regular Day'),
      CASE 
        WHEN TO_NUMBER(TO_CHAR(curr_date.cal_date,'D')) BETWEEN 2 AND 6 
        AND NOT EXISTS (SELECT 1 FROM HOLIDAY_LIST h WHERE h.CAL_DATE = curr_date.cal_date) 
        THEN 'Y' 
        ELSE 'N' 
      END
    FROM DUAL;

  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Date dimension rows inserted: ' || counter);
  COMMIT;
END;
/


-- ============================================
-- 2. DIMBOOK LOADING (using sequence)
-- ============================================
INSERT INTO DimBook ( 
  bookKey, bookId,title, author, genre, price, popularity 
  ) 
  SELECT
   seq_dim_book.NEXTVAL,
   bookId,
  UPPER(TRIM(title)), 
  UPPER(TRIM(author)), 
  UPPER(TRIM(genre)), 
  ROUND(GREATEST(COALESCE(salesPrice, 0), 0), 2), 
  COALESCE(popularity, 3.0) FROM BookTitles; 
COMMIT;


-- ============================================
-- 3. DIMMEMBERS LOADING (registrationDate start, open-ended current)
-- ============================================
INSERT INTO DimMembers (
    memberKey, memberId, memberName,memberAgeRange,memberGender,state, city, MemberDuration,
    effective_date
)
SELECT 
    seq_dim_member.NEXTVAL,
    m.memberId,
    UPPER(TRIM(m.memberName)),

    /* ===== memberAgeRange =====
       below18 / 18 to 25 / 26 to 40 / 41 to 55 / 56 to 70 / 71+ / unknown (for 100 or NULL) */
    CASE
      WHEN m.memberAge IS NULL OR m.memberAge = 100 THEN 'UNKNOWN'
      WHEN m.memberAge < 18                     THEN 'BELOW 18'
      WHEN m.memberAge BETWEEN 18 AND 25        THEN '18 TO 25'
      WHEN m.memberAge BETWEEN 26 AND 40        THEN '26 TO 40'
      WHEN m.memberAge BETWEEN 41 AND 55        THEN '41 TO 55'
      WHEN m.memberAge BETWEEN 56 AND 70        THEN '56 TO 70'
      WHEN m.memberAge >= 71                    THEN '71+'
      ELSE 'UNKNOWN'
    END AS memberAgeRange,
    
    /* ===== memberGender: female->F, male->M, else U ===== */
    CASE
      WHEN LOWER(TRIM(m.memberGender)) = 'female' THEN 'F'
      WHEN LOWER(TRIM(m.memberGender)) = 'male'   THEN 'M'
      ELSE 'U'  ---unknown
    END AS memberGender,

    -- STATE (between last-2nd and last comma)
CASE
  WHEN INSTR(m.memberAddress, ',', -1, 2) > 0
   AND INSTR(m.memberAddress, ',', -1, 1) > 0 THEN
    UPPER(TRIM(SUBSTR(
      m.memberAddress,
      INSTR(m.memberAddress, ',', -1, 2) + 1,
      INSTR(m.memberAddress, ',', -1, 1) - INSTR(m.memberAddress, ',', -1, 2) - 1
    )))
  ELSE 'UNKNOWN'
END AS state,

-- CITY (between last-3rd and last-2nd comma)
CASE
  WHEN INSTR(m.memberAddress, ',', -1, 3) > 0
   AND INSTR(m.memberAddress, ',', -1, 2) > 0 THEN
    UPPER(TRIM(SUBSTR(
      m.memberAddress,
      INSTR(m.memberAddress, ',', -1, 3) + 1,
      INSTR(m.memberAddress, ',', -1, 2) - INSTR(m.memberAddress, ',', -1, 3) - 1
    )))
  ELSE 'UNKNOWN'
END AS city,

    -- Duration text (optional, keep your style)
    CASE 
      WHEN m.memberStatus = 'active' THEN
        ROUND(MONTHS_BETWEEN(TRUNC(SYSDATE), TRUNC(m.registrationDate))/12, 1) || ' years'
      ELSE
        ROUND(MONTHS_BETWEEN(TRUNC(SYSDATE), TRUNC(m.registrationDate))/12, 1) || ' years'
    END AS MemberDuration,

    -- SCD dates and flag
    TRUNC(m.registrationDate)        AS effective_date
FROM Members m;
COMMIT;

-- ============================================
-- 4. DIMSUPPLIERS LOADING (using sequence)
-- ============================================
INSERT INTO DimSuppliers (
    supplierKey, supplierId, supplierName, State, City
)
SELECT 
    seq_dim_supplier.NEXTVAL,
    supplierId,
    UPPER(TRIM(supplierName)),
    CASE 
               WHEN INSTR(suppliersAddress, ',', -1, 3) > 0 THEN
            UPPER(TRIM(SUBSTR(suppliersAddress, 
                     INSTR(suppliersAddress, ',', -1, 3) + 1,
                     INSTR(suppliersAddress, ',', -1, 2) - INSTR(suppliersAddress, ',', -1, 3) - 1)))
        ELSE 'UNKNOWN'
    END AS State,
    CASE 
        WHEN INSTR(suppliersAddress, ',', -1, 4) > 0 THEN
            UPPER(TRIM(SUBSTR(suppliersAddress, 
                     INSTR(suppliersAddress, ',', -1, 4) + 1,
                     INSTR(suppliersAddress, ',', -1, 3) - INSTR(suppliersAddress, ',', -1, 4) - 1)))
        ELSE 'UNKNOWN'
    END AS City
FROM Suppliers;
COMMIT;

-- ============================================
-- 5. FACTPURCHASE LOADING
-- ============================================
INSERT INTO FactPurchase (
    dateKey, bookKey, supplierKey, quantity, totalAmount, flag_ind, purchaseOrderId
)
SELECT 
    dd.dateKey,
    db.bookKey,
    ds.supplierKey,
    SUM(GREATEST(COALESCE(pd.quantity, 0), 0)),
    ROUND(GREATEST(COALESCE(po.totalAmount, 0), 0), 2),
    CASE WHEN po.orderStatus = 'Received' THEN 'Y' ELSE 'N' END,
    po.purchaseOrderId
FROM PurchaseOrders po
JOIN PurchaseDetails pd ON po.purchaseOrderId = pd.purchaseOrderId
JOIN DimDate dd ON TRUNC(po.purchaseDate) = dd.cal_date
JOIN DimBook db ON pd.bookId = db.bookId
JOIN DimSuppliers ds ON po.supplierId = ds.supplierId
WHERE po.purchaseDate IS NOT NULL
GROUP BY dd.dateKey, db.bookKey, ds.supplierKey, po.totalAmount, po.orderStatus, po.purchaseOrderId;
COMMIT;

-- ============================================
-- 6. FACTBORROWING LOADING
-- ============================================
INSERT INTO FactBorrowing (
  dateKey, memberKey, bookKey, overdueDays, borrowDuration, returnRate
)
WITH base AS (
  SELECT
    bb.borrowId,
    bb.memberId,
    bb.copyId,
    bb.borrowDate,
    bb.dueDate,
    bb.returnDate,
    bb.returnStatus,
    bc.bookId
  FROM BorrowedBooks bb
  JOIN BookCopies  bc ON bc.copyId = bb.copyId
  WHERE bb.borrowDate IS NOT NULL
),
metrics AS (
  SELECT
    bookId,
    COUNT(*) AS total_borrowed,
    SUM(CASE WHEN returnStatus = 'Returned' THEN 1 ELSE 0 END) AS total_returned
  FROM base
  GROUP BY bookId
)
SELECT 
  dd.dateKey,
  dm.memberKey,
  db.bookKey,

  NVL(
    CASE 
      WHEN b.returnDate IS NULL AND b.dueDate < TRUNC(SYSDATE)
        THEN TRUNC(TRUNC(SYSDATE) - b.dueDate)
      WHEN b.returnDate > b.dueDate
        THEN TRUNC(b.returnDate - b.dueDate)
      ELSE 0
    END, 0
  ) AS overdueDays,

  NVL(
    CASE 
      WHEN b.returnDate IS NOT NULL
        THEN TRUNC(b.returnDate - b.borrowDate)
      ELSE TRUNC(TRUNC(SYSDATE) - b.borrowDate)
    END, 0
  ) AS borrowDuration,

  ROUND(100 * NVL(m.total_returned, 0) / NULLIF(m.total_borrowed, 0), 2) AS returnRate

FROM base b
JOIN metrics    m  ON m.bookId   = b.bookId
JOIN DimDate    dd ON TRUNC(b.borrowDate) = dd.cal_date
JOIN DimMembers dm ON dm.memberId = b.memberId
JOIN DimBook    db ON db.bookId   = b.bookId
WHERE NOT EXISTS (
  SELECT 1
  FROM FactBorrowing f
  WHERE f.dateKey   = dd.dateKey
    AND f.memberKey = dm.memberKey
    AND f.bookKey   = db.bookKey
);

COMMIT;

-- ============================================
-- 7. FACTSALES LOADING
-- ============================================
INSERT INTO FactSales (
    memberKey, bookKey, dateKey, sales_id, salesPrice, discount, discount_desc, line_total, quantity
)
SELECT 
    dm.memberKey,
    db.bookKey,
    dd.dateKey,
    sd.salesId,
    bt.salesPrice,
    COALESCE(sd.discountAmount, 0),
    COALESCE(d.discountName, 'No Discount'),
    ROUND(GREATEST(COALESCE(sd.totalAmount, 0), 0), 2),
    GREATEST(COALESCE(sd.quantitySold, 0), 0)
FROM SalesDetails sd
JOIN BookOrders bo ON sd.orderId = bo.orderId
JOIN BookTitles bt ON sd.bookId = bt.bookId
LEFT JOIN Discounts d ON bo.discountId = d.discountId
JOIN DimDate dd ON TRUNC(bo.salesDate) = dd.cal_date
JOIN DimMembers dm ON bo.memberId = dm.memberId
JOIN DimBook db ON sd.bookId = db.bookId
WHERE bo.salesDate IS NOT NULL;
COMMIT;

-- Cleanup temporary objects
DROP FUNCTION get_moving_holiday;
DROP TABLE HOLIDAY_LIST PURGE;