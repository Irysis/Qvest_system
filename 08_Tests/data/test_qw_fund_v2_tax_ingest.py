"""test_qw_fund_v2_tax_ingest.py — 02_Infrastructure/data/qw_fund_v2_tax_ingest.py 합성 시계열 책 시험(운영 03_Universe · .cache 무접촉).

책 모양 = 실제 퀀티 시계열(Company) 책: B1 'Last Update' · B5 From · 8행 종목 · B10 코드 · 11행 단위 · 12행 Base Date ·
15행부터 A열 날짜. 날짜 표지는 실측(11-09 전체 책 · 10종목 시험 책)대로 — 분기 말 달('1999-12' · '2000-03' …) + 마지막 행 =
CPD-1TD 의 달('2026-11'), 첫 행 = B5 이하 마지막 분기 말(From 20000101 → '1999-12'). 행 d 의 값 = d − 1분기 결산분기(FQ0).

사례: T0 날짜 → 결산분기 고정(실측 표지) · T1 첫 전체 적재 · T2 전체 재적재 변경 없음 · T2b 전체 재적재 값 변경 → revisions ·
      T3 창 갱신(T9 꼴: 창만 교체 · 창 앞 한 행 버림 · changed/deleted/new · first_fetched_at 유지) ·
      T4 창 채움 급감 → 3(T9b 꼴) · T5 B1 낡음 → 3 · T6 B12 FY0 → 3 · T7 창 시작 늦음 → 3 · T7b 창 앞 두 행 → 3 ·
      T8 가운데 분기 빠짐 → 3 · T8b 틀의 낡은 행 남음(중복) → 3 · T9 끝 잘림 → 3 · T9b 분기 말일(끝 한 분기 앞) → 통과 ·
      T10 매입채무 양성 대조 실패 → 3 · T11 부모 없이 창 갱신 → 3 · T12 모르는 단위 → 3 · T13 dry-run 무기록 · T14 시트별 날짜 다름 → 3.
돌연변이(검출력 — 관문을 끄면 그 모양이 통과해야 한다 · 소스 글자 치환 · 치환 성사 단정 · 사본 단독 실행):
      TM1 연속 분기 관문 끔 → T8 통과 · TM2 창 시작 관문 끔 → T7 통과 · TM3 창 끝 관문 끔 → T9 통과 ·
      TM4 FILL_RATIO 0 → T4 통과 · TM5 CONTROL_MIN 0 → T10 통과 · TM6 분기 대응 −1분기 제거 → 양성 대조가 잡음(3).
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
CODES = [f"A{200000 + i:06d}" for i in range(60)]   # 0 = 금융업('#INVALID OPTION') · 1 = 단위 빈칸
FULL_DATES = ["2025-06", "2025-09", "2025-12", "2026-03", "2026-06", "2026-09", "2026-11"]
WIN_DATES = ["2026-06", "2026-09", "2026-11"]        # 창 2분기(11-10 기준 202606~202609) + 창 앞 한 행(B5 20260701 → 2026-06)
# 결산분기는 시험이 따로 정한다(적재기 함수를 쓰면 순환 — 대응이 틀려도 같이 틀린다)
DATE_PER = {"1999-12": "199909", "2000-03": "199912", "2000-06": "200003", "2025-03": "202412", "2025-06": "202503",
            "2025-09": "202506", "2025-12": "202509", "2026-03": "202512", "2026-06": "202603", "2026-09": "202606",
            "2026-11": "202609", "2026-12": "202609"}
PERIODS = ["202503", "202506", "202509", "202512", "202603", "202606", "202609"]
OCL, NIL, TP, DTN = "B201700_M", "B101400_M", "B201600_M", "B100300_M"


def qk(p):
    return int(p[:4]) * 4 + int(p[4:]) // 3 - 1


def val(sheet, i, p, nil_scale=1.0):
    nil = (100 + i) * 2 ** (qk(p) - qk("202503"))
    return {NIL: nil * nil_scale, OCL: nil + 10 + i, TP: 50 + i, DTN: (i % 7) - 3}[sheet]


def make_book(path, dates, stamp="2026-11-09 12:00:00", b12="FQ0", over=None, blank=(), fill=None, units=None,
              nil_scale=1.0, dates_by_sheet=None, b5=20000101):
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
            p = DATE_PER[d]
            ws.cell(row=15 + r, column=1, value=d)
            for i, c in enumerate(CODES):
                if i == 0:
                    v = "#INVALID OPTION"
                elif (s, c, p) in blank or (None, c, p) in blank or i >= (fill or {}).get((s, p), len(CODES)):
                    continue
                else:
                    v = (over or {}).get((s, c, p), val(s, i, p, nil_scale))
                ws.cell(row=15 + r, column=2 + i, value=v)
    wb.save(path)


def setup(name, wq=2):
    root = T / name
    (root / "03_Universe/Fundamental_v2").mkdir(parents=True)
    (root / "02_Infrastructure/data").mkdir(parents=True)
    (root / ".cache/qw_fund_v2").mkdir(parents=True)
    reg = {"fundamentals_v2": {"dir": "03_Universe/Fundamental_v2", "ts_dbs": [{
        "name": "FundV2_TAX", "file": "FundV2_TAX_TS.xlsx",
        "update": {"db": "FundV2_TAX_upd", "file": "FundV2_TAX_TS_upd.xlsx", "window_quarters": wq}}]}}
    (root / "02_Infrastructure/data/qw_updatefile_registry.json").write_text(json.dumps(reg), encoding="utf-8")
    # v2 AccountsPay(원) = 비이자부유동부채(천원) × 1000 × 0.9 — 바른 대응이면 NIL ≥ AP · 한 분기 밀리면 NIL < AP(값이 분기마다 두 배)
    ap = [(c, p, "AccountsPay", val(NIL, i, p) * 1000 * 0.9) for i, c in enumerate(CODES) if i >= 1 for p in PERIODS]
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


def one(df, c, p, item):
    r = df[(df["Ticker"] == c) & (df["Period"] == p) & (df["Item"] == item)]
    return r.iloc[0] if len(r) == 1 else None


def full_parent(name, wq=2, **kw):
    root, fb, ub = setup(name, wq)
    make_book(fb, FULL_DATES, **kw)
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
    ok("T0 날짜 → 결산분기 = 행 d − 1분기(12개 표지)") if got == DATE_PER else ng(f"T0 {[(d, g) for d, g in got.items() if g != DATE_PER[d]]}")

    # T1 첫 전체 적재
    root, fb, ub, rc = full_parent("t1", blank={(None, CODES[7], "202609")})
    df = table(root); rep = json.loads((root / ".cache/qw_fund_v2/FundV2_TAX_ingest_report.json").read_text(encoding="utf-8"))
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
    rc = run(r2, "--expect-date", "2026-11-09"); df2 = table(r2)
    rep2 = json.loads((r2 / ".cache/qw_fund_v2/FundV2_TAX_ingest_report.json").read_text(encoding="utf-8"))
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
    rep = json.loads((root / ".cache/qw_fund_v2/FundV2_TAX_upd_report.json").read_text(encoding="utf-8"))
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
    rep9 = json.loads((t4_root / ".cache/qw_fund_v2/FundV2_TAX_upd_report.json").read_text(encoding="utf-8")) if rc == 0 else {}
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
    m6 = mutant("TM6", "return _qk(y * 4 + (m - 1) // 3 - 1)", "return _qk(y * 4 + (m - 1) // 3)")
    if m6 is not None:
        rm, fbm, _ = setup("m_tm6"); make_book(fbm, FULL_DATES)
        rc = run(rm, "--expect-date", "2026-11-09", mod=m6)
        ok("TM6 분기 대응에서 −1분기를 빼면(한 분기 밀림) 양성 대조가 잡는다(rc 3)") if rc == 3 and table(rm) is None else ng(f"TM6 rc={rc}")
except Exception as e:  # noqa: BLE001
    import traceback; traceback.print_exc()
    ng(f"harness error: {e!r}")
finally:
    shutil.rmtree(T, ignore_errors=True)

print(f"\n합계: 통과 {PASS} · 실패 {FAIL}")
print(json.dumps({"test": "qw_fund_v2_tax_ingest", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(1 if FAIL else 0)
