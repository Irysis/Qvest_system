import pyarrow.parquet as pq, pandas as pd, numpy as np
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
m=pq.read_table(R+"macro_fred.parquet",memory_map=False).to_pandas()
v=m[m['Series_ID']=='VIXCLS'][['Date','Value']].dropna(); v['Date']=pd.to_datetime(v['Date'])
print('macro_fred VIXCLS dow', v.Date.dt.dayofweek.value_counts().sort_index().to_dict(), v.Date.min(), v.Date.max(), len(v))
print(v[(v.Date>='2020-03-12')&(v.Date<='2020-03-19')])
fw=pq.read_table(R+"fred_macro_wide.parquet",memory_map=False).to_pandas(); fw['Date']=pd.to_datetime(fw['Date'])
print(fw[(fw.Date>='2020-03-12')&(fw.Date<='2020-03-19')][['Date','VIX','HY_Spread','Term_Spread']])
fv=fw[['Date','VIX']].dropna()
print('fredwide VIX dow', fv.Date.dt.dayofweek.value_counts().sort_index().to_dict())
rd=pq.read_table(R+"regime_daily_v2.parquet",memory_map=False).to_pandas(); rd['Date']=pd.to_datetime(rd['Date'])
print(rd[(rd.Date>='2020-03-12')&(rd.Date<='2020-03-19')][['Date','MRS','VIX_z_smooth','HY_z_smooth','ax1_VIX']])
# other series in macro_fred with dow
for s in ['BAMLH0A0HYM2','T10Y2Y','DEXKOUS','SP500']:
    x=m[m['Series_ID']==s]; x=x.assign(Date=pd.to_datetime(x['Date']))
    print(s, x.Date.dt.dayofweek.value_counts().sort_index().to_dict())
print(m.Series_ID.unique()[:40])
