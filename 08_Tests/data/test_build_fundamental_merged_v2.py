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
  T10~T12 차입금 = DLC · DLTT(사채 포함) · 차입 줄 없는 기간 = TotalDebt 없음 · 정정 의심 연도 차입 = 퀀티 미룬 값
  T13 차입 두 줄 기간 완비(11-10(2)): I 201406 장기 줄이 원천에서 빠짐 → 장기차입금 0 행(같은 날) · 최신 장기 줄 = 201406(옛 201403 의 8 아님) ·
     G(사채만) · E(장기만 · 정정 미룸) 단기차입금 0 행 · H(차입 줄 없음) 두 줄 다 없음 · 분기 표도 같음
  T14 불변식: 병합 표 · 분기 표의 모든 (종목, 기간)에서 두 줄이 함께 있고 날짜가 같다 · 병합 표 두 줄 합 = TotalDebt
  T15 저장 파일 R 메타데이터에 data.table 자동 색인('index') 없음 — 새 단정이 D[Item == ...] 로 고르면 색인이 실려 파일이 3배가 됐다(11-10 실측)
  TC 대조군: B 의 Check 를 agree 로 바꾸면 TotalAssets = 퀀티 120 · Origin QW_V2 — T3 의 DART 값은 정정 의심에서만
  TM 돌연변이: 병합 표의 순서 계약 호출을 지운 사본(소스 텍스트 치환 1곳 확인) → 산출이 T4 순서 검사에 걸린다
     (검사가 실제로 위반을 잡는다 = 양성 대조)
  TM2~TM4 차입 수리를 하나씩 되돌린 사본 → T10 · T11 · T12 가 잡는다(TM4 는 병합기 단정도 끈다 — 단정이 먼저 멈추므로)
  TM5a 0 행 채우기를 지운 사본 → 병합기 단정(.check_debt_lines)이 rc 1 로 멈춘다 · TM5b 채우기 + 단정을 지운 사본 → T13 이 잡는다
  TM6 색인 막는 두 겹(사본 위 검사 · 쓰기 전 setindex)을 모두 지운 사본 → T15 가 잡는다
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

# ── (2026-11-10) 해석기 자기해결 — 배터리(run_all_hooks.sh)는 pandas · pyarrow 없는 시스템 파이썬으로 돈다.
#   없으면 venv 로 다시 실행한다(SKIP 하지 않는다 — SKIP 은 통과와 겉보기가 같다). 패턴 = hooks/test_benchmark_scale_seam.py.
try:
    import pandas as _pd_probe  # noqa: F401
    import pyarrow as _pa_probe  # noqa: F401
except ImportError:
    import subprocess as _sp
    _venv = ""
    for _cand in (str(Path(__file__).resolve().parents[2]), os.environ.get("CLAUDE_PROJECT_DIR", ""), os.environ.get("QM_ROOT", "")):
        _p = os.path.join(_cand.replace("\\", "/"), ".venv_qvest_ml", "Scripts", "python.exe") if _cand else ""
        if _p and os.path.exists(_p):
            _venv = _p
            break
    if _venv and os.environ.get("_QVEST_VENV_REEXEC") != "1":
        sys.exit(_sp.call([_venv, "-X", "utf8", os.path.abspath(__file__)] + sys.argv[1:], env=dict(os.environ, _QVEST_VENV_REEXEC="1")))
    raise

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
    # E 의 차입 줄(11-10) — 구판 T7 '퀀티 파생 TotalDebt 있음'은 차입 줄이 없는데도 0 을 만들어 통과했다(이번에 고친 결함 그 자체)
    rows.append(qrow("E", "201712", "LongTermBorr", 5, "2019-03-22", "restated"))
    # (2026-11-10 차입금 = DLC · DLTT) F: 네 성분 · G: 사채만 · H: 차입 줄 없음(손익만) · B FY2016(정정 의심 · DART 먼저): 퀀티 차입 성분
    for item, v in [("TotalAssets", 100), ("CurrentBorr", 3), ("CurrentBonds", 2), ("LongTermBorr", 4), ("Bonds", 10)]:
        rows.append(qrow("F", "201412", item, v, "2015-03-20", "pre2015"))
    rows += [qrow("G", "201412", "TotalAssets", 80, "2015-03-20", "pre2015"), qrow("G", "201412", "Bonds", 6, "2015-03-20", "pre2015"),
             qrow("H", "201412", "Revenue", 10, "2015-03-20", "pre2015")]
    bfd = "2018-03-22" if b_check == "restated" else "2017-03-24"
    rows += [qrow("B", "201612", "CurrentBorr", 7, bfd, b_check), qrow("B", "201612", "Bonds", 3, bfd, b_check)]
    # (2026-11-10(2) 차입 두 줄 기간 완비) I: 201403 단기 5 · 장기 8 → 201406 장기 줄이 원천에서 빠짐(퀀티는 비유동 0 을 적지 않는다 ·
    #   유동 두 줄은 0 도 적는다) — 구판은 201406 뒤에도 장기차입금 최신 행 = 201403 의 8 이었다(옛 줄 섞임)
    rows += [qrow("I", "201403", it, v, "2014-05-15", "pre2015") for it, v in [("TotalAssets", 200), ("CurrentBorr", 5),
                                                                              ("CurrentBonds", 0), ("LongTermBorr", 8)]]
    rows += [qrow("I", "201406", it, v, "2014-08-14", "pre2015") for it, v in [("TotalAssets", 210), ("CurrentBorr", 6),
                                                                              ("CurrentBonds", 0)]]
    q = pd.DataFrame(rows)
    pq.write_table(pa.Table.from_pandas(q, preserve_index=False), t / ".cache/fundamental_v2/fund_v2_quarterly.parquet")
    ck = pd.DataFrame([dict(Ticker="B", FY=2016, Item="TotalAssets", QW_Value=120.0, DART_Value=999.0, Rel_Diff=0.88,
                            DART_Date=D("2017-03-23"), DART_Factor_Date=D("2017-03-24"), Same=False),
                       dict(Ticker="A", FY=2015, Item="TotalAssets", QW_Value=60.0, DART_Value=60.0, Rel_Diff=0.0,
                            DART_Date=D("2016-03-18"), DART_Factor_Date=D("2016-03-21"), Same=True),
                       dict(Ticker="E", FY=2017, Item="TotalAssets", QW_Value=130.0, DART_Value=777.0, Rel_Diff=0.83,
                            DART_Date=D("2020-01-09"), DART_Factor_Date=D("2020-01-10"), Same=False)])
    pq.write_table(pa.Table.from_pandas(ck, preserve_index=False), t / ".cache/fundamental_v2/fund_v2_annual_check.parquet")
    pd.DataFrame({"Ticker": list("ABCDEFGHI"), "FiscalMonth": ["12"] * 9, "fetched_at": ["x"] * 9}).to_parquet(t / ".cache/qw_fund_v2/fiscal_month.parquet")
    # DART 당시 기록의 차입 = 이름 일치로만 잡은 불완전한 값(실측 LG화학 FY2019~2025 TotalDebt 0 형태) — 정정 의심 연도에서도 쓰면 안 된다
    pd.DataFrame({"Ticker": ["B", "E"], "bsns_year": [2016, 2017], "Factor_Date": [D("2017-03-31"), D("2018-03-31")],
                  "TotalAssets": [999.0, 777.0], "Revenue": [101.0, 90.0], "ROA": [0.05, 0.1],
                  "ShortTermBorr": [1.0, None], "LongTermBorr": [None, None], "TotalDebt": [0.0, 0.0],
                  "BorrowingDependency": [0.0, 0.0]}).to_parquet(t / ".cache/fundamental_dart.parquet")


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


def latest(m, tk, item):
    """소비자가 고르는 행 = (종목, 항목) 안 Factor_Date 최신(팩터 모듈 .SD[.N] · rank 1 과 같은 선택)."""
    r = m[(m["Ticker"] == tk) & (m["Item"] == item)]
    return None if r.empty else r.sort_values("Factor_Date").iloc[-1]


def r_attrs(p):
    """R 이 이 parquet 을 읽을 때 되살리는 속성 이름(arrow R 메타데이터) — data.table 자동 색인 'index' 가 실리면 안 된다."""
    ps = str(p).replace("\\", "/")
    r = subprocess.run([RS, "--vanilla", "-e", f'suppressMessages(library(arrow)); cat(names(attributes(read_parquet("{ps}"))), sep = ",")'],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout.strip().split(",") if r.returncode == 0 else None


def debt_lines_complete(m, with_total) -> bool:
    """모든 (종목, 기간)에서 단기 · 장기차입금이 함께 있고 날짜가 같다 · (병합 표) 두 줄 합 = 같은 기간 TotalDebt."""
    cols = ["Ticker", "Period", "Factor_Date", "Value"]
    j = m[m["Item"] == "ShortTermBorr"][cols].merge(m[m["Item"] == "LongTermBorr"][cols], on=["Ticker", "Period"],
                                                    how="outer", suffixes=("_s", "_l"))
    good = bool(len(j) and j["Factor_Date_s"].notna().all() and j["Factor_Date_l"].notna().all() and
                (j["Factor_Date_s"] == j["Factor_Date_l"]).all())
    if with_total:
        k = j.merge(m[m["Item"] == "TotalDebt"][["Ticker", "Period", "Value"]].rename(columns={"Value": "td"}),
                    on=["Ticker", "Period"], how="inner")
        good = good and len(k) > 0 and bool(((k["Value_s"] + k["Value_l"] - k["td"]).abs() <= 1e-9 * k["td"].abs().clip(lower=1)).all())
    return good


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
        not (m["Origin"].eq("DART_RESTATED") & m["Ticker"].eq("E")).any() and etd is not None and etd["Origin"] == "QW_V2_derived" and \
        etd["Value"] == 5
    ok("T7 정정 의심(DART 더 늦음): 퀀티 미룬 값 130 · DART 행 없음 · 퀀티 파생 있음") if ok7 else ng(f"T7 {eta} {etd}")
    ok8 = r_ta["Source"] == "XLSX" and r_td["Source"] == "xlsx_derived" and rv["Source"] == "DART" and \
        bta["Source"] == "DART" and sh["Source"] == "XLSX" and set(m["Source"]) <= {"XLSX", "xlsx_derived", "DART"}
    ok("T8 Source 역할 표지: 분기 XLSX · 분기 파생 xlsx_derived · 연간 DART") if ok8 else ng(f"T8 {sorted(set(m['Source']))}")
    xre = get(x, "A", "201412", "RetainedEarnings")
    ok9 = list(x.columns) == ["Ticker", "Period", "Item", "Value", "Period_Date", "Factor_Date"] and \
        set(x["Item"]) <= RAW41 and strictly_ordered(x) and xre is not None and xre["Value"] == 7 and \
        get(x, "D", "201512", "Revenue") is None and get(x, "D", "201603", "Revenue") is not None
    ok("T9 분기 표: 옛 꼴 · 원계정 41개 안 · 순서 계약 · 늦게 온 D 201512 버림") if ok9 else ng(f"T9 cols={list(x.columns)} {xre}")
    # T10~T12 (2026-11-10 차입금 = DLC · DLTT · 없는 것을 0으로 만들지 않음 · 정정 의심 연도 차입 = 퀀티 미룬 값)
    def debt_facts(mm, xx):
        f = {k: get(mm, "F", "201412", k) for k in ("ShortTermBorr", "LongTermBorr", "TotalDebt")}
        return dict(F=f, G=get(mm, "G", "201412", "TotalDebt"), H=get(mm, "H", "201412", "TotalDebt"),
                    xF=(get(xx, "F", "201412", "ShortTermBorr"), get(xx, "F", "201412", "LongTermBorr")),
                    B={k: get(mm, "B", "201612", k) for k in ("ShortTermBorr", "LongTermBorr", "TotalDebt", "BorrowingDependency")},
                    B_dart_debt=bool((mm["Ticker"].eq("B") & mm["Origin"].eq("DART_RESTATED") &
                                      mm["Item"].isin(["ShortTermBorr", "LongTermBorr", "TotalDebt", "BorrowingDependency"])).any()),
                    I_lt=latest(mm, "I", "LongTermBorr"), xI_lt=latest(xx, "I", "LongTermBorr"))
    df_ = debt_facts(m, x)
    t10 = all(df_["F"][k] is not None for k in df_["F"]) and df_["F"]["ShortTermBorr"]["Value"] == 5 and \
        df_["F"]["LongTermBorr"]["Value"] == 14 and abs(df_["F"]["TotalDebt"]["Value"] - 19) < 1e-9 and \
        all(v is not None for v in df_["xF"]) and df_["xF"][0]["Value"] == 5 and df_["xF"][1]["Value"] == 14
    ok("T10 차입금 = DLC 3+2 · DLTT 4+10 · TotalDebt 19 · 분기 표도 같은 이름에 같은 값") if t10 else ng(f"T10 {df_['F']} {df_['xF']}")
    ok("T10b 사채만 있는 회사 TotalDebt = 6(0 아님)") if df_["G"] is not None and df_["G"]["Value"] == 6 else ng(f"T10b {df_['G']}")
    ok("T11 차입 줄 없는 기간 = TotalDebt 행 없음(0 을 만들지 않는다)") if df_["H"] is None else ng(f"T11 H TotalDebt = {df_['H']}")
    bb = df_["B"]
    t12 = not df_["B_dart_debt"] and all(bb[k] is not None for k in bb) and bb["ShortTermBorr"]["Value"] == 7 and \
        bb["ShortTermBorr"]["Origin"] == "QW_V2_DELAYED" and bb["LongTermBorr"]["Value"] == 3 and \
        abs(bb["TotalDebt"]["Value"] - 10) < 1e-9 and bb["TotalDebt"]["Origin"] == "QW_V2_derived" and \
        fd(bb["ShortTermBorr"]) == "2018-03-22" and bb["TotalDebt"]["Factor_Date"] >= pd.Timestamp("2018-03-22") and \
        abs(bb["BorrowingDependency"]["Value"] - 10 / 120) < 1e-9 and bb["BorrowingDependency"]["Origin"] == "QW_V2_derived"
    ok("T12 정정 의심 연도: DART 차입 기록(0) 안 씀 · 퀀티 차입 7 · 3 미룬 날짜 · TotalDebt 10 퀀티 파생") if t12 else \
        ng(f"T12 dart_debt={df_['B_dart_debt']} {bb}")
    # T13 · T14 (2026-11-10(2) 차입 두 줄 기간 완비 — 옛 차입 줄 섞임 수리)
    i_lt, i_st, i_td = (get(m, "I", "201406", k) for k in ("LongTermBorr", "ShortTermBorr", "TotalDebt"))
    g_st, g_lt, e_st = get(m, "G", "201412", "ShortTermBorr"), get(m, "G", "201412", "LongTermBorr"), get(m, "E", "201712", "ShortTermBorr")
    h_lines = m[m["Ticker"].eq("H") & m["Item"].isin(["ShortTermBorr", "LongTermBorr"])]
    x_lt = get(x, "I", "201406", "LongTermBorr")
    t13 = i_lt is not None and i_lt["Value"] == 0 and fd(i_lt) == "2014-08-14" and i_st is not None and i_st["Value"] == 6 and \
        fd(i_st) == "2014-08-14" and i_td is not None and abs(i_td["Value"] - 6) < 1e-9 and \
        df_["I_lt"] is not None and df_["I_lt"]["Period"] == "201406" and df_["I_lt"]["Value"] == 0 and \
        g_st is not None and g_st["Value"] == 0 and g_lt is not None and fd(g_st) == fd(g_lt) and \
        e_st is not None and e_st["Value"] == 0 and e_st["Origin"] == "QW_V2_DELAYED" and fd(e_st) == "2019-03-22" and \
        h_lines.empty and x_lt is not None and x_lt["Value"] == 0 and fd(x_lt) == "2014-08-14" and \
        df_["xI_lt"] is not None and df_["xI_lt"]["Period"] == "201406"
    ok("T13 기간 완비: I 장기 줄 빠진 201406 = 장기 0 행(같은 날) · 최신 장기 줄 201406 · G · E 단기 0 행 · H 없음 · 분기 표 같음") if t13 else \
        ng(f"T13 I={i_lt} / {i_st} / {i_td} latest={df_['I_lt']} G={g_st} E={e_st} H={len(h_lines)} X={x_lt}")
    t14 = debt_lines_complete(m, with_total=True) and debt_lines_complete(x, with_total=False)
    ok("T14 불변식: 모든 (종목, 기간) 두 줄 함께 · 같은 날짜 · 병합 표 두 줄 합 = TotalDebt") if t14 else \
        ng(f"T14 merged={debt_lines_complete(m, True)} xlsx={debt_lines_complete(x, False)}")
    am, ax = r_attrs(out), r_attrs(outx)
    ok("T15 저장 파일에 data.table 자동 색인 없음(R 메타데이터 · 두 표)") if am is not None and ax is not None and \
        "index" not in am and "index" not in ax else ng(f"T15 merged={am} xlsx={ax}")
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
    # TM2~TM4 (2026-11-10): 차입 수리를 하나씩 되돌린 사본 → 해당 사례가 잡힌다(치환 1곳 단정 · 사본 = 병합기 + 파생식 한 쌍)
    src0, dsrc = SUT.read_text(encoding="utf-8"), DERIVE.read_text(encoding="utf-8")
    # 치환 = (파일, 옛 문자열, 새 문자열) 쌍 목록 — 구판 동작 그대로 되돌린다(한쪽만 되돌린 사본은 병합기의 중복 키 검사에 먼저 걸린다)
    # 병합기 단정 끄기(11-10(2)) — 구판 동작이 단정에 먼저 멈추는 사본에서 시험 자체가 잡는지 보려고(TM4 · TM5b)
    GUARD_OFF = [("sut", 'dlm <- .check_debt_lines(M, "병합", with_total = TRUE)', "dlm <- list()"),
                 ("sut", 'dlx <- .check_debt_lines(X, "분기 표")', "dlx <- list()")]
    FILL_OFF = ("sut", "dq <- rbind(dq, debt_fill, use.names = TRUE)", "dq <- dq")
    muts = [
        ("TM2 사채 빼기(구판 DEBT_TO)", [("sut",
          'DEBT_TO <- c(CurrentBorr = "CurrentBorr", CurrentBonds = "CurrentBorr", LongTermBorr = "LongTermBorr", Bonds = "LongTermBorr")',
          'DEBT_TO <- c(CurrentBorr = "CurrentBorr", LongTermBorr = "LongTermBorr")')],
         lambda f: f["F"]["TotalDebt"] is not None and abs(f["F"]["TotalDebt"]["Value"] - 7) < 1e-9),
        ("TM3 없는 차입 = 0(구판 파생식)", [("derive", "fifelse(is.na(ShortTermBorr) & is.na(LongTermBorr), NA_real_,",
                                         "fifelse(is.na(ShortTermBorr) & FALSE, NA_real_,")],
         lambda f: f["H"] is not None and f["H"]["Value"] == 0),
        ("TM4 정정 의심 연도 DART 차입 그대로(구판)", [("sut", "dl <- dl[!Item %in% DEBT_ITEMS]", "dl <- dl"),
          ("sut", "dB <- rbind(dB[!RS, on = .(Ticker, FY)], dB[RS, on = .(Ticker, FY), nomatch = 0L][Item %in% DEBT_ITEMS])",
           "dB <- dB[!RS, on = .(Ticker, FY)]")] + GUARD_OFF,
         lambda f: f["B_dart_debt"]),
        ("TM5b 차입 0 행 채우기 + 단정 지움(구판 옛 줄 섞임)", [FILL_OFF] + GUARD_OFF,
         lambda f: f["I_lt"] is not None and f["I_lt"]["Period"] == "201403" and f["I_lt"]["Value"] == 8),
    ]
    for name, pairs, caught in muts:
        srcs = {"sut": src0, "derive": dsrc}
        bad = [a_[:40] for w_, a_, _ in pairs if srcs[w_].count(a_) != 1]
        if bad:
            ng(f"{name} 치환 대상이 1곳이 아니다: {bad}"); continue
        for w_, a_, b_ in pairs:
            srcs[w_] = srcs[w_].replace(a_, b_)
        d_ = T / ("m_" + name[:3]); d_.mkdir()
        (d_ / SUT.name).write_text(srcs["sut"], encoding="utf-8")
        (d_ / DERIVE.name).write_text(srcs["derive"], encoding="utf-8")
        w = T / ("w_" + name[:3]); setup(w)
        rc, log, out_, outx_ = run(w, sut=d_ / SUT.name)
        if rc != 0:
            ng(f"{name} 사본 실행 실패 rc={rc}: {log[-600:]}"); continue
        f_ = debt_facts(load(out_), load(outx_))
        ok(f"{name} → 시험이 잡는다") if caught(f_) else ng(f"{name} → 잡지 못함 {f_}")
    # TM5a (2026-11-10(2)): 0 행 채우기만 지운 사본 → 병합기 단정이 멈춘다(rc 1 · 두 줄 기간 · 날짜 갈림) = 단정의 양성 대조
    if src0.count(FILL_OFF[1]) != 1:
        ng(f"TM5a 치환 대상이 {src0.count(FILL_OFF[1])}곳 (1곳이어야 한다)")
    else:
        d5 = T / "m_TM5a"; d5.mkdir()
        (d5 / SUT.name).write_text(src0.replace(FILL_OFF[1], FILL_OFF[2]), encoding="utf-8")
        shutil.copy(DERIVE, d5 / DERIVE.name)
        w5 = T / "w_TM5a"; setup(w5)
        rc, log, _, _ = run(w5, sut=d5 / SUT.name)
        ok("TM5a 채우기 지운 사본 → 병합기 단정이 rc 1 로 멈춘다") if rc == 1 and "차입 두 줄(단기 · 장기차입금)의 기간 · 날짜가 갈린 칸" in log else \
            ng(f"TM5a 단정이 멈추지 않았다 rc={rc}: {log[-600:]}")
    # TM6 (2026-11-10(2)): 색인 막는 두 겹(사본 위 검사 · 쓰기 전 setindex)을 모두 지운 사본 → T15 가 잡는다(한 겹만 지우면 다른 겹이 막는다)
    pairs6 = [("w <- D[, .(Ticker, Period, Item, Factor_Date, Value)]", "w <- D"), ("setindex(D, NULL)", "invisible(NULL)")]
    bad6 = [a_[:40] for a_, _ in pairs6 if src0.count(a_) != 1]
    if bad6:
        ng(f"TM6 치환 대상이 1곳이 아니다: {bad6}")
    else:
        s6 = src0
        for a_, b_ in pairs6:
            s6 = s6.replace(a_, b_)
        d6 = T / "m_TM6"; d6.mkdir()
        (d6 / SUT.name).write_text(s6, encoding="utf-8")
        shutil.copy(DERIVE, d6 / DERIVE.name)
        w6 = T / "w_TM6"; setup(w6)
        rc, log, out6, outx6 = run(w6, sut=d6 / SUT.name)
        a6 = r_attrs(out6) if rc == 0 else None
        ok("TM6 색인 막는 두 겹 지운 사본 → T15 가 잡는다(파일에 'index')") if a6 is not None and "index" in a6 else \
            ng(f"TM6 → 잡지 못함 rc={rc} attrs={a6}")
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
