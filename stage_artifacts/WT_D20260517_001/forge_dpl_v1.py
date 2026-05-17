"""WT-D20260517_001 Forge — DPL_KR_v1 Train + Walk-forward + 9 Artifact emission.

Author: Forge agent (Q-Lead spawn 2026-05-17)
Architecture: dpl_architecture.md (Transformer-lite ~165K params, cross-section attention)
Protocol: training_protocol.md (Option B-modified 5 overlapping shift-12m walk-forward)
PIT compliance: C1~C15 strict. features t-1, target t+1, lockbox per window.
"""
from __future__ import annotations
import os, sys, json, time, hashlib, math, traceback
from pathlib import Path
from datetime import date, datetime, timedelta
import numpy as np
import pandas as pd
import pyarrow.parquet as pq
import pyarrow as pa
import torch
import torch.nn as nn
import torch.nn.functional as F

# ───────────────────────────────────────────────────────────────────────
# Paths
# ───────────────────────────────────────────────────────────────────────
ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WT = "WT-D20260517_001"
STAGE = ROOT / "stage_artifacts" / "WT_D20260517_001"
MAILBOX = ROOT / "qepm" / "mailbox" / "worktask" / WT

FEATURES_MASTER = ROOT / "stage_artifacts" / "WT_D20260514_008" / "features_master.parquet"
ALLOWLIST_PATH = STAGE / "feature_allowlist.csv"
RAWDATA_PATH = ROOT / ".cache" / "rawdata.parquet"

LOG_DIR = STAGE / "logs"
LOG_DIR.mkdir(exist_ok=True)
CKPT_DIR = STAGE / "checkpoints"
CKPT_DIR.mkdir(exist_ok=True)
SIGMA_DIR = STAGE / "sigma_per_sigdate"
SIGMA_DIR.mkdir(exist_ok=True)

OUT_FEATURES_FILTERED = STAGE / "features_filtered.parquet"
OUT_WEIGHTS = STAGE / "weights.csv"
OUT_ALPHA_SCORES = STAGE / "alpha_scores.parquet"
OUT_COV = STAGE / "covariance.parquet"
OUT_FMP_B = STAGE / "FMP_implicit_B_per_feature.parquet"
OUT_TAIL_RISK = STAGE / "tail_risk.json"
OUT_CROWDING = STAGE / "crowding_summary.json"
OUT_DPL_RISK_ATTR = STAGE / "dpl_risk_attribution.json"
OUT_SCENARIO = STAGE / "scenario_admission_measurements.json"
OUT_SAME_HARNESS = STAGE / "same_harness_comparison.json"
OUT_OPT_COMPARE = STAGE / "optimizer_comparison.parquet"
OUT_DECISION_GATES = STAGE / "decision_gates_measurement.json"
OUT_LOOKAHEAD = STAGE / "lookahead_scan.json"
OUT_MODEL = STAGE / "dpl_model.pt"
OUT_FORGE_LOG = STAGE / "forge_run_log.json"

# ───────────────────────────────────────────────────────────────────────
# Logger
# ───────────────────────────────────────────────────────────────────────
LOG_FILE = LOG_DIR / f"forge_dpl_v1_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

def log(msg: str):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

# ───────────────────────────────────────────────────────────────────────
# Constants
# ───────────────────────────────────────────────────────────────────────
K_TOP = 20
W_MAX = 0.20
W_MIN = 0.0
LIQ_PROD_THRESHOLD = 2e8  # 2e8 KRW 20d ADV alpha-emit strict
COST_BPS = 0.0015  # 15bps one-way
SEED = 42

# DPL_KR_v1 architecture
D_MODEL = 64
N_HEADS = 2
N_LAYERS = 2
DROPOUT = 0.3
LR = 1e-4
WEIGHT_DECAY = 1e-4
EPOCHS_MAX = 30  # reduced from 50 for time budget
PATIENCE = 5
TAU_INIT = 1.0
TAU_MIN = 0.1
GAMMA_COST = 1.0
LAMBDA_CVAR = 0.5
BATCH_MONTHS = 12  # sig_dates per batch

# Walk-forward windows (Option B-modified)
WINDOWS = [
    # (train_start, train_end, val_start, val_end, test_start, test_end)
    ("2016-01-01", "2020-12-31", "2021-01-01", "2021-12-31", "2022-01-01", "2022-12-31"),
    ("2017-01-01", "2021-12-31", "2022-01-01", "2022-12-31", "2023-01-01", "2023-12-31"),
    ("2018-01-01", "2022-12-31", "2023-01-01", "2023-12-31", "2024-01-01", "2024-12-31"),
    ("2019-01-01", "2023-12-31", "2024-01-01", "2024-12-31", "2025-01-01", "2025-12-31"),
    ("2020-01-01", "2024-12-31", "2025-01-01", "2025-12-31", "2026-01-01", "2026-04-30"),
]

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


# ───────────────────────────────────────────────────────────────────────
# DPL_KR_v1 Model
# ───────────────────────────────────────────────────────────────────────
class DPL_KR_v1(nn.Module):
    def __init__(self, n_features: int, d_model: int = D_MODEL, n_heads: int = N_HEADS,
                 n_layers: int = N_LAYERS, dropout: float = DROPOUT):
        super().__init__()
        self.embed = nn.Linear(n_features, d_model)
        self.embed_ln = nn.LayerNorm(d_model)
        self.dropout = nn.Dropout(dropout)
        enc_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=n_heads, dim_feedforward=4 * d_model,
            dropout=dropout, activation="gelu", batch_first=True, norm_first=True,
        )
        self.encoder = nn.TransformerEncoder(enc_layer, num_layers=n_layers)
        self.score_head = nn.Linear(d_model, 1)

    def forward(self, X):
        # X: (N, F) single sig_date cross-section
        h = self.dropout(self.embed_ln(self.embed(X)))
        # treat sig_date cross-section as one sequence (1, N, d_model)
        h = h.unsqueeze(0)
        h = self.encoder(h)
        h = h.squeeze(0)  # (N, d_model)
        s = self.score_head(h).squeeze(-1)  # (N,)
        return s


# ───────────────────────────────────────────────────────────────────────
# Constraint Projection (4-stage with iterative fix for non-idempotency)
# ───────────────────────────────────────────────────────────────────────
def constraint_projection(scores: torch.Tensor, tau: float, k: int = K_TOP,
                          w_max: float = W_MAX, hard: bool = False,
                          max_iter: int = 3) -> torch.Tensor:
    """4-stage projection. scores: (N,) raw. Returns: w (N,) feasible."""
    # Stage 1: Long-only ReLU
    s = F.relu(scores)
    eps = 1e-10
    # Stage 2: Top-K via differentiable selection
    n = s.shape[0]
    if n <= k:
        # all selected
        y = s + eps
    else:
        # Use top-k mask via Gumbel softmax sampling (k iterations)
        # Implementation: log(s + eps) + Gumbel noise / tau, then argmax k times
        log_s = torch.log(s + eps)
        if hard:
            # eval mode: hard top-K
            topk_idx = torch.topk(s, k=k).indices
            mask = torch.zeros_like(s)
            mask[topk_idx] = 1.0
            y = s * mask
        else:
            # training mode: Gumbel softmax k passes (stochastic top-k)
            # Use a simpler approach: temperature-controlled softmax + top-k mask STE
            # Forward: hard top-k mask. Backward: gradient via soft logits.
            soft_w = F.softmax(log_s / tau, dim=0)
            topk_idx = torch.topk(s, k=k).indices
            mask = torch.zeros_like(s)
            mask[topk_idx] = 1.0
            # STE: forward uses mask, backward uses soft_w gradient
            y = soft_w + (s * mask - soft_w).detach()
            # ensure non-negative (soft_w is ≥ 0 anyway)
            y = F.relu(y)

    # Iterative projection (Stage 3-4): clip + normalize, up to max_iter
    w = y
    for _ in range(max_iter):
        # Stage 3: bounds clip
        w = torch.clamp(w, min=W_MIN, max=w_max)
        # Stage 4: L1 normalize
        s_sum = w.sum()
        if s_sum < 1e-8:
            # fallback: EW over top-k (in eval mode)
            topk_idx = torch.topk(scores, k=k).indices
            w = torch.zeros_like(scores)
            w[topk_idx] = 1.0 / k
            return w
        w = w / s_sum
        # check feasibility
        if (w <= w_max + 1e-6).all() and (w >= -1e-6).all() and abs(w.sum().item() - 1.0) < 1e-6:
            break
    # final clip + renormalize (safety)
    w = torch.clamp(w, min=W_MIN, max=w_max)
    w = w / w.sum().clamp(min=1e-8)
    return w


# ───────────────────────────────────────────────────────────────────────
# Data loader
# ───────────────────────────────────────────────────────────────────────
def load_allowlist():
    df = pd.read_csv(ALLOWLIST_PATH)
    feats = df["feature_id"].tolist()
    log(f"Loaded allowlist: {len(feats)} features")
    return feats


def filter_features_master(allowlist: list) -> pd.DataFrame:
    """Load features_master, keep only sig_date, Ticker, Sector_Lv2 + allowlist features."""
    log(f"Reading features_master.parquet (~1GB)...")
    t0 = time.time()
    pf = pq.ParquetFile(FEATURES_MASTER)
    all_cols = pf.schema_arrow.names
    keep = ["sig_date", "Ticker", "Sector_Lv2"] + [c for c in allowlist if c in all_cols]
    missing = [c for c in allowlist if c not in all_cols]
    if missing:
        log(f"WARNING: {len(missing)} allowlist features not in master (first 5): {missing[:5]}")
    log(f"Reading {len(keep)} columns of {len(all_cols)} total...")
    tbl = pf.read(columns=keep)
    df = tbl.to_pandas()
    df["sig_date"] = pd.to_datetime(df["sig_date"])
    log(f"Loaded features_master subset: rows={len(df):,} cols={len(df.columns)} elapsed={time.time()-t0:.1f}s")
    return df, keep


def load_rawdata_returns_liq():
    """Compute monthly returns + 20d ADV liquidity per (Ticker, month_end)."""
    log("Loading rawdata.parquet for returns + liquidity...")
    t0 = time.time()
    cols = ["Date", "Ticker", "Close", "Vol", "Size", "AdminStock", "TradingHalt", "UnfaithfulDisc"]
    df = pq.read_table(RAWDATA_PATH, columns=cols).to_pandas()
    df["Date"] = pd.to_datetime(df["Date"])
    log(f"rawdata loaded: rows={len(df):,} elapsed={time.time()-t0:.1f}s")
    return df


def compute_monthly_returns_panel(raw: pd.DataFrame, sig_dates: list) -> pd.DataFrame:
    """For each (Ticker, sig_date_t), compute return from sig_date_t to sig_date_{t+1} (close-to-close)."""
    sig_dates_sorted = sorted(sig_dates)
    raw = raw.sort_values(["Ticker", "Date"]).reset_index(drop=True)
    # for each sig_date, find closest Date <= sig_date close
    out_rows = []
    # Build map sig_date -> next sig_date
    sd_arr = np.array([pd.Timestamp(d) for d in sig_dates_sorted])
    # find closest trade date per ticker per sig_date
    log("Building close prices per sig_date per ticker...")
    # for memory efficiency, we use merge_asof
    close_panel = raw[["Date", "Ticker", "Close"]].dropna(subset=["Close"])
    close_panel = close_panel.sort_values(["Ticker", "Date"])
    # merge_asof per sig_date
    sd_df = pd.DataFrame({"sig_date": sd_arr})
    panel_list = []
    for sd in sd_arr:
        sub = close_panel[close_panel["Date"] <= sd].groupby("Ticker", as_index=False).tail(1)
        sub = sub.rename(columns={"Date": "asof_date", "Close": "Close_t"})
        sub["sig_date"] = sd
        panel_list.append(sub[["sig_date", "Ticker", "asof_date", "Close_t"]])
    close_at_sd = pd.concat(panel_list, ignore_index=True)
    # sort by sig_date for each ticker, then compute next-month return
    close_at_sd = close_at_sd.sort_values(["Ticker", "sig_date"]).reset_index(drop=True)
    close_at_sd["Close_next"] = close_at_sd.groupby("Ticker")["Close_t"].shift(-1)
    close_at_sd["ret_next_1m"] = close_at_sd["Close_next"] / close_at_sd["Close_t"] - 1
    log(f"Returns panel built: rows={len(close_at_sd):,}")
    return close_at_sd[["sig_date", "Ticker", "ret_next_1m"]]


def compute_liquidity_panel(raw: pd.DataFrame, sig_dates: list) -> pd.DataFrame:
    """For each (Ticker, sig_date), compute 20d trailing ADV (KRW) ending at sig_date close."""
    log("Computing 20d ADV per (sig_date, Ticker)...")
    sd_arr = sorted(sig_dates)
    raw["traded_value"] = raw["Close"] * raw["Vol"]
    raw_sub = raw[["Date", "Ticker", "traded_value", "AdminStock", "TradingHalt", "UnfaithfulDisc"]].copy()
    raw_sub = raw_sub.sort_values(["Ticker", "Date"]).reset_index(drop=True)

    panel_list = []
    for sd in sd_arr:
        # 20 trading days <= sd
        start = sd - pd.Timedelta(days=40)  # buffer for ~20 trading days
        sub = raw_sub[(raw_sub["Date"] <= sd) & (raw_sub["Date"] > start)].copy()
        # last 20 days per ticker
        sub = sub.sort_values(["Ticker", "Date"]).groupby("Ticker").tail(20)
        adv = sub.groupby("Ticker", as_index=False).agg(
            adv20=("traded_value", "mean"),
            n_days=("traded_value", "size"),
            admin_max=("AdminStock", "max"),
            halt_max=("TradingHalt", "max"),
            unfaith_max=("UnfaithfulDisc", "max"),
        )
        adv["sig_date"] = sd
        panel_list.append(adv)
    out = pd.concat(panel_list, ignore_index=True)
    out = out[["sig_date", "Ticker", "adv20", "n_days", "admin_max", "halt_max", "unfaith_max"]]
    log(f"Liquidity panel built: rows={len(out):,}")
    return out


def load_bm_returns(raw: pd.DataFrame, sig_dates: list) -> pd.DataFrame:
    """Compute KOSPI200 total return per sig_date_t → sig_date_{t+1}.
    Approximation: use K200=1 (cap-weighted index proxy). Use equal-weighted average of K200 names
    as benchmark proxy if K200 dummy reliable.
    """
    log("Building KOSPI200 benchmark returns proxy...")
    sd_arr = sorted(sig_dates)
    # use Size-weighted average return of K200=1 names per month
    raw["Date_M"] = pd.to_datetime(raw["Date"]).dt.to_period("M").dt.to_timestamp("M")
    # get last day of each month
    bm_data = []
    for sd in sd_arr:
        prev_sd = max([d for d in sd_arr if d < sd], default=None)
        if prev_sd is None:
            bm_data.append({"sig_date": sd, "bm_ret_next_1m": np.nan})
            continue
    # Better: use BM_Ret if available, otherwise cap-weighted close ret of K200=1 stocks per sig_date
    # use Close-to-close per K200 names, then size-weighted
    log("Using cap-weighted K200=1 close-to-close returns per month...")
    raw_k = raw[(raw["K200"] == 1) if "K200" in raw.columns else raw["Ticker"].notna()].copy()
    return _build_bm_proxy(raw, sd_arr)


def _build_bm_proxy(raw: pd.DataFrame, sd_arr: list) -> pd.DataFrame:
    """KOSPI200 monthly return proxy: size-weighted next-month close-to-close of K200=1 stocks."""
    rows = []
    has_k200 = "K200" in raw.columns
    close_panel = raw[["Date", "Ticker", "Close", "Size"] + (["K200"] if has_k200 else [])].dropna(subset=["Close"])
    close_panel = close_panel.sort_values(["Ticker", "Date"]).reset_index(drop=True)
    # per sig_date, closest Date <= sig_date
    for i, sd in enumerate(sd_arr):
        if i == len(sd_arr) - 1:
            rows.append({"sig_date": sd, "bm_ret_next_1m": np.nan})
            continue
        sd_next = sd_arr[i + 1]
        sub_t = close_panel[close_panel["Date"] <= sd].groupby("Ticker", as_index=False).tail(1)
        sub_t1 = close_panel[close_panel["Date"] <= sd_next].groupby("Ticker", as_index=False).tail(1)
        sub_t = sub_t.rename(columns={"Close": "Close_t", "Size": "Size_t"})
        sub_t1 = sub_t1.rename(columns={"Close": "Close_t1"})
        if has_k200:
            sub_t = sub_t[sub_t["K200"] == 1]
        merged = sub_t.merge(sub_t1[["Ticker", "Close_t1"]], on="Ticker", how="inner")
        merged["ret"] = merged["Close_t1"] / merged["Close_t"] - 1
        merged = merged.dropna(subset=["ret", "Size_t"])
        if len(merged) == 0:
            rows.append({"sig_date": sd, "bm_ret_next_1m": np.nan})
            continue
        merged["w"] = merged["Size_t"] / merged["Size_t"].sum()
        bm_ret = (merged["w"] * merged["ret"]).sum()
        rows.append({"sig_date": sd, "bm_ret_next_1m": bm_ret})
    return pd.DataFrame(rows)


# ───────────────────────────────────────────────────────────────────────
# Per-sig-date Z-score winsorize
# ───────────────────────────────────────────────────────────────────────
def preprocess_sig_date(df_sd: pd.DataFrame, feature_cols: list) -> pd.DataFrame:
    """Per sig_date: median impute → 1-99 winsorize → cross-section Z-score."""
    Xf = df_sd[feature_cols].copy()
    # median impute per column
    med = Xf.median(numeric_only=True, skipna=True)
    Xf = Xf.fillna(med)
    Xf = Xf.fillna(0.0)  # any remaining (all-NaN columns)
    # winsorize
    q1 = Xf.quantile(0.01)
    q99 = Xf.quantile(0.99)
    Xf = Xf.clip(lower=q1, upper=q99, axis=1)
    # z-score
    mu = Xf.mean()
    sd = Xf.std().replace(0, 1.0).fillna(1.0)
    Xf = (Xf - mu) / sd
    Xf = Xf.fillna(0.0)
    return Xf


# ───────────────────────────────────────────────────────────────────────
# Training loop
# ───────────────────────────────────────────────────────────────────────
def get_window_data(features_df: pd.DataFrame, returns_panel: pd.DataFrame,
                    liq_panel: pd.DataFrame, feature_cols: list,
                    start: str, end: str, liq_strict: float = LIQ_PROD_THRESHOLD):
    """Per-window data slice: list of (sig_date, X_tensor, ret_vec, ticker_list)."""
    start = pd.Timestamp(start)
    end = pd.Timestamp(end)
    sds = sorted(features_df[(features_df["sig_date"] >= start) &
                              (features_df["sig_date"] <= end)]["sig_date"].unique())
    out = []
    for sd in sds:
        # join features + liq + ret
        f_sd = features_df[features_df["sig_date"] == sd].copy()
        l_sd = liq_panel[liq_panel["sig_date"] == sd]
        r_sd = returns_panel[returns_panel["sig_date"] == sd]
        merged = f_sd.merge(l_sd[["Ticker", "adv20", "admin_max", "halt_max", "unfaith_max"]],
                            on="Ticker", how="left")
        merged = merged.merge(r_sd[["Ticker", "ret_next_1m"]], on="Ticker", how="left")
        # liquidity + admin filter
        merged = merged[
            (merged["adv20"] >= liq_strict) &
            (merged["admin_max"].fillna(0) == 0) &
            (merged["halt_max"].fillna(0) == 0) &
            (merged["unfaith_max"].fillna(0) == 0)
        ].copy()
        if len(merged) < 50:
            log(f"  sig_date={sd.date()} only {len(merged)} eligible after LIQ filter — skip")
            continue
        Xf = preprocess_sig_date(merged, feature_cols)
        # mask: must have non-NaN return
        ret = merged["ret_next_1m"].values
        mask = ~np.isnan(ret)
        if mask.sum() < 50:
            continue
        Xf = Xf.iloc[mask].reset_index(drop=True)
        merged_kept = merged.iloc[mask].reset_index(drop=True)
        ret = ret[mask]
        X_t = torch.tensor(Xf.values, dtype=torch.float32, device=device)
        ret_t = torch.tensor(ret, dtype=torch.float32, device=device)
        out.append({
            "sig_date": sd,
            "X": X_t,
            "ret": ret_t,
            "tickers": merged_kept["Ticker"].tolist(),
        })
    return out


def compute_loss(model: nn.Module, window: list, tau: float,
                 gamma_cost: float = GAMMA_COST,
                 lambda_cvar: float = LAMBDA_CVAR,
                 prev_w_state: dict = None,
                 train_mode: bool = True) -> tuple:
    """One pass over a window: compute -E[r_p] + gamma·cost + lambda·CVaR penalty."""
    rets_list = []
    to_list = []
    weights_dict = {}
    for sd_data in window:
        sd = sd_data["sig_date"]
        X = sd_data["X"]
        r = sd_data["ret"]
        tickers = sd_data["tickers"]
        scores = model(X)
        w = constraint_projection(scores, tau=tau, hard=(not train_mode))
        # portfolio return next-period
        r_p = (w * r).sum()
        rets_list.append(r_p)
        # turnover (using previous weights if available)
        if prev_w_state is not None and "w_prev" in prev_w_state and prev_w_state["w_prev"] is not None:
            prev_w = prev_w_state["w_prev"]
            prev_tickers = prev_w_state["tickers_prev"]
            # align
            curr_w_aligned = {tickers[i]: w[i] for i in range(len(tickers))}
            prev_w_aligned = {prev_tickers[i]: prev_w[i] for i in range(len(prev_tickers))}
            all_t = set(curr_w_aligned.keys()) | set(prev_w_aligned.keys())
            to_val = torch.tensor(0.0, device=device)
            for t_ in all_t:
                cw = curr_w_aligned.get(t_, torch.tensor(0.0, device=device))
                pw = prev_w_aligned.get(t_, torch.tensor(0.0, device=device))
                to_val = to_val + torch.abs(cw - pw)
            to_list.append(to_val)
        if prev_w_state is not None:
            prev_w_state["w_prev"] = w.detach()
            prev_w_state["tickers_prev"] = tickers
        weights_dict[sd] = {"w": w.detach().cpu().numpy(), "tickers": tickers,
                            "scores": scores.detach().cpu().numpy(),
                            "r_p": r_p.detach().cpu().item(),
                            "r_actual": r.cpu().numpy()}
    if not rets_list:
        return None, None, None
    rets_tensor = torch.stack(rets_list)
    e_rp = rets_tensor.mean()
    if to_list:
        to_mean = torch.stack(to_list).mean()
        cost_penalty = gamma_cost * COST_BPS * to_mean
    else:
        cost_penalty = torch.tensor(0.0, device=device)
    # CVaR_5%
    if len(rets_tensor) >= 20:
        q5 = torch.quantile(rets_tensor, 0.05)
        tail = rets_tensor[rets_tensor <= q5]
        cvar_5 = tail.mean() if len(tail) > 0 else q5
    else:
        cvar_5 = rets_tensor.min()
    # penalty: -lambda · CVaR (CVaR is negative for losses)
    cvar_penalty = -lambda_cvar * cvar_5
    loss = -e_rp + cost_penalty + cvar_penalty
    return loss, weights_dict, {"e_rp": e_rp.item(), "cost": cost_penalty.item(),
                                 "cvar5": cvar_5.item()}


def train_window(window_id: int, train_w: list, val_w: list, test_w: list,
                 n_features: int) -> dict:
    """Train one walk-forward window."""
    log(f"[Window {window_id+1}/5] Training | train_n_sig={len(train_w)} val_n_sig={len(val_w)} test_n_sig={len(test_w)}")
    torch.manual_seed(SEED + window_id * 1000)
    np.random.seed(SEED + window_id * 1000)
    model = DPL_KR_v1(n_features).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)
    best_val_loss = float("inf")
    best_state = None
    patience = 0
    history = []
    for epoch in range(1, EPOCHS_MAX + 1):
        model.train()
        tau = max(TAU_MIN, TAU_INIT - (TAU_INIT - TAU_MIN) * (epoch - 1) / EPOCHS_MAX)
        # split train into batches of BATCH_MONTHS
        train_batches = [train_w[i:i + BATCH_MONTHS] for i in range(0, len(train_w), BATCH_MONTHS)]
        epoch_train_loss = 0.0
        n_batches = 0
        for batch in train_batches:
            if len(batch) < 2:
                continue
            opt.zero_grad()
            prev_state = {"w_prev": None, "tickers_prev": None}
            loss, _, _ = compute_loss(model, batch, tau=tau, prev_w_state=prev_state, train_mode=True)
            if loss is None or torch.isnan(loss) or torch.isinf(loss):
                log(f"  epoch {epoch} batch NaN/Inf — skip")
                continue
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            opt.step()
            epoch_train_loss += loss.item()
            n_batches += 1
        epoch_train_loss = epoch_train_loss / max(n_batches, 1)
        # val
        model.eval()
        with torch.no_grad():
            prev_state = {"w_prev": None, "tickers_prev": None}
            val_loss, _, val_stats = compute_loss(model, val_w, tau=TAU_MIN,
                                                   prev_w_state=prev_state, train_mode=False)
            val_loss = val_loss.item() if val_loss is not None else float("inf")
        history.append({"epoch": epoch, "train_loss": epoch_train_loss,
                        "val_loss": val_loss, "tau": tau,
                        **(val_stats or {})})
        log(f"  epoch {epoch} tau={tau:.3f} train_loss={epoch_train_loss:.6f} val_loss={val_loss:.6f}")
        if val_loss < best_val_loss - 1e-6:
            best_val_loss = val_loss
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            patience = 0
        else:
            patience += 1
            if patience >= PATIENCE:
                log(f"  Early stop @ epoch {epoch} (patience {PATIENCE})")
                break
    # restore best
    if best_state is not None:
        model.load_state_dict(best_state)
    # test
    model.eval()
    with torch.no_grad():
        prev_state = {"w_prev": None, "tickers_prev": None}
        test_loss, test_weights, test_stats = compute_loss(model, test_w, tau=TAU_MIN,
                                                          prev_w_state=prev_state, train_mode=False)
        test_loss = test_loss.item() if test_loss is not None else float("inf")
    log(f"[Window {window_id+1}/5] Done. best_val_loss={best_val_loss:.6f} test_loss={test_loss:.6f}")
    return {
        "window_id": window_id,
        "history": history,
        "best_val_loss": best_val_loss,
        "test_loss": test_loss,
        "test_weights": test_weights,
        "model_state": best_state,
    }


# ───────────────────────────────────────────────────────────────────────
# Main
# ───────────────────────────────────────────────────────────────────────
def main():
    log("=" * 80)
    log(f"WT-D20260517_001 Forge DPL_KR_v1 — START")
    log(f"Device: {device} | torch: {torch.__version__}")
    if device.type == "cuda":
        log(f"GPU: {torch.cuda.get_device_name(0)} | mem: {torch.cuda.get_device_properties(0).total_memory/1e9:.1f} GB")
    log("=" * 80)
    t_start = time.time()
    allowlist = load_allowlist()
    features_df, kept_cols = filter_features_master(allowlist)
    feature_cols = [c for c in kept_cols if c not in ("sig_date", "Ticker", "Sector_Lv2")]
    log(f"Effective feature columns: {len(feature_cols)}")

    # save filtered features
    log(f"Saving features_filtered.parquet (this may take 1-2 min)...")
    features_df.to_parquet(OUT_FEATURES_FILTERED, compression="snappy", index=False)
    log(f"  saved: {OUT_FEATURES_FILTERED}")

    # raw + returns + liquidity
    sig_dates = sorted(features_df["sig_date"].unique())
    log(f"sig_dates total: {len(sig_dates)} | first={sig_dates[0].date()} last={sig_dates[-1].date()}")

    raw = load_rawdata_returns_liq()
    returns_panel = compute_monthly_returns_panel(raw, sig_dates)
    liq_panel = compute_liquidity_panel(raw, sig_dates)
    bm_panel = _build_bm_proxy(raw, sig_dates)
    log(f"BM panel: rows={len(bm_panel)}, mean={bm_panel['bm_ret_next_1m'].mean():.4f}")

    # save bm + returns for later use
    returns_panel.to_parquet(STAGE / "returns_panel.parquet", index=False)
    liq_panel.to_parquet(STAGE / "liq_panel.parquet", index=False)
    bm_panel.to_parquet(STAGE / "bm_panel.parquet", index=False)

    # ── 6.2 DPL training ─────────────────────────────────
    log("=" * 80)
    log("PHASE 6.2 — DPL walk-forward training (5 windows)")
    log("=" * 80)
    window_results = []
    all_test_weights = {}
    for i, (tr_s, tr_e, va_s, va_e, te_s, te_e) in enumerate(WINDOWS):
        log(f"\n── Window {i+1}/5 ──")
        log(f"  train: {tr_s} ~ {tr_e}")
        log(f"  val:   {va_s} ~ {va_e}")
        log(f"  test:  {te_s} ~ {te_e}")
        train_w = get_window_data(features_df, returns_panel, liq_panel, feature_cols, tr_s, tr_e)
        val_w = get_window_data(features_df, returns_panel, liq_panel, feature_cols, va_s, va_e)
        test_w = get_window_data(features_df, returns_panel, liq_panel, feature_cols, te_s, te_e)
        if len(train_w) < 10 or len(val_w) < 3 or len(test_w) < 1:
            log(f"  Window {i+1} INSUFFICIENT DATA — train_n={len(train_w)} val_n={len(val_w)} test_n={len(test_w)}")
            continue
        wr = train_window(i, train_w, val_w, test_w, n_features=len(feature_cols))
        window_results.append(wr)
        for sd, wdat in wr["test_weights"].items():
            all_test_weights[sd] = wdat
        # save checkpoint
        ckpt = CKPT_DIR / f"window_{i+1}.pt"
        torch.save(wr["model_state"], ckpt)
        log(f"  saved ckpt: {ckpt}")
        # GPU clear
        if device.type == "cuda":
            torch.cuda.empty_cache()

    log(f"\nWalk-forward done. n_test_sig_dates_collected={len(all_test_weights)}")

    # save model (last window's best)
    if window_results:
        torch.save({"model_state": window_results[-1]["model_state"],
                    "feature_cols": feature_cols,
                    "config": {
                        "D_MODEL": D_MODEL, "N_HEADS": N_HEADS, "N_LAYERS": N_LAYERS,
                        "DROPOUT": DROPOUT, "LR": LR, "K_TOP": K_TOP, "W_MAX": W_MAX,
                    }}, OUT_MODEL)
        log(f"saved: {OUT_MODEL}")

    elapsed = time.time() - t_start
    log(f"\nFORGE DPL TRAINING DONE | total wall-clock: {elapsed/60:.1f} min ({elapsed/3600:.2f}h)")

    # write training log JSON
    forge_run_log = {
        "wt_id": WT,
        "started_at": datetime.now().isoformat(),
        "device": str(device),
        "n_features": len(feature_cols),
        "n_sig_dates_features_master": len(sig_dates),
        "n_test_sig_dates_collected": len(all_test_weights),
        "hyperparams": {
            "lr": LR, "dropout": DROPOUT, "gamma_cost": GAMMA_COST,
            "lambda_cvar": LAMBDA_CVAR, "tau_min": TAU_MIN, "epochs_max": EPOCHS_MAX,
            "patience": PATIENCE, "batch_months": BATCH_MONTHS,
            "weight_decay": WEIGHT_DECAY,
        },
        "windows": [{"window_id": w["window_id"],
                     "best_val_loss": w["best_val_loss"],
                     "test_loss": w["test_loss"],
                     "n_epochs_trained": len(w["history"]),
                     "history_last": w["history"][-1] if w["history"] else None}
                    for w in window_results],
        "elapsed_min": elapsed / 60,
        "features_filtered_sha256": file_sha256(OUT_FEATURES_FILTERED),
        "features_master_sha256_first8": file_sha256(FEATURES_MASTER)[:16],
    }
    with open(OUT_FORGE_LOG, "w") as f:
        json.dump(forge_run_log, f, indent=2, default=str)
    log(f"saved: {OUT_FORGE_LOG}")
    # Save all_test_weights + window_results for downstream artifact builder
    import pickle
    with open(STAGE / "test_weights.pkl", "wb") as f:
        pickle.dump({"all_test_weights": all_test_weights,
                     "window_results": [{k: v for k, v in w.items() if k != "model_state"} for w in window_results],
                     "bm_panel": bm_panel, "returns_panel": returns_panel,
                     "liq_panel": liq_panel, "feature_cols": feature_cols,
                     "sig_dates": sig_dates}, f)
    log(f"saved: {STAGE / 'test_weights.pkl'}")
    log("PHASE 6.2 DONE.")
    return forge_run_log


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log("FATAL ERROR:")
        log(traceback.format_exc())
        sys.exit(1)
