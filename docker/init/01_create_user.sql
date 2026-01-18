-- Create inexora test user for integration tests
-- This script runs automatically on container startup

ALTER SESSION SET CONTAINER = FREEPDB1;

-- Create user if not exists (Oracle 12c+ pattern)
DECLARE
  user_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO user_exists FROM all_users WHERE username = 'INEXORA';
  IF user_exists = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER inexora IDENTIFIED BY Welcome4321';
    EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO inexora';
    EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO inexora';
    EXECUTE IMMEDIATE 'GRANT CREATE TABLE TO inexora';
    EXECUTE IMMEDIATE 'GRANT CREATE SEQUENCE TO inexora';
    EXECUTE IMMEDIATE 'GRANT CREATE PROCEDURE TO inexora';
    EXECUTE IMMEDIATE 'GRANT CREATE VIEW TO inexora';
    EXECUTE IMMEDIATE 'GRANT UNLIMITED TABLESPACE TO inexora';
    DBMS_OUTPUT.PUT_LINE('User INEXORA created successfully');
  ELSE
    DBMS_OUTPUT.PUT_LINE('User INEXORA already exists');
  END IF;
END;
/

EXIT;
