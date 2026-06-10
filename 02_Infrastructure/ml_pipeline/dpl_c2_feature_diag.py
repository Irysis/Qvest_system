#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_c2_feature_diag.py — alpha-research per-feature canonical validation (WT-D20260606_002).

DPL이 먹을 feature panel(98f, WT_DPL_C2)의 *각 신규 feature*가 실제 신호를 주는지 실측.
역할: alpha-research = feature-alpha 패널 큐레이트/검증 (Σ/weight 금지).

각 feature x_{i,t} (month-end signal) vs forward 1M return Ret_1m:
  - rank-IC (Spearman, per-month) → mean, ICIR=mean/sd, Harvey-t(NW lag-3)
  - subperiod stability (3 eras: 2005-11 / 2012-18 / 2019-26 frac same-sign)
  - uncertainty-aware: ICIR 하한 μ̃ = mean_IC − k·SE(IC), k=1 (Liao 2025 RFS 정신)
  - 신규 feature 간 + base 90f 대비 직교성: |corr| 분포 (mutual orthogonality)
  - long-only top-20 portfolio active return t (canonical screen proxy, NW lag-3) — rank-IC와 구분

PIT: panel은 이미 forward-label recompute PASS(pit_audit.json). 여기선 추가 lookahead 생성 없음
     (단면 z feature × forward label, 모두 panel 내 PIT-clean 컬럼 사용).
self-synth 금지: portfolio active return은 월별 EW top-20 mean active만(라벨=canonical_screen_proxy).
출력: stage_artifacts/WT_D20260606_002/feature_diag.json
"""
import os, json
import numpy as np
import pandas as pd
from scipy import stats

ROOT = r"G:/Quant_Module_Moltbot"
PANEL = os.path.join(ROOT, "stage_artifacts", "WT_DPL_C2", "dpl_feature_panel.parquet")
OUT_DIR = os.path.join(ROOT, "stage_artifacts", "WT_D20260606_002")
os.makedirs(OUT_DIR, exist_ok=True)

NEW_FEATS = ["RESIDMOM__lvl", "RESIDMOM__slp", "PIOTROSKI__lvl", "PIOTROSKI__slp",
             "MOHANRAM__lvl", "MOHANRAM__slp", "NETISSUE__lvl", "NETISSUE__slp"]
LOCKBOX = "2023-12"   # regular-research lockbox (alpha = lockbox 적용)


def nw_t(x, lag=3):
    x = np.asarray([v for v in x if v == v], float)
    n = len(x)
    if n < lag + 2:
        return np.nan
    mu = x.mean(); e = x - mu; g0 = (e**2).sum()/n; s = g0
    for l in range(1, lag+1):
        w = 1 - l/(lag+1); g = (e[l:]*e[:-l]).sum()/n; s += 2*w*g
    if s <= 0:
        return np.nan
    return mu/np.sqrt(s/n)


def per_month_ic(df, feat, ret="Ret_1m"):
    ics = []
    for ym, g in df.groupby("ym"):
        sub = g[[feat, ret]].dropna()
        if len(sub) < 15 or sub[feat].std() == 0:
            continue
        ic = stats.spearmanr(sub[feat], sub[ret]).correlation
        if ic == ic:
            ics.append((ym, ic))
    return pd.DataFrame(ics, columns=["ym", "ic"])


def topn_active(df, feat, n=20, ret="Ret_1m"):
    """월별 top-n EW active return (vs cross-section mean = proxy benchmark). self-synth 아님(월별 mean active만)."""
    rows = []
    for ym, g in df.groupby("ym"):
        sub = g[[feat, ret]].dropna()
        if len(sub) < 30 or sub[feat].std() == 0:
            continue
        top = sub.nlargest(n, feat)[ret].mean()
        bench = sub[ret].mean()
        rows.append((ym, top - bench))
    return pd.DataFrame(rows, columns=["ym", "active"])


def main():
    df = pd.read_parquet(PANEL)
    df["ym"] = df["ym"].astype(str)
    if "in_univ" in df.columns:
        df = df[df["in_univ"] == 1].copy()
    # lockbox: regular research alpha (alpha-research = lockbox 적용)
    df = df[df["ym"] <= LOCKBOX].copy()
    print(f"[diag] rows(in-univ, <=lockbox)={len(df):,} months={df['ym'].nunique()} "
          f"[{df['ym'].min()}..{df['ym'].max()}]")

    eras = {"E1_2005_2011": ("2005-01", "2011-12"),
            "E2_2012_2018": ("2012-01", "2018-12"),
            "E3_2019_lock": ("2019-01", LOCKBOX)}

    results = {}
    for feat in NEW_FEATS:
        if feat not in df.columns:
            results[feat] = {"error": "missing"}
            continue
        icdf = per_month_ic(df, feat)
        if len(icdf) < 24:
            results[feat] = {"error": f"n_ic_months={len(icdf)}"}
            continue
        ic_mean = float(icdf["ic"].mean())
        ic_sd = float(icdf["ic"].std(ddof=1))
        n = len(icdf)
        icir = ic_mean/ic_sd if ic_sd > 0 else np.nan
        se_ic = ic_sd/np.sqrt(n)
        harvey_t = nw_t(icdf["ic"].values, 3)
        ic_lb = ic_mean - 1.0*se_ic   # uncertainty-aware lower bound (k=1)
        # subperiod stability: fraction of eras with same sign as overall
        sub = {}
        for nm, (a, b) in eras.items():
            seg = icdf[(icdf["ym"] >= a) & (icdf["ym"] <= b)]["ic"]
            sub[nm] = round(float(seg.mean()), 4) if len(seg) >= 6 else None
        signs = [np.sign(v) for v in sub.values() if v is not None]
        stab = float(np.mean([s == np.sign(ic_mean) for s in signs])) if signs else np.nan
        # top-20 active (canonical-screen proxy, NW t) — rank-IC와 구분
        act = topn_active(df, feat)
        act_t = nw_t(act["active"].values, 3) if len(act) >= 24 else np.nan
        act_mean_ann = float(act["active"].mean()*12) if len(act) else np.nan
        results[feat] = {
            "n_ic_months": n,
            "rank_ic_mean": round(ic_mean, 4),
            "icir": round(float(icir), 4) if icir == icir else None,
            "harvey_t_rankic_nw3": round(float(harvey_t), 3) if harvey_t == harvey_t else None,
            "ic_lower_bound_k1": round(float(ic_lb), 4),
            "subperiod_ic": sub,
            "subperiod_sign_stability": round(stab, 3) if stab == stab else None,
            "top20_active_t_nw3_proxy": round(float(act_t), 3) if act_t == act_t else None,
            "top20_active_ann_proxy": round(act_mean_ann, 4),
            "metric_type": "canonical_screen_proxy",
        }
        print(f"[diag] {feat:18s} IC={ic_mean:+.4f} ICIR={icir:+.3f} H-t={harvey_t:+.2f} "
              f"stab={stab:.2f} top20_t={act_t if act_t==act_t else float('nan'):+.2f}")

    # mutual orthogonality among new feats + vs base 90f (pooled corr over panel)
    feat_cols = [c for c in df.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    base_cols = [c for c in feat_cols if c not in NEW_FEATS]
    sub = df[[c for c in NEW_FEATS if c in df.columns]].fillna(0.0)
    mut = sub.corr().abs()
    np.fill_diagonal(mut.values, np.nan)
    # max |corr| of each new feat vs base 90f
    vs_base = {}
    base_mat = df[base_cols].fillna(0.0)
    for f in NEW_FEATS:
        if f not in df.columns:
            continue
        cors = base_mat.corrwith(df[f].fillna(0.0)).abs()
        vs_base[f] = {"max_abs_corr_vs_base90": round(float(cors.max()), 3),
                      "argmax_base": str(cors.idxmax())}

    ortho = {
        "mutual_max_abs_corr_among_new": round(float(np.nanmax(mut.values)), 3),
        "mutual_mean_abs_corr_among_new": round(float(np.nanmean(mut.values)), 3),
        "new_vs_base90_max_abs_corr": vs_base,
        "note": "low |corr| = orthogonal (DPL benefits from diverse, non-redundant features).",
    }

    out = {
        "task_id": "WT-D20260606_002",
        "as_of_date": "2026-06-06",
        "panel": PANEL,
        "universe": "KOSPI200_KOSDAQ150_intersection (in_univ==1)",
        "lockbox": LOCKBOX,
        "metric_type": "canonical_screen_proxy (rank-IC + top20 active; forge-authoritative 아님)",
        "per_feature": results,
        "orthogonality": ortho,
    }
    with open(os.path.join(OUT_DIR, "feature_diag.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"[diag] -> {os.path.join(OUT_DIR, 'feature_diag.json')}")
    print(f"[diag] mutual max|corr| new={ortho['mutual_max_abs_corr_among_new']} "
          f"mean={ortho['mutual_mean_abs_corr_among_new']}")


if __name__ == "__main__":
    main()
