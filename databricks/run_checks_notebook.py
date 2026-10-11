# Databricks notebook source
# ============================================================================
# Databricks: load the CSVs and run the validation checks
# Free edition: https://www.databricks.com/learn/free-edition
#
# 1. Upload patients.csv, encounters.csv, claims.csv to a Unity Catalog Volume
#    (Catalog > your catalog > default schema > Create > Volume, then upload files).
# 2. Set VOLUME_PATH below to that volume, e.g. /Volumes/workspace/default/healthcare_dq
# 3. Import this file as a notebook (File > Import) and run the cells.
#    The "# COMMAND ----------" lines split it into cells.
# ============================================================================

# COMMAND ----------
VOLUME_PATH = "/Volumes/workspace/default/healthcare_dq"   # <-- change to your volume

# COMMAND ----------
# Read every column as string (header=True, no schema inference) so bad types stay visible to the checks
for table, f in [("raw_patients", "patients.csv"), ("raw_encounters", "encounters.csv"), ("raw_claims", "claims.csv")]:
    df = spark.read.option("header", True).option("inferSchema", False).csv(f"{VOLUME_PATH}/{f}")
    df.createOrReplaceTempView(table)
    print(table, df.count())

# COMMAND ----------
# Paste the full contents of sql/01_validation_checks.sql between the triple quotes
CHECKS_SQL = """
-- paste sql/01_validation_checks.sql here
"""
results = spark.sql(CHECKS_SQL)
display(results)

# COMMAND ----------
# Optional: keep results as a Delta table for monitoring over time
# results.write.mode("overwrite").saveAsTable("dq_results")

# COMMAND ----------
# Drill-down: paste sql/02_trend_anomaly_detail.sql between the quotes
TREND_SQL = """
-- paste sql/02_trend_anomaly_detail.sql here
"""
display(spark.sql(TREND_SQL))
