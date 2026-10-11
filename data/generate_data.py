"""
Generate a SYNTHETIC healthcare dataset (patients, encounters, claims) with
deliberately injected data-quality problems, so the SQL validation checks
have something real to catch.

No real patient data is used. Everything is randomly generated.

Usage:  python generate_data.py          -> writes CSVs next to this script
"""
import csv
import json
import os
import random
from datetime import date, timedelta

random.seed(42)
OUT = os.path.dirname(os.path.abspath(__file__))

N_PATIENTS = 5000
START = date(2026, 1, 1)
N_DAYS = 120
DROP_DAYS = {45, 46, 47}  # days with an abnormal volume drop (pipeline outage simulation)

STATES = ["CA", "TX", "NY", "FL", "IL", "PA", "OH", "GA", "NC", "MI"]
ENC_TYPES = ["OUTPATIENT", "INPATIENT", "EMERGENCY", "TELEHEALTH"]
DIAG = ["E11.9", "I10", "J45.909", "Z00.00", "M54.5", "K21.9", "F41.1", "N39.0", "R07.9", "E78.5"]
BAD_DIAG = ["ABC123", "12345", "e11.9", "I1"]

injected = {}


def bump(key, n=1):
    injected[key] = injected.get(key, 0) + n


def rate(p):
    return random.random() < p


# ---------------- patients ----------------
patients = []
for i in range(1, N_PATIENTS + 1):
    pid = f"P{i:05d}"
    birth = date(1930, 1, 1) + timedelta(days=random.randint(0, (date(2022, 12, 31) - date(1930, 1, 1)).days))
    birth_s = birth.isoformat()
    gender = random.choice(["F", "M", "O"])
    if rate(0.02):
        birth_s = ""; bump("patients.birth_date_blank")
    elif rate(0.004):
        birth_s = f"{random.randint(2030, 2035)}-06-15"; bump("patients.birth_date_in_future")
    elif rate(0.003):
        birth_s = "1990-13-45"; bump("patients.birth_date_bad_format")
    if rate(0.01):
        gender = random.choice(["X", "unknown"]); bump("patients.gender_invalid")
    elif rate(0.01):
        gender = ""; bump("patients.gender_blank")
    reg = START - timedelta(days=random.randint(30, 2000))
    patients.append([pid, birth_s, gender, random.choice(STATES), reg.isoformat()])

# duplicate ~1% of patient rows
for row in random.sample(patients[:], int(N_PATIENTS * 0.01)):
    patients.append(list(row)); bump("patients.duplicate_patient_id_rows")

# ---------------- encounters ----------------
encounters = []
eid = 0
for d in range(N_DAYS):
    day = START + timedelta(days=d)
    n = random.randint(15, 25) if d in DROP_DAYS else random.randint(140, 190)
    if d in DROP_DAYS:
        bump("encounters.volume_drop_days")
    for _ in range(n):
        eid += 1
        enc_id = f"E{eid:06d}"
        pid = f"P{random.randint(1, N_PATIENTS):05d}"
        etype = random.choice(ENC_TYPES)
        discharge = ""
        if etype == "INPATIENT":
            discharge = (day + timedelta(days=random.randint(1, 10))).isoformat()
            if rate(0.01):
                discharge = (day - timedelta(days=random.randint(1, 3))).isoformat()
                bump("encounters.discharge_before_encounter")
        enc_date = day.isoformat()
        if rate(0.01):
            pid = f"P{random.randint(90000, 99999)}"; bump("encounters.orphan_patient_id")
        elif rate(0.005):
            pid = ""; bump("encounters.patient_id_blank")
        if rate(0.004):
            enc_date = "2026-02-30"; bump("encounters.encounter_date_bad_format")
        encounters.append([enc_id, pid, enc_date, etype, f"PR{random.randint(1, 50):03d}", discharge])

# ---------------- claims ----------------
claims = []
cid = 0
valid_encs = [e for e in encounters]
for e in valid_encs:
    if not rate(0.9):
        continue
    cid += 1
    claim_id = f"C{cid:06d}"
    enc_id, pid = e[0], e[1]
    try:
        base = date.fromisoformat(e[2])
    except ValueError:
        base = START
    claim_date = (base + timedelta(days=random.randint(0, 5))).isoformat()
    billed = round(random.uniform(50, 5000), 2)
    status = random.choices(["PAID", "DENIED", "PENDING", "ADJUSTED"], [70, 10, 15, 5])[0]
    paid = round(billed * random.uniform(0.5, 1.0), 2) if status in ("PAID", "ADJUSTED") else (0.0 if status == "DENIED" else "")
    diag = random.choice(DIAG)

    billed_s = f"{billed:.2f}"
    if rate(0.005):
        billed_s = f"-{billed:.2f}"; bump("claims.billed_negative")
    elif rate(0.007):
        billed_s = "N/A"; bump("claims.billed_not_numeric")
    elif rate(0.004):
        billed_s = ""; bump("claims.billed_blank")
    paid_s = "" if paid == "" else f"{paid:.2f}"
    if status == "PAID" and rate(0.01):
        paid_s = f"{billed * random.uniform(1.1, 1.8):.2f}"; bump("claims.paid_exceeds_billed")
    if rate(0.012):
        diag = random.choice(BAD_DIAG); bump("claims.diagnosis_code_invalid")
    if rate(0.01):
        enc_id = f"E{random.randint(900000, 999999)}"; bump("claims.orphan_encounter_id")
    elif rate(0.005):
        enc_id = ""; bump("claims.encounter_id_blank")
    elif rate(0.008) and pid:
        other = f"P{random.randint(1, N_PATIENTS):05d}"
        if other != pid:
            pid = other; bump("claims.patient_mismatch_with_encounter")
    claims.append([claim_id, enc_id, pid, claim_date, billed_s, paid_s, status, diag])

for row in random.sample(claims[:], int(len(claims) * 0.006)):
    claims.append(list(row)); bump("claims.duplicate_claim_id_rows")


def write(name, header, rows):
    with open(os.path.join(OUT, name), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


write("patients.csv", ["patient_id", "birth_date", "gender", "state", "registration_date"], patients)
write("encounters.csv", ["encounter_id", "patient_id", "encounter_date", "encounter_type", "provider_id", "discharge_date"], encounters)
write("claims.csv", ["claim_id", "encounter_id", "patient_id", "claim_date", "billed_amount", "paid_amount", "status", "diagnosis_code"], claims)

with open(os.path.join(OUT, "injected_issues.json"), "w") as f:
    json.dump(dict(sorted(injected.items())), f, indent=2)

print(f"patients={len(patients)} encounters={len(encounters)} claims={len(claims)}")
for k, v in sorted(injected.items()):
    print(f"  injected {k}: {v}")
