import sys, pandas as pd
p = sys.argv[1]
df = pd.read_parquet(p)
print("shape", df.shape)
print("cols", list(df.columns)[:60])
print("dtypes head:")
print(df.dtypes.head(20))
print("date range:", df.iloc[:,0].min(), "..", df.iloc[:,0].max() if df.shape[0] else "NA")
print(df.head(3).to_string())
