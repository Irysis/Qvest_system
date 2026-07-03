# STEP 5 — consolidated ranking + meta
import pandas as pd, json, os
OUT="C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_defense_survey"
s1=pd.read_csv(OUT+"/step1_defense_candidates.csv")
s2b=pd.read_csv(OUT+"/step2b_relative_ranked.csv")
s3=pd.read_csv(OUT+"/step3_ranking_orthogonality.csv")
cs=pd.read_csv(OUT+"/step4_canonical_port_t.csv")

# merge master survey table
m=s2b.merge(s1[['code','definition','reason','macro_defensive','crisis_positive']], on='code', how='left')
# def_score from step3 logic recomputed on full set
def z(s): s=pd.to_numeric(s,errors='coerce'); return (s-s.mean())/s.std()
m['def_score_level']=(z(-m['beta_all'])+z(m['crisis_ic'])+z(m['excess_down_active'])+0.5*z(m['recent36_ic'])).round(3)
m=m.sort_values('def_score_level',ascending=False).reset_index(drop=True)
m['rank']=range(1,len(m)+1)
# attach canonical port_t where available
csmap=cs.set_index('code')[['port_t','net_ir','net_sr','turnover_annual']].to_dict('index')
for k in ['port_t','net_ir','net_sr','turnover_annual']:
    m[k]=m['code'].map(lambda c: csmap.get(c,{}).get(k))
m['recent_alive']=(m['recent36_ic']>0.02)
keepcols=['rank','code','name','category','defclass','direction','beta_all','beta_asym','ic_mean',
          'crisis_ic','down_active','excess_down_active','recent36_ic','recent_alive','def_score_level',
          'verdict2','port_t','net_ir','net_sr','turnover_annual','definition']
m[keepcols].to_csv(OUT+"/defense_survey_master.csv", index=False, encoding='utf-8-sig')

meta=dict(
  task="PG2 defensive factor DB full survey",
  date="2026-07-03",
  universe="STR_1715 tracked panel (KOSPI200 U KOSDAQ150 proxy), 256 months 2005-01..2026-04",
  data_sources=dict(
    panel=".cache/discovery/explore_panel.parquet (330 factors, pre-C13 Z_Score, ym x Ticker x fwd_ret_1m)",
    benchmark=".cache/benchmark.parquet (corrected IKS200 KOSPI200, daily BM_Ret)",
    registry="02_Infrastructure/factor_db/factor_registry.json (373 factors)"),
  method=dict(
    classification="registry category/economic_family/macro_sensitivity/regime_profile + 6 defensive buckets (family D / quality-safety / low-beta-lowvol / distress / downside-tail / conservatism-accrual)",
    diagnostics="monthly cross-sectional Spearman IC (oriented by registry direction) + top-quintile EW long-leg beta/down-active vs FORWARD BM (aligned at signal month ym; no realized_ym offset bug)",
    confound_correction="raw beta<1 & down_active>0 near-universal in KR long-only (universe baseline beta 0.735) -> used beta_asymmetry, excess_down_active vs EW-universe, crisis_ic, level-beta",
    canonical="canonical_screen_bt (contract build_benchmark_compare, NW lag-3 PORT_t, 15bps, top25 EW) on top defense candidates + book-3"),
  counts=dict(
    total_registry=373,
    defense_candidates=int(len(s1)),
    measured=int(len(s2b)),
    recent_alive_gt002=int((s2b['recent36_ic']>0.02).sum()),
    decayed_recent_lt0=int((s2b['recent36_ic']<0).sum())),
  key_findings=[
    "KR structural: NO long-only defense factor has negative beta_asymmetry — all long-legs carry HIGHER beta in down months than up months (EW baseline +0.541). Classic 'de-risks in crash' pattern is absent in long-only KR.",
    "Low-beta/low-vol/downside D-family dominates raw defensiveness: beta_all 0.39-0.52, crisis_ic 0.11-0.16, FAR exceeding Q07 (beta 0.63, crisis_ic 0.076). D20_EW_Beta_126, D11_FP_Beta, RE07_Crisis_Beta, D15/D19 top.",
    "BUT canonical PORT_t is NEGATIVE for all pure-defense factors: D20 -1.26, D11 -1.32, D45 -1.42, D50 -0.74, Q07 -0.77. Their defensiveness does NOT translate to realized net long-only alpha (mean_active_net negative). Consistent with '16/16 standalone FAIL = PORT_t problem not IC'.",
    "Book-3 canonical PORT_t: Q07 -0.77 (defense engine but standalone alpha negative), Q25 +0.11 (flat), M08 +1.58 (best standalone but not defensive by crisis_ic). None reach PORT_t 2.95 graduation.",
    "Top defense candidates correlate 0.85-0.90 with Q07 active-return — same defensive dimension, NOT orthogonal. Adding them = redundant with existing Q07 sleeve.",
    "Recent survival: 53/166 defense candidates alive (recent36_ic>0.02); low-vol/downside D-family survives 2017+ cohort decay best (D56/D41/D51/D50/D53/D42/D45/D40)."],
  verdict="No DB defense factor beats the book-3 as a standalone capital-grade defensive. The pure-defense (low-beta) family is stronger on defensive DIAGNOSTICS (beta/crisis-IC) than Q07 but WEAKER on realized net PORT_t (all negative) and highly correlated (0.85+) with Q07. Defense improvement is NOT available via factor swap/add at standalone level — consistent with 06-30 'defense reweight settled'. Any use = overlay/DPL-feature (screen-tier), not book graduation.",
  caveats=[
    "IC/crisis_ic are diagnostics; PORT_t (canonical, NW lag-3) is authoritative for realized alpha.",
    "canonical PORT_t on 5 candidates only (top pure-defense + book3); IC-ranked others not PORT_t-tested but share the same negative-standalone structure.",
    "Panel universe = STR_1715 tracked names (defensive/quality-tilted), so absolute beta<1 is a universe artifact — corrected via relative measures.",
    "Debt/leverage factors (Q15/Q16) show positive recent36_ic but negative ic_mean = recent sign-reversal, fragile not robust defense.",
    "This is a diagnostic SURVEY — no graduation declared."])
json.dump(meta, open(OUT+"/defense_survey_meta.json",'w',encoding='utf-8'), ensure_ascii=False, indent=2)
print("saved defense_survey_master.csv + defense_survey_meta.json")
print("\nTOP 15 master:")
print(m[['rank','code','name','defclass','beta_all','crisis_ic','recent36_ic','recent_alive','port_t','verdict2']].head(15).to_string(index=False))
