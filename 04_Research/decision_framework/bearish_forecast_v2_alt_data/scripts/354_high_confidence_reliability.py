#!/usr/bin/env python3
"""354_high_confidence_reliability.py — 도훈 mandate "고확률 = 고신뢰" 자가발전

발견 (353):
  T5 rank 1 (prob 0.93) → 실제 아님 ❌ — 극단 overconfident
  T5 Top 1 = 0/1 (0%) but Top 3 = 2/3 (67%) — calibration 깨짐

3 path 동시 측정:
  A. Reliability diagnostic — current ECE / Brier / reliability diagram
  B. Isotonic calibration — OOS 절반으로 calibration fit + 나머지 holdout eval
  C. Consensus rule — P_consensus = P_T5 if (count(P_base > thr) >= K) else damp

각 방법 Top N precision + calibration metric 측정.

Output: outputs/04_evaluation/cycle58dd_high_conf_reliability.json
"""
import os
os.environ['CUBLAS_WORKSPACE_CONFIG'] = ':4096:8'
import json
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.isotonic import IsotonicRegression
from sklearn.metrics import brier_score_loss, average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
EVAL = WS / "outputs/04_evaluation"
OUT = EVAL / "cycle58dd_high_conf_reliability.json"
PRETRAIN_DIR = WS / "outputs/03_models/timemae_pretrain_per_year"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)
TEST_START = pd.Timestamp("2018-01-01")
SEQ_LEN = 21
D_MODEL = 64; N_HEADS = 4; N_LAYERS = 2; DROPOUT = 0.10

andreou_json = json.loads((EVAL / "cycle58dd_phase3_3_andreou.json").read_text())
andreou_preds = {pd.Timestamp(k): float(v) for k, v in andreou_json['predictions'].items()}


class TimeMAEEncoder(nn.Module):
    def __init__(self, n_features, d_model=D_MODEL, n_heads=N_HEADS, n_layers=N_LAYERS, dropout=DROPOUT, seq_len=SEQ_LEN):
        super().__init__()
        self.input_proj = nn.Linear(n_features, d_model); self.input_norm = nn.LayerNorm(d_model)
        self.pos_emb = nn.Parameter(torch.zeros(1, seq_len, d_model))
        self.mask_token = nn.Parameter(torch.zeros(1, 1, d_model))
        layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=n_heads,
            dim_feedforward=d_model * 4, dropout=dropout, batch_first=True,
            activation='gelu', norm_first=True)
        self.encoder = nn.TransformerEncoder(layer, num_layers=n_layers); self.enc_norm = nn.LayerNorm(d_model)
        self.recon_head = nn.Sequential(nn.Linear(d_model, d_model * 2), nn.GELU(), nn.Dropout(dropout),
            nn.Linear(d_model * 2, n_features))
    def encode(self, x):
        h = self.input_proj(x); h = self.input_norm(h); h = h + self.pos_emb
        h = self.encoder(h); h = self.enc_norm(h)
        return h

class BearClassifier(nn.Module):
    def __init__(self, encoder, d_model, dropout=0.20):
        super().__init__()
        self.encoder = encoder; self.dropout = nn.Dropout(dropout)
        self.head = nn.Sequential(nn.LayerNorm(d_model), nn.Linear(d_model, d_model // 2),
            nn.GELU(), nn.Dropout(dropout), nn.Linear(d_model // 2, 1))
    def forward(self, x):
        h = self.encoder.encode(x); h = h.mean(dim=1); h = self.dropout(h)
        return self.head(h).squeeze(-1)


# Load
feat = pd.read_parquet(DATA / "feature_panel_v5g_cross_market.parquet")
feat['Date'] = pd.to_datetime(feat['Date']); feat = feat.sort_values('Date').reset_index(drop=True)
feat_cols = [c for c in feat.columns if c != 'Date']
feat[feat_cols] = feat[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
feat_X_raw = feat[feat_cols].values

m = pd.read_parquet(DATA / "monthly_features.parquet")
m['Date'] = pd.to_datetime(m['Date'])
m = m.dropna(subset=['y_tail_q15']).reset_index(drop=True)
m_feat_cols = [c for c in m.columns if c not in ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']]
m[m_feat_cols] = m[m_feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)

seqs_raw = []; ys = []; dates = []; m_rows = []
for _, row in m.iterrows():
    ms = row['Date']; cut = ms - pd.Timedelta(days=1)
    cut_idx = (feat['Date'] <= cut).sum() - 1
    if cut_idx + 1 < SEQ_LEN: continue
    seq = feat_X_raw[cut_idx - SEQ_LEN + 1 : cut_idx + 1]
    if seq.shape != (SEQ_LEN, len(feat_cols)): continue
    seqs_raw.append(seq); ys.append(row['y_tail_q15']); dates.append(ms)
    m_rows.append(row[m_feat_cols].values)
X_seq_raw = np.array(seqs_raw, dtype=np.float32)
X_mon = np.array(m_rows, dtype=np.float32)
y = np.array(ys, dtype=np.float32)
dates = pd.to_datetime(dates)
test_idx = np.where(dates >= TEST_START)[0]

# HGB monthly
p_hgb = []; y_hgb = []; d_hgb = []
for i in test_idx:
    tr = np.arange(0, i)
    if y[tr].sum() < 20: continue
    mh = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
        class_weight='balanced', random_state=42)
    mh.fit(X_mon[tr], y[tr])
    p_hgb.append(mh.predict_proba(X_mon[i:i+1])[0, 1])
    y_hgb.append(y[i]); d_hgb.append(dates[i])
p_hgb = np.array(p_hgb); y_hgb = np.array(y_hgb); d_hgb = pd.to_datetime(d_hgb)

# Per-year TimeMAE
def fine_tune(state, n_features, X_tr, y_tr, epochs=30):
    enc = TimeMAEEncoder(n_features=n_features).to(DEVICE)
    enc.load_state_dict(state, strict=True)
    model = BearClassifier(enc, d_model=D_MODEL).to(DEVICE)
    opt = torch.optim.AdamW(model.parameters(), lr=5e-4, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=torch.tensor([min(pos_w, 8.0)], device=DEVICE))
    Xt = torch.from_numpy(X_tr).to(DEVICE); yt = torch.from_numpy(y_tr).to(DEVICE)
    loader = DataLoader(TensorDataset(Xt, yt), batch_size=64, shuffle=True, drop_last=False)
    for _ in range(epochs):
        model.train()
        for xb, yb in loader:
            opt.zero_grad(); loss = loss_fn(model(xb), yb)
            loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        sched.step()
    return model
def predict_t(model, X):
    model.eval()
    with torch.no_grad():
        return torch.sigmoid(model(torch.from_numpy(X).to(DEVICE))).cpu().numpy()

test_dates_s = pd.Series(dates[test_idx])
p_tmae_all = np.full(len(test_idx), np.nan)
for yr in sorted(test_dates_s.dt.year.unique()):
    yr_pos = np.where((test_dates_s.dt.year == yr).values)[0]
    if len(yr_pos) == 0: continue
    first_global = test_idx[yr_pos[0]]
    tr_idx = np.arange(0, first_global)
    if y[tr_idx].sum() < 20: continue
    enc_path = PRETRAIN_DIR / f"timemae_pretrain_v2_{yr}.pt"
    if not enc_path.exists(): continue
    ckpt_yr = torch.load(enc_path, map_location=DEVICE, weights_only=False)
    mu_y = np.array(ckpt_yr['mu']); sd_y = np.array(ckpt_yr['sd'])
    X_seq_std = ((X_seq_raw - mu_y) / sd_y).astype(np.float32)
    model = fine_tune(ckpt_yr['state_dict'], len(feat_cols), X_seq_std[tr_idx], y[tr_idx])
    p_tmae_all[yr_pos] = predict_t(model, X_seq_std[test_idx[yr_pos]])

common_dates = pd.Series(d_hgb)
test_dates_arr = test_dates_s.values
tmae_align = np.full(len(common_dates), np.nan)
andr_align = np.full(len(common_dates), np.nan)
for i, d in enumerate(common_dates):
    test_pos = np.where(test_dates_arr == d.to_numpy())[0]
    if len(test_pos) > 0: tmae_align[i] = p_tmae_all[test_pos[0]]
    if d in andreou_preds: andr_align[i] = andreou_preds[d]
mask = ~np.isnan(tmae_align) & ~np.isnan(andr_align)
p_hgb_f = p_hgb[mask]; p_tmae_f = tmae_align[mask]; p_andr_f = andr_align[mask]
y_f = y_hgb[mask].astype(int); d_f = pd.Series(d_hgb)[mask].reset_index(drop=True)
n = len(y_f); base = y_f.mean()
p_t5 = 2/3 * p_hgb_f + 1/3 * np.maximum(p_tmae_f, p_andr_f)
print(f"[Setup] n={n}, 실제 약세 {int(y_f.sum())}건 (base {base*100:.1f}%)")


# === A. Reliability diagnostic ===
def reliability_diagram(p, y, n_bins=10):
    """Bin predictions, compute observed precision per bin. ECE 계산."""
    bins = np.linspace(0, 1, n_bins + 1)
    rows = []
    ece = 0.0
    n_total = len(y)
    for i in range(n_bins):
        lo = bins[i]; hi = bins[i + 1]
        in_bin = (p >= lo) & (p <= hi if i == n_bins - 1 else p < hi)
        n_bin = in_bin.sum()
        if n_bin == 0:
            rows.append({'lo': lo, 'hi': hi, 'n': 0, 'mean_pred': None, 'observed_freq': None})
            continue
        mean_pred = p[in_bin].mean()
        observed = y[in_bin].mean()
        rows.append({'lo': float(lo), 'hi': float(hi), 'n': int(n_bin),
                     'mean_pred': float(mean_pred), 'observed_freq': float(observed)})
        ece += (n_bin / n_total) * abs(mean_pred - observed)
    return rows, float(ece)


def brier(p, y):
    return float(brier_score_loss(y, p))


print("\n=== [A] Reliability diagnostic (10-bin) ===")
print(f"{'Model':<18s} {'ECE':>8s} {'Brier':>8s} {'BrierRand':>10s}")
diagnostics = {}
brier_random = base * (1 - base)  # Brier of constant base rate predictor
for name, p in [('HGB', p_hgb_f), ('TimeMAE', p_tmae_f), ('Andreou', p_andr_f), ('T5', p_t5)]:
    diag, ece = reliability_diagram(p, y_f)
    br = brier(p, y_f)
    diagnostics[name] = {'reliability_diagram': diag, 'ece': ece, 'brier': br,
                          'brier_baseline': float(brier_random)}
    flag = '⭐' if br < brier_random else '⚠️'
    print(f"  {name:<18s} {ece:>8.4f} {br:>8.4f} {brier_random:>10.4f} {flag}")

# Show reliability bins for T5
print(f"\n[T5 reliability diagram]")
print(f"{'Bin':<10s} {'n':>4s} {'mean_pred':>10s} {'observed':>10s} {'gap':>8s}")
for r in diagnostics['T5']['reliability_diagram']:
    if r['n'] == 0: continue
    gap = r['mean_pred'] - r['observed_freq']
    print(f"  [{r['lo']:.1f},{r['hi']:.1f}] {r['n']:>4d} {r['mean_pred']:>9.3f} {r['observed_freq']:>9.3f} {gap:>+7.3f}")


# === B. Isotonic calibration ===
# Split OOS into calibration (first 50%) and holdout (last 50%) — temporal
print("\n=== [B] Isotonic calibration (temporal split: first 50% calib, last 50% test) ===")
split = n // 2
cal_idx = np.arange(0, split); hold_idx = np.arange(split, n)
y_cal = y_f[cal_idx]; y_hold = y_f[hold_idx]
d_hold = d_f.iloc[hold_idx].reset_index(drop=True)
print(f"  Calib: {len(cal_idx)} months (실제 {int(y_cal.sum())}건), Hold: {len(hold_idx)} months (실제 {int(y_hold.sum())}건)")

calibrators = {}
calib_results = {}
for name, p in [('HGB', p_hgb_f), ('TimeMAE', p_tmae_f), ('Andreou', p_andr_f), ('T5', p_t5)]:
    p_cal = p[cal_idx]
    p_hold_raw = p[hold_idx]
    if len(np.unique(y_cal)) < 2:
        print(f"  {name}: only 1 class in calib, skip")
        continue
    iso = IsotonicRegression(out_of_bounds='clip')
    iso.fit(p_cal, y_cal)
    p_hold_cal = iso.predict(p_hold_raw)
    calibrators[name] = iso
    # Eval on holdout
    pr_raw = average_precision_score(y_hold, p_hold_raw) if y_hold.sum() > 0 else np.nan
    pr_cal = average_precision_score(y_hold, p_hold_cal) if y_hold.sum() > 0 else np.nan
    br_raw = brier(p_hold_raw, y_hold); br_cal = brier(p_hold_cal, y_hold)
    diag_raw, ece_raw = reliability_diagram(p_hold_raw, y_hold)
    diag_cal, ece_cal = reliability_diagram(p_hold_cal, y_hold)
    calib_results[name] = {'pr_raw': float(pr_raw), 'pr_cal': float(pr_cal),
                            'brier_raw': float(br_raw), 'brier_cal': float(br_cal),
                            'ece_raw': float(ece_raw), 'ece_cal': float(ece_cal)}
    print(f"  {name:<10s}: PR raw {pr_raw:.4f} → cal {pr_cal:.4f}  |  Brier {br_raw:.4f}→{br_cal:.4f}  |  ECE {ece_raw:.4f}→{ece_cal:.4f}")

# Top N on holdout (raw vs calibrated)
print(f"\n[Top N on holdout, raw vs calibrated]")
def topn(p, y, N):
    if N > len(y): return None
    order = np.argsort(-p)
    tp = int(y[order[:N]].sum())
    return tp, N, tp / N if N > 0 else 0

print(f"{'Model':<10s} {'Mode':<6s} {'Top1':>10s} {'Top3':>10s} {'Top5':>10s} {'Top7':>10s} {'Top10':>10s}")
topn_results = {}
for name, p in [('HGB', p_hgb_f), ('TimeMAE', p_tmae_f), ('Andreou', p_andr_f), ('T5', p_t5)]:
    if name not in calibrators: continue
    p_hold_raw = p[hold_idx]; p_hold_cal = calibrators[name].predict(p_hold_raw)
    raw_row = {}; cal_row = {}
    print(f"{name:<10s} {'raw':<6s}", end='')
    for N in [1, 3, 5, 7, 10]:
        r = topn(p_hold_raw, y_hold, N)
        if r is None: print(f"  N/A      ", end=''); raw_row[f'top{N}'] = None; continue
        tp, k, prec = r
        print(f"  {tp}/{k} ({prec*100:>3.0f}%)", end='')
        raw_row[f'top{N}'] = {'tp': tp, 'k': k, 'precision': prec}
    print()
    print(f"{name:<10s} {'cal':<6s}", end='')
    for N in [1, 3, 5, 7, 10]:
        r = topn(p_hold_cal, y_hold, N)
        if r is None: print(f"  N/A      ", end=''); cal_row[f'top{N}'] = None; continue
        tp, k, prec = r
        print(f"  {tp}/{k} ({prec*100:>3.0f}%)", end='')
        cal_row[f'top{N}'] = {'tp': tp, 'k': k, 'precision': prec}
    print()
    topn_results[name] = {'raw': raw_row, 'cal': cal_row}


# === C. Consensus rule ===
print("\n=== [C] Multi-model consensus rule ===")
# For each month, count how many of (HGB, TimeMAE, Andreou) exceed threshold
# Sharpen T5 if at least K of 3 agree
thresholds = [0.4, 0.5, 0.6]
consensus_results = {}
for thr in thresholds:
    p_hgb_pos = (p_hgb_f >= thr).astype(int)
    p_tmae_pos = (p_tmae_f >= thr).astype(int)
    p_andr_pos = (p_andr_f >= thr).astype(int)
    agree_count = p_hgb_pos + p_tmae_pos + p_andr_pos  # 0~3
    print(f"\n[threshold = {thr}]")
    print(f"  Agreement distribution: {dict(zip(*np.unique(agree_count, return_counts=True)))}")
    for min_agree in [2, 3]:
        consensus_mask = (agree_count >= min_agree)
        n_pred = int(consensus_mask.sum())
        if n_pred == 0:
            print(f"  min_agree {min_agree}: 0 predictions")
            continue
        n_correct = int(y_f[consensus_mask].sum())
        prec = n_correct / n_pred
        lift = prec / base
        # Precision when consensus fires
        consensus_results[f"thr_{thr}_min_{min_agree}"] = {
            'threshold': thr, 'min_agree': min_agree,
            'n_predictions': n_pred, 'n_correct': n_correct,
            'precision': float(prec), 'lift': float(lift)}
        print(f"  min_agree {min_agree}: {n_correct}/{n_pred} = {prec*100:.1f}% (lift {lift:.2f}x)")

# Also: Consensus-weighted T5
# Multiplier: 1 if all 3 agree (above their median), 0.5 otherwise — damp uncertain predictions
print(f"\n[Consensus-weighted T5 (damp when models disagree)]")
hgb_med = np.median(p_hgb_f); tmae_med = np.median(p_tmae_f); andr_med = np.median(p_andr_f)
hgb_above = (p_hgb_f > hgb_med).astype(int)
tmae_above = (p_tmae_f > tmae_med).astype(int)
andr_above = (p_andr_f > andr_med).astype(int)
agree_strong = hgb_above + tmae_above + andr_above  # 0~3
# Damping: 3-agree → 1.0, 2-agree → 0.7, 1-agree → 0.4, 0-agree → 0.1
damp_factor = np.where(agree_strong == 3, 1.0,
              np.where(agree_strong == 2, 0.7,
              np.where(agree_strong == 1, 0.4, 0.1)))
p_t5_damp = p_t5 * damp_factor
# Top N precision
print(f"{'Variant':<25s} Top1 Top3 Top5 Top7 Top10")
for name, p in [('T5 raw', p_t5), ('T5 damped (consensus)', p_t5_damp)]:
    print(f"{name:<25s}", end='')
    for N in [1, 3, 5, 7, 10]:
        r = topn(p, y_f, N)
        if r is None: print(" N/A", end=''); continue
        tp, k, prec = r
        print(f" {tp}/{k}({prec*100:.0f}%)", end='')
    print()

# Save
def conv(o):
    if isinstance(o, dict): return {k: conv(v) for k, v in o.items()}
    if isinstance(o, list): return [conv(x) for x in o]
    if isinstance(o, (np.floating, np.float32, np.float64)): return float(o)
    if isinstance(o, (np.integer, np.int32, np.int64)): return int(o)
    return o

audit = {
    'cycle': '58DD_high_confidence_reliability',
    'n_oos': int(n), 'base': float(base),
    'A_reliability_diagnostic': conv(diagnostics),
    'B_isotonic_calibration_temporal_split': conv({'calib_pr_ece_brier': calib_results, 'top_n_holdout': topn_results}),
    'C_consensus_rule': conv(consensus_results),
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
