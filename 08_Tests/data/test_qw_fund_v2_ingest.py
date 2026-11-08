"""test_qw_fund_v2_ingest.py — 02_Infrastructure/data/qw_fund_v2_ingest.py 합성 DB 시험(운영 03_Universe · .cache 무접촉).

사례: T1 첫 적재 · T2 변경 없음 → 2 · T3 G1(템플릿 스탬프 시트) → 3 · T4 G2(D9 ≠ 등록부) → 3 ·
      T5 G3(한 기간 채움 60 → 10) → 3 · T6 값 변경 → revisions 'changed' + first_fetched_at 재설정(안 바뀐 행은 유지) ·
      T7 창 안 삭제 → revisions 'deleted' · T8 날짜 항목 → Text 'YYYYMMDD' ·
      TM 뮤테이션(FILL_RATIO 0) → T5 모양이 통과(rc 0) = T5 는 G3 의 발화다(검출력).
실행: .venv_qvest_ml/Scripts/python.exe -X utf8 08_Tests/data/test_qw_fund_v2_ingest.py
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(os.environ.get("QM_ROOT") or Path(__file__).resolve().parents[2])
SUT = ROOT / "02_Infrastructure/data/qw_fund_v2_ingest.py"
spec = importlib.util.spec_from_file_location("qw_fund_v2_ingest", SUT)
M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
import openpyxl  # noqa: E402
import pyarrow.parquet as pq  # noqa: E402

PASS = FAIL = 0
def ok(m):
    global PASS; PASS += 1; print("  OK  ", m)
def ng(m):
    global FAIL; FAIL += 1; print("  FAIL", m)

T = Path(tempfile.mkdtemp(prefix="qwfund_"))
CODES = [f"A{100000 + i:06d}" for i in range(60)]
PER = ["202403", "202406", "202409"]
ITEMS = [{"sheet": "TotalAssets", "code": "M111000.M", "kind": "stock"},
         {"sheet": "ReportDate", "code": "M123955.M", "kind": "date"}]


def make_db(path, stamp="2026-11-08 12:00:00", stamps=None, d9=None, fill=None, base=1000.0, drop=None, dates=None):
    wb = openpyxl.Workbook(); wb.remove(wb.active)
    dk = wb.create_sheet("DATA_Key")
    for i, c in enumerate(CODES):
        dk.cell(row=4 + i, column=11, value=c)
    for it in ITEMS:
        s = it["sheet"]; ws = wb.create_sheet(s)
        ws["A1"] = "     Refresh     "; ws["B1"] = "Last Update : " + (stamps or {}).get(s, stamp)
        ws["A3"] = "Peer Analysis (To Select)"
        ws["B9"] = "Account"; ws["C9"] = "R100200"; ws["D9"] = (d9 or {}).get(s, it["code"])
        for j, p in enumerate(PER):
            ws.cell(row=10, column=4 + j, value=int(p))
        ws["A13"] = "Code"; ws["B13"] = "Name"; ws["C13"] = "결산월"
        for i, c in enumerate(CODES):
            r = 14 + i
            ws.cell(row=r, column=1, value=c); ws.cell(row=r, column=2, value=f"name{i}"); ws.cell(row=r, column=3, value=12)
            for j, p in enumerate(PER):
                n = (fill or {}).get((s, p), len(CODES))
                if i >= n or (drop and (s, c, p) in drop):
                    continue
                if it["kind"] == "date":
                    ws.cell(row=r, column=4 + j, value=(dates or {}).get((c, p), 20240515 + j * 100))
                else:
                    ws.cell(row=r, column=4 + j, value=base + i + j / 10)
        ws.cell(row=14 + len(CODES), column=1, value="n/a")
    wb.save(path)


def setup(name):
    root = T / name
    (root / "03_Universe/Fundamental_v2").mkdir(parents=True)
    reg = {"fundamentals_v2": {"dir": "03_Universe/Fundamental_v2", "items": ITEMS,
                               "dbs": [{"name": "Demo", "file": "Demo.xlsx", "items": [it["sheet"] for it in ITEMS]}]}}
    (root / "reg.json").write_text(json.dumps(reg, ensure_ascii=False), encoding="utf-8")
    return root, root / "03_Universe/Fundamental_v2/Demo.xlsx"


def run(root, *extra):
    sys.argv = ["qw_fund_v2_ingest.py", "--root", str(root), "--registry", str(root / "reg.json"), *extra]
    return M.main()


def read(root, f="Demo.parquet"):
    p = root / ".cache/qw_fund_v2" / f
    return pq.read_table(p).to_pylist() if p.exists() else []


def bump(path):  # 다음 적재가 '변경'으로 보도록 mtime 을 확실히 옮긴다
    t = time.time() + 5; os.utime(path, (t, t))


try:
    # T1 / T2 / T8
    r, b = setup("t1"); make_db(b)
    rc = run(r); rows = read(r)
    ta = [x for x in rows if x["Item"] == "TotalAssets"]; rd = [x for x in rows if x["Item"] == "ReportDate"]
    if rc == 0 and len(ta) == 180 and len(rd) == 180 and all(x["first_fetched_at"] == "2026-11-08T12:00:00" for x in rows):
        ok("T1 첫 적재 — 60종 × 3기간 × 2항목 · first_fetched_at = B1 스탬프")
    else: ng(f"T1 rc={rc} ta={len(ta)} rd={len(rd)}")
    ok("T8 날짜 항목 → Text 'YYYYMMDD' · Value 없음") if rd and rd[0]["Text"] == "20240515" and rd[0]["Value"] is None else ng(f"T8 {rd[:1]}")
    rc2 = run(r)
    ok("T2 변경 없음 → 2") if rc2 == 2 else ng(f"T2 rc={rc2}")
    # T3 G1
    r, b = setup("t3"); make_db(b, stamps={"ReportDate": M.TEMPLATE_STAMP})
    rc = run(r)
    ok("T3 G1 템플릿 스탬프 시트 → 3 · 출력 0") if rc == 3 and not read(r) else ng(f"T3 rc={rc}")
    # T4 G2
    r, b = setup("t4"); make_db(b, d9={"TotalAssets": "M111100.M"})
    rc = run(r)
    ok("T4 G2 D9 ≠ 등록부 → 3") if rc == 3 and not read(r) else ng(f"T4 rc={rc}")
    # T10 G1b 빈 시트(끊긴 세션이 스탬프만 새로 찍음) → 3 · allow_empty 항목이면 통과
    r, b = setup("t10"); make_db(b, fill={("ReportDate", p): 0 for p in PER})
    rc = run(r)
    ok("T10 G1b 값 0칸 시트(새 스탬프) → 3") if rc == 3 and not read(r) else ng(f"T10 rc={rc}")
    reg10 = json.loads((r / "reg.json").read_text(encoding="utf-8"))
    for it in reg10["fundamentals_v2"]["items"]:
        if it["sheet"] == "ReportDate":
            it["allow_empty"] = True
    (r / "reg.json").write_text(json.dumps(reg10, ensure_ascii=False), encoding="utf-8")
    rc = run(r)
    ok("T10b 같은 DB · allow_empty 항목 → 통과(rc 0)") if rc == 0 else ng(f"T10b rc={rc}")
    # T5 G3 (직전 60 → 이번 10)
    r, b = setup("t5"); make_db(b); run(r)
    make_db(b, stamp="2026-11-09 12:00:00", fill={("TotalAssets", "202406"): 10}); bump(b)
    rc = run(r); rows = read(r)
    ok("T5 G3 한 기간 채움 60 → 10 → 3 · 직전 출력 그대로") if rc == 3 and len([x for x in rows if x["Item"] == "TotalAssets"]) == 180 else ng(f"T5 rc={rc}")
    # T6 / T7 값 변경 + 삭제
    r, b = setup("t6"); make_db(b); run(r)
    make_db(b, stamp="2026-11-09 12:00:00", base=1000.0, drop={("TotalAssets", CODES[5], "202403")}); bump(b)
    wb = openpyxl.load_workbook(b); wb["TotalAssets"].cell(row=14 + 3, column=4, value=9999.0); wb.save(b); bump(b)
    rc = run(r); rows = read(r); revs = read(r, "revisions.parquet")
    ch = [x for x in revs if x["kind"] == "changed"]; de = [x for x in revs if x["kind"] == "deleted"]
    row3 = [x for x in rows if x["Ticker"] == CODES[3] and x["Period"] == "202403" and x["Item"] == "TotalAssets"]
    row4 = [x for x in rows if x["Ticker"] == CODES[4] and x["Period"] == "202403" and x["Item"] == "TotalAssets"]
    if rc == 0 and len(ch) == 1 and ch[0]["old_value"] == 1003.0 and ch[0]["new_value"] == 9999.0 and row3 and row3[0]["first_fetched_at"] == "2026-11-09T12:00:00" \
            and row4 and row4[0]["first_fetched_at"] == "2026-11-08T12:00:00" and row4[0]["last_fetched_at"] == "2026-11-09T12:00:00":
        ok("T6 값 변경 → revisions 'changed'(1003 → 9999) · 그 행만 first_fetched_at 재설정 · 나머지 유지")
    else: ng(f"T6 rc={rc} ch={ch[:1]} row3={row3[:1]} row4={row4[:1]}")
    ok("T7 창 안에서 사라진 값 → revisions 'deleted' · 현재 표에서 빠짐") if len(de) == 1 and de[0]["Ticker"] == CODES[5] and \
        not [x for x in rows if x["Ticker"] == CODES[5] and x["Period"] == "202403" and x["Item"] == "TotalAssets"] else ng(f"T7 de={de[:2]}")
    # T9 갱신용 DB(target = 부모) — 최근 2기간만 교체 · 옛 기간 유지 · 첫 적재 G3 는 부모 채움으로
    r, b = setup("t9"); make_db(b); run(r)
    reg = json.loads((r / "reg.json").read_text(encoding="utf-8"))
    reg["fundamentals_v2"]["dbs"].append({"name": "Demo_upd", "file": "Demo_upd.xlsx", "target": "Demo", "items": [it["sheet"] for it in ITEMS]})
    (r / "reg.json").write_text(json.dumps(reg, ensure_ascii=False), encoding="utf-8")
    ub = b.with_name("Demo_upd.xlsx")
    keep = PER; PER = ["202406", "202409"]   # 모듈 전역 — make_db 가 호출 시점에 읽는다
    try:
        make_db(ub, stamp="2026-11-10 12:00:00", base=5000.0)
        rc = run(r, "--db", "Demo_upd"); rows = read(r)
        old_p = [x for x in rows if x["Item"] == "TotalAssets" and x["Period"] == "202403"]
        new_p = [x for x in rows if x["Item"] == "TotalAssets" and x["Period"] == "202406"]
        ok9 = rc == 0 and len(old_p) == 60 and all(x["Value"] < 5000 for x in old_p) and len(new_p) == 60 and all(x["Value"] >= 5000 for x in new_p) \
            and not (r / ".cache/qw_fund_v2/Demo_upd.parquet").exists()
        ok("T9 갱신용 DB → 부모 parquet 의 창(202406 · 202409)만 교체 · 202403 유지 · 별도 출력 없음") if ok9 else ng(f"T9 rc={rc} old={len(old_p)} new={len(new_p)}")
        make_db(ub, stamp="2026-11-11 12:00:00", base=5000.0, fill={("TotalAssets", "202409"): 10}); bump(ub)
        r2, b2 = setup("t9b"); make_db(b2); run(r2)
        (r2 / "reg.json").write_text(json.dumps(reg, ensure_ascii=False), encoding="utf-8")
        shutil.copy(ub, b2.with_name("Demo_upd.xlsx"))
        rc = run(r2, "--db", "Demo_upd")
        ok("T9b 갱신용 DB 첫 적재의 채움 급감(부모 60 → 10) → 3(G3 가 부모 채움으로 걸림)") if rc == 3 else ng(f"T9b rc={rc}")
    finally:
        PER = keep
    # TM 뮤테이션 — G3 를 끄면 T5 모양이 통과해야 한다
    ratio = M.FILL_RATIO; M.FILL_RATIO = 0.0
    try:
        r, b = setup("tm"); make_db(b); run(r)
        make_db(b, stamp="2026-11-09 12:00:00", fill={("TotalAssets", "202406"): 10}); bump(b)
        rc = run(r)
    finally:
        M.FILL_RATIO = ratio
    ok("TM 뮤테이션(FILL_RATIO 0) → T5 모양이 통과(rc 0) — T5 는 G3 의 발화다") if rc == 0 else ng(f"TM rc={rc}")
except Exception as e:  # noqa: BLE001
    import traceback; traceback.print_exc()
    ng(f"harness error: {e!r}")
finally:
    shutil.rmtree(T, ignore_errors=True)

print(f"\n합계: 통과 {PASS} · 실패 {FAIL}")
print(json.dumps({"test": "qw_fund_v2_ingest", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(1 if FAIL else 0)
