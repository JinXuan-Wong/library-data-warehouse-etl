# Library Data Warehouse and Analytics

An Oracle SQL data warehouse project developed for a Data Warehouse Technology assignment. This project transforms operational library data into a dimensional warehouse for analytics, reporting, and decision support.

## Project Overview

This project designs and implements a library data warehouse using a star schema model. It includes dimension and fact table creation, initial and subsequent ETL loading, Slowly Changing Dimension (Type 2) handling, and analytical reports for business decision-making.

The warehouse supports reporting on:
- borrowing trends
- sales and borrowing preferences
- supplier contribution and geography
- discount impact
- member behavior
- sales performance

## Objectives

- Design a dimensional data warehouse for a library business
- Implement logical and physical warehouse structures
- Build ETL scripts for initial and subsequent loading
- Handle historical dimension changes using Type 2 SCD
- Generate business analytics reports from warehouse data
- Support decision-making with SQL-based reporting and visualizations

## Data Warehouse Design

The warehouse is based on a star schema.

### Dimension tables
- `DimDate`
- `DimBook`
- `DimMembers`
- `DimSuppliers`

### Fact tables
- `FactPurchase`
- `FactBorrowing`
- `FactSales`

## ETL Workflow

The SQL scripts are organized in execution order.

### Run order
1. `00_Deleteall.sql`
2. `01_Create.sql`
3. `02_Trigger.sql`
4. `03_Insert/`
5. `04_CreateDimensionFact.sql`
6. `05_InitialLoading.sql`
7. `06_Type2-1.sql`
8. `06_Type2-2.sql`
9. `07_SubsequentLoading.sql`

These scripts cover:
- table creation
- trigger setup
- source data insertion
- dimension and fact creation
- initial data warehouse loading
- Type 2 SCD updates
- subsequent ETL loading

## Key Features

- Star schema design for analytical reporting
- Dimension and fact table implementation
- Initial ETL loading from source tables
- Subsequent ETL loading for new records
- Type 2 Slowly Changing Dimension support
- SQL-based reporting for business analysis
- Report output text files and supporting visualizations

## My Contribution

Wong Jin Xuan focused on the following analytics reports:

- Quarterly and Monthly Borrowing Trend Analysis
- Sales and Borrowing Preference Analysis by Year and Genre
- Supplier Contribution Deliveries by Geography

### 1. Quarterly and Monthly Borrowing Trend Analysis
This report analyzes borrowing volume by month and quarter, including:
- month-to-month and quarter-to-quarter changes
- 3-month moving averages
- seasonal index
- net copies available
- top borrowed genre
- holiday month indicator

### 2. Sales and Borrowing Preference Analysis by Year and Genre
This report compares:
- borrow count
- sales count
- borrow percentage
- sales percentage
- sales revenue
- member gender participation
- genre preference classification

### 3. Supplier Contribution Deliveries by Geography
This report evaluates:
- purchase orders by supplier city
- purchase value by geography
- quantity supplied
- average order value
- contribution percentage by period
- supplier priority
- top supplier by purchase value

## Project Structure

```text
.
├── 00_Deleteall.sql
├── 01_Create.sql
├── 02_Trigger.sql
├── 03_Insert/
├── 04_CreateDimensionFact.sql
├── 05_InitialLoading.sql
├── 06_Type2-1.sql
├── 06_Type2-2.sql
├── 07_SubsequentLoading.sql
├── BorrowingTrend_Report1.txt
├── BorrowVsSales_Genre_Report2.txt
├── SupplierPerformance_Report3.txt
├── WongJinXuan/
├── WongJinXuan_ReportVisualization...
├── SQL Report & PowerBI Charts ...
├── README.md
└── .gitignore
```
## Technologies Used

- Oracle SQL  
- PL/SQL  
- Star schema modeling  
- ETL design  
- Slowly Changing Dimension (Type 2)  
- SQL*Plus style reporting  
- Power BI / visualization outputs  

---

## How to Use

1. Open Oracle SQL Developer or SQL*Plus.  
2. Run the SQL scripts in sequence from `00` to `07`.  
3. Load the operational source data.  
4. Build the warehouse tables and dimensions.  
5. Execute ETL scripts for initial loading.  
6. Run Type 2 scripts to test historical dimension tracking.  
7. Execute subsequent loading scripts for incremental updates.  
8. Run the analytics report scripts and review output files.  

---

## Business Value

This project transforms transactional library data into a structured data warehouse that supports:

- trend analysis  
- procurement planning  
- borrowing demand analysis  
- sales performance monitoring  
- supplier management  
- better business decisions through dimensional reporting  

---

## Notes

- The execution order of scripts is important.  
- The report PDF and ZIP archive are intentionally excluded from the repository.  
- This repository is intended for academic and portfolio purposes.  
