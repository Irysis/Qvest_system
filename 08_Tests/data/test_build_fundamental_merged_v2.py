"""test_build_fundamental_merged_v2.py — 02_Infrastructure/data/build_fundamental_merged_v2.R 합성 자료 시험
(운영 .cache 무접촉 · 등록부와 파생 공식 파일만 실물을 읽는다).

사례 (A · B = 12월 결산):
  T1 <=2014 분기: A 201412 TotalAssets → Freq Q · Source QW_V2 · 이름 대응(RetainedEarnings ← v2 RetainedEarnings,
     ShortTermBorr ← v2 CurrentBorr) · 파생 TotalDebt = ShortTermBorr + LongTermBorr
  T2 2015 연간(일치): A 201512 Revenue = 네 분기 합 100 · TotalAssets = 연말 값 · Source QW_V2 · Freq A ·
     Factor_Date = 연말 키 날짜
  T3 정정 의심: B FY2016 → TotalAssets = DART 값 999(퀀티 120 아님) · Source DART_RESTATED · Factor_Date = DART 날짜 ·
     DART 에 없는 퀀티 전용 FCF1 → QW_V2_DELAYED(미룬 날짜)
  T4 불변식: 키 중복 없음 · Factor_Date > Period_Date
  TC 대조군: 같은 자료에서 B 의 Check 를 agree 로 바꾸면 TotalAssets = 퀀티 120 · Source QW_V2 — T3 의 DART 값은
     정정 의심 판정에서만 나온다
실행: .venv_qvest_ml/Scripts/python.exe -X utf8 08_Tests/data/test_build_fundamental_merged_v2.py
"""
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

ROOT = Path(os.environ.get("QM_ROOT") or Path(__file__).resolve().parents[2])
SUT = ROOT / "02_Infrastructure/data/build_fundamental_merged_v2.R"
REG = ROOT / "02_Infrastructure/data/qw_updatefile_registry.json"
RS = os.environ.get("QVEST_RSCRIPT") or r"C:\Program Files\R\R-4.6.2\bin\Rscript.exe"
PASS = FAIL = 0


def ok(m):
    global PASS; PASS += 1; print("  OK  ", m)


def ng(m):
    global FAIL; FAIL += 1; print("  FAIL", m)


def D(s):
    return dt.date.fromisoformat(s)


def qrow(tk, p, item, v, fd, check):
    y, m = int(p[:4]), int(p[4:])
    pe = (pd.Timestamp(y, m, 1) + pd.offsets.MonthEnd(0)).date()
    return dict(Ticker=tk, Period=p, Period_Date=pe, Item=item, Value=float(v), Avail_Date=D(fd) - dt.timedelta(days=1),
                Factor_Date=D(fd), Avail_Basis="qw_report", Check=check, Db="X")


def setup(t: Path, b_check="restated"):
    (t / ".cache/fundamental_v2").mkdir(parents=True)
    (t / ".cache/qw_fund_v2").mkdir(parents=True)
    rows = [qrow("A", "201412", "TotalAssets", 50, "2015-03-20", "pre2015"),
            qrow("A", "201412", "RetainedEarnings", 7, "2015-03-20", "pre2015"),
            qrow("A", "201412", "CurrentBorr", 3, "2015-03-20", "pre2015"),
            qrow("A", "201412", "LongTermBorr", 4, "2015-03-20", "pre2015")]
    for p, v, fd in [("201503", 10, "2015-05-15"), ("201506", 20, "2015-08-14"), ("201509", 30, "2015-11-16"), ("201512", 40, "2016-03-21")]:
        rows.append(qrow("A", p, "Revenue", v, fd, "agree"))
    rows.append(qrow("A", "201512", "TotalAssets", 60, "2016-03-21", "agree"))
    # B FY2016: restated (v2 already delayed the dates to the FY2017 report: 2018-03-22)
    for p in ["201603", "201606", "201609", "201612"]:
        rows.append(qrow("B", p, "Revenue", 25, "2018-03-22" if b_check == "restated" else "2017-03-24", b_check))
        rows.append(qrow("B", p, "FCF1", 1, "2018-03-22" if b_check == "restated" else "2017-03-24", b_check))
    rows.append(qrow("B", "201612", "TotalAssets", 120, "2018-03-22" if b_check == "restated" else "2017-03-24", b_check))
    q = pd.DataFrame(rows)
    pq.write_table(pa.Table.from_pandas(q, preserve_index=False), t / ".cache/fundamental_v2/fund_v2_quarterly.parquet")
    ck = pd.DataFrame([dict(Ticker="B", FY=2016, Item="TotalAssets", QW_Value=120.0, DART_Value=999.0, Rel_Diff=0.88,
                            DART_Date=D("2017-03-23"), DART_Factor_Date=D("2017-03-24"), Same=False),
                       dict(Ticker="A", FY=2015, Item="TotalAssets", QW_Value=60.0, DART_Value=60.0, Rel_Diff=0.0,
                            DART_Date=D("2016-03-18"), DART_Factor_Date=D("2016-03-21"), Same=True)])
    pq.write_table(pa.Table.from_pandas(ck, preserve_index=False), t / ".cache/fundamental_v2/fund_v2_annual_check.parquet")
    pd.DataFrame({"Ticker": ["A", "B"], "FiscalMonth": ["12", "12"], "fetched_at": ["x", "x"]}).to_parquet(t / ".cache/qw_fund_v2/fiscal_month.parquet")
    pd.DataFrame({"Ticker": ["B"], "bsns_year": [2016], "Factor_Date": [D("2017-03-31")], "TotalAssets": [999.0],
                  "Revenue": [101.0], "ROA": [0.05]}).to_parquet(t / ".cache/fundamental_dart.parquet")


def run(t: Path):
    out = t / ".cache/fundamental_merged_v2.parquet"
    r = subprocess.run([RS, "--vanilla", str(SUT), "--root", str(t), "--registry", str(REG), "--out", str(out)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout + r.stderr), out


def get(m, tk, p, item):
    r = m[(m["Ticker"] == tk) & (m["Period"] == p) & (m["Item"] == item)]
    return r.iloc[0] if len(r) == 1 else None


T = Path(tempfile.mkdtemp(prefix="mergedv2_"))
try:
    if not SUT.exists() or not Path(RS).exists():
        raise SystemExit(f"missing SUT or Rscript: {SUT} {RS}")
    a = T / "a"; setup(a)
    rc, log, out = run(a)
    if rc != 0:
        ng(f"build rc={rc}: {log[-1500:]}"); raise SystemExit
    m = pd.read_parquet(out)
    for c in ("Period_Date", "Factor_Date"):
        m[c] = pd.to_datetime(m[c])
    r_ta, r_re, r_sb, r_td = (get(m, "A", "201412", i) for i in ("TotalAssets", "RetainedEarnings", "ShortTermBorr", "TotalDebt"))
    ok1 = all(x is not None for x in (r_ta, r_re, r_sb, r_td)) and r_ta["Freq"] == "Q" and r_ta["Source"] == "QW_V2" and \
        r_re["Value"] == 7 and r_sb["Value"] == 3 and abs(r_td["Value"] - 7) < 1e-9
    ok("T1 <=2014 분기 · 이름 대응 · TotalDebt = 3 + 4") if ok1 else ng(f"T1 {r_ta} {r_re} {r_sb} {r_td}")
    rv, ta = get(m, "A", "201512", "Revenue"), get(m, "A", "201512", "TotalAssets")
    ok2 = rv is not None and ta is not None and rv["Value"] == 100 and ta["Value"] == 60 and rv["Freq"] == "A" and \
        rv["Source"] == "QW_V2" and str(rv["Factor_Date"].date()) == "2016-03-21"
    ok("T2 2015 연간: 매출 = 네 분기 합 100 · 자산 = 연말 60 · 연말 키 날짜") if ok2 else ng(f"T2 {rv} {ta}")
    bta, bf = get(m, "B", "201612", "TotalAssets"), get(m, "B", "201612", "FCF1")
    ok3 = bta is not None and bf is not None and bta["Value"] == 999 and bta["Source"] == "DART_RESTATED" and \
        str(bta["Factor_Date"].date()) == "2017-03-24" and bf["Source"] == "QW_V2_DELAYED" and str(bf["Factor_Date"].date()) == "2018-03-22"
    ok("T3 정정 의심: DART 기록(999 · DART 날짜) · 퀀티 전용 FCF1 은 미룬 날짜") if ok3 else ng(f"T3 {bta} {bf}")
    dup = m.duplicated(["Ticker", "Period", "Item"]).any()
    ok("T4 불변식: 키 중복 없음 · Factor_Date > Period_Date") if (not dup and (m["Factor_Date"] > m["Period_Date"]).all()) else ng("T4")
    c = T / "c"; setup(c, b_check="agree")
    rc, log, out = run(c)
    mc = pd.read_parquet(out) if rc == 0 else None
    cta = get(mc, "B", "201612", "TotalAssets") if mc is not None else None
    ok("TC 대조군(B = agree) → 퀀티 120 · QW_V2 — DART 값은 정정 의심에서만") if cta is not None and cta["Value"] == 120 and \
        cta["Source"] == "QW_V2" else ng(f"TC rc={rc} {cta}")
except SystemExit:
    pass
except Exception as e:  # noqa: BLE001
    import traceback; traceback.print_exc()
    ng(f"harness error: {e!r}")
finally:
    shutil.rmtree(T, ignore_errors=True)

print(f"\n합계: 통과 {PASS} · 실패 {FAIL}")
print(json.dumps({"test": "build_fundamental_merged_v2", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(1 if FAIL else 0)
