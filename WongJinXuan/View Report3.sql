CREATE OR REPLACE VIEW VW_RPT3_SUPPLIER_GEO AS
/* ============================================================================
   BI-ready view for Power BI

   GRAIN             : 'MONTH' / 'QUARTER'
   TIME KEYS         : YEAR, QUARTER_NUM, MONTH_NUM, YEAR_MONTH, YEAR_QUARTER
   DATES             : PERIOD_START_DATE, PERIOD_END_DATE
   SORT/RANK         : PERIOD_SEQ, PERIOD_RANK_DESC, IS_LATEST_PERIOD,
                       CITY_RANK_VALUE_RM
   METRICS (detail)  : ORDERS, VALUE_RM, QTY, AVG_ORDER_VALUE, CONTRIB_PCT,
                       PRIORITY_FLAG
   METRICS (period)  : PERIOD_ORDERS, PERIOD_VALUE_RM, PERIOD_QTY
   KPIs (tot_row=1)  : PERIOD_AVG_ORDER_VALUE, PREV_PERIOD_VALUE_RM,
                       DELTA_VALUE_PCT, PREV_PERIOD_AVG_ORDER_VALUE,
                       DELTA_AVG_ORDER_PCT
   ROW TYPE          : TOT_ROW  (0 = city detail, 1 = period total)
   ============================================================================ */
WITH
/* ---------- Base + PO value de-dup (header-vs-line totals) ---------- */
f AS (
  SELECT
    dd.cal_year                                   AS yr,
    TO_NUMBER(SUBSTR(dd.cal_quarter, 2, 1))       AS qtr_num,
    EXTRACT(MONTH FROM dd.cal_date)               AS mon_num,
    UPPER(TRIM(NVL(ds.city, 'OTHERS')))           AS city,
    fp.purchaseOrderId                            AS po_id,
    fp.totalAmount                                AS amount,      -- header OR line total
    fp.quantity                                   AS qty
  FROM FactPurchase fp
  JOIN DimDate      dd ON dd.dateKey     = fp.dateKey
  JOIN DimSuppliers ds ON ds.supplierKey = fp.supplierKey
),
f_enriched AS (
  SELECT
    yr, qtr_num, mon_num, city, po_id, qty,
    CASE
      WHEN ABS(MAX(amount) OVER (PARTITION BY po_id)
             - MIN(amount) OVER (PARTITION BY po_id)) <= 0.005
        THEN MAX(amount) OVER (PARTITION BY po_id)     -- header repeated -> take once
      ELSE SUM(amount) OVER (PARTITION BY po_id)       -- true line totals -> sum
    END AS order_value,
    ROW_NUMBER() OVER (PARTITION BY po_id ORDER BY po_id) AS rn_po
  FROM f
),

/* =============================== MONTHLY =============================== */
m_city AS (
  SELECT
    yr,
    mon_num                                         AS period_ord,
    city,
    COUNT(DISTINCT po_id)                           AS total_orders,
    SUM(CASE WHEN rn_po = 1 THEN order_value ELSE 0 END) AS total_value,
    SUM(NVL(qty, 0))                                AS total_qty
  FROM f_enriched
  GROUP BY yr, mon_num, city
),
m_tot AS (
  SELECT
    yr,
    period_ord,
    SUM(total_orders) AS period_orders,
    SUM(total_value)  AS period_value,
    SUM(total_qty)    AS period_qty
  FROM m_city
  GROUP BY yr, period_ord
),
m_final AS (
  SELECT
    CAST('MONTH' AS VARCHAR2(10))                                           AS grain,
    m.yr                                                                     AS year,
    CEIL(m.period_ord / 3)                                                   AS quarter_num,
    m.period_ord                                                             AS month_num,
    TO_CHAR(TO_DATE(m.yr || LPAD(m.period_ord, 2, '0'), 'YYYYMM'), 'YYYY-MM') AS year_month,
    CAST(NULL AS VARCHAR2(7))                                                AS year_quarter,
    TO_DATE(m.yr || LPAD(m.period_ord, 2, '0') || '01', 'YYYYMMDD')          AS period_start_date,
    LAST_DAY(TO_DATE(m.yr || LPAD(m.period_ord, 2, '0') || '01', 'YYYYMMDD')) AS period_end_date,
    m.city                                                                    AS city,
    m.total_orders                                                            AS orders,
    m.total_value                                                             AS value_rm,
    m.total_qty                                                               AS qty,
    ROUND(m.total_value / NULLIF(m.total_orders, 0), 2)                      AS avg_order_value,
    ROUND(100 * m.total_value / NULLIF(t.period_value, 0), 2)                AS contrib_pct,
    CASE
      WHEN (100 * m.total_value / NULLIF(t.period_value, 0)) >= 30 THEN 'HIGH'
      WHEN (100 * m.total_value / NULLIF(t.period_value, 0)) >= 15 THEN 'MED'
      ELSE 'LOW'
    END                                                                       AS priority_flag,
    t.period_orders                                                           AS period_orders,
    t.period_value                                                            AS period_value_rm,
    t.period_qty                                                              AS period_qty,
    0                                                                         AS tot_row
  FROM m_city m
  JOIN m_tot  t
    ON t.yr = m.yr AND t.period_ord = m.period_ord
),
m_total_row AS (  -- one total row per month
  SELECT
    CAST('MONTH' AS VARCHAR2(10))                                           AS grain,
    t.yr                                                                     AS year,
    CEIL(t.period_ord / 3)                                                   AS quarter_num,
    t.period_ord                                                             AS month_num,
    TO_CHAR(TO_DATE(t.yr || LPAD(t.period_ord, 2, '0'), 'YYYYMM'), 'YYYY-MM') AS year_month,
    CAST(NULL AS VARCHAR2(7))                                                AS year_quarter,
    TO_DATE(t.yr || LPAD(t.period_ord, 2, '0') || '01', 'YYYYMMDD')          AS period_start_date,
    LAST_DAY(TO_DATE(t.yr || LPAD(t.period_ord, 2, '0') || '01', 'YYYYMMDD')) AS period_end_date,
    '[TOTAL]'                                                                 AS city,
    t.period_orders                                                           AS orders,
    t.period_value                                                            AS value_rm,
    t.period_qty                                                              AS qty,
    CAST(NULL AS NUMBER)                                                      AS avg_order_value,
    100                                                                       AS contrib_pct,
    CAST(NULL AS VARCHAR2(8))                                                 AS priority_flag,
    t.period_orders                                                           AS period_orders,
    t.period_value                                                            AS period_value_rm,
    t.period_qty                                                              AS period_qty,
    1                                                                         AS tot_row
  FROM m_tot t
),

/* ============================== QUARTERLY ============================== */
q_city AS (
  SELECT
    yr,
    qtr_num                                          AS period_ord,
    city,
    COUNT(DISTINCT po_id)                            AS total_orders,
    SUM(CASE WHEN rn_po = 1 THEN order_value ELSE 0 END) AS total_value,
    SUM(NVL(qty, 0))                                 AS total_qty
  FROM f_enriched
  GROUP BY yr, qtr_num, city
),
q_tot AS (
  SELECT
    yr,
    period_ord,
    SUM(total_orders) AS period_orders,
    SUM(total_value)  AS period_value,
    SUM(total_qty)    AS period_qty
  FROM q_city
  GROUP BY yr, period_ord
),
q_final AS (
  SELECT
    CAST('QUARTER' AS VARCHAR2(10))                                         AS grain,
    q.yr                                                                     AS year,
    q.period_ord                                                             AS quarter_num,
    CAST(NULL AS NUMBER)                                                     AS month_num,
    CAST(NULL AS VARCHAR2(7))                                                AS year_month,
    TO_CHAR(q.yr) || '-Q' || q.period_ord                                    AS year_quarter,
    TO_DATE(q.yr || LPAD(q.period_ord * 3 - 2, 2, '0') || '01', 'YYYYMMDD')   AS period_start_date,
    LAST_DAY(ADD_MONTHS(TO_DATE(q.yr || LPAD(q.period_ord * 3 - 2, 2, '0') || '01', 'YYYYMMDD'), 2))
                                                                             AS period_end_date,
    q.city                                                                    AS city,
    q.total_orders                                                            AS orders,
    q.total_value                                                             AS value_rm,
    q.total_qty                                                               AS qty,
    ROUND(q.total_value / NULLIF(q.total_orders, 0), 2)                      AS avg_order_value,
    ROUND(100 * q.total_value / NULLIF(t.period_value, 0), 2)                AS contrib_pct,
    CASE
      WHEN (100 * q.total_value / NULLIF(t.period_value, 0)) >= 30 THEN 'HIGH'
      WHEN (100 * q.total_value / NULLIF(t.period_value, 0)) >= 15 THEN 'MED'
      ELSE 'LOW'
    END                                                                       AS priority_flag,
    t.period_orders                                                           AS period_orders,
    t.period_value                                                            AS period_value_rm,
    t.period_qty                                                              AS period_qty,
    0                                                                         AS tot_row
  FROM q_city q
  JOIN q_tot  t
    ON t.yr = q.yr AND t.period_ord = q.period_ord
),
q_total_row AS (  -- one total row per quarter
  SELECT
    CAST('QUARTER' AS VARCHAR2(10))                                         AS grain,
    t.yr                                                                     AS year,
    t.period_ord                                                             AS quarter_num,
    CAST(NULL AS NUMBER)                                                     AS month_num,
    CAST(NULL AS VARCHAR2(7))                                                AS year_month,
    TO_CHAR(t.yr) || '-Q' || t.period_ord                                    AS year_quarter,
    TO_DATE(t.yr || LPAD(t.period_ord * 3 - 2, 2, '0') || '01', 'YYYYMMDD')   AS period_start_date,
    LAST_DAY(ADD_MONTHS(TO_DATE(t.yr || LPAD(t.period_ord * 3 - 2, 2, '0') || '01', 'YYYYMMDD'), 2))
                                                                             AS period_end_date,
    '[TOTAL]'                                                                 AS city,
    t.period_orders                                                           AS orders,
    t.period_value                                                            AS value_rm,
    t.period_qty                                                              AS qty,
    CAST(NULL AS NUMBER)                                                      AS avg_order_value,
    100                                                                       AS contrib_pct,
    CAST(NULL AS VARCHAR2(8))                                                 AS priority_flag,
    t.period_orders                                                           AS period_orders,
    t.period_value                                                            AS period_value_rm,
    t.period_qty                                                              AS period_qty,
    1                                                                         AS tot_row
  FROM q_tot t
),

/* ================ UNION + period KPIs / ranks / helpers ================ */
u AS (
  SELECT * FROM m_final
  UNION ALL
  SELECT * FROM m_total_row
  UNION ALL
  SELECT * FROM q_final
  UNION ALL
  SELECT * FROM q_total_row
),
final_data AS (  -- (avoid name 'final' to keep Oracle happy)
  SELECT
    u.*,

    /* unified sort key for time */
    CASE
      WHEN u.grain = 'MONTH'
        THEN u.year * 100 + u.month_num
      ELSE u.year * 10 + u.quarter_num
    END AS period_seq,

    /* true period average on TOT_ROW=1; NULL on city rows */
    CASE
      WHEN u.tot_row = 1
        THEN ROUND(u.period_value_rm / NULLIF(u.period_orders, 0), 2)
      ELSE CAST(NULL AS NUMBER)
    END AS period_avg_order_value,

    /* prev period comparisons (by grain) on TOT_ROW=1 */
    CASE
      WHEN u.tot_row = 1 THEN
        LAG(u.period_value_rm) OVER (
          PARTITION BY u.grain
          ORDER BY CASE WHEN u.grain = 'MONTH'
                        THEN u.year * 100 + u.month_num
                        ELSE u.year * 10 + u.quarter_num
                   END
        )
    END AS prev_period_value_rm,

    CASE
      WHEN u.tot_row = 1 THEN
        LAG(ROUND(u.period_value_rm / NULLIF(u.period_orders, 0), 2)) OVER (
          PARTITION BY u.grain
          ORDER BY CASE WHEN u.grain = 'MONTH'
                        THEN u.year * 100 + u.month_num
                        ELSE u.year * 10 + u.quarter_num
                   END
        )
    END AS prev_period_avg_order_value,

    CASE
      WHEN u.tot_row = 1 THEN
        ROUND(
          100 * (u.period_value_rm -
                 LAG(u.period_value_rm) OVER (
                   PARTITION BY u.grain
                   ORDER BY CASE WHEN u.grain = 'MONTH'
                                 THEN u.year * 100 + u.month_num
                                 ELSE u.year * 10 + u.quarter_num
                            END
                 )
          )
          / NULLIF(
              LAG(u.period_value_rm) OVER (
                PARTITION BY u.grain
                ORDER BY CASE WHEN u.grain = 'MONTH'
                              THEN u.year * 100 + u.month_num
                              ELSE u.year * 10 + u.quarter_num
                         END
              ), 0
            )
        , 2)
      ELSE CAST(NULL AS NUMBER)
    END AS delta_value_pct,

    CASE
      WHEN u.tot_row = 1 THEN
        ROUND(
          100 * (
            (ROUND(u.period_value_rm / NULLIF(u.period_orders, 0), 2)) -
            LAG(ROUND(u.period_value_rm / NULLIF(u.period_orders, 0), 2)) OVER (
              PARTITION BY u.grain
              ORDER BY CASE WHEN u.grain = 'MONTH'
                            THEN u.year * 100 + u.month_num
                            ELSE u.year * 10 + u.quarter_num
                       END
            )
          )
          / NULLIF(
              LAG(ROUND(u.period_value_rm / NULLIF(u.period_orders, 0), 2)) OVER (
                PARTITION BY u.grain
                ORDER BY CASE WHEN u.grain = 'MONTH'
                              THEN u.year * 100 + u.month_num
                              ELSE u.year * 10 + u.quarter_num
                         END
              ), 0
            )
        , 2)
      ELSE CAST(NULL AS NUMBER)
    END AS delta_avg_order_pct,

    /* period ranking (1 = latest period in the selected grain) */
    DENSE_RANK() OVER (
      PARTITION BY u.grain
      ORDER BY CASE WHEN u.grain = 'MONTH'
                    THEN u.year * 100 + u.month_num
                    ELSE u.year * 10 + u.quarter_num
               END DESC
    ) AS period_rank_desc,

    /* convenience flag for filters */
    CASE
      WHEN DENSE_RANK() OVER (
             PARTITION BY u.grain
             ORDER BY CASE WHEN u.grain = 'MONTH'
                           THEN u.year * 100 + u.month_num
                           ELSE u.year * 10 + u.quarter_num
                      END DESC
           ) = 1
        THEN 1 ELSE 0
    END AS is_latest_period,

    /* Top-N city helper inside each period (NULL on totals) */
    CASE
      WHEN u.tot_row = 0 THEN
        DENSE_RANK() OVER (
          PARTITION BY u.grain,
                       CASE WHEN u.grain = 'MONTH'
                              THEN u.year * 100 + u.month_num
                            ELSE u.year * 10 + u.quarter_num
                       END
          ORDER BY u.value_rm DESC
        )
    END AS city_rank_value_rm
  FROM u u
)
SELECT * FROM final_data;
