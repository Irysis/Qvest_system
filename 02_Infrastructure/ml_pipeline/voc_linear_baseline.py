#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
voc_linear_baseline.py — Qvest v8.x: LINEAR baseline for the Virtue-of-Complexity test.

Same panel(98f) + same walk-forward + same top-25 EW portfolio as voc_forecast.py, but the
forecaster is a *plain linear cross-sectional ridge* on the raw 98 features (P=F=98, no random
Fourier expansion). This is the "linear cross-sectional factor → top-N" paradigm that 밤샘
long-only experiments exhausted. If VoC (P≫T RFF) beats this OOS, it is a paradigm escape.

Reuses voc_forecast machinery (load_panel / build_forward_h_label / ridge_fit /
net_return_series / port_ew_topn) — no self-synthesis, identical realized-return assembly.
Exports baselines_net_returns.parquet with method=LINEAR_98f_top25 into VOC_OUT_DIR for the
R contract eval (dpl_c2_eval_total.R picks it up alongside EW_top20/MVO_2stage copies).

실행:
  $env:VOC_OUT_DIR="G:/Quant_Module_Moltbot/stage_artifacts/WT_VOC_C3"
  .venv_qvest_ml/Scripts/python.exe 02_Infrastructure/ml_pipeline/voc_linear_baseline.py
"""
import os
import json
import numpy as np
import pandas as pd
import torch

import voc_forecast as V

torch.set_default_dtype(torch.float64)
DEVICE = V.DEVICE
HORIZON = V.HORIZON
LOOKBACK = V.LOOKBACK
TOP_N = V.TOP_N
ANNUALIZE = V.ANNUALIZE
OUT_DIR = V.OUT_DIR
LAMBDA = float(os.environ.get("VOC_LIN_LAMBDA", "1e-2"))  # mild ridge for stability


def walk_forward_linear(panel, feat_cols, months, lam, lookback, step):
    """Plain linear ridge on raw 98f (no RFF). Identical walk-forward/refit cadence to VoC."""
    n_feat = len(feat_cols)
    mcache = {}
    for m, sub in panel.groupby("ym"):
        mcache[m] = {
            "X": torch.tensor(sub[feat_cols].values, dtype=torch.float64, device=DEVICE),
            "y": torch.tensor(sub["label_h"].values, dtype=torch.float64, device=DEVICE),
            "tk": sub["Ticker"].values, "lab": sub["label_h"].values}
    rows = []
    beta = None
    refit_anchor = None
    start_i = lookback
    for i in range(start_i, len(months), step):
        m = months[i]
        if m not in mcache:
            continue
        need = (beta is None) or (refit_anchor is None) or ((i - refit_anchor) >= V.REFIT_EVERY)
        if need:
            tr = months[max(0, i - lookback):i]
            Xb = [mcache[t]["X"] for t in tr if t in mcache]
            yb = [mcache[t]["y"] for t in tr if t in mcache]
            if not Xb:
                continue
            Xtr = torch.cat(Xb, 0)
            ytr = torch.cat(yb, 0)
            good = torch.isfinite(ytr)
            Xtr, ytr = Xtr[good], ytr[good]
            if Xtr.shape[0] < TOP_N * 2:
                continue
            xmu = Xtr.mean(0, keepdim=True)
            xsd = Xtr.std(0, keepdim=True).clamp_min(1e-8)
            Xtr = (Xtr - xmu) / xsd
            beta, _ = V.ridge_fit(Xtr, ytr, lam)
            refit_anchor = i
            _xmu, _xsd = xmu, xsd
        c = mcache[m]
        if c["X"].shape[0] < TOP_N:
            continue
        Xte = (c["X"] - _xmu) / _xsd
        yhat = (Xte @ beta).detach().cpu().numpy()
        w = V.port_ew_topn(yhat)
        sel = w > 1e-6
        rows.append({"ym": m, "tk": c["tk"][sel], "w": w[sel], "lab": c["lab"][sel]})
    return rows


def main():
    print(f"[lin] device={DEVICE} horizon={HORIZON}m lookback={LOOKBACK} lam={LAMBDA:g}", flush=True)
    panel0, bm0, feat_cols = V.load_panel()
    panel, bm, _ = V.build_forward_h_label(panel0, bm0, HORIZON)
    months = sorted(panel["ym"].unique())
    step = HORIZON
    rows = walk_forward_linear(panel, feat_cols, months, LAMBDA, LOOKBACK, step)
    df = V.net_return_series(rows, bm)
    sr = V.sharpe_active(df)
    ret = V.oos_retention_worst3(df)
    to = float(df["traded"].mean() * (ANNUALIZE / max(1, HORIZON)))
    print(f"[lin] LINEAR_98f_top25 active_SR={sr:.3f} retention={ret} TO={to:.2f} "
          f"n_oos={int(df['ret_net'].notna().sum())}", flush=True)

    be = df.copy()
    be["date"] = pd.PeriodIndex(be["ym"], freq="M").to_timestamp("M")
    be["method"] = "LINEAR_98f_top25"
    be = be.rename(columns={"BM_Ret_1m": "BM_Ret"})
    out = be[["method", "date", "ret_net", "BM_Ret", "traded"]].dropna(subset=["ret_net"])

    # merge with any existing baselines copies (EW_top20/MVO_2stage) so eval picks all up
    bpath = os.path.join(OUT_DIR, "baselines_net_returns.parquet")
    if os.path.exists(bpath):
        prev = pd.read_parquet(bpath)
        prev = prev[prev["method"] != "LINEAR_98f_top25"]
        out = pd.concat([prev, out], ignore_index=True)
    out.to_parquet(bpath, index=False)
    print(f"[lin] -> {bpath} (methods: {sorted(out['method'].unique())})", flush=True)

    meta = {"method": "LINEAR_98f_top25", "forecaster": "cross-sectional ridge on raw 98f",
            "lambda": LAMBDA, "horizon": HORIZON, "lookback": LOOKBACK,
            "active_sr": round(sr, 4) if sr == sr else None,
            "retention": round(ret, 3) if ret == ret else None,
            "to_ann": round(to, 2), "n_oos": int(df["ret_net"].notna().sum()),
            "note": "linear cross-sectional factor->top25 paradigm (밤샘 exhausted). "
                    "VoC가 이를 OOS로 능가하면 패러다임 탈출."}
    with open(os.path.join(OUT_DIR, "linear_baseline.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False, default=float)
    print(f"[lin] meta -> {os.path.join(OUT_DIR, 'linear_baseline.json')}", flush=True)


if __name__ == "__main__":
    main()
