#!/usr/bin/env python
# ml_momentum_ensemble.py — 15 모멘텀 feature → XGBoost 앙상블 (factor momentum, PIT rolling, GPU)
# 도훈 mandate 2026-06-05: ML/DL 모멘텀 허용.
# PIT: feature는 과거 shift(+), label(fwd_ret)만 미래 shift(-21) — label은 train에만, predict 시 NaN 제외.
#      (data_table_shift_convention 정합: forward는 label 전용, feature lookahead 절대 금지 — Cycle 50 교훈)
import os, numpy as np, pandas as pd, pyarrow.parquet as pq
import xgboost as xgb
from scipy.stats import spearmanr

ROOT = os.environ.get('CLAUDE_PROJECT_DIR', 'G:/Quant_Module_Moltbot')
PARQUET = os.path.join(ROOT, '.cache', 'rawdata.parquet')

# ---- 1. Load ----
cols = ['Date','Ticker','Close','Vol','Size','Ret','K200','KQ150','AdminStock','TradingHalt']
df = pq.read_table(PARQUET, columns=cols).to_pandas()
df['Date'] = pd.to_datetime(df['Date'])
df = df.sort_values(['Ticker','Date']).reset_index(drop=True)
print(f"[load] {len(df):,} rows | {df['Ticker'].nunique()} tickers", flush=True)

gc = df.groupby('Ticker')['Close']

# ---- 2. Universe: KOSPI200 ∪ KOSDAQ150 실제 멤버십 + 유동성 2e8 + 정상종목 ----
df['TV20'] = (df['Close']*df['Vol']).groupby(df['Ticker']).transform(lambda x: x.rolling(20, min_periods=10).mean())
for c in ['K200','KQ150','AdminStock','TradingHalt']:
    df[c] = df[c].fillna(False).astype(bool)
df['univ'] = (df['K200']|df['KQ150']) & (df['TV20']>=2e8) & (~df['AdminStock']) & (~df['TradingHalt'])

# ---- 3. 15 모멘텀 feature (PIT: 과거 shift만) ----
feats = {}
feats['mom3_1']  = gc.shift(21)/gc.shift(63)-1
feats['mom6_1']  = gc.shift(21)/gc.shift(126)-1
feats['mom9_1']  = gc.shift(21)/gc.shift(189)-1
feats['mom12_1'] = gc.shift(21)/gc.shift(252)-1
feats['mom18_1'] = gc.shift(21)/gc.shift(378)-1
feats['mom24_1'] = gc.shift(21)/gc.shift(504)-1
feats['mom2_12'] = gc.shift(42)/gc.shift(252)-1
feats['mom6_12'] = gc.shift(126)/gc.shift(252)-1
feats['rev1m']   = gc.shift(21)/df['Close']-1          # 1M reversal (현재 대비)
feats['rev2w']   = gc.shift(10)/df['Close']-1          # 2W reversal
hi52 = gc.transform(lambda x: x.shift(1).rolling(252, min_periods=120).max())
lo52 = gc.transform(lambda x: x.shift(1).rolling(252, min_periods=120).min())
feats['mom52w']    = df['Close']/hi52-1                 # 52주高 근접
feats['mom52wlow'] = lo52/df['Close']-1                 # 52주低 근접 (reversal)
ret1 = gc.pct_change()
vol126 = ret1.groupby(df['Ticker']).transform(lambda x: x.shift(1).rolling(126, min_periods=60).std())
feats['momvol']    = (gc.shift(21)/gc.shift(126)-1)/(vol126+1e-8)
feats['momsharpe'] = (gc.shift(21)/gc.shift(252)-1)/(vol126+1e-8)
feats['momaccel']  = (gc.shift(21)/gc.shift(126)-1) - (gc.shift(126)/gc.shift(252)-1)
for k,v in feats.items(): df[k] = v.values
FCOLS = list(feats.keys())
print(f"[features] {len(FCOLS)}종 계산 완료", flush=True)

# ---- 4. Forward 1M label (PIT: 미래 — train label만, predict 제외) ----
df['fwd_ret'] = gc.shift(-21)/df['Close']-1            # forward 1M (lookahead은 label에만)

# ---- 4b. Forward-label PIT self-assert (Cycle 50 회귀 방지 · python-policy.md 언어무관 의무) ----
# bear_date_audit.R 동등 검증: COVID 2020-02-19 peak 직후 universe forward 21d는 강하게 음수여야 함.
#   forward면 -34%대(시장 폭락), backward(shift 부호 함정)면 +1.8%대 → assert로 즉시 중단(buggy label 학습 차단).
_covid = pd.Timestamp('2020-02-19')
_cw = df[df['univ'] & df['Date'].between(_covid - pd.Timedelta(days=7), _covid + pd.Timedelta(days=7))]
_cw = _cw.dropna(subset=['fwd_ret'])
if len(_cw) >= 20:
    _mean_fwd = float(_cw['fwd_ret'].mean())
    assert _mean_fwd < -0.05, (
        f"[PIT FAIL] forward-label sanity: COVID(2020-02-19) 21d universe mean fwd_ret={_mean_fwd:+.4f} "
        f"(>= -5%). backward label 부호 함정 의심 — Cycle 50 회귀. 학습 중단.")
    print(f"[PIT self-assert] COVID forward 21d mean fwd_ret={_mean_fwd:+.4f} (< -5% OK · forward 정합)", flush=True)
else:
    print(f"[PIT self-assert][WARN] COVID window 데이터 부족(n={len(_cw)}) — forward-label sanity skip. 수동 확인 요망.", flush=True)

# ---- 5. 월말 sig_date + universe + feature 완비 ----
df['ym'] = df['Date'].dt.to_period('M')
df['is_me'] = df.groupby('ym')['Date'].transform('max')==df['Date']
sig = df[df['is_me'] & df['univ']].dropna(subset=FCOLS).copy().sort_values('Date')
print(f"[sig] {len(sig):,} rows | {sig['Date'].nunique()} months | avg {len(sig)//max(sig['Date'].nunique(),1)}/월", flush=True)

# ---- 6. XGBoost device (gpu→cpu fallback) ----
try:
    xgb.train({'tree_method':'hist','device':'cuda'}, xgb.DMatrix(np.random.rand(20,2), label=np.random.rand(20)), num_boost_round=1)
    DEVICE='cuda'
except Exception as e:
    DEVICE='cpu'; print(f"[xgb] cuda 실패→cpu: {e}", flush=True)
print(f"[xgb device] {DEVICE}", flush=True)
params = dict(tree_method='hist', device=DEVICE, max_depth=4, eta=0.05,
              subsample=0.8, colsample_bytree=0.8, objective='reg:squarederror', verbosity=0)

# ---- 7. Expanding walk-forward (PIT: d 이전만 train), 연 1회 retrain ----
dates = sorted(pd.Timestamp(d) for d in sig['Date'].unique())
START_OOS = pd.Timestamp('2012-01-01')   # 초기 ~7년 train 후 OOS
oos, model, last_year = [], None, None
for d in dates:
    if d < START_OOS: continue
    if last_year != d.year:
        tr = sig[sig['Date'] < d].dropna(subset=['fwd_ret'])
        if len(tr) < 500: continue
        model = xgb.train(params, xgb.DMatrix(tr[FCOLS], label=tr['fwd_ret']), num_boost_round=200)
        last_year = d.year
    if model is None: continue
    te = sig[sig['Date']==d].copy()
    if len(te)==0: continue
    te['pred'] = model.predict(xgb.DMatrix(te[FCOLS]))
    oos.append(te[['Date','Ticker','pred','fwd_ret']])

oos = pd.concat(oos, ignore_index=True)
# ---- 8. OOS rolling IC (pred vs realized) ----
ic = oos.dropna(subset=['fwd_ret']).groupby('Date').apply(
    lambda x: spearmanr(x['pred'], x['fwd_ret'])[0] if len(x)>5 else np.nan)
ic = ic.dropna()
print(f"[ML OOS IC] mean={ic.mean():.4f} | ICIR={ic.mean()/ic.std():.3f} | pos_rate={ (ic>0).mean():.3f} | n={len(ic)}", flush=True)
imp = sorted(model.get_score(importance_type='gain').items(), key=lambda x:-x[1])
print(f"[feature importance top6] {imp[:6]}", flush=True)

# ---- 9. 예측 score 저장 (→ R fe_ml 백테용) ----
out = os.path.join(ROOT, '.cache', 'ml_momentum_pred.parquet')
oos[['Date','Ticker','pred']].to_parquet(out, index=False)
print(f"[saved] {out} ({len(oos):,} rows)", flush=True)
print("[ML 완료]", flush=True)
