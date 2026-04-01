SPOOL "C:\Users\wongj\Documents\SupplierPerformance_Report3.txt"

-- ======================== Session and Prompts =========================
SET LINESIZE 130
SET PAGESIZE 35
SET TRIMSPOOL ON
SET VERIFY OFF
SET SQLBLANKLINES ON
SET WRAP OFF
SET TAB OFF
ALTER SESSION SET NLS_DATE_FORMAT = 'DD-MON-YYYY';

PROMPT === Supplier City Geography Parameters ===
ACCEPT start_year  NUMBER DEFAULT 2023 PROMPT 'Enter START year (YYYY) [2023]: '
ACCEPT end_year    NUMBER DEFAULT 2025 PROMPT 'Enter END year (YYYY)   [2025]: '
ACCEPT period_view CHAR   DEFAULT 'Q'  PROMPT 'Period view [Q=Quarterly, M=Monthly]: '

COLUMN run_dt NEW_VALUE run_dt
SELECT TO_CHAR(SYSDATE,'DD-MON-YYYY') run_dt FROM dual;

-- Dynamic label for contribution header: Q -> Qtr, M -> Mon (silent)
SET TERMOUT OFF
COLUMN perhdr NEW_VALUE perhdr NOPRINT
SELECT CASE WHEN UPPER('&period_view')='Q' THEN 'Qtr' ELSE 'Mon' END AS perhdr FROM dual;
SET TERMOUT ON
SET TERMOUT OFF
COLUMN sep_line NEW_VALUE sep_line NOPRINT
SELECT RPAD('_', 130, '_') AS sep_line FROM dual;
SET TERMOUT ON

TTITLE LEFT ' ' CENTER 'Supplier Contribution Deliveries by Geography &start_year -- &end_year' -
       SKIP 1 RIGHT 'Page ' FORMAT 999 SQL.PNO SKIP 1 LEFT 'Date: &run_dt' SKIP 2
BTITLE CENTER '&sep_line'

-- ======================== Display formats ===========================
CLEAR COLUMNS
COLUMN "Year"         HEADING 'Year'                           FORMAT 9999
COLUMN "Period"       HEADING 'Quarter|Month'                  FORMAT A8
COLUMN "City"         HEADING 'Supplier|City'                  FORMAT A20
COLUMN "Orders"       HEADING 'Orders|(POs)'                   FORMAT 9,999
COLUMN "Value (RM)"   HEADING 'Purchases|Value (RM)'           FORMAT 999,999,999.99
COLUMN "Qty"          HEADING 'Units|Qty'                      FORMAT 999,999,999
COLUMN "Avg Order"    HEADING 'Avg|Order (RM)'                 FORMAT 999,999,999.99
COLUMN "Contrib %"    HEADING 'Contribution|% of &perhdr'      FORMAT 999,990.00
COLUMN "Priority"     HEADING 'Delivery|Priority'              FORMAT A8 JUSTIFY RIGHT
COLUMN "Top Supplier" HEADING 'Top Supplier|(PurchaseValue)'   FORMAT A40

-- Show Year once; show Period once (blank line between periods)
CLEAR BREAKS
CLEAR COMPUTES
BREAK ON "Year" SKIP 1 ON "Period" SKIP 1 ON REPORT

-- ========================= Star-Schema Model ========================
WITH
-- Fact joined to dimensions, filtered by year range
f AS (
  SELECT
    dd.cal_year                           AS yr,
    TO_NUMBER(SUBSTR(dd.cal_quarter,2,1)) AS qtr_num,
    EXTRACT(MONTH FROM dd.cal_date)       AS mon_num,
    UPPER(TRIM(NVL(ds.city,'OTHERS')))    AS city,
    TRIM(ds.supplierName)                 AS supplier_name,
    fp.purchaseOrderId                    AS po_id,
    fp.totalAmount                        AS amount,
    fp.quantity                           AS qty
  FROM FactPurchase fp
  JOIN DimDate      dd ON dd.dateKey     = fp.dateKey
  JOIN DimSuppliers ds ON ds.supplierKey = fp.supplierKey
  WHERE dd.cal_year BETWEEN &start_year AND &end_year
),

-- Deduplicate order value correctly (header-vs-line totals)
f_enriched AS (
  SELECT
    yr, qtr_num, mon_num, city, supplier_name, po_id, qty,
    CASE
      WHEN ABS(MAX(amount) OVER (PARTITION BY po_id)
             - MIN(amount) OVER (PARTITION BY po_id)) <= 0.005
        THEN MAX(amount) OVER (PARTITION BY po_id)
      ELSE SUM(amount) OVER (PARTITION BY po_id)
    END AS order_value,
    ROW_NUMBER() OVER (PARTITION BY po_id ORDER BY po_id) AS rn_po
  FROM f
),

-- ================== Quarterly and Monthly city views =================
q_city AS (
  SELECT
    yr,
    'Q' || qtr_num                                AS period_label,
    qtr_num                                       AS period_ord,
    city,
    COUNT(DISTINCT po_id)                          AS total_orders,
    SUM(CASE WHEN rn_po = 1 THEN order_value ELSE 0 END) AS total_value,
    SUM(NVL(qty,0))                                AS total_qty,
    ROUND(
      SUM(CASE WHEN rn_po = 1 THEN order_value ELSE 0 END)
      / NULLIF(COUNT(DISTINCT po_id),0), 2
    ) AS avg_order_value
  FROM f_enriched
  GROUP BY yr, qtr_num, city
),
q_tot AS (
  SELECT yr, period_ord, SUM(total_value) AS period_value
  FROM q_city
  GROUP BY yr, period_ord
),
q_city_pct AS (
  SELECT
    q.*,
    ROUND(100 * q.total_value / NULLIF(t.period_value,0), 2) AS contrib_pct,
    CASE
      WHEN (100 * q.total_value / NULLIF(t.period_value,0)) >= 30 THEN 'HIGH'
      WHEN (100 * q.total_value / NULLIF(t.period_value,0)) >= 15 THEN 'MED'
      ELSE 'LOW'
    END AS priority_flag
  FROM q_city q
  JOIN q_tot  t ON t.yr = q.yr AND t.period_ord = q.period_ord
),

m_city AS (
  SELECT
    yr,
    TO_CHAR(ADD_MONTHS(DATE '2000-01-01', mon_num-1), 'Mon') AS period_label,
    mon_num                                       AS period_ord,
    city,
    COUNT(DISTINCT po_id)                          AS total_orders,
    SUM(CASE WHEN rn_po = 1 THEN order_value ELSE 0 END) AS total_value,
    SUM(NVL(qty,0))                                AS total_qty,
    ROUND(
      SUM(CASE WHEN rn_po = 1 THEN order_value ELSE 0 END)
      / NULLIF(COUNT(DISTINCT po_id),0), 2
    ) AS avg_order_value
  FROM f_enriched
  GROUP BY yr, mon_num, city
),
m_tot AS (
  SELECT yr, period_ord, SUM(total_value) AS period_value
  FROM m_city
  GROUP BY yr, period_ord
),
m_city_pct AS (
  SELECT
    m.*,
    ROUND(100 * m.total_value / NULLIF(t.period_value,0), 2) AS contrib_pct,
    CASE
      WHEN (100 * m.total_value / NULLIF(t.period_value,0)) >= 30 THEN 'HIGH'
      WHEN (100 * m.total_value / NULLIF(t.period_value,0)) >= 15 THEN 'MED'
      ELSE 'LOW'
    END AS priority_flag
  FROM m_city m
  JOIN m_tot  t ON t.yr = m.yr AND t.period_ord = m.period_ord
),

-- ============ Pick view and append *** + “Year Total:” ==============
pc_raw AS (
  SELECT * FROM q_city_pct WHERE UPPER('&period_view')='Q'
  UNION ALL
  SELECT * FROM m_city_pct WHERE UPPER('&period_view')='M'
),

/* ====== Supplier totals per period (to print Top Supplier + value) ====== */
m_sup AS (
  SELECT
    yr, mon_num AS period_ord,
    supplier_name,
    COUNT(DISTINCT po_id)                                                AS sup_orders,
    SUM(CASE WHEN rn_po = 1 THEN order_value ELSE 0 END)                 AS sup_value
  FROM f_enriched
  GROUP BY yr, mon_num, supplier_name
),
m_sup_top AS (
  SELECT yr, period_ord,
         supplier_name AS top_supplier,
         sup_value     AS top_value,
         ROW_NUMBER() OVER (
           PARTITION BY yr, period_ord
           ORDER BY sup_value DESC, sup_orders DESC, supplier_name
         ) AS rn
  FROM m_sup
),
q_sup AS (
  SELECT
    yr, qtr_num AS period_ord,
    supplier_name,
    COUNT(DISTINCT po_id)                                                AS sup_orders,
    SUM(CASE WHEN rn_po = 1 THEN order_value ELSE 0 END)                 AS sup_value
  FROM f_enriched
  GROUP BY yr, qtr_num, supplier_name
),
q_sup_top AS (
  SELECT yr, period_ord,
         supplier_name AS top_supplier,
         sup_value     AS top_value,
         ROW_NUMBER() OVER (
           PARTITION BY yr, period_ord
           ORDER BY sup_value DESC, sup_orders DESC, supplier_name
         ) AS rn
  FROM q_sup
),

/* Winner list respecting selected grain (Top Supplier per period) */
period_winner AS (
  SELECT yr, period_ord, top_supplier, top_value
  FROM q_sup_top
  WHERE UPPER('&period_view')='Q' AND rn = 1
  UNION ALL
  SELECT yr, period_ord, top_supplier, top_value
  FROM m_sup_top
  WHERE UPPER('&period_view')='M' AND rn = 1
),

/* ==== Year Champion by highest purchase value (not by wins) ==== */
sup_year AS (
  SELECT
    yr,
    supplier_name,
    COUNT(DISTINCT po_id) AS year_orders,
    SUM(CASE WHEN rn_po = 1 THEN order_value ELSE 0 END) AS year_value
  FROM f_enriched
  GROUP BY yr, supplier_name
),
year_top_pick AS (
  SELECT
    sy.yr,
    MAX(sy.supplier_name)
      KEEP (DENSE_RANK FIRST ORDER BY sy.year_value DESC, sy.year_orders DESC, sy.supplier_name)
      AS top_supplier_year,
    MAX(sy.year_value)
      KEEP (DENSE_RANK FIRST ORDER BY sy.year_value DESC, sy.year_orders DESC, sy.supplier_name)
      AS top_supplier_year_value
  FROM sup_year sy
  GROUP BY sy.yr
),

year_tot AS (
  SELECT
    yr,
    SUM(total_orders) AS orders_sum,
    SUM(total_value)  AS value_sum,
    SUM(total_qty)    AS qty_sum
  FROM pc_raw
  GROUP BY yr
),

pc AS (
  -- detail rows
  SELECT
    yr, period_ord, period_label, city,
    total_orders, total_value, total_qty, avg_order_value, contrib_pct, priority_flag,
    1 AS sec_ord
  FROM pc_raw

  UNION ALL

  -- decorative separator BEFORE the Year Total row (***)
  SELECT
    yt.yr,
    998 AS period_ord,
    (SELECT MAX(period_label) FROM pc_raw r WHERE r.yr = yt.yr) AS period_label,
    RPAD('*', 16, '*') AS city,
    CAST(NULL AS NUMBER) AS total_orders,
    CAST(NULL AS NUMBER) AS total_value,
    CAST(NULL AS NUMBER) AS total_qty,
    CAST(NULL AS NUMBER) AS avg_order_value,
    CAST(NULL AS NUMBER) AS contrib_pct,
    CAST(NULL AS VARCHAR2(8)) AS priority_flag,
    2 AS sec_ord
  FROM year_tot yt

  UNION ALL

  -- Year Total row
  SELECT
    yt.yr,
    999 AS period_ord,
    (SELECT MAX(period_label) FROM pc_raw r WHERE r.yr = yt.yr) AS period_label,
    'Year Total:' AS city,
    yt.orders_sum, yt.value_sum, yt.qty_sum,
    CAST(NULL AS NUMBER)       AS avg_order_value,
    CAST(NULL AS NUMBER)       AS contrib_pct,
    CAST(NULL AS VARCHAR2(8))  AS priority_flag,
    3 AS sec_ord
  FROM year_tot yt
),

/* ---- Print winner once per period: mark the first city row in each period ---- */
pc2 AS (
  SELECT pc.*,
         ROW_NUMBER() OVER (
           PARTITION BY pc.yr, pc.period_ord
           ORDER BY pc.sec_ord, pc.city
         ) AS rn_in_period
  FROM pc
)

-- ========================= SINGLE OUTPUT =========================
SELECT
  pc2.yr                      AS "Year",
  pc2.period_label            AS "Period",
  pc2.city                    AS "City",
  pc2.total_orders            AS "Orders",
  pc2.total_value             AS "Value (RM)",
  pc2.total_qty               AS "Qty",
  pc2.avg_order_value         AS "Avg Order",
  pc2.contrib_pct             AS "Contrib %",
  LPAD(pc2.priority_flag, 8)  AS "Priority",
  CASE
    WHEN pc2.sec_ord = 1 AND pc2.rn_in_period = 1
      THEN pw.top_supplier
    WHEN pc2.sec_ord = 3
      THEN ytp.top_supplier_year
    ELSE NULL
  END AS "Top Supplier"
FROM pc2
LEFT JOIN period_winner pw
  ON pw.yr = pc2.yr AND pw.period_ord = pc2.period_ord
LEFT JOIN year_top_pick ytp
  ON ytp.yr = pc2.yr
ORDER BY pc2.yr, pc2.sec_ord, pc2.period_ord, pc2.city;

TTITLE OFF
BTITLE OFF

PROMPT
PROMPT Legend:
PROMPT • Grain = (Quarter/Month) by City within Year.
PROMPT • Orders = distinct purchase orders; Value (RM) = PO value after de-dup at PO level.
PROMPT • Avg Order = Value ÷ Orders.
PROMPT • Delivery Priority (by Contrib % share):
PROMPT     HIGH  : ≥ 30%   (major share — prioritize/expedite)
PROMPT     MED   : 15–29.99%
PROMPT     LOW   : < 15%
PROMPT • "Top Supplier" (per &perhdr): supplier with the highest purchase value in that period.
PROMPT • "Year Total:": Year Champion = supplier with the highest total purchase value in that year.
PROMPT

SPOOL OFF
