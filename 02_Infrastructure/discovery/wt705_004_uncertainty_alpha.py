"""
wt705_004_uncertainty_alpha.py — WT-D20260705_004 Alpha Research
Uncertainty-aware alpha_hat: probabilistic forecast (NGBoost + MAPIE conformal) over an
ESTABLISHED signal mean (score_eff composite), then compare 4 selection/sizing rules
on the SAME alpha_hat mean. Goal: does uncertainty-based selection recover realized PORT_t
that point-ranking destroys (IC -> PORT_t transition wall)?

STRICT PIT:
  - Expanding-window training: at rebalance month t, train ONLY on months < t (60-month burn-in).
  - NGBoost -> per-name (mu_hat, sigma_hat) predictive distribution.
  - MAPIE conformal -> calibrated prediction interval half-width (confidence proxy).
  - Target y = forward active return (F1 cross-sectionally demeaned per month). PIT: F1 = t->t+1.
  - No look-ahead: model at month t never sees F1 of month >= t.

VARIANTS (identical mu_hat mean, only selection/sizing differs):
  A baseline           : point mu_hat, top-25
  B risk_adjusted      : mu_hat / sigma_hat, top-25
  C confidence_band    : among names whose conformal lower-bound > 0 (high-confidence), top-25 by mu_hat
  D uncertainty_shrunk : mu_shrunk = mu_hat * (1 - lambda*sigma_norm), top-25 by mu_shrunk

Each variant's monthly (Date,Ticker,score) -> R canonical_screen_bt (build_benchmark_compare,
NW lag-3) = metric_type "canonical_screen". proxy hand-calc forbidden.

Output: cs_scores per variant + cs_result.json per variant, plus alpha_scores.parquet (mu/sigma/lb).
"""
import os, sys, json, subprocess, shutil, glob, warnings, time
import numpy as np, pandas as pd
warnings.filterwarnings("ignore")

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
CACHE = ROOT + "/.cache"
PANEL = CACHE + "/discovery/explore_panel.parquet"
OUTDIR = ROOT + "/stage_artifacts/WT-D20260705_004"
SCRATCH = OUTDIR + "/_canon_scratch"
os.makedirs(OUTDIR, exist_ok=True)
os.makedirs(SCRATCH, exist_ok=True)

# ---- config ----
FEATS = ['score_eff', 'V02_EP', 'Q01_GPA', 'M01_Mom_12_1',
         'INV01_Foreign_NetBuy_20d', 'D01_IdioVol', 'L01_Amihud']
ALPHA_MEAN_COL = 'score_eff'   # established composite = the alpha_hat mean anchor
BURN_IN = 60                   # months of history before first prediction
RETRAIN_EVERY = 6             # retrain NGBoost every K months (predict monthly w/ latest PIT model)
TOP_N = 25
RECENT_LO = "2017-01"          # post-2017 subperiod (decay era, WT mandate)
SHRINK_LAMBDA = 0.5
SEED = 0

def _ym2date(ym): return ym + "-01"

def nw_t(x, lag=3):
    x = np.asarray(x, float); x = x[~np.isnan(x)]; n = len(x)
    if n < 5: return np.nan
    e = x - x.mean(); s = (e @ e) / n
    for l in range(1, lag + 1):
        s += 2 * (1 - l / (lag + 1)) * ((e[l:] @ e[:-l]) / n)
    return x.mean() / np.sqrt(s / n)

# ---------------------------------------------------------------------------
# 1. Load panel, build cross-sectional standardized features + active target
# ---------------------------------------------------------------------------
def load_data():
    d = pd.read_parquet(PANEL, columns=['ym', 'Ticker', 'F1'] + FEATS)
    d = d.dropna(subset=FEATS + ['F1']).copy()
    # cross-sectional z-score of features per month (features already ~Z; re-standardize for safety)
    for f in FEATS:
        d[f + '_z'] = d.groupby('ym')[f].transform(
            lambda s: (s - s.mean()) / (s.std() + 1e-9))
    # target = forward ACTIVE return (demean F1 cross-sectionally each month)
    d['y_active'] = d.groupby('ym')['F1'].transform(lambda s: s - s.mean())
    return d

# ---------------------------------------------------------------------------
# 2. Probabilistic forecast, expanding window (PIT-safe)
# ---------------------------------------------------------------------------
def run_forecasts(d):
    from ngboost import NGBRegressor
    from ngboost.distns import Normal
    from ngboost.learners import default_tree_learner
    try:
        from mapie.regression import MapieRegressor as _Mapie
        MAPIE_KIND = 'legacy'
    except Exception:
        try:
            from mapie.regression import SplitConformalRegressor as _Mapie
            MAPIE_KIND = 'split'
        except Exception:
            _Mapie = None; MAPIE_KIND = None
    from sklearn.ensemble import GradientBoostingRegressor

    feat_z = [f + '_z' for f in FEATS]
    months = sorted(d['ym'].unique())
    midx = {m: i for i, m in enumerate(months)}
    pred_months = months[BURN_IN:]

    rows = []
    model = None; mapie = None; last_train_i = -999
    t0 = time.time()
    for k, t in enumerate(pred_months):
        ti = midx[t]
        need_retrain = (model is None) or (ti - last_train_i >= RETRAIN_EVERY)
        if need_retrain:
            tr = d[d['ym'].isin(months[:ti])]   # STRICT: months strictly before t
            Xtr = tr[feat_z].values; ytr = tr['y_active'].values
            model = NGBRegressor(Dist=Normal, n_estimators=300, learning_rate=0.02,
                                 minibatch_frac=0.5, col_sample=0.8, verbose=False,
                                 random_state=SEED, Base=default_tree_learner)
            model.fit(Xtr, ytr)
            # conformal: split-calibrate on most-recent 24 months of the PAST training set
            if _Mapie is not None:
                cal_months = months[max(0, ti - 24):ti]
                cal = tr[tr['ym'].isin(cal_months)]
                if len(cal) > 200:
                    base = GradientBoostingRegressor(n_estimators=200, learning_rate=0.03,
                                                     max_depth=3, subsample=0.8, random_state=SEED)
                    tr_fit_months = months[:max(0, ti - 24)]
                    trf = tr[tr['ym'].isin(tr_fit_months)]
                    try:
                        if MAPIE_KIND == 'legacy':
                            base.fit(trf[feat_z].values, trf['y_active'].values)
                            mapie = _Mapie(estimator=base, method='base', cv='prefit')
                            mapie.fit(cal[feat_z].values, cal['y_active'].values)
                        else:
                            mapie = _Mapie(estimator=base, confidence_level=0.68, prefit=False)
                            mapie.fit(trf[feat_z].values, trf['y_active'].values)
                            mapie.conformalize(cal[feat_z].values, cal['y_active'].values)
                    except Exception as e:
                        mapie = None
            last_train_i = ti
        # predict month t
        cur = d[d['ym'] == t]
        Xc = cur[feat_z].values
        dist = model.pred_dist(Xc)
        mu = dist.loc              # NGBoost Normal mean
        sig = dist.scale           # NGBoost Normal std (predictive uncertainty)
        # conformal lower bound at ~68% (1-sigma-equiv)
        lb = np.full(len(cur), np.nan)
        if mapie is not None:
            try:
                if MAPIE_KIND == 'legacy':
                    _, yint = mapie.predict(Xc, alpha=0.32)
                    lb = yint[:, 0, 0]
                else:
                    _, yint = mapie.predict_interval(Xc)
                    lb = yint[:, 0, 0]
            except Exception:
                lb = np.full(len(cur), np.nan)
        sub = pd.DataFrame({
            'ym': t, 'Ticker': cur['Ticker'].values,
            'mu_hat': mu, 'sigma_hat': sig, 'lb68': lb,
            'F1': cur['F1'].values, 'alpha_mean': cur[ALPHA_MEAN_COL].values})
        rows.append(sub)
        if (k + 1) % 24 == 0:
            print(f"  [{k+1}/{len(pred_months)}] {t}  elapsed={time.time()-t0:.0f}s", flush=True)
    fc = pd.concat(rows, ignore_index=True)
    print(f"  forecasts done: {len(fc)} rows, {fc['ym'].nunique()} months, "
          f"mapie={'on' if fc['lb68'].notna().any() else 'off'}", flush=True)
    return fc

# ---------------------------------------------------------------------------
# 3. Build 4 variant scores + write cs parquet (Date,Ticker,score) & returns/bench
# ---------------------------------------------------------------------------
def bm_fwd_map():
    import pyarrow.parquet as pq
    bm = pq.read_table(CACHE + "/benchmark.parquet").to_pandas()
    bc = [c for c in ("BM_Ret", "Ret") if c in bm.columns][0]
    bm["ym"] = pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m")
    bm = bm.dropna(subset=[bc])
    lr = bm.groupby("ym")[bc].apply(lambda r: np.log1p(r).sum())
    idx = list(lr.index)
    def f(t):
        if t not in idx: return np.nan
        i = idx.index(t)
        return np.expm1(lr.iloc[i + 1:i + 2].sum()) if i + 2 <= len(idx) else np.nan
    return f

def variant_scores(fc):
    fc = fc.copy()
    # sigma normalized cross-sectionally per month (for shrink)
    fc['sig_norm'] = fc.groupby('ym')['sigma_hat'].transform(
        lambda s: (s - s.min()) / (s.max() - s.min() + 1e-12))
    out = {}
    out['A_baseline'] = fc['mu_hat'].values
    out['B_risk_adj'] = (fc['mu_hat'] / (fc['sigma_hat'] + 1e-9)).values
    out['D_shrunk'] = (fc['mu_hat'] * (1 - SHRINK_LAMBDA * fc['sig_norm'])).values
    # C confidence-band: only names with conformal lb68 > 0 eligible; else -inf so excluded
    has_mapie = fc['lb68'].notna().any()
    if has_mapie:
        elig = fc['lb68'].values > 0
    else:
        # fallback confidence proxy: mu_hat - 1*sigma_hat > 0 (parametric 68% lower bound)
        elig = (fc['mu_hat'].values - fc['sigma_hat'].values) > 0
    cscore = fc['mu_hat'].values.copy()
    cscore[~elig] = -1e9
    out['C_confband'] = cscore
    out['_confband_source'] = 'mapie' if has_mapie else 'parametric_1sigma'
    return fc, out

def write_variant(fc, scorevals, tag, bmf, lo=None, hi=None):
    d = fc.copy(); d['score'] = scorevals
    d = d.dropna(subset=['score'])
    d = d[d['score'] > -1e8]   # drop confband-excluded
    if lo: d = d[d['ym'] >= lo]
    if hi: d = d[d['ym'] <= hi]
    if d['ym'].nunique() < 6: return None
    sd = SCRATCH
    scores = d[['ym', 'Ticker', 'score']].copy(); scores['Date'] = scores['ym'].map(_ym2date)
    scores = scores[['Date', 'Ticker', 'score']]
    rets = d[['ym', 'Ticker', 'F1']].dropna(subset=['F1']).rename(columns={'F1': 'Ret_1m'})
    rets['Date'] = rets['ym'].map(_ym2date); rets = rets[['Date', 'Ticker', 'Ret_1m']]
    byms = sorted(d['ym'].unique())
    bench = pd.DataFrame({'ym': byms}); bench['BM_Ret'] = [bmf(t) for t in byms]
    bench = bench.dropna(subset=['BM_Ret']); bench['Date'] = bench['ym'].map(_ym2date)
    bench = bench[['Date', 'BM_Ret']]
    scores.to_parquet(sd + "/cs_scores.parquet", index=False)
    rets.to_parquet(sd + "/cs_returns.parquet", index=False)
    bench.to_parquet(sd + "/cs_bench.parquet", index=False)
    return run_canonical(sd)

def _rscript():
    for c in [shutil.which("Rscript"), "C:/Program Files/R/R-4.5.2/bin/Rscript.exe"]:
        if c and os.path.exists(c): return c
    hits = glob.glob("C:/Program Files/R/R-*/bin/Rscript.exe")
    if hits: return hits[0]
    raise RuntimeError("Rscript not found")

def run_canonical(sd):
    wrapper = (ROOT + "/02_Infrastructure/discovery/run_canonical_screen.R").replace("\\", "/")
    env = {**os.environ, "QM_ROOT": ROOT, "CS_SCRATCH": sd.replace("\\", "/"),
           "CS_TOPN": str(TOP_N), "CS_PPY": "12"}
    rf = os.path.join(sd, "cs_result.json")
    if os.path.exists(rf): os.remove(rf)
    try:
        r = subprocess.run([_rscript(), "-e", f"source('{wrapper}')"], env=env,
                           check=True, capture_output=True, text=True, timeout=600)
    except Exception as e:
        print("  [canonical] R fail:", str(e)[:300]); return None
    if not os.path.exists(rf): return None
    return json.load(open(rf))

# ---------------------------------------------------------------------------
# 4. rank-IC per variant score (diagnostic, NOT authoritative)
# ---------------------------------------------------------------------------
def rank_ic(fc, scorevals, lo=None, hi=None):
    d = fc.copy(); d['score'] = scorevals
    d = d[d['score'] > -1e8].dropna(subset=['score', 'F1'])
    if lo: d = d[d['ym'] >= lo]
    if hi: d = d[d['ym'] <= hi]
    ic = d.groupby('ym').apply(lambda g: g['score'].corr(g['F1'], method='spearman')).dropna()
    if len(ic) < 5: return {'ic': np.nan, 'icir': np.nan, 't': np.nan, 'n': len(ic)}
    return {'ic': round(ic.mean(), 4), 'icir': round(ic.mean() / (ic.std() + 1e-9), 3),
            't': round(nw_t(ic.values), 2), 'n': int(len(ic))}

def main():
    print("[1] load panel + features", flush=True)
    d = load_data()
    print(f"    {len(d)} rows, {d['ym'].nunique()} months", flush=True)
    print("[2] probabilistic forecasts (expanding PIT)", flush=True)
    fc = run_forecasts(d)
    fc.to_parquet(OUTDIR + "/alpha_scores.parquet", index=False)
    print("[3] build variants + canonical PORT_t", flush=True)
    fc, variants = variant_scores(fc)
    confband_src = variants.pop('_confband_source')
    bmf = bm_fwd_map()
    results = {}
    for tag in ['A_baseline', 'B_risk_adj', 'C_confband', 'D_shrunk']:
        sv = variants[tag]
        full = write_variant(fc, sv, tag, bmf)
        recent = write_variant(fc, sv, tag, bmf, lo=RECENT_LO)
        ic_full = rank_ic(fc, sv)
        ic_recent = rank_ic(fc, sv, lo=RECENT_LO)
        results[tag] = {
            'full': {k: full.get(k) for k in
                     ('portfolio_alpha_t_nw_lag3', 'information_ratio', 'alpha_annualized',
                      'net_sr', 'turnover_annual', 'n_months')} if full else None,
            'recent2017': {k: recent.get(k) for k in
                           ('portfolio_alpha_t_nw_lag3', 'information_ratio', 'net_sr', 'n_months')} if recent else None,
            'rank_ic_full': ic_full, 'rank_ic_recent2017': ic_recent}
        pt = full.get('portfolio_alpha_t_nw_lag3') if full else None
        ptr = recent.get('portfolio_alpha_t_nw_lag3') if recent else None
        print(f"    {tag:14s} PORT_t full={pt}  recent2017={ptr}  rankIC_full={ic_full['ic']}", flush=True)
    results['_meta'] = {'confband_source': confband_src, 'top_n': TOP_N,
                        'alpha_mean_col': ALPHA_MEAN_COL, 'burn_in': BURN_IN,
                        'retrain_every': RETRAIN_EVERY, 'shrink_lambda': SHRINK_LAMBDA,
                        'features': FEATS, 'n_forecast_months': int(fc['ym'].nunique()),
                        'recent_lo': RECENT_LO}
    json.dump(results, open(OUTDIR + "/variant_results.json", "w"), indent=2, default=str)
    print("[4] done ->", OUTDIR + "/variant_results.json", flush=True)

if __name__ == "__main__":
    main()
