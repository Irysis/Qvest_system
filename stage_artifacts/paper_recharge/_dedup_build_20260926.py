# -*- coding: utf-8 -*-
"""Build the dedup key universe for 20260926 triage.
Chain (per spec §판정1 + 20260924 precedent): paper_registry(paper_key/arxiv_id/duplicate_of/source/path)
+ alpha_search_queue_done::processed + all alpha_search_route_*.json history + data_pipeline_queue.
Captures BOTH modern (2504.01234) and legacy (cond-mat/0410079) arXiv id notations.
"""
import json, re, glob, os
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PR = ROOT + "/stage_artifacts/paper_recharge"

MOD = re.compile(r"\b(\d{4}\.\d{4,5})\b")
LEG = re.compile(r"\b((?:cond-mat|q-fin|math|physics|cs|stat|q-bio|nlin|hep-th|hep-ph|astro-ph|math-ph|gr-qc|quant-ph|nucl-th|adap-org|chao-dyn)(?:\.[A-Za-z\-]+)?/\d{7})\b")
UND = re.compile(r"\b(\d{4})[._](\d{4,5})\b")   # MCP_2609_04496.pdf style

def ids_from(text):
    if not text: return set()
    s = str(text); out = set()
    out |= set(MOD.findall(s))
    out |= set(LEG.findall(s))
    for a, b in UND.findall(s):
        out.add(f"{a}.{b}")
    return {i.strip() for i in out if i}

seen_ids, seen_keys, prov = set(), set(), {}
def add(i, src):
    if not i: return
    i = str(i).strip()
    i = re.sub(r"v\d+$", "", i)
    if not i: return
    if i not in seen_ids: prov[i] = src
    seen_ids.add(i)

# 1. paper_registry
reg = json.load(open(ROOT + "/06_Registry/paper_registry.json", encoding="utf-8"))
n_reg_ids = 0
for e in reg:
    for f in ("arxiv_id", "paper_key", "duplicate_of", "source", "path", "note", "title"):
        v = e.get(f)
        if f == "paper_key" and v and str(v).startswith("axv:"):
            add(str(v)[4:], "registry.paper_key")
        if f in ("arxiv_id",) and v:
            add(v, "registry.arxiv_id")
        if f in ("source", "path", "duplicate_of") and v:
            for i in ids_from(v): add(i, f"registry.{f}")
    if e.get("paper_key"): seen_keys.add(str(e["paper_key"]))
n_reg_ids = len(seen_ids)

# 2. done queue processed
dq = json.load(open(PR + "/alpha_search_queue_done.json", encoding="utf-8"))
for pid in (dq.get("processed") or []): add(pid, "done_queue.processed")
for r in (dq.get("records") or []):
    if r.get("paper_id"): add(r["paper_id"], "done_queue.records")
n_after_dq = len(seen_ids)

# 3. route history
route_files = sorted(glob.glob(PR + "/alpha_search_route_*.json"))
n_route_papers = 0
for rf in route_files:
    try: d = json.load(open(rf, encoding="utf-8"))
    except Exception: continue
    for p in (d.get("papers") or []):
        n_route_papers += 1
        if p.get("paper_key"): seen_keys.add(str(p["paper_key"]))
        if p.get("paper_key") and str(p["paper_key"]).startswith("axv:"):
            add(str(p["paper_key"])[4:], "route_history")
        if p.get("id"): add(p["id"], "route_history")
n_after_route = len(seen_ids)

# 4. data_pipeline_queue
dpq_path = ROOT + "/06_Registry/data_pipeline_queue.json"
dpq = None
if os.path.exists(dpq_path):
    dpq = json.load(open(dpq_path, encoding="utf-8"))
    for e in (dpq.get("entries") or []):
        if e.get("paper_key") and str(e["paper_key"]).startswith("axv:"):
            add(str(e["paper_key"])[4:], "data_pipeline_queue")
        if e.get("paper_id"): add(e["paper_id"], "data_pipeline_queue")
        seen_keys.add(str(e.get("paper_key")))

out = {"n_registry_entries": len(reg), "n_ids_registry": n_reg_ids,
       "n_ids_after_done_queue": n_after_dq, "n_ids_after_route_history": n_after_route,
       "n_route_files": len(route_files), "n_route_papers": n_route_papers,
       "n_ids_total": len(seen_ids), "n_keys_total": len(seen_keys),
       "dpq_exists": dpq is not None,
       "dpq_entries": len((dpq or {}).get("entries") or []) if dpq else 0,
       "legacy_ids_sample": sorted([i for i in seen_ids if "/" in i])[:10],
       "n_legacy_ids": len([i for i in seen_ids if "/" in i])}
json.dump({"meta": out, "ids": sorted(seen_ids), "keys": sorted(k for k in seen_keys if k and k!='None')},
          open(PR + "/_dedup_universe_20260926.json", "w", encoding="utf-8"), ensure_ascii=False)
print(json.dumps(out, ensure_ascii=False, indent=1))
