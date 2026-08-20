# build_census_and_plan.py — module_catalog 동일-hash 이명 오염 전수 census + 패치 플랜 생성
# 재현: .venv_qvest_ml/Scripts/python.exe 04_Research/01_reports/audits/module_catalog_dup_hash_audit_20260820/build_census_and_plan.py
# 입력(read-only): 06_Registry/module_catalog.json · module_performance.json ·
#                  standalone_track_dispositions.json · hypothesis_index.json ·
#                  04_Research/01_reports/audits/batch434_label_audit_20260613/audit_runs.csv
# 출력: 이 디렉토리의 census_dup_hash_20260820.csv + catalog_patch_plan_20260820.csv
# 판정 로직은 README.md §분류 참조. catalog 는 절대 수정하지 않는다(플랜만 생성).
import csv
import json
import os
import re
from collections import defaultdict

ROOT = os.environ.get("QM_ROOT", r"C:/Users/99922/OneDrive/Quant_Module_Moltbot")
HERE = os.path.join(ROOT, "04_Research/01_reports/audits/module_catalog_dup_hash_audit_20260820")
JUNE = os.path.join(ROOT, "04_Research/01_reports/audits/batch434_label_audit_20260613/audit_runs.csv")

MARKERS = ("requires code generation", "diagnostic/sweep spec", "patched blocked runner")

def strip_markers(s):
    s = re.sub(r"Forge contract/spec requires code generation before backtest", "", s)
    s = re.sub(r"diagnostic/sweep spec; code or target absent.*", "", s)
    s = re.sub(r"patched blocked runner into executable.*", "", s)
    return re.sub(r"\s+", " ", s).strip()

with open(os.path.join(ROOT, "06_Registry/module_catalog.json"), encoding="utf-8") as f:
    mods = json.load(f)["modules"]

byhash = defaultdict(list)
for sid, m in mods.items():
    h = m.get("module_hash")
    if isinstance(h, str) and h:
        byhash[h].append(sid)
dup = {h: sorted(ids, key=lambda s: (mods[s].get("registered_at") or "", s))
       for h, ids in byhash.items() if len(ids) > 1}

june = {}
if os.path.exists(JUNE):
    with open(JUNE, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            june[row["strategy_id"]] = row

with open(os.path.join(ROOT, "06_Registry/module_performance.json"), encoding="utf-8") as f:
    mp = json.load(f)
mp_ids = set()
for reg in (mp.get("regimes") or {}).values() if isinstance(mp.get("regimes"), dict) else []:
    if isinstance(reg, dict):
        mp_ids.update(reg.keys())
if not mp_ids:  # schema fallback: any strategy_id string occurrence
    mp_s = json.dumps(mp, ensure_ascii=False)
    mp_ids = {sid for h, ids in dup.items() for sid in ids if sid in mp_s}

with open(os.path.join(ROOT, "06_Registry/standalone_track_dispositions.json"), encoding="utf-8") as f:
    disp_s = json.dumps(json.load(f), ensure_ascii=False)

def idea(sid):
    return ((mods[sid].get("meta") or {}).get("strategy_idea") or "")

def classify(ids):
    stems = {strip_markers(idea(s)) for s in ids}
    marked = [s for s in ids if any(mk in idea(s) for mk in MARKERS)]
    if len(stems) == 1:
        return "SAME_IDEA_RERUN"
    if marked:
        return "FALLBACK_SUBSTITUTION"
    # 무마커 + 이종 가설: overlay/게이트 차이 선언이 결과에 반영 안 된 경우 vs 동일 신호 이명.
    # "excluded/제외" 는 overlay 부재를 **선언**한 라벨이라 동일-NAV 가 거짓이 아니다 → 이명.
    joined = " | ".join(sorted(stems))
    if re.search(r"excluded|제외", joined):
        return "BASE_ALIAS"
    if re.search(r"BRK|MRS|overlay|Overlay|Gate", joined):
        return "OVERLAY_NOOP"
    return "BASE_ALIAS"

census_rows, plan_rows = [], []
for h, ids in sorted(dup.items(), key=lambda kv: -len(kv[1])):
    cls = classify(ids)
    rep = ids[0]  # registered_at 최솟값 (June 플랜과 동일 규칙)
    for sid in ids:
        j = june.get(sid, {})
        ae = ((mods[sid].get("meta") or {}).get("authoritative_essence") or {})
        census_rows.append({
            "strategy_id": sid,
            "module_hash": h,
            "group_size": len(ids),
            "cluster_rep": rep,
            "is_rep": sid == rep,
            "class": cls,
            "june_label_class": j.get("label_class", ""),
            "actual_factor_names": (j.get("actual_factor_names", "") or "").replace('"")', "").strip('", '),
            "actual_engine": j.get("actual_engine", ""),
            "registered_at": mods[sid].get("registered_at", ""),
            "grade": mods[sid].get("grade", ""),
            "fr_eligible": mods[sid].get("fr_eligible", ""),
            "port_t": ae.get("portfolio_alpha_t_nw_lag3", ""),
            "oos_retention": ae.get("oos_retention", ""),
            "calmar": ae.get("calmar", ""),
            "in_module_performance": sid in mp_ids,
            "in_dispositions": sid in disp_s,
            "strategy_idea_head": idea(sid)[:90],
        })
        is_mismatch = cls in ("FALLBACK_SUBSTITUTION", "OVERLAY_NOOP") or "MISMATCH" in j.get("label_class", "")
        plan_rows.append({
            "strategy_id": sid,
            "dup_hash_group": h,
            "cluster_rep": rep,
            "annotate_duplicate_of": "" if sid == rep else rep,
            "annotate_label_class": j.get("label_class", "") or cls,
            "annotate_actual_factor_names": (j.get("actual_factor_names", "") or "").replace('"")', "").strip('", '),
            "defr_nonrep": sid != rep,          # --defr-nonrep 시 fr_eligible=false
            "quarantine_mismatch": is_mismatch,  # --quarantine-mismatch 시 격리 이동
        })

# ── 확장 (2026-08-20 continuity 사이클): 유니크-hash 치환분 ───────────────────
# June 감사(batch_434) 런 중 현행 catalog 등재 + dup census 밖 = 치환됐지만 콤보가
# 유니크해 중복으로 안 잡힌 것. dup 가드는 원리적으로 못 잡는다(산출물 유니크) —
# 라벨 주석이 유일한 방어선이므로 플랜에 편입한다. de-FR 대상 아님(복제본이 아님).
dup_ids_all = {r["strategy_id"] for r in census_rows}
uniq_rows = []
for sid, j in june.items():
    if sid in mods and sid not in dup_ids_all:
        is_mismatch = "MISMATCH" in j.get("label_class", "")
        plan_rows.append({
            "strategy_id": sid,
            "dup_hash_group": "",
            "cluster_rep": "",
            "annotate_duplicate_of": "",
            "annotate_label_class": j.get("label_class", ""),
            "annotate_actual_factor_names": (j.get("actual_factor_names", "") or "").replace('"")', "").strip('", '),
            "defr_nonrep": False,
            "quarantine_mismatch": is_mismatch,
        })
        uniq_rows.append({
            "strategy_id": sid,
            "label_class": j.get("label_class", ""),
            "actual_factor_names": (j.get("actual_factor_names", "") or "").replace('"")', "").strip('", '),
            "fr_eligible": mods[sid].get("fr_eligible", ""),
            "strategy_idea_head": idea(sid)[:90],
        })

for name, rows in (("census_dup_hash_20260820.csv", census_rows),
                   ("unique_hash_substituted_20260820.csv", uniq_rows),
                   ("catalog_patch_plan_20260820.csv", plan_rows)):
    p = os.path.join(HERE, name)
    with open(p, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print("wrote", p, len(rows), "rows")

n_cls = defaultdict(int)
for r in census_rows:
    n_cls[r["class"]] += 1
print("groups:", len(dup), "| modules:", len(census_rows), "| class:", dict(n_cls))
print("in module_performance:", sum(1 for r in census_rows if r["in_module_performance"]),
      "| in dispositions:", sum(1 for r in census_rows if r["in_dispositions"]),
      "| june-audited:", sum(1 for r in census_rows if r["june_label_class"]))
