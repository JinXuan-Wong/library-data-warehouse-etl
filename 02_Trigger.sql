-------------- TRIGGER 1 - Auto update member status ----------------
CREATE OR REPLACE TRIGGER trg_auto_expire_membership
BEFORE UPDATE ON Members
FOR EACH ROW
WHEN (NEW.expireDate <= SYSDATE AND OLD.memberStatus = 'active')
BEGIN
    -- Automatically update the member status to 'Expire'
    :NEW.memberStatus := 'Expire';

END;
/

---------------------- TRIGGER 2 - Manage Book Details Validation -----------------------
CREATE OR REPLACE TRIGGER TRG_MANAGE_BOOK_DETAILS
BEFORE INSERT OR UPDATE ON BookTitles
FOR EACH ROW
DECLARE
   v_count NUMBER;
BEGIN
    
   -- Ensure publication year is valid
   IF :NEW.publicationYear > EXTRACT(YEAR FROM SYSDATE) THEN
      RAISE_APPLICATION_ERROR(-20002, 'Error: Publication year cannot be in the future.');
   END IF;

   -- Ensure price is positive
   IF :NEW.purchasePrice < 0 THEN
      RAISE_APPLICATION_ERROR(-20003, 'Error: Price must be zero or greater.');
   END IF;

   -- Ensure price is positive
   IF :NEW.salesPrice < 0 THEN
      RAISE_APPLICATION_ERROR(-20003, 'Error: Price must be zero or greater.');
   END IF;

   -- Ensure popularity is within the range 1.0 - 5.0
   IF :NEW.popularity < 1.0 OR :NEW.popularity > 5.0 THEN
      RAISE_APPLICATION_ERROR(-20004, 'Error: Popularity must be between 1.0 and 5.0.');
   END IF;
END;
/

--================= Trigger: Automatic Book Status Update (BookCopies)===============
--------------------- TRIGGER 3 - Book Status from BorrowedBooks ------------------------
CREATE OR REPLACE TRIGGER TRG_MANAGE_BOOK_STATUS_BB
FOR INSERT OR UPDATE ON BorrowedBooks
COMPOUND TRIGGER

   -- Declare a collection to store affected copyIds
   TYPE CopyIdList IS TABLE OF BookCopies.copyId%TYPE;
   affected_copyIds CopyIdList := CopyIdList(); 

   -- BEFORE EACH ROW: Store affected copyIds
   BEFORE EACH ROW IS
   BEGIN
      affected_copyIds.EXTEND;
      affected_copyIds(affected_copyIds.LAST) := :NEW.copyId;
   END BEFORE EACH ROW;

   -- AFTER STATEMENT: Process all affected copyIds
   AFTER STATEMENT IS
   BEGIN
      FOR i IN 1..affected_copyIds.COUNT LOOP
         DECLARE
            v_copyId BookCopies.copyId%TYPE := affected_copyIds(i);
            v_new_status BookCopies.bookStatus%TYPE;
            v_current_status BookCopies.bookStatus%TYPE;
         BEGIN
            -- Get current book status
            SELECT bookStatus INTO v_current_status
            FROM BookCopies
            WHERE copyId = v_copyId;

            -- Determine new book status
            SELECT
               CASE 
                  -- 1. If book is borrowed, set to "Borrowed"
                  WHEN EXISTS (
                     SELECT 1 FROM BorrowedBooks 
                     WHERE copyId = v_copyId  
                     AND returnStatus = 'On loan'
                  ) THEN 'borrowed'
                  
                  ELSE v_current_status
               END
            INTO v_new_status
            FROM dual;

            -- Update only if book status has changed
            IF v_new_status IS NOT NULL AND v_new_status <> v_current_status THEN
               UPDATE BookCopies
               SET bookStatus = v_new_status
               WHERE copyId = v_copyId;
            END IF;
         END;
      END LOOP;
   END AFTER STATEMENT;
END TRG_MANAGE_BOOK_STATUS_BB;
/

-- =============================

--------- TRIGGER 5 - Auto-mark Staff as 'Late' Based on Shift Start Time------------
CREATE OR REPLACE TRIGGER trg_auto_mark_late
BEFORE INSERT OR UPDATE ON StaffAttendance
FOR EACH ROW
DECLARE
    v_shiftStart TIMESTAMP;
BEGIN
    SELECT s.startTime INTO v_shiftStart
    FROM ShiftSchedules ss
    JOIN Shift s ON ss.shiftId = s.shiftId
    WHERE ss.scheduleId = :NEW.scheduleId;

    IF :NEW.actualStartTime IS NOT NULL THEN
        IF :NEW.actualStartTime > v_shiftStart THEN
            :NEW.attendanceStatus := 'Late';
        ELSE
            :NEW.attendanceStatus := 'Present';
        END IF;
    END IF;
END;
/

------- TRIGGER 6 -  Enforce 40-Hour Weekly Limit for Staff ------------
CREATE OR REPLACE TRIGGER trg_check_weekly_hours
BEFORE INSERT OR UPDATE ON StaffAttendance
FOR EACH ROW
DECLARE
    v_staffId ShiftSchedules.staffId%TYPE;
    v_shiftDate DATE;
    v_weekStart DATE;
    v_totalHours NUMBER := 0;
    v_newHours NUMBER := 0;
BEGIN
    SELECT staffId, shiftDate INTO v_staffId, v_shiftDate
    FROM ShiftSchedules
    WHERE scheduleId = :NEW.scheduleId;

    v_weekStart := TRUNC(v_shiftDate, 'IW');

    SELECT NVL(SUM(
        EXTRACT(DAY FROM (actualEndTime - actualStartTime)) * 24 + EXTRACT(HOUR FROM (actualEndTime - actualStartTime))
    ), 0)
    INTO v_totalHours
    FROM StaffAttendance sa
    JOIN ShiftSchedules ss ON sa.scheduleId = ss.scheduleId
    WHERE ss.staffId = v_staffId
      AND TRUNC(ss.shiftDate, 'IW') = v_weekStart;
      
    IF :NEW.actualStartTime IS NOT NULL AND :NEW.actualEndTime IS NOT NULL THEN
        v_newHours := (EXTRACT(DAY FROM (:NEW.actualEndTime - :NEW.actualStartTime)) * 24) + EXTRACT(HOUR FROM (:NEW.actualEndTime - :NEW.actualStartTime));
    END IF;

    IF (v_totalHours + v_newHours) > 40 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Total working hours for this staff in the week would exceed 40 hours.');
    END IF;
END;
/

------------ TRIGGER: ENFORCE MEMBER BORROW BOOK IN THE VALID RANGES ----------
CREATE OR REPLACE TRIGGER trg_bb_member_valid
  BEFORE INSERT OR UPDATE OF memberId, borrowDate ON BorrowedBooks
  FOR EACH ROW
DECLARE
  v_reg  Members.registrationDate%TYPE;
  v_exp  Members.expireDate%TYPE;
BEGIN
  IF :NEW.memberId IS NULL OR :NEW.borrowDate IS NULL THEN
    RAISE_APPLICATION_ERROR(-20030, 'memberId and borrowDate are required.');
  END IF;

  BEGIN
    SELECT registrationDate, expireDate
      INTO v_reg, v_exp
      FROM Members
     WHERE memberId = :NEW.memberId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20031, 'Member '||:NEW.memberId||' does not exist.');
  END;

  -- Compare dates ignoring time-of-day
  IF TRUNC(:NEW.borrowDate) < TRUNC(v_reg)
     OR TRUNC(:NEW.borrowDate) > TRUNC(v_exp) THEN
    RAISE_APPLICATION_ERROR(
      -20032,
      'Borrow date '||TO_CHAR(:NEW.borrowDate,'YYYY-MM-DD')||
      ' is outside membership window '||
      TO_CHAR(v_reg,'YYYY-MM-DD')||'..'||TO_CHAR(v_exp,'YYYY-MM-DD')||
      ' for member '||:NEW.memberId
    );
  END IF;
END;
/

------------ TRIGGER 8 - UPDATE_FINE_AMOUNT -------------

CREATE OR REPLACE TRIGGER TRG_CALCULATE_FINE_AMOUNT
BEFORE INSERT OR UPDATE ON Fines
FOR EACH ROW
WHEN (NEW.fineAmount IS NULL)
DECLARE
   v_salesPrice BookTitles.salesPrice%TYPE;
BEGIN
   IF :NEW.fineType IN ('Lost Book', 'Damage') THEN
      SELECT BT.salesPrice
      INTO v_salesPrice
      FROM BookTitles BT
      JOIN BookCopies BC ON BC.bookId = BT.bookId
      JOIN BorrowedBooks BB ON BB.copyId = BC.copyId
      WHERE BB.borrowId = :NEW.borrowId;

      IF :NEW.fineType = 'Lost Book' THEN
         :NEW.fineAmount := v_salesPrice + 20;
      ELSIF :NEW.fineType = 'Damage' THEN
         :NEW.fineAmount := v_salesPrice;
      END IF;

   ELSIF :NEW.fineType = 'Late Return' THEN
      :NEW.fineAmount := 30;
   END IF;
END;
/

------------------ TRIGGER 9 - UPDATE_PAYMENT_AMOUNT ------------------
CREATE OR REPLACE TRIGGER TRG_CALCULATE_PAYMENT_AMOUNT
BEFORE INSERT OR UPDATE ON Payments
FOR EACH ROW
WHEN (NEW.payAmount IS NULL)
DECLARE
   v_total NUMBER;
BEGIN
   IF :NEW.paymentType = 'Fines' THEN
      SELECT SUM(fineAmount)
      INTO v_total
      FROM Fines
      WHERE paymentId = :NEW.paymentId;

      :NEW.payAmount := NVL(v_total, 0);

   ELSIF :NEW.paymentType = 'Membership Registration' THEN
      :NEW.payAmount := 50;
   END IF;
END;
/

------------------ TRIGGER 10 - MANAGE_FINES ------------------
CREATE OR REPLACE TRIGGER TRG_MANAGE_FINES
BEFORE INSERT OR UPDATE ON Fines
FOR EACH ROW
BEGIN
   -- Validate fineType
   IF :NEW.fineType NOT IN ('Late Return', 'Lost Book', 'Damage') THEN
      RAISE_APPLICATION_ERROR(-20010, 'Invalid fine type. Allowed: Late Return, Lost Book, Damage.');
   END IF;

   -- Validate fineStatus
   IF :NEW.fineStatus NOT IN ('Unpaid', 'Paid') THEN
      RAISE_APPLICATION_ERROR(-20011, 'Invalid fine status. Allowed: Unpaid, Paid.');
   END IF;

-- Validate fineAmount (ensure non-negative value)
   IF :NEW.fineAmount <= 0 THEN
      RAISE_APPLICATION_ERROR(-20012, 'Fine amount cannot be negative.');
   END IF;
END;
/

------------------ TRIGGER 11 - MANAGE_PAYMENTS ------------------
CREATE OR REPLACE TRIGGER TRG_MANAGE_PAYMENTS
AFTER INSERT OR UPDATE ON Payments
FOR EACH ROW
BEGIN
   -- Validate paymentMethod
   IF :NEW.paymentMethod NOT IN ('Tng', 'Cash', 'Duitnow') THEN
      RAISE_APPLICATION_ERROR(-20013, 'Invalid payment method. Allowed: Tng, Cash, Duitnow.');
   END IF;

   -- Validate paymentType
   IF :NEW.paymentType NOT IN ('Fines', 'Membership Registration', 'Book Sale') THEN
      RAISE_APPLICATION_ERROR(-20014, 'Invalid payment type. Allowed: Fines, Membership Registration, Book Sale.');
   END IF;

   -- Validate payAmount (ensure non-negative value)
   IF :NEW.payAmount <= 0 THEN
      RAISE_APPLICATION_ERROR(-20015, 'Payment amount cannot be negative.');
   END IF;

   -- Update fineStatus if payment is for a fine and has amount
   IF :NEW.paymentType = 'Fines' AND :NEW.payAmount IS NOT NULL THEN
      UPDATE Fines
      SET fineStatus = 'Paid'
      WHERE paymentId = :NEW.paymentId;
   END IF;
END;
/

------------------ TRIGGER 12 - PurchaseTotalAmountCheck  ------------------
-- Validate that PurchaseOrders.totalAmount equals the sum over PurchaseDetails
-- (quantity * BookTitles.purchasePrice) for each affected purchaseOrderId.

CREATE OR REPLACE TRIGGER trg_check_purchase_total
FOR INSERT OR UPDATE OR DELETE ON PurchaseDetails
COMPOUND TRIGGER

  -- A simple "set" of purchaseOrderIds affected in this statement
  TYPE t_po_set IS TABLE OF BOOLEAN INDEX BY VARCHAR2(5);
  g_po_set t_po_set;

  PROCEDURE add_po(poid VARCHAR2) IS
  BEGIN
    IF poid IS NOT NULL THEN
      g_po_set(poid) := TRUE;
    END IF;
  END;

  BEFORE EACH ROW IS
  BEGIN
    IF INSERTING OR UPDATING THEN
      add_po(:NEW.purchaseOrderId);
    END IF;

    IF UPDATING OR DELETING THEN
      add_po(:OLD.purchaseOrderId);
    END IF;
  END BEFORE EACH ROW;

  AFTER STATEMENT IS
    v_key   VARCHAR2(5);
    v_sum   NUMBER(10,2);
    v_total NUMBER(10,2);
  BEGIN
    v_key := g_po_set.FIRST;
    WHILE v_key IS NOT NULL LOOP
      -- Recompute details sum for this PO
      SELECT NVL(SUM(NVL(d.quantity,0) * b.purchasePrice), 0)
      INTO v_sum
      FROM PurchaseDetails d
      JOIN BookTitles b ON b.bookId = d.bookId
      WHERE d.purchaseOrderId = v_key;

      -- Compare with header total (if the PO header exists)
      BEGIN
         UPDATE PurchaseOrders
            SET totalAmount = ROUND(NVL(v_sum,0),2)
         WHERE purchaseOrderId = v_key;
      EXCEPTION
            WHEN NO_DATA_FOUND THEN NULL;
      END;

      v_key := g_po_set.NEXT(v_key);
    END LOOP;
  END AFTER STATEMENT;

END;
/

------------------ TRIGGER 13 - PurchaseOrder TotalAmount  ----------------
CREATE OR REPLACE TRIGGER trg_guard_po_total
BEFORE INSERT OR UPDATE OF totalAmount, purchaseOrderId ON PurchaseOrders
FOR EACH ROW
DECLARE
  v_sum NUMBER(10,2);
BEGIN
  SELECT NVL(SUM(NVL(d.quantity,0) * b.purchasePrice), 0)
  INTO v_sum
  FROM PurchaseDetails d
  JOIN BookTitles b ON b.bookId = d.bookId
  WHERE d.purchaseOrderId = :NEW.purchaseOrderId;

  IF ROUND(NVL(:NEW.totalAmount,0), 2) != ROUND(NVL(v_sum,0), 2) THEN
    RAISE_APPLICATION_ERROR(
      -20002,
      'totalAmount must equal details sum: ' || TO_CHAR(v_sum,'FM9999990.00')
    );
  END IF;
END;
/

----------- TRIGGER 14 - Check Discount Date---------

CREATE OR REPLACE TRIGGER trg_BookOrders_DiscDate
BEFORE INSERT OR UPDATE OF salesDate, discountId ON BookOrders
FOR EACH ROW
DECLARE
  v_start DATE;
  v_end   DATE;
BEGIN
  -- Default salesDate
  IF :NEW.salesDate IS NULL THEN
    :NEW.salesDate := SYSDATE;
  END IF;

  -- Check discount validity on that salesDate
  SELECT discountStart, discountEnd
    INTO v_start, v_end
    FROM Discounts
   WHERE discountId = :NEW.discountId;

  IF (v_start IS NOT NULL AND :NEW.salesDate < v_start)
     OR (v_end IS NOT NULL AND :NEW.salesDate > v_end) THEN
    RAISE_APPLICATION_ERROR(
      -20001,
      'Discount '||:NEW.discountId||' not active on salesDate '||TO_CHAR(:NEW.salesDate,'YYYY-MM-DD')
    );
  END IF;
END;
/

----------- TRIGGER 15 - Auto Compute Discount Amount and Total Amount ---------
CREATE OR REPLACE TRIGGER trg_salesdetails_calc_amounts
BEFORE INSERT OR UPDATE OF orderId, bookId, quantitySold, discountAmount, totalAmount ON SalesDetails
FOR EACH ROW
DECLARE
  v_rate   NUMBER := 0;     -- percent (0..100)
  v_price  NUMBER := 0;     -- BookTitles.salesPrice
  v_date   DATE;            -- BookOrders.salesDate
  v_start  DATE;            -- Discounts.discountStart
  v_end    DATE;            -- Discounts.discountEnd
  v_gross  NUMBER := 0;
BEGIN
  -- quantity sanity
  IF :NEW.quantitySold IS NULL OR :NEW.quantitySold < 1 THEN
    RAISE_APPLICATION_ERROR(-20002, 'quantitySold must be >= 1');
  END IF;

  -- fetch parent order date, discount window & rate
  SELECT o.salesDate, d.discountStart, d.discountEnd, NVL(d.discountRate,0)
    INTO v_date,      v_start,        v_end,          v_rate
    FROM BookOrders o
    JOIN Discounts d ON d.discountId = o.discountId
   WHERE o.orderId = :NEW.orderId;

  -- fetch item price
  SELECT salesPrice
    INTO v_price
    FROM BookTitles
   WHERE bookId = :NEW.bookId;

  -- ensure discount active for that order date (defensive check)
  IF (v_start IS NOT NULL AND v_date < v_start)
     OR (v_end IS NOT NULL AND v_date > v_end) THEN
    RAISE_APPLICATION_ERROR(
      -20003,
      'Discount on order '||:NEW.orderId||' not active on '||TO_CHAR(v_date,'YYYY-MM-DD')
    );
  END IF;

  -- compute amounts
  v_gross := v_price * :NEW.quantitySold;
  :NEW.discountAmount := ROUND(v_gross * (v_rate/100), 2);
  :NEW.totalAmount    := ROUND(v_gross - :NEW.discountAmount, 2);
END;
/

