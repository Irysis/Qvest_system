# STEP 2b — confound-corrected defensiveness (relative to universe baseline + beta asymmetry)
#
# Adversarial correction to step2: raw beta<1 & down_active>0 are near-universal because
# the panel universe (STR_1715 tracked ~256 names) long-only top-quintiles sit below market beta.
# We need confound-free discriminators:
#   (A) baseline reference = score_eff top-quintile long-leg (current book signal) beta/down_active/EWuniv
#   (B) EW-of-universe long-leg (all names) as beta~1 anchor
#   (C) beta_asymmetry = beta(down months) - beta(up months). TRUE defensive => negative (down-beta < up-beta).
#       This is confound-free: it measures whether the long-leg de-risks specifically in down markets.
#   (D) excess_down_active = down_active(factor) - down_active(EW universe)  [does it protect MORE than passive?]
import pyarrow.parquet as pq, pandas as pd, numpy as np, json, csv, os
from scipy.stats import spearmanr

ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PANEL=ROOT+"/.cache/discovery/explore_panel.parquet"
BENCH=ROOT+"/.cache/benchmark.parquet"
REG=ROOT+"/02_Infrastructure/factor_db/factor_registry.json"
OUT=ROOT+"/stage_artifacts/pg2_defense_survey"

with open(REG,'r',encoding='utf-8') as f: reg=json.load(f)
prev=pd.read_csv(OUT+"/step2_characterization.csv")
codes=[c for c in prev['code'].tolist()]
BOOK3=['Q07_Earnings_Stability','M08_Residual_Mom','Q25_Ohlson_O']

# benchmark forward monthly
b=pq.read_table(BENCH).to_pandas()
b['ym']=pd.to_datetime(b['Date']).dt.strftime('%Y-%m'); b=b.dropna(subset=['BM_Ret'])
b['lr']=np.log1p(b['BM_Ret'].clip(lower=-0.99))
bm=b.groupby('ym')['lr'].sum().apply(np.expm1).rename('bm_ret').reset_index().sort_values('ym')
bm['bm_fwd']=bm['bm_ret'].shift(-1); bm_fwd=bm.set_index('ym')['bm_fwd']

need=['ym','Ticker','fwd_ret_1m','score_eff']+[c for c in codes if c in set(pq.ParquetFile(PANEL).schema_arrow.names)]
pf=pq.read_table(PANEL, columns=list(dict.fromkeys(need))).to_pandas()
pf['bm_fwd']=pf['ym'].map(bm_fwd); pf=pf.dropna(subset=['fwd_ret_1m','bm_fwd'])
months=sorted(pf['ym'].unique())
month_frames={ym:g for ym,g in pf.groupby('ym')}
mbm=pf.groupby('ym')['bm_fwd'].first()
down_m=set(mbm[mbm<0].index); up_m=set(mbm[mbm>=0].index)

def orient(code,s):
    d=(reg.get(code,{}).get('direction') or 'higher_better')
    return s if d=='higher_better' else -s

def longleg_series(code, use_score=False):
    r={}
    for ym in months:
        g=month_frames[ym]
        key='score_eff' if use_score else code
        sub=g[[key,'fwd_ret_1m']].dropna()
        if len(sub)<20: continue
        fv=(sub['score_eff'].values if use_score else orient(code,sub[key].values))
        fr=sub['fwd_ret_1m'].values
        n=len(sub); k=max(1,int(round(n*0.2)))
        top=np.argsort(-fv)[:k]
        r[ym]=np.mean(fr[top])
    return pd.Series(r)

def ew_universe_series():
    r={}
    for ym in months:
        g=month_frames[ym]; fr=g['fwd_ret_1m'].dropna().values
        if len(fr)>=20: r[ym]=fr.mean()
    return pd.Series(r)

def metrics(lret):
    idx=lret.index
    bmf=mbm.reindex(idx)
    act=lret - bmf
    xy=pd.concat([lret.rename('y'),bmf.rename('x')],axis=1).dropna()
    beta_all=np.polyfit(xy['x'],xy['y'],1)[0] if len(xy)>10 else np.nan
    dn=[m for m in idx if m in down_m]; upn=[m for m in idx if m in up_m]
    xyd=pd.concat([lret[dn].rename('y'),bmf[dn].rename('x')],axis=1).dropna()
    xyu=pd.concat([lret[upn].rename('y'),bmf[upn].rename('x')],axis=1).dropna()
    beta_dn=np.polyfit(xyd['x'],xyd['y'],1)[0] if len(xyd)>10 else np.nan
    beta_up=np.polyfit(xyu['x'],xyu['y'],1)[0] if len(xyu)>10 else np.nan
    return dict(beta_all=beta_all, beta_dn=beta_dn, beta_up=beta_up,
                beta_asym=(beta_dn-beta_up) if (beta_dn==beta_dn and beta_up==beta_up) else np.nan,
                down_active=act[dn].mean() if dn else np.nan)

# baselines
ew=ew_universe_series(); ew_m=metrics(ew)
sc=longleg_series(None, use_score=True); sc_m=metrics(sc)
print("EW-universe long-leg: beta_all %.3f beta_asym %+.3f down_active %+.4f"%(ew_m['beta_all'],ew_m['beta_asym'],ew_m['down_active']))
print("score_eff long-leg:   beta_all %.3f beta_asym %+.3f down_active %+.4f"%(sc_m['beta_all'],sc_m['beta_asym'],sc_m['down_active']))

rows=[]
for code in codes:
    if code not in pf.columns: continue
    m=metrics(longleg_series(code))
    rows.append(dict(code=code,
        beta_all=round(m['beta_all'],3) if m['beta_all']==m['beta_all'] else None,
        beta_dn=round(m['beta_dn'],3) if m['beta_dn']==m['beta_dn'] else None,
        beta_up=round(m['beta_up'],3) if m['beta_up']==m['beta_up'] else None,
        beta_asym=round(m['beta_asym'],3) if m['beta_asym']==m['beta_asym'] else None,
        down_active=round(m['down_active'],4) if m['down_active']==m['down_active'] else None,
        excess_down_active=round(m['down_active']-ew_m['down_active'],4) if m['down_active']==m['down_active'] else None,
    ))
rb=pd.DataFrame(rows)
merged=prev.merge(rb, on='code', how='left', suffixes=('','_r'))

# confound-free verdict:
#  TRUE_DEFENSE: beta_asym < -0.02 (de-risks in down markets) AND excess_down_active > 0 (beats passive protection)
#  STRONG if also crisis_ic>0 and beta_all < ew beta
def verdict2(r):
    ba=r['beta_asym']; eda=r['excess_down_active']; ci=r['crisis_ic']
    if pd.isna(ba) or pd.isna(eda): return 'INSUFFICIENT'
    core = (ba < -0.02) and (eda > 0)
    if core:
        strong = (ci is not None and ci>0) and (r['beta_all'] is not None and r['beta_all']<ew_m['beta_all'])
        return 'TRUE_DEFENSE_STRONG' if strong else 'TRUE_DEFENSE'
    # partial: one of the two
    if (ba < -0.02) or (eda > 0.002):
        return 'PARTIAL'
    return 'LABEL_ONLY'
merged['verdict2']=merged.apply(verdict2,axis=1)

# defense strength score (for ranking): lower beta_asym (more negative) + higher excess_down_active + higher crisis_ic
def z(s):
    s=pd.to_numeric(s,errors='coerce'); return (s-s.mean())/s.std()
merged['def_strength']= (-z(merged['beta_asym']) + z(merged['excess_down_active']) + 0.5*z(merged['crisis_ic'])).round(3)

merged=merged.sort_values('def_strength', ascending=False)
merged.to_csv(OUT+"/step2b_relative_ranked.csv", index=False, encoding='utf-8-sig')
print("\nbaselines -> EW beta_asym %+.3f down_active %+.4f | score_eff beta_asym %+.3f"%(ew_m['beta_asym'],ew_m['down_active'],sc_m['beta_asym']))
print("\nverdict2 counts:"); print(merged['verdict2'].value_counts().to_string())
print("\nBOOK-3:")
print(merged[merged['code'].isin(BOOK3)][['code','beta_all','beta_asym','down_active','excess_down_active','crisis_ic','recent36_ic','def_strength','verdict2']].to_string(index=False))
print("\nTOP 20 by def_strength:")
print(merged.head(20)[['code','name','defclass','beta_all','beta_asym','excess_down_active','crisis_ic','recent36_ic','def_strength','verdict2']].to_string(index=False))
