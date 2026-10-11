"""
Run the SQL validation checks locally with DuckDB (no cloud account needed).

    pip install duckdb
    python data/generate_data.py
    python run_checks.py

Writes results/dq_report.csv and results/dq_report.md
"""
import csv
import os

import duckdb

ROOT = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(ROOT, "data")
SQL = os.path.join(ROOT, "sql")
OUT = os.path.join(ROOT, "results")
os.makedirs(OUT, exist_ok=True)

con = duckdb.connect()
# DuckDB has regexp_matches; Snowflake/Databricks have REGEXP_LIKE. Alias it so one SQL file runs everywhere.
con.execute("CREATE MACRO regexp_like(s, p) AS regexp_matches(s, p)")

# Load every column as text so type problems (e.g. 'N/A' in an amount column) stay visible to the checks
for table, f in [("raw_patients", "patients.csv"), ("raw_encounters", "encounters.csv"), ("raw_claims", "claims.csv")]:
    con.execute(
        f"CREATE TABLE {table} AS SELECT * FROM read_csv('{os.path.join(DATA, f)}', header=true, all_varchar=true)"
    )


def run(path):
    with open(path) as fh:
        cur = con.execute(fh.read())
    return [d[0] for d in cur.description], cur.fetchall()


cols, rows = run(os.path.join(SQL, "01_validation_checks.sql"))
with open(os.path.join(OUT, "dq_report.csv"), "w", newline="") as f:
    w = csv.writer(f); w.writerow(cols); w.writerows(rows)

lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
lines += ["| " + " | ".join(str(v) for v in r) + " |" for r in rows]
failed = sum(1 for r in rows if r[-1] == "FAIL")
with open(os.path.join(OUT, "dq_report.md"), "w") as f:
    f.write(f"# Data quality report\n\n{failed} of {len(rows)} checks failed.\n\n" + "\n".join(lines) + "\n")

print(f"{failed} of {len(rows)} checks failed\n")
for r in rows:
    print(f"{r[-1]:4} | {r[0]:12} | {r[1]:15} | {r[2][:62]:62} | {r[3]:>5} / {r[4]:<6} ({r[5]}%)")

dcols, drows = run(os.path.join(SQL, "02_trend_anomaly_detail.sql"))
print("\nTrend anomaly days:")
for r in drows:
    print("  ", dict(zip(dcols, r)))
