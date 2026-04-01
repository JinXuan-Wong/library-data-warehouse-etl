SPOOL "C:\Users\wongj\Documents\BorrowingTrend_Report1.txt"

SET LINESIZE 130
SET PAGESIZE 35
SET TRIMSPOOL ON
SET VERIFY OFF
SET SQLBLANKLINES ON
SET WRAP OFF
SET TAB OFF
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY';

PROMPT === Borrowing Trend Parameters ===
ACCEPT start_year NUMBER DEFAULT 2023 PROMPT 'Enter START year (YYYY) [2023]: '
ACCEPT end_year   NUMBER DEFAULT 2025 PROMPT 'Enter END year (YYYY)   [2025]: '

COLUMN run_dt NEW_VALUE run_dt
SELECT TO_CHAR(SYSDATE,'DD-MON-YYYY') run_dt FROM dual;

COLUMN sep_line NEW_VALUE sep_line NOPRINT
SELECT RPAD('_', 130, '_') AS sep_line FROM dual;

TTITLE LEFT ' ' CENTER 'Quarterly and Monthly Borrowing Trend Analysis &start_year -- &end_year' -
       SKIP 1 RIGHT 'Page ' FORMAT 999 SQL.PNO SKIP 1 LEFT 'Date: &run_dt' SKIP 2
BTITLE CENTER '&sep_line'

-- ===================== Compact column formats (fit within 130 chars) =====================
CLEAR COLUMNS
COLUMN "Year"         HEADING 'Year'                 FORMAT 9999
COLUMN period_label   HEADING 'Period'               FORMAT A12
COLUMN borrows        HEADING 'Borrows|(count)'      FORMAT 999,999,999
COLUMN last_period    HEADING 'Last|Period'          FORMAT 999,999,999
COLUMN pct_vs_last    HEADING 'Change %|vs Last'     FORMAT 999990.00
COLUMN ma3            HEADING '3-Month|Moving Avg'   FORMAT 999,999,999.99
COLUMN season_var     HEADING 'Seasonal|Index %'     FORMAT A12 JUSTIFY RIGHT
COLUMN net_avail      HEADING 'Net Copies|Available' FORMAT 999,999,999
COLUMN top_genre      HEADING 'Top|Genre'            FORMAT A18
COLUMN festive_events HEADING 'Holiday|Month'        FORMAT A10 JUSTIFY CENTER
COLUMN yr_group NOPRINT

-- ===================== Breaks & (no computed totals) =====================
CLEAR BREAKS
CLEAR COMPUTES
BREAK ON yr_group SKIP 1 ON REPORT

-- ===================== Hierarchical report =====================
WITH
lib_cap AS (
  SELECT COUNT(*) AS total_copies
  FROM BookCopies
  WHERE UPPER(NVL(bookStatus,'AVAILABLE')) <> 'UNAVAILABLE'
),
base AS (  -- borrowing dates in range
  SELECT d.cal_date,
         EXTRACT(YEAR  FROM d.cal_date) AS yr,
         EXTRACT(MONTH FROM d.cal_date) AS mon
  FROM FactBorrowing fb
  JOIN DimDate d ON d.dateKey = fb.dateKey
  WHERE EXTRACT(YEAR FROM d.cal_date) BETWEEN &start_year AND &end_year
),
m AS (     -- monthly borrow counts
  SELECT yr, mon,
         TRUNC(cal_date,'MM')           AS month_start_dt,
         LAST_DAY(TRUNC(cal_date,'MM')) AS month_end_dt,
         COUNT(*)                       AS borrow_cnt
  FROM base
  GROUP BY yr, mon, TRUNC(cal_date,'MM'), LAST_DAY(TRUNC(cal_date,'MM'))
),
moy AS (  -- average by month-of-year (seasonality baseline)
  SELECT mon AS mon_of_year, AVG(borrow_cnt) AS moy_avg
  FROM m
  GROUP BY mon
),
overall AS (  -- overall mean of monthly averages
  SELECT AVG(moy_avg) AS overall_avg
  FROM moy
),
m_active AS (  -- active loans at month-end
  SELECT m.month_start_dt, COUNT(*) AS active_loans_end
  FROM m
  JOIN BorrowedBooks bb
    ON bb.borrowDate <= m.month_end_dt
   AND (bb.returnDate IS NULL OR bb.returnDate > m.month_end_dt)
  GROUP BY m.month_start_dt
),
/* Top genre per month (ties kept, joined with '/') */
mg AS (
  SELECT EXTRACT(YEAR  FROM d.cal_date) AS yr,
         EXTRACT(MONTH FROM d.cal_date) AS mon,
         b.genre,
         COUNT(*) AS borrow_cnt
  FROM FactBorrowing fb
  JOIN DimDate d ON d.dateKey = fb.dateKey
  JOIN DimBook b ON b.bookKey = fb.bookKey
  WHERE EXTRACT(YEAR FROM d.cal_date) BETWEEN &start_year AND &end_year
  GROUP BY EXTRACT(YEAR FROM d.cal_date), EXTRACT(MONTH FROM d.cal_date), b.genre
),
top_gen AS (
  SELECT yr, mon,
         LISTAGG(genre, '/') WITHIN GROUP (ORDER BY genre) AS top_genre
  FROM (
    SELECT yr, mon, genre,
           RANK() OVER (PARTITION BY yr, mon ORDER BY borrow_cnt DESC) AS rnk
    FROM mg
  )
  WHERE rnk = 1
  GROUP BY yr, mon
),
/* NEW: Yes/No holiday flag per (year, month) */
m_hol AS (
  SELECT
    EXTRACT(YEAR  FROM d.cal_date) AS yr,
    EXTRACT(MONTH FROM d.cal_date) AS mon,
    CASE WHEN MAX(CASE WHEN d.holiday_indicator = 'Y' THEN 1 ELSE 0 END) = 1
         THEN 'Yes' ELSE 'No' END AS holiday_month
  FROM DimDate d
  WHERE EXTRACT(YEAR FROM d.cal_date) BETWEEN &start_year AND &end_year
  GROUP BY EXTRACT(YEAR FROM d.cal_date), EXTRACT(MONTH FROM d.cal_date)
),
m_stats AS (  -- monthly stats + seasonality + capacity + top genre + holiday flag
  SELECT
    m.yr,
    m.mon,
    CEIL(m.mon/3) AS qtr_num,
    MOD(m.mon-1,3)+1 AS mon_in_qtr,
    m.month_start_dt,
    m.month_end_dt,
    m.borrow_cnt,
    LAG(m.borrow_cnt) OVER (PARTITION BY m.yr ORDER BY m.month_start_dt) AS prev_month,
    ROUND(
      (m.borrow_cnt - LAG(m.borrow_cnt) OVER (PARTITION BY m.yr ORDER BY m.month_start_dt))
      / NULLIF(LAG(m.borrow_cnt) OVER (PARTITION BY m.yr ORDER BY m.month_start_dt),0) * 100, 2
    ) AS pct_vs_last_month,
    ROUND(AVG(m.borrow_cnt) OVER (
            PARTITION BY m.yr ORDER BY m.month_start_dt
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS ma3,
    ROUND(moy.moy_avg / NULLIF((SELECT overall_avg FROM overall),0) * 100 - 100, 2) AS season_index_pct,
    (SELECT total_copies FROM lib_cap) - NVL(ma.active_loans_end,0) AS net_avail,
    NVL(tg.top_genre, NULL) AS top_genre,
    h.holiday_month AS festive_events,
    ROW_NUMBER() OVER (PARTITION BY m.yr ORDER BY m.month_start_dt) AS rn_year
  FROM m
  JOIN moy ON moy.mon_of_year = m.mon
  LEFT JOIN m_active ma ON ma.month_start_dt = m.month_start_dt
  LEFT JOIN top_gen tg ON tg.yr = m.yr AND tg.mon = m.mon
  LEFT JOIN m_hol  h  ON h.yr  = m.yr AND h.mon = m.mon
),
q_end AS (
  SELECT yr, CEIL(mon/3) AS qtr_num, MAX(month_end_dt) AS qtr_end_dt
  FROM m
  GROUP BY yr, CEIL(mon/3)
),
q_active AS (
  SELECT qe.yr, qe.qtr_num, COUNT(*) AS active_loans_end
  FROM q_end qe
  JOIN BorrowedBooks bb
    ON bb.borrowDate <= qe.qtr_end_dt
   AND (bb.returnDate IS NULL OR bb.returnDate > qe.qtr_end_dt)
  GROUP BY qe.yr, qe.qtr_num
),
q_stats AS (  -- quarterly aggregates
  SELECT
    ms.yr,
    ms.qtr_num,
    SUM(ms.borrow_cnt)                                                    AS qtr_borrow_cnt,
    LAG(SUM(ms.borrow_cnt)) OVER (PARTITION BY ms.yr ORDER BY ms.qtr_num) AS prev_qtr,
    ROUND(
      (SUM(ms.borrow_cnt) - LAG(SUM(ms.borrow_cnt)) OVER (PARTITION BY ms.yr ORDER BY ms.qtr_num))
      / NULLIF(LAG(SUM(ms.borrow_cnt)) OVER (PARTITION BY ms.yr ORDER BY ms.qtr_num),0) * 100, 2
    ) AS pct_vs_last_qtr,
    (SELECT total_copies FROM lib_cap) - NVL(MAX(qa.active_loans_end),0)   AS net_avail_qtr
  FROM m_stats ms
  LEFT JOIN q_active qa
    ON qa.yr = ms.yr AND qa.qtr_num = ms.qtr_num
  GROUP BY ms.yr, ms.qtr_num
),
year_tot AS (  -- yearly totals (for footer band)
  SELECT yr, SUM(qtr_borrow_cnt) AS year_borrow_total
  FROM q_stats
  GROUP BY yr
)

SELECT
  ysort                         AS yr_group,   -- hidden break key (NOPRINT)
  yr_display                    AS "Year",
  period_label,
  borrows,
  last_period,
  pct_vs_last,
  ma3,
  season_var,
  net_avail,
  top_genre,
  festive_events
FROM (

  /* Month rows — show Year + Quarter on the FIRST month in each quarter */
  SELECT
    CASE WHEN ms.rn_year = 1 THEN ms.yr END       AS yr_display,
    CASE
      WHEN ms.mon_in_qtr = 1 THEN
          RPAD('Q' || ms.qtr_num, 6, ' ')
          || TO_CHAR(ADD_MONTHS(DATE '2000-01-01', ms.mon-1), 'Mon')
      ELSE
          '      ' || TO_CHAR(ADD_MONTHS(DATE '2000-01-01', ms.mon-1), 'Mon')
    END                                                         AS period_label,
    ms.borrow_cnt                                               AS borrows,
    ms.prev_month                                               AS last_period,
    ms.pct_vs_last_month                                        AS pct_vs_last,
    ms.ma3                                                      AS ma3,
    '    ' || TO_CHAR(ms.season_index_pct, 'SFM990.00') || '%'  AS season_var,
    ms.net_avail                                                AS net_avail,
    ms.top_genre                                                AS top_genre,
    ms.festive_events                                           AS festive_events,
    ms.yr                                                       AS ysort,
    ms.qtr_num                                                  AS qsort,
    ms.mon_in_qtr                                               AS ord_in_qtr
  FROM m_stats ms

  UNION ALL

  /* Separator BEFORE quarter totals */
  SELECT
    CAST(NULL AS NUMBER)                    AS yr_display,
    RPAD('-',12,'-')                        AS period_label,
    CAST(NULL AS NUMBER)                    AS borrows,
    CAST(NULL AS NUMBER)                    AS last_period,
    CAST(NULL AS NUMBER)                    AS pct_vs_last,
    CAST(NULL AS NUMBER)                    AS ma3,
    CAST(NULL AS VARCHAR2(12))              AS season_var,
    CAST(NULL AS NUMBER)                    AS net_avail,
    CAST(NULL AS VARCHAR2(18))              AS top_genre,
    CAST(NULL AS VARCHAR2(10))              AS festive_events,
    q.yr                                    AS ysort,
    q.qtr_num                               AS qsort,
    90                                      AS ord_in_qtr
  FROM q_stats q

  UNION ALL

  /* Quarter totals row AFTER the months (no Year here anymore) */
  SELECT
    CAST(NULL AS NUMBER)                    AS yr_display,
    'Q' || q.qtr_num || ' Total'            AS period_label,
    q.qtr_borrow_cnt                        AS borrows,
    q.prev_qtr                              AS last_period,
    q.pct_vs_last_qtr                       AS pct_vs_last,
    CAST(NULL AS NUMBER)                    AS ma3,
    CAST(NULL AS VARCHAR2(12))              AS season_var,
    q.net_avail_qtr                         AS net_avail,
    CAST(NULL AS VARCHAR2(18))              AS top_genre,
    CAST(NULL AS VARCHAR2(10))              AS festive_events,
    q.yr                                    AS ysort,
    q.qtr_num                               AS qsort,
    91                                      AS ord_in_qtr
  FROM q_stats q

  UNION ALL

  /* Blank spacer AFTER quarter totals */
  SELECT
    CAST(NULL AS NUMBER)                    AS yr_display,
    ' '                                     AS period_label,
    CAST(NULL AS NUMBER)                    AS borrows,
    CAST(NULL AS NUMBER)                    AS last_period,
    CAST(NULL AS NUMBER)                    AS pct_vs_last,
    CAST(NULL AS NUMBER)                    AS ma3,
    CAST(NULL AS VARCHAR2(12))              AS season_var,
    CAST(NULL AS NUMBER)                    AS net_avail,
    CAST(NULL AS VARCHAR2(18))              AS top_genre,
    CAST(NULL AS VARCHAR2(10))              AS festive_events,
    q.yr                                    AS ysort,
    q.qtr_num                               AS qsort,
    92                                      AS ord_in_qtr
  FROM q_stats q

  UNION ALL

  /* Year subtotal band */
  SELECT
    CAST(NULL AS NUMBER)                    AS yr_display,
    RPAD('*',12,'*')                        AS period_label,
    CAST(NULL AS NUMBER)                    AS borrows,
    CAST(NULL AS NUMBER)                    AS last_period,
    CAST(NULL AS NUMBER)                    AS pct_vs_last,
    CAST(NULL AS NUMBER)                    AS ma3,
    CAST(NULL AS VARCHAR2(12))              AS season_var,
    CAST(NULL AS NUMBER)                    AS net_avail,
    CAST(NULL AS VARCHAR2(18))              AS top_genre,
    CAST(NULL AS VARCHAR2(10))              AS festive_events,
    yt.yr                                   AS ysort,
    98                                      AS qsort,
    98                                      AS ord_in_qtr
  FROM year_tot yt

  UNION ALL
  SELECT
    CAST(NULL AS NUMBER)                    AS yr_display,
    RPAD('Total',12,' ')                    AS period_label,
    yt.year_borrow_total                    AS borrows,
    CAST(NULL AS NUMBER)                    AS last_period,
    CAST(NULL AS NUMBER)                    AS pct_vs_last,
    CAST(NULL AS NUMBER)                    AS ma3,
    CAST(NULL AS VARCHAR2(12))              AS season_var,
    CAST(NULL AS NUMBER)                    AS net_avail,
    CAST(NULL AS VARCHAR2(18))              AS top_genre,
    CAST(NULL AS VARCHAR2(10))              AS festive_events,
    yt.yr                                   AS ysort,
    99                                      AS qsort,
    99                                      AS ord_in_qtr
  FROM year_tot yt

  UNION ALL

  /* Grand Total */
  SELECT
    CAST(NULL AS NUMBER)                    AS yr_display,
    RPAD('Grand Total',12,' ')              AS period_label,
    (SELECT SUM(year_borrow_total) FROM year_tot) AS borrows,
    CAST(NULL AS NUMBER)                    AS last_period,
    CAST(NULL AS NUMBER)                    AS pct_vs_last,
    CAST(NULL AS NUMBER)                    AS ma3,
    CAST(NULL AS VARCHAR2(12))              AS season_var,
    CAST(NULL AS NUMBER)                    AS net_avail,
    CAST(NULL AS VARCHAR2(18))              AS top_genre,
    CAST(NULL AS VARCHAR2(10))              AS festive_events,
    9999                                    AS ysort,
    99                                      AS qsort,
    999                                     AS ord_in_qtr
  FROM dual
)
ORDER BY ysort, qsort, ord_in_qtr;

TTITLE OFF
BTITLE OFF

PROMPT
PROMPT Legend:
PROMPT - Borrows = loan count.
PROMPT - Last Period = previous month / previous quarter.
PROMPT - Change % = vs Last.
PROMPT - 3-Month Moving Avg = trailing 3 months.
PROMPT - Seasonal Index % = month strength vs overall.
PROMPT - Net Copies Available = in-service book copies minus active loans.
PROMPT - Top Genre = most-borrowed genre for the month.
PROMPT - Holiday Month = Yes if any public holiday occurs in that month.
PROMPT


SPOOL OFF
