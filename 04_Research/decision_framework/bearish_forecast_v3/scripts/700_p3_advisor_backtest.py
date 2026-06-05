"""
700_p3_advisor_backtest.py — P3 BUY/SELL/HOLD 추천 모델 + KOSPI 벤치마크 백테스트

도훈 mandate 2026-05-26: P3 자문 활용 시 CAGR / SD / SR / MDD 개선 확인.

3가지 추천 모델:
1. Rule-based threshold (직관적 규칙)
2. Score-based percentile (data-driven 분위)
3. Hybrid (rules + score combined)

Position rule:
- BUY  = 100% KOSPI
- HOLD = 50% KOSPI + 50% cash
- SELL = 0% KOSPI (100% cash)

Transaction cost: 15 bps one-way (KR retail standard)
"""
import pandas as pd
import numpy as np

ANN = 252
TC_BPS = 15  # one-way bps
RF_DAILY = 0.0  # risk-free rate (cash) — 단순 가정

def metrics(returns_dec, label):
    nav = np.cumprod(1 + returns_dec)
    ann_ret = (nav[-1] ** (ANN / len(returns_dec)) - 1) * 100
    ann_vol = returns_dec.std() * np.sqrt(ANN) * 100
    sr = (returns_dec.mean() - RF_DAILY) / returns_dec.std() * np.sqrt(ANN) if returns_dec.std() > 0 else 0
    cummax = np.maximum.accumulate(nav)
    dd = (nav - cummax) / cummax
    mdd = abs(dd.min()) * 100
    return {'name': label, 'sr': sr, 'cagr': ann_ret, 'vol': ann_vol, 'mdd': mdd,
            'final_nav': nav[-1], 'hit': (returns_dec > 0).mean() * 100}


def apply_signals_to_returns(signal, r_kospi, exposure_map={'BUY': 1.0, 'HOLD': 0.5, 'SELL': 0.0}):
    """Convert signals → daily exposures → apply tx cost when exposure changes."""
    exposure = np.array([exposure_map[s] for s in signal])
    # transaction cost: applied at exposure change
    tc_daily = TC_BPS / 10000  # 15 bps to decimal
    delta = np.abs(np.diff(exposure, prepend=0))  # initial exposure 0
    cost = delta * tc_daily
    # net return = exposure * r_kospi - cost
    return exposure * r_kospi - cost


# ─── Signal generators ──────────────────────────────────────────────────────
def signal_rule_based(df):
    """Simple intuitive thresholds."""
    sig = []
    for _, row in df.iterrows():
        sigma = row['sigma']
        lam = row['lam']
        p5 = row['p_minus_5pct'] * 100
        p10 = row['p_minus_10pct'] * 100
        # SELL if strong bear or high tail
        if lam < -0.30 or p10 > 1.0 or sigma > 3.5:
            sig.append('SELL')
        # BUY if calm + slight bull
        elif sigma < 1.3 and lam >= -0.05 and p5 < 1.5:
            sig.append('BUY')
        else:
            sig.append('HOLD')
    return np.array(sig)


def signal_score_based(df, expanding=True):
    """Percentile rank of composite risk score; lowest 33% → BUY, highest 33% → SELL."""
    # Composite: high risk = high σ + high P(-5%) + high P(-10%) + low λ (more negative)
    sigma_z = df['sigma'].rank(pct=True).values  # higher pct = higher σ = worse
    p5_z = df['p_minus_5pct'].rank(pct=True).values
    p10_z = df['p_minus_10pct'].rank(pct=True).values
    lam_neg_z = (-df['lam']).rank(pct=True).values  # higher pct = more negative λ = worse

    score = 0.30 * sigma_z + 0.30 * p5_z + 0.20 * p10_z + 0.20 * lam_neg_z  # 0~1, higher=worse
    # If expanding=True, recompute rank using only past (PIT-safe)
    if expanding:
        n = len(df)
        score_pit = np.zeros(n)
        # Compute z-scores using expanding window (only past data)
        for i in range(n):
            past = df.iloc[:i+1]
            if len(past) < 50:
                score_pit[i] = 0.5  # neutral until enough history
                continue
            s_z = (past['sigma'].iloc[i] >= past['sigma'].values).mean()
            p5_zi = (past['p_minus_5pct'].iloc[i] >= past['p_minus_5pct'].values).mean()
            p10_zi = (past['p_minus_10pct'].iloc[i] >= past['p_minus_10pct'].values).mean()
            ln_zi = ((-past['lam'].iloc[i]) >= (-past['lam'].values)).mean()
            score_pit[i] = 0.30 * s_z + 0.30 * p5_zi + 0.20 * p10_zi + 0.20 * ln_zi
        score = score_pit
    # Tertiles
    sig = np.where(score < 0.33, 'BUY',
          np.where(score > 0.67, 'SELL', 'HOLD'))
    return sig


def signal_hybrid(df, expanding=True):
    """Hybrid: rule-based for clear extremes, score for ambiguous middle."""
    rule = signal_rule_based(df)
    score = signal_score_based(df, expanding=expanding)
    sig = np.array(['HOLD'] * len(df))
    # Strong override (rule extremes)
    for i in range(len(df)):
        if rule[i] == 'SELL':
            sig[i] = 'SELL'
        elif rule[i] == 'BUY':
            sig[i] = 'BUY'
        else:
            sig[i] = score[i]  # use score for ambiguous middle
    return sig


# ─── Main ──────────────────────────────────────────────────────────────────
df = pd.read_parquet('03_models/p3_trial19/all_predictions.parquet')
df['Date'] = pd.to_datetime(df['Date'])
df = df.sort_values('Date').reset_index(drop=True)
n = len(df)
print(f'Backtest n = {n}  ({df.Date.min().date()} ~ {df.Date.max().date()})')
print(f'Years = {(df.Date.max() - df.Date.min()).days / 365:.1f}')
print()

r = df['y_actual'].values / 100  # decimal log return

# Baseline
m_baseline = metrics(r, 'KOSPI Buy-and-Hold')

# Strategies
sig_rule = signal_rule_based(df)
sig_score = signal_score_based(df, expanding=True)  # PIT-safe
sig_hybrid = signal_hybrid(df, expanding=True)

# Apply with 15 bps TC
r_rule = apply_signals_to_returns(sig_rule, r)
r_score = apply_signals_to_returns(sig_score, r)
r_hybrid = apply_signals_to_returns(sig_hybrid, r)

m_rule = metrics(r_rule, 'P3 Rule-based')
m_score = metrics(r_score, 'P3 Score-based (PIT)')
m_hybrid = metrics(r_hybrid, 'P3 Hybrid')

# Print summary
print(f"{'Strategy':<26} {'SR':>7} {'CAGR%':>8} {'Vol%':>7} {'MDD%':>7} {'Final NAV':>10} {'Hit%':>6}")
print('─' * 80)
for m in [m_baseline, m_rule, m_score, m_hybrid]:
    print(f"{m['name']:<26} {m['sr']:>7.3f} {m['cagr']:>+8.2f} {m['vol']:>7.2f} {m['mdd']:>7.2f} {m['final_nav']:>10.2f} {m['hit']:>6.1f}")

# Signal distribution
print()
print('=== Signal distribution ===')
for name, sig in [('Rule-based', sig_rule), ('Score-based', sig_score), ('Hybrid', sig_hybrid)]:
    counts = pd.Series(sig).value_counts()
    print(f'  {name:<14} BUY: {counts.get("BUY", 0):>4} ({counts.get("BUY", 0)/n*100:.1f}%)  '
          f'HOLD: {counts.get("HOLD", 0):>4} ({counts.get("HOLD", 0)/n*100:.1f}%)  '
          f'SELL: {counts.get("SELL", 0):>4} ({counts.get("SELL", 0)/n*100:.1f}%)')

# Improvement table vs baseline
print()
print('=== Improvement vs KOSPI Buy-and-Hold baseline ===')
print(f"{'Strategy':<26} {'ΔSR':>8} {'ΔCAGR':>8} {'ΔVol':>7} {'ΔMDD':>8}")
for m in [m_rule, m_score, m_hybrid]:
    d_sr = m['sr'] - m_baseline['sr']
    d_cagr = m['cagr'] - m_baseline['cagr']
    d_vol = m['vol'] - m_baseline['vol']
    d_mdd = m['mdd'] - m_baseline['mdd']
    print(f"{m['name']:<26} {d_sr:>+8.3f} {d_cagr:>+8.2f} {d_vol:>+7.2f} {d_mdd:>+8.2f}")

# Yearly view
print()
print('=== Year-by-year SR by strategy ===')
df['Year'] = df['Date'].dt.year
print(f"{'Year':<6} {'KOSPI':>7} {'Rule':>7} {'Score':>7} {'Hybrid':>7}")
for year in sorted(df['Year'].unique()):
    mask = df['Year'] == year
    if mask.sum() < 50: continue
    sr_b = r[mask].mean() / (r[mask].std() + 1e-9) * np.sqrt(ANN)
    sr_r = r_rule[mask].mean() / (r_rule[mask].std() + 1e-9) * np.sqrt(ANN)
    sr_s = r_score[mask].mean() / (r_score[mask].std() + 1e-9) * np.sqrt(ANN)
    sr_h = r_hybrid[mask].mean() / (r_hybrid[mask].std() + 1e-9) * np.sqrt(ANN)
    print(f"{year:<6} {sr_b:>7.3f} {sr_r:>7.3f} {sr_s:>7.3f} {sr_h:>7.3f}")

# Save NAV series for visualization
nav_df = pd.DataFrame({
    'Date': df['Date'],
    'KOSPI_BH': np.cumprod(1 + r),
    'P3_Rule': np.cumprod(1 + r_rule),
    'P3_Score': np.cumprod(1 + r_score),
    'P3_Hybrid': np.cumprod(1 + r_hybrid),
    'signal_rule': sig_rule,
    'signal_score': sig_score,
    'signal_hybrid': sig_hybrid,
})
nav_df.to_parquet('03_models/p3_advisor/advisor_backtest.parquet')
print(f'\n[saved] 03_models/p3_advisor/advisor_backtest.parquet')
