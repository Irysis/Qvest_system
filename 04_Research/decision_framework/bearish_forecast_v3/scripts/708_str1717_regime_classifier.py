"""
708_str1717_regime_classifier.py — P3을 binary risk on/off regime classifier로 사용

도훈 mandate 2026-05-26: P3을 continuous overlay 대신 risk on/off 국면 구분으로.

여러 candidate rule 비교:
1. Strict bear: λ<-0.2 AND P(-10%)>0.5%
2. Moderate: λ<-0.2 AND σ>2.0%
3. Tail-focus: P(-10%)>0.5% only
4. Combined: λ<-0.2 AND (σ>2.0% OR P(-10%)>0.3%)
5. Hysteresis: enter strict / exit loose

Risk OFF action options: 50% cash, 70% cash, 100% cash

Backtest: STR_1715 base × regime weight
Compare vs STR_1715 baseline + STR_1716 continuous
"""
import pandas as pd
import numpy as np
import os
from pathlib import Path

PROJECT = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[4])
ANN_M = 12
TC_RATE = 0.0015


def metrics(ret, name):
    nav = np.cumprod(1 + ret)
    cagr = nav[-1] ** (ANN_M / len(ret)) - 1
    vol = ret.std() * np.sqrt(ANN_M)
    sr = ret.mean() / (ret.std() + 1e-12) * np.sqrt(ANN_M)
    down = ret[ret < 0].std() if (ret < 0).any() else 1e-9
    sortino = ret.mean() / (down + 1e-12) * np.sqrt(ANN_M)
    cm = np.maximum.accumulate(nav); dd = (nav - cm) / cm; mdd = abs(dd.min())
    calmar = cagr / mdd if mdd > 0 else 0
    return {'name': name, 'cagr': cagr, 'vol': vol, 'sr': sr, 'sortino': sortino,
            'calmar': calmar, 'mdd': mdd, 'final_nav': nav[-1]}


def apply_regime(ret_base, regime_off, off_cash_pct):
    """Apply regime: ON = full ret_base, OFF = (1-off_cash) × ret_base."""
    weight = np.where(regime_off, 1 - off_cash_pct, 1.0)
    weight_prev = np.concatenate([[1.0], weight[:-1]])
    delta = np.abs(weight - weight_prev)
    tc = delta * TC_RATE
    return weight * ret_base - tc, weight


# ─── Load data ──────────────────────────────────────────────────────────────
str1715 = pd.read_csv(PROJECT / '04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv')
str1715['Date'] = pd.to_datetime(str1715['date'])
str1715 = str1715.sort_values('Date').reset_index(drop=True)

p3 = pd.read_parquet(PROJECT / '04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet')
p3['Date'] = pd.to_datetime(p3['Date'])

# Aggregate P3 to PG2 rebalance dates (PIT-safe: prior trading day)
def p3_at(dt):
    past = p3[p3.Date < dt]
    return past.iloc[-1] if len(past) > 0 else None
str1715['p3'] = str1715['Date'].apply(p3_at)
str1715['p3_avail'] = str1715['p3'].notna()
str1715['sig'] = str1715['p3'].apply(lambda r: r['sigma'] if r is not None else np.nan)
str1715['lam'] = str1715['p3'].apply(lambda r: r['lam'] if r is not None else np.nan)
str1715['p5'] = str1715['p3'].apply(lambda r: r['p_minus_5pct'] if r is not None else np.nan)
str1715['p10'] = str1715['p3'].apply(lambda r: r['p_minus_10pct'] if r is not None else np.nan)

# P3 era only
d = str1715[str1715.p3_avail].reset_index(drop=True)
print(f'P3 era backtest: n={len(d)} ({d.Date.min().date()} ~ {d.Date.max().date()})')

ret = d['ret_net'].values
sig = d['sig'].values; lam = d['lam'].values; p5 = d['p5'].values; p10 = d['p10'].values

# ─── Risk OFF rule candidates ──────────────────────────────────────────────
rules = {
    '01_strict_bear': (lam < -0.2) & (p10 > 0.005),
    '02_moderate': (lam < -0.2) & (sig > 2.0),
    '03_tail_only': p10 > 0.005,
    '04_combined': (lam < -0.2) & ((sig > 2.0) | (p10 > 0.003)),
    '05_λ_alone_strict': lam < -0.3,
    '06_λ_alone_loose': lam < -0.2,
    '07_σ_alone': sig > 2.5,
    '08_loose_OR': (lam < -0.15) | (p10 > 0.005),
    '09_p10_strict': p10 > 0.01,
}

# Hysteresis rule: enter strict, exit loose
def hysteresis_rule(lam, sig, p10, enter_strict, exit_loose):
    """Risk OFF state machine."""
    state = np.zeros(len(lam), dtype=bool)
    in_off = False
    for i in range(len(lam)):
        if not in_off and enter_strict(lam[i], sig[i], p10[i]):
            in_off = True
        elif in_off and exit_loose(lam[i], sig[i], p10[i]):
            in_off = False
        state[i] = in_off
    return state

# Hysteresis variant
rules['10_hysteresis'] = hysteresis_rule(
    lam, sig, p10,
    enter_strict=lambda l, s, p: l < -0.20 and (s > 2.0 or p > 0.003),
    exit_loose=lambda l, s, p: l > -0.05 and s < 1.5 and p < 0.0005,
)

m_base = metrics(ret, 'STR_1715 baseline (P3 era)')

# Test each rule × cash level
results = [m_base]
print(f'\n{"name":<35} {"cash%":<6} {"n_off":<6} {"SR":<6} {"Sortino":<8} {"Calmar":<7} {"CAGR%":<7} {"MDD%":<7}')
print('-'*100)
print(f'{"STR_1715 baseline":<35} {"-":<6} {"-":<6} {m_base["sr"]:<6.3f} {m_base["sortino"]:<8.3f} '
      f'{m_base["calmar"]:<7.3f} {m_base["cagr"]*100:<+7.2f} {m_base["mdd"]*100:<7.2f}')
print('-'*100)

for rule_name, regime_off in rules.items():
    for cash_pct in [0.5, 0.7, 1.0]:
        r_overlay, weight = apply_regime(ret, regime_off, cash_pct)
        m = metrics(r_overlay, f'{rule_name}_cash{int(cash_pct*100)}')
        results.append({**m, 'rule': rule_name, 'cash_pct': cash_pct,
                        'n_off': int(regime_off.sum()), 'off_pct': float(regime_off.mean()*100)})
        print(f'{rule_name:<35} {int(cash_pct*100):<6}% {int(regime_off.sum()):<6} '
              f'{m["sr"]:<6.3f} {m["sortino"]:<8.3f} {m["calmar"]:<7.3f} '
              f'{m["cagr"]*100:<+7.2f} {m["mdd"]*100:<7.2f}')

# ─── Sort by SR ────────────────────────────────────────────────────────────
results_df = pd.DataFrame([r for r in results if 'rule' in r])
top_sr = results_df.sort_values('sr', ascending=False)
print(f'\n=== TOP 5 by Sharpe ===')
for _, r in top_sr.head(5).iterrows():
    print(f'  {r["rule"]:<25} cash{int(r["cash_pct"]*100)}% '
          f'SR={r["sr"]:.3f}  Sortino={r["sortino"]:.3f}  Calmar={r["calmar"]:.3f}  '
          f'CAGR={r["cagr"]*100:+.2f}%  MDD={r["mdd"]*100:.2f}%  off={r["n_off"]}({r["off_pct"]:.1f}%)')

print(f'\n=== TOP 5 by Calmar ===')
top_cal = results_df.sort_values('calmar', ascending=False)
for _, r in top_cal.head(5).iterrows():
    print(f'  {r["rule"]:<25} cash{int(r["cash_pct"]*100)}% '
          f'SR={r["sr"]:.3f}  Calmar={r["calmar"]:.3f}  CAGR={r["cagr"]*100:+.2f}%  MDD={r["mdd"]*100:.2f}%')

print(f'\n=== TOP 5 by CAGR (preserve return) ===')
top_cagr = results_df.sort_values('cagr', ascending=False)
for _, r in top_cagr.head(5).iterrows():
    print(f'  {r["rule"]:<25} cash{int(r["cash_pct"]*100)}% '
          f'SR={r["sr"]:.3f}  CAGR={r["cagr"]*100:+.2f}%  MDD={r["mdd"]*100:.2f}%  off={r["n_off"]}({r["off_pct"]:.1f}%)')

# Save
results_df.to_csv('04_Research/strategies/STR_1716_AR_M4_R05_P3vol/output/regime_classifier_sweep.csv', index=False)
print(f'\n[saved] regime_classifier_sweep.csv')
