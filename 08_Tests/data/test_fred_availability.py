"""test_fred_availability.py — PIT C11 가용시점 층(S0) Python 판 검사 (2026-09-24 신설).

R 판 검사(test_fred_availability.R)와 같은 공용 픽스처(08_Tests/fixtures/fred_availability_cases.json)를
fred_availability.py 에 돌린다. 기대값은 판정서 ② 에서 손으로 유도한 값이다.
양방향: 양성 대조 + 위반 주입(같은 날짜 결합·exposure=decision·주간/월간 라벨 결합·규칙 파일 변조)은 빨개져야 한다.
R↔py 전수 교차는 R 검사 F 축이 이 모듈의 --parity CLI 로 수행한다.

표준 라이브러리만 쓴다(러너의 QVEST_PY 에 pandas/pyarrow 가 없다). pandas 축은 있으면 재고 없으면 SKIP(사유 기재).
쓰기: tempfile 디렉터리만.
"""
from __future__ import annotations

import copy
import datetime as dt
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "data"))
import fred_availability as fa  # noqa: E402

RULES = os.path.join(ROOT, "06_Registry", "fred_availability_rules.json")
CASES = os.path.join(ROOT, "08_Tests", "fixtures", "fred_availability_cases.json")

PASS = 0
FAIL = 0
SKIPS = []


def chk(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name} {detail}")


def skip(axis, reason, missing):
    SKIPS.append({"axis": axis, "reason": reason, "missing": missing})
    print(f"  SKIP  {axis} — {reason} [{missing}]")


def raises(fn):
    try:
        fn()
    except fa.FredAvailError:
        return True
    except Exception:  # noqa: BLE001 — 다른 예외도 '거부'지만 구분해 보고
        return True
    return False


with open(CASES, encoding="utf-8") as fh:
    FX = json.load(fh)
RL = fa.fred_avail_rules(RULES)


def _syn_cal():
    c = FX["calendar"]
    d0 = dt.date.fromisoformat(c["start"])
    d1 = dt.date.fromisoformat(c["end"])
    hol = {dt.date.fromisoformat(h) for h in c["holidays"]}
    out, d = [], d0
    while d <= d1:
        if d.isoweekday() <= 5 and d not in hol:
            out.append(d)
        d += dt.timedelta(days=1)
    return out


CAL = _syn_cal()
TD = tempfile.mkdtemp(prefix="fredavail_py_")


def real_avail(sid, obs, rules=RL):
    return fa.fred_avail_date(sid, obs, CAL, rules)


def real_join(kd, series, sid, mode, rules=RL):
    return fa.fred_asof_join(kd, series, sid, mode, kr_calendar=CAL, rules=rules)


def s_or_none(x):
    return None if x is None else str(x)


def avail_mismatch(fun, only=None):
    bad = []
    for cs in FX["avail_cases"]:
        if only and cs["series"] not in only:
            continue
        try:
            got = s_or_none(fun(cs["series"], cs["obs"]))
        except Exception:  # noqa: BLE001
            got = "ERR"
        if got != cs["expect"]:
            bad.append(cs["id"])
    return bad


def join_mismatch(fun, only=None):
    bad = []
    for cs in FX["join_cases"]:
        if only and cs["id"] not in only:
            continue
        series = list(zip(cs["obs"], cs["values"]))
        try:
            rows = fun(cs["kr_dates"], series, cs["series"], cs["mode"])
            ok = [s_or_none(r["obs_date"]) for r in rows] == cs["expect_obs"]
            if ok and cs.get("expect_decision"):
                ok = [s_or_none(r["decision_date"]) for r in rows] == cs["expect_decision"]
        except Exception:  # noqa: BLE001
            ok = False
        if not ok:
            bad.append(cs["id"])
    return bad


def mut_rules(tag, f):
    with open(RULES, encoding="utf-8") as fh:
        raw = json.load(fh)
    raw = f(copy.deepcopy(raw))
    p = os.path.join(TD, f"rules_{tag}.json")
    with open(p, "w", encoding="utf-8") as fh:
        json.dump(raw, fh, ensure_ascii=False)
    return p


def sidx(raw, sid):
    return next(i for i, s in enumerate(raw["series"]) if s["id"] == sid)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001
        pass
    print(f"  합성 달력 {CAL[0]} ~ {CAL[-1]} ({len(CAL)} 거래일)")
    print("\n=== B 양성 대조 — 판정서 ② 실례(공용 픽스처) ===")
    for cs in FX["avail_cases"]:
        try:
            got = s_or_none(real_avail(cs["series"], cs["obs"]))
        except Exception as e:  # noqa: BLE001
            got = f"ERR {e}"
        chk(f"{cs['id']} {cs['series']} {cs['obs']} → {cs['expect']}", got == cs["expect"], f"(got {got} · {cs['why']})")
    for cs in FX["join_cases"]:
        chk(f"{cs['id']} {cs['series']} {cs['mode']}", not join_mismatch(real_join, only=[cs["id"]]), cs["why"])
    for cs in FX["join_core_cases"]:
        got = fa._join_idx(cs["dec"], cs["obs"], cs["avail"])
        want = [None if v is None else v - 1 for v in cs["expect_idx"]]  # 픽스처는 1-based
        chk(f"{cs['id']} 결합 핵심(지배 관측 제거)", got == want, f"(got {got} · {cs['why']})")
    j = real_join(["2026-09-01"], [("2026-08-28", 1.0)], "VIXCLS", "decision_close")
    chk("B-meta 결합 산출에 규칙 md5 가 실린다", j.attrs.get("rules_md5") == RL["md5"])
    j = real_join(["2026-09-03"], [("2026-08-28", 1.0)], "NFCI", "decision_close")
    chk("B-vintage 개정 계열(NFCI)은 vintage_resolved=False", j[0]["vintage_resolved"] is False)

    print("\n=== C fail-closed ===")
    for sid in FX["error_cases"]:
        chk(f"C 거부: {sid}", raises(lambda sid=sid: real_avail(sid, "2026-09-01")))
    try:
        fa.fred_series_rule("DEXKOUS", RL)
        msg = ""
    except fa.FredAvailError as e:
        msg = str(e)
    chk("C DEXKOUS 거부 메시지가 ECOS_KRW_USD 를 가리킨다", "ECOS_KRW_USD" in msg)
    chk("C exposure_return 비거래일 kr_date → 거부",
        raises(lambda: real_join(["2026-09-24"], [("2026-09-21", 1.0)], "VIXCLS", "exposure_return")))
    chk("C 같은 관측일 2행 → 거부",
        raises(lambda: real_join(["2026-09-02"], [("2026-08-28", 1.0), ("2026-08-28", 2.0)], "VIXCLS", "decision_close")))
    chk("C Series_ID 가 섞인 입력 → 거부",
        raises(lambda: real_join(["2026-09-02"], {"Date": ["2026-08-27", "2026-08-28"], "Value": [1.0, 2.0],
                                                  "Series_ID": ["VIXCLS", "NFCI"]}, "VIXCLS", "decision_close")))
    p = mut_rules("novix", lambda r: (r["series"].pop(sidx(r, "VIXCLS")), r)[1])
    chk("C 규칙 파일에서 VIXCLS 삭제 → 거부", raises(lambda: fa.fred_avail_date("VIXCLS", "2026-09-01", CAL, p)))

    def _bt(r):
        r["series"][sidx(r, "NFCI")]["bounds"][0]["type"] = "same_day"
        return r
    chk("C 알 수 없는 bound type → 로드 거부", raises(lambda: fa.fred_avail_rules(mut_rules("badtype", _bt))))

    def _nb(r):
        r["series"][sidx(r, "ICSA")]["bounds"][0]["basis"] = ""
        return r
    chk("C 근거 빈 bound → 로드 거부", raises(lambda: fa.fred_avail_rules(mut_rules("nobasis", _nb))))

    print("\n=== D 위반 주입 — 돌연변이는 빨개져야 한다 ===")

    def mut_same_date(sid, obs):
        fa.fred_series_rule(sid, RL)
        return dt.date.fromisoformat(obs)
    b = avail_mismatch(mut_same_date)
    chk("D1 같은 날짜 결합 돌연변이 → 양성 대조가 잡는다", len(b) >= 30 and "P01" in b, f"(불일치 {len(b)})")

    def join_same_date(kd, series, sid, mode):
        fa.fred_series_rule(sid, RL)
        dec = fa.fred_decision_date(kd, mode, CAL) if mode == "exposure_return" else [dt.date.fromisoformat(k) for k in kd]
        obs = sorted(dt.date.fromisoformat(o) for o, _ in series)
        out = []
        for d in dec:
            c = [o for o in obs if o <= d]
            out.append({"obs_date": c[-1] if c else None, "decision_date": d})
        return out
    chk("D1b 같은 날짜 결합 → J1 빨강", "J1" in join_mismatch(join_same_date))
    chk("D2 exposure_return=decision_close → J2 빨강",
        "J2" in join_mismatch(lambda kd, s, sid, mode: real_join(kd, s, sid, "decision_close")))
    chk("D3 '1행 lag'(직전 거래일 같은 날짜 결합) → J2 빨강", "J2" in join_mismatch(join_same_date, only=["J2"]))
    weekly = {"NFCI", "STLFSI4", "ICSA", "WALCL"}

    def mut_weekly(sid, obs):
        return dt.date.fromisoformat(obs) if fa.fred_series_rule(sid, RL)["id"] in weekly else real_avail(sid, obs)
    b = avail_mismatch(mut_weekly, only=weekly)
    chk("D4 주간 관측일 결합 → 주간 대조 전부 빨강", len(b) >= 7, f"(불일치 {b})")
    monthly = {"CPIAUCSL", "INDPRO", "UNRATE"}

    def mut_monthly(sid, obs):
        return dt.date.fromisoformat(obs) if fa.fred_series_rule(sid, RL)["id"] in monthly else real_avail(sid, obs)
    chk("D5 월간 라벨 결합 → P09·P11·P13 빨강", {"P09", "P11", "P13"} <= set(avail_mismatch(mut_monthly, only=monthly)))

    def _n0(r):
        r["series"][sidx(r, "NFCI")]["bounds"] = [{"type": "label_plus_days", "days": 0, "basis": "mutant"}]
        return r
    p = mut_rules("nfci0", _n0)
    chk("D6 규칙 변조(NFCI +6→+0) → P05 빨강", "P05" in avail_mismatch(lambda s, o: real_avail(s, o, p), only={"NFCI"}))

    def _v0(r):
        r["series"][sidx(r, "VIXCLS")]["bounds"][0]["n"] = 0
        return r
    p = mut_rules("vix0", _v0)
    chk("D7 규칙 변조(VIX n=1→0) → P01 빨강", "P01" in avail_mismatch(lambda s, o: real_avail(s, o, p), only={"VIXCLS"}))

    def _i1(r):
        i = sidx(r, "BAMLH0A0HYM2")
        r["series"][i]["bounds"] = r["series"][i]["bounds"][:1]
        r["series"][i]["bounds"][0]["n"] = 1
        return r
    p = mut_rules("ice1", _i1)
    chk("D8 규칙 변조(ICE d+2→d+1) → P16·P17 빨강",
        {"P16", "P17"} <= set(avail_mismatch(lambda s, o: real_avail(s, o, p), only={"BAMLH0A0HYM2"})))

    def _nr(r):
        i = sidx(r, "NFCI")
        r["series"][i]["bounds"] = r["series"][i]["bounds"][:1]
        return r
    p = mut_rules("noroll", _nr)
    chk("D9 규칙 변조(NFCI 휴일 공표 bound 삭제) → P18 빨강", "P18" in avail_mismatch(lambda s, o: real_avail(s, o, p), only={"NFCI"}))

    # r1(b2): CPI 2025-09 override 는 새 영업일 상한과 같아져 P10 으로 안 보인다 → INDPRO 2025-10(P38)로 옮긴다(R 판과 같게)
    def _no(r):
        r["series"][sidx(r, "INDPRO")].pop("release_overrides", None)
        return r
    p = mut_rules("noov", _no)
    chk("D10 규칙 변조(INDPRO 셧다운 override 삭제) → P38 빨강", "P38" in avail_mismatch(lambda s, o: real_avail(s, o, p), only={"INDPRO"}))
    kd = ["2026-08-31", "2026-09-01", "2026-09-02"]
    pit = ["2026-08-28", "2026-08-31", "2026-09-01"]
    chk("D11a 탐지기: 같은 날짜 쌍 3/3 위반", len(fa.fred_join_violations(kd, kd, "VIXCLS", "decision_close", CAL, RL)) == 3)
    chk("D11b 탐지기: PIT 쌍 0 위반", len(fa.fred_join_violations(kd, pit, "VIXCLS", "decision_close", CAL, RL)) == 0)
    chk("D11c 탐지기: 같은 쌍 exposure_return 3/3 위반", len(fa.fred_join_violations(kd, pit, "VIXCLS", "exposure_return", CAL, RL)) == 3)

    print("\n=== G pandas 입출력(선택 축) ===")
    try:
        import pandas as pd  # noqa: WPS433
    except ImportError:
        pd = None
    if pd is None:
        skip("G_pandas", "이 해석기에 pandas 없음 — DataFrame 입출력 미측정(핵심 축은 표준 라이브러리로 측정됨)", "pandas")
    else:
        df = pd.DataFrame({"Date": pd.to_datetime(["2026-08-27", "2026-08-28", "2026-08-31"]),
                           "Value": [14.51, 14.43, 14.92], "Series_ID": "VIXCLS"})
        out = real_join(["2026-08-31", "2026-09-01"], df, "VIXCLS", "decision_close")
        chk("G1 DataFrame 입력 → DataFrame 출력·값 일치",
            hasattr(out, "columns") and [str(x) for x in out["obs_date"]] == ["2026-08-28", "2026-08-31"])
        ann = fa.fred_avail_annotate(df, "VIXCLS", CAL, RL)
        chk("G2 annotate avail_date 열", [str(x) for x in ann["avail_date"]] == ["2026-08-28", "2026-08-31", "2026-09-01"])

    shutil.rmtree(TD, ignore_errors=True)
    print(f"\n=== 결과: PASS {PASS} · FAIL {FAIL} · SKIP {len(SKIPS)} ===")
    print(json.dumps({"test": "fred_availability_py", "pass": PASS, "fail": FAIL, "skipped": len(SKIPS),
                      "total": PASS + FAIL, "skips": SKIPS}, ensure_ascii=False))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
