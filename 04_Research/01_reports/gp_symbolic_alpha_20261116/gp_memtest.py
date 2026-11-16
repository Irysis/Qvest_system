import sys, os, time, json, psutil, numpy as np
sys.path.insert(0, "G:/OneDrive/Quant_Module_Moltbot/04_Research/01_reports/gp_symbolic_alpha_20261116")
from gp_data import build_panel, load_cfg
import gp_ops as O, gp_selftest as ST
from gp_fitness import metrics, month_sets
def mem():
    mi = psutil.Process().memory_info(); return {"rss": round(mi.rss/2**30,2), "private": round(mi.private/2**30,2), "peak_wset": round(mi.peak_wset/2**30,2), "peak_private": round(mi.peak_pagefile/2**30,2)}
cfg = load_cfg(); O.configure(cfg["grammar"])
out = {}
t = time.time()
store = "G:/OneDrive/Quant_Module_Moltbot/.cache/gp_alpha_factors/memtest_20261116/panel"
from gp_data import load_panel, build_panel_subprocess
import os
p = load_panel(store) if os.path.exists(os.path.join(store, "panel_meta.json")) else build_panel_subprocess(None, "1998-01-01", "2025-12-31", None, store)
out["load_s"] = round(time.time()-t, 1); out["after_load"] = mem(); out["T_N"] = list(p.elig.shape)
import pyarrow as pa
pa.default_memory_pool().release_unused(); out["after_pool_release"] = mem()
ev = O.Evaluator(p.fields, cfg["resources"]["subtree_cache_mb"])
tm, vm = month_sets(p, "2000-01-01", "2000-01-01", 36, 1)
ts = []
for e in ST.random_exprs(cfg, 25, seed=5):
    t = time.time(); X = ev.eval(e); S = X[p.me_idx]; metrics(p, S, tm, cfg["portfolio"]); metrics(p, S, vm, cfg["portfolio"]); ts.append(time.time()-t)
out["eval_s"] = {"mean": round(float(np.mean(ts)),2), "median": round(float(np.median(ts)),2), "max": round(float(np.max(ts)),2)}
out["after_eval"] = mem(); out["cache_mb"] = round(ev.cache_bytes/2**20)
print(json.dumps(out))
json.dump(out, open("G:/OneDrive/Quant_Module_Moltbot/.cache/gp_alpha_factors/memtest_20261116/memtest.json", "w"), indent=1)
