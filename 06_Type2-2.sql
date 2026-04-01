DROP PROCEDURE Prod_Update_DimMembers_T2;


CREATE OR REPLACE PROCEDURE Prod_Update_DimMembers_T2 (
  p_member_id        IN VARCHAR2,
  p_member_name      IN VARCHAR2,
  p_member_age_range IN VARCHAR2,
  p_member_gender    IN VARCHAR2,
  p_state            IN VARCHAR2,
  p_city             IN VARCHAR2,
  p_member_status    IN VARCHAR2,   -- 'active' or 'expire'
  p_registration_date IN DATE
) IS
  CURSOR cur_curr IS
    SELECT *
      FROM DimMembers
     WHERE memberId = p_member_id
       AND curr_ind = 'Y';

  v_curr        cur_curr%ROWTYPE;
  v_has_curr    BOOLEAN := FALSE;

  v_today       DATE := TRUNC(SYSDATE);
  v_yesterday   DATE := TRUNC(SYSDATE) - 1;
  v_open_ended  DATE := DATE '9999-12-31';

  v_name_up     VARCHAR2(100) := UPPER(TRIM(p_member_name));
  v_member_age  VARCHAR2(50)  := UPPER(TRIM(p_member_age_range));
  v_member_gender CHAR(1) := UPPER(TRIM(p_member_gender));
  v_state_up    VARCHAR2(20)  := UPPER(TRIM(p_state));
  v_city_up     VARCHAR2(20)  := UPPER(TRIM(p_city));
BEGIN
  OPEN cur_curr; FETCH cur_curr INTO v_curr; v_has_curr := cur_curr%FOUND; CLOSE cur_curr;

  ----------------------------------------------------------------------
  -- Case A: New member (no current row exists) → Insert first current row
  ----------------------------------------------------------------------
  IF NOT v_has_curr THEN
    INSERT INTO DimMembers (
      memberKey, memberId, memberName,memberAgeRange, memberGender, state, city, MemberDuration,
      effective_date, expiration_date, curr_ind
    )
    VALUES (
      seq_dim_member.NEXTVAL,
      p_member_id,
      v_name_up,
      v_member_age,
      v_member_gender,
      v_state_up,
      v_city_up,
      ROUND(MONTHS_BETWEEN(v_today, TRUNC(p_registration_date))/12, 1) || ' years',
      TRUNC(p_registration_date),   -- effective from registrationDate
      v_open_ended,                 -- open-ended until change
      CASE WHEN LOWER(p_member_status)='active' THEN 'Y' ELSE 'N' END
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Inserted new member row: '||p_member_id);
    RETURN;
  END IF;

  ----------------------------------------------------------------------
  -- Case B: Member exists and ACTIVE → check for changes
  ----------------------------------------------------------------------
  IF LOWER(p_member_status) = 'active' THEN
    -- detect changes in name/state/city
    IF UPPER(NVL(v_curr.memberName,'~')) <> v_name_up
       OR UPPER(NVL(v_curr.state,'~'))    <> v_state_up
       OR UPPER(NVL(v_curr.city,'~'))     <> v_city_up
    THEN
      -- close current row
      UPDATE DimMembers
         SET expiration_date = GREATEST(v_yesterday, TRUNC(v_curr.effective_date)),
             curr_ind        = 'N'
       WHERE memberKey = v_curr.memberKey
         AND curr_ind  = 'Y';

      -- insert new current row
      INSERT INTO DimMembers (
        memberKey, memberId, memberName, memberAgeRange, memberGender,state, city, MemberDuration,
        effective_date, expiration_date, curr_ind
      )
      VALUES (
        seq_dim_member.NEXTVAL,
        p_member_id,
        v_name_up,
        v_member_age,
        v_member_gender,
        v_state_up,
        v_city_up,
        ROUND(MONTHS_BETWEEN(v_today, TRUNC(p_registration_date))/12, 1) || ' years',
        v_today,       -- effective from today
        v_open_ended,  -- open-ended
        'Y'
      );
    END IF;

  ----------------------------------------------------------------------
  -- Case C: Member is INACTIVE → close current row, no new current
  ----------------------------------------------------------------------
  ELSE
    UPDATE DimMembers
       SET expiration_date = GREATEST(v_yesterday, TRUNC(v_curr.effective_date)),
           curr_ind        = 'N'
     WHERE memberKey = v_curr.memberKey
       AND curr_ind  = 'Y';
  END IF;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Processed member: '||p_member_id);

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Error in Prod_Update_DimMembers_T2: '||SQLERRM);
    RAISE;
END Prod_Update_DimMembers_T2;
/


BEGIN
  Prod_Update_DimMembers_T2(
    p_member_id         => 'M1752',
    p_member_name       => 'Siti Zakaria',
    p_member_age_range  => '17 to 25',
    p_member_gender     => 'F', 
    p_state             => 'Johor',
    p_city              => 'Johor Bahru',
    p_member_status     => 'active',
    p_registration_date => DATE '2023-07-01'
  );
END;
/

select * from DIMMEMBERS where MEMBERID ='M1752';

