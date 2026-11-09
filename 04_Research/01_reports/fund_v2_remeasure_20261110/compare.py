"""compare.py — 재무 v2 재측정 3칸 vs 원 측정(10-18) 대조 · 읽기 전용(측정 없음 · 쓰기 = 이 폴더 comparison.json/.md 뿐).

수치 출처 = 각 측정 폴더의 authoritative_remeasure.json(권위 등급 · essence) · 칸 결과 results/<code>.json · A 자격 관문 산출
(judge_request.eligible.json / judge_request.held.json — run_paper_replication §11 이 측정 안에서 쓴다 · 손으로 쓰지 않는다).
데이터 판 = results/<code>.fp_start · .fp_end(fingerprint.sh equality) 같음 여부.
실행: <python> -X utf8 compare.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ORIG = {"P2R03_E3_RX0": "stage_artifacts/replication/20261018_062857_26492",
        "P2R03_E3_L2": "stage_artifacts/replication/20261018_064319_28512",
        "P2R04_E3_RX0": "stage_artifacts/replication/20261018_153141_29448"}


def jload(p):
    try:
        return json.load(open(p, encoding="utf-8"))
    except Exception:
        return None


def last_nav_date(d):
    p = os.path.join(d, "02_nav.csv")
    try:
        with open(p, encoding="utf-8") as f:
            rows = f.read().strip().splitlines()
        if len(rows) < 2:
            return None
        i = [h.strip('"') for h in rows[0].split(",")].index("date")
        return rows[1].split(",")[i].strip('"') + "~" + rows[-1].split(",")[i].strip('"')
    except Exception:
        return None


def summ(d):
    A = jload(os.path.join(d, "authoritative_remeasure.json")) if d else None
    if not A:
        return {"status": "no_record", "dir": d}
    g = A.get("grade_v3") or {}
    fa = g.get("fa") or {}
    oos = g.get("oos") or {}
    cr = g.get("cr") or {}
    ess = A.get("essence") or {}
    con = A.get("contract") or {}
    ma = A.get("measurement_axis") or {}
    out = {"dir": os.path.relpath(d, ROOT).replace("\\", "/"), "essence_grade": A.get("essence_grade"),
           "rules_version": g.get("rules_version"), "S": g.get("S"), "S_B": g.get("S_B"), "band": g.get("band"),
           "notch": g.get("notch"), "fa_notch": g.get("fa_notch"), "fa_t_min": fa.get("t_min"),
           "fa_model": fa.get("t_min_model"), "fa_why_not": fa.get("why_not"), "fa_test_all_pos": fa.get("test_all_pos"),
           "blocked_by": g.get("blocked_by"), "calmar_tw": oos.get("calmar_tw"), "bench_calmar_tw": oos.get("bench_calmar_tw"),
           "oos_gate": oos.get("gate"), "cr": cr.get("overall"), "cr_test": cr.get("test"),
           "port_t": ess.get("portfolio_alpha_t_nw_lag3") if isinstance(ess, dict) else None,
           "cagr": con.get("cagr"), "sharpe": con.get("sharpe"), "mdd": con.get("mdd"), "calmar": con.get("calmar"),
           "dsr": A.get("dsr"), "dsr_gate_applied": A.get("dsr_gate_applied"), "n_trials": A.get("n_trials_cumulative"),
           "epoch": ma.get("epoch"), "effective_start": (ma.get("effective_start") or {}).get("date") if isinstance(ma.get("effective_start"), dict) else ma.get("effective_start"),
           "nav_last": last_nav_date(d), "remeasured_at": A.get("remeasured_at")}
    for nm in ("judge_request.eligible.json", "judge_request.held.json", "judge_request.json"):
        J = jload(os.path.join(d, nm))
        if J is not None:
            ae = J.get("a_eligibility") or {}
            out.setdefault("judge_files", []).append({"file": nm, "status": J.get("status"), "grade": J.get("grade"),
                                                     "eligible": ae.get("eligible"), "codes": ae.get("codes")})
    return out


def main():
    rows = []
    for code, od in ORIG.items():
        r = jload(os.path.join(HERE, "results", code + ".json")) or {}
        nd = r.get("artifacts")
        fp = [os.path.join(HERE, "results", code + s) for s in (".fp_start", ".fp_end")]
        same = None
        if all(os.path.exists(p) for p in fp):
            same = open(fp[0], "rb").read() == open(fp[1], "rb").read()
        rows.append({"code": code, "ok": r.get("ok"), "err": r.get("err"), "fingerprint_same": same,
                     "orig": summ(os.path.join(ROOT, od)), "new": summ(nd) if nd else {"status": "not_measured"}})
    json.dump({"generated_by": "compare.py", "rows": rows}, open(os.path.join(HERE, "comparison.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    keys = ["essence_grade", "band", "S", "fa_notch", "fa_t_min", "fa_model", "blocked_by", "calmar_tw", "bench_calmar_tw",
            "cr", "cr_test", "port_t", "cagr", "sharpe", "mdd", "calmar", "dsr", "n_trials", "nav_last", "judge_files"]
    L = ["# 재무 v2 재측정 vs 원 측정(10-18)", ""]
    for x in rows:
        L.append(f"## {x['code']} — ok {x['ok']} · 데이터 지문 같음 {x['fingerprint_same']}" + (f" · err {x['err']}" if x.get("err") else ""))
        L.append("| 항목 | 원(10-18) | 재측정 |")
        L.append("|---|---|---|")
        for k in keys:
            L.append(f"| {k} | {x['orig'].get(k)} | {x['new'].get(k)} |")
        L.append(f"| dir | {x['orig'].get('dir')} | {x['new'].get('dir')} |")
        L.append("")
    open(os.path.join(HERE, "comparison.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
    print("\n".join(L))
    return 0


if __name__ == "__main__":
    sys.exit(main())
