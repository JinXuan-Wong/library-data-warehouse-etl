BEGIN
   -- 1) Drop all views
   FOR v IN (SELECT view_name FROM user_views) LOOP
      EXECUTE IMMEDIATE 'DROP VIEW "' || v.view_name || '"';
   END LOOP;

   -- 2) Drop all procedures
   FOR p IN (SELECT object_name FROM user_objects WHERE object_type = 'PROCEDURE') LOOP
      EXECUTE IMMEDIATE 'DROP PROCEDURE "' || p.object_name || '"';
   END LOOP;

   -- 3) Drop all functions
   FOR f IN (SELECT object_name FROM user_objects WHERE object_type = 'FUNCTION') LOOP
      EXECUTE IMMEDIATE 'DROP FUNCTION "' || f.object_name || '"';
   END LOOP;

   -- 4) Drop all sequences
   FOR s IN (SELECT sequence_name FROM user_sequences) LOOP
      EXECUTE IMMEDIATE 'DROP SEQUENCE "' || s.sequence_name || '"';
   END LOOP;

   -- 5) Drop all tables
   FOR t IN (SELECT table_name FROM user_tables) LOOP
      EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS';
   END LOOP;
END;
/
