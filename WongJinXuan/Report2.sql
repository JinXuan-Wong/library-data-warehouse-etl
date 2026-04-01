SPOOL "C:\Users\wongj\Documents\BorrowVsSales_Genre_Report2.txt"

SET LINESIZE 130
SET PAGESIZE 35
SET TRIMSPOOL ON
SET VERIFY OFF
SET SQLBLANKLINES ON
SET WRAP OFF
SET TAB OFF
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY';

PROMPT === Borrow vs Sales Analysis Parameters ===
ACCEPT start_year NUMBER DEFAULT 2022 PROMPT 'Enter START year (YYYY) [2022]: '
ACCEPT end_year   NUMBER DEFAULT 2025 PROMPT 'Enter END year (YYYY)   [2025]: '

COLUMN run_dt NEW_VALUE run_dt
SELECT TO_CHAR(SYSDATE,'DD-MON-YYYY') run_dt FROM dual;

COLUMN sep_line NEW_VALUE sep_line NOPRINT
SELECT RPAD('_', 130, '_') AS sep_line FROM dual;

TTITLE LEFT ' ' CENTER 'Sales and Borrowing Preference Analysis by Year and Genre &start_year -- &end_year' -
       SKIP 1 RIGHT 'Page ' FORMAT 999 SQL.PNO SKIP 1 LEFT 'Date: &run_dt' SKIP 2
BTITLE CENTER '&sep_line'

-- ===== Column formats =====
CLEAR COLUMNS
COLUMN "Year"          HEADING 'Year'          FORMAT A17
COLUMN genre           HEADING 'Genre'         FORMAT A20
COLUMN borrow_cnt      HEADING 'Borrow|Count'  FORMAT 999,999
COLUMN sales_cnt       HEADING 'Sales|Count'   FORMAT 999,999
COLUMN borrow_pct      HEADING 'Borrow %'      FORMAT 990.00
COLUMN sales_pct       HEADING 'Sales %'       FORMAT 990.00
COLUMN revenue         HEADING 'Sales|Revenue' FORMAT 999,999,990.00
COLUMN male_pct        HEADING 'Member`s|Male %'        FORMAT 990.00
COLUMN female_pct      HEADING 'Gender|Female %'      FORMAT 990.00
COLUMN preference      HEADING 'Preference'    FORMAT A18

-- ===== Only show Year once per group; show grand totals at very end =====
CLEAR BREAKS
CLEAR COMPUTES
BREAK ON "Year" SKIP 1 ON REPORT
COMPUTE SUM LABEL 'Grand Total:' OF borrow_cnt sales_cnt revenue ON REPORT

-- ===== Base (Oracle 11g safe) =====
WITH
sales AS (
  SELECT d.cal_year,
         b.genre,
         COUNT(fs.sales_id)         AS sales_cnt,
         SUM(fs.line_total)         AS revenue,
         COUNT(DISTINCT CASE WHEN m.memberGender = 'M' THEN m.memberKey END) AS male_sales,
         COUNT(DISTINCT CASE WHEN m.memberGender = 'F' THEN m.memberKey END) AS female_sales
  FROM FactSales fs
  JOIN DimDate    d ON d.dateKey = fs.dateKey
  JOIN DimBook    b ON b.bookKey = fs.bookKey
  JOIN DimMembers m ON m.memberKey = fs.memberKey
  WHERE d.cal_year BETWEEN &start_year AND &end_year
  GROUP BY d.cal_year, b.genre
),
borrows AS (
  SELECT d.cal_year,
         b.genre,
         COUNT(*) AS borrow_cnt,
         COUNT(DISTINCT CASE WHEN m.memberGender = 'M' THEN m.memberKey END) AS male_borrow,
         COUNT(DISTINCT CASE WHEN m.memberGender = 'F' THEN m.memberKey END) AS female_borrow
  FROM FactBorrowing fb
  JOIN DimDate    d ON d.dateKey = fb.dateKey
  JOIN DimBook    b ON b.bookKey = fb.bookKey
  JOIN DimMembers m ON m.memberKey = fb.memberKey
  WHERE d.cal_year BETWEEN &start_year AND &end_year
  GROUP BY d.cal_year, b.genre
),
combined AS (
  SELECT NVL(s.cal_year, b.cal_year) AS cal_year,
         NVL(s.genre,    b.genre)    AS genre,
         NVL(b.borrow_cnt,0)         AS borrow_cnt,
         NVL(s.sales_cnt,0)          AS sales_cnt,
         NVL(s.revenue,0)            AS revenue,
         NVL(s.male_sales,0)  + NVL(b.male_borrow,0)    AS male_cnt,
         NVL(s.female_sales,0)+ NVL(b.female_borrow,0)  AS female_cnt
  FROM sales s
  FULL OUTER JOIN borrows b
    ON s.cal_year = b.cal_year
   AND s.genre    = b.genre
),
detail AS (
  SELECT
    cal_year,
    genre,
    borrow_cnt,
    sales_cnt,
    revenue,
    ROUND(borrow_cnt / NULLIF(borrow_cnt + sales_cnt, 0) * 100, 2) AS borrow_pct,
    ROUND(sales_cnt  / NULLIF(borrow_cnt + sales_cnt, 0) * 100, 2) AS sales_pct,
    ROUND(male_cnt   / NULLIF(male_cnt + female_cnt, 0) * 100, 2)  AS male_pct,
    ROUND(female_cnt / NULLIF(male_cnt + female_cnt, 0) * 100, 2)  AS female_pct,
    CASE
      WHEN borrow_cnt > sales_cnt * 1.10 THEN 'Borrowing Higher'
      WHEN sales_cnt  > borrow_cnt * 1.10 THEN 'Sales Higher'
      ELSE 'Balanced'
    END AS preference
  FROM combined
),
year_tot AS (   -- recompute % from totals (not averages)
  SELECT
    cal_year,
    'Total' AS genre,
    SUM(borrow_cnt) AS borrow_cnt,
    SUM(sales_cnt)  AS sales_cnt,
    SUM(revenue)    AS revenue,
    -- For demographics, recompute from distinct participants across the year.
    -- If you prefer distinct members across all genres for the year,
    -- switch to a separate subquery. Here we approximate from sums:
    SUM(male_cnt)   AS male_cnt,
    SUM(female_cnt) AS female_cnt
  FROM combined
  GROUP BY cal_year
),
year_tot_fmt AS (
  SELECT
    cal_year,
    '===================' AS genre,
    NULL AS borrow_cnt,
    NULL AS sales_cnt,
    NULL AS revenue,
    NULL AS borrow_pct,
    NULL AS sales_pct,
    NULL AS male_pct,
    NULL AS female_pct,
    NULL AS preference
  FROM year_tot
  UNION ALL
  SELECT
    cal_year,
    'Total' AS genre,
    borrow_cnt,
    sales_cnt,
    revenue,
    ROUND(borrow_cnt / NULLIF(borrow_cnt + sales_cnt, 0) * 100, 2) AS borrow_pct,
    ROUND(sales_cnt  / NULLIF(borrow_cnt + sales_cnt, 0) * 100, 2) AS sales_pct,
    ROUND(male_cnt   / NULLIF(male_cnt + female_cnt, 0) * 100, 2)  AS male_pct,
    ROUND(female_cnt / NULLIF(male_cnt + female_cnt, 0) * 100, 2)  AS female_pct,
    CASE
      WHEN borrow_cnt > sales_cnt * 1.10 THEN 'Borrowing Higher'
      WHEN sales_cnt  > borrow_cnt * 1.10 THEN 'Sales Higher'
      ELSE 'Balanced'
    END AS preference
  FROM year_tot
)

-- ===== Final output: details, then a "Total" row per year at bottom =====
SELECT *
FROM (
  SELECT
    TO_CHAR(d.cal_year) AS "Year",
    d.genre,
    d.borrow_cnt,
    d.sales_cnt,
    d.borrow_pct,
    d.sales_pct,
    d.revenue,
    d.male_pct,
    d.female_pct,
    d.preference
  FROM detail d

  UNION ALL

  SELECT
    TO_CHAR(t.cal_year) AS "Year",
    t.genre,
    t.borrow_cnt,
    t.sales_cnt,
    t.borrow_pct,
    t.sales_pct,
    t.revenue,
    t.male_pct,
    t.female_pct,
    t.preference
  FROM year_tot_fmt t
)
-- Order by: 1 = Year, put 'Total' after all genres in that year, then by Genre
ORDER BY 1,
         CASE WHEN genre = '===================' THEN 1
              WHEN genre = 'Total'      THEN 2
              ELSE 0 END,
         2;


TTITLE OFF
BTITLE OFF

PROMPT
PROMPT Legend: 
PROMPT • "Year" prints once; genres list under it. A "Total" row appears at the end of each year.
PROMPT • Borrow Count = number of borrowing transactions; Sales Count = number of sales transactions.
PROMPT • Sales Revenue = total sales amount (from line_total).
PROMPT • Borrow % = Borrow Count / (Borrow Count + Sales Count) × 100.
PROMPT • Sales  % = Sales Count  / (Borrow Count + Sales Count) × 100.
PROMPT • Gender % = share of distinct members (M/F) who borrowed or bought for that line.
PROMPT 
PROMPT • Preference (10% rule):
PROMPT   – Borrowing Higher: Borrow Count > 110% of Sales Count
PROMPT   – Sales Higher:     Sales Count  > 110% of Borrow Count
PROMPT   – Balanced:         Borrow/Sales between 0.91 and 1.10 (inclusive);
PROMPT
PROMPT • Preference Near-50% view (derived from 10% count gap):
PROMPT   – Borrowing Higher: Borrow % ≥ 52.38%
PROMPT   – Sales Higher:     Borrow % ≤ 47.62%
PROMPT   – Balanced:         Borrow % between 47.62% and 52.38% (inclusive);
PROMPT

SPOOL OFF
