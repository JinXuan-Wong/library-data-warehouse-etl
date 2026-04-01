-- Drop fact tables first (child tables)
DROP TABLE FactSales CASCADE CONSTRAINTS;
DROP TABLE FactBorrowing CASCADE CONSTRAINTS;
DROP TABLE FactPurchase CASCADE CONSTRAINTS;

-- Drop dimension tables next (parent tables)
DROP TABLE DimBook CASCADE CONSTRAINTS;
DROP TABLE DimMembers CASCADE CONSTRAINTS;
DROP TABLE DimSuppliers CASCADE CONSTRAINTS;
DROP TABLE DimDate CASCADE CONSTRAINTS;

-- Date Dimension
CREATE TABLE DimDate (
    dateKey            NUMBER NOT NULL,  
    cal_date           DATE   NOT NULL,  
    full_desc          VARCHAR(40),      
    day_of_week        NUMBER(1),        
    day_num_month      NUMBER(2),        
    day_num_year       NUMBER(3),        
    month_name         VARCHAR2(20),
    cal_month_year     NUMBER(2),        
    cal_year_month     CHAR(7),          
    cal_quarter         CHAR(2),          
    cal_year_quarter    CHAR(7),          
    cal_year           NUMBER(4),        
    holiday_indicator  CHAR(1),          
    weekday_indicator  CHAR(1),          
    festive_event      VARCHAR(50),      
    business_day_ind   CHAR(1),
    CONSTRAINT DimDate_PK PRIMARY KEY (dateKey)
);

-- Member Dimension
CREATE TABLE DimMembers (
    memberKey        NUMBER NOT NULL,
    memberId         VARCHAR2(5) NOT NULL,
    memberName       VARCHAR2(100) NOT NULL,
    memberAgeRange   VARCHAR2(50),
    memberGender     CHAR(1),
    state            VARCHAR2(20),
    city             VARCHAR2(20),
    MemberDuration   VARCHAR2(20),
    effective_date   DATE DEFAULT TO_DATE('01-JUL-2004','DD-MON-YYYY'),
    expiration_date  DATE DEFAULT TO_DATE('31-DEC-9999','DD-MON-YYYY'),
    curr_ind         CHAR(1) DEFAULT 'Y',     
    CONSTRAINT DimMembers_PK PRIMARY KEY (memberKey)
);

-- Book Dimension
CREATE TABLE DimBook (
    bookKey     NUMBER NOT NULL,
    bookId      VARCHAR2(5) NOT NULL,
    bookStatus  VARCHAR2(20) DEFAULT 'AVAILABLE',
    title       VARCHAR2(255),
    author      VARCHAR2(255),
    genre       VARCHAR2(100),
    price       NUMBER(6,2),
    popularity  NUMBER(2,1),
    effective_date   DATE DEFAULT TO_DATE('01-JUL-2004','DD-MON-YYYY'),
    expiration_date  DATE DEFAULT TO_DATE('31-DEC-9999','DD-MON-YYYY'),
    curr_ind         CHAR(1) DEFAULT 'Y',     
    CONSTRAINT DimBook_PK PRIMARY KEY (bookKey)
);

-- Suppliers Dimension
CREATE TABLE DimSuppliers (
    supplierKey   NUMBER NOT NULL,
    supplierId    VARCHAR2(5) NOT NULL,
    supplierName  VARCHAR2(100),
    State         VARCHAR2(35),
    City          VARCHAR2(35),
    CONSTRAINT DimSuppliers_PK PRIMARY KEY (supplierKey)
);

-- Purchase Fact Table
CREATE TABLE FactPurchase (
    dateKey         NUMBER       NOT NULL,
    bookKey         NUMBER       NOT NULL,
    supplierKey     NUMBER       NOT NULL,
    quantity        NUMBER       NOT NULL,
    totalAmount     NUMBER(12,2) NOT NULL,
    flag_ind        CHAR(1)      NOT NULL,
    purchaseOrderId VARCHAR2(7)  NOT NULL,
    CONSTRAINT FactPurchase_PK PRIMARY KEY (dateKey, bookKey, supplierKey, purchaseOrderId), 
    CONSTRAINT FactPurchase_Date_FK FOREIGN KEY (dateKey) REFERENCES DimDate(dateKey), 
    CONSTRAINT FactPurchase_Book_FK FOREIGN KEY (bookKey) REFERENCES DimBook(bookKey), 
    CONSTRAINT FactPurchase_Supplier_FK FOREIGN KEY (supplierKey) REFERENCES DimSuppliers(supplierKey),
    CONSTRAINT FactPurchase_POId_FK FOREIGN KEY (purchaseOrderId) REFERENCES PurchaseOrders(purchaseOrderId) 
);

-- Borrowing Fact Table
CREATE TABLE FactBorrowing (
    dateKey        NUMBER      NOT NULL,
    memberKey      NUMBER      NOT NULL,
    bookKey        NUMBER      NOT NULL,
    overdueDays    NUMBER      NOT NULL,
    borrowDuration NUMBER      NOT NULL,
    returnRate     NUMBER(5,2) NOT NULL,
    CONSTRAINT FactBorrowing_PK PRIMARY KEY (dateKey, memberKey, bookKey), 
    CONSTRAINT FactBorrowing_Date_FK FOREIGN KEY (dateKey) REFERENCES DimDate(dateKey), 
    CONSTRAINT FactBorrowing_Member_FK FOREIGN KEY (memberKey) REFERENCES DimMembers(memberKey), 
    CONSTRAINT FactBorrowing_Book_FK FOREIGN KEY (bookKey) REFERENCES DimBook(bookKey) 
);

-- Sales Fact Table
CREATE TABLE FactSales (
    memberKey      NUMBER        NOT NULL,
    bookKey        NUMBER        NOT NULL,
    dateKey        NUMBER        NOT NULL,
    sales_id       VARCHAR2(12)  NOT NULL,
    salesPrice     NUMBER(10,2)  NOT NULL,
    discount       NUMBER(8,2)   NOT NULL,
    discount_desc  VARCHAR2(100) NOT NULL,
    line_total     NUMBER(12,2)  NOT NULL,
    quantity       NUMBER        NOT NULL,
    CONSTRAINT FactSales_PK PRIMARY KEY (memberKey, bookKey, dateKey, sales_id), 
    CONSTRAINT FactSales_Member_FK FOREIGN KEY (memberKey) REFERENCES DimMembers(memberKey), 
    CONSTRAINT FactSales_Book_FK FOREIGN KEY (bookKey) REFERENCES DimBook(bookKey), 
    CONSTRAINT FactSales_Date_FK FOREIGN KEY (dateKey) REFERENCES DimDate(dateKey),
    CONSTRAINT FactSales_sales_id_FK FOREIGN KEY (sales_id) REFERENCES SalesDetails(salesId)
);