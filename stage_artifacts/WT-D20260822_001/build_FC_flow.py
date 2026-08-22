# -*- coding: utf-8 -*-
"""
FQ-236 Lane D — F_C 기전 부수관측: FlowAsym_t = corr_XS( 개인 순매수/ADV20 , 당월 수익률 ), Spearman
★동월 관측이지만 **포트 결정에 쓰지 않는 사후 기전 검증**이므로 C2 순환참조 아님 (승계 설계 명시 선언).
기전 예측: corr(S_t-, FlowAsym_t) > 0  (평시 개인 = 역추세 매수 → 음의 월내 상관 / 경색 시 반대매매 강제 → 양의 방향 이동)
"""
import os
import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from scipy.stats import spearmanr

ROOT = os.environ.get("QM_ROOT", r"C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT = os.path.join(ROOT, "stage_artifacts", "WT-D20260822_001")
LIQ = 2e8

inv = pq.read_table(os.path.join(ROOT, ".cache/investor_stock/investor_wide.parquet"),
                    columns=['Date', 'Ticker', 'Individual']).to_pandas()
inv['Date'] = pd.to_datetime(inv['Date'])
print("investor range", inv['Date'].min().date(), inv['Date'].max().date(), len(inv), flush=True)
print("Individual abs median", float(inv['Individual'].abs().median()), flush=True)
inv['ym'] = inv['Date'].dt.to_period('M')
flow = inv.groupby(['ym', 'Ticker'])['Individual'].sum().rename('indiv_net').reset_index()

cols = ['Date', 'Ticker', 'Ret', 'Close', 'Vol', 'K200', 'KQ150', 'AdminStock', 'TradingHalt']
df = pq.read_table(os.path.join(ROOT, ".cache/RAWDATA.parquet"), columns=cols,
                   filters=[('Date', '>=', pd.Timestamp('1998-01-01').date())]).to_pandas()
df['Date'] = pd.to_datetime(df['Date'])
df.loc[df['Ret'].abs() > 1.0, 'Ret'] = np.nan
df = df.sort_values(['Ticker', 'Date'], kind='mergesort').reset_index(drop=True)
df['tv'] = df['Close'] * df['Vol']
df['adv20'] = df.groupby('Ticker', sort=False)['tv'].transform(lambda s: s.rolling(20, min_periods=15).mean())
df['ym'] = df['Date'].dt.to_period('M')

cen = pd.read_csv(os.path.join(OUT, "universe_membership_census.csv"))
cen['d0'] = pd.to_datetime(cen['d0'])
d0_map = dict(zip(cen['ym'], cen['d0']))
snap = df[df['Date'].isin(set(d0_map.values()))][
    ['Date', 'Ticker', 'K200', 'KQ150', 'AdminStock', 'TradingHalt', 'adv20']].set_index(['Date', 'Ticker'])

g = df.dropna(subset=['Ret']).groupby(['ym', 'Ticker'])['Ret']
mret = g.apply(lambda s: np.prod(1.0 + s.values) - 1.0).rename('Ret_1m').reset_index()
mcnt = g.size().rename('nobs').reset_index()
ndays = df.groupby('ym')['Date'].nunique()
mret = mret.merge(mcnt, on=['ym', 'Ticker'])
mret['ndays_m'] = mret['ym'].map(ndays)
mret = mret[mret['nobs'] >= 0.60 * mret['ndays_m']]

rows = []
for ym_s, d0 in sorted(d0_map.items()):
    ym = pd.Period(ym_s, 'M')
    try:
        s = snap.loc[d0]
    except KeyError:
        continue
    ok = ((s['K200'].fillna(0) > 0) | (s['KQ150'].fillna(0) > 0)) & \
         (s['AdminStock'].fillna(0) == 0) & (s['TradingHalt'].fillna(0) == 0) & \
         (s['adv20'].fillna(0) >= LIQ)
    tk = s.index[ok]
    if len(tk) < 50:
        continue
    adv = s.loc[tk, 'adv20']
    r = mret[(mret['ym'] == ym) & (mret['Ticker'].isin(set(tk)))].set_index('Ticker')['Ret_1m']
    fl = flow[flow['ym'] == ym].set_index('Ticker')['indiv_net']
    idx = r.index.intersection(fl.index).intersection(adv.index)
    if len(idx) < 50:
        continue
    x = (fl.loc[idx] / adv.loc[idx]).values
    y = r.loc[idx].values
    m = np.isfinite(x) & np.isfinite(y)
    if m.sum() < 50:
        continue
    rho, _ = spearmanr(x[m], y[m])
    rows.append(dict(ym=str(ym), n=int(m.sum()), FlowAsym=float(rho)))

fc = pd.DataFrame(rows)
fc.to_csv(os.path.join(OUT, "FC_flow_panel.csv"), index=False)
print("[F_C] months", len(fc), fc['ym'].min() if len(fc) else '-', fc['ym'].max() if len(fc) else '-')
print(fc['FlowAsym'].describe().round(4).to_string())
