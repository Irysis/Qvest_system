#!/usr/bin/env python3
"""330_hamilton_ms_regime.py — Plan Phase 3.2 Hamilton Markov-Switching

학술:
  - Hamilton 1989 (Econometrica) — Markov-switching regime model
  - Adrian-Brunnermeier 2016 (AER) — CoVaR systemic risk
  - Kim 1994 — Smoother for filtered probabilities

설계:
  Stage A: statsmodels MarkovRegression on KOSPI200 monthly returns
    - 2-regime (low-vol/high-vol) — Hamilton baseline
    - Fit on expanding window (PIT), refit annually
  Stage B: Per-regime HGB classifier on labeled month-starts
    - Group training samples by filtered regime probability
    - Weighted training: sample_weight = P(regime_at_train_time)
  Stage C: Mixture prediction
    - P(bear_t) = Σ P(regime_t | past) × P(bear | regime, X_t)

OOS: 2018-2026 (99-100 months). Annual regime refit.
Baseline: HGB V1 expanding lift 2.00x.

Output: outputs/04_evaluation/cycle58dd_phase3_2_hamilton.json
"""
import json
from pathlib import Path
import numpy as np
import pandas as pd
from statsmodels.tsa.regime_switching.markov_regression import MarkovRegression
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
OUT = WS / "outputs/04_evaluation/cycle58dd_phase3_2_hamilton.json"

TEST_START = pd.Timestamp("2018-01-01")
N_REGIMES = 2  # Hamilton baseline: 2-regime


def fit_ms_regime(returns_series, n_regimes=N_REGIMES, max_iter=200):
    """Fit Markov-Switching Regression on returns. Return filtered probabilities."""
    try:
        ms = MarkovRegression(returns_series, k_regimes=n_regimes,
            trend='c', switching_variance=True)
        res = ms.fit(disp=False, maxiter=max_iter, em_iter=50)
        # filtered_marginal_probabilities: P(regime_t | y_1, ..., y_t) — PIT
        filt = res.filtered_marginal_probabilities  # (T, n_regimes)
        return res, filt
    except Exception as e:
        print(f"  MS fit failed: {e}")
        return None, None


def main():
    # Load monthly returns + monthly features + benchmark
    m = pd.read_parquet(DATA / "monthly_features.parquet")
    m['Date'] = pd.to_datetime(m['Date'])
    m = m.dropna(subset=['y_tail_q15']).sort_values('Date').reset_index(drop=True)
    # Use ret_1m as primary return series (1-month return at month-start)
    rets = m['ret_1m'].values
    valid_mask = ~np.isnan(rets)
    print(f"[Load] {len(m)} monthly rows, {valid_mask.sum()} valid returns")
    print(f"  Date range: {m.Date.min().date()} ~ {m.Date.max().date()}")
    print(f"  ret_1m: mean {np.nanmean(rets)*100:.2f}% std {np.nanstd(rets)*100:.2f}%")

    non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']
    feat_cols = [c for c in m.columns if c not in non_feat]
    m[feat_cols] = m[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    X = m[feat_cols].values
    y = m['y_tail_q15'].values
    dates = pd.to_datetime(m['Date'])
    test_start_idx = max((dates >= TEST_START).idxmax(), 100)
    print(f"  OOS start: {dates.iloc[test_start_idx].date()} (n_test {len(m) - test_start_idx - 1})")

    # === Stage A: Annual MS regime fit ===
    # For each test year, fit MS on returns up to year start, get filtered probs for all past months
    print(f"\n[Stage A] Markov-Switching regime detection (annual refit, {N_REGIMES}-regime)")
    test_dates_s = pd.Series(dates.iloc[test_start_idx:])
    years = sorted(test_dates_s.dt.year.unique())
    # Storage: filtered regime probabilities at each month
    regime_probs_per_year = {}  # year → (full filtered probs array up to that year start)

    for yr in years:
        # Find global idx for first test month of this year
        yr_mask = test_dates_s.dt.year == yr
        first_test = test_dates_s[yr_mask].iloc[0]
        first_global = (dates == first_test).idxmax()
        # Fit MS on returns up to (NOT including) first_global
        train_rets = rets[:first_global]
        valid = ~np.isnan(train_rets)
        if valid.sum() < 100: continue
        print(f"  Year {yr}: train on {valid.sum()} monthly returns up to {dates.iloc[first_global-1].date()}")
        ret_series = pd.Series(train_rets[valid])
        res, filt = fit_ms_regime(ret_series)
        if res is None:
            print(f"    failed for {yr}")
            continue
        # Map back to original indices (only valid positions)
        full_probs = np.full((first_global, N_REGIMES), np.nan)
        full_probs[valid] = filt.values
        # forward-fill regime probs for valid positions
        regime_probs_per_year[yr] = full_probs
        # Identify which regime is "crisis" (higher conditional variance)
        sigma2 = np.array([res.params[f'sigma2[{i}]'] for i in range(N_REGIMES)])
        crisis_regime = int(np.argmax(sigma2))
        # Print latest regime probs and crisis sigma
        latest_probs = filt.iloc[-1].values
        print(f"    crisis_regime={crisis_regime} sigma2={sigma2[crisis_regime]:.6f} vs calm={sigma2[1-crisis_regime]:.6f}")
        print(f"    latest filtered prob: regime0={latest_probs[0]:.3f} regime1={latest_probs[1]:.3f}")

    # === Stage B+C: Per-regime HGB + mixture prediction ===
    print(f"\n[Stage B+C] Per-regime HGB + mixture prediction")
    preds_mixture = []
    preds_hgb_baseline = []  # for ref comparison
    y_ex = []; dates_ex = []
    for i in range(test_start_idx, len(m) - 1):
        tr_idx = np.arange(0, i)
        if y[tr_idx].sum() < 20: continue
        yr = dates.iloc[i].year
        if yr not in regime_probs_per_year: continue
        rp = regime_probs_per_year[yr]  # (year_fit_train_len, N_REGIMES)

        # Regime probs for training samples — pad with last available if needed
        if rp.shape[0] >= i:
            rp_tr = rp[tr_idx]
        else:
            # Pad: fill missing recent samples with the LATEST regime prob (persistence assumption)
            last_valid = np.where(~np.isnan(rp[:, 0]))[0]
            if len(last_valid) == 0: continue
            last_p = rp[last_valid[-1]]
            full_rp = np.full((i, N_REGIMES), np.nan)
            full_rp[:rp.shape[0]] = rp
            full_rp[rp.shape[0]:] = last_p  # persistence
            rp_tr = full_rp[tr_idx]

        valid_rp = ~np.isnan(rp_tr).any(axis=1)
        if valid_rp.sum() < 30: continue
        Xtr = X[tr_idx][valid_rp]; ytr = y[tr_idx][valid_rp]; rp_tr_v = rp_tr[valid_rp]

        # Test regime probability: use last available regime prob (filtered up to t-1)
        last_valid_idx = np.where(~np.isnan(rp[:, 0]))[0]
        if len(last_valid_idx) == 0: continue
        test_rp = rp[last_valid_idx[-1]]  # (N_REGIMES,)

        # Per-regime HGB classifier: weight training samples by P(regime|sample_t)
        regime_preds = np.zeros(N_REGIMES)
        for r in range(N_REGIMES):
            # Weight: P(regime=r | sample_t)
            w = rp_tr_v[:, r]
            # Effective sample size (skip if < 10)
            if w.sum() < 10: continue
            # Train HGB with sample_weight
            try:
                mh = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
                    class_weight='balanced', random_state=42)
                mh.fit(Xtr, ytr, sample_weight=w)
                regime_preds[r] = mh.predict_proba(X[i:i+1])[0, 1]
            except Exception:
                regime_preds[r] = 0.5

        # Mixture: P(bear) = Σ P(regime_t) × P(bear|regime_r)
        p_mix = float(np.sum(test_rp * regime_preds))
        preds_mixture.append(p_mix)

        # Baseline HGB (no regime conditioning)
        try:
            mb = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
                class_weight='balanced', random_state=42)
            mb.fit(X[tr_idx], y[tr_idx])
            preds_hgb_baseline.append(mb.predict_proba(X[i:i+1])[0, 1])
        except Exception:
            preds_hgb_baseline.append(0.5)

        y_ex.append(y[i]); dates_ex.append(dates.iloc[i])

    y_ex = np.array(y_ex); preds_mixture = np.array(preds_mixture); preds_hgb = np.array(preds_hgb_baseline)
    n = len(y_ex); base = y_ex.mean()
    print(f"\n[OOS] n={n}, base={base*100:.1f}%")
    pr_mix = average_precision_score(y_ex, preds_mixture)
    pr_hgb = average_precision_score(y_ex, preds_hgb)
    roc_mix = roc_auc_score(y_ex, preds_mixture)
    roc_hgb = roc_auc_score(y_ex, preds_hgb)
    print(f"  HGB baseline:        PR-AUC {pr_hgb:.4f} lift {pr_hgb/base:.2f}x ROC {roc_hgb:.4f}")
    print(f"  Hamilton MS mixture: PR-AUC {pr_mix:.4f} lift {pr_mix/base:.2f}x ROC {roc_mix:.4f}")
    print(f"  Δ vs HGB baseline: {pr_mix - pr_hgb:+.4f}")
    print(f"  cor(P_hgb, P_mix): {np.corrcoef(preds_hgb, preds_mixture)[0, 1]:.3f}")

    # Period-balanced
    periods = [('2018-2020', '2018-01-01', '2020-12-31'),
               ('2021-2023', '2021-01-01', '2023-12-31'),
               ('2024-2026', '2024-01-01', '2026-12-31')]
    print("\n[Period-balanced]")
    print(f"{'Period':<12s} {'HGB lift':>10s} {'MS lift':>10s} {'n':>4s} {'pos':>4s}")
    period_res = []
    dates_ex_s = pd.Series(dates_ex)
    for pname, s, e in periods:
        mask = ((dates_ex_s >= pd.Timestamp(s)) & (dates_ex_s <= pd.Timestamp(e))).values
        if mask.sum() < 12 or y_ex[mask].sum() < 2: continue
        ypm = y_ex[mask]; bp = ypm.mean()
        pr_h = average_precision_score(ypm, preds_hgb[mask]); pr_m = average_precision_score(ypm, preds_mixture[mask])
        period_res.append({'period': pname, 'n': int(mask.sum()), 'pos': int(ypm.sum()),
                            'hgb_lift': float(pr_h / bp), 'ms_lift': float(pr_m / bp),
                            'hgb_pr': float(pr_h), 'ms_pr': float(pr_m)})
        print(f"  {pname:<12s} {pr_h/bp:>9.2f}x {pr_m/bp:>9.2f}x {int(mask.sum()):>4d} {int(ypm.sum()):>4d}")

    # Bootstrap CI paired
    print("\n[Paired bootstrap CI 95% — Hamilton MS vs HGB baseline, B=5000]")
    B = 5000; np.random.seed(42)
    prs_h = []; prs_m = []; deltas = []
    for b in range(B):
        idx = np.random.choice(n, n, replace=True)
        if y_ex[idx].sum() < 5: continue
        prs_h.append(average_precision_score(y_ex[idx], preds_hgb[idx]))
        prs_m.append(average_precision_score(y_ex[idx], preds_mixture[idx]))
        deltas.append(prs_m[-1] - prs_h[-1])
    prs_h = np.array(prs_h); prs_m = np.array(prs_m); deltas = np.array(deltas)
    print(f"  HGB CI: [{np.quantile(prs_h, 0.025):.4f}, {np.quantile(prs_h, 0.975):.4f}]")
    print(f"  MS CI:  [{np.quantile(prs_m, 0.025):.4f}, {np.quantile(prs_m, 0.975):.4f}]")
    print(f"  Δ CI:   [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
    print(f"  P(MS > HGB) = {(deltas > 0).mean():.3f}")
    print(f"  P(MS lift > 2x) = {(prs_m > 2*base).mean():.3f}")
    print(f"  P(HGB lift > 2x) = {(prs_h > 2*base).mean():.3f}")

    audit = {
        'cycle': '58DD_phase3_2_hamilton_ms',
        'n_regimes': N_REGIMES,
        'n_oos': int(n),
        'base': float(base),
        'hgb_pr_auc': float(pr_hgb),
        'ms_pr_auc': float(pr_mix),
        'delta': float(pr_mix - pr_hgb),
        'cor_hgb_ms': float(np.corrcoef(preds_hgb, preds_mixture)[0, 1]),
        'period_balanced': period_res,
        'paired_bootstrap': {
            'hgb_ci': [float(np.quantile(prs_h, 0.025)), float(np.quantile(prs_h, 0.975))],
            'ms_ci': [float(np.quantile(prs_m, 0.025)), float(np.quantile(prs_m, 0.975))],
            'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
            'p_ms_gt_hgb': float((deltas > 0).mean()),
            'p_ms_lift_gt_2x': float((prs_m > 2*base).mean()),
            'p_hgb_lift_gt_2x': float((prs_h > 2*base).mean()),
        },
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(audit, indent=2))
    print(f"\nSaved: {OUT}")


if __name__ == '__main__':
    main()
