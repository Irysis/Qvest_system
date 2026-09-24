import pyarrow.parquet as pq, pandas as pd
m=pq.read_table("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/macro_fred.parquet",memory_map=False).to_pandas()
c=m[m.Series_ID=='CPIAUCSL'][['Date','Value','Frequency']].copy(); c['Date']=pd.to_datetime(c['Date'])
print(c.tail(4)); print('day-of-month counts', c.Date.dt.day.value_counts().head(3).to_dict())
