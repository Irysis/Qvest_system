# STEP 3 — ranking (KR-honest defense strength) + orthogonality vs book-3 & score_eff
#
# KR structural finding (step2b): beta_asym positive for ALL long-only long-legs
#   (down-market beta > up-market beta) -> no long-only factor de-risks specifically in crashes.
#   Therefore defense must be read as LEVEL: low beta_all + high crisis_ic + protects more
#   than passive (excess_down_active) + still alive recently (recent36_ic).
#
# def_score = z(-beta_all) + z(crisis_ic) + z(excess_down_active) + 0.5*z(recent36_ic)
#   (removed beta_asym: non-discriminating + outlier-driven)
#
# Orthogonality: monthly long-leg-active return correlation of each top defense factor vs
#   Q07 / M08 / Q25 / score_eff long-leg-active (ACTIVE basis, per 06-18 lesson gross!=active).
import pyarrow.parquet as pq, pandas as pd, numpy as np, json, os
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PANEL=ROOT+"/.cache/discovery/explore_panel.parquet"; BENCH=ROOT+"/.cache/benchmark.parquet"
REG=ROOT+"/02_Infrastructure/factor_db/factor_registry.json"; OUT=ROOT+"/stage_artifacts/pg2_defense_survey"
with open(REG) as f: reg=json.load(f)
df=pd.read_csv(OUT+"/step2b_relative_ranked.csv")
BOOK3=['Q07_Earnings_Stability','M08_Residual_Mom','Q25_Ohlson_O']

def z(s): s=pd.to_numeric(s,errors='coerce'); return (s-s.mean())/s.std()
df['def_score']=(z(-df['beta_all'])+z(df['crisis_ic'])+z(df['excess_down_active'])+0.5*z(df['recent36_ic'])).round(3)
df=df.sort_values('def_score',ascending=False).reset_index(drop=True)
df['rank']=range(1,len(df)+1)

# ---- long-leg active return series for orthogonality ----
b=pq.read_table(BENCH).to_pandas(); b['ym']=pd.to_datetime(b['Date']).dt.strftime('%Y-%m'); b=b.dropna(subset=['BM_Ret'])
b['lr']=np.log1p(b['BM_Ret'].clip(lower=-0.99))
bm=b.groupby('ym')['lr'].sum().apply(np.expm1).reset_index(); bm.columns=['ym','bm_ret']; bm=bm.sort_values('ym')
bm['bm_fwd']=bm['bm_ret'].shift(-1); bm_fwd=bm.set_index('ym')['bm_fwd']

top_codes=df.head(25)['code'].tolist()
need_codes=list(dict.fromkeys(top_codes+BOOK3))
avail=set(pq.ParquetFile(PANEL).schema_arrow.names)
need_codes=[c for c in need_codes if c in avail]
pf=pq.read_table(PANEL, columns=['ym','Ticker','fwd_ret_1m','score_eff']+need_codes).to_pandas()
pf['bm_fwd']=pf['ym'].map(bm_fwd); pf=pf.dropna(subset=['fwd_ret_1m','bm_fwd'])
months=sorted(pf['ym'].unique()); mf={ym:g for ym,g in pf.groupby('ym')}
def orient(code,s):
    d=(reg.get(code,{}).get('direction') or 'higher_better'); return s if d=='higher_better' else -s
def active_series(code, use_score=False):
    r={}
    for ym in months:
        g=mf[ym]; key='score_eff' if use_score else code
        sub=g[[key,'fwd_ret_1m','bm_fwd']].dropna(subset=[key,'fwd_ret_1m'])
        if len(sub)<20: continue
        fv=sub['score_eff'].values if use_score else orient(code,sub[key].values)
        fr=sub['fwd_ret_1m'].values; n=len(sub); k=max(1,int(round(n*0.2)))
        top=np.argsort(-fv)[:k]
        r[ym]=np.mean(fr[top]) - sub['bm_fwd'].iloc[0]
    return pd.Series(r)

series={c:active_series(c) for c in need_codes}
series['score_eff']=active_series(None,use_score=True)
S=pd.DataFrame(series)
# correlation of each top code vs book3 + score_eff (ACTIVE basis)
refs=['Q07_Earnings_Stability','M08_Residual_Mom','Q25_Ohlson_O','score_eff']
orth=[]
for c in top_codes:
    if c not in S.columns: continue
    row={'code':c}
    for rname in refs:
        cc=S[[c,rname]].dropna()
        row['cor_'+rname.replace('_Earnings_Stability','').replace('_Residual_Mom','').replace('_Ohlson_O','')]=round(cc[c].corr(cc[rname]),3) if len(cc)>24 else None
    orth.append(row)
orthdf=pd.DataFrame(orth)
final=df.head(25).merge(orthdf,on='code',how='left')
final.to_csv(OUT+"/step3_ranking_orthogonality.csv",index=False,encoding='utf-8-sig')

cols=['rank','code','name','defclass','beta_all','crisis_ic','excess_down_active','recent36_ic','def_score','cor_Q07','cor_M08','cor_Q25','cor_score_eff']
print("TOP 25 defense factors (KR-honest: low-beta level + crisis IC + excess protection):")
print(final[cols].to_string(index=False))
print("\nBOOK-3 rank position:")
for c in BOOK3:
    r=df[df['code']==c]
    if len(r): print(f"  {c}: rank {int(r['rank'].iloc[0])}/166  def_score {r['def_score'].iloc[0]}")
print("\nsaved:", OUT+"/step3_ranking_orthogonality.csv")
