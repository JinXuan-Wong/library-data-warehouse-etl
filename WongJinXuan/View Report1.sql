CREATE OR REPLACE VIEW VW_RPT1_BORROWING_TREND AS
/* Borrowing Trend — Monthly and Quarterly, star schema
   Output columns are friendly for BI:
   - GRAIN: 'MONTH' or 'QUARTER'
   - YEAR, QUARTER_NUM, MONTH_NUM, YEAR_MONTH, YEAR_QUARTER
   - PERIOD_START_DATE, PERIOD_END_DATE
   - BORROWS, PREV_PERIOD_BORROWS, PCT_VS_PREV, MOVING_AVG_3, SEASONAL_INDEX_PCT
   - ACTIVE_LOANS_END, NET_COPIES_AVAILABLE
   - TOP_GENRE, FESTIVE_EVENTS (MONTH only, now 'Yes'/'No')
*/
WITH
/* ================= Library capacity (copies in service) ================ */
lib_cap AS (
  SELECT COUNT(*) AS total_copies
  FROM BookCopies
  WHERE UPPER(NVL(bookStatus,'AVAILABLE')) <> 'UNAVAILABLE'
),

/* ================= Monthly counts from star schema ===================== */
m_cnt AS (
  SELECT
    EXTRACT(YEAR  FROM d.cal_date)                AS yr,
    EXTRACT(MONTH FROM d.cal_date)                AS mon,
    TRUNC(d.cal_date,'MM')                        AS month_start_dt,
    LAST_DAY(TRUNC(d.cal_date,'MM'))              AS month_end_dt,
    COUNT(*)                                      AS borrow_cnt
  FROM FactBorrowing fb
  JOIN DimDate d ON d.dateKey = fb.dateKey
  GROUP BY EXTRACT(YEAR  FROM d.cal_date),
           EXTRACT(MONTH FROM d.cal_date),
           TRUNC(d.cal_date,'MM'),
           LAST_DAY(TRUNC(d.cal_date,'MM'))
),

/* Average by month-of-year (seasonality baseline, across all years) */
moy AS (
  SELECT mon AS mon_of_year, AVG(borrow_cnt) AS moy_avg
  FROM m_cnt
  GROUP BY mon
),
overall AS (
  SELECT AVG(moy_avg) AS overall_avg FROM moy
),

/* Active loans at the end of each month */
m_active AS (
  SELECT c.month_start_dt, COUNT(*) AS active_loans_end
  FROM m_cnt c
  JOIN BorrowedBooks bb
    ON bb.borrowDate <= c.month_end_dt
   AND (bb.returnDate IS NULL OR bb.returnDate > c.month_end_dt)
  GROUP BY c.month_start_dt
),

/* Top genre by month (ties included, “/”-joined) */
mg AS (
  SELECT EXTRACT(YEAR FROM d.cal_date) AS yr,
         EXTRACT(MONTH FROM d.cal_date) AS mon,
         b.genre, COUNT(*) AS borrow_cnt
  FROM FactBorrowing fb
  JOIN DimDate d ON d.dateKey = fb.dateKey
  JOIN DimBook b ON b.bookKey = fb.bookKey
  GROUP BY EXTRACT(YEAR FROM d.cal_date),
           EXTRACT(MONTH FROM d.cal_date),
           b.genre
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

/* === Month-level holiday presence (Yes/No); handles multiple holidays === */
m_hol AS (
  SELECT
    TRUNC(d.cal_date,'MM') AS month_start_dt,
    CASE WHEN MAX(CASE WHEN d.holiday_indicator = 'Y' THEN 1 ELSE 0 END) = 1
         THEN 'Yes' ELSE 'No' END AS festive_events
  FROM DimDate d
  GROUP BY TRUNC(d.cal_date,'MM')
),

/* Monthly stats bundle */
m_stats AS (
  SELECT
    m.yr,
    m.mon,
    CEIL(m.mon/3)                                        AS qtr_num,
    m.month_start_dt,
    m.month_end_dt,
    m.borrow_cnt,
    LAG(m.borrow_cnt) OVER (PARTITION BY m.yr ORDER BY m.month_start_dt) AS prev_month,
    ROUND(
      (m.borrow_cnt - LAG(m.borrow_cnt) OVER (PARTITION BY m.yr ORDER BY m.month_start_dt))
      / NULLIF(LAG(m.borrow_cnt) OVER (PARTITION BY m.yr ORDER BY m.month_start_dt),0) * 100, 2
    )                                                    AS pct_vs_prev_month,
    ROUND(AVG(m.borrow_cnt) OVER (
      PARTITION BY m.yr
      ORDER BY m.month_start_dt
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2)                                               AS moving_avg_3,
    ROUND(moy.moy_avg / NULLIF((SELECT overall_avg FROM overall),0) * 100 - 100, 2)
                                                        AS seasonal_index_pct,
    NVL(ma.active_loans_end,0)                          AS active_loans_end,
    (SELECT total_copies FROM lib_cap) - NVL(ma.active_loans_end,0)
                                                        AS net_copies_available,
    NVL(tg.top_genre, NULL)                             AS top_genre,
    mh.festive_events                                    AS festive_events   -- 'Yes'/'No'
  FROM m_cnt m
  JOIN moy ON moy.mon_of_year = m.mon
  LEFT JOIN m_active ma ON ma.month_start_dt = m.month_start_dt
  LEFT JOIN top_gen tg ON tg.yr = m.yr AND tg.mon = m.mon
  LEFT JOIN m_hol  mh ON mh.month_start_dt = m.month_start_dt
),

/* ================= Quarterly rollups from monthly ===================== */
q_cnt AS (
  SELECT ms.yr, ms.qtr_num,
         MIN(ms.month_start_dt) AS qtr_start_dt,
         MAX(ms.month_end_dt)   AS qtr_end_dt,
         SUM(ms.borrow_cnt)     AS qtr_borrow_cnt
  FROM m_stats ms
  GROUP BY ms.yr, ms.qtr_num
),
q_active AS (
  SELECT q.yr, q.qtr_num, COUNT(*) AS active_loans_end
  FROM q_cnt q
  JOIN BorrowedBooks bb
    ON bb.borrowDate <= q.qtr_end_dt
   AND (bb.returnDate IS NULL OR bb.returnDate > q.qtr_end_dt)
  GROUP BY q.yr, q.qtr_num
),
q_stats AS (
  SELECT
    q.yr, q.qtr_num, q.qtr_start_dt, q.qtr_end_dt, q.qtr_borrow_cnt,
    LAG(q.qtr_borrow_cnt) OVER (PARTITION BY q.yr ORDER BY q.qtr_num) AS prev_qtr,
    ROUND(
      (q.qtr_borrow_cnt - LAG(q.qtr_borrow_cnt) OVER (PARTITION BY q.yr ORDER BY q.qtr_num))
      / NULLIF(LAG(q.qtr_borrow_cnt) OVER (PARTITION BY q.yr ORDER BY q.qtr_num),0) * 100, 2
    ) AS pct_vs_prev_qtr,
    NVL(a.active_loans_end,0) AS active_loans_end,
    (SELECT total_copies FROM lib_cap) - NVL(a.active_loans_end,0)
      AS net_copies_available
  FROM q_cnt q
  LEFT JOIN q_active a ON a.yr = q.yr AND a.qtr_num = q.qtr_num
)
SELECT
  'MONTH' AS grain,
  ms.yr   AS year,
  ms.qtr_num AS quarter_num,
  ms.mon  AS month_num,
  TO_CHAR(ms.month_start_dt,'YYYY-MM') AS year_month,
  NULL    AS year_quarter,
  ms.month_start_dt AS period_start_date,
  ms.month_end_dt   AS period_end_date,
  ms.borrow_cnt     AS borrows,
  ms.prev_month     AS prev_period_borrows,
  ms.pct_vs_prev_month AS pct_vs_prev,
  ms.moving_avg_3       AS moving_avg_3,
  ms.seasonal_index_pct AS seasonal_index_pct,
  ms.active_loans_end   AS active_loans_end,
  ms.net_copies_available AS net_copies_available,
  ms.top_genre          AS top_genre,
  ms.festive_events     AS festive_events      -- 'Yes' or 'No'
FROM m_stats ms
UNION ALL
SELECT
  'QUARTER' AS grain,
  qs.yr     AS year,
  qs.qtr_num AS quarter_num,
  NULL      AS month_num,
  NULL      AS year_month,
  TO_CHAR(qs.yr) || '-Q' || qs.qtr_num AS year_quarter,
  qs.qtr_start_dt AS period_start_date,
  qs.qtr_end_dt   AS period_end_date,
  qs.qtr_borrow_cnt AS borrows,
  qs.prev_qtr       AS prev_period_borrows,
  qs.pct_vs_prev_qtr AS pct_vs_prev,
  CAST(NULL AS NUMBER) AS moving_avg_3,
  CAST(NULL AS NUMBER) AS seasonal_index_pct,
  qs.active_loans_end AS active_loans_end,
  qs.net_copies_available AS net_copies_available,
  CAST(NULL AS VARCHAR2(4000)) AS top_genre,
  CAST(NULL AS VARCHAR2(4000)) AS festive_events   -- month-only
FROM q_stats qs;


CREATE OR REPLACE VIEW VW_RPT1_BORROWING_TREND_M AS
/* Borrowing Trend – MONTH grain (star schema)
   Columns: YEAR, QUARTER_NUM, MONTH_NUM, MONTH_NAME, YEAR_MONTH, YEAR_MONTH_KEY
            PERIOD_START_DATE, PERIOD_END_DATE
            BORROWS
            PREV_MONTH_BORROWS, MOM_PCT
            PREV_YEAR_BORROWS, YOY_PCT
            MOVING_AVG_3, SEASONAL_INDEX_PCT
            ACTIVE_LOANS_END, NET_COPIES_AVAILABLE
            TOP_GENRE, FESTIVE_EVENTS (now 'Yes'/'No')
*/
WITH
-- Copies in service (exclude UNAVAILABLE)
lib_cap AS (
  SELECT COUNT(*) AS total_copies
  FROM BookCopies
  WHERE UPPER(NVL(bookStatus,'AVAILABLE')) <> 'UNAVAILABLE'
),

-- Monthly borrow counts from star schema
m_cnt AS (
  SELECT
    TRUNC(d.cal_date,'MM')             AS month_start_dt,
    LAST_DAY(TRUNC(d.cal_date,'MM'))   AS month_end_dt,
    EXTRACT(YEAR  FROM d.cal_date)     AS yr,
    EXTRACT(MONTH FROM d.cal_date)     AS mon,
    COUNT(*)                           AS borrow_cnt
  FROM FactBorrowing fb
  JOIN DimDate d ON d.dateKey = fb.dateKey
  GROUP BY TRUNC(d.cal_date,'MM'),
           LAST_DAY(TRUNC(d.cal_date,'MM')),
           EXTRACT(YEAR  FROM d.cal_date),
           EXTRACT(MONTH FROM d.cal_date)
),

-- Seasonality baseline across all years
moy AS (
  SELECT mon AS mon_of_year, AVG(borrow_cnt) AS moy_avg
  FROM m_cnt
  GROUP BY mon
),
overall AS (
  SELECT AVG(moy_avg) AS overall_avg FROM moy
),

-- Loans still active at the end of each month
m_active AS (
  SELECT c.month_start_dt, COUNT(*) AS active_loans_end
  FROM m_cnt c
  JOIN BorrowedBooks bb
    ON bb.borrowDate <= c.month_end_dt
   AND (bb.returnDate IS NULL OR bb.returnDate > c.month_end_dt)
  GROUP BY c.month_start_dt
),

-- Top genre for the month (ties kept, '/' joined)
mg AS (
  SELECT TRUNC(d.cal_date,'MM') AS month_start_dt,
         b.genre, COUNT(*) AS cnt
  FROM FactBorrowing fb
  JOIN DimDate d ON d.dateKey = fb.dateKey
  JOIN DimBook b ON b.bookKey = fb.bookKey
  GROUP BY TRUNC(d.cal_date,'MM'), b.genre
),
top_gen AS (
  SELECT month_start_dt,
         LISTAGG(genre, '/') WITHIN GROUP (ORDER BY genre) AS top_genre
  FROM (
    SELECT month_start_dt, genre,
           RANK() OVER (PARTITION BY month_start_dt ORDER BY cnt DESC) rnk
    FROM mg
  )
  WHERE rnk = 1
  GROUP BY month_start_dt
),

-- === Month-level holiday presence (Yes/No) ===
m_hol AS (
  SELECT
    TRUNC(d.cal_date,'MM') AS month_start_dt,
    CASE WHEN MAX(CASE WHEN d.holiday_indicator = 'Y' THEN 1 ELSE 0 END) = 1
         THEN 'Yes' ELSE 'No' END AS festive_events
  FROM DimDate d
  GROUP BY TRUNC(d.cal_date,'MM')
)

SELECT
  c.yr AS year,
  CEIL(c.mon/3) AS quarter_num,
  c.mon AS month_num,
  TO_CHAR(c.month_start_dt,'Mon') AS month_name,
  TO_CHAR(c.month_start_dt,'YYYY-MM') AS year_month,
  (EXTRACT(YEAR FROM c.month_start_dt)*100 + EXTRACT(MONTH FROM c.month_start_dt)) AS year_month_key,

  -- period
  c.month_start_dt AS period_start_date,
  c.month_end_dt   AS period_end_date,

  -- Core metrics
  c.borrow_cnt AS borrows,

  -- Month-over-month (RESET per year)
  LAG(c.borrow_cnt) OVER (PARTITION BY c.yr ORDER BY c.month_start_dt) AS prev_month_borrows,
  ROUND(
    (c.borrow_cnt - LAG(c.borrow_cnt) OVER (PARTITION BY c.yr ORDER BY c.month_start_dt))
    / NULLIF(LAG(c.borrow_cnt) OVER (PARTITION BY c.yr ORDER BY c.month_start_dt),0) * 100, 2
  ) AS mom_pct,

  -- Year-over-year (vs same month last year)
  LAG(c.borrow_cnt,12) OVER (ORDER BY c.month_start_dt) AS prev_year_borrows,
  ROUND(
    (c.borrow_cnt - LAG(c.borrow_cnt,12) OVER (ORDER BY c.month_start_dt))
    / NULLIF(LAG(c.borrow_cnt,12) OVER (ORDER BY c.month_start_dt),0) * 100, 2
  ) AS yoy_pct,

  -- Smoothing and seasonality (RESET per year)
  ROUND(AVG(c.borrow_cnt) OVER (
    PARTITION BY c.yr
    ORDER BY c.month_start_dt
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
  ), 2) AS moving_avg_3,
  ROUND(moy.moy_avg / NULLIF((SELECT overall_avg FROM overall),0) * 100 - 100, 2)
    AS seasonal_index_pct,

  -- Capacity snapshot
  NVL(a.active_loans_end,0) AS active_loans_end,
  (SELECT total_copies FROM lib_cap) - NVL(a.active_loans_end,0) AS net_copies_available,

  -- Context
  tg.top_genre      AS top_genre,
  mh.festive_events AS festive_events   -- 'Yes' or 'No'
FROM m_cnt c
JOIN moy ON moy.mon_of_year = c.mon
LEFT JOIN m_active a ON a.month_start_dt = c.month_start_dt
LEFT JOIN top_gen  tg ON tg.month_start_dt = c.month_start_dt
LEFT JOIN m_hol   mh ON mh.month_start_dt = c.month_start_dt;
