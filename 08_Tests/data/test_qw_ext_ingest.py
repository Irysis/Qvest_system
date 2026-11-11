"""test_qw_ext_ingest.py — 02_Infrastructure/data/qw_ext_ingest.py 합성 DB 시험(운영 03_Universe · .cache 무접촉).

사례: T1 첫 적재 · T2 변경 없음 → 2 · T3 G1(B6 미해석 시트) → 3 · T4 끝 미공표 자르기 · T5 가운데 결손 → 3 ·
      T6 겹침 교체 + first_fetched_at 보존 · T7 등록 안 된 xlsx → 1 · T8 G2(B10 불일치) → 3 ·
      TM 뮤테이션(문턱 0) → T5 의 가운데 결손이 통과한다 = T5 는 그 검사의 발화다(검출력).
실행: .venv_qvest_ml/Scripts/python.exe -X utf8 08_Tests/data/test_qw_ext_ingest.py
"""
import datetime as dt
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

# ── (2026-11-11) 해석기 자기해결 — 배터리(run_all_hooks.sh)는 pyarrow 없는 시스템 파이썬으로 돈다.
#   없으면 venv 로 다시 실행한다(SKIP 하지 않는다 — SKIP 은 통과와 겉보기가 같다). 패턴 = data/test_qw_fund_v2_ingest.py.
try:
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

ROOT = Path(os.environ.get("QM_ROOT") or Path(__file__).resolve().parents[2])
SUT = ROOT / "02_Infrastructure/data/qw_ext_ingest.py"
spec = importlib.util.spec_from_file_location("qw_ext_ingest", SUT)
M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
import openpyxl  # noqa: E402
import pyarrow.parquet as pq  # noqa: E402

PASS = FAIL = 0
def ok(m):
    global PASS; PASS += 1; print("  OK  ", m)
def ng(m):
    global FAIL; FAIL += 1; print("  FAIL", m)

T = Path(tempfile.mkdtemp(prefix="qwext_"))
CODES = ["A000010", "A000020", "A0001A0", "A495910"]
D0 = [dt.date(2026, 11, 2) + dt.timedelta(days=i) for i in range(5)]   # 11-02..11-06 (월~금)


def make_book(path, sheets, b6="CPD-1TD [20261106]", fills=None, b10=None, vals_base=1.0):
    wb = openpyxl.Workbook(); wb.remove(wb.active)
    for s, code in sheets:
        ws = wb.create_sheet(s)
        ws["A3"] = "Time Series (Company)"; ws["A5"] = "Period(From)"; ws["A6"] = "Period(To)"
        ws["B6"] = b6.get(s, "CPD-1TD [20261106]") if isinstance(b6, dict) else b6
        ws["A8"] = "Code"
        for j, c in enumerate(CODES): ws.cell(row=8, column=2 + j, value=c)
        ws["A10"] = "Item Code"; ws["B10"] = (b10 or {}).get(s, code)
        ws["A14"] = "D A T E"
        for j in range(len(CODES)): ws.cell(row=14, column=2 + j, value=f"name_{s}")
        for i, d in enumerate(D0):
            ws.cell(row=15 + i, column=1, value=dt.datetime(d.year, d.month, d.day))
            n = (fills or {}).get((s, i), len(CODES))
            for j in range(len(CODES)):
                if j < n: ws.cell(row=15 + i, column=2 + j, value=vals_base + i + j / 10)
    wb.save(path)


def setup(name):
    root = T / name
    (root / "03_Universe/Update_File_ext").mkdir(parents=True)
    reg = {"ext_dir": "03_Universe/Update_File_ext", "books": [{"name": "Demo", "group": "ext", "layout": "ts",
           "path": "03_Universe/Update_File_ext/Demo_update.xlsx", "sheets": [
               {"sheet": "S1", "item_code": "S102345", "item_name": "name_S1", "output": ".cache/qw_ext/demo/s1.parquet"},
               {"sheet": "S2", "item_code": "S145030", "item_name": "name_S2", "output": ".cache/qw_ext/demo/s2.parquet"}]}]}
    (root / "reg.json").write_text(json.dumps(reg, ensure_ascii=False), encoding="utf-8")
    return root, root / "03_Universe/Update_File_ext/Demo_update.xlsx"


def run(root, *extra):
    sys.argv = ["qw_ext_ingest.py", "--root", str(root), "--registry", str(root / "reg.json"), *extra]
    return M.main()


def read(root, s):
    p = root / f".cache/qw_ext/demo/{s}.parquet"
    return pq.read_table(p).to_pylist() if p.exists() else []


SH = [("S1", "S102345"), ("S2", "S145030")]
try:
    # T1 / T2
    r, b = setup("t1"); make_book(b, SH)
    rc = run(r); rows = read(r, "s1")
    if rc == 0 and len(rows) == 20 and all(x["first_fetched_at"] for x in rows) and {x["Ticker"] for x in rows} == set(CODES):
        ok("T1 첫 적재 — 5일 × 4종 = 20행 · first_fetched_at")
    else: ng(f"T1 rc={rc} n={len(rows)}")
    rc2 = run(r)
    ok("T2 변경 없음 → 2") if rc2 == 2 else ng(f"T2 rc={rc2}")
    # T3 G1 — 한 시트만 조회되지 않음(11-08 중복 로그인 실사고 모양)
    r, b = setup("t3"); make_book(b, SH, b6={"S1": "CPD-1TD [20261106]", "S2": "CPD-1TD"})
    rc = run(r)
    ok("T3 G1 B6 미해석 시트 → 3 · 출력 0") if rc == 3 and not read(r, "s1") else ng(f"T3 rc={rc} n={len(read(r, 's1'))}")
    # T4 끝 미공표(마지막 2일 1/4 채움) → 지평선 11-04 까지만
    r, b = setup("t4"); make_book(b, SH, fills={("S1", 3): 1, ("S1", 4): 1})
    rc = run(r); d1 = sorted({x["Date"] for x in read(r, "s1")})
    ok("T4 끝 미공표 2일 잘라 냄 — 지평선 11-04") if rc == 0 and d1 and d1[-1] == dt.date(2026, 11, 4) else ng(f"T4 rc={rc} dates={d1}")
    # T5 가운데 결손(11-04 1/4) → 거부
    r, b = setup("t5"); make_book(b, SH, fills={("S1", 2): 1})
    rc = run(r)
    ok("T5 창 가운데 채움 미달 → 3") if rc == 3 and not read(r, "s1") else ng(f"T5 rc={rc}")
    # T6 겹침 교체 + first_fetched_at 보존
    r, b = setup("t6"); make_book(b, SH); run(r)
    first = {(x["Date"], x["Ticker"]): x["first_fetched_at"] for x in read(r, "s1")}
    time.sleep(1.1); make_book(b, SH, vals_base=100.0); rc = run(r); rows = read(r, "s1")
    same_first = all(first.get((x["Date"], x["Ticker"])) == x["first_fetched_at"] for x in rows)
    replaced = all(x["Value"] >= 100 for x in rows) and len(rows) == 20
    ok("T6 겹침 창 교체 · first_fetched_at 보존 · last_fetched_at 갱신") if rc == 0 and same_first and replaced and rows[0]["last_fetched_at"] != rows[0]["first_fetched_at"] else ng(f"T6 rc={rc} same_first={same_first} replaced={replaced}")
    # T7 등록 안 된 xlsx
    r, b = setup("t7"); make_book(b, SH); shutil.copy(b, b.parent / "Stray_update.xlsx")
    rc = run(r)
    ok("T7 Update_File_ext 의 등록 안 된 xlsx → 1(조용히 버리지 않는다)") if rc == 1 else ng(f"T7 rc={rc}")
    # T8 G2 B10 불일치
    r, b = setup("t8"); make_book(b, SH, b10={"S2": "S999999"})
    rc = run(r)
    ok("T8 G2 B10 ≠ 등록부 → 3") if rc == 3 and not read(r, "s1") else ng(f"T8 rc={rc}")
    # TM 뮤테이션 — 문턱 0 이면 T5 가 통과해야 한다(=T5 는 문턱 검사의 발화)
    cap = M.THR_CAP; M.THR_CAP = 0.0
    try:
        r, b = setup("tm"); make_book(b, SH, fills={("S1", 2): 1}); rc = run(r)
    finally:
        M.THR_CAP = cap
    ok("TM 뮤테이션(문턱 0) → T5 모양이 통과(rc 0) — T5 는 문턱 검사의 발화다") if rc == 0 else ng(f"TM rc={rc}")
except Exception as e:  # noqa: BLE001
    ng(f"harness error: {e!r}")
finally:
    shutil.rmtree(T, ignore_errors=True)

print(f"\n합계: 통과 {PASS} · 실패 {FAIL}")
print(json.dumps({"test": "qw_ext_ingest", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(1 if FAIL else 0)
