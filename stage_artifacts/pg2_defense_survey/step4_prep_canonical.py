# STEP 4 prep — write cs_scores/returns/bench parquets for canonical PORT_t on top defense candidates
import pyarrow.parquet as pq, pandas as pd, numpy as np, json, os
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PANEL=ROOT+"/.cache/discovery/explore_panel.parquet"; BENCH=ROOT+"/.cache/benchmark.parquet"
REG=ROOT+"/02_Infrastructure/factor_db/factor_registry.json"
with open(REG) as f: reg=json.load(f)
CANDS=['D20_EW_Beta_126','D11_FP_Beta','D50_MaxDrawdown','D45_Downside_Dev',
       'Q07_Earnings_Stability','M08_Residual_Mom','Q25_Ohlson_O']

# forward bm indexed at signal month ym
b=pq.read_table(BENCH).to_pandas(); b['ym']=pd.to_datetime(b['Date']).dt.strftime('%Y-%m'); b=b.dropna(subset=['BM_Ret'])
b['lr']=np.log1p(b['BM_Ret'].clip(lower=-0.99))
bm=b.groupby('ym')['lr'].sum().apply(np.expm1).reset_index(); bm.columns=['ym','bm_ret']; bm=bm.sort_values('ym')
bm['bm_fwd']=bm['bm_ret'].shift(-1)
# Date = last calendar day-ish of signal month (use month-start; canonical uses Date only as key)
bm['Date']=pd.to_datetime(bm['ym']+"-01")
bench_out=bm.dropna(subset=['bm_fwd'])[['Date','bm_fwd']].rename(columns={'bm_fwd':'BM_Ret'})

pf=pq.read_table(PANEL, columns=['ym','Ticker','fwd_ret_1m']+CANDS).to_pandas()
pf['Date']=pd.to_datetime(pf['ym']+"-01")
returns_out=pf[['Date','Ticker','fwd_ret_1m']].dropna().rename(columns={'fwd_ret_1m':'Ret_1m'})

def orient(code,s):
    d=(reg.get(code,{}).get('direction') or 'higher_better'); return s if d=='higher_better' else -s

os.makedirs(ROOT+"/stage_artifacts/pg2_defense_survey/cs", exist_ok=True)
returns_out.to_parquet(ROOT+"/stage_artifacts/pg2_defense_survey/cs/cs_returns.parquet", index=False)
bench_out.to_parquet(ROOT+"/stage_artifacts/pg2_defense_survey/cs/cs_bench.parquet", index=False)
for code in CANDS:
    sc=pf[['Date','Ticker',code]].dropna().copy()
    sc['score']=orient(code, sc[code].values)
    sc=sc[['Date','Ticker','score']]
    d=ROOT+f"/stage_artifacts/pg2_defense_survey/cs/{code}"; os.makedirs(d,exist_ok=True)
    sc.to_parquet(d+"/cs_scores.parquet", index=False)
    # bench+returns copied per dir (runner reads from CS_SCRATCH)
    returns_out.to_parquet(d+"/cs_returns.parquet", index=False)
    bench_out.to_parquet(d+"/cs_bench.parquet", index=False)
print("prepared canonical scratch for:", CANDS)
print("returns rows:", len(returns_out), "| bench rows:", len(bench_out), "| months:", returns_out['Date'].nunique())
