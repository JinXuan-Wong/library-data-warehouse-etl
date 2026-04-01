-- Helpers (ensure these compile first)

CREATE OR REPLACE FUNCTION next_member_id RETURN VARCHAR2 IS
  v_max_num NUMBER;
BEGIN
  SELECT NVL(MAX(TO_NUMBER(REGEXP_SUBSTR(memberId, '\d+'))), 0)
    INTO v_max_num
    FROM Members
   WHERE memberId LIKE 'M%';
  v_max_num := v_max_num + 1;
  RETURN 'M' || LPAD(v_max_num, 4, '0');
END;
/

CREATE OR REPLACE FUNCTION make_phone(p_seq NUMBER) RETURN VARCHAR2 IS
BEGIN
  RETURN '01' || TO_CHAR(MOD(p_seq, 10)) || '-' || LPAD(p_seq, 7, '0');
END;
/

CREATE OR REPLACE FUNCTION make_email(p_seq NUMBER) RETURN VARCHAR2 IS
BEGIN
  RETURN 'member' || TO_CHAR(p_seq) || '@example.com';
END;
/

CREATE OR REPLACE FUNCTION pick_one(p_list CLOB) RETURN VARCHAR2 IS
  v_count PLS_INTEGER := REGEXP_COUNT(p_list, '[^,]+');
  v_n     PLS_INTEGER;
  v_item  VARCHAR2(4000);
BEGIN
  IF v_count = 0 THEN RETURN NULL; END IF;
  v_n := TRUNC(DBMS_RANDOM.VALUE(1, v_count + 1));
  v_item := TRIM(REGEXP_SUBSTR(p_list, '[^,]+', 1, v_n));
  RETURN v_item;
END;
/

CREATE OR REPLACE FUNCTION expiry_after_renewals(p_reg DATE, p_renewals NUMBER) RETURN DATE IS
BEGIN
  RETURN ADD_MONTHS(p_reg, 12 * (1 + p_renewals)) - 1;
END;
/

-- ================== MAIN PROCEDURE ==================
CREATE OR REPLACE PROCEDURE generate_members(
  p_target_total IN NUMBER   DEFAULT 7500,
  p_active_ratio IN NUMBER   DEFAULT 0.75,
  p_reg_start    IN DATE     DEFAULT DATE '2004-07-01',
  p_reg_end      IN DATE     DEFAULT DATE '2024-06-30',
  p_cutoff       IN DATE     DEFAULT DATE '2024-06-30',
  p_cap_expiry   IN DATE     DEFAULT DATE '2025-06-30'  -- upper bound for expiry realism
) IS
  -- ===== constants / derived =====
  v_start   DATE := TRUNC(p_reg_start);
  v_end     DATE := TRUNC(p_reg_end);
  v_today   DATE := TRUNC(SYSDATE);

  -- 20-year bucket count (exact): months span / 12 + 1
  v_buckets PLS_INTEGER := FLOOR(MONTHS_BETWEEN(v_end, v_start) / 12) + 1;

  -- inventory
  v_have NUMBER; v_need NUMBER;
  base_per_bucket PLS_INTEGER;
  remainder_bkt   PLS_INTEGER;

  -- names/addr pools (same as before)
  c_first_names  CLOB := 'Amin,Aina,Hafiz,Nadia,Calvin,Victor,Marissa,Jason,Li Mei,Azlan,Haziq,Deepa,Daniel,Siti,Priya,Ramesh,Arif,Zara,Ivy,Harith,Adam,Aisyah,Iman,Khairul';
  c_last_names   CLOB := 'Ismail,Rahman,Chong,Goh,Cheah,Lee,Tan,Wong,Menon,Subramaniam,Abdullah,Aziz,Koh,Zakaria,Mustafa,Lim,Chan,Liew,Din,Latif,Krishnan';
  c_streets      CLOB := 'Jalan Ampang,Jalan Raja Laut,Jalan Bukit Bintang,Jalan Pudu,Jalan Sentral,Jalan Sutera,Jalan Macalister,Jalan Song,Jalan Damai,Jalan Duta';
  c_cities       CLOB := 'Kuala Lumpur,Shah Alam,Petaling Jaya,Johor Bahru,Ipoh,George Town,Kota Kinabalu,Kuching,Seremban,Melaka City,Taiping,Kuantan,Putrajaya,Miri,Sibu,Sandakan,Kota Bharu,Alor Setar';
  c_states       CLOB := 'Kuala Lumpur,Selangor,Johor,Perak,Penang,Sabah,Sarawak,Negeri Sembilan,Melaka,Kelantan,Kedah,Pahang,Putrajaya';

  -- row vars
  v_member_id Members.memberId%TYPE;
  v_member_name Members.memberName%TYPE;
  v_member_tel Members.memberTel%TYPE;
  v_member_email Members.memberEmail%TYPE;
  v_member_age     PLS_INTEGER;
  v_member_gender  VARCHAR2(6);
  v_member_address Members.memberAddress%TYPE;
  v_member_status Members.memberStatus%TYPE;
  v_reg_date Members.registrationDate%TYPE;
  v_exp_date Members.expireDate%TYPE;


  v_seq_num PLS_INTEGER;

  -- bucket iter vars
  b_start DATE; b_end DATE; n_in_bucket PLS_INTEGER;

  -- renewal maths
  k_min_active PLS_INTEGER;  -- minimal renewals to be active at cutoff
  k_max_cap    PLS_INTEGER;  -- maximal renewals allowed by cap
  k_chosen     PLS_INTEGER;

  -- random helper
  FUNCTION rand_date(a DATE, b DATE) RETURN DATE IS
  BEGIN
    RETURN TRUNC(a + DBMS_RANDOM.VALUE(0, (b - a) + 1));
  END;
BEGIN
  -- sanity for buckets
  IF v_buckets < 1 THEN
    DBMS_OUTPUT.PUT_LINE('No period to generate.');
    RETURN;
  END IF;

  -- how many to insert
  SELECT COUNT(*) INTO v_have FROM Members;
  v_need := GREATEST(p_target_total - v_have, 0);
  IF v_need = 0 THEN
    DBMS_OUTPUT.PUT_LINE('No new members needed (already at or above target).');
    RETURN;
  END IF;

  base_per_bucket := TRUNC(v_need / v_buckets);
  remainder_bkt   := MOD(v_need, v_buckets);

  -- iterate evenly across 20 buckets
  FOR b IN 0 .. v_buckets-1 LOOP
    b_start := ADD_MONTHS(v_start, 12*b);
    b_end   := LEAST(v_end, ADD_MONTHS(b_start, 12) - 1);
    IF b_end < b_start THEN CONTINUE; END IF;

    -- distribute remainder: first R buckets get +1
    n_in_bucket := base_per_bucket + CASE WHEN b < remainder_bkt THEN 1 ELSE 0 END;

    FOR i IN 1 .. n_in_bucket LOOP
      -- 1) pick a registration date uniformly within the bucket
      v_reg_date := rand_date(b_start, b_end);

      -- 2) decide whether this row aims to be active (per-bucket ratio)
      --    If true, choose enough renewals to cross cutoff; else choose fewer than needed.
      --    expiry_after_renewals(reg, k) = ADD_MONTHS(reg, 12*(1+k)) - 1
      k_min_active := CEIL(MONTHS_BETWEEN(TRUNC(p_cutoff)+1, TRUNC(v_reg_date)) / 12) - 1;
      IF k_min_active < 0 THEN k_min_active := 0; END IF;

      k_max_cap := FLOOR(MONTHS_BETWEEN(TRUNC(p_cap_expiry)+1, TRUNC(v_reg_date)) / 12) - 1;
      IF k_max_cap < 0 THEN k_max_cap := 0; END IF;

      IF DBMS_RANDOM.VALUE(0,1) < p_active_ratio THEN
        -- target ACTIVE
        IF k_min_active <= k_max_cap THEN
          k_chosen := TRUNC(DBMS_RANDOM.VALUE(k_min_active, k_max_cap + 1));
        ELSE
          -- cap too tight; still pick the minimal to make as-close-as-possible
          k_chosen := k_min_active;
        END IF;
      ELSE
        -- target EXPIRED (if possible)
        IF k_min_active > 0 THEN
          k_chosen := TRUNC(DBMS_RANDOM.VALUE(0, k_min_active));  -- [0 .. k_min_active-1]
        ELSE
          k_chosen := 0;  -- cannot force expired if even 0-year covers cutoff
        END IF;
      END IF;

      v_exp_date := expiry_after_renewals(v_reg_date, k_chosen);
      v_member_status := CASE WHEN v_exp_date >= TRUNC(p_cutoff) THEN 'active' ELSE 'expire' END;

      -- 3) synthesize identity
      v_member_id := next_member_id();
      v_seq_num   := TO_NUMBER(REGEXP_SUBSTR(v_member_id, '\d+'));
      v_member_name    := pick_one(c_first_names) || ' ' || pick_one(c_last_names);
      v_member_tel     := make_phone(v_seq_num);
      v_member_email   := make_email(v_seq_num);
      v_member_age    := TRUNC(DBMS_RANDOM.VALUE(12, 75)); -- 75 exclusive -> 12..74
      v_member_gender := CASE WHEN DBMS_RANDOM.VALUE(0,1) < 0.65 THEN 'female' ELSE 'male' END;
      v_member_address := TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(10,300))) || ' '
                          || pick_one(c_streets) || ', ' || pick_one(c_cities)
                          || ', ' || pick_one(c_states) || ', Malaysia';

      -- 4) insert
      INSERT INTO Members(memberId, memberName, memberTel, memberEmail,memberGender,memberAge, memberAddress,
                          memberStatus, registrationDate, expireDate)
      VALUES (v_member_id, v_member_name, v_member_tel, v_member_email, v_member_gender,v_member_age,v_member_address,
              v_member_status, v_reg_date, v_exp_date);
    END LOOP;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Inserted ' || v_need || ' members evenly across '||v_buckets||' years.');
END;
/


-- Example: grow to 7000 total members, 75% active, in your date window
BEGIN
  generate_members(
    p_target_total => 7500,
    p_active_ratio => 0.75,
    p_reg_start    => DATE '2004-07-01',
    p_reg_end      => DATE '2024-06-30',
    p_cutoff       => DATE '2024-06-30'
  );
END;
/

-- ✅ Quick checks
-- Total count:
SELECT COUNT(*) AS total_members FROM Members;

-- Active vs expired by your rule (derived from expireDate):
SELECT
  SUM(CASE WHEN expireDate >= DATE '2024-06-30' THEN 1 ELSE 0 END) AS active_by_rule,
  SUM(CASE WHEN expireDate <  DATE '2024-06-30' THEN 1 ELSE 0 END) AS expired_by_rule
FROM Members;

-- Verify status column matches the rule
SELECT COUNT(*) AS mismatches
FROM Members
WHERE (memberStatus = 'active' AND expireDate <  DATE '2024-06-30')
   OR (memberStatus = 'expire' AND expireDate >= DATE '2024-06-30');

SELECT EXTRACT(YEAR FROM registrationDate) y, COUNT(*) n
FROM Members GROUP BY EXTRACT(YEAR FROM registrationDate) ORDER BY y;

-- Range check
SELECT MIN(memberAge) AS min_age, MAX(memberAge) AS max_age, ROUND(AVG(memberAge),2) AS avg_age
FROM Members;

-- Gender split
SELECT memberGender, COUNT(*) AS cnt,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 2) AS pct
FROM Members
GROUP BY memberGender;

-- Your existing status rule checks still apply
