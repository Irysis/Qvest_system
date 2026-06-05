#!/usr/bin/env python3
"""340_andreou_options_direct.py — Plan Phase 3.3 Andreou 2025 options direct crash

학술:
  - Andreou et al. 2025 (JFM) "Predicting jumps and crashes using options"
  - Bates 2008 (JF) implied skew crash predictor
  - Bollerslev-Todorov 2011 (JF) fear index from short OTM options

설계 (Phase 1.2와 차별):
  Phase 1.2: full v5g + 8 options features → HGB Δ-0.034 (options 추가 시 hurt, dilution)
  Phase 3.3: **options-ONLY** classifier + 시계열 dynamics — direct paradigm
    - Features: 8 options + lagged versions (1d/5d/21d) + cross-terms
    - HGB monthly expanding from 2012+ (options data start 2010+)
    - vs HGB V1 baseline + TimeMAE on same OOS
    - If orthogonal signal → triple ensemble candidate

Features extended (옵션 daily 8건 + interaction + lagged):
  base 8: atm_iv_near, atm_iv_far, iv_term_slope, iv_skew_put, iv_smile_curvature, pcr_oi, pcr_vol, iv_rolling_z_5y
  cross:  iv_term_slope × pcr_oi, iv_skew_put × atm_iv_near
  lagged: each base × {1m_change, 1m_mean, 1m_max}

Output: outputs/04_evaluation/cycle58dd_phase3_3_andreou.json
"""
import json
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
IN_OPT = DATA / "kospi200_options_deep_daily.parquet"
IN_M = DATA / "monthly_features.parquet"
OUT_M_OPT = DATA / "monthly_options_only_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58dd_phase3_3_andreou.json"
TEST_START = pd.Timestamp("2018-01-01")


def build_monthly_options_only():
    """Build monthly options-only feature panel with rich derivatives."""
    opt = pd.read_parquet(IN_OPT)
    opt['Date'] = pd.to_datetime(opt['Date'])
    opt = opt.sort_values('Date').reset_index(drop=True)
    base_cols = ['atm_iv_near', 'atm_iv_far', 'iv_term_slope', 'iv_skew_put',
                 'iv_smile_curvature', 'pcr_oi', 'pcr_vol', 'iv_rolling_z_5y']

    m = pd.read_parquet(IN_M)
    m['Date'] = pd.to_datetime(m['Date'])
    m = m.dropna(subset=['y_tail_q15']).sort_values('Date').reset_index(drop=True)
    print(f"[Build] monthly {len(m)}, opt {len(opt)}")

    rows = []
    for _, mr in m.iterrows():
        ms = mr['Date']
        cut = ms - pd.Timedelta(days=1)
        past = opt[opt['Date'] <= cut]
        if len(past) == 0:
            row = {'Date': ms, 'y_tail_q15': mr['y_tail_q15']}
            for c in base_cols:
                row[f'{c}'] = np.nan
            rows.append(row); continue
        last = past.iloc[-1]
        row = {'Date': ms, 'y_tail_q15': mr['y_tail_q15']}
        for c in base_cols:
            row[c] = last[c]
        # Past 21d statistics (1m window)
        past21 = past.tail(21)
        for c in base_cols:
            if c not in past21.columns: continue
            v = past21[c].dropna()
            if len(v) >= 5:
                row[f'{c}_1m_mean'] = v.mean()
                row[f'{c}_1m_max'] = v.max()
                row[f'{c}_1m_change'] = v.iloc[-1] - v.iloc[0]
        # Cross terms (fear interaction)
        if not pd.isna(row.get('iv_term_slope')) and not pd.isna(row.get('pcr_oi')):
            row['cross_term_slope_x_pcr'] = row['iv_term_slope'] * row['pcr_oi']
        if not pd.isna(row.get('iv_skew_put')) and not pd.isna(row.get('atm_iv_near')):
            row['cross_skew_x_iv_level'] = row['iv_skew_put'] * row['atm_iv_near']
        rows.append(row)

    out = pd.DataFrame(rows)
    OUT_M_OPT.parent.mkdir(parents=True, exist_ok=True)
    out.to_parquet(OUT_M_OPT, index=False)
    print(f"  Saved: {OUT_M_OPT} — {len(out)} rows × {len(out.columns)} cols")
    feat_cols = [c for c in out.columns if c not in ['Date', 'y_tail_q15']]
    print(f"  feature cols ({len(feat_cols)}): {feat_cols}")
    return out, feat_cols


def main():
    m_opt, feat_cols = build_monthly_options_only()
    # Filter to rows with options data (2010+)
    m_opt['Date'] = pd.to_datetime(m_opt['Date'])
    m_opt = m_opt[m_opt['Date'] >= '2010-02-01'].reset_index(drop=True)
    m_opt[feat_cols] = m_opt[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    X = m_opt[feat_cols].values
    y = m_opt['y_tail_q15'].values
    dates = pd.to_datetime(m_opt['Date'])
    test_start_idx = (dates >= TEST_START).idxmax()
    # Need at least 60 months of training (2010-02 + 60m = 2015-02 minimum, < TEST_START so fine)
    print(f"\n[OOS] options-only n_train_initial={test_start_idx}, n_oos={len(m_opt) - test_start_idx - 1}")

    # === HGB monthly expanding ===
    print("\n[Stage A: options-only HGB monthly expanding]")
    p_opt = []; y_ex = []; dates_ex = []
    for i in range(test_start_idx, len(m_opt) - 1):
        tr = np.arange(0, i)
        if y[tr].sum() < 15: continue
        m = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
            class_weight='balanced', random_state=42)
        m.fit(X[tr], y[tr])
        p_opt.append(m.predict_proba(X[i:i+1])[0, 1])
        y_ex.append(y[i]); dates_ex.append(dates.iloc[i])
    y_ex = np.array(y_ex); p_opt = np.array(p_opt)
    n = len(y_ex); base = y_ex.mean()
    pr_opt = average_precision_score(y_ex, p_opt)
    roc_opt = roc_auc_score(y_ex, p_opt)
    print(f"  Options-only HGB: n={n} base={base*100:.1f}% PR-AUC {pr_opt:.4f} lift {pr_opt/base:.2f}x ROC {roc_opt:.4f}")

    # Period-balanced
    periods = [('2018-2020', '2018-01-01', '2020-12-31'),
               ('2021-2023', '2021-01-01', '2023-12-31'),
               ('2024-2026', '2024-01-01', '2026-12-31')]
    print("\n[Period-balanced]")
    period_res = []
    dates_s = pd.Series(dates_ex)
    for pname, s, e in periods:
        mask = ((dates_s >= pd.Timestamp(s)) & (dates_s <= pd.Timestamp(e))).values
        if mask.sum() < 12 or y_ex[mask].sum() < 2: continue
        ypm = y_ex[mask]; bp = ypm.mean()
        prp = average_precision_score(ypm, p_opt[mask])
        period_res.append({'period': pname, 'n': int(mask.sum()), 'pos': int(ypm.sum()),
                            'pr_auc': float(prp), 'lift': float(prp / bp)})
        print(f"  {pname}: n={int(mask.sum())} pos={int(ypm.sum())} PR-AUC {prp:.4f} lift {prp/bp:.2f}x")

    # Bootstrap CI
    B = 5000; np.random.seed(42)
    prs_boot = []
    for b in range(B):
        idx = np.random.choice(n, n, replace=True)
        if y_ex[idx].sum() < 5: continue
        prs_boot.append(average_precision_score(y_ex[idx], p_opt[idx]))
    prs_boot = np.array(prs_boot)
    print(f"\n  Bootstrap CI: [{np.quantile(prs_boot, 0.025):.4f}, {np.quantile(prs_boot, 0.975):.4f}]")
    print(f"  P(lift > 2x) = {(prs_boot > 2*base).mean():.3f}")
    print(f"  P(lift > 1.5x) = {(prs_boot > 1.5*base).mean():.3f}")

    audit = {
        'cycle': '58DD_phase3_3_andreou_options_direct',
        'n_features': len(feat_cols),
        'feature_cols': feat_cols,
        'n_oos': int(n),
        'base': float(base),
        'options_only_pr_auc': float(pr_opt),
        'options_only_lift': float(pr_opt / base),
        'options_only_roc': float(roc_opt),
        'period_balanced': period_res,
        'bootstrap_ci': [float(np.quantile(prs_boot, 0.025)), float(np.quantile(prs_boot, 0.975))],
        'p_lift_gt_2x': float((prs_boot > 2*base).mean()),
        'p_lift_gt_1_5x': float((prs_boot > 1.5*base).mean()),
        'predictions': {str(d.date()): float(p) for d, p in zip(dates_ex, p_opt)},
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(audit, indent=2))
    print(f"\nSaved: {OUT}")


if __name__ == '__main__':
    main()
