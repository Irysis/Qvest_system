"""v33_transitions.py — 등급 v3.3 재채점(2026-11-10) 전이표 · 읽기 전용(측정 없음 · 쓰기 = 이 폴더의 transitions.json/.md 뿐).

입력: 같은 폴더 backfill_manifest.csv(grade_v3_backfill.R --write 산출) + 각 authoritative_remeasure.json(재채점 뒤)
      + 재무 v2 영향 목록(fundamentals_v2/affected_strategies_20261109.json · FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE ④)
산출: 측정 축(epoch)별 전이(직전 판 → v3.3) · 바뀐 기록 목록(원인 = 팩터 알파 노치 · OOS 관문 교체 · 기타) · A 목록 ·
      재무 결함 위 측정 여부(인용 전 v2 재측정 대상) · 같은 축 안 비교만(CLAUDE.md 측정 축 규칙).
실행: <python> -X utf8 v33_transitions.py
"""
import csv
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, *([".."] * 5)))
AFF = os.path.join(ROOT, "04_Research/01_reports/quantiwise_data_expansion_20261106/fundamentals_v2/affected_strategies_20261109.json")
CUR = "all_hyg_px1000_2000_v1"


def rel(p):
    p = p.replace("\\", "/")
    r = ROOT.replace("\\", "/") + "/"
    return p[len(r):] if p.startswith(r) else p


def main():
    man = list(csv.DictReader(open(os.path.join(HERE, "backfill_manifest.csv"), encoding="utf-8")))
    aff = json.load(open(AFF, encoding="utf-8"))
    by_dir = {}
    for it in aff["items"]:
        for d in it.get("run_dirs") or []:
            by_dir[d.replace("\\", "/")] = it
    rows = []
    st = Counter(r["status"] for r in man)
    for r in man:
        if r["status"] != "ok":
            continue
        p = r["path"] if os.path.isabs(r["path"]) else os.path.join(ROOT, r["path"])
        A = json.load(open(p, encoding="utf-8"))
        g = A.get("grade_v3") or {}
        bf = A.get("grade_v3_backfill") or {}
        ep = (A.get("measurement_axis") or {}).get("epoch") or "k200kq150_2005_v1(축 기록 없음)"
        fa = g.get("fa") or {}
        d = os.path.dirname(rel(p))
        it = by_dir.get(d)
        rows.append(dict(
            dir=d, strategy_id=A.get("strategy_id"), name=(A.get("strategy_name") or "")[:90], epoch=ep,
            prior_rv=bf.get("prior_rules_version"), old=bf.get("prior_essence_grade") or r["old_grade"], new=A.get("essence_grade"),
            S=g.get("S"), S_B=g.get("S_B"), band=g.get("band"), notch=g.get("notch"), fa_notch=g.get("fa_notch"),
            fa_t_min=fa.get("t_min"), fa_model=fa.get("t_min_model"), fa_why_not=fa.get("why_not"),
            blocked_by=g.get("blocked_by"),
            cr=(g.get("cr") or {}).get("overall") if isinstance(g.get("cr"), dict) else g.get("cr"),
            cr_test=(g.get("cr") or {}).get("test") if isinstance(g.get("cr"), dict) else None,
            oos_gate=(g.get("oos") or {}).get("gate"), oos_components=(g.get("oos") or {}).get("components"),
            calmar_tw=(g.get("oos") or {}).get("calmar_tw"), bench_calmar_tw=(g.get("oos") or {}).get("bench_calmar_tw"),
            fund_v1=(None if it is None else bool(it.get("affected_v1"))),
            fund_channels=(None if it is None else it.get("fundamental_channels")),
            program_round=(A.get("replication") or {}).get("program_round") if isinstance(A.get("replication"), dict) else None))
    trans = defaultdict(Counter)
    for x in rows:
        trans[x["epoch"]][(x["old"], x["new"])] += 1
    changed = [x for x in rows if x["old"] != x["new"]]

    def cause(x):
        c = []
        if x["fa_notch"] in (1, "1", True):
            c.append("팩터 알파 노치")
        b = x["blocked_by"] or []
        if isinstance(b, str):
            b = [b]
        if any("oos" in str(v) for v in b):
            c.append("OOS 관문(시험 창 Calmar 또는 CR)")
        return " · ".join(c) or "기타(재채점 규칙 · 입력)"
    for x in changed:
        x["cause"] = cause(x)
    out = dict(
        generated_at=__import__("datetime").datetime.now().astimezone().isoformat(timespec="seconds"),
        rules_version="v3.3", status_counts=dict(st), n_ok=len(rows),
        transitions={ep: {f"{a}->{b}": n for (a, b), n in sorted(c.items(), key=lambda kv: (str(kv[0][0]), str(kv[0][1])))}
                     for ep, c in trans.items()},
        changed=changed,
        current_axis_A=[x for x in rows if x["epoch"] == CUR and x["new"] == "A"],
        fa_notch_applied=[x for x in rows if x["fa_notch"] in (1, "1", True)],
        note="같은 측정 축 안에서만 비교한다. 현 축 기록 중 fund_v1 = true 는 재무 결함 위 측정(v1) — 풀 · BOOK · 라운드 재료 · 인용 전에 v2 팩터 DB 로 재측정(FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE-20261109).")
    with open(os.path.join(HERE, "transitions.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1, default=str)
    L = [f"# 등급 v3.3 재채점 전이 (2026-11-10)", "",
         f"- 상태: {dict(st)} · 채점 {len(rows)}", ""]
    for ep, c in trans.items():
        L.append(f"## 축 {ep}")
        for (a, b), n in sorted(c.items(), key=lambda kv: (str(kv[0][0]), str(kv[0][1]))):
            L.append(f"- {a} → {b}: {n}" + ("  ★" if a != b else ""))
        L.append("")
    L.append("## 바뀐 기록")
    for x in sorted(changed, key=lambda x: (x["epoch"], x["new"] or "")):
        fv = {True: "재무 v1(인용 전 재측정)", False: "재무 영향 없음", None: "영향 목록 밖"}[x["fund_v1"]]
        L.append(f"- [{x['epoch']}] {x['strategy_id']} {x['old']} → {x['new']} · S {x['S']} · 띠 {x['band']} · 노치 {x['notch']} · "
                 f"알파 노치 {x['fa_notch']}(최소 t {x['fa_t_min']} {x['fa_model'] or ''}) · 원인 {x['cause']} · {fv} · {x['name']}")
    open(os.path.join(HERE, "transitions.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
    print("\n".join(L[:60]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
