CREATE OR REPLACE VIEW VW_RPT2_BORROW_VS_SALES AS
/*  Report 2 — Borrow vs Sales Preference by Year and Genre (star schema)
    GRAIN: one row per (YEAR, GENRE), plus optional YEAR_TOTAL rows
    Columns (for visuals):
      YEAR                         number(4)
      GENRE                        varchar2
      BORROW_CNT, SALES_CNT        activity counts
      REVENUE                      sales revenue (line_total)
      BORROW_PCT, SALES_PCT        mix % within (BORROW_CNT + SALES_CNT)
      PARTICIPANTS_TOTAL           distinct members across BOTH activities
      MALE_CNT, FEMALE_CNT         distinct members by gender (M/F)
      MALE_PCT, FEMALE_PCT         gender mix within PARTICIPANTS_TOTAL
      PREF_FLAG                    'Borrowing Higher' / 'Sales Higher' / 'Balanced'
      YEAR_BORROW_TOTAL / YEAR_SALES_TOTAL
      BORROW_SHARE_OF_YEAR_PCT     genre share of year total (borrows)
      SALES_SHARE_OF_YEAR_PCT      genre share of year total (sales)
      BORROW_YOY_PCT / SALES_YOY_PCT / REVENUE_YOY_PCT (per genre)
      BORROW_TO_SALES_RATIO        simple ratio
      GRAIN_TAG                    'GENRE' or 'YEAR_TOTAL' (for easy filtering)
      YEAR_GENRE_KEY               convenient unique key for visuals
*/
WITH
/* ===== All (year, genre) pairs present in either fact =================== */
k AS (
  SELECT DISTINCT d.cal_year AS year, b.genre
  FROM FactBorrowing fb
  JOIN DimDate d ON d.dateKey = fb.dateKey
  JOIN DimBook b ON b.bookKey = fb.bookKey
  UNION
  SELECT DISTINCT d.cal_year, b.genre
  FROM FactSales fs
  JOIN DimDate d ON d.dateKey = fs.dateKey
  JOIN DimBook b ON b.bookKey = fs.bookKey
),

/* ===== Sales by year and genre =========================================== */
s AS (
  SELECT d.cal_year AS year,
         b.genre,
         COUNT(fs.sales_id)                 AS sales_cnt,
         SUM(fs.line_total)                 AS revenue
  FROM FactSales fs
  JOIN DimDate d ON d.dateKey = fs.dateKey
  JOIN DimBook b ON b.bookKey = fs.bookKey
  GROUP BY d.cal_year, b.genre
),

/* ===== Borrows by year and genre ========================================= */
br AS (
  SELECT d.cal_year AS year,
         b.genre,
         COUNT(*)                         AS borrow_cnt
  FROM FactBorrowing fb
  JOIN DimDate d ON d.dateKey = fb.dateKey
  JOIN DimBook b ON b.bookKey = fb.bookKey
  GROUP BY d.cal_year, b.genre
),

/* ===== Distinct participants across BOTH activities (no double count) === */
p_raw AS (
  /* Borrowing participants */
  SELECT DISTINCT d.cal_year AS year,
         b.genre,
         m.memberKey,
         UPPER(m.memberGender) AS gender
  FROM FactBorrowing fb
  JOIN DimDate d    ON d.dateKey    = fb.dateKey
  JOIN DimBook b    ON b.bookKey    = fb.bookKey
  JOIN DimMembers m ON m.memberKey  = fb.memberKey

  UNION ALL

  /* Sales participants */
  SELECT DISTINCT d.cal_year,
         b.genre,
         m.memberKey,
         UPPER(m.memberGender)
  FROM FactSales fs
  JOIN DimDate d    ON d.dateKey    = fs.dateKey
  JOIN DimBook b    ON b.bookKey    = fs.bookKey
  JOIN DimMembers m ON m.memberKey  = fs.memberKey
),
p AS (
  SELECT year,
         genre,
         COUNT(DISTINCT memberKey)                                           AS participants_total,
         COUNT(DISTINCT CASE WHEN gender = 'M' THEN memberKey END)           AS male_cnt,
         COUNT(DISTINCT CASE WHEN gender = 'F' THEN memberKey END)           AS female_cnt
  FROM p_raw
  GROUP BY year, genre
),

/* ===== Core rows: one per (year, genre) ================================= */
core AS (
  SELECT
    k.year,
    k.genre,
    NVL(br.borrow_cnt, 0)                       AS borrow_cnt,
    NVL(s.sales_cnt,  0)                        AS sales_cnt,
    NVL(s.revenue,    0)                        AS revenue,
    NVL(p.participants_total, 0)                AS participants_total,
    NVL(p.male_cnt, 0)                          AS male_cnt,
    NVL(p.female_cnt, 0)                        AS female_cnt
  FROM k
  LEFT JOIN br ON br.year = k.year AND br.genre = k.genre
  LEFT JOIN s  ON s.year  = k.year AND s.genre  = k.genre
  LEFT JOIN p  ON p.year  = k.year AND p.genre  = k.genre
),

/* ===== Add mixes, shares, YoY metrics =================================== */
enriched AS (
  SELECT
    c.*,
    /* Mix within actions */
    ROUND(100 * c.borrow_cnt / NULLIF(c.borrow_cnt + c.sales_cnt, 0), 2) AS borrow_pct,
    ROUND(100 * c.sales_cnt  / NULLIF(c.borrow_cnt + c.sales_cnt, 0), 2) AS sales_pct,

    /* Gender mix within distinct participants */
    ROUND(100 * c.male_cnt   / NULLIF(c.participants_total, 0), 2)       AS male_pct,
    ROUND(100 * c.female_cnt / NULLIF(c.participants_total, 0), 2)       AS female_pct,

    /* Year totals and shares */
    SUM(c.borrow_cnt) OVER (PARTITION BY c.year)                          AS year_borrow_total,
    SUM(c.sales_cnt ) OVER (PARTITION BY c.year)                          AS year_sales_total,
    ROUND(100 * c.borrow_cnt / NULLIF(SUM(c.borrow_cnt) OVER (PARTITION BY c.year), 0), 2)
                                                                          AS borrow_share_of_year_pct,
    ROUND(100 * c.sales_cnt  / NULLIF(SUM(c.sales_cnt ) OVER (PARTITION BY c.year), 0), 2)
                                                                          AS sales_share_of_year_pct,

    /* YoY % (by genre) */
    LAG(c.borrow_cnt) OVER (PARTITION BY c.genre ORDER BY c.year)         AS borrow_cnt_prev_year,
    ROUND(
      100 * (c.borrow_cnt - LAG(c.borrow_cnt) OVER (PARTITION BY c.genre ORDER BY c.year))
        / NULLIF(LAG(c.borrow_cnt) OVER (PARTITION BY c.genre ORDER BY c.year), 0), 2
    )                                                                     AS borrow_yoy_pct,

    LAG(c.sales_cnt)  OVER (PARTITION BY c.genre ORDER BY c.year)         AS sales_cnt_prev_year,
    ROUND(
      100 * (c.sales_cnt - LAG(c.sales_cnt) OVER (PARTITION BY c.genre ORDER BY c.year))
        / NULLIF(LAG(c.sales_cnt) OVER (PARTITION BY c.genre ORDER BY c.year), 0), 2
    )                                                                     AS sales_yoy_pct,

    LAG(c.revenue)    OVER (PARTITION BY c.genre ORDER BY c.year)         AS revenue_prev_year,
    ROUND(
      100 * (c.revenue - LAG(c.revenue) OVER (PARTITION BY c.genre ORDER BY c.year))
        / NULLIF(LAG(c.revenue) OVER (PARTITION BY c.genre ORDER BY c.year), 0), 2
    )                                                                     AS revenue_yoy_pct,

    /* Preference flag and ratio */
    CASE
      WHEN c.borrow_cnt > c.sales_cnt * 1.10 THEN 'Borrowing Higher'
      WHEN c.sales_cnt  > c.borrow_cnt * 1.10 THEN 'Sales Higher'
      ELSE 'Balanced'
    END                                                                   AS pref_flag,
    ROUND(c.borrow_cnt / NULLIF(c.sales_cnt, 0), 3)                        AS borrow_to_sales_ratio
  FROM core c
),

/* ===== Year totals (one row per year) =================================== */
tot AS (
  SELECT
    year,
    'ALL'             AS genre,
    SUM(borrow_cnt)   AS borrow_cnt,
    SUM(sales_cnt)    AS sales_cnt,
    SUM(revenue)      AS revenue,
    SUM(participants_total) AS participants_total,   -- note: sum by genre (approx.)
    SUM(male_cnt)     AS male_cnt,
    SUM(female_cnt)   AS female_cnt
  FROM core
  GROUP BY year
),
tot_enriched AS (
  SELECT
    t.*,
    ROUND(100 * t.borrow_cnt / NULLIF(t.borrow_cnt + t.sales_cnt, 0), 2) AS borrow_pct,
    ROUND(100 * t.sales_cnt  / NULLIF(t.borrow_cnt + t.sales_cnt, 0), 2) AS sales_pct,
    ROUND(100 * t.male_cnt   / NULLIF(t.participants_total, 0), 2)       AS male_pct,
    ROUND(100 * t.female_cnt / NULLIF(t.participants_total, 0), 2)       AS female_pct,
    /* YoY on totals */
    LAG(t.borrow_cnt) OVER (ORDER BY t.year)                              AS borrow_cnt_prev_year,
    ROUND(
      100 * (t.borrow_cnt - LAG(t.borrow_cnt) OVER (ORDER BY t.year))
        / NULLIF(LAG(t.borrow_cnt) OVER (ORDER BY t.year), 0), 2
    )                                                                     AS borrow_yoy_pct,
    LAG(t.sales_cnt)  OVER (ORDER BY t.year)                              AS sales_cnt_prev_year,
    ROUND(
      100 * (t.sales_cnt - LAG(t.sales_cnt) OVER (ORDER BY t.year))
        / NULLIF(LAG(t.sales_cnt) OVER (ORDER BY t.year), 0), 2
    )                                                                     AS sales_yoy_pct,
    LAG(t.revenue)    OVER (ORDER BY t.year)                              AS revenue_prev_year,
    ROUND(
      100 * (t.revenue - LAG(t.revenue) OVER (ORDER BY t.year))
        / NULLIF(LAG(t.revenue) OVER (ORDER BY t.year), 0), 2
    )                                                                     AS revenue_yoy_pct,
    CASE
      WHEN t.borrow_cnt > t.sales_cnt * 1.10 THEN 'Borrowing Higher'
      WHEN t.sales_cnt  > t.borrow_cnt * 1.10 THEN 'Sales Higher'
      ELSE 'Balanced'
    END                                                                   AS pref_flag,
    ROUND(t.borrow_cnt / NULLIF(t.sales_cnt, 0), 3)                        AS borrow_to_sales_ratio
  FROM tot t
)

/* ===== Final UNION: genre rows + year total rows ======================== */
SELECT
  'GENRE'                          AS grain_tag,
  e.year                           AS year,
  e.genre                          AS genre,
  e.borrow_cnt,
  e.sales_cnt,
  e.revenue,
  e.borrow_pct,
  e.sales_pct,
  e.participants_total,
  e.male_cnt,
  e.female_cnt,
  e.male_pct,
  e.female_pct,
  e.pref_flag,
  e.year_borrow_total,
  e.year_sales_total,
  e.borrow_share_of_year_pct,
  e.sales_share_of_year_pct,
  e.borrow_cnt_prev_year,
  e.borrow_yoy_pct,
  e.sales_cnt_prev_year,
  e.sales_yoy_pct,
  e.revenue_prev_year,
  e.revenue_yoy_pct,
  e.borrow_to_sales_ratio,
  TO_CHAR(e.year) || '|' || e.genre AS year_genre_key
FROM enriched e

UNION ALL

SELECT
  'YEAR_TOTAL'                     AS grain_tag,
  t.year                           AS year,
  t.genre                          AS genre,  -- 'ALL'
  t.borrow_cnt,
  t.sales_cnt,
  t.revenue,
  t.borrow_pct,
  t.sales_pct,
  t.participants_total,
  t.male_cnt,
  t.female_cnt,
  t.male_pct,
  t.female_pct,
  t.pref_flag,
  /* for total rows, echo totals and set shares to 100% */
  t.borrow_cnt                     AS year_borrow_total,
  t.sales_cnt                      AS year_sales_total,
  100                              AS borrow_share_of_year_pct,
  100                              AS sales_share_of_year_pct,
  t.borrow_cnt_prev_year,
  t.borrow_yoy_pct,
  t.sales_cnt_prev_year,
  t.sales_yoy_pct,
  t.revenue_prev_year,
  t.revenue_yoy_pct,
  t.borrow_to_sales_ratio,
  TO_CHAR(t.year) || '|ALL'        AS year_genre_key
FROM tot_enriched t;
