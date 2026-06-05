"""
703_str1716_full_backtest.py — STR_1716 13년 P3 era isolated backtest (C안)

도훈 mandate 2026-05-26:
- C안: 2013-04 ~ 2026-04 (13년 P3 active period)만 isolated comparison
- STR_1715 baseline도 같은 13년 period로 truncated
- Clean A/B test (P3 always-on assumption)

Strategy:
  strategy_id : STR_1716_AR_M4_R05_P3vol
  base        : STR_1715 (PG2 admitted)
  overlay     : P3 vol-target X% ann cash overlay (param sweep로 X 최적화)
  period      : 2013-04 ~ 2026-04 (156 monthly)

Output: 04_Research/strategies/STR_1716_AR_M4_R05_P3vol/output/
"""
import pandas as pd
import numpy as np
import json
import os
from pathlib import Path
from datetime import datetime

PROJECT = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[4])
STR_OUT = PROJECT / '04_Research/strategies/STR_1716_AR_M4_R05_P3vol/output'
STR_OUT.mkdir(parents=True, exist_ok=True)

STRATEGY_ID = 'STR_1716_AR_M4_R05_P3vol'
RUN_ID = f"{STRATEGY_ID}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
TC_RATE = 0.0015
ANN_M = 12


def metrics(ret, name):
    nav = np.cumprod(1 + ret)
    cagr = (nav[-1] ** (ANN_M / len(ret)) - 1)
    vol = ret.std() * np.sqrt(ANN_M)
    sr = ret.mean() / (ret.std() + 1e-12) * np.sqrt(ANN_M)
    down = ret[ret < 0].std() if (ret < 0).any() else 1e-9
    sortino = ret.mean() / (down + 1e-12) * np.sqrt(ANN_M)
    cm = np.maximum.accumulate(nav); dd = (nav - cm) / cm; mdd = abs(dd.min())
    calmar = cagr / mdd if mdd > 0 else 0
    return {'name': name, 'cagr': cagr, 'vol': vol, 'sr': sr, 'sortino': sortino,
            'calmar': calmar, 'mdd': mdd, 'final_nav': nav[-1],
            'hit': (ret > 0).mean(), 'var95': np.quantile(ret, 0.05),
            'var99': np.quantile(ret, 0.01),
            'cvar99': ret[ret <= np.quantile(ret, 0.01)].mean() if (ret <= np.quantile(ret, 0.01)).any() else 0,
            'skew': pd.Series(ret).skew(), 'kurt': pd.Series(ret).kurtosis()}


# ─── Load PG2 base ─────────────────────────────────────────────────────────
str1715 = pd.read_csv(PROJECT / '04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv')
str1715['Date'] = pd.to_datetime(str1715['date'])
str1715 = str1715.sort_values('Date').reset_index(drop=True)

p3 = pd.read_parquet(PROJECT / '04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet')
p3['Date'] = pd.to_datetime(p3['Date'])
p3 = p3.sort_values('Date').reset_index(drop=True)


# ─── Compute P3 features per rebalance date ────────────────────────────────
def p3_features_at(rebal_date):
    past = p3[p3.Date < rebal_date]
    if len(past) == 0:
        return None
    last = past.iloc[-1]
    return {
        'sigma_daily': last['sigma'], 'lam': last['lam'],
        'p5': last['p_minus_5pct'], 'p10': last['p_minus_10pct'],
        'p3_date': last['Date'],
    }


str1715['p3'] = str1715['Date'].apply(p3_features_at)
str1715_p3era = str1715[str1715['p3'].notna()].reset_index(drop=True)
print(f'P3 era only: n={len(str1715_p3era)} ({str1715_p3era.Date.min().date()} ~ {str1715_p3era.Date.max().date()})')

ret_base = str1715_p3era['ret_net'].values
ret_gross = str1715_p3era['ret_gross'].values
turnover_base = str1715_p3era['turnover'].values
cost_base = str1715_p3era['cost_ret'].values
sigma_daily = np.array([r['sigma_daily'] for r in str1715_p3era['p3']])
lam_arr = np.array([r['lam'] for r in str1715_p3era['p3']])
p5_arr = np.array([r['p5'] for r in str1715_p3era['p3']])
p10_arr = np.array([r['p10'] for r in str1715_p3era['p3']])
sigma_ann = sigma_daily * np.sqrt(252) / 100


# ─── Overlay variants for sweep ─────────────────────────────────────────────
def overlay_vol_target(target_vol, cash_cap=0.50):
    expo = np.clip(target_vol / np.maximum(sigma_ann, 0.05), 0, 1)
    cash = np.clip(1 - expo, 0, cash_cap)
    return cash


def overlay_hybrid_vol_tail(target_vol, p10_boost=30, cash_cap=0.50):
    """vol-target + tail-trigger boost when P(-10%) high."""
    expo_vt = np.clip(target_vol / np.maximum(sigma_ann, 0.05), 0, 1)
    cash_vt = 1 - expo_vt
    # Boost cash when P(-10%) high
    tail_extra = np.clip(p10_boost * p10_arr, 0, 0.40)
    cash = np.clip(cash_vt + tail_extra, 0, cash_cap)
    return cash


def overlay_hybrid_full(target_vol, lam_thresh=-0.20, lam_boost=0.20, p10_boost=30, cash_cap=0.60):
    """vol-target + tail boost + λ regime boost."""
    expo_vt = np.clip(target_vol / np.maximum(sigma_ann, 0.05), 0, 1)
    cash_vt = 1 - expo_vt
    tail_extra = np.clip(p10_boost * p10_arr, 0, 0.40)
    lam_extra = np.where(lam_arr < lam_thresh, lam_boost, 0.0)
    cash = np.clip(cash_vt + tail_extra + lam_extra, 0, cash_cap)
    return cash


def apply_overlay(ret_base, cash):
    cash_prev = np.concatenate([[0.0], cash[:-1]])
    delta_cash = np.abs(cash - cash_prev)
    overlay_tc = delta_cash * TC_RATE
    return (1 - cash) * ret_base - overlay_tc


# ─── Baseline ──────────────────────────────────────────────────────────────
m_base = metrics(ret_base, 'STR_1715 baseline (P3 era only)')

# ─── Sweep target_vol ──────────────────────────────────────────────────────
print()
print('='*100)
print('SWEEP: Vol-target × cash_cap variants (n=156 monthly, 2013-04 ~ 2026-04)')
print('='*100)
print(f"{'variant':<55} {'CAGR%':>7} {'Vol%':>6} {'SR':>6} {'Sortino':>8} {'Calmar':>7} {'MDD%':>7}")
print(f"{'STR_1715 baseline (P3 era only)':<55} {m_base['cagr']*100:>+7.2f} {m_base['vol']*100:>6.2f} "
      f"{m_base['sr']:>6.3f} {m_base['sortino']:>8.3f} {m_base['calmar']:>7.3f} {m_base['mdd']*100:>7.2f}")
print('-'*100)

results = [{'variant': 'STR_1715 baseline (P3 era only)', **m_base, 'cash_mean': 0.0, 'spec': 'baseline'}]

# Vol-target variants
for tv in [0.12, 0.15, 0.18, 0.20, 0.22, 0.25]:
    for cap in [0.30, 0.50]:
        cash = overlay_vol_target(tv, cash_cap=cap)
        r_o = apply_overlay(ret_base, cash)
        m = metrics(r_o, f'VolT {int(tv*100)}% cap {int(cap*100)}%')
        results.append({'variant': m['name'], **m, 'cash_mean': cash.mean(), 'spec': f'vol_target={tv}, cap={cap}'})
        print(f"{m['name']:<55} {m['cagr']*100:>+7.2f} {m['vol']*100:>6.2f} {m['sr']:>6.3f} "
              f"{m['sortino']:>8.3f} {m['calmar']:>7.3f} {m['mdd']*100:>7.2f}")

# Vol+Tail hybrid variants
print('-'*100)
for tv in [0.15, 0.20, 0.25]:
    for pb in [20, 40, 60]:
        cash = overlay_hybrid_vol_tail(tv, p10_boost=pb)
        r_o = apply_overlay(ret_base, cash)
        m = metrics(r_o, f'VolT {int(tv*100)}% + Tail{pb}×P(-10%)')
        results.append({'variant': m['name'], **m, 'cash_mean': cash.mean(), 'spec': f'vol_target={tv}, p10_boost={pb}'})
        print(f"{m['name']:<55} {m['cagr']*100:>+7.2f} {m['vol']*100:>6.2f} {m['sr']:>6.3f} "
              f"{m['sortino']:>8.3f} {m['calmar']:>7.3f} {m['mdd']*100:>7.2f}")

# Full hybrid variants
print('-'*100)
for tv in [0.15, 0.20]:
    for lt in [-0.15, -0.20, -0.25]:
        for lb in [0.10, 0.20]:
            cash = overlay_hybrid_full(tv, lam_thresh=lt, lam_boost=lb, p10_boost=30)
            r_o = apply_overlay(ret_base, cash)
            m = metrics(r_o, f'Full VolT{int(tv*100)}+Tail+λ<{lt}→{int(lb*100)}%')
            results.append({'variant': m['name'], **m, 'cash_mean': cash.mean(),
                            'spec': f'vol={tv}, lam<{lt}→+{lb}, p10×30'})
            print(f"{m['name']:<55} {m['cagr']*100:>+7.2f} {m['vol']*100:>6.2f} {m['sr']:>6.3f} "
                  f"{m['sortino']:>8.3f} {m['calmar']:>7.3f} {m['mdd']*100:>7.2f}")

# ─── Best variant 선택 (by SR) ────────────────────────────────────────────
results_df = pd.DataFrame(results)
results_df_sorted = results_df.sort_values('sr', ascending=False)
print()
print('=== TOP 5 by Sharpe ===')
print(results_df_sorted.head(5)[['variant', 'sr', 'sortino', 'calmar', 'cagr', 'vol', 'mdd', 'cash_mean']].to_string(index=False, float_format='{:.4f}'.format))

# By Calmar (return/MDD)
print()
print('=== TOP 5 by Calmar (CAGR / MDD) ===')
results_df_cal = results_df.sort_values('calmar', ascending=False)
print(results_df_cal.head(5)[['variant', 'sr', 'sortino', 'calmar', 'cagr', 'vol', 'mdd', 'cash_mean']].to_string(index=False, float_format='{:.4f}'.format))

# By MDD reduction (smallest MDD)
print()
print('=== TOP 5 by Lowest MDD ===')
results_df_mdd = results_df.sort_values('mdd', ascending=True)
print(results_df_mdd.head(5)[['variant', 'sr', 'sortino', 'calmar', 'cagr', 'vol', 'mdd', 'cash_mean']].to_string(index=False, float_format='{:.4f}'.format))

# ─── Select final spec — best SR ───────────────────────────────────────────
best = results_df_sorted.iloc[0]
print()
print(f'★★★ FINAL STR_1716 spec: {best["variant"]}')
print(f'    spec: {best["spec"]}')

# Save sweep results
results_df.to_csv(STR_OUT / 'sweep_results.csv', index=False)
print(f'\n[saved] sweep_results.csv')
