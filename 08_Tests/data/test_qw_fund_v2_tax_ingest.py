"""test_qw_fund_v2_tax_ingest.py — 02_Infrastructure/data/qw_fund_v2_tax_ingest.py 합성 시계열 책 시험(운영 03_Universe · .cache 무접촉).

책 모양 = 실제 퀀티 시계열(Company) 책: B1 'Last Update' · B5 From · 8행 종목 · B10 코드 · 11행 단위 · 12행 Base Date ·
15행부터 A열 날짜. 날짜 표지는 실측(11-09 전체 책 · 10종목 시험 책)대로 — 분기 말 달('1999-12' · '2000-03' …) + 마지막 행 =
CPD-1TD 의 달('2026-11'), 첫 행 = B5 이하 마지막 분기 말(From 20000101 → '1999-12'). 행 d 의 값 = d 의 3개월 전 날이 든
결산분기(FQ0) · 표지 = 그 결산분기가 끝나는 달력 분기(v2 Peer 와 같다) — 12월(3 · 6 · 9월) 결산 = d − 1분기, 그 밖의 결산월 =
분기 말 행에서 한 분기 뒤(11-09 실측 12종목).

사례: T0 날짜 → 결산분기(12월 결산 · 실측 표지) · T0b 결산월 1~12 대응(11월 · 10월 손 표 + 같은 부류) · T0c 시험 쪽 생성기 = 손 표 ·
      T1 첫 전체 적재 · T2 전체 재적재 변경 없음 · T2b 전체 재적재 값 변경 → revisions ·
      T3 창 갱신(T9 꼴: 창만 교체 · 창 앞 한 행 버림 · changed/deleted/new · first_fetched_at 유지) ·
      T4 창 채움 급감 → 3(T9b 꼴) · T5 B1 낡음 → 3 · T6 B12 FY0 → 3 · T7 창 시작 늦음 → 3 · T7b 창 앞 두 행 → 3 ·
      T8 가운데 분기 빠짐 → 3 · T8b 틀의 낡은 행 남음(중복) → 3 · T9 끝 잘림 → 3 · T9b 분기 말일(끝 한 분기 앞) → 통과 ·
      T10 매입채무 양성 대조 실패 → 3 · T11 부모 없이 창 갱신 → 3 · T12 모르는 단위 → 3 · T13 dry-run 무기록 · T14 시트별 날짜 다름 → 3 ·
      T15 결산월 11 · 10 종목 전체 적재(한 분기 뒤 표지 · 11월 결산 마지막 두 행 = 한 기간 한 번 · 10월 결산 마지막 행 = 202612) ·
      T16 한 기간에 두 행 값이 다름 → 3 · T17 결산월 없는 종목(숫자 있음) → 3 · T17b fiscal_month.parquet 없음 → 3 ·
      T17c 결산월 없는 금융업(글자 칸만) → 통과 · T18 결산월이 12로 잘못 적힌 11월 결산 종목(18분기) → 종목별 정렬 대조 3 ·
      T18b 같은 책 · 결산월 맞음 → 통과 · T19 창 갱신 + 결산월 11 · 10(창 앞 행이 창 안 · 202612 표지까지 창) ·
      T19b 창 시작에 바로 닿는 책 — 덮지 않은 기간(11 · 10월 결산 202606)은 지우지 않는다(창 = 결산월 부류별).
돌연변이(검출력 — 관문을 끄면 그 모양이 통과해야 한다 · 소스 글자 치환 · 치환 성사 단정 · 사본 단독 실행):
      TM1 연속 분기 관문 끔 → T8 통과 · TM2 창 시작 관문 끔 → T7 통과 · TM3 창 끝 관문 끔 → T9 통과 ·
      TM4 FILL_RATIO 0 → T4 통과 · TM5 CONTROL_MIN 0 → T10 통과 · TM6 월 색인에서 −3(3개월 래깅) 제거 → 양성 대조가 잡음(3) ·
      TM7 결산월 무시(12 고정) → T15 꼴이 한 분기 이른 표지로 써진다 · TM8 종목별 정렬 대조 끔 → T18 통과 ·
      TM9 한 기간 두 행 값 대조 끔 → T16 통과 · TM10 결산월 없으면 12 → T17 통과 · TM11 창 = 부류 합집합 → T19b 꼴에서 8행 삭제.
실행: .venv_qvest_ml/Scripts/python.exe -X utf8 08_Tests/data/test_qw_fund_v2_tax_ingest.py
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(os.environ.get("QM_ROOT") or Path(__file__).resolve().parents[2])
SUT = ROOT / "02_Infrastructure/data/qw_fund_v2_tax_ingest.py"
CORE = ROOT / "02_Infrastructure/data/qw_fund_v2_ingest.py"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


M = load(SUT, "qw_fund_v2_tax_ingest")
import openpyxl  # noqa: E402
import pandas as pd  # noqa: E402
import pyarrow as pa  # noqa: E402
import pyarrow.parquet as pq  # noqa: E402

PASS = FAIL = 0
def ok(m):
    global PASS; PASS += 1; print("  OK  ", m)
def ng(m):
    global FAIL; FAIL += 1; print("  FAIL", m)

T = Path(tempfile.mkdtemp(prefix="qwtax_"))
CODES = [f"A{200000 + i:06d}" for i in range(60)]   # 0 = 금융업('#INVALID OPTION') · 1 = 단위 빈칸 · 12 = 지그재그 값
FULL_DATES = ["2025-06", "2025-09", "2025-12", "2026-03", "2026-06", "2026-09", "2026-11"]
WIN_DATES = ["2026-06", "2026-09", "2026-11"]        # 창 2분기(11-10 기준 202606~202609) + 창 앞 한 행(B5 20260701 → 2026-06)
LONG_DATES = [f"{y}-{m:02d}" for y in range(2022, 2027) for m in (3, 6, 9, 12)][2:-1] + ["2026-11"]   # 18행(12월 표지 202206~202609)
# 결산분기는 시험이 따로 정한다(적재기 함수를 쓰면 순환 — 대응이 틀려도 같이 틀린다). 12월 결산 = 손 표(실측 표지)
DATE_PER = {"1999-12": "199909", "2000-03": "199912", "2000-06": "200003", "2025-03": "202412", "2025-06": "202503",
            "2025-09": "202506", "2025-12": "202509", "2026-03": "202512", "2026-06": "202603", "2026-09": "202606",
            "2026-11": "202609", "2026-12": "202609"}
# 결산월 11(분기 = 2 · 5 · 8 · 11월에 끝남) · 10(1 · 4 · 7 · 10월) 손 표 — 행 d 의 3개월 전 날이 든 결산분기 → 끝나는 달의 달력 분기
#   예: 11월 결산 6월 말 행 = 3~5월 분기 → 202606(12월 결산이면 202603) · 11월 6일 행 = 6~8월 분기 → 202609(9월 말 행과 같다)
DATE_PER_FM = {
    11: {"1999-12": "199912", "2000-03": "200003", "2000-06": "200006", "2025-03": "202503", "2025-06": "202506",
         "2025-09": "202509", "2025-12": "202512", "2026-03": "202603", "2026-06": "202606", "2026-09": "202609",
         "2026-11": "202609", "2026-12": "202612"},
    10: {"1999-12": "199912", "2000-03": "200003", "2000-06": "200006", "2025-03": "202503", "2025-06": "202506",
         "2025-09": "202509", "2025-12": "202512", "2026-03": "202603", "2026-06": "202606", "2026-09": "202609",
         "2026-11": "202612", "2026-12": "202612"},
}
PERIODS = ["202503", "202506", "202509", "202512", "202603", "202606", "202609"]
OCL, NIL, TP, DTN = "B201700_M", "B101400_M", "B201600_M", "B100300_M"
ZIG = {12}   # 분기마다 3배 · 1배 — 한 분기 밀리면 같은 분기 대조가 반쯤 깨진다(두 배씩 크는 값은 한쪽으로 밀릴 때만 깨진다)
F2 = {CODES[10]: 11, CODES[11]: 10}


def qk(p):
    return int(p[:4]) * 4 + int(p[4:]) // 3 - 1


def true_label(d, fm=12):
    """시험 쪽 대응(적재기 산술과 다른 방법 — 달을 하나씩 넘긴다): 행 d 의 3개월 전 달부터 결산분기 말 달(fm · fm−3 · fm−6 · fm−9)이
    나올 때까지 앞으로 → 그 달의 달력 분기. T0c 가 손 표와 같음을 단정한다."""
    y, m = int(d[:4]), int(d[5:7])
    ends = {(fm - 1 - 3 * j) % 12 + 1 for j in range(4)}
    y, m = (y, m - 3) if m > 3 else (y - 1, m + 9)
    while m not in ends:
        y, m = (y, m + 1) if m < 12 else (y + 1, 1)
    return f"{y}{(m - 1) // 3 * 3 + 3:02d}"


def val(sheet, i, p, nil_scale=1.0):
    nil = (100 + i) * (3 if qk(p) % 2 == 0 else 1) if i in ZIG else (100 + i) * 2 ** (qk(p) - qk("202503"))
    return {NIL: nil * nil_scale, OCL: nil + 10 + i, TP: 50 + i, DTN: (i % 7) - 3}[sheet]


def make_book(path, dates, stamp="2026-11-09 12:00:00", b12="FQ0", over=None, blank=(), fill=None, units=None,
              nil_scale=1.0, dates_by_sheet=None, b5=20000101, fmap=None, over_row=None):
    """fmap = {종목: 실제 결산월} — 퀀티가 그 행에 싣는 결산분기 값을 그 결산월로 정한다(적재기가 읽는 fiscal_month.parquet 와 별개) ·
    over = {(시트, 종목, 결산분기): 값} · over_row = {(시트, 종목, 날짜 행): 값}."""
    wb = openpyxl.Workbook(); wb.remove(wb.active)
    dk = wb.create_sheet("DATA_Key")
    for i, c in enumerate(CODES):
        dk.cell(row=2 + i, column=4, value=c)
    for s, (code, item) in M.SHEETS.items():
        ws = wb.create_sheet(s)
        ws["A1"] = "     Refresh     "; ws["B1"] = "Last Update : " + stamp
        ws["A3"] = "Time Series (Company)"; ws["A4"] = "Frequency"; ws["B4"] = "Q"
        ws["A5"] = "Period(From)"; ws["B5"] = b5; ws["A6"] = "Period(To)"; ws["B6"] = "CPD-1TD [20261106]"
        ws["A8"] = "Code"; ws["A9"] = "Name"; ws["A10"] = "Item Code"; ws["B10"] = code
        ws["A11"] = "Unit"; ws["A12"] = "Base Date"; ws["A14"] = "D A T E"
        for i, c in enumerate(CODES):
            col = 2 + i
            ws.cell(row=8, column=col, value=c); ws.cell(row=9, column=col, value=f"name{i}")
            ws.cell(row=11, column=col, value=(units or {}).get(c, "" if i == 1 else "Local thou"))
            ws.cell(row=12, column=col, value=b12)
            ws.cell(row=14, column=col, value="N/A" if i == 0 else f"item{i}")
        for r, d in enumerate((dates_by_sheet or {}).get(s, dates)):
            ws.cell(row=15 + r, column=1, value=d)
            for i, c in enumerate(CODES):
                p = true_label(d, (fmap or {}).get(c, 12))
                if i == 0:
                    v = "#INVALID OPTION"
                elif (s, c, p) in blank or (None, c, p) in blank or i >= (fill or {}).get((s, p), len(CODES)):
                    continue
                else:
                    v = (over_row or {}).get((s, c, d), (over or {}).get((s, c, p), val(s, i, p, nil_scale)))
                ws.cell(row=15 + r, column=2 + i, value=v)
    wb.save(path)


def setup(name, wq=2, fm=None, fm_drop=(), no_fm=False, dates=FULL_DATES):
    """fm = {종목: 결산월}(fiscal_month.parquet · 나머지 12 · 실물처럼 글자) · fm_drop = 결산월 없는 종목."""
    root = T / name
    (root / "03_Universe/Fundamental_v2").mkdir(parents=True)
    (root / "02_Infrastructure/data").mkdir(parents=True)
    (root / ".cache/qw_fund_v2").mkdir(parents=True)
    reg = {"fundamentals_v2": {"dir": "03_Universe/Fundamental_v2", "ts_dbs": [{
        "name": "FundV2_TAX", "file": "FundV2_TAX_TS.xlsx",
        "update": {"db": "FundV2_TAX_upd", "file": "FundV2_TAX_TS_upd.xlsx", "window_quarters": wq}}]}}
    (root / "02_Infrastructure/data/qw_updatefile_registry.json").write_text(json.dumps(reg), encoding="utf-8")
    if not no_fm:
        fmd = {c: str((fm or {}).get(c, 12)) for c in CODES if c not in fm_drop}
        pq.write_table(pa.table({"Ticker": list(fmd), "FiscalMonth": list(fmd.values()), "fetched_at": ["x"] * len(fmd)}),
                       root / ".cache/qw_fund_v2/fiscal_month.parquet")
    # v2 AccountsPay(원) = 비이자부유동부채(천원) × 1000 × 0.9 — 바른 대응이면 NIL ≥ AP · 한 분기 밀리면 NIL < AP 가 섞인다
    #   기간 = 책 날짜가 어느 결산월로든 닿는 결산분기 전부(한 분기 뒤 · 앞 대조까지 되게)
    aps = sorted({true_label(d, f) for d in dates for f in (12, 11, 10)})
    ap = [(c, p, "AccountsPay", val(NIL, i, p) * 1000 * 0.9) for i, c in enumerate(CODES) if i >= 1 for p in aps]
    pq.write_table(pa.Table.from_pandas(pd.DataFrame(ap, columns=["Ticker", "Period", "Item", "Value"]), preserve_index=False),
                   root / ".cache/qw_fund_v2/FundV2_BS.parquet")
    return root, root / "03_Universe/Fundamental_v2/FundV2_TAX_TS.xlsx", root / "03_Universe/Fundamental_v2/FundV2_TAX_TS_upd.xlsx"


def run(root, *extra, mod=None):
    sys.argv = ["qw_fund_v2_tax_ingest.py", "--root", str(root), *extra]
    try:
        return (mod or M).main()
    except Exception as e:  # noqa: BLE001
        return f"EXC {e!r}"


def table(root, f="FundV2_TAX.parquet"):
    p = root / ".cache/qw_fund_v2" / f
    return pq.read_table(p).to_pandas() if p.exists() else None


def report(root, f="FundV2_TAX_ingest_report.json"):
    p = root / ".cache/qw_fund_v2" / f
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def one(df, c, p, item):
    r = df[(df["Ticker"] == c) & (df["Period"] == p) & (df["Item"] == item)]
    return r.iloc[0] if len(r) == 1 else None


def full_parent(name, wq=2, fm=None, **kw):
    root, fb, ub = setup(name, wq, fm=fm)
    make_book(fb, FULL_DATES, fmap=fm, **kw)
    rc = run(root, "--expect-date", "2026-11-09")
    return root, fb, ub, rc


SRC = SUT.read_text(encoding="utf-8")


def mutant(name, old, new):
    """소스 글자 치환 사본(+ 같은 폴더에 공용 병합 모듈 사본 — load_core 가 코드 경로로 찾는다). 치환이 정확히 1곳이 아니면 None."""
    if SRC.count(old) != 1:
        ng(f"{name} 돌연변이 치환 대상 {SRC.count(old)}곳(1이어야 함) — 시험이 낡았다")
        return None
    d = T / f"mut_{name}"; d.mkdir()
    shutil.copy(CORE, d / "qw_fund_v2_ingest.py")
    p = d / "qw_fund_v2_tax_ingest.py"; p.write_text(SRC.replace(old, new), encoding="utf-8")
    return load(p, f"tax_mut_{name}")


try:
    # T0 날짜 표지 → 결산분기(실측: 첫 행 '1999-12' · 마지막 행 = CPD-1TD 달 '2026-11')
    got = {d: M.period_from_row_date(d) for d in DATE_PER}
    ok("T0 날짜 → 결산분기 = 행 d − 1분기(12월 결산 · 12개 표지)") if got == DATE_PER else ng(f"T0 {[(d, g) for d, g in got.items() if g != DATE_PER[d]]}")
    exp = {0: DATE_PER, 2: DATE_PER_FM[11], 1: DATE_PER_FM[10]}   # 결산월 mod 3 → 결산분기 말 달이 같은 부류
    bad = [(f, d, M.period_from_row_date(d, f)) for f in range(1, 13) for d in DATE_PER if M.period_from_row_date(d, f) != exp[f % 3][d]]
    ok("T0b 결산월 1~12 × 12개 표지 — 11 · 8 · 5 · 2 = 11월 표 · 10 · 7 · 4 · 1 = 10월 표 · 12 · 9 · 6 · 3 = 12월 표") if not bad else ng(f"T0b {bad[:6]}")
    bad = [(f, d) for f in range(1, 13) for d in DATE_PER if true_label(d, f) != exp[f % 3][d]]
    ok("T0c 시험 쪽 생성기(달 넘기기) = 손 표(결산월 1~12)") if not bad else ng(f"T0c {bad[:6]}")

    # T1 첫 전체 적재
    root, fb, ub, rc = full_parent("t1", blank={(None, CODES[7], "202609")})
    df = table(root); rep = report(root)
    n_exp = 59 * 7 * 4 - 4
    b1 = one(df, CODES[1], "202503", "NonInterestCurLiab") if df is not None else None
    if rc == 0 and len(df) == n_exp and CODES[0] not in set(df["Ticker"]) and b1 is not None and b1["Value"] == 101000.0 \
            and (df["first_fetched_at"] == "2026-11-09T12:00:00").all() and (df["last_fetched_at"] == "2026-11-09T12:00:00").all() \
            and rep["counts"] == {"new": n_exp, "changed": 0, "deleted": 0} \
            and all(v["unit_defaulted_tickers"] == [CODES[1]] and v["text_dropped"] == 7 for v in rep["sheets"].values()) \
            and not (root / ".cache/qw_fund_v2/revisions.parquet").exists():
        ok(f"T1 첫 전체 적재 — 59종 × 7분기 × 4항목 − 4 = {n_exp} · 금융업 글자 제외 · 단위 빈칸 = 천원(보고서 목록) · fetched = B1")
    else: ng(f"T1 rc={rc} rows={None if df is None else len(df)} b1={None if b1 is None else b1['Value']} counts={rep.get('counts')}")

    # T2 · T2b 전체 재적재
    r2, fb2, _, _ = full_parent("t2")
    make_book(fb2, FULL_DATES, stamp="2026-11-09 15:00:00")
    rc = run(r2, "--expect-date", "2026-11-09"); df2 = table(r2); rep2 = report(r2)
    ok("T2 전체 재적재 변경 없음 — counts 0 · first_fetched_at 유지 · last 갱신") if rc == 0 and rep2["counts"] == {"new": 0, "changed": 0, "deleted": 0} \
        and (df2["first_fetched_at"] == "2026-11-09T12:00:00").all() and (df2["last_fetched_at"] == "2026-11-09T15:00:00").all() \
        else ng(f"T2 rc={rc} counts={rep2.get('counts')}")
    make_book(fb2, FULL_DATES, stamp="2026-11-09 16:00:00", over={(TP, CODES[3], "202509"): 4321})
    rc = run(r2, "--expect-date", "2026-11-09"); revs = table(r2, "revisions.parquet")
    ch = revs[revs["kind"] == "changed"] if revs is not None else []
    ok("T2b 전체 재적재 값 변경 → revisions 'changed'(Db FundV2_TAX · 53,000 → 4,321,000)") if rc == 0 and len(ch) == 1 \
        and ch.iloc[0]["Db"] == "FundV2_TAX" and ch.iloc[0]["old_value"] == 53000.0 and ch.iloc[0]["new_value"] == 4321000.0 \
        else ng(f"T2b rc={rc} ch={None if revs is None else revs.to_dict('records')[:2]}")

    # T3 창 갱신(T9 꼴)
    root, fb, ub, _ = full_parent("t3", blank={(None, CODES[7], "202609")})
    before = table(root)
    make_book(ub, WIN_DATES, stamp="2026-11-10 12:00:00", b5=20260701,
              over={(OCL, CODES[5], "202606"): 999999, (OCL, CODES[8], "202603"): 777}, blank={(TP, CODES[6], "202609")})
    rc = run(root, "--window", "--expect-date", "2026-11-10"); df = table(root); revs = table(root, "revisions.parquet")
    rep = report(root, "FundV2_TAX_upd_report.json")
    out_old = before[before["Period"] < "202606"].sort_values(["Ticker", "Period", "Item"]).reset_index(drop=True)
    out_new = df[df["Period"] < "202606"].sort_values(["Ticker", "Period", "Item"]).reset_index(drop=True)
    ch5 = one(df, CODES[5], "202606", "OtherCurLiabInclTax"); c8 = one(df, CODES[8], "202603", "OtherCurLiabInclTax")
    keep9 = one(df, CODES[9], "202606", "NonInterestCurLiab"); new7 = df[(df["Ticker"] == CODES[7]) & (df["Period"] == "202609")]
    rch = revs[revs["kind"] == "changed"]; rde = revs[revs["kind"] == "deleted"]
    good = rc == 0 and out_old.equals(out_new) and ch5["Value"] == 999999000.0 and ch5["first_fetched_at"] == "2026-11-10T12:00:00" \
        and c8["Value"] == val(OCL, 8, "202603") * 1000 and one(df, CODES[6], "202609", "TradePayables") is None \
        and len(new7) == 4 and (new7["first_fetched_at"] == "2026-11-10T12:00:00").all() \
        and keep9["first_fetched_at"] == "2026-11-09T12:00:00" and keep9["last_fetched_at"] == "2026-11-10T12:00:00" \
        and len(rch) == 1 and rch.iloc[0]["Db"] == "FundV2_TAX_upd" and rch.iloc[0]["new_value"] == 999999000.0 \
        and len(rde) == 1 and rde.iloc[0]["Ticker"] == CODES[6] and rep["counts"] == {"new": 4, "changed": 1, "deleted": 1} \
        and rep["rows_before_window_dropped"] == ["202603"] and rep["periods"] == ["202606", "202609", 2]
    ok("T3 창 갱신 — 창(202606~202609)만 교체 · 창 앞 행(202603) 버림 · changed 1 · deleted 1 · new 4 · 안 바뀐 값 first 유지") if good \
        else ng(f"T3 rc={rc} counts={rep.get('counts')} dropped={rep.get('rows_before_window_dropped')} outside_equal={out_old.equals(out_new)}")

    # T4 창 채움 급감(T9b 꼴) — 부모 59 → 9
    root, fb, ub, _ = full_parent("t4")
    par = (root / ".cache/qw_fund_v2/FundV2_TAX.parquet").read_bytes()
    make_book(ub, WIN_DATES, stamp="2026-11-10 12:00:00", fill={(OCL, "202606"): 10})
    rc = run(root, "--window", "--expect-date", "2026-11-10")
    ok("T4 창 채움 급감(부모 59 → 9) → 3 · 부모 그대로 · revisions 없음") if rc == 3 and par == (root / ".cache/qw_fund_v2/FundV2_TAX.parquet").read_bytes() \
        and not (root / ".cache/qw_fund_v2/revisions.parquet").exists() else ng(f"T4 rc={rc}")
    t4_root = root

    # T5 B1 낡음 · T6 B12
    make_book(ub, WIN_DATES, stamp="2026-11-08 12:00:00")
    rc = run(t4_root, "--window", "--expect-date", "2026-11-10")
    ok("T5 B1 날짜 ≠ 기대 날짜(갱신 안 됨) → 3") if rc == 3 else ng(f"T5 rc={rc}")
    r6, fb6, _ = setup("t6"); make_book(fb6, FULL_DATES, b12="FY0")
    rc = run(r6, "--expect-date", "2026-11-09")
    ok("T6 B12 'FY0' → 3 · 출력 없음") if rc == 3 and table(r6) is None else ng(f"T6 rc={rc}")

    # T7 창 시작 늦음 · T7b 창 앞 두 행 · T8 가운데 빠짐 · T8b 낡은 행 남음 · T9 끝 잘림 · T9b 분기 말일
    shapes = {
        "T7": (["2026-11"], "창 시작 늦음(202609 > 202606)"),
        "T7b": (["2026-03", "2026-06", "2026-09", "2026-11"], "창 앞 두 행(B5 안 먹음)"),
        "T8": (["2026-06", "2026-11"], "가운데 분기 빠짐(202606)"),
        "T8b": (["2026-06", "2026-09", "2026-11", "2025-12", "2026-03", "2026-06"], "틀의 낡은 행 남음(중복 분기)"),
    }
    for tag, (dates, what) in shapes.items():
        make_book(ub, dates, stamp="2026-11-10 12:00:00")
        rc = run(t4_root, "--window", "--expect-date", "2026-11-10")
        ok(f"{tag} {what} → 3") if rc == 3 else ng(f"{tag} rc={rc}")
    make_book(ub, ["2026-03", "2026-06"], stamp="2026-11-10 12:00:00")
    rc = run(t4_root, "--window", "--window-quarters", "3", "--expect-date", "2026-11-10")
    ok("T9 끝 잘림(3분기 창 202603~202609 · 마지막 행 202603) → 3") if rc == 3 else ng(f"T9 rc={rc}")
    if par != (t4_root / ".cache/qw_fund_v2/FundV2_TAX.parquet").read_bytes():
        ng("T5~T9 거부 사례가 부모를 바꿨다")
    make_book(ub, ["2026-09", "2026-12"], stamp="2026-12-31 12:00:00", b5=20261001)
    rc = run(t4_root, "--window", "--expect-date", "2026-12-31")
    rep9 = report(t4_root, "FundV2_TAX_upd_report.json") if rc == 0 else {}
    ok("T9b 분기 말일 12-31(창 202609~202612 · CPD-1TD 12-30 → 마지막 행 202609 = 한 분기 앞) → 통과 · 창 = 202609") \
        if rc == 0 and rep9.get("periods") == ["202609", "202609", 1] else ng(f"T9b rc={rc} periods={rep9.get('periods')}")

    # T10 양성 대조 실패 · T11 부모 없음 · T12 모르는 단위 · T13 dry-run · T14 시트별 날짜 다름
    r10, fb10, _ = setup("t10"); make_book(fb10, FULL_DATES, nil_scale=0.5)
    rc = run(r10, "--expect-date", "2026-11-09")
    ok("T10 매입채무 양성 대조 실패(NIL < AP) → 3 · 출력 없음") if rc == 3 and table(r10) is None else ng(f"T10 rc={rc}")
    r11, _, ub11 = setup("t11"); make_book(ub11, WIN_DATES, stamp="2026-11-10 12:00:00")
    rc = run(r11, "--window", "--expect-date", "2026-11-10")
    ok("T11 부모 없이 창 갱신 → 3") if rc == 3 and table(r11) is None else ng(f"T11 rc={rc}")
    r12, fb12, _ = setup("t12"); make_book(fb12, FULL_DATES, units={CODES[4]: "USD"})
    rc = run(r12, "--expect-date", "2026-11-09")
    ok("T12 모르는 단위(USD) 아래 숫자 → 3") if rc == 3 and table(r12) is None else ng(f"T12 rc={rc}")
    r13, fb13, _ = setup("t13"); make_book(fb13, FULL_DATES)
    rc = run(r13, "--expect-date", "2026-11-09", "--dry-run")
    ok("T13 dry-run → rc 0 · 아무것도 안 씀") if rc == 0 and not any((r13 / ".cache/qw_fund_v2").glob("FundV2_TAX*")) else ng(f"T13 rc={rc}")
    r14, fb14, _ = setup("t14"); make_book(fb14, FULL_DATES, dates_by_sheet={DTN: FULL_DATES[1:]})
    rc = run(r14, "--expect-date", "2026-11-09")
    ok("T14 시트별 날짜 행 다름 → 3") if rc == 3 and table(r14) is None else ng(f"T14 rc={rc}")

    # T15 결산월 11 · 10 종목(나머지 12월) 전체 적재
    r15, _, _, rc = full_parent("t15", fm=F2)
    df = table(r15); rep = report(r15)
    p10 = ["202506", "202509", "202512", "202603", "202606", "202609"]
    exp15 = {(c, p, it): val(sh, i, p) * 1000 for c, i, ps in ((CODES[10], 10, p10), (CODES[11], 11, p10 + ["202612"]))
             for p in ps for sh, (_, it) in M.SHEETS.items()}
    got15 = {k: v for k, v in df.set_index(["Ticker", "Period", "Item"])["Value"].items() if k[0] in F2} if df is not None else {}
    dec2 = sorted(df.loc[df["Ticker"] == CODES[2], "Period"].unique()) if df is not None else None
    good = rc == 0 and got15 == exp15 and dec2 == PERIODS and len(df) == 59 * 7 * 4 - 4 \
        and rep.get("fiscal_month") == {"off_calendar_tickers": {CODES[10]: 11, CODES[11]: 10}, "same_period_rows_kept_once": 4}
    ok("T15 결산월 11 · 10 — 분기 말 행이 한 분기 뒤 표지 · 11월 결산 마지막 두 행 = 202609 한 번(4행) · 10월 결산 마지막 행 = 202612 · "
       "12월 결산 그대로") if good else ng(f"T15 rc={rc} rows={None if df is None else len(df)} fm={rep.get('fiscal_month')} "
                                           f"diff={sorted(set(exp15.items()) ^ set(got15.items()))[:4]}")

    # T16 한 기간에 두 행 값이 다름 · T17 결산월 없음 · T17b 파일 없음 · T17c 금융업(글자만) 결산월 없음
    r16, fb16, _ = setup("t16", fm={CODES[10]: 11})
    make_book(fb16, FULL_DATES, fmap={CODES[10]: 11}, over_row={(TP, CODES[10], "2026-11"): 4242})
    rc = run(r16, "--expect-date", "2026-11-09")
    ok("T16 11월 결산 마지막 두 행(한 기간)의 값이 다름 → 3 · 출력 없음") if rc == 3 and table(r16) is None else ng(f"T16 rc={rc}")
    r17, fb17, _ = setup("t17", fm_drop={CODES[5]}); make_book(fb17, FULL_DATES)
    rc = run(r17, "--expect-date", "2026-11-09")
    ok("T17 숫자가 있는 종목의 결산월 없음 → 3 · 출력 없음") if rc == 3 and table(r17) is None else ng(f"T17 rc={rc}")
    r17b, fb17b, _ = setup("t17b", no_fm=True); make_book(fb17b, FULL_DATES)
    rc = run(r17b, "--expect-date", "2026-11-09")
    ok("T17b fiscal_month.parquet 없음 → 3") if rc == 3 and table(r17b) is None else ng(f"T17b rc={rc}")
    r17c, fb17c, _ = setup("t17c", fm_drop={CODES[0]}); make_book(fb17c, FULL_DATES)
    rc = run(r17c, "--expect-date", "2026-11-09")
    ok("T17c 결산월 없는 금융업(글자 칸만) → 통과") if rc == 0 else ng(f"T17c rc={rc}")

    # T18 결산월이 12로 잘못 적힌 11월 결산 종목(18분기 · 지그재그) · T18b 같은 책 · 결산월 맞음
    r18, fb18, _ = setup("t18", dates=LONG_DATES)
    make_book(fb18, LONG_DATES, fmap={CODES[12]: 11})
    rc = run(r18, "--expect-date", "2026-11-09")
    ok("T18 결산월이 12로 잘못 적힌 11월 결산 종목 → 종목별 정렬 대조 3 · 출력 없음") if rc == 3 and table(r18) is None else ng(f"T18 rc={rc}")
    r18b, fb18b, _ = setup("t18b", fm={CODES[12]: 11}, dates=LONG_DATES)
    make_book(fb18b, LONG_DATES, fmap={CODES[12]: 11})
    rc = run(r18b, "--expect-date", "2026-11-09")
    al = report(r18b).get("alignment_control", {}) if rc == 0 else {}
    ok("T18b 같은 책 · 결산월 맞음 → 통과 · 정렬 대조 59종목 · 걸림 0 · 그 종목 같은 분기 1.0(17분기)") \
        if rc == 0 and al.get("tested") == 59 and al.get("flagged") == {} and al.get("watch", {}).get(CODES[12], [0, 0])[:2] == [17, 1.0] \
        else ng(f"T18b rc={rc} al={ {k: al.get(k) for k in ('tested', 'flagged', 'watch')} }")

    # T19 창 갱신 + 결산월 11 · 10 — 창 앞 행(2026-06)이 이 종목들에겐 창 안(202606) · 10월 결산 202612 까지 창
    root, fb, ub, _ = full_parent("t19", fm=F2)
    before = table(root)
    make_book(ub, WIN_DATES, stamp="2026-11-10 12:00:00", b5=20260701, fmap=F2, over={(OCL, CODES[10], "202606"): 555})
    rc = run(root, "--window", "--expect-date", "2026-11-10"); df = table(root)
    rep = report(root, "FundV2_TAX_upd_report.json") if rc == 0 else {}
    o10 = one(df, CODES[10], "202606", "OtherCurLiabInclTax")
    q12 = df[(df["Ticker"] == CODES[11]) & (df["Period"] == "202612")]
    out_old = before[before["Period"] < "202606"].sort_values(["Ticker", "Period", "Item"]).reset_index(drop=True)
    out_new = df[df["Period"] < "202606"].sort_values(["Ticker", "Period", "Item"]).reset_index(drop=True)
    good = rc == 0 and o10 is not None and o10["Value"] == 555000.0 and len(q12) == 4 \
        and (q12["first_fetched_at"] == "2026-11-09T12:00:00").all() and (q12["last_fetched_at"] == "2026-11-10T12:00:00").all() \
        and rep.get("counts") == {"new": 0, "changed": 1, "deleted": 0} and rep.get("rows_before_window_dropped") == ["202603"] \
        and rep.get("cells_before_window_dropped") == 57 * 4 and rep.get("win_periods") == ["202606", "202612", 3] and out_old.equals(out_new)
    ok("T19 창 갱신 + 결산월 11 · 10 — 11월 결산 창 앞 행 = 202606(창 안 · 바뀐 값 1) · 10월 결산 202612 창 안(같은 값 · last 갱신) · "
       "12월 결산 창 앞 228칸 버림 · 창 밖 그대로") if good else ng(f"T19 rc={rc} counts={rep.get('counts')} win={rep.get('win_periods')} "
                                                     f"dropped={rep.get('cells_before_window_dropped')}")

    # T19b 창 시작에 바로 닿는 책(창 앞 행 없음 — 관문이 허용) — 11 · 10월 결산 종목은 그 책으로 202606 을 덮지 않는다(그대로 둬야)
    root, fb, ub, _ = full_parent("t19b", fm=F2)
    make_book(ub, ["2026-09", "2026-11"], stamp="2026-11-10 12:00:00", b5=20261001, fmap=F2)
    rc = run(root, "--window", "--expect-date", "2026-11-10"); df = table(root)
    rep = report(root, "FundV2_TAX_upd_report.json") if rc == 0 else {}
    kept = df[df["Ticker"].isin(list(F2)) & (df["Period"] == "202606")]
    ok("T19b 창 시작에 바로 닿는 책 — 11 · 10월 결산 종목 202606(덮지 않은 기간)은 그대로(deleted 0 · last 그대로 · 8행)") \
        if rc == 0 and rep.get("counts") == {"new": 0, "changed": 0, "deleted": 0} and len(kept) == 8 \
        and (kept["last_fetched_at"] == "2026-11-09T12:00:00").all() and rep.get("rows_before_window_dropped") == [] \
        else ng(f"T19b rc={rc} counts={rep.get('counts')} kept={len(kept)}")

    # 돌연변이 — 관문을 끄면 그 모양이 통과해야 한다(그 사례가 그 관문의 발화다)
    def mut_case(tag, m, dates, extra=()):
        if m is None:
            return
        rm, _, ubm, _ = full_parent(f"m_{tag}")
        make_book(ubm, dates, stamp="2026-11-10 12:00:00")
        rc = run(rm, "--window", *extra, "--expect-date", "2026-11-10", mod=m)
        ok(f"{tag} 관문 끔 → 그 모양 통과(rc 0)") if rc == 0 else ng(f"{tag} rc={rc}")
    mut_case("TM1", mutant("TM1", "if any(y - x != 1 for x, y in zip(ks, ks[1:])):", "if False:"), shapes["T8"][0])
    mut_case("TM2", mutant("TM2", "if ks[0] > kf or len(before) > 1:", "if False:"), shapes["T7"][0])
    mut_case("TM3", mutant("TM3", "if ks[-1] not in (kl - 1, kl):", "if False:"), ["2026-03", "2026-06"], ("--window-quarters", "3"))
    real_core = M.load_core
    def weak_core():
        c = real_core(); c.FILL_RATIO = 0.0; return c
    M.load_core = weak_core
    try:
        rm, _, ubm, _ = full_parent("m_tm4")
        make_book(ubm, WIN_DATES, stamp="2026-11-10 12:00:00", fill={(OCL, "202606"): 10})
        rc = run(rm, "--window", "--expect-date", "2026-11-10")
    finally:
        M.load_core = real_core
    ok("TM4 FILL_RATIO 0 → T4 모양 통과(rc 0)") if rc == 0 else ng(f"TM4 rc={rc}")
    cmin = M.CONTROL_MIN; M.CONTROL_MIN = 0.0
    try:
        rm, fbm, _ = setup("m_tm5"); make_book(fbm, FULL_DATES, nil_scale=0.5)
        rc = run(rm, "--expect-date", "2026-11-09")
    finally:
        M.CONTROL_MIN = cmin
    ok("TM5 CONTROL_MIN 0 → T10 모양 통과(rc 0)") if rc == 0 else ng(f"TM5 rc={rc}")
    m6 = mutant("TM6", "i = y * 12 + (m - 1) - 3", "i = y * 12 + (m - 1)")
    if m6 is not None:
        rm, fbm, _ = setup("m_tm6"); make_book(fbm, FULL_DATES)
        rc = run(rm, "--expect-date", "2026-11-09", mod=m6)
        ok("TM6 월 색인에서 −3(3개월 래깅)을 빼면(한 분기 밀림) 양성 대조가 잡는다(rc 3)") if rc == 3 and table(rm) is None else ng(f"TM6 rc={rc}")
    m7 = mutant("TM7", "key = list(zip(new['RowDate'], fmv.astype(int)))", "key = list(zip(new['RowDate'], [12] * len(new)))")
    if m7 is not None:
        rm, fbm, _ = setup("m_tm7", fm=F2); make_book(fbm, FULL_DATES, fmap=F2)
        rc = run(rm, "--expect-date", "2026-11-09", mod=m7); dm = table(rm)
        early = dm is not None and one(dm, CODES[10], "202503", "NonInterestCurLiab") is not None
        ok("TM7 결산월 무시(12 고정) → T15 꼴이 한 분기 이른 표지(CODES[10] 202503)로 써진다 — T15 가 잡는 꼴") \
            if rc == 0 and early else ng(f"TM7 rc={rc} early={early}")
    m8 = mutant("TM8", "if al['flagged']:", "if False:")
    if m8 is not None:
        rm, fbm, _ = setup("m_tm8", dates=LONG_DATES); make_book(fbm, LONG_DATES, fmap={CODES[12]: 11})
        rc = run(rm, "--expect-date", "2026-11-09", mod=m8)
        ok("TM8 종목별 정렬 대조 끔 → T18 꼴 통과(rc 0 — 전체 양성 대조만으로는 못 잡는다)") if rc == 0 else ng(f"TM8 rc={rc}")
    m9 = mutant("TM9", "if (nv > 1).any():", "if False:")
    if m9 is not None:
        rm, fbm, _ = setup("m_tm9", fm={CODES[10]: 11})
        make_book(fbm, FULL_DATES, fmap={CODES[10]: 11}, over_row={(TP, CODES[10], "2026-11"): 4242})
        rc = run(rm, "--expect-date", "2026-11-09", mod=m9)
        ok("TM9 한 기간 두 행 값 대조 끔 → T16 꼴 통과(rc 0)") if rc == 0 else ng(f"TM9 rc={rc}")
    m10 = mutant("TM10", "fmv = new['Ticker'].map(fms)", "fmv = new['Ticker'].map(fms).fillna(12)")
    if m10 is not None:
        rm, fbm, _ = setup("m_tm10", fm_drop={CODES[5]}); make_book(fbm, FULL_DATES)
        rc = run(rm, "--expect-date", "2026-11-09", mod=m10)
        ok("TM10 결산월 없으면 12 → T17 꼴 통과(rc 0)") if rc == 0 else ng(f"TM10 rc={rc}")
    m11 = mutant("TM11", "win = {(it, p) for _, it in SHEETS.values() for p in ps}",
                 "win = {(it, p) for _, it in SHEETS.values() for p in win_periods}")
    if m11 is not None:
        rm, _, ubm, _ = full_parent("m_tm11", fm=F2)
        make_book(ubm, ["2026-09", "2026-11"], stamp="2026-11-10 12:00:00", b5=20261001, fmap=F2)
        rc = run(rm, "--window", "--expect-date", "2026-11-10", mod=m11)
        cnt = report(rm, "FundV2_TAX_upd_report.json").get("counts") if rc == 0 else None
        ok("TM11 창을 결산월 부류 합집합 하나로 → T19b 꼴에서 11 · 10월 결산 종목 202606 이 지워진다(deleted 8 — T19b 가 잡는 꼴)") \
            if rc == 0 and cnt == {"new": 0, "changed": 0, "deleted": 8} else ng(f"TM11 rc={rc} counts={cnt}")
except Exception as e:  # noqa: BLE001
    import traceback; traceback.print_exc()
    ng(f"harness error: {e!r}")
finally:
    shutil.rmtree(T, ignore_errors=True)

print(f"\n합계: 통과 {PASS} · 실패 {FAIL}")
print(json.dumps({"test": "qw_fund_v2_tax_ingest", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(1 if FAIL else 0)
