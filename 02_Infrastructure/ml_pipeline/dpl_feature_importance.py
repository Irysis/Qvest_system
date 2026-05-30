#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""dpl_feature_importance.py — best DPL config 재학습 후 permutation importance.

90개 rolling feature 중 실제 기여 피처 보고 (피처폭발 대응 — 도훈 설계 C).
permutation: OOS 패널에서 각 피처를 셔플 → 모델 score-rank 변화(스피어만 ρ 하락)로 중요도.
"""
import os, sys, json
import numpy as np, pandas as pd, torch
torch.set_default_dtype(torch.float64)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dpl_gpu_sweep as S

OUT = S.OUT_DIR
panel, bm, feat_cols = S.load_panel()
months = sorted(panel["ym"].unique())
lock = S.LOCKBOX.to_period("M")
months = [m for m in months if pd.Period(m, "M") <= lock]
cache = S.build_month_cache(panel[panel["ym"].isin(months)], feat_cols)

sw = json.load(open(os.path.join(OUT, "sweep_results.json")))
b = sw["best"]
cfg = {k: b[k] for k in ["lam","gamma","lookback","depth","width","l2","dropout","temp","lr","epochs","min_train"]}
torch.manual_seed(7); np.random.seed(7)
# 마지막 학습창으로 모델 학습
tr = months[-cfg["lookback"]-1:-1]
model = S.train_dpl(cache, len(feat_cols), tr, cfg)
model.eval()

# OOS-ish eval month set (마지막 24개월)
ev_months = months[-24:]
def realized_active_sr(perm_feat=None):
    rows=[]
    for m in ev_months:
        if m not in cache or cache[m]["n"] < S.ACTIVE_MAX: continue
        X = cache[m]["X"].clone()
        if perm_feat is not None:
            idxp = torch.randperm(X.shape[0], device=X.device)
            X[:, perm_feat] = X[idxp, perm_feat]
        with torch.no_grad():
            mu = model(X)
        idx = torch.topk(mu, S.ACTIVE_MAX).indices
        muc = (mu[idx]-mu[idx].mean())/(mu[idx].std()+1e-6)
        w = S.weights_from_scores(muc, cap=S.CAP, temp=cfg["temp"])
        r = cache[m]["r"][idx]
        rows.append(float((w*r).sum().cpu()))
    rows=np.array(rows)
    bmv = bm.set_index("ym")["BM_Ret_1m"].reindex(ev_months).values
    active = rows - np.nan_to_num(bmv[:len(rows)])
    return float(active.mean()/(active.std()+1e-9)*np.sqrt(12))

base_sr = realized_active_sr()
imp = {}
for j, c in enumerate(feat_cols):
    drops=[realized_active_sr(j) for _ in range(3)]
    imp[c] = base_sr - np.mean(drops)   # 양수 = 중요(셔플 시 SR 하락)
ranked = sorted(imp.items(), key=lambda kv:-kv[1])
print(f"[imp] base OOS active SR (last 24m): {base_sr:.3f}")
print("[imp] top 12 features by permutation importance:")
for c,v in ranked[:12]:
    print(f"   {c:32s} {v:+.4f}")
json.dump({"base_oos_sr_24m":base_sr, "permutation_importance":dict(ranked)},
          open(os.path.join(OUT,"feature_importance.json"),"w"), indent=2, default=float)
print(f"[imp] -> {os.path.join(OUT,'feature_importance.json')}")
