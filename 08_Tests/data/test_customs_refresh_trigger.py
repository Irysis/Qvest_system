"""test_customs_refresh_trigger.py — 관세청(FQ-073) 스냅샷 시점 refresh_customs() 오프라인 시험 (2026-11-24 신설)

왜: 신선도 경보 customs_hs_monthly lag 55 > 45(11-15~). 원인 = 받는 시점 규칙. 종전 규칙은 '달마다 첫 실행에 1회'인데
  관세청은 전월 자료를 매월 15일경에 싣는다(PIT_plan_fq073 §1-b · c) → 스냅샷이 늘 한 달 늦었다
  (실측 07-26 · 08-01 · 09-01 · 10-03 · 11-06 = 최신 달 06 · 06 · 07 · 08 · 09 · 경보 08-15 · 09-15 · 10-16 · 11-15).
  수리 = API 에 마지막 스냅샷보다 늦은 달이 실렸을 때 받는다(그 스냅샷에 가장 많이 실린 HS 장 하나로 탐침 · 탐침 실패 = 종전 규칙).
네트워크를 쓰지 않는다 — _cust_fetch · _key · time.sleep 을 가짜로 바꾸고 임시 루트(QM_ROOT)에서 잰다(운영 파일 쓰기 0).
축: C1 새 달 실림 → 받는다(이번 달 스냅샷이 있어도) · C2 새 달 없음 → 쉰다(탐침 2회뿐) · C3 탐침 실패 + 이번 달 스냅샷 있음 → 쉰다 ·
    C4 탐침 실패 + 이번 달 스냅샷 없음 → 받는다 · C5 같은 날 스냅샷 → 조회 0 · C6 스냅샷 없음 → 탐침 없이 받는다 ·
    C7 탐침 응답에 행 없음(오류 XML) = 탐침 실패 · B1 기존 스냅샷 바이트 동일(append-only) ·
    M1 종전 규칙(이번 달 스냅샷이면 쉼) → C1 이 쉰다(검출) · M2 비교 없음(늘 받음) → C2 가 받는다(검출) · 치환 성사 단정.
실행: .venv_qvest_ml/Scripts/python.exe -X utf8 08_Tests/data/test_customs_refresh_trigger.py
"""
import datetime as dt
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
import types
from pathlib import Path

# ── 해석기 자기해결 — 시스템 파이썬(QVEST_PY)에는 pandas · pyarrow 가 없다 → venv 로 다시 실행(SKIP 하지 않는다)
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

ROOT = Path(__file__).resolve().parents[2]
SUT = ROOT / "02_Infrastructure" / "data" / "refresh_nonreturn_sources.py"
PASS = FAIL = 0


def chk(name, cond, note=""):
    global PASS, FAIL
    if cond:
        PASS += 1; print(f"  PASS  {name}")
    else:
        FAIL += 1; print(f"  ★FAIL {name}  {note}")


def months(a, b):
    """'YYYY-MM' a..b (포함)."""
    y, m = int(a[:4]), int(a[5:])
    out = []
    while f"{y:04d}-{m:02d}" <= b:
        out.append(f"{y:04d}-{m:02d}")
        m += 1
        if m == 13:
            y, m = y + 1, 1
    return out


def xml_items(rows):
    it = "".join(f"<item><hsCode>{h}</hsCode><statKor>s</statKor><year>{ym.replace('-', '.')}</year><expDlr>{v}</expDlr>"
                 f"<impDlr>1</impDlr><expWgt>1</expWgt><impWgt>1</impWgt></item>" for h, ym, v in rows)
    tot = "<item><hsCode>-</hsCode><statKor>총계</statKor><year>총계</year><expDlr>9</expDlr><impDlr>9</impDlr><expWgt>9</expWgt><impWgt>9</impWgt></item>"
    return f"<response><header><resultCode>00</resultCode></header><body><items>{it}{tot}</items></body></response>"


def build_root(td, snaps):
    """snaps = {tag: 최신 달} — 각 스냅샷: 85 장 품목 3개 + 01 장 품목 1개 · 2025-01 ~ 최신 달(85 장이 가장 많다)."""
    fq = Path(td) / "stage_artifacts/method_frontier/firm_level_scaffold/fq073"
    (fq / "vintage_store").mkdir(parents=True)
    last = None
    for tag, mx in sorted(snaps.items()):
        rows = [(h, ym) for h in ("8542311000", "8542321000", "8517130000", "0101210000") for ym in months("2025-01", mx)]
        df = pd.DataFrame({"hs": [h for h, _ in rows], "stat_kor": "s", "ym": [ym for _, ym in rows], "exp_usd": 1.0, "imp_usd": 1.0,
                           "exp_wgt": 1.0, "imp_wgt": 1.0, "pull_date": tag, "vintage_basis": "revised_asof_pull"})
        df.to_parquet(fq / "vintage_store" / f"customs_hs_{tag}.parquet", index=False)
        last = df
    if last is not None:
        last.to_parquet(fq / "customs_hs_monthly.parquet", index=False)
    return fq


def load(td, api_max, src_text=None, fail_first=0, probe_bad_xml=False):
    os.environ["QM_ROOT"] = td
    if src_text is None:
        spec = importlib.util.spec_from_file_location("rns_cust_test", SUT)
        M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
    else:
        M = types.ModuleType("rns_cust_mut"); M.__file__ = str(SUT)
        exec(compile(src_text, str(SUT), "exec"), M.__dict__)
    calls = []

    def _fetch(K, hs, y, end_ym):
        calls.append((hs, y, end_ym))
        if len(calls) <= fail_first:
            raise TimeoutError("fake timeout")
        if probe_bad_xml and len(calls) <= 2:
            return "<OpenAPI_ServiceResponse><cmmMsgHeader><errMsg>SERVICE ERROR</errMsg></cmmMsgHeader></OpenAPI_ServiceResponse>"
        hi = min(f"{end_ym[:4]}-{end_ym[4:]}", api_max)
        yms = [m for m in months(f"{y}-01", f"{y}-12") if m <= hi]
        return xml_items([(f"{hs}00000000", ym, 7) for ym in yms])

    M._cust_fetch = _fetch
    M._key = lambda: "TESTKEY"
    M.time = types.SimpleNamespace(sleep=lambda s: None)
    return M, calls


def run(snaps, today, api_max, src_text=None, fail_first=0, probe_bad_xml=False):
    with tempfile.TemporaryDirectory() as td:
        td = td.replace("\\", "/")
        fq = build_root(td, snaps)
        vs = fq / "vintage_store"
        before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in vs.glob("*.parquet")}
        M, calls = load(td, api_max, src_text, fail_first, probe_bad_xml)
        f = {"err": None, "r": None}
        try:
            f["r"] = M.refresh_customs(today=today)
        except Exception as ex:  # noqa: BLE001
            f["err"] = ex
        after = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in vs.glob("*.parquet")}
        new = sorted(set(after) - set(before))
        f.update(calls=list(calls), new=new, kept=all(after.get(k) == v for k, v in before.items()))
        f["new_max"] = str(pd.read_parquet(vs / new[0], columns=["ym"]).ym.max()) if new else None
        lp = fq / "customs_hs_monthly.parquet"
        f["latest_max"] = str(pd.read_parquet(lp, columns=["ym"]).ym.max()) if lp.exists() else None
    os.environ.pop("QM_ROOT", None)
    return f


def main():
    src = SUT.read_text(encoding="utf-8")
    full = 97 * 3
    D = dt.date
    print("── C1 새 달 실림 — 11-06 스냅샷(최신 09) 뒤 11-24 · API 최신 10")
    f = run({"20261106": "2026-09"}, D(2026, 11, 24), "2026-10")
    chk("C1a 받는다(이번 달 스냅샷이 있어도) — 새 스냅샷 customs_hs_20261124 · 최신 달 10", f["err"] is None and f["r"].get("action") == "snapshot"
        and f["new"] == ["customs_hs_20261124.parquet"] and f["new_max"] == "2026-10", f"{f['err']!r} {f['r']} {f['new']} {f['new_max']}")
    chk("C1b 탐침 = 마지막 스냅샷에 가장 많이 실린 장(85) · 전년과 올해 2회 → 그 뒤 전체 97장 × 3년",
        f["calls"][:2] == [("85", 2025, "202512"), ("85", 2026, "202611")] and len(f["calls"]) == 2 + full, f"{f['calls'][:3]} n={len(f['calls'])}")
    chk("C1c 파생 최신판(customs_hs_monthly) 최신 달 10", f["latest_max"] == "2026-10", str(f["latest_max"]))
    chk("B1 기존 스냅샷 바이트 동일(append-only)", f["kept"])
    print("── C2 새 달 없음 — API 최신 09")
    f = run({"20261106": "2026-09"}, D(2026, 11, 24), "2026-09")
    chk("C2 쉰다(no_new_month) — 새 파일 0 · 조회 = 탐침 2회뿐", f["err"] is None and f["r"].get("action") == "noop" and f["r"].get("why") == "no_new_month"
        and not f["new"] and len(f["calls"]) == 2 and f["r"].get("api_latest_ym") == "2026-09", f"{f['err']!r} {f['r']} n={len(f['calls'])}")
    print("── C3 탐침 실패 + 이번 달 스냅샷 있음")
    f = run({"20261106": "2026-09"}, D(2026, 11, 24), "2026-10", fail_first=1)
    chk("C3 종전 규칙으로 쉰다(probe_failed_same_month) — 새 파일 0", f["err"] is None and f["r"].get("why") == "probe_failed_same_month"
        and not f["new"], f"{f['err']!r} {f['r']}")
    print("── C4 탐침 실패 + 이번 달 스냅샷 없음(12-02 · 마지막 = 11-06)")
    f = run({"20261106": "2026-09"}, D(2026, 12, 2), "2026-10", fail_first=1)
    chk("C4 종전 규칙대로 받는다 — 새 스냅샷 20261202 · 최신 달 10", f["err"] is None and f["r"].get("action") == "snapshot"
        and f["new"] == ["customs_hs_20261202.parquet"] and f["new_max"] == "2026-10", f"{f['err']!r} {f['r']} {f['new']}")
    print("── C5 같은 날 스냅샷 있음")
    f = run({"20261124": "2026-10"}, D(2026, 11, 24), "2026-11")
    chk("C5 쉰다(same_day) — 조회 0", f["err"] is None and f["r"].get("why") == "same_day" and not f["calls"] and not f["new"], f"{f['err']!r} {f['r']} n={len(f['calls'])}")
    print("── C6 스냅샷 없음")
    f = run({}, D(2026, 11, 24), "2026-10")
    chk("C6 탐침 없이 받는다 — 조회 = 전체 97장 × 3년", f["err"] is None and f["r"].get("action") == "snapshot" and len(f["calls"]) == full
        and f["new_max"] == "2026-10", f"{f['err']!r} {f['r']} n={len(f['calls'])}")
    print("── C7 탐침 응답에 행 없음(오류 XML) + 이번 달 스냅샷 있음")
    f = run({"20261106": "2026-09"}, D(2026, 11, 24), "2026-10", probe_bad_xml=True)
    chk("C7 행 없는 응답 = 탐침 실패 → 종전 규칙으로 쉰다", f["err"] is None and f["r"].get("why") == "probe_failed_same_month" and not f["new"],
        f"{f['err']!r} {f['r']}")
    # ── 돌연변이 — 고친 곳을 되돌리면 해당 축이 걸린다(치환 성사 단정)
    OLD_RULE = ("    if os.path.exists(snap_path):\n",
                "    if [f for f in existing if f[len(\"customs_hs_\"):len(\"customs_hs_\") + 6] == today.strftime(\"%Y%m\")]:\n"
                "        return {\"source\": \"customs\", \"action\": \"noop\", \"snapshots\": len(existing)}\n"
                "    if os.path.exists(snap_path):\n")
    NO_CMP = ("        elif api_ym <= last_ym:\n", "        elif False:\n")
    print("── 돌연변이")
    for name, (a_, b_), args, caught in [
        ("M1 종전 규칙(이번 달 스냅샷이면 쉼) → C1 이 쉰다(검출)", OLD_RULE, ({"20261106": "2026-09"}, D(2026, 11, 24), "2026-10"),
         lambda f: f["err"] is None and f["r"].get("action") == "noop" and not f["new"]),
        ("M2 비교 없음(늘 받음) → C2 가 받는다(검출)", NO_CMP, ({"20261106": "2026-09"}, D(2026, 11, 24), "2026-09"),
         lambda f: f["err"] is None and f["r"].get("action") == "snapshot" and f["new"]),
    ]:
        if src.count(a_) != 1:
            chk(f"{name} — 치환 성사", False, f"대상 수 {src.count(a_)} ≠ 1: {a_[:48]!r}"); continue
        f = run(*args, src_text=src.replace(a_, b_))
        chk(name, caught(f), f"err={f['err']!r} r={f['r']} new={f['new']}")
    print(f"\n[test_customs_refresh_trigger] {PASS} passed, {FAIL} failed")
    print(json.dumps({"test": "customs_refresh_trigger", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
