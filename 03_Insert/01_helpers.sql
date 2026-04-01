-- 01_helpers.sql
-- Utility sequences and helper functions for ID formatting and random dates.
-- Run this first.

-- ========================
-- Drop sequences (ignore errors if they don't exist)
-- ========================
-- DROP SEQUENCE seq_supplier;
-- DROP SEQUENCE seq_discount;
-- DROP SEQUENCE seq_copy;
-- DROP SEQUENCE seq_order;
-- DROP SEQUENCE seq_detail;
-- DROP SEQUENCE seq_sorder;
-- DROP SEQUENCE seq_salesdetail;
-- DROP SEQUENCE seq_borrow;
-- DROP SEQUENCE seq_payment;
-- DROP SEQUENCE seq_receipt;

-- ========================
-- Create sequences
-- ========================
CREATE SEQUENCE seq_supplier START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_discount START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_copy START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_order START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_detail START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_sorder START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 999999999999 NOCACHE NOCYCLE;
Create SEQUENCE seq_salesdetail START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_borrow START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_payment START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_receipt START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_fine START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;


-- ========================
-- Helper functions
-- ========================

-- Random date in [p_start, p_end]
CREATE OR REPLACE FUNCTION rnd_date(p_start DATE, p_end DATE) RETURN DATE IS
  span NUMBER := p_end - p_start;
BEGIN
  RETURN p_start + TRUNC(DBMS_RANDOM.value(0, GREATEST(span,1)));
END;
/

-- ID formatter: fmt_id('PO', 12, 4) -> 'PO0012'
CREATE OR REPLACE FUNCTION fmt_id(p_prefix VARCHAR2, p_n NUMBER, p_len PLS_INTEGER := 3)
RETURN VARCHAR2 IS
BEGIN
  RETURN p_prefix || LPAD(p_n, p_len, '0');
END;
/

SET SERVEROUTPUT ON