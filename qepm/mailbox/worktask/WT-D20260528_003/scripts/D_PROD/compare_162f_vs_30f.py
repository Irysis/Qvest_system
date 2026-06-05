#!/usr/bin/env python
"""
WT-D20260528_003 D_PROD — Feature set decision: 162f vs 30f LightGBM
under IDENTICAL EWMA + bandbuffer + net-of-cost overlay (AX-008 verify, no guessing).

Both prediction sets: 40276 rows, 116 sig_dates, identical Ticker/Date/log_ret_1m_w/y_zxs.
Only differ in the LightGBM prediction column.

Overlay (production spec): EWMA α=0.5, keep_n=50, entry_n=20, cooldown=3m,
softmax tau=1.0, weight_cap=0.20, max_names=20.

Metrics computed on same footing for both:
  - IC / ICIR (raw + EWMA-smoothed)
  - net-of-cost annualized Sharpe (15bps one-way * 2-way turnover)
  - turnover/yr
  - DSR proper (Bailey-Lopez de Prado + Mertens higher-moment correction)
  - AX-001 v2 bad/normal IC ratio (KOSPI < -5% crisis dates)

Lockbox: predictions already restricted to <= 2023-12-22 walk-forward (test_end 2023-11-30).
"""

import sys
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import spearmanr, norm

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
DIR_30 = PROJ / 'stage_artifacts' / 'WT_D20260528_003_D_REFINE'
DIR_162 = PROJ / 'stage_artifacts' / 'WT_D20260528_003_D_ENSEMBLE'
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_D_PROD'
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Overlay params (production spec)
EWMA_ALPHA = 0.5
KEEP_N = 50
ENTRY_N = 20
COOLDOWN_MONTHS = 3
SOFTMAX_TAU = 1.0
WEIGHT_CAP = 0.20
MAX_NAMES = 20
N_TRIALS_EFF = 411  # consistent with D_REFINE dsr_proper

sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)
t0 = time.time()


def build_weights(preds, pred_col):
    """Apply EWMA + bandbuffer + cooldown + softmax-cap. Returns weights_df + IC stats."""
    p = preds.copy()
    p['sig_date'] = pd.to_datetime(p['sig_date'])
    p = p.sort_values(['Ticker', 'sig_date']).reset_index(drop=True)
    # EWMA smoothing per ticker
    p['pred_smooth'] = p.groupby('Ticker')[pred_col].transform(
        lambda x: x.ewm(alpha=1 - EWMA_ALPHA, adjust=False).mean())

    # IC raw + smoothed
    ic_raw, ic_smth = [], []
    for sd, grp in p.groupby('sig_date'):
        if grp.shape[0] >= 20:
            ir, _ = spearmanr(grp[pred_col].values, grp['y_zxs'].values)
            isth, _ = spearmanr(grp['pred_smooth'].values, grp['y_zxs'].values)
            if not np.isnan(ir):
                ic_raw.append(ir)
            if not np.isnan(isth):
                ic_smth.append(isth)
    ic_raw = np.array(ic_raw)
    ic_smth = np.array(ic_smth)

    p['pred_final'] = p['pred_smooth']
    sig_dates_sorted = sorted(p['sig_date'].unique())
    prev_holdings = set()
    cooldown_register = {}
    weights_records = []

    for sd in sig_dates_sorted:
        grp = p[p['sig_date'] == sd].copy().sort_values('pred_final', ascending=False).reset_index(drop=True)
        in_cooldown = set()
        for tkr, exit_sd in list(cooldown_register.items()):
            months_since = sum(1 for d in sig_dates_sorted if exit_sd < d <= sd)
            if months_since <= COOLDOWN_MONTHS:
                in_cooldown.add(tkr)
            else:
                del cooldown_register[tkr]
        avail = grp[~grp['Ticker'].isin(in_cooldown)].copy()
        top_keep = set(avail.head(KEEP_N)['Ticker'])
        retained = prev_holdings.intersection(top_keep)
        n_new_needed = MAX_NAMES - len(retained)
        if n_new_needed > 0:
            new_candidates = avail[~avail['Ticker'].isin(retained)].head(MAX_NAMES * 2)
            new_entries = new_candidates.head(n_new_needed)['Ticker'].tolist()
        else:
            new_entries = []
        final_top20 = (list(retained) + new_entries)[:MAX_NAMES]
        final_grp = grp[grp['Ticker'].isin(final_top20)].copy()
        if final_grp.shape[0] == 0:
            continue
        final_grp = final_grp.sort_values('pred_final', ascending=False).reset_index(drop=True)
        pv = final_grp['pred_final'].values
        exp_p = np.exp((pv - pv.max()) / SOFTMAX_TAU)
        w = exp_p / exp_p.sum()
        for _ in range(10):
            cm = w > WEIGHT_CAP
            if not cm.any():
                break
            excess = (w[cm] - WEIGHT_CAP).sum()
            w[cm] = WEIGHT_CAP
            fm = ~cm & (w > 0)
            if fm.sum() > 0:
                w[fm] += excess * (w[fm] / w[fm].sum())
        w = w / w.sum()
        for tkr, weight in zip(final_grp['Ticker'].values, w):
            weights_records.append({'sig_date': sd, 'Ticker': tkr, 'weight': float(weight)})
        cur_holdings = set(final_top20)
        for tkr in (prev_holdings - cur_holdings):
            cooldown_register[tkr] = sd
        prev_holdings = cur_holdings

    weights_df = pd.DataFrame(weights_records)
    return weights_df, ic_raw, ic_smth, p


def turnover_yr(weights_df):
    dates = sorted(weights_df['sig_date'].unique())
    tns = []
    prev_w = None
    for d in dates:
        cur_w = weights_df[weights_df['sig_date'] == d].set_index('Ticker')['weight']
        if prev_w is not None:
            idx = cur_w.index.union(prev_w.index)
            tns.append(float((cur_w.reindex(idx, fill_value=0) - prev_w.reindex(idx, fill_value=0)).abs().sum()))
        prev_w = cur_w
    m = float(np.mean(tns))
    return m, m * 12


def portfolio_returns(weights_df, audit, bm_map):
    """audit has Date/Ticker/log_ret_1m_w. bm_map: Date -> bm_log_ret."""
    rows = []
    for sd in weights_df['sig_date'].unique():
        wg = weights_df[weights_df['sig_date'] == sd]
        rg = audit[audit['Date'] == sd][['Ticker', 'log_ret_1m_w']]
        m = wg.merge(rg, on='Ticker', how='left').dropna(subset=['log_ret_1m_w'])
        if m.shape[0] == 0:
            continue
        rows.append({'Date': sd, 'port_ret': float((m['weight'] * m['log_ret_1m_w']).sum())})
    pr = pd.DataFrame(rows).sort_values('Date').reset_index(drop=True)
    pr['bm_log_ret'] = pr['Date'].map(bm_map)
    pr['active_ret'] = pr['port_ret'] - pr['bm_log_ret']
    return pr


def dsr_proper(ret_net, sr_net_annual, n_trials_eff):
    n = len(ret_net)
    exp_max_sr = np.sqrt(2 * np.log(max(n_trials_eff, 2)))
    mean_r = ret_net.mean()
    std_r = ret_net.std()
    skew_r = ((ret_net - mean_r) ** 3).mean() / (std_r + 1e-10) ** 3
    kurt_r = ((ret_net - mean_r) ** 4).mean() / (std_r + 1e-10) ** 4
    sr_monthly = mean_r / (std_r + 1e-8)
    sr_se = np.sqrt((1 - skew_r * sr_monthly + (kurt_r - 1) / 4 * sr_monthly ** 2) / (n - 1))
    dsr_z = (sr_net_annual - exp_max_sr * (1 - 0.5772 / np.sqrt(2 * np.log(n_trials_eff)))) / max(sr_se * np.sqrt(12), 1e-8)
    return float(norm.cdf(dsr_z)), float(dsr_z), float(skew_r), float(kurt_r), float(exp_max_sr)


def ax001_v2(pr, p_full, pred_col):
    """bad/normal IC ratio. Bad regime = bottom-25% cross-sectional mean return
    (KR relative-quantile crisis proxy, identical to D_ENSEMBLE 01_train_three_models.py
    and D_REFINE cv definitions). IC = spearman(pred, y_zxs) per sig_date within mask."""
    df = p_full.copy()
    df['xs_mean_ret'] = df.groupby('sig_date')['log_ret_1m_w'].transform('mean')
    q25 = df['xs_mean_ret'].quantile(0.25)
    bad_mask = df['xs_mean_ret'] <= q25

    def ax_ic_sub(mask):
        ics_s = []
        sub = df[mask]
        for sd, grp in sub.groupby('sig_date'):
            if grp.shape[0] >= 20:
                ic, _ = spearmanr(grp[pred_col].values, grp['y_zxs'].values)
                if not np.isnan(ic):
                    ics_s.append(ic)
        return (float(np.mean(ics_s)) if ics_s else 0.0), len(ics_s)

    bad_m, nb = ax_ic_sub(bad_mask)
    nrm_m, nn = ax_ic_sub(~bad_mask)
    ratio = bad_m / (abs(nrm_m) + 1e-8) if nrm_m != 0 else 0.0
    return float(bad_m), float(nrm_m), float(ratio), nb, nn


# ---- Load benchmark map once ----
print(f"[{time.strftime('%H:%M:%S')}] Loading RAWDATA benchmark...", flush=True)
rawdata = pd.read_parquet(PROJ / '.cache' / 'rawdata.parquet')
rawdata['Date'] = pd.to_datetime(rawdata['Date'])
me_seq = sorted(rawdata['Date'].unique())


def bm_next_1m_log(sd):
    nxt = [d for d in me_seq if d > sd]
    if not nxt:
        return None
    next_me = nxt[0]
    ip = rawdata[(rawdata['Date'] > sd) & (rawdata['Date'] <= next_me)]
    if ip.shape[0] == 0:
        return None
    bm_daily = ip.groupby('Date')['BM_Ret'].first()
    return float(np.log(1 + bm_daily.dropna()).sum())


# Build BM map from union of dates (both sets share dates)
audit30 = pd.read_parquet(DIR_30 / 'alpha_scores_audit.parquet')
audit30['Date'] = pd.to_datetime(audit30['Date'])
all_dates = sorted(audit30['Date'].unique())
bm_map = {d: bm_next_1m_log(d) for d in all_dates}
print(f"  BM map built for {len(bm_map)} dates", flush=True)

results = {}

# ---- Variant A: 30f (D_REFINE pruned) ----
print(f"\n[{time.strftime('%H:%M:%S')}] === 30f (D_REFINE pruned) ===", flush=True)
preds30 = pd.read_parquet(DIR_30 / 'predictions_walkforward.parquet')
w30, icr30, ics30, pf30 = build_weights(preds30, 'pred')
tn_m30, tn_y30 = turnover_yr(w30)
pr30 = portfolio_returns(w30, audit30, bm_map)
cost30 = tn_m30 * 0.0015
pr30['port_ret_net'] = pr30['port_ret'] - cost30
sr_net30 = pr30['port_ret_net'].mean() / (pr30['port_ret_net'].std() + 1e-8) * np.sqrt(12)
sr_gross30 = pr30['port_ret'].mean() / (pr30['port_ret'].std() + 1e-8) * np.sqrt(12)
dsr30, dsrz30, sk30, ku30, ems30 = dsr_proper(pr30['port_ret_net'].values, sr_net30, N_TRIALS_EFF)
bad30, nrm30, ratio30, nb30, nn30 = ax001_v2(pr30, pf30, 'pred')
results['30f'] = {
    'n_features': 30, 'ic_raw_mean': float(np.mean(icr30)), 'icir_raw': float(np.mean(icr30) / (np.std(icr30) + 1e-8)),
    'ic_smth_mean': float(np.mean(ics30)), 'icir_smth': float(np.mean(ics30) / (np.std(ics30) + 1e-8)),
    'turnover_yr': tn_y30, 'turnover_pass_6': bool(tn_y30 <= 6.0),
    'sr_net_annual': float(sr_net30), 'sr_gross_annual': float(sr_gross30),
    'dsr_proper': dsr30, 'dsr_z': dsrz30, 'dsr_pass_05': bool(dsr30 >= 0.5),
    'skewness': sk30, 'kurtosis': ku30,
    'ax001_v2_bad': bad30, 'ax001_v2_normal': nrm30, 'ax001_v2_ratio': ratio30,
    'ax001_v2_pass_05': bool(ratio30 >= 0.5), 'n_crisis': nb30, 'n_normal': nn30,
}
print(f"  IC {np.mean(icr30):.4f} ICIR {np.mean(icr30)/(np.std(icr30)+1e-8):.3f} | TO {tn_y30:.2f}/yr | "
      f"netSR {sr_net30:.3f} | DSR {dsr30:.4f} z={dsrz30:.2f} | AX001v2 {ratio30:.3f}", flush=True)

# ---- Variant B: 162f (D_ENSEMBLE LightGBM) ----
print(f"\n[{time.strftime('%H:%M:%S')}] === 162f (D_ENSEMBLE LightGBM) ===", flush=True)
preds162 = pd.read_parquet(DIR_162 / 'predictions_walkforward_lgbm.parquet')
w162, icr162, ics162, pf162 = build_weights(preds162, 'pred_lgbm')
tn_m162, tn_y162 = turnover_yr(w162)
# 162f audit = same labels; build audit frame
audit162 = preds162.rename(columns={'sig_date': 'Date'})[['Date', 'Ticker', 'log_ret_1m_w']].copy()
audit162['Date'] = pd.to_datetime(audit162['Date'])
pr162 = portfolio_returns(w162, audit162, bm_map)
cost162 = tn_m162 * 0.0015
pr162['port_ret_net'] = pr162['port_ret'] - cost162
sr_net162 = pr162['port_ret_net'].mean() / (pr162['port_ret_net'].std() + 1e-8) * np.sqrt(12)
sr_gross162 = pr162['port_ret'].mean() / (pr162['port_ret'].std() + 1e-8) * np.sqrt(12)
dsr162, dsrz162, sk162, ku162, ems162 = dsr_proper(pr162['port_ret_net'].values, sr_net162, N_TRIALS_EFF)
bad162, nrm162, ratio162, nb162, nn162 = ax001_v2(pr162, pf162, 'pred_lgbm')
results['162f'] = {
    'n_features': 162, 'ic_raw_mean': float(np.mean(icr162)), 'icir_raw': float(np.mean(icr162) / (np.std(icr162) + 1e-8)),
    'ic_smth_mean': float(np.mean(ics162)), 'icir_smth': float(np.mean(ics162) / (np.std(ics162) + 1e-8)),
    'turnover_yr': tn_y162, 'turnover_pass_6': bool(tn_y162 <= 6.0),
    'sr_net_annual': float(sr_net162), 'sr_gross_annual': float(sr_gross162),
    'dsr_proper': dsr162, 'dsr_z': dsrz162, 'dsr_pass_05': bool(dsr162 >= 0.5),
    'skewness': sk162, 'kurtosis': ku162,
    'ax001_v2_bad': bad162, 'ax001_v2_normal': nrm162, 'ax001_v2_ratio': ratio162,
    'ax001_v2_pass_05': bool(ratio162 >= 0.5), 'n_crisis': nb162, 'n_normal': nn162,
}
print(f"  IC {np.mean(icr162):.4f} ICIR {np.mean(icr162)/(np.std(icr162)+1e-8):.3f} | TO {tn_y162:.2f}/yr | "
      f"netSR {sr_net162:.3f} | DSR {dsr162:.4f} z={dsrz162:.2f} | AX001v2 {ratio162:.3f}", flush=True)

# ---- Decision logic ----
def overfit_gap(res):
    # in-sample IC vs net SR realized: larger IC with worse DSR/AX001 = overfit signature
    return res['ic_raw_mean'] - res['sr_net_annual'] * 0.0  # placeholder; decision below

# Net SR + DSR + AX-001 v2 priority
decision = {}
r30, r162 = results['30f'], results['162f']
# Criterion 1: net SR (higher better)
# Criterion 2: DSR (both likely FAIL; higher z less bad)
# Criterion 3: AX-001 v2 hard axiom (pass required for defensive eval)
decision['net_sr_winner'] = '30f' if r30['sr_net_annual'] >= r162['sr_net_annual'] else '162f'
decision['dsr_z_winner'] = '30f' if r30['dsr_z'] >= r162['dsr_z'] else '162f'
decision['ax001_v2_30f_pass'] = r30['ax001_v2_pass_05']
decision['ax001_v2_162f_pass'] = r162['ax001_v2_pass_05']
decision['turnover_30f_pass'] = r30['turnover_pass_6']
decision['turnover_162f_pass'] = r162['turnover_pass_6']

results['decision_signals'] = decision

with open(OUT_DIR / 'feature_set_comparison.json', 'w') as f:
    json.dump(results, f, indent=2)

# Save portfolio returns for the eventual winner determined post-hoc
pr30.to_parquet(OUT_DIR / 'portfolio_returns_30f.parquet', index=False)
pr162.to_parquet(OUT_DIR / 'portfolio_returns_162f.parquet', index=False)
w30.to_parquet(OUT_DIR / 'weights_schedule_30f.parquet', index=False)
w162.to_parquet(OUT_DIR / 'weights_schedule_162f.parquet', index=False)
# Save alpha_scores (clean preds) for both
preds30[['sig_date', 'Ticker', 'pred', 'fold_id']].rename(columns={'sig_date': 'Date'}).to_parquet(OUT_DIR / 'alpha_scores_30f.parquet', index=False)
preds162[['sig_date', 'Ticker', 'pred_lgbm', 'fold_id']].rename(columns={'sig_date': 'Date', 'pred_lgbm': 'pred'}).to_parquet(OUT_DIR / 'alpha_scores_162f.parquet', index=False)

print(f"\n=== COMPARISON COMPLETE — {(time.time()-t0):.1f}s ===", flush=True)
print(json.dumps(decision, indent=2), flush=True)
