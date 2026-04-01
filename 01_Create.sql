
-- BEGIN
--    FOR rec IN (SELECT table_name FROM user_tables) LOOP
--       EXECUTE IMMEDIATE 'DROP TABLE ' || rec.table_name || ' CASCADE CONSTRAINTS PURGE';
--    END LOOP;
-- END;
-- /

-- BEGIN
--     -- Drop all triggers
--     FOR rec IN (SELECT trigger_name FROM user_triggers) LOOP
--         EXECUTE IMMEDIATE 'DROP TRIGGER ' || rec.trigger_name;
--     END LOOP;

--     -- Drop all views
--     FOR rec IN (SELECT view_name FROM user_views) LOOP
--         EXECUTE IMMEDIATE 'DROP VIEW ' || rec.view_name;
--     END LOOP;

--     -- Drop all tables (CASCADE to drop dependent constraints)
--     FOR rec IN (SELECT table_name FROM user_tables) LOOP
--         EXECUTE IMMEDIATE 'DROP TABLE ' || rec.table_name || ' CASCADE CONSTRAINTS';
--     END LOOP;

--     -- Drop all sequences
--     FOR rec IN (SELECT sequence_name FROM user_sequences) LOOP
--         EXECUTE IMMEDIATE 'DROP SEQUENCE ' || rec.sequence_name;
--     END LOOP;

--     -- Drop all functions
--     FOR rec IN (SELECT object_name FROM user_objects WHERE object_type = 'FUNCTION') LOOP
--         EXECUTE IMMEDIATE 'DROP FUNCTION ' || rec.object_name;
--     END LOOP;

--     -- Drop all procedures
--     FOR rec IN (SELECT object_name FROM user_objects WHERE object_type = 'PROCEDURE') LOOP
--         EXECUTE IMMEDIATE 'DROP PROCEDURE ' || rec.object_name;
--     END LOOP;

--     END;
--     /

-- ===== DROP in dependency order =====
-- DROP TABLE PurchaseDetails      CASCADE CONSTRAINTS;
-- DROP TABLE PurchaseOrders       CASCADE CONSTRAINTS;
-- DROP TABLE SalesDetails         CASCADE CONSTRAINTS;
-- DROP TABLE BookSales            CASCADE CONSTRAINTS;
-- DROP TABLE Discounts            CASCADE CONSTRAINTS;
-- DROP TABLE Suppliers            CASCADE CONSTRAINTS;
-- DROP TABLE Fines                CASCADE CONSTRAINTS;
-- DROP TABLE Payments             CASCADE CONSTRAINTS;
-- DROP TABLE StaffAttendance      CASCADE CONSTRAINTS;
-- DROP TABLE ShiftSchedules       CASCADE CONSTRAINTS;
-- DROP TABLE Reservation          CASCADE CONSTRAINTS;
-- DROP TABLE BorrowedBooks        CASCADE CONSTRAINTS;
-- DROP TABLE BookCopies           CASCADE CONSTRAINTS;
-- DROP TABLE BookTitles           CASCADE CONSTRAINTS;
-- DROP TABLE Shift                CASCADE CONSTRAINTS;
-- DROP TABLE Staff                CASCADE CONSTRAINTS;
-- DROP TABLE Members              CASCADE CONSTRAINTS;

-- ===== Members =====
CREATE TABLE Members(
  memberId         VARCHAR2(5)    NOT NULL, 
  memberName       VARCHAR2(100)  NOT NULL, 	
  memberTel        VARCHAR2(20)   UNIQUE NOT NULL, 
  memberEmail      VARCHAR2(100)  UNIQUE NOT NULL, 
  memberGender     VARCHAR2(6)   NOT NULL,
  memberAge        NUMBER(2)      NOT NULL,
  memberAddress    VARCHAR2(255)  NOT NULL, 
  memberStatus     VARCHAR2(10)   NOT NULL, 
  registrationDate DATE           DEFAULT SYSDATE NOT NULL, 
  expireDate       DATE           NOT NULL,
  CONSTRAINT ck_members_gender CHECK (memberGender IN ('female','male')),
  CONSTRAINT ck_members_age CHECK (memberAge BETWEEN 12 AND 74),
  CONSTRAINT chk_memberStatus CHECK (memberStatus IN ('active', 'expire')),
  CONSTRAINT pk_Member PRIMARY KEY (memberId)
);

-- ===== Staff =====
CREATE TABLE Staff (
  staffId   VARCHAR2(4)   NOT NULL, 
  staffName VARCHAR2(100) NOT NULL, 
  staffEmail VARCHAR2(100) NOT NULL UNIQUE, 
  staffTel   VARCHAR2(20)  NOT NULL UNIQUE, 
  role       VARCHAR2(20)  NOT NULL,
  CONSTRAINT chk_role CHECK (role IN ('librarian', 'manager', 'assistant', 'security', 'cleaner')),
  CONSTRAINT pk_Staff PRIMARY KEY (staffId)
);

-- ===== Shift =====
CREATE TABLE Shift (
  shiftId   VARCHAR2(4)  NOT NULL,
  shiftType VARCHAR2(50) NOT NULL, 
  startTime TIMESTAMP    NOT NULL, 
  endTime   TIMESTAMP    NOT NULL, 
  CONSTRAINT chk_shift_time CHECK (startTime < endTime),
  CONSTRAINT pk_Shift PRIMARY KEY (shiftId)
);

-- ===== BookTitles =====
CREATE TABLE BookTitles (
  bookId          VARCHAR2(5)   NOT NULL,
  title           VARCHAR2(255) NOT NULL,
  author          VARCHAR2(255) NOT NULL,
  genre           VARCHAR2(100) NOT NULL,
  publicationYear NUMBER(4)     NOT NULL,
  purchasePrice   NUMBER(6,2)   NOT NULL CHECK (purchasePrice >= 0),
  salesPrice      NUMBER(6,2)   NOT NULL CHECK (salesPrice >= 0),
  popularity      NUMBER(2,1)   CHECK (popularity BETWEEN 1.0 AND 5.0),
  CONSTRAINT pk_BookTitles PRIMARY KEY (bookId)
);

-- ===== BookCopies =====
CREATE TABLE BookCopies (
  copyId     VARCHAR2(6)  NOT NULL,
  bookId     VARCHAR2(5)  NOT NULL,
  bookStatus VARCHAR2(20) DEFAULT 'available' NOT NULL,
  CONSTRAINT pk_BookCopies PRIMARY KEY (copyId),
  CONSTRAINT fk_BookCopies_BookTitles
    FOREIGN KEY (bookId) REFERENCES BookTitles(bookId) ON DELETE CASCADE,
  CONSTRAINT chk_BookStatus CHECK (bookStatus IN ('available', 'reserved', 'borrowed', 'unavailable')) 
);

-- ===== BorrowedBooks =====
CREATE TABLE BorrowedBooks (
    borrowId VARCHAR2(10) NOT NULL,
    memberId VARCHAR2(5) NOT NULL,
    copyId VARCHAR2(6) NOT NULL,
    borrowDate DATE NOT NULL,
    dueDate DATE NOT NULL,
    returnDate DATE,
    returnStatus VARCHAR2(10) DEFAULT 'On loan' NOT NULL CHECK (
        returnStatus IN ('On loan', 'Returned', 'Overdue', 'Lost')
    ),
    extendStatus VARCHAR2(12) DEFAULT 'Unsubmitted' CHECK (
        extendStatus IN ('Unsubmitted', 'Pending', 'Approved', 'Rejected', 'Canceled')
    ),
    CONSTRAINT pk_BorrowedBooks PRIMARY KEY (borrowId),
    CONSTRAINT fk_BorrowedBooks_Members FOREIGN KEY (memberId) REFERENCES Members(memberId) ON DELETE CASCADE,
    CONSTRAINT fk_BorrowedBooks_BookCopies FOREIGN KEY (copyId) REFERENCES BookCopies(copyId) ON DELETE CASCADE
);

-- ===== ShiftSchedules =====
CREATE TABLE ShiftSchedules (
  scheduleId VARCHAR2(5) NOT NULL,        
  shiftId    VARCHAR2(4) NOT NULL,         
  staffId    VARCHAR2(4) NOT NULL,        
  shiftDate  DATE        NOT NULL,        
  CONSTRAINT pk_ShiftSchedules PRIMARY KEY (scheduleId),
  CONSTRAINT uq_ShiftSchedules_StaffDate UNIQUE (staffId, shiftDate),
  CONSTRAINT fk_ShiftSchedules_Shift FOREIGN KEY (shiftId) REFERENCES Shift(shiftId),        
  CONSTRAINT fk_ShiftSchedules_Staff FOREIGN KEY (staffId) REFERENCES Staff(staffId)
);

-- ===== StaffAttendance =====
CREATE TABLE StaffAttendance (
  attendanceId     VARCHAR2(5) NOT NULL,                         
  scheduleId       VARCHAR2(5) NOT NULL,
  attendanceStatus VARCHAR2(10) NOT NULL,                        
  actualStartTime  TIMESTAMP,                                  
  actualEndTime    TIMESTAMP,
  CONSTRAINT pk_StaffAttendance PRIMARY KEY (attendanceId),     
  CONSTRAINT fk_StaffAtt_ShiftSched FOREIGN KEY (scheduleId) REFERENCES ShiftSchedules(scheduleId),       
  CONSTRAINT chk_attendanceStatus CHECK (attendanceStatus IN ('Present', 'Absent', 'Late')),
  CONSTRAINT chk_StaffAttendance_Time CHECK (
    actualStartTime IS NULL OR actualEndTime IS NULL OR actualStartTime < actualEndTime
  )
);

-- ===== Payments =====
CREATE TABLE Payments (
	paymentId    VARCHAR2(10) NOT NULL,
	memberId     VARCHAR2(9) NOT NULL,
	paymentDate  DATE NOT NULL,	
	payAmount    NUMBER(8,2) NULL,		
  paymentMethod VARCHAR2(20) NOT NULL,
	paymentType   VARCHAR2(25) NOT NULL,	
	receiptNo     VARCHAR2(12) NOT NULL,	
	CONSTRAINT pk_Payments PRIMARY KEY (paymentId),	
	CONSTRAINT fk_Payments_Members FOREIGN KEY (memberId) REFERENCES Members (memberId),
	CONSTRAINT chk_paymentMethod CHECK (paymentMethod IN ('Tng', 'Cash', 'Duitnow')),
	CONSTRAINT chk_paymentType CHECK (paymentType IN ('Fines', 'Membership Registration','Book Sale'))
);

-- ===== Fines =====
CREATE TABLE Fines (
    fineId VARCHAR2(7) NOT NULL,        
    borrowId VARCHAR2(10) NOT NULL,        
    paymentId VARCHAR2(10) NULL,
    fineType VARCHAR2(12) NOT NULL,        
    fineAmount NUMBER(8,2) NULL,        
    fineDate DATE NOT NULL,        
    fineStatus VARCHAR2(6) NOT NULL,        
    CONSTRAINT pk_Fines PRIMARY KEY (fineId),        
    CONSTRAINT fk_Fines_BorrowedBooks FOREIGN KEY (borrowId) REFERENCES BorrowedBooks (borrowId),                
    CONSTRAINT chk_fineType CHECK (fineType IN ('Late Return', 'Lost Book', 'Damage')),        
    CONSTRAINT chk_fineStatus CHECK (fineStatus IN ('Unpaid', 'Paid'))
);

-- ===== Suppliers =====
CREATE TABLE Suppliers(
  supplierId    VARCHAR2(5)      NOT NULL,
  supplierName  VARCHAR2(100)    NOT NULL,
  contactPerson VARCHAR2(50)     NOT NULL,
  supplierTel   VARCHAR2(20)     NOT NULL,
  suppliersAddress VARCHAR2(100) NOT NULL,
  CONSTRAINT pk_Suppliers PRIMARY KEY (supplierId)
);

-- ===== Discounts =====
CREATE TABLE Discounts (
  discountId    VARCHAR2(5)   NOT NULL,
  discountName  VARCHAR2(50)  NOT NULL,
  discountRate  NUMBER(8,2),
  discountStart DATE,
  discountEnd   DATE,
  CONSTRAINT pk_Discounts PRIMARY KEY (discountId),
  CONSTRAINT chk_discounts_range CHECK (discountStart IS NULL OR discountEnd IS NULL OR discountStart < discountEnd),
  CONSTRAINT chk_discountRate     CHECK (discountRate IS NULL OR (discountRate BETWEEN 0 AND 100))
);


-- ===== BookOrders =====
CREATE TABLE BookOrders(
   orderId        VARCHAR2(9) NOT NULL,
   paymentId      VARCHAR2(10) NOT NULL,
   discountId     VARCHAR2(5) NOT NULL,
   memberId       VARCHAR2(5) NOT NULL,
   salesDate      DATE,
   CONSTRAINT pk_BookOrders PRIMARY KEY (orderId),
   CONSTRAINT fk_BookOrders_Payments FOREIGN KEY (paymentId) REFERENCES Payments(paymentId),
   CONSTRAINT fk_BookOrders_Discounts FOREIGN KEY (discountId) REFERENCES Discounts(discountId),
   CONSTRAINT fk_BookOrders_Members FOREIGN KEY (memberId) REFERENCES Members(memberId)
);

-- ===== SalesDetails =====
CREATE TABLE SalesDetails(
   salesId        VARCHAR2(10) NOT NULL,
   orderId        VARCHAR2(9) NOT NULL,
   bookId         VARCHAR2(5) NOT NULL,
   quantitySold   NUMBER,
   discountAmount NUMBER(10,2),
   totalAmount    NUMBER(10,2),
   CONSTRAINT pk_SalesDetails PRIMARY KEY (salesId),
   CONSTRAINT fk_SalesDetails_BookOrders FOREIGN KEY (orderId) REFERENCES BookOrders(orderId),
   CONSTRAINT fk_SalesDetails_BookTitles FOREIGN KEY (bookId) REFERENCES BookTitles(bookId)
);

-- ===== PurchaseOrders =====
CREATE TABLE PurchaseOrders(
   purchaseOrderId VARCHAR2(7) NOT NULL,
   supplierId      VARCHAR2(5) NOT NULL,
   purchaseDate    DATE NOT NULL,
   totalAmount    NUMBER(8,2) NOT NULL,
   orderStatus    VARCHAR2(20) DEFAULT 'Received' NOT NULL CHECK (
        orderStatus IN ('Received','Pending','Cancelled')
   ),
   CONSTRAINT pk_PurchaseOrders PRIMARY KEY (purchaseOrderId),
   CONSTRAINT fk_PurchaseOrders_Suppliers FOREIGN KEY (supplierId) REFERENCES Suppliers(supplierId) 
);

-- ===== PurchaseDetails =====
CREATE TABLE PurchaseDetails(
   detailId     VARCHAR2(6) NOT NULL,
   purchaseOrderId      VARCHAR2(7) NOT NULL,
   bookId       VARCHAR2(5) NOT NULL,
   quantity     NUMBER,
   CONSTRAINT pk_PurchaseDetails PRIMARY KEY (detailId),
   CONSTRAINT fk_PurchaseDetails_Orders FOREIGN KEY (purchaseOrderId) REFERENCES PurchaseOrders(purchaseOrderId),
   CONSTRAINT fk_PurchaseDetails_BookTitles FOREIGN KEY (bookId) REFERENCES BookTitles(bookId),
   CONSTRAINT chk_pd_qty_nonneg CHECK (quantity IS NULL OR quantity >= 0)
);
