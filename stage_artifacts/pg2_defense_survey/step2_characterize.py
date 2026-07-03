# STEP 2 — 방어성격 특성화 (AX-001 v2, IC-based diagnostics, no self-synth)
#
# For each defense-candidate factor:
#   - orient Z_Score by registry direction (higher_better as-is / lower_better flip)
#   - monthly cross-sectional Spearman IC (oriented factor -> fwd_ret_1m)  [diagnostic]
#   - top-quintile EW long-leg return per month (oriented) ; active = long - BM_fwd
#   - beta of long-leg-active NOT used; beta of long-leg raw return vs BM (defensive if <1)
#   - down-month vs up-month split by FORWARD BM return (aligned to fwd_ret_1m)
#   - AX-001 v2 metrics:
#       * beta_bm         : OLS beta of long-leg raw monthly return on BM_fwd return
#       * down_active_mean : mean(long-active) in down BM-fwd months (>0 = defensive)
#       * badnormal_ic    : mean IC(down months) / mean IC(up months)
#       * crisis_ic       : mean IC in crisis months (worst tercile BM_fwd)
#       * recent36_ic     : mean IC last 36 months
#   PIT: panel factor_db_{ym} = ym-end snapshot; fwd_ret_1m = ym+1 realized.
#        BM_fwd aligned = BM monthly return of month ym+1 (shift +1 of BM monthly, indexed at ym).
#        -> no realized_ym offset bug (both stock fwd and BM fwd indexed at signal month ym).
import pyarrow.parquet as pq, pandas as pd, numpy as np, json, csv, os
from scipy.stats import spearmanr

ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PANEL=ROOT+"/.cache/discovery/explore_panel.parquet"
BENCH=ROOT+"/.cache/benchmark.parquet"
REG=ROOT+"/02_Infrastructure/factor_db/factor_registry.json"
OUT=ROOT+"/stage_artifacts/pg2_defense_survey"

with open(REG,'r',encoding='utf-8') as f: reg=json.load(f)
cand=[]
with open(OUT+"/step1_defense_candidates.csv",encoding='utf-8-sig') as f:
    for r in csv.DictReader(f): cand.append(r)
cand_codes=[r['code'] for r in cand]
# benchmarks to always include (book-3)
BOOK3=['Q07_Earnings_Stability','M08_Residual_Mom','Q25_Ohlson_O']

# --- load benchmark monthly, build FORWARD bm indexed at signal-month ym ---
b=pq.read_table(BENCH).to_pandas()
b['ym']=pd.to_datetime(b['Date']).dt.strftime('%Y-%m')
b=b.dropna(subset=['BM_Ret'])
b['lr']=np.log1p(b['BM_Ret'].clip(lower=-0.99))
bm=b.groupby('ym')['lr'].sum().apply(np.expm1).rename('bm_ret').reset_index().sort_values('ym')
bm['bm_fwd']=bm['bm_ret'].shift(-1)   # month ym+1 return, indexed at ym  (parallel to fwd_ret_1m)
bm_fwd=bm.set_index('ym')['bm_fwd']

# --- load panel ---
allcols=['ym','Ticker','fwd_ret_1m']+[c for c in dict.fromkeys(cand_codes+BOOK3) if c in set(pq.ParquetFile(PANEL).schema_arrow.names)]
pf=pq.read_table(PANEL, columns=allcols).to_pandas()
factor_cols=[c for c in allcols if c not in ('ym','Ticker','fwd_ret_1m')]
print("panel loaded:", pf.shape, "| factors to measure:", len(factor_cols))

# attach bm_fwd
pf['bm_fwd']=pf['ym'].map(bm_fwd)
pf=pf.dropna(subset=['fwd_ret_1m','bm_fwd'])
months=sorted(pf['ym'].unique())
# regime split thresholds on bm_fwd (per-month scalar)
mbm=pf.groupby('ym')['bm_fwd'].first()
down_months=set(mbm[mbm<0].index)           # BM_fwd negative = down month
up_months=set(mbm[mbm>=0].index)
crisis_thr=mbm.quantile(1/3)                  # worst tercile
crisis_months=set(mbm[mbm<=crisis_thr].index)
recent36=set(months[-36:])
print(f"months {len(months)} | down {len(down_months)} up {len(up_months)} crisis {len(crisis_months)} | crisis_thr {crisis_thr:.4f}")

def orient(code, s):
    d=(reg.get(code,{}).get('direction') or 'higher_better')
    return s if d=='higher_better' else -s

rows=[]
grp=pf.groupby('ym')
# precompute per-month groups once
month_frames={ym:g for ym,g in grp}

for code in factor_cols:
    ic_by_m={}; longleg_ret={}; longleg_act={}
    for ym in months:
        g=month_frames[ym]
        sub=g[[code,'fwd_ret_1m','bm_fwd']].dropna(subset=[code,'fwd_ret_1m'])
        if len(sub)<20: continue
        fv=orient(code, sub[code].values)
        fr=sub['fwd_ret_1m'].values
        # spearman IC
        ic=spearmanr(fv, fr).correlation
        if ic==ic: ic_by_m[ym]=ic
        # top-quintile long-leg EW
        n=len(sub); k=max(1,int(round(n*0.2)))
        order=np.argsort(-fv)          # highest oriented factor first
        top_idx=order[:k]
        lr=np.mean(fr[top_idx])
        longleg_ret[ym]=lr
        longleg_act[ym]=lr - sub['bm_fwd'].iloc[0]
    if len(ic_by_m)<24:
        rows.append(dict(code=code, note='insufficient_months', n_months=len(ic_by_m)))
        continue
    icser=pd.Series(ic_by_m)
    lret=pd.Series(longleg_ret); lact=pd.Series(longleg_act)
    bmser=mbm.reindex(lret.index)
    # beta of long-leg raw return vs bm_fwd
    xy=pd.concat([lret.rename('y'), bmser.rename('x')],axis=1).dropna()
    beta=np.polyfit(xy['x'], xy['y'],1)[0] if len(xy)>10 else np.nan
    # down/up ic
    ic_down=icser[[m for m in icser.index if m in down_months]]
    ic_up  =icser[[m for m in icser.index if m in up_months]]
    ic_crisis=icser[[m for m in icser.index if m in crisis_months]]
    ic_recent=icser[[m for m in icser.index if m in recent36]]
    badnormal = (ic_down.mean()/ic_up.mean()) if (ic_up.mean() not in (0,np.nan) and abs(ic_up.mean())>1e-6) else np.nan
    # down-month long active
    act_down=lact[[m for m in lact.index if m in down_months]]
    act_all=lact
    icir = icser.mean()/icser.std() if icser.std()>0 else np.nan
    harvey_t = icser.mean()/icser.std()*np.sqrt(len(icser)) if icser.std()>0 else np.nan
    rows.append(dict(
        code=code,
        name=reg.get(code,{}).get('name'),
        category=(reg.get(code,{}).get('category') or ''),
        direction=reg.get(code,{}).get('direction'),
        n_months=len(icser),
        ic_mean=round(icser.mean(),4),
        icir=round(icir,3) if icir==icir else None,
        harvey_t=round(harvey_t,2) if harvey_t==harvey_t else None,
        beta_bm=round(beta,3) if beta==beta else None,
        down_active_mean=round(act_down.mean(),4) if len(act_down) else None,
        active_all_mean=round(act_all.mean(),4),
        ic_down=round(ic_down.mean(),4) if len(ic_down) else None,
        ic_up=round(ic_up.mean(),4) if len(ic_up) else None,
        badnormal_ic=round(badnormal,3) if badnormal==badnormal else None,
        crisis_ic=round(ic_crisis.mean(),4) if len(ic_crisis) else None,
        recent36_ic=round(ic_recent.mean(),4) if len(ic_recent) else None,
    ))

df=pd.DataFrame(rows)
# merge defclass
cmap={r['code']:r for r in cand}
df['defclass']=df['code'].map(lambda c: cmap.get(c,{}).get('defclass'))
df.loc[df['code'].isin(BOOK3),'defclass']=df.loc[df['code'].isin(BOOK3),'defclass'].fillna('BENCHMARK_book3')
df['is_book3']=df['code'].isin(BOOK3)

# --- true-defensive verdict ---
# defensive if: beta_bm < 0.95  AND  down_active_mean > 0  AND badnormal_ic > 1.0 (IC stronger in down)
def verdict(r):
    if pd.isna(r.get('beta_bm')): return 'INSUFFICIENT'
    b=r['beta_bm']; da=r.get('down_active_mean'); bn=r.get('badnormal_ic'); ci=r.get('crisis_ic')
    score=0
    if b is not None and b<0.95: score+=1
    if da is not None and da>0: score+=1
    if bn is not None and bn>1.0: score+=1
    if ci is not None and ci>0: score+=1
    if score>=3: return 'TRUE_DEFENSE'
    if score==2: return 'PARTIAL'
    return 'LABEL_ONLY'
df['verdict']=df.apply(verdict,axis=1)

df=df.sort_values(['defclass','code'])
df.to_csv(OUT+"/step2_characterization.csv", index=False, encoding='utf-8-sig')
print("\nsaved:", OUT+"/step2_characterization.csv", "| rows:", len(df))
print("\nverdict counts:")
print(df['verdict'].value_counts().to_string())
print("\nBOOK-3 benchmark:")
print(df[df['is_book3']][['code','beta_bm','down_active_mean','badnormal_ic','crisis_ic','recent36_ic','ic_mean','harvey_t','verdict']].to_string(index=False))
