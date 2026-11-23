"""test_qw_fund_v2_div_supplement.py — 02_Infrastructure/data/qw_fund_v2_div_supplement.py 합성 시계열 책 시험(운영 03_Universe · .cache 무접촉).

책 모양 = 실제 퀀티 시계열(Company) 책: B1 'Last Update' · 8행 종목 · B10 코드 · 11행 단위 · 12행 Base Date · 15행부터 A열 날짜.
날짜 행 → 결산분기는 시험이 손 표로 따로 정한다(적재기 함수를 쓰면 순환): 12월 결산 = d − 1분기 · 11월 · 10월 결산 = 분기 말 행 그대로.
사례: S1 첫 보충(금액 × 1000 · 주당 그대로 · 결산월 11 · 10 종목은 한 분기 뒤 표지 · 창 밖 행 무접촉 · 부모 둘) ·
      S2 다시 돌려도 변경 없음(first_fetched_at 유지) · S3 dry-run 무기록 ·
      G1 B10 코드 다름 → 3 · G2 Base Date FY0 → 3 · G3 금액 항목의 모르는 단위 → 3 · G4 단위가 틀린 책(천 원 아님) → 겹침 대조 3 ·
      G5 날짜 행이 창을 덮지 못함 → 3 · G6 결산월 없는 종목에 0 아닌 값 → 3 · G6b 결산월 없는 종목이 0 뿐 → 빼고 통과 ·
      G7 창 안 채움 부족 → 3 · G8 부모 표 없음 → 3 · G9 등록부에 이름 없음 → 3 · G10 한 기간에 두 행 값이 다름 → 3
돌연변이(검출력): M1 겹침 대조 끔 → G4 모양이 통과 · M2 결산월 무시(12 고정) → 겹침 대조가 잡는다(3) · M3 채움 하한 0 → G7 통과.
실행: .venv_qvest_ml/Scripts/python.exe -X utf8 08_Tests/data/test_qw_fund_v2_div_supplement.py
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

try:
    import pandas as _pd_probe  # noqa: F401
    import pyarrow as _pa_probe  # noqa: F401
except ImportError:   # 배터리는 pandas · pyarrow 없는 시스템 파이썬으로 돈다 — venv 로 다시 실행한다(SKIP 은 통과와 겉보기가 같다)
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

ROOT = Path(os.environ.get("QM_ROOT") or Path(__file__).resolve().parents[2])
SUT = ROOT / "02_Infrastructure/data/qw_fund_v2_div_supplement.py"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


M = load(SUT, "qw_fund_v2_div_supplement")
import openpyxl  # noqa: E402
import pyarrow as pa  # noqa: E402
import pyarrow.parquet as pq  # noqa: E402

PASS = FAIL = 0
def ok(m):
    global PASS; PASS += 1; print("  OK  ", m)
def ng(m):
    global FAIL; FAIL += 1; print("  FAIL", m)

T = Path(tempfile.mkdtemp(prefix="qwdiv_"))
NAME = "FundV2_DIV_201209_201312"
CODES = [f"A{300000 + i:06d}" for i in range(60)]
FM = {c: 12 for c in CODES}; FM[CODES[7]] = 11; FM[CODES[8]] = 10          # 결산월 — 7번 = 11월 · 8번 = 10월
DATES = ["2012-06", "2012-09", "2012-12", "2013-03", "2013-06", "2013-09", "2013-12", "2014-03", "2014-06"]
WINDOW = ["201209", "201212", "201303", "201306", "201309", "201312"]
PEER_PER = ["201203", "201206", "201403", "201406"]                         # 피어 표에 이미 있는 기간(창 앞뒤)
# 손 표: 날짜 행 → 결산분기 표지(12월 결산 = d − 1분기 · 11 · 10월 결산 = 분기 말 행 그대로 — 세금 항목 적재 시험의 실측 표와 같은 규칙)
LABEL = {12: dict(zip(DATES, ["201203", "201206", "201209", "201212", "201303", "201306", "201309", "201312", "201403"])),
         11: dict(zip(DATES, ["201206", "201209", "201212", "201303", "201306", "201309", "201312", "201403", "201406"]))}
LABEL[10] = LABEL[11]
SHEETS = [("a.xlsx", "B201700_M", "CashDivTotal", "M441800.M", "amount", "FundV2_META"), ("a.xlsx", "B101400_M", "AdjDPS", "M423400.M", "per_share", "FundV2_META"),
          ("b.xlsx", "B201700_M", "CashDivCommon", "M441600.M", "amount", "FundV2_META"), ("b.xlsx", "B201600_M", "AdjDPSFinal", "M423200.M", "per_share", "FundV2_INFO")]
ITEM_NO = {"CashDivTotal": 1, "AdjDPS": 2, "CashDivCommon": 3, "AdjDPSFinal": 4}


def val(item, i, per):
    """(항목, 종목 번호, 결산분기)의 참값 — 금액은 원 · 주당은 원."""
    base = ITEM_NO[item] * 1000 + i * 10 + int(per[2:]) % 97
    return float(base * 1000) if item in ("CashDivTotal", "CashDivCommon") else float(base)


def make_book(path, sheets, b12="FQ0", code=None, unit=None, dates=DATES, scale=None, over=None, stamp="2026-11-23 20:41:23"):
    wb = openpyxl.Workbook(); wb.remove(wb.active)
    for (_, sheet, item, cd, kind, _) in sheets:
        ws = wb.create_sheet(sheet)
        ws["A1"] = "     Refresh     "; ws["B1"] = "Last Update : " + stamp
        ws["A10"] = "Item"; ws["B10"] = (code or {}).get(sheet, cd)
        for j, c in enumerate(CODES):
            ws.cell(row=8, column=2 + j, value=c)
            ws.cell(row=11, column=2 + j, value=(unit or {}).get((sheet, c), "Local thou"))
            ws.cell(row=12, column=2 + j, value=b12)
        for r, d in enumerate(dates):
            ws.cell(row=15 + r, column=1, value=d)
            for j, c in enumerate(CODES):
                per = LABEL[FM[c]][d]
                v = val(item, j, per) / ((scale or {}).get(item, 1000.0 if kind == "amount" else 1.0))
                v = (over or {}).get((sheet, c, d), v)
                if v is not None:
                    ws.cell(row=15 + r, column=2 + j, value=v)
    wb.save(path)


SCHEMA = pa.schema([("Ticker", pa.string()), ("Period", pa.string()), ("Item", pa.string()), ("Value", pa.float64()), ("Text", pa.string()),
                    ("first_fetched_at", pa.string()), ("last_fetched_at", pa.string())])


def setup(name, fm=None, parents=("FundV2_META", "FundV2_INFO")):
    root = T / name
    (root / "03_Universe/Fundamental_v2").mkdir(parents=True)
    (root / "02_Infrastructure/data").mkdir(parents=True)
    (root / ".cache/qw_fund_v2").mkdir(parents=True)
    books = {}
    for f, sheet, item, cd, kind, parent in SHEETS:
        books.setdefault(f, []).append({"sheet": sheet, "item": item, "code": cd, "kind": kind, "parent": parent})
    reg = {"fundamentals_v2": {"dir": "03_Universe/Fundamental_v2", "ts_supplements": [
        {"name": NAME, "periods": WINDOW, "books": [{"file": f, "sheets": s} for f, s in books.items()]}]}}
    (root / "02_Infrastructure/data/qw_updatefile_registry.json").write_text(json.dumps(reg, ensure_ascii=False), encoding="utf-8")
    fmap = FM if fm is None else fm
    pq.write_table(pa.table({"Ticker": list(fmap), "FiscalMonth": [str(v) for v in fmap.values()], "fetched_at": ["x"] * len(fmap)}), root / ".cache/qw_fund_v2/fiscal_month.parquet")
    for parent in parents:
        rows = [(c, p, item, val(item, j, p), None, "2026-11-08T17:03:40", "2026-11-08T17:03:40")
                for (_, _, item, _, _, par) in SHEETS if par == parent for j, c in enumerate(CODES) for p in PEER_PER]
        rows += [(c, "201206", "Other", 1.0, None, "2026-11-08T17:03:40", "2026-11-08T17:03:40") for c in CODES[:5]]    # 다른 항목(무접촉 확인용)
        pq.write_table(pa.Table.from_pylist([dict(zip(SCHEMA.names, r)) for r in rows], schema=SCHEMA), root / f".cache/qw_fund_v2/{parent}.parquet")
    d = root / "03_Universe/Fundamental_v2"
    return root, d


def books(d, **kw):
    for f in ("a.xlsx", "b.xlsx"):
        make_book(d / f, [s for s in SHEETS if s[0] == f], **kw)


def run(root, *extra, mod=None):
    sys.argv = ["qw_fund_v2_div_supplement.py", "--root", str(root), *extra]
    return (mod or M).main()


def table(root, parent="FundV2_META"):
    return pq.read_table(root / f".cache/qw_fund_v2/{parent}.parquet").to_pandas()


def one(df, c, p, item):
    r = df[(df.Ticker == c) & (df.Period == p) & (df.Item == item)]
    return None if r.empty else r.iloc[0]


def mutant(name, old, new):
    """소스 글자를 바꾼 사본을 임시 폴더에 두고 읽는다 — 형제 모듈(세금 적재기 · 피어 적재기)을 같은 폴더에서 찾으므로 함께 복사한다(운영 폴더 무접촉)."""
    src = SUT.read_text(encoding="utf-8")
    assert src.count(old) == 1, f"돌연변이 치환 대상이 {src.count(old)}번 나온다: {old[:50]}"
    d = T / f"_mut_{name}"; d.mkdir()
    for sib in ("qw_fund_v2_tax_ingest.py", "qw_fund_v2_ingest.py"):
        shutil.copy(SUT.with_name(sib), d / sib)
    (d / SUT.name).write_text(src.replace(old, new), encoding="utf-8")
    return load(d / SUT.name, f"mut_{name}")


try:
    # S1 첫 보충
    r, d = setup("s1"); books(d)
    rc = run(r); meta, info = table(r), table(r, "FundV2_INFO")
    n_meta = len(meta[meta.Period.isin(WINDOW)]); n_info = len(info[info.Period.isin(WINDOW)])
    a = one(meta, CODES[3], "201209", "CashDivTotal"); b = one(meta, CODES[3], "201303", "AdjDPS")
    f11 = one(meta, CODES[7], "201209", "CashDivTotal"); f10 = one(info, CODES[8], "201312", "AdjDPSFinal")
    out = one(meta, CODES[3], "201206", "CashDivTotal"); oth = one(meta, CODES[2], "201206", "Other")
    good = rc == 0 and n_meta == 60 * 6 * 3 and n_info == 60 * 6 and a is not None and a.Value == val("CashDivTotal", 3, "201209") and b.Value == val("AdjDPS", 3, "201303") \
        and f11.Value == val("CashDivTotal", 7, "201209") and f10.Value == val("AdjDPSFinal", 8, "201312") and a.first_fetched_at == "2026-11-23T20:41:23" \
        and out.first_fetched_at == "2026-11-08T17:03:40" and out.last_fetched_at == "2026-11-08T17:03:40" and oth is not None and len(meta) == 60 * 4 * 3 + 5 + 60 * 6 * 3
    ok("S1 첫 보충 — 창 6분기 × 60종목 × 항목(부모 둘) · 금액 × 1000 · 주당 그대로 · 결산월 11 · 10 종목은 한 분기 뒤 표지 · 창 밖 행 무접촉") if good else ng(
        f"S1 rc={rc} meta={n_meta} info={n_info} a={None if a is None else a.Value} f11={None if f11 is None else f11.Value}")
    rep = json.loads((r / ".cache/qw_fund_v2/FundV2_DIV_supplement_report.json").read_text(encoding="utf-8"))
    ok("S1b 보고 — 신규만(변경 0 · 삭제 0) · 겹침 대조 전부 일치") if rep["counts"]["FundV2_META"]["new"] == 1080 and rep["counts"]["FundV2_META"]["changed"] == 0 \
        and rep["counts"]["FundV2_META"]["deleted"] == 0 and all(v["share"] == 1.0 for v in rep["overlap_control"].values()) else ng(f"S1b {rep['counts']}")
    # S2 다시
    rc = run(r); meta2 = table(r)
    a2 = one(meta2, CODES[3], "201209", "CashDivTotal")
    ok("S2 다시 돌려도 변경 없음 — 행 수 같음 · first_fetched_at 유지") if rc == 0 and len(meta2) == len(meta) and a2.first_fetched_at == "2026-11-23T20:41:23" else ng(f"S2 rc={rc} {len(meta2)}")
    # S3 dry-run
    r, d = setup("s3"); books(d)
    rc = run(r, "--dry-run")
    ok("S3 dry-run — 부모 표 그대로 · 보고 파일 없음") if rc == 0 and not len(table(r)[table(r).Period.isin(WINDOW)]) and not (r / ".cache/qw_fund_v2/FundV2_DIV_supplement_report.json").exists() else ng(f"S3 rc={rc}")

    def refused(tag, what, **kw):
        r_, d_ = setup(tag); books(d_, **kw.pop("book", {}))
        if "post" in kw:
            kw["post"](r_, d_)
        rc_ = run(r_, *kw.get("args", ()))
        n_ = len(table(r_)[table(r_).Period.isin(WINDOW)]) if (r_ / ".cache/qw_fund_v2/FundV2_META.parquet").exists() else 0
        ok(f"{tag.upper()} {what} → 3 · 쓰기 없음") if rc_ == 3 and n_ == 0 else ng(f"{tag.upper()} rc={rc_} 창 행 {n_}")

    refused("g1", "B10 코드 다름", book={"code": {"B201700_M": "M441700.M"}})
    refused("g2", "Base Date FY0", book={"b12": "FY0"})
    refused("g3", "금액 항목의 모르는 단위", book={"unit": {("B201700_M", CODES[4]): "Local mn"}})
    refused("g4", "단위가 틀린 책(금액이 원 단위로 옴) — 겹침 대조", book={"scale": {"CashDivTotal": 1.0, "CashDivCommon": 1.0}})
    refused("g5", "날짜 행이 창을 덮지 못함(2013-09 에서 끝)", book={"dates": DATES[:6]})
    refused("g7", "창 안 채움 부족(한 기간 값 40개)", book={"over": {("B201700_M", c, "2013-03"): None for c in CODES[40:]}})
    refused("g8", "부모 표 없음", post=lambda r_, d_: (r_ / ".cache/qw_fund_v2/FundV2_INFO.parquet").unlink())
    refused("g9", "등록부에 이름 없음", args=("--name", "NoSuch"))
    # G6 결산월 없는 종목
    fm6 = {c: v for c, v in FM.items() if c != CODES[9]}
    r, d = setup("g6", fm=fm6); books(d)
    rc = run(r)
    ok("G6 결산월 없는 종목에 0 아닌 값 → 3") if rc == 3 and not len(table(r)[table(r).Period.isin(WINDOW)]) else ng(f"G6 rc={rc}")
    r, d = setup("g6b", fm=fm6)
    books(d, over={(s[1], CODES[9], dd): 0.0 for s in SHEETS for dd in DATES})
    rc = run(r); meta = table(r)
    ok("G6b 결산월 없는 종목이 0 뿐 → 그 종목만 빼고 통과(59종목)") if rc == 0 and len(meta[(meta.Period == "201209") & (meta.Item == "CashDivTotal")]) == 59 else ng(f"G6b rc={rc}")
    # G10 한 기간에 두 행 값이 다름 — 10월 결산 종목의 두 날짜 행이 한 기간으로 떨어지게 손 표를 겹친다(시험 쪽 생성기는 그대로 · 책의 날짜 한 줄을 달 중간으로)
    r, d = setup("g10")
    dates10 = DATES[:-1] + ["2014-04"]          # 2014-03 행과 2014-04 행: 12월 결산이면 둘 다 201312 … 값은 서로 다르게 넣는다
    LABEL[12]["2014-04"] = "201403"; LABEL[11]["2014-04"] = "201406"
    try:
        books(d, dates=dates10)
        rc = run(r)
    finally:
        LABEL[12].pop("2014-04"); LABEL[11].pop("2014-04")
    ok("G10 한 기간에 두 날짜 행의 값이 다름 → 3") if rc == 3 and not len(table(r)[table(r).Period.isin(WINDOW)]) else ng(f"G10 rc={rc}")

    # 돌연변이
    m1 = mutant("m1", "OVERLAP_MIN = {'amount': 0.98, 'per_share': 0.95}", "OVERLAP_MIN = {'amount': 0.0, 'per_share': 0.0}")
    m1.OVERLAP_MIN_N = 0
    r, d = setup("m1"); books(d, scale={"CashDivTotal": 1.0, "CashDivCommon": 1.0})
    rc = run(r, mod=m1)
    ok("M1 돌연변이(겹침 대조 끔) → 단위가 틀린 책이 통과(rc 0) — G4 는 겹침 대조의 발화다") if rc == 0 else ng(f"M1 rc={rc}")
    m2 = mutant("m2", "lab = {k: tax.period_from_row_date(*k) for k in set(key)}", "lab = {k: tax.period_from_row_date(k[0], 12) for k in set(key)}")
    r, d = setup("m2"); books(d)
    rc = run(r, mod=m2)
    ok("M2 돌연변이(결산월 무시 · 12 고정) → 겹침 대조가 잡는다(3)") if rc == 3 else ng(f"M2 rc={rc}")
    m3 = mutant("m3", "if fill.get((i, p), 0) < core.FILL_MIN]", "if fill.get((i, p), 0) < 0]")
    r, d = setup("m3"); books(d, over={("B201700_M", c, "2013-03"): None for c in CODES[40:]})
    rc = run(r, mod=m3)
    ok("M3 돌연변이(채움 하한 0) → G7 모양이 통과(rc 0) — G7 은 채움 관문의 발화다") if rc == 0 else ng(f"M3 rc={rc}")
except Exception as e:  # noqa: BLE001
    import traceback; traceback.print_exc()
    ng(f"harness error: {e!r}")
finally:
    shutil.rmtree(T, ignore_errors=True)

print(f"\n합계: 통과 {PASS} · 실패 {FAIL}")
print(json.dumps({"test": "qw_fund_v2_div_supplement", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(1 if FAIL else 0)
