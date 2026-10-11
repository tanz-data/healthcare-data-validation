-- ============================================================================
-- Healthcare data validation checks
-- Tables (all columns loaded as text/VARCHAR so type problems can be detected):
--   raw_patients, raw_encounters, raw_claims
-- Portable across DuckDB, Snowflake and Databricks SQL
-- Output: one row per check -> category, table, check, failed_rows, total_rows, fail_pct, status
-- ============================================================================
WITH daily AS (
    SELECT TRY_CAST(encounter_date AS DATE) AS d, COUNT(*) AS cnt
    FROM raw_encounters
    WHERE TRY_CAST(encounter_date AS DATE) IS NOT NULL
    GROUP BY TRY_CAST(encounter_date AS DATE)
),
trend AS (
    SELECT d, cnt,
           AVG(cnt) OVER (ORDER BY d ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS trailing_avg
    FROM daily
),
checks AS (
    -- ---------------------------- COMPLETENESS ----------------------------
    SELECT 'Completeness' AS category, 'raw_patients' AS table_name, 'birth_date is not null/blank' AS check_name,
           SUM(CASE WHEN birth_date IS NULL OR TRIM(birth_date) = '' THEN 1 ELSE 0 END) AS failed_rows, COUNT(*) AS total_rows
    FROM raw_patients
    UNION ALL
    SELECT 'Completeness', 'raw_patients', 'gender is not null/blank',
           SUM(CASE WHEN gender IS NULL OR TRIM(gender) = '' THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_patients
    UNION ALL
    SELECT 'Completeness', 'raw_encounters', 'patient_id is not null/blank',
           SUM(CASE WHEN patient_id IS NULL OR TRIM(patient_id) = '' THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_encounters
    UNION ALL
    SELECT 'Completeness', 'raw_claims', 'encounter_id is not null/blank',
           SUM(CASE WHEN encounter_id IS NULL OR TRIM(encounter_id) = '' THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims
    UNION ALL
    SELECT 'Completeness', 'raw_claims', 'billed_amount is not null/blank',
           SUM(CASE WHEN billed_amount IS NULL OR TRIM(billed_amount) = '' THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims

    -- ----------------------------- UNIQUENESS -----------------------------
    UNION ALL
    SELECT 'Uniqueness', 'raw_patients', 'patient_id is unique (extra duplicate rows)',
           COUNT(*) - COUNT(DISTINCT patient_id), COUNT(*)
    FROM raw_patients
    UNION ALL
    SELECT 'Uniqueness', 'raw_encounters', 'encounter_id is unique (extra duplicate rows)',
           COUNT(*) - COUNT(DISTINCT encounter_id), COUNT(*)
    FROM raw_encounters
    UNION ALL
    SELECT 'Uniqueness', 'raw_claims', 'claim_id is unique (extra duplicate rows)',
           COUNT(*) - COUNT(DISTINCT claim_id), COUNT(*)
    FROM raw_claims

    -- ----------------------------- DATA TYPES -----------------------------
    UNION ALL
    SELECT 'Data type', 'raw_patients', 'birth_date is a valid date',
           SUM(CASE WHEN TRIM(birth_date) <> '' AND TRY_CAST(birth_date AS DATE) IS NULL THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_patients
    UNION ALL
    SELECT 'Data type', 'raw_encounters', 'encounter_date is a valid date',
           SUM(CASE WHEN TRIM(encounter_date) <> '' AND TRY_CAST(encounter_date AS DATE) IS NULL THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_encounters
    UNION ALL
    SELECT 'Data type', 'raw_claims', 'billed_amount is numeric',
           SUM(CASE WHEN TRIM(billed_amount) <> '' AND TRY_CAST(billed_amount AS DECIMAL(12,2)) IS NULL THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims
    UNION ALL
    SELECT 'Data type', 'raw_claims', 'paid_amount is numeric',
           SUM(CASE WHEN TRIM(paid_amount) <> '' AND TRY_CAST(paid_amount AS DECIMAL(12,2)) IS NULL THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims

    -- ------------------------ ACCURACY / VALIDITY -------------------------
    UNION ALL
    SELECT 'Accuracy', 'raw_patients', 'gender in (F, M, O)',
           SUM(CASE WHEN TRIM(gender) <> '' AND gender NOT IN ('F', 'M', 'O') THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_patients
    UNION ALL
    SELECT 'Accuracy', 'raw_patients', 'birth_date not in the future and after 1900',
           SUM(CASE WHEN TRY_CAST(birth_date AS DATE) > CURRENT_DATE
                      OR TRY_CAST(birth_date AS DATE) < CAST('1900-01-01' AS DATE) THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_patients
    UNION ALL
    SELECT 'Accuracy', 'raw_encounters', 'discharge_date is not before encounter_date',
           SUM(CASE WHEN TRY_CAST(discharge_date AS DATE) < TRY_CAST(encounter_date AS DATE) THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_encounters
    UNION ALL
    SELECT 'Accuracy', 'raw_claims', 'billed_amount is not negative',
           SUM(CASE WHEN TRY_CAST(billed_amount AS DECIMAL(12,2)) < 0 THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims
    UNION ALL
    SELECT 'Accuracy', 'raw_claims', 'paid_amount does not exceed billed_amount',
           SUM(CASE WHEN TRY_CAST(paid_amount AS DECIMAL(12,2)) > TRY_CAST(billed_amount AS DECIMAL(12,2)) THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims
    UNION ALL
    SELECT 'Accuracy', 'raw_claims', 'status in (PAID, DENIED, PENDING, ADJUSTED)',
           SUM(CASE WHEN status NOT IN ('PAID', 'DENIED', 'PENDING', 'ADJUSTED') THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims
    UNION ALL
    SELECT 'Accuracy', 'raw_claims', 'diagnosis_code matches ICD-10 pattern',
           SUM(CASE WHEN NOT REGEXP_LIKE(diagnosis_code, '^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$') THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims

    -- ---------------------------- RELATIONSHIPS ---------------------------
    UNION ALL
    SELECT 'Relationship', 'raw_encounters', 'patient_id exists in raw_patients',
           SUM(CASE WHEN TRIM(e.patient_id) <> '' AND p.patient_id IS NULL THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_encounters e
    LEFT JOIN (SELECT DISTINCT patient_id FROM raw_patients) p ON e.patient_id = p.patient_id
    UNION ALL
    SELECT 'Relationship', 'raw_claims', 'encounter_id exists in raw_encounters',
           SUM(CASE WHEN TRIM(c.encounter_id) <> '' AND e.encounter_id IS NULL THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims c
    LEFT JOIN (SELECT DISTINCT encounter_id FROM raw_encounters) e ON c.encounter_id = e.encounter_id
    UNION ALL
    SELECT 'Relationship', 'raw_claims', 'claim patient_id matches its encounter patient_id',
           SUM(CASE WHEN e.encounter_id IS NOT NULL AND TRIM(e.patient_id) <> '' AND c.patient_id <> e.patient_id THEN 1 ELSE 0 END), COUNT(*)
    FROM raw_claims c
    LEFT JOIN (SELECT DISTINCT encounter_id, patient_id FROM raw_encounters) e ON c.encounter_id = e.encounter_id

    -- -------------------------------- TREND --------------------------------
    UNION ALL
    SELECT 'Trend', 'raw_encounters', 'daily volume >= 50% of trailing 7-day average (days failing)',
           SUM(CASE WHEN cnt < 0.5 * trailing_avg THEN 1 ELSE 0 END), COUNT(*)
    FROM trend
)
SELECT category, table_name, check_name, failed_rows, total_rows,
       ROUND(100.0 * failed_rows / total_rows, 2) AS fail_pct,
       CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY category, table_name, check_name;
