#==============================================================================
# ca_core.py - Conditional Autoencoder asset-pricing model (Gu-Kelly-Xiu 2021), KR
#
# Extends the existing LINEAR IPCA (WT_D20260508_006) with a NONLINEAR beta net.
#   beta_{i,t} = g(z_{i,t})  [MLP, depth>=1 nonlinear; depth=0 -> linear ~ IPCA]
#   f_t        = W * (Z_t' r_t / N)   [factor net: managed-portfolio -> K factors]
#   rhat_{i,t} = beta_{i,t} . f_t      ;  loss = MSE(r, rhat)   (no-arbitrage: factor = char portfolio)
#
# Walk-forward (PIT): expanding train (>=MIN_TRAIN months), refit every REFIT,
# score next block OOS using beta(z) . fbar(train premia). -> per-stock monthly
# score series consumed by canonical_screen_bt (long-only top-N) for measurement.
#
# depth=0 config == linear IPCA-like baseline (apples-to-apples vs nonlinear CA).
#
# Env: CA_PANEL CA_OUT CA_CONFIGS(json) CA_K CA_DEPTH CA_WIDTH CA_EPOCHS CA_LR
#      CA_MIN_TRAIN CA_REFIT CA_SEED
# Run: $env:PYTHONUTF8="1"; .venv_qvest_ml/Scripts/python.exe -u 02_Infrastructure/ml_pipeline/ca_core.py
#==============================================================================
import os, sys, json, time
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from scipy.stats import spearmanr

torch.set_default_dtype(torch.float64)
ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT") or "G:/Quant_Module_Moltbot"
PANEL = os.environ.get("CA_PANEL", f"{ROOT}/stage_artifacts/WT_CA/panel_kr30/charpanel.parquet")
OUT   = os.environ.get("CA_OUT",   f"{ROOT}/stage_artifacts/WT_CA/kr30")
EPOCHS= int(os.environ.get("CA_EPOCHS", "300"))
LR    = float(os.environ.get("CA_LR", "1e-3"))
MIN_TRAIN = int(os.environ.get("CA_MIN_TRAIN", "60"))   # months before first OOS score
REFIT     = int(os.environ.get("CA_REFIT", "12"))       # refit cadence (months)
SEED  = int(os.environ.get("CA_SEED", "42"))
# default: linear baseline + nonlinear CA, both K=5 (KR paper)
CONFIGS = json.loads(os.environ.get("CA_CONFIGS",
    '[{"tag":"linear","depth":0,"K":5,"width":32},{"tag":"ca","depth":2,"K":5,"width":32}]'))
os.makedirs(OUT, exist_ok=True)
DEV = "cuda" if torch.cuda.is_available() else "cpu"
print(f"[ca] device={DEV} panel={PANEL} epochs={EPOCHS} min_train={MIN_TRAIN} refit={REFIT}", flush=True)


def load_panel():
    df = pd.read_parquet(PANEL)
    meta = {"Date", "YearMonth", "Ticker", "ret_fwd1m", "period_class"}
    chars = [c for c in df.columns if c not in meta]
    # derive betasq, absacc (re-z per month)
    if "D02_Beta" in df.columns:
        df["betasq"] = df["D02_Beta"] ** 2; chars.append("betasq")
    if "Q05_Accrual" in df.columns:
        df["absacc"] = df["Q05_Accrual"].abs(); chars.append("absacc")
    for c in ["betasq", "absacc"]:
        if c in df.columns:
            g = df.groupby("YearMonth")[c]
            df[c] = ((df[c] - g.transform("mean")) / (g.transform("std") + 1e-9)).fillna(0.0)
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values(["YearMonth", "Ticker"]).reset_index(drop=True)
    return df, chars


def to_months(df, chars):
    out = []
    for ym, g in df.groupby("YearMonth"):
        out.append({
            "ym": ym,
            "date": g["Date"].iloc[-1],
            "tk": g["Ticker"].to_numpy(),
            "Z": torch.tensor(g[chars].to_numpy(), device=DEV),
            "r": torch.tensor(g["ret_fwd1m"].to_numpy(), device=DEV),
        })
    return out


class CA(nn.Module):
    def __init__(self, L, K, depth, width):
        super().__init__()
        if depth <= 0:
            self.beta = nn.Linear(L, K, bias=False)          # linear ~ IPCA
        else:
            layers = [nn.Linear(L, width), nn.Tanh()]
            for _ in range(depth - 1):
                layers += [nn.Linear(width, width), nn.Tanh()]
            layers += [nn.Linear(width, K)]
            self.beta = nn.Sequential(*layers)
        self.factor = nn.Linear(L, K, bias=False)            # managed-portfolio -> factor

    def month(self, Z, r):
        beta = self.beta(Z)                                  # N x K
        x = (Z * r.unsqueeze(1)).mean(0)                     # L  (managed portfolio Z'r/N)
        f = self.factor(x)                                   # K
        rhat = beta @ f                                       # N
        return rhat, beta, f


def fit(train_m, L, K, depth, width):
    torch.manual_seed(SEED); np.random.seed(SEED)
    m = CA(L, K, depth, width).to(DEV)
    opt = torch.optim.Adam(m.parameters(), lr=LR, weight_decay=1e-5)
    best, bad, patience = 1e18, 0, 25
    for ep in range(EPOCHS):
        m.train(); opt.zero_grad()
        loss = 0.0
        for mo in train_m:
            rhat, _, _ = m.month(mo["Z"], mo["r"])
            loss = loss + ((mo["r"] - rhat) ** 2).mean()
        loss = loss / max(len(train_m), 1)
        loss.backward(); opt.step()
        v = loss.item()
        if v < best - 1e-8: best, bad = v, 0
        else: bad += 1
        if bad >= patience: break
    # premia fbar from train
    m.eval()
    with torch.no_grad():
        fbar = torch.stack([m.month(mo["Z"], mo["r"])[2] for mo in train_m]).mean(0)
    return m, fbar, best


def score_block(m, fbar, block):
    rows, ics = [], []
    with torch.no_grad():
        for mo in block:
            beta = m.beta(mo["Z"])
            sc = (beta @ fbar).cpu().numpy()
            rr = mo["r"].cpu().numpy()
            if len(rr) >= 10:
                ic = spearmanr(sc, rr).correlation
                if ic == ic: ics.append(ic)
            for tk, s in zip(mo["tk"], sc):
                rows.append((mo["date"], tk, float(s)))
    return rows, ics


def run_config(months, L, cfg):
    tag, depth, K, width = cfg["tag"], cfg["depth"], cfg["K"], cfg.get("width", 32)
    print(f"[ca:{tag}] depth={depth} K={K} width={width} walk-forward ...", flush=True)
    t0 = time.time()
    rows, ics = [], []
    i = MIN_TRAIN
    n = len(months)
    while i < n:
        train_m = months[:i]                 # expanding, strictly-before (PIT)
        block = months[i:i + REFIT]
        m, fbar, mse = fit(train_m, L, K, depth, width)
        r_b, ic_b = score_block(m, fbar, block)
        rows += r_b; ics += ic_b
        print(f"[ca:{tag}] trained on {len(train_m)}m -> scored {len(block)}m "
              f"(through {block[-1]['ym']}) train_mse={mse:.5f}", flush=True)
        i += REFIT
    sc = pd.DataFrame(rows, columns=["Date", "Ticker", "score"])
    sc.to_parquet(f"{OUT}/ca_scores_{tag}.parquet", index=False)
    ics = np.array(ics)
    diag = {"tag": tag, "depth": depth, "K": K, "width": width, "L": L,
            "n_oos_months": int(sc["Date"].nunique()),
            "oos_rank_ic_mean": float(np.nanmean(ics)) if len(ics) else None,
            "oos_icir": float(np.nanmean(ics) / (np.nanstd(ics) + 1e-9)) if len(ics) else None,
            "elapsed_s": round(time.time() - t0, 1), "device": DEV}
    print(f"[ca:{tag}] DONE {json.dumps(diag)}", flush=True)
    return diag


def main():
    df, chars = load_panel()
    L = len(chars)
    months = to_months(df, chars)
    print(f"[ca] panel: {len(df)} rows, {len(months)} months, L={L} chars, "
          f"date {df['Date'].min().date()}..{df['Date'].max().date()}", flush=True)
    diags = [run_config(months, L, cfg) for cfg in CONFIGS]
    json.dump({"chars": chars, "configs": diags,
               "panel": PANEL, "min_train": MIN_TRAIN, "refit": REFIT},
              open(f"{OUT}/ca_diag.json", "w"), indent=2, default=str)
    print("[ca] ALL DONE -> " + f"{OUT}/ca_diag.json", flush=True)


if __name__ == "__main__":
    main()
