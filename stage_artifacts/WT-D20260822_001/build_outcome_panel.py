# -*- coding: utf-8 -*-
"""
FQ-236 Lane D — 결과량 3계열(Y1a/Y1b/Y2) 월간 패널 생성 + 유니버스 소급 커버리지 census.
사전등록: stage_artifacts/WT-D20260822_001/preregistration_spec.json (본 스크립트 실행 前 기록)

PIT: 멤버십/유동성/거래정지 = 홀딩월 첫 거래일 직전 거래일(d0) 정보만. 결과량 = 홀딩월 실현 수익 분포.
     진행월(마지막 미완결 월) 제외.
"""
import os, json
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", r"C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT = os.path.join(ROOT, "stage_artifacts", "WT-D20260822_001")
os.makedirs(OUT, exist_ok=True)

LIQ_PRIMARY = 2e8
LIQ_DIAG = 5e7
MIN_XS = 50
MIN_DAY_FRAC = 0.60
ROLL_MONTHS = 60

print("[1] load RAWDATA ...", flush=True)
cols = ['Date', 'Ticker', 'Ret', 'Close', 'Vol', 'K200', 'KQ150', 'AdminStock', 'TradingHalt']
df = pq.read_table(os.path.join(ROOT, ".cache/RAWDATA.parquet"), columns=cols,
                   filters=[('Date', '>=', pd.Timestamp('1998-01-01').date())]).to_pandas()
df['Date'] = pd.to_datetime(df['Date'])
print("   rows", len(df), df['Date'].min().date(), df['Date'].max().date(), flush=True)

# --- sanity firewall: 물리 불가능 일간 수익 제거 (|Ret| > 1.0) ---
n_bad = int((df['Ret'].abs() > 1.0).sum())
df.loc[df['Ret'].abs() > 1.0, 'Ret'] = np.nan
print("   sanity: |Ret|>1.0 -> NA :", n_bad, flush=True)

df = df.sort_values(['Ticker', 'Date'], kind='mergesort').reset_index(drop=True)
df['tv'] = df['Close'] * df['Vol']
df['adv20'] = df.groupby('Ticker', sort=False)['tv'].transform(
    lambda s: s.rolling(20, min_periods=15).mean())
print("[2] adv20 done", flush=True)

df['ym'] = df['Date'].dt.to_period('M')

# 거래일 달력 + 월별 첫 거래일 / 직전 거래일(d0)
tdays = np.sort(df['Date'].unique())
tser = pd.Series(tdays)
tdf = pd.DataFrame({'Date': tser, 'ym': tser.dt.to_period('M')})
first_td = tdf.groupby('ym')['Date'].min()
ndays = tdf.groupby('ym')['Date'].size()
pos = {d: i for i, d in enumerate(tdays)}
d0_map = {}
for ym, fd in first_td.items():
    i = pos[fd]
    if i == 0:
        continue
    d0_map[ym] = tdays[i - 1]

# 결정일 스냅샷
snap = df[df['Date'].isin(set(d0_map.values()))][
    ['Date', 'Ticker', 'K200', 'KQ150', 'AdminStock', 'TradingHalt', 'adv20']].copy()
snap = snap.set_index(['Date', 'Ticker'])

# 월간 수익
print("[3] monthly returns ...", flush=True)
g = df.dropna(subset=['Ret']).groupby(['ym', 'Ticker'])['Ret']
mret = g.apply(lambda s: np.prod(1.0 + s.values) - 1.0).rename('Ret_1m').reset_index()
mcnt = g.size().rename('nobs').reset_index()
mret = mret.merge(mcnt, on=['ym', 'Ticker'])
mret['ndays_m'] = mret['ym'].map(ndays)
mret = mret[mret['nobs'] >= MIN_DAY_FRAC * mret['ndays_m']]
print("   monthly rows", len(mret), flush=True)


def q7(x, p):
    return float(np.quantile(x, p, method='linear'))


def build_series(universe_mode, liq_thr):
    """universe_mode: 'union' (K200|KQ150) | 'k200' (K200 only)"""
    rows = []
    hist = {}   # ym -> returns array (for rolling thresholds)
    yms = sorted([ym for ym in d0_map.keys() if ym in set(mret['ym'])])
    mret_by_ym = {ym: gg for ym, gg in mret.groupby('ym')}
    for ym in yms:
        d0 = d0_map[ym]
        try:
            s = snap.loc[d0]
        except KeyError:
            continue
        k200 = s['K200'].fillna(0) > 0
        kq = s['KQ150'].fillna(0) > 0
        memb = k200 | kq if universe_mode == 'union' else k200
        ok = memb & (s['AdminStock'].fillna(0) == 0) & (s['TradingHalt'].fillna(0) == 0) \
             & (s['adv20'].fillna(0) >= liq_thr)
        tickers = set(s.index[ok])
        if not tickers:
            continue
        gg = mret_by_ym.get(ym)
        if gg is None:
            continue
        r = gg[gg['Ticker'].isin(tickers)]['Ret_1m'].values
        r = r[np.isfinite(r)]
        n = len(r)
        if n < MIN_XS:
            continue
        q10, q50, q90 = q7(r, .10), q7(r, .50), q7(r, .90)
        up, dn = q90 - q50, q50 - q10
        y1b = up - dn
        y1a = y1b / (q90 - q10) if (q90 - q10) > 0 else np.nan
        # Y2: 직전 60개월 풀링 문턱
        prev = [hist[k] for k in sorted(hist.keys()) if k < ym][-ROLL_MONTHS:]
        y2 = np.nan
        n_roll = len(prev)
        if n_roll >= 24:
            pool = np.concatenate(prev)
            th_hi, th_lo = q7(pool, .90), q7(pool, .10)
            y2 = float((r > th_hi).mean() - (r < th_lo).mean())
        hist[ym] = r
        rows.append(dict(ym=str(ym), d0=str(pd.Timestamp(d0).date()), n_names=n,
                         q10=q10, q50=q50, q90=q90,
                         Y1a=y1a, Y1b=y1b, Y2=y2, n_roll_months=n_roll,
                         xs_sd=float(np.std(r, ddof=1)), xs_mean=float(np.mean(r))))
    return pd.DataFrame(rows)


print("[4] build series ...", flush=True)
res = {}
res['union_liq2e8'] = build_series('union', LIQ_PRIMARY)
res['union_liq5e7'] = build_series('union', LIQ_DIAG)
res['k200_liq2e8'] = build_series('k200', LIQ_PRIMARY)

for k, v in res.items():
    v.to_csv(os.path.join(OUT, f"outcome_panel_{k}.csv"), index=False)
    print(f"   {k}: n={len(v)}  {v['ym'].min() if len(v) else '-'} .. {v['ym'].max() if len(v) else '-'}",
          flush=True)

# --- 유니버스 소급 커버리지 census (Gate 2) ---
print("[5] membership census ...", flush=True)
cen = []
snap_all = df[df['Date'].isin(set(d0_map.values()))]
for ym, d0 in sorted(d0_map.items()):
    s = snap_all[snap_all['Date'] == d0]
    if len(s) == 0:
        continue
    k2 = int((s['K200'].fillna(0) > 0).sum())
    kq = int((s['KQ150'].fillna(0) > 0).sum())
    un = int(((s['K200'].fillna(0) > 0) | (s['KQ150'].fillna(0) > 0)).sum())
    liq = int((((s['K200'].fillna(0) > 0) | (s['KQ150'].fillna(0) > 0)) &
               (s['AdminStock'].fillna(0) == 0) & (s['TradingHalt'].fillna(0) == 0) &
               (s['adv20'].fillna(0) >= LIQ_PRIMARY)).sum())
    cen.append(dict(ym=str(ym), d0=str(pd.Timestamp(d0).date()),
                    n_k200=k2, n_kq150=kq, n_union=un, n_union_eligible_2e8=liq))
cen = pd.DataFrame(cen)
cen.to_csv(os.path.join(OUT, "universe_membership_census.csv"), index=False)
print("   census rows", len(cen), flush=True)
print(cen.groupby(cen['ym'].str[:4]).agg(
    k200=('n_k200', 'mean'), kq150=('n_kq150', 'mean'),
    union=('n_union', 'mean'), elig=('n_union_eligible_2e8', 'mean')).round(1).to_string())
print("DONE")
