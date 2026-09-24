import pyarrow.parquet as pq, pandas as pd, numpy as np
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
rd=pq.read_table(R+"regime_daily_v2.parquet",memory_map=False).to_pandas()
rd['Date']=pd.to_datetime(rd['Date']); rd=rd.set_index('Date').sort_index()
fw=pq.read_table(R+"fred_macro_wide.parquet",memory_map=False).to_pandas()
fw['Date']=pd.to_datetime(fw['Date']); fw=fw.set_index('Date').sort_index()
print('regime dow counts', rd.index.dayofweek.value_counts().sort_index().to_dict())
print('fredwide dow counts', fw.index.dayofweek.value_counts().sort_index().to_dict())
vix=fw['VIX'].reindex(rd.index).ffill()
d=pd.DataFrame({'dzs':rd['VIX_z_smooth'].diff(),'dv':np.log(vix).diff()}).dropna()
for k in range(-2,4):
    x=d['dv'].shift(k)
    ok=x.notna()
    print('lag k=%d corr(dVIXzs_t, dlogVIX_{t-k}) = %.4f' % (k, np.corrcoef(d['dzs'][ok], x[ok])[0,1]))
# also the axis score & MRS for comparison
a=pd.DataFrame({'dax':rd['ax1_VIX'].diff(),'lv':vix}).dropna()
# ax1 is threshold on z_smooth; test level corr of ax1 with VIX level shifted
for k in range(0,3):
    print('ax1 vs VIX level lag',k, np.corrcoef(rd['ax1_VIX'].reindex(a.index), vix.shift(k).reindex(a.index).fillna(method='bfill'))[0,1])
# check duplicate-name hypothesis: compare VIX_z_smooth vs HY_z_smooth lag structure with HY series
hy=fw['HY_Spread'].reindex(rd.index).ffill()
d2=pd.DataFrame({'dzs':rd['HY_z_smooth'].diff(),'dv':hy.diff()}).dropna()
for k in range(-1,3):
    x=d2['dv'].shift(k); ok=x.notna()
    print('HY lag k=%d corr = %.4f' % (k, np.corrcoef(d2['dzs'][ok], x[ok])[0,1]))
ts=fw['Term_Spread'].reindex(rd.index).ffill()
d3=pd.DataFrame({'dzs':rd['TS_z_smooth'].diff(),'dv':ts.diff()}).dropna()
for k in range(-1,3):
    x=d3['dv'].shift(k); ok=x.notna()
    print('TS lag k=%d corr = %.4f' % (k, np.corrcoef(d3['dzs'][ok], x[ok])[0,1]))
