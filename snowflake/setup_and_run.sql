-- ============================================================================
-- Snowflake: load the CSVs and run the validation checks
-- Free trial: https://signup.snowflake.com  (choose any cloud/region)
-- Run these statements in a Snowflake worksheet (Projects > Worksheets).
-- ============================================================================

CREATE DATABASE IF NOT EXISTS HEALTHCARE_DQ;
CREATE SCHEMA IF NOT EXISTS HEALTHCARE_DQ.RAW;
USE SCHEMA HEALTHCARE_DQ.RAW;

-- All columns are VARCHAR on purpose: the checks detect bad types themselves.
CREATE OR REPLACE TABLE raw_patients   (patient_id VARCHAR, birth_date VARCHAR, gender VARCHAR, state VARCHAR, registration_date VARCHAR);
CREATE OR REPLACE TABLE raw_encounters (encounter_id VARCHAR, patient_id VARCHAR, encounter_date VARCHAR, encounter_type VARCHAR, provider_id VARCHAR, discharge_date VARCHAR);
CREATE OR REPLACE TABLE raw_claims     (claim_id VARCHAR, encounter_id VARCHAR, patient_id VARCHAR, claim_date VARCHAR, billed_amount VARCHAR, paid_amount VARCHAR, status VARCHAR, diagnosis_code VARCHAR);

CREATE OR REPLACE FILE FORMAT csv_fmt TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"' NULL_IF = () EMPTY_FIELD_AS_NULL = FALSE;
CREATE OR REPLACE STAGE raw_stage FILE_FORMAT = csv_fmt;

-- Upload the three CSVs from the data/ folder:
--   Snowsight UI:  Data > Databases > HEALTHCARE_DQ > RAW > Stages > RAW_STAGE > "+ Files"
--   (or from SnowSQL:  PUT file://data/patients.csv @raw_stage;  etc.)

COPY INTO raw_patients   FROM @raw_stage/patients.csv;
COPY INTO raw_encounters FROM @raw_stage/encounters.csv;
COPY INTO raw_claims     FROM @raw_stage/claims.csv;

-- Quick sanity check: expect roughly 5,050 / 19,600 / 17,700 rows
SELECT 'raw_patients' AS t, COUNT(*) AS n FROM raw_patients
UNION ALL SELECT 'raw_encounters', COUNT(*) FROM raw_encounters
UNION ALL SELECT 'raw_claims', COUNT(*) FROM raw_claims;

-- Now open sql/01_validation_checks.sql, paste it here and run it.
-- To keep the results as a table you can monitor over time:
--   CREATE OR REPLACE TABLE dq_results AS <paste the full SELECT from 01_validation_checks.sql>;
-- Then drill into the trend failure with sql/02_trend_anomaly_detail.sql.
