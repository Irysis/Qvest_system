"""test_build_fundamental_v2.py — 02_Infrastructure/data/build_fundamental_v2.py 합성 자료 시험(운영 .cache 무접촉).

사례 (종목 A = 12월 결산 · B = 3월 결산):
  T1 퀀티 공시일: A 201603(공시 20160513 금) → Avail 2016-05-13 · Factor_Date = 다음 거래일 2016-05-16(월)
  T2 DART 접수일이 더 늦음: A 201612(퀀티 20170320 · DART 접수 20170331) → Avail 2017-03-31 · dart_rcept
  T3 고정 규칙: A 201003(공시일 없음) → 2010-05-15 + 다음 거래일 · rule
  T4 3월 결산 연말 분기: B 201703(공시일 없음) → 2017-06-30(+3개월 말일) · non_dec_fy
  T5 정정 의심: A FY2017 자산총계 퀀티 120 · DART 110 → FY2017 네 분기 전부 Avail = FY2018 사업보고서 공개일(20190315) ·
     restated · 대조 표에 Same=False
  T6 일치: A FY2016 자산 100=100 · 매출 네 분기 합 100=100 → agree
  T7 불변식: 모든 행 Factor_Date > Avail_Date ≥ (분기말 다음날) · Factor_Date 는 달력의 거래일(달력 안일 때)
  TM 뮤테이션(--tol 10 = 검사 끔): T5 모양이 agree 가 되고 FY2017 Factor_Date 가 2018 년으로 당겨진다 = T5 는 검사의 발화다
실행: .venv_qvest_ml/Scripts/python.exe -X utf8 08_Tests/data/test_build_fundamental_v2.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(os.environ.get("QM_ROOT") or Path(__file__).resolve().parents[2])
SUT = ROOT / "02_Infrastructure/data/build_fundamental_v2.py"
PY = sys.executable
PASS = FAIL = 0


def ok(m):
    global PASS; PASS += 1; print("  OK  ", m)


def ng(m):
    global FAIL; FAIL += 1; print("  FAIL", m)


def long(rows):
    d = pd.DataFrame(rows, columns=["Ticker", "Period", "Item", "Value", "Text"])
    d["first_fetched_at"] = d["last_fetched_at"] = "2026-11-08T00:00:00"
    return d


def setup(t: Path):
    v2 = t / ".cache/qw_fund_v2"; v2.mkdir(parents=True)
    (t / ".cache/dart").mkdir(parents=True)
    bs = [("A", "201003", "TotalAssets", 50.0, None), ("A", "201603", "TotalAssets", 90.0, None),
          ("A", "201612", "TotalAssets", 100.0, None),
          ("A", "201703", "TotalAssets", 105.0, None), ("A", "201706", "TotalAssets", 110.0, None),
          ("A", "201709", "TotalAssets", 115.0, None), ("A", "201712", "TotalAssets", 120.0, None),
          ("A", "201812", "TotalAssets", 130.0, None), ("B", "201703", "TotalAssets", 70.0, None)]
    is_ = [("A", f"2016{q}", "Revenue", v, None) for q, v in zip(["03", "06", "09", "12"], [10.0, 20.0, 30.0, 40.0])]
    long(bs).to_parquet(v2 / "FundV2_BS.parquet")
    long(is_).to_parquet(v2 / "FundV2_IS.parquet")
    long([("A", "201612", "OperatingCF", 5.0, None)]).to_parquet(v2 / "FundV2_CF.parquet")
    long([("A", "200312", "OrdinaryIncomeGAAP", 3.0, None)]).to_parquet(v2 / "FundV2_GAAP.parquet")
    meta = [("A", "201603", "ReportDate", np.nan, "20160513"), ("A", "201612", "ReportDate", np.nan, "20170320"),
            ("A", "201703", "ReportDate", np.nan, "20170515"), ("A", "201706", "ReportDate", np.nan, "20170814"),
            ("A", "201709", "ReportDate", np.nan, "20171114"), ("A", "201712", "ReportDate", np.nan, "20180320"),
            ("A", "201812", "ReportDate", np.nan, "20190315")]
    long(meta).to_parquet(v2 / "FundV2_META.parquet")
    pd.DataFrame({"Ticker": ["A", "B"], "FiscalMonth": ["12", "3"], "fetched_at": ["x", "x"]}).to_parquet(v2 / "fiscal_month.parquet")
    pd.DataFrame({"Ticker": ["A", "A", "A"], "bsns_year": [2016, 2017, 2018], "TotalAssets": [100.0, 110.0, 130.0],
                  "Revenue": [100.0, np.nan, np.nan]}).to_parquet(t / ".cache/fundamental_dart.parquet")
    pd.DataFrame({"Ticker": ["A", "A", "A"], "bsns_year": [2016, 2017, 2018],
                  "rcept_no": ["20170331000111", "20180330000222", "20190320000333"]}).to_parquet(t / ".cache/dart/dart_raw_financials.parquet")
    days = pd.bdate_range("2009-01-01", "2020-12-31")
    pd.DataFrame({"Ticker": "Z", "Date": days.date}).to_parquet(t / ".cache/RAWDATA.parquet")


def run(t: Path, *extra):
    r = subprocess.run([PY, "-X", "utf8", str(SUT), "--root", str(t), *extra], capture_output=True, text=True, encoding="utf-8")
    return r.returncode, r.stdout + r.stderr


def read(t: Path):
    q = pd.read_parquet(t / ".cache/fundamental_v2/fund_v2_quarterly.parquet")
    for c in ("Period_Date", "Avail_Date", "Factor_Date"):
        q[c] = pd.to_datetime(q[c])
    return q


def row(q, tk, p, item):
    r = q[(q["Ticker"] == tk) & (q["Period"] == p) & (q["Item"] == item)]
    return r.iloc[0] if len(r) else None


T = Path(tempfile.mkdtemp(prefix="fundv2_"))
try:
    if not SUT.exists():
        raise SystemExit(f"SUT missing: {SUT}")
    a = T / "a"; setup(a)
    rc, out = run(a)
    if rc != 0:
        ng(f"build rc={rc}: {out[-800:]}"); raise SystemExit
    q = read(a)
    r1 = row(q, "A", "201603", "TotalAssets")
    ok("T1 퀀티 공시일 → 다음 거래일(금 → 월)") if r1 is not None and r1["Avail_Basis"] == "qw_report" and \
        str(r1["Avail_Date"].date()) == "2016-05-13" and str(r1["Factor_Date"].date()) == "2016-05-16" else ng(f"T1 {r1}")
    r2 = row(q, "A", "201612", "TotalAssets")
    ok("T2 DART 접수일이 늦으면 DART 날짜") if r2 is not None and r2["Avail_Basis"] == "dart_rcept" and \
        str(r2["Avail_Date"].date()) == "2017-03-31" and str(r2["Factor_Date"].date()) == "2017-04-03" else ng(f"T2 {r2}")
    r3 = row(q, "A", "201003", "TotalAssets")
    ok("T3 공시일 없음 → 분기말 + 45일 + 다음 거래일") if r3 is not None and r3["Avail_Basis"] == "rule" and \
        str(r3["Avail_Date"].date()) == "2010-05-15" and str(r3["Factor_Date"].date()) == "2010-05-17" else ng(f"T3 {r3}")
    r4 = row(q, "B", "201703", "TotalAssets")
    ok("T4 3월 결산 연말 분기 → +3개월 말일 · non_dec_fy") if r4 is not None and r4["Check"] == "non_dec_fy" and \
        str(r4["Avail_Date"].date()) == "2017-06-30" else ng(f"T4 {r4}")
    fy17 = q[(q["Ticker"] == "A") & (q["Period"].str[:4] == "2017")]
    chk = pd.read_parquet(a / ".cache/fundamental_v2/fund_v2_annual_check.parquet")
    c17 = chk[(chk["Ticker"] == "A") & (chk["FY"] == 2017) & (chk["Item"] == "TotalAssets")]
    ok5 = len(fy17) == 4 and (fy17["Check"] == "restated").all() and (fy17["Avail_Basis"] == "restated_next_fy").all() \
        and (fy17["Avail_Date"] >= pd.Timestamp("2019-03-20")).all() and len(c17) == 1 and not bool(c17["Same"].iloc[0])
    ok("T5 정정 의심 → FY2017 네 분기 전부 FY2018 사업보고서(DART 접수 2019-03-20) 뒤로") if ok5 else \
        ng(f"T5 {fy17[['Period', 'Check', 'Avail_Basis', 'Avail_Date']].to_dict('records')} {c17.to_dict('records')}")
    fy16 = q[(q["Ticker"] == "A") & (q["Period"].str[:4] == "2016")]
    c16 = chk[(chk["Ticker"] == "A") & (chk["FY"] == 2016)]
    ok("T6 일치(자산 · 매출 네 분기 합) → agree") if (fy16["Check"] == "agree").all() and len(c16) == 2 and c16["Same"].all() \
        else ng(f"T6 {fy16[['Period', 'Item', 'Check']].to_dict('records')} {c16.to_dict('records')}")
    cal = set(pd.bdate_range("2009-01-01", "2020-12-31").date)
    inside = q[(q["Avail_Date"] >= pd.Timestamp("2009-01-01")) & (q["Factor_Date"] <= pd.Timestamp("2020-12-31"))]
    outside = q[q["Avail_Date"] < pd.Timestamp("2009-01-01")]
    inv = (q["Factor_Date"] > q["Avail_Date"]).all() and (q["Avail_Date"] > q["Period_Date"]).all() and \
        all(d.date() in cal for d in inside["Factor_Date"]) and \
        ((outside["Factor_Date"] - outside["Avail_Date"]).dt.days == 1).all() and len(inside) > 0 and len(outside) > 0
    ok("T7 불변식: Factor_Date > Avail_Date > 분기말 · 달력 안 = 거래일 · 달력 시작 전 = 다음 날") if inv else \
        ng(f"T7 {q[['Ticker', 'Period', 'Item', 'Period_Date', 'Avail_Date', 'Factor_Date']].to_dict('records')}")
    # TM 뮤테이션 — 검사를 끄면(허용 차이 1000%) T5 가 일치로 바뀌고 날짜가 당겨져야 한다
    m = T / "m"; setup(m)
    rc, out = run(m, "--tol", "10")
    qm = read(m)
    m17 = qm[(qm["Ticker"] == "A") & (qm["Period"] == "201712") & (qm["Item"] == "TotalAssets")]
    ok("TM 뮤테이션(--tol 10) → FY2017 이 agree · 날짜 2018 로 당겨짐 — T5 는 검사의 발화다") if rc == 0 and len(m17) == 1 and \
        m17["Check"].iloc[0] == "agree" and m17["Avail_Date"].iloc[0] < pd.Timestamp("2019-01-01") else ng(f"TM rc={rc} {m17.to_dict('records')}")
except SystemExit:
    pass
except Exception as e:  # noqa: BLE001
    import traceback; traceback.print_exc()
    ng(f"harness error: {e!r}")
finally:
    shutil.rmtree(T, ignore_errors=True)

print(f"\n합계: 통과 {PASS} · 실패 {FAIL}")
print(json.dumps({"test": "build_fundamental_v2", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(1 if FAIL else 0)
