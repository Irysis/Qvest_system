import pyarrow.parquet as pq, pandas as pd, numpy as np
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
rd=pq.read_table(R+"regime_daily_v2.parquet",memory_map=False).to_pandas()
print(rd.columns.tolist()); print(rd.shape, rd.Date.min(), rd.Date.max())
fw=pq.read_table(R+"fred_macro_wide.parquet",memory_map=False).to_pandas()
print(fw.columns.tolist()[:30]); 
m=pq.read_table(R+"macro_fred.parquet",memory_map=False).to_pandas()
print(m.columns.tolist()); 
sid='Series_ID' if 'Series_ID' in m.columns else 'Series'
v=m[m[sid]=='VIXCLS'][['Date','Value']].dropna().copy(); v['Date']=pd.to_datetime(v['Date']); v=v.groupby('Date').last().sort_index()
rd['Date']=pd.to_datetime(rd['Date']); rd=rd.set_index('Date').sort_index()
# rebuild z and smooth from VIX on FRED dates (rolling 756, min 252) then 20d MA
vv=v['Value']
z=(vv-vv.rolling(756,min_periods=252).mean())/vv.rolling(756,min_periods=252).std()
zs=z.rolling(20,min_periods=1).mean()
df=pd.DataFrame({'zs0':zs,'zs1':zs.shift(1)}).join(rd[['VIX_z_smooth','ax1_VIX' if 'ax1_VIX' in rd.columns else rd.columns[4]]],how='inner').dropna()
print('n',len(df))
for c in ['zs0','zs1']:
    print(c,'max|diff|',np.abs(df[c]-df['VIX_z_smooth']).max(),'mean|diff|',np.abs(df[c]-df['VIX_z_smooth']).mean(),'corr_d',np.corrcoef(df[c].diff().dropna(),df['VIX_z_smooth'].diff().dropna())[0,1])
print(df.tail(8))
