"""등급 v3.5 재채점 전수 · 대상 목록 (사전등록 부록 1 §2) — 저장 권위 기록의 필드만 읽는다(계산 없음 · 쓰기 = data/ 의 CSV · 목록뿐).

사용: python -I tools/census_regrade_set.py <저장소 루트> <tag>
산출: data/census_<tag>.csv(시험 창 열 없음 — 판단 T4 C-20261113-074) · data/dirs_regrade_<tag>.txt
  대상 = 규칙 범위(grade_v3 · v3.3/v3.4 · cr_notch_basis = strong) ∪ 요인 낡음(같은 축 · 저장 factor_md5 ≠ 현행 · 또는 요인 문맥 복구)
         ∪ 교체를 걸친 불완전 기록(판 표식 = 현행 · 상태 ok · selection_control 없음)
         ∪ 사전등록 T4 음성 대조 52(prereg.json) — 재채점 도구(grade_v3_backfill.R)의 판정과 같은 조건을 기록 필드로 다시 쓴다.
"""
import csv, json, os, sys

ROOT, TAG = sys.argv[1], sys.argv[2]
D = os.path.join(ROOT, "04_Research", "01_reports", "grade_v35_cr_beta_selection_20261113")
meta = json.load(open(os.path.join(ROOT, ".cache", "kr_factor_returns_meta.json"), encoding="utf-8"))
FA_NOW, FA_EP = meta["monthly"]["content_md5"], meta.get("epoch")
pre = json.load(open(os.path.join(D, "prereg.json"), encoding="utf-8"))
t4 = set(pre["report"]["T4_sets"]["cr_strong_converted_normal"]) | set(pre["report"]["T4_sets"]["random_non_strong"]["paths"])
snap = set(pre["regrade_scope"]["scope_snapshot"])
G3 = json.load(open(os.path.join(ROOT, "06_Registry", "grade_v3.json"), encoding="utf-8"))
RV_NOW = G3.get("rules_version"); NEED_SC = (G3.get("cr_notch") or {}).get("selection_control") == "size_beta"
rows, dirs = [], []
for dp, dn, fn in os.walk(os.path.join(ROOT, "stage_artifacts")):
    if "authoritative_remeasure.json" not in fn:
        continue
    rel = os.path.relpath(dp, ROOT).replace(os.sep, "/")
    if rel.startswith("stage_artifacts/WT_"):
        continue
    try:
        A = json.load(open(os.path.join(dp, "authoritative_remeasure.json"), encoding="utf-8"))
    except Exception:
        rows.append(dict(dir=rel, status="read_error")); continue
    g = A.get("grade_v3") or {}; fa = g.get("fa") or {}
    v3 = A.get("grade_scheme") == "grade_v3"
    rv = g.get("rules_version")
    old = fa.get("factor_md5"); re_, fe = fa.get("record_epoch"), fa.get("factor_epoch")
    stale = v3 and bool(re_) and bool(fe) and re_ == fe and bool(old) and old != FA_NOW
    restored = v3 and fa.get("status") == "factor_unavailable" and not old and (A.get("measurement_axis") or {}).get("epoch") == FA_EP
    scope = v3 and rv in ("v3.3", "v3.4") and g.get("cr_notch_basis") == "strong"
    rec_inc = v3 and NEED_SC and rv == RV_NOW and g.get("status") == "ok" and "selection_control" not in g   # 교체를 걸친 측정(backfill record_fields_incomplete 와 같은 조건)
    rows.append(dict(dir=rel, status="ok", strategy=A.get("strategy_name"), remeasured_at=A.get("remeasured_at"), scheme=A.get("grade_scheme"), essence_grade=A.get("essence_grade"), rules_version=rv,
                     band=g.get("band"), notch=g.get("notch"), cr_notch=g.get("cr_notch_basis"), cr_overall=(g.get("cr") or {}).get("overall"),
                     mc8_label=(g.get("mc8") or {}).get("label"), epoch=(A.get("measurement_axis") or {}).get("epoch"),
                     factor_md5_old=old, fa_stale=bool(stale or restored), scope=bool(scope), scope_snapshot=rel in snap,
                     t4=rel in t4, rec_inc=bool(rec_inc), hard_fail=bool(A.get("hard_fail")),
                     benefit=(A.get("rule_change_benefit") or {}).get("benefit"),
                     causes="+".join((A.get("grade_v3_backfill") or {}).get("causes") or []),
                     judge_eligible=os.path.exists(os.path.join(dp, "judge_request.eligible.json"))))
    if scope or stale or restored or rec_inc or rel in t4:
        dirs.append(rel)
keys = ["dir", "status", "strategy", "remeasured_at", "scheme", "essence_grade", "rules_version", "band", "notch", "cr_notch", "cr_overall", "mc8_label", "epoch",
        "factor_md5_old", "fa_stale", "scope", "scope_snapshot", "t4", "rec_inc", "hard_fail", "benefit", "causes", "judge_eligible"]
os.makedirs(os.path.join(D, "data"), exist_ok=True)
with open(os.path.join(D, "data", f"census_{TAG}.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=keys); w.writeheader()
    for r in rows:
        w.writerow({k: r.get(k, "") for k in keys})
with open(os.path.join(D, "data", f"dirs_regrade_{TAG}.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(sorted(set(dirs))) + "\n")
n = lambda k: sum(1 for r in rows if r.get(k))
print(f"[census {TAG}] 기록 {len(rows)} · 요인 md5 지금 {FA_NOW[:12]} · 규칙 범위 {n('scope')}(등록 시점 {sum(1 for r in rows if r.get('scope') and r.get('scope_snapshot'))}) · "
      f"요인 낡음 {n('fa_stale')} · 교체 걸친 불완전 {n('rec_inc')} · 겹침 {sum(1 for r in rows if r.get('scope') and r.get('fa_stale'))} · T4 {n('t4')} · 드라이런 대상 {len(set(dirs))}")
