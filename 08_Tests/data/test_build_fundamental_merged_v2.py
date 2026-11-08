"""test_build_fundamental_merged_v2.py — 02_Infrastructure/data/build_fundamental_merged_v2.R 합성 자료 시험
(운영 .cache 무접촉 · 등록부와 파생 공식 파일만 실물을 읽는다).

사례 (전부 12월 결산):
  T1 <=2014 분기: A 201412 TotalAssets → Freq Q · Origin QW_V2 · 이름 대응(RetainedEarnings ← v2 RetainedEarnings,
     ShortTermBorr ← v2 CurrentBorr) · 파생 TotalDebt = ShortTermBorr + LongTermBorr
  T2 2015 연간(일치): A 201512 Revenue = 네 분기 합 100 · TotalAssets = 연말 값 · Origin QW_V2 · Freq A ·
     Factor_Date = 연말 키 날짜 · 주식 수(ISSD)는 2015~ 도 분기 행(연간 행 없음)
  T3 정정 의심(DART 가 먼저): B FY2016 → TotalAssets = DART 값 999(퀀티 120 아님) · Origin DART_RESTATED ·
     Factor_Date = DART 날짜 · DART 에 없는 퀀티 전용 FCF1 → QW_V2_DELAYED(미룬 날짜)
  T4 불변식: 키 중복 없음 · Factor_Date > Period_Date · (종목, 항목) 안에서 Factor_Date 가 기간 순서대로 엄격히 는다
  T5 날짜 순서 계약: C 201406 = 늦게 도착한 옛 기간(뒤 기간이 더 일찍 쓰일 수 있었음) → 버림 · 201409 · 201412 같은
     날 도착 → 201412 하루 늦춤
  T6 파생 날짜: D FY2015 연말 분기가 늦게(2017-06-01) 정정 → FY2015 원계정은 버림(FY2016 이 먼저 쓰일 수 있었음) ·
     FY2016 성장률(직전 연도 값을 씀)은 2017-06-01 이후(같은 날 FY2015 성장률과 겹쳐 하루 더 늦춤 = 06-02) ·
     값 = 60/48 − 1
  T7 정정 의심(DART 가 더 늦음): E FY2017 DART 기록 2020-01-10 > 퀀티 미룬 날 2019-03-22 → 퀀티 미룬 값(130 ·
     QW_V2_DELAYED) · DART 행 없음 · 퀀티 파생 있음
  T8 Source = 지금 병합 표의 역할 표지: 분기 원계정 XLSX · 분기 파생 xlsx_derived · 연간(퀀티 · DART 모두) DART
  T9 분기 표(--out-xlsx): fundamental_xlsx.parquet 꼴(열 순서 · 원계정 41개 이름 안) · 같은 순서 계약 ·
     A 201412 RetainedEarnings = 7 · D 201512 Revenue 버림
  TC 대조군: B 의 Check 를 agree 로 바꾸면 TotalAssets = 퀀티 120 · Origin QW_V2 — T3 의 DART 값은 정정 의심에서만
  TM 돌연변이: 병합 표의 순서 계약 호출을 지운 사본(소스 텍스트 치환 1곳 확인) → 산출이 T4 순서 검사에 걸린다
     (검사가 실제로 위반을 잡는다 = 양성 대조)
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

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

ROOT = Path(os.environ.get("QM_ROOT") or Path(__file__).resolve().parents[2])
SUT = ROOT / "02_Infrastructure/data/build_fundamental_merged_v2.R"
DERIVE = ROOT / "02_Infrastructure/data/fundamental_derive_items.R"
REG = ROOT / "02_Infrastructure/data/qw_updatefile_registry.json"
RS = os.environ.get("QVEST_RSCRIPT") or r"C:\Program Files\R\R-4.6.2\bin\Rscript.exe"
RAW41 = {"AccountsPay", "AccountsRecv", "COGS", "CapitalStock", "CashAndEquiv", "CurrentAssets", "CurrentLiab",
         "DepAmort", "Dividends", "FCF1", "FCF2", "FinanceCF", "GrossProfit", "ISSD", "IntangibleAssets",
         "InterestExp", "InterestIncome", "Inventory", "InvestCF", "LongTermBorr", "LongTermPay", "LongTermRecv",
         "NetInterestExp", "NonCurrentAssets", "NonCurrentLiab", "OperatingCF", "OperatingProfit", "OrdRandD",
         "PretaxIncome", "RandD", "RetainedEarnings", "Revenue", "SBB", "SGAExpense", "ShortTermBorr",
         "TangibleAssets", "TaxExpense", "TotalAssets", "TotalEquity", "TotalLiab", "TotalNetInterestExp"}
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
        rows.append(qrow("A", p, "SharesCommonAdj", 100, fd, "agree"))
    rows.append(qrow("A", "201512", "TotalAssets", 60, "2016-03-21", "agree"))
    # B FY2016: restated (v2 already delayed the dates to the FY2017 report: 2018-03-22)
    for p in ["201603", "201606", "201609", "201612"]:
        rows.append(qrow("B", p, "Revenue", 25, "2018-03-22" if b_check == "restated" else "2017-03-24", b_check))
        rows.append(qrow("B", p, "FCF1", 1, "2018-03-22" if b_check == "restated" else "2017-03-24", b_check))
    rows.append(qrow("B", "201612", "TotalAssets", 120, "2018-03-22" if b_check == "restated" else "2017-03-24", b_check))
    # C <=2014: 201406 arrives late (a later document) · 201409 and 201412 arrive the same day
    for p, v, fd in [("201403", 1, "2014-05-15"), ("201406", 2, "2016-01-10"), ("201409", 3, "2015-03-20"), ("201412", 4, "2015-03-20")]:
        rows.append(qrow("C", p, "TotalAssets", v, fd, "pre2015"))
    # D: FY2014 seed · FY2015 year-end quarter restated late (2017-06-01, not flagged) · FY2016 normal
    for fy, v, dates in [(2014, 10, ["2014-05-15", "2014-08-14", "2014-11-14", "2015-03-20"]),
                         (2015, 12, ["2015-05-15", "2015-08-14", "2015-11-16", "2017-06-01"]),
                         (2016, 15, ["2016-05-16", "2016-08-16", "2016-11-14", "2017-03-20"])]:
        ck_ = "pre2015" if fy == 2014 else "agree"
        for mm, fd in zip(["03", "06", "09", "12"], dates):
            rows.append(qrow("D", f"{fy}{mm}", "Revenue", v, fd, ck_))
        rows.append(qrow("D", f"{fy}12", "TotalAssets", 100 + fy - 2014, dates[-1], ck_))
    # E FY2017: restated · v2 delayed to 2019-03-22 · the DART record we hold is a later correction (2020-01-10)
    for mm in ["03", "06", "09", "12"]:
        rows.append(qrow("E", f"2017{mm}", "Revenue", 20, "2019-03-22", "restated"))
    rows.append(qrow("E", "201712", "TotalAssets", 130, "2019-03-22", "restated"))
    q = pd.DataFrame(rows)
    pq.write_table(pa.Table.from_pandas(q, preserve_index=False), t / ".cache/fundamental_v2/fund_v2_quarterly.parquet")
    ck = pd.DataFrame([dict(Ticker="B", FY=2016, Item="TotalAssets", QW_Value=120.0, DART_Value=999.0, Rel_Diff=0.88,
                            DART_Date=D("2017-03-23"), DART_Factor_Date=D("2017-03-24"), Same=False),
                       dict(Ticker="A", FY=2015, Item="TotalAssets", QW_Value=60.0, DART_Value=60.0, Rel_Diff=0.0,
                            DART_Date=D("2016-03-18"), DART_Factor_Date=D("2016-03-21"), Same=True),
                       dict(Ticker="E", FY=2017, Item="TotalAssets", QW_Value=130.0, DART_Value=777.0, Rel_Diff=0.83,
                            DART_Date=D("2020-01-09"), DART_Factor_Date=D("2020-01-10"), Same=False)])
    pq.write_table(pa.Table.from_pandas(ck, preserve_index=False), t / ".cache/fundamental_v2/fund_v2_annual_check.parquet")
    pd.DataFrame({"Ticker": list("ABCDE"), "FiscalMonth": ["12"] * 5, "fetched_at": ["x"] * 5}).to_parquet(t / ".cache/qw_fund_v2/fiscal_month.parquet")
    pd.DataFrame({"Ticker": ["B", "E"], "bsns_year": [2016, 2017], "Factor_Date": [D("2017-03-31"), D("2018-03-31")],
                  "TotalAssets": [999.0, 777.0], "Revenue": [101.0, 90.0], "ROA": [0.05, 0.1]}).to_parquet(t / ".cache/fundamental_dart.parquet")


def run(t: Path, sut: Path = SUT):
    out, outx = t / ".cache/fundamental_merged_v2.parquet", t / ".cache/fundamental_xlsx_v2.parquet"
    r = subprocess.run([RS, "--vanilla", str(sut), "--root", str(t), "--registry", str(REG), "--out", str(out),
                        "--out-xlsx", str(outx)], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout + r.stderr), out, outx


def load(p: Path):
    m = pd.read_parquet(p)
    for c in ("Period_Date", "Factor_Date"):
        m[c] = pd.to_datetime(m[c])
    return m


def get(m, tk, p, item):
    r = m[(m["Ticker"] == tk) & (m["Period"] == p) & (m["Item"] == item)]
    return r.iloc[0] if len(r) == 1 else None


def fd(r):
    return None if r is None else str(r["Factor_Date"].date())


def strictly_ordered(m) -> bool:
    s = m.sort_values(["Ticker", "Item", "Period_Date"])
    g = s.groupby(["Ticker", "Item"], sort=False)["Factor_Date"].diff()
    return bool((g.dropna() > pd.Timedelta(0)).all())


T = Path(tempfile.mkdtemp(prefix="mergedv2_"))
try:
    if not SUT.exists() or not Path(RS).exists():
        raise SystemExit(f"missing SUT or Rscript: {SUT} {RS}")
    a = T / "a"; setup(a)
    rc, log, out, outx = run(a)
    if rc != 0:
        ng(f"build rc={rc}: {log[-2500:]}"); raise SystemExit
    m, x = load(out), load(outx)
    r_ta, r_re, r_sb, r_td = (get(m, "A", "201412", i) for i in ("TotalAssets", "RetainedEarnings", "ShortTermBorr", "TotalDebt"))
    ok1 = all(v is not None for v in (r_ta, r_re, r_sb, r_td)) and r_ta["Freq"] == "Q" and r_ta["Origin"] == "QW_V2" and \
        r_re["Value"] == 7 and r_sb["Value"] == 3 and abs(r_td["Value"] - 7) < 1e-9
    ok("T1 <=2014 분기 · 이름 대응 · TotalDebt = 3 + 4") if ok1 else ng(f"T1 {r_ta} {r_re} {r_sb} {r_td}")
    rv, ta, sh = get(m, "A", "201512", "Revenue"), get(m, "A", "201512", "TotalAssets"), get(m, "A", "201512", "ISSD")
    ok2 = rv is not None and ta is not None and rv["Value"] == 100 and ta["Value"] == 60 and rv["Freq"] == "A" and \
        rv["Origin"] == "QW_V2" and fd(rv) == "2016-03-21" and sh is not None and sh["Freq"] == "Q" and \
        len(m[(m["Ticker"] == "A") & (m["Item"] == "ISSD")]) == 4
    ok("T2 2015 연간: 매출 = 네 분기 합 100 · 자산 = 연말 60 · 연말 키 날짜 · ISSD 는 분기 행 4개") if ok2 else ng(f"T2 {rv} {ta} {sh}")
    bta, bf = get(m, "B", "201612", "TotalAssets"), get(m, "B", "201612", "FCF1")
    ok3 = bta is not None and bf is not None and bta["Value"] == 999 and bta["Origin"] == "DART_RESTATED" and \
        fd(bta) == "2017-03-24" and bf["Origin"] == "QW_V2_DELAYED" and fd(bf) == "2018-03-22"
    ok("T3 정정 의심(DART 먼저): DART 기록(999 · DART 날짜) · 퀀티 전용 FCF1 은 미룬 날짜") if ok3 else ng(f"T3 {bta} {bf}")
    dup = m.duplicated(["Ticker", "Period", "Item"]).any()
    ok4 = not dup and (m["Factor_Date"] > m["Period_Date"]).all() and strictly_ordered(m)
    ok("T4 불변식: 키 중복 없음 · Factor_Date > Period_Date · 항목 안 날짜 순서 엄격") if ok4 else ng(f"T4 dup={dup} order={strictly_ordered(m)}")
    c06, c09, c12 = (get(m, "C", p, "TotalAssets") for p in ("201406", "201409", "201412"))
    ok5 = c06 is None and fd(c09) == "2015-03-20" and fd(c12) == "2015-03-21"
    ok("T5 순서 계약: 늦게 온 201406 버림 · 같은 날 온 201412 하루 늦춤") if ok5 else ng(f"T5 {c06} {fd(c09)} {fd(c12)}")
    d15, d16, g15, g16 = (get(m, "D", p, i) for p, i in (("201512", "TotalAssets"), ("201612", "TotalAssets"),
                                                         ("201512", "RevenueGrowth"), ("201612", "RevenueGrowth")))
    ok6 = d15 is None and fd(d16) == "2017-03-20" and fd(g15) == "2017-06-01" and fd(g16) == "2017-06-02" and \
        abs(g16["Value"] - (60 / 48 - 1)) < 1e-9
    ok("T6 파생 날짜: FY2015 원계정 버림 · FY2016 성장률은 FY2015 값이 나온 뒤(06-02) · 값 0.25") if ok6 else \
        ng(f"T6 d15={d15 is not None} d16={fd(d16)} g15={fd(g15)} g16={fd(g16)} v={None if g16 is None else g16['Value']}")
    eta, etd = get(m, "E", "201712", "TotalAssets"), get(m, "E", "201712", "TotalDebt")
    ok7 = eta is not None and eta["Value"] == 130 and eta["Origin"] == "QW_V2_DELAYED" and fd(eta) == "2019-03-22" and \
        not (m["Origin"].eq("DART_RESTATED") & m["Ticker"].eq("E")).any() and etd is not None and etd["Origin"] == "QW_V2_derived"
    ok("T7 정정 의심(DART 더 늦음): 퀀티 미룬 값 130 · DART 행 없음 · 퀀티 파생 있음") if ok7 else ng(f"T7 {eta} {etd}")
    ok8 = r_ta["Source"] == "XLSX" and r_td["Source"] == "xlsx_derived" and rv["Source"] == "DART" and \
        bta["Source"] == "DART" and sh["Source"] == "XLSX" and set(m["Source"]) <= {"XLSX", "xlsx_derived", "DART"}
    ok("T8 Source 역할 표지: 분기 XLSX · 분기 파생 xlsx_derived · 연간 DART") if ok8 else ng(f"T8 {sorted(set(m['Source']))}")
    xre = get(x, "A", "201412", "RetainedEarnings")
    ok9 = list(x.columns) == ["Ticker", "Period", "Item", "Value", "Period_Date", "Factor_Date"] and \
        set(x["Item"]) <= RAW41 and strictly_ordered(x) and xre is not None and xre["Value"] == 7 and \
        get(x, "D", "201512", "Revenue") is None and get(x, "D", "201603", "Revenue") is not None
    ok("T9 분기 표: 옛 꼴 · 원계정 41개 안 · 순서 계약 · 늦게 온 D 201512 버림") if ok9 else ng(f"T9 cols={list(x.columns)} {xre}")
    c = T / "c"; setup(c, b_check="agree")
    rc, log, out, _ = run(c)
    mc = load(out) if rc == 0 else None
    cta = get(mc, "B", "201612", "TotalAssets") if mc is not None else None
    ok("TC 대조군(B = agree) → 퀀티 120 · QW_V2 — DART 값은 정정 의심에서만") if cta is not None and cta["Value"] == 120 and \
        cta["Origin"] == "QW_V2" else ng(f"TC rc={rc} {cta}")
    # TM: mutated copy without the merged-table order contract (text substitution, verified to happen exactly once)
    mdir = T / "mut"; mdir.mkdir()
    src = SUT.read_text(encoding="utf-8")
    needle = "oc <- order_contract(M); M <- oc$D"
    if src.count(needle) != 1:
        ng(f"TM 돌연변이 치환 대상이 {src.count(needle)}곳 (1곳이어야 한다)")
    else:
        stub = "oc <- list(stats = list(rows_in = nrow(M), dropped = 0L, holes_created = 0L, shifted = 0L, max_shift_days = 0L))"
        (mdir / SUT.name).write_text(src.replace(needle, stub), encoding="utf-8")
        shutil.copy(DERIVE, mdir / DERIVE.name)
        b = T / "b"; setup(b)
        rc, log, out, _ = run(b, sut=mdir / SUT.name)
        if rc != 0:
            ng(f"TM 돌연변이 사본 실행 실패 rc={rc}: {log[-800:]}")
        else:
            mm = load(out)
            ok("TM 돌연변이(순서 계약 제거) → T4 순서 검사가 위반을 잡는다") if not strictly_ordered(mm) else \
                ng("TM 돌연변이 산출이 순서 검사를 통과했다(검사가 죽어 있다)")
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
