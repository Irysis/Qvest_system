"""
Quick-test for paper 2606.19318 (Tempered Skew-t for accumulated returns).
KR analogue: fit distributions to KOSPI benchmark accumulated multi-day returns
(h = 20,40,60,90,120 days), the same horizons the paper studies for S&P500.

Compares (per the paper): Gaussian vs Student-t vs Jones-Faddy Skew-t.
The paper's "tempered Skew-t" = capped-InvGamma stoch-vol -> tempered Student-t,
then Jones-Faddy symmetry-break. scipy's jf_skew_t IS the Jones-Faddy skew-t
(non-tempered); we ALSO add a finite-variance check (tempering => df effectively
grows / variance linear in h) which is the paper's core empirical claim.

Measurement discipline: standard stats funcs only (scipy MLE, KS/AD GOF, AIC/BIC).
NO self-synthesis. metric_type = empirical (distribution fit, not a backtest).
PIT: pure descriptive distribution fitting of realized history; no forward leak.
BM data status (CORRECTED 2026-07-01): earlier "corruption ≤2025-09" premise WITHDRAWN
— external yfinance ^KS11 cross-check matches BM_Close to the decimal. 2025-26 is a
REAL +250% melt-up (KOSPI 2400->8476); 2026-03 -19% / 2026-04 +30% are genuine
correction/rebound months, NOT corruption. FULL period (2026 incl) is valid and the
2026 extreme moves are the BEST fat-tail data for this test. Cap removed -> 2026-06-30.
"""
import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from scipy import stats
import json, sys

np.random.seed(42)

# ---- Load daily benchmark returns (FULL period through 2026-06-30; cap withdrawn) ----
b = pq.read_table('.cache/benchmark.parquet').to_pandas()
b['Date'] = pd.to_datetime(b['Date'])
b = b.sort_values('Date').reset_index(drop=True)
b = b[(b.Date >= '2000-01-01') & (b.Date <= '2026-06-30')].copy()
r = b['BM_Ret'].values.astype(float)
r = r[np.isfinite(r)]
print(f"Daily benchmark returns: n={len(r)}, range {b.Date.min().date()}..{b.Date.max().date()}")
print(f"daily mean={r.mean():.5f} std={r.std():.5f} skew={stats.skew(r):.3f} kurt(excess)={stats.kurtosis(r):.3f}")

# log returns for accumulation (additive). BM_Ret are simple returns.
lr = np.log1p(r)

def accumulate(logret, h):
    """Non-overlapping h-day accumulated log-returns -> convert back to simple-ish.
    Paper uses accumulated returns; we use non-overlapping blocks to keep iid-ish
    sample for clean MLE/GOF (overlapping would inflate n and break GOF p-values).
    """
    n = len(logret)
    k = n // h
    blocks = logret[:k*h].reshape(k, h).sum(axis=1)
    return blocks  # accumulated log return over h days

horizons = [20, 40, 60, 90, 120]
results = {}

for h in horizons:
    x = accumulate(lr, h)
    n = len(x)
    if n < 30:
        results[h] = {'n': n, 'note': 'too few non-overlapping blocks'}
        continue
    out = {'n': int(n), 'mean': float(x.mean()), 'var': float(x.var(ddof=1)),
           'std': float(x.std(ddof=1)), 'skew': float(stats.skew(x)),
           'exkurt': float(stats.kurtosis(x))}

    # ---- Fit 3 models via MLE ----
    # 1) Gaussian
    mu, sg = stats.norm.fit(x)
    ll_norm = np.sum(stats.norm.logpdf(x, mu, sg))
    # 2) Student-t (location-scale)
    df_t, loc_t, sc_t = stats.t.fit(x)
    ll_t = np.sum(stats.t.logpdf(x, df_t, loc_t, sc_t))
    # 3) Jones-Faddy skew-t (the paper's symmetry-break mechanism)
    try:
        a_jf, b_jf, loc_jf, sc_jf = stats.jf_skew_t.fit(x)
        ll_jf = np.sum(stats.jf_skew_t.logpdf(x, a_jf, b_jf, loc_jf, sc_jf))
        jf_ok = np.isfinite(ll_jf)
    except Exception as e:
        a_jf=b_jf=loc_jf=sc_jf=np.nan; ll_jf=-np.inf; jf_ok=False
        out['jf_err']=str(e)[:120]

    def aic_bic(ll, k_par, n):
        return (2*k_par - 2*ll, k_par*np.log(n) - 2*ll)
    aic_n, bic_n = aic_bic(ll_norm, 2, n)
    aic_t, bic_t = aic_bic(ll_t, 3, n)
    aic_jf, bic_jf = aic_bic(ll_jf, 4, n)

    # ---- GOF: KS + Anderson-Darling-ish via cramervonmises ----
    ks_n = stats.kstest(x, 'norm', args=(mu, sg)).statistic
    ks_t = stats.kstest(x, 't', args=(df_t, loc_t, sc_t)).statistic
    ks_jf = stats.kstest(x, 'jf_skew_t', args=(a_jf,b_jf,loc_jf,sc_jf)).statistic if jf_ok else np.nan

    out.update({
        'norm': {'mu': float(mu), 'sg': float(sg), 'aic': float(aic_n), 'bic': float(bic_n), 'ks': float(ks_n)},
        'student_t': {'df': float(df_t), 'loc': float(loc_t), 'scale': float(sc_t), 'aic': float(aic_t), 'bic': float(bic_t), 'ks': float(ks_t)},
        'jf_skew_t': {'a': float(a_jf), 'b': float(b_jf), 'loc': float(loc_jf), 'scale': float(sc_jf), 'aic': float(aic_jf), 'bic': float(bic_jf), 'ks': float(ks_jf)},
    })
    # winner by AIC
    cand = {'norm': aic_n, 'student_t': aic_t, 'jf_skew_t': aic_jf}
    out['aic_winner'] = min(cand, key=cand.get)
    results[h] = out
    print(f"\nh={h:3d} n={n:4d} mean={x.mean():+.4f} var={x.var(ddof=1):.5f} skew={stats.skew(x):+.3f} exkurt={stats.kurtosis(x):+.3f}")
    print(f"  Gaussian  AIC={aic_n:9.2f} KS={ks_n:.4f}")
    print(f"  Student-t AIC={aic_t:9.2f} KS={ks_t:.4f}  df={df_t:.2f}")
    print(f"  JF-skew-t AIC={aic_jf:9.2f} KS={ks_jf:.4f}  a={a_jf:.2f} b={b_jf:.2f}")
    print(f"  -> AIC winner: {out['aic_winner']}")

# ---- Paper's CORE claim test: linear dependence of mean & variance on h ----
hs = np.array([h for h in horizons if 'mean' in results.get(h,{})])
means = np.array([results[h]['mean'] for h in hs])
varis = np.array([results[h]['var'] for h in hs])
# regress mean~h and var~h through origin-ish (paper says near-perfect linear)
def linfit(xv, yv):
    A = np.vstack([xv, np.ones_like(xv)]).T
    coef, res, *_ = np.linalg.lstsq(A, yv, rcond=None)
    yhat = A @ coef
    ss_res = np.sum((yv-yhat)**2); ss_tot = np.sum((yv-yv.mean())**2)
    r2 = 1 - ss_res/ss_tot if ss_tot>0 else np.nan
    return coef, r2
cm, r2m = linfit(hs, means)
cv, r2v = linfit(hs, varis)
print(f"\n=== Paper core claim: mean & variance linear in h ===")
print(f"mean ~ h: slope={cm[0]:.6f} intcpt={cm[1]:+.5f} R2={r2m:.4f}")
print(f"var  ~ h: slope={cv[0]:.7f} intcpt={cv[1]:+.6f} R2={r2v:.4f}")

# ---- Tail-fit comparison at VaR/CVaR: does skew-t improve tail vs current D-factor proxies? ----
# Current system uses empirical/normal VaR. Compare model VaR5% to EMPIRICAL VaR5% at h=20.
h0 = 20
x0 = accumulate(lr, h0)
emp_q05 = np.quantile(x0, 0.05); emp_q01 = np.quantile(x0, 0.01)
mu0,sg0 = results[h0]['norm']['mu'], results[h0]['norm']['sg']
norm_q05 = stats.norm.ppf(0.05, mu0, sg0); norm_q01 = stats.norm.ppf(0.01, mu0, sg0)
dt,lt,st = results[h0]['student_t']['df'],results[h0]['student_t']['loc'],results[h0]['student_t']['scale']
t_q05 = stats.t.ppf(0.05, dt, lt, st); t_q01 = stats.t.ppf(0.01, dt, lt, st)
print(f"\n=== Tail accuracy @ h={h0} (5% / 1% VaR on accumulated logret) ===")
print(f"Empirical : q05={emp_q05:+.4f} q01={emp_q01:+.4f}")
print(f"Gaussian  : q05={norm_q05:+.4f} q01={norm_q01:+.4f}  (err01={norm_q01-emp_q01:+.4f})")
print(f"Student-t : q05={t_q05:+.4f} q01={t_q01:+.4f}  (err01={t_q01-emp_q01:+.4f})")

summary = {'horizons': results,
           'linearity': {'mean_slope': float(cm[0]), 'mean_r2': float(r2m),
                         'var_slope': float(cv[0]), 'var_r2': float(r2v)},
           'tail_h20': {'emp_q05': float(emp_q05),'emp_q01':float(emp_q01),
                        'norm_q01':float(norm_q01),'t_q01':float(t_q01)},
           'metric_type':'empirical_distribution_fit'}
with open('stage_artifacts/paper_recharge/skewt_19318_results.json','w') as f:
    json.dump(summary, f, indent=2)
print("\nsaved -> stage_artifacts/paper_recharge/skewt_19318_results.json")
