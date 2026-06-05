"""
702_pg2_p3_overlay.py — P3 overlay 적용 on PG2 (STR_1715_AR_on_M4_R05_overlay_PG2)

도훈 mandate 2026-05-26: P3을 PG2에 적용시킬 방법들 고민 + 백테스트.

PG2 facts:
- Multi-sleeve (4F + Q07 + M08 + Q25), KR top342, monthly rebalance, 20 holdings
- 2004-2026: CAGR 43.9%, SR 1.52, Vol 26.5%, MDD 41.7%
- cash_weight=0 (현재 cash overlay 비활성)

Overlay scenarios:
1. Baseline (PG2 current, cash=0)
2. P3 P(-10%) linear cash: cash = clip(50·P(-10%), 0, 0.5)
3. P3 regime cash: λ→cash% (3 zones)
4. P3 vol-target cash: target=20% ann → cash = max(0, 1 - target/σ_ann)
5. P3 hybrid: λ regime × tail dampen
6. P3 crisis mode only: P(-10%) > 1% AND λ<-0.2 → 50% cash
"""
import pandas as pd
import numpy as np
import os
from pathlib import Path

ANN_M = 12
PROJECT = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[4])


def metrics(returns_dec, label):
    nav = np.cumprod(1 + returns_dec)
    ann_ret = (nav[-1] ** (ANN_M / len(returns_dec)) - 1) * 100
    ann_vol = returns_dec.std() * np.sqrt(ANN_M) * 100
    sr = returns_dec.mean() / (returns_dec.std() + 1e-12) * np.sqrt(ANN_M)
    cummax = np.maximum.accumulate(nav)
    dd = (nav - cummax) / cummax
    mdd = abs(dd.min()) * 100
    hit = (returns_dec > 0).mean() * 100
    sortino_d = np.where(returns_dec < 0, returns_dec, 0).std() + 1e-12
    sortino = returns_dec.mean() / sortino_d * np.sqrt(ANN_M)
    calmar = ann_ret / mdd if mdd > 0 else 0
    return {'name': label, 'sr': sr, 'sortino': sortino, 'calmar': calmar,
            'cagr': ann_ret, 'vol': ann_vol, 'mdd': mdd,
            'final_nav': nav[-1], 'hit': hit}


# ─── Load PG2 monthly returns ──────────────────────────────────────────────
pg2 = pd.read_csv(PROJECT / '04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv')
pg2['Date'] = pd.to_datetime(pg2['date'])
pg2 = pg2.sort_values('Date').reset_index(drop=True)[['Date', 'ret_net']]
print(f'PG2 monthly: n={len(pg2)}  ({pg2.Date.min().date()} ~ {pg2.Date.max().date()})')

# ─── Load P3 daily ──────────────────────────────────────────────────────────
p3 = pd.read_parquet(PROJECT / '04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet')
p3['Date'] = pd.to_datetime(p3['Date'])
print(f'P3 daily: n={len(p3)}  ({p3.Date.min().date()} ~ {p3.Date.max().date()})')

# ─── Aggregate P3 to monthly (last-day-of-month forecast) ──────────────────
# For each PG2 month-start date, use P3 forecast from previous trading day
p3_for_pg2 = []
for _, row in pg2.iterrows():
    pg2_date = row['Date']
    # Use most recent P3 forecast on or before this date
    past = p3[p3.Date <= pg2_date]
    if len(past) == 0:
        p3_for_pg2.append(None)
    else:
        p3_for_pg2.append(past.iloc[-1])

pg2['p3_sigma'] = [r['sigma'] if r is not None else np.nan for r in p3_for_pg2]
pg2['p3_lam'] = [r['lam'] if r is not None else np.nan for r in p3_for_pg2]
pg2['p3_p5'] = [r['p_minus_5pct'] if r is not None else np.nan for r in p3_for_pg2]
pg2['p3_p10'] = [r['p_minus_10pct'] if r is not None else np.nan for r in p3_for_pg2]

# Keep only periods with P3 data available
pg2_overlay = pg2.dropna(subset=['p3_sigma']).reset_index(drop=True)
print(f'PG2 + P3 overlap: n={len(pg2_overlay)}  ({pg2_overlay.Date.min().date()} ~ {pg2_overlay.Date.max().date()})')

ret_pg2 = pg2_overlay['ret_net'].values  # monthly net returns
sigma_d = pg2_overlay['p3_sigma'].values  # daily σ %
lam = pg2_overlay['p3_lam'].values
p5 = pg2_overlay['p3_p5'].values  # decimal
p10 = pg2_overlay['p3_p10'].values

# Convert daily σ to monthly σ
sigma_m = sigma_d * np.sqrt(21) / 100  # monthly decimal σ
sigma_ann = sigma_d * np.sqrt(252) / 100

# ─── Cash overlay scenarios ────────────────────────────────────────────────
def apply_cash(ret, cash_weight):
    """Cash earns 0%. Equity gets (1-cash) * ret."""
    return (1.0 - cash_weight) * ret


# Baseline
m_base = metrics(ret_pg2, 'PG2 Baseline (cash=0)')

# Scenario 1: Linear tail cash
cash1 = np.clip(50 * p10, 0.0, 0.5)
r1 = apply_cash(ret_pg2, cash1)
m1 = metrics(r1, 'P3 Linear-Tail cash (50×P(-10%))')

# Scenario 2: Regime cash by λ
cash2 = np.where(lam < -0.30, 0.50, np.where(lam < -0.10, 0.20, 0.0))
r2 = apply_cash(ret_pg2, cash2)
m2 = metrics(r2, 'P3 Regime cash (λ-zones)')

# Scenario 3: Vol-target cash
target_vol_ann = 0.20
cash3 = np.clip(1 - target_vol_ann / np.maximum(sigma_ann, 0.05), 0.0, 0.5)
r3 = apply_cash(ret_pg2, cash3)
m3 = metrics(r3, 'P3 Vol-target cash (20% ann)')

# Scenario 4: Hybrid (λ-regime × tail-dampen)
regime_factor = np.where(lam < -0.30, 0.5, np.where(lam < -0.10, 0.8, 1.0))
tail_factor = np.clip(1 - 30 * p10, 0.5, 1.0)
exposure = regime_factor * tail_factor
cash4 = 1 - exposure
r4 = apply_cash(ret_pg2, cash4)
m4 = metrics(r4, 'P3 Hybrid (regime × tail)')

# Scenario 5: Crisis-only (rare trigger)
cash5 = np.where((p10 > 0.01) & (lam < -0.20), 0.50, 0.0)
r5 = apply_cash(ret_pg2, cash5)
m5 = metrics(r5, 'P3 Crisis-only (P(-10%)>1% AND λ<-0.2)')

# Scenario 6: P(-7%) threshold cash
cash6 = np.where(pg2_overlay['p3_p5'].values * 100 > 5.0, 0.30, 0.0)
r6 = apply_cash(ret_pg2, cash6)
m6 = metrics(r6, 'P3 Tail-trigger P(-5%)>5% → 30% cash')

# Scenario 7: Smooth tail cash (continuous)
cash7 = np.clip(20 * p10, 0.0, 0.6)
r7 = apply_cash(ret_pg2, cash7)
m7 = metrics(r7, 'P3 Smooth tail (20×P(-10%))')

print()
print(f"{'Strategy':<42} {'SR':>6} {'Sortino':>8} {'Calmar':>7} {'CAGR%':>8} {'Vol%':>7} {'MDD%':>7} {'NAV':>7} {'Hit%':>6}")
print('─' * 110)
for m in [m_base, m1, m2, m3, m4, m5, m6, m7]:
    print(f"{m['name']:<42} {m['sr']:>6.3f} {m['sortino']:>8.3f} {m['calmar']:>7.3f} "
          f"{m['cagr']:>+8.2f} {m['vol']:>7.2f} {m['mdd']:>7.2f} {m['final_nav']:>7.2f} {m['hit']:>6.1f}")

# Improvement table
print()
print('=== Improvement vs PG2 baseline ===')
print(f"{'Strategy':<42} {'ΔSR':>7} {'ΔCAGR':>8} {'ΔVol':>7} {'ΔMDD':>8} {'ΔCalmar':>9}")
for m in [m1, m2, m3, m4, m5, m6, m7]:
    print(f"{m['name']:<42} {m['sr']-m_base['sr']:>+7.3f} {m['cagr']-m_base['cagr']:>+8.2f} "
          f"{m['vol']-m_base['vol']:>+7.2f} {m['mdd']-m_base['mdd']:>+8.2f} {m['calmar']-m_base['calmar']:>+9.3f}")

# Cash distribution
print()
print('=== Cash weight distribution by scenario ===')
print(f"{'Scenario':<35} {'mean':>6} {'p25':>6} {'med':>6} {'p75':>6} {'max':>6} {'%days>0':>8}")
for name, c in [('Linear-Tail', cash1), ('Regime-λ', cash2), ('Vol-target 20%', cash3),
                ('Hybrid', cash4), ('Crisis-only', cash5), ('P(-5%)>5%', cash6), ('Smooth-tail', cash7)]:
    print(f"{name:<35} {c.mean():>6.3f} {np.quantile(c, 0.25):>6.3f} {np.median(c):>6.3f} "
          f"{np.quantile(c, 0.75):>6.3f} {c.max():>6.3f} {(c > 0).mean()*100:>7.1f}%")
