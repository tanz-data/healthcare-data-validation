-- Drill-down for the Trend check: which days had an unexpected drop in encounter volume?
-- Use this after 01_validation_checks.sql flags the trend check, to investigate the pipeline.
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
)
SELECT d AS encounter_day, cnt AS encounters, ROUND(trailing_avg, 1) AS trailing_7day_avg,
       ROUND(100.0 * cnt / trailing_avg, 1) AS pct_of_average
FROM trend
WHERE cnt < 0.5 * trailing_avg
ORDER BY d;
