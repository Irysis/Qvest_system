# STEP 1 — DB 방어형 팩터 전수 식별 (registry parse + defensive classification)
import json, re, csv, os
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
REG=ROOT+"/02_Infrastructure/factor_db/factor_registry.json"
OUT=ROOT+"/stage_artifacts/pg2_defense_survey"

with open(REG,'r',encoding='utf-8') as f:
    reg=json.load(f)

# --- defensive classification rules ---
# returns (is_defense, defclass, reason) ; defclass in the 6 buckets
DISTRESS_KW = ['altman','ohlson','bankrupt','failure','distress','z-score','zscore','o-score']
LOWVOL_KW   = ['beta','idiovol','volatility','realvol','vol','idio','ewma_vol','vol_of_vol','garmanklass','parkinson','yangzhang','rogerssatchell','range_vol']
DOWNSIDE_KW = ['downside','tail','left_tail','var','cvar','drawdown','ulcer','semi','sortino','minret','coskew','cokurt','ncskew','duvol','maxret','max_return','skew','kurt','neg_ret']
CONSERV_KW  = ['accrual','asset_growth','net_equity_issuance','equity_issuance','investment','conservat','capex','noa','discretionary']
SAFETY_QUAL_KW = ['earnings_stability','earnings stability','persistence','current_ratio','quick','debt','leverage','interest_coverage','coverage_ratio','cash_to','cash ratio','cashratio','solvency','liquidity ratio','working_capital','workingcapital','sustainable','margin','gross_margin','net_margin','cash_conversion']

def classify(code, e):
    cat = (e.get('category') or '').lower()
    labels = e.get('labels') or {}
    fam = (labels.get('economic_family') or '').lower()
    macro = (labels.get('macro_sensitivity') or '').lower()
    name = (e.get('name') or '').lower()
    defin = (e.get('definition') or '').lower()
    txt = name + ' ' + defin + ' ' + code.lower()
    rp = labels.get('regime_profile') or {}
    crisis = (rp.get('crisis') or '').lower()

    reasons=[]
    dclass=None

    # rule 1: family D (defense) or category defense
    fam_defense = (fam=='defense' or cat=='defense' or code.startswith('D'))
    # rule 4: distress
    if any(k in txt for k in DISTRESS_KW):
        dclass='4_distress'; reasons.append('distress/bankruptcy model')
    # rule 3: low-beta/low-vol/IVOL
    elif (fam_defense and any(k in txt for k in LOWVOL_KW)) or (code.startswith('D') and 'beta' in txt) or ('idiovol' in txt) or (code.startswith('D') and 'vol' in txt):
        dclass='3_lowbeta_lowvol'; reasons.append('low-beta/low-vol')
    # rule 5: downside/tail
    elif any(k in txt for k in DOWNSIDE_KW):
        dclass='5_downside_tail'; reasons.append('downside/tail risk')
    # rule 6: conservatism / accrual quality
    elif any(k in txt for k in CONSERV_KW):
        dclass='6_conservatism_accrual'; reasons.append('conservatism/accrual quality')
    # rule 2: quality/safety
    elif (fam in ('quality',) or cat=='quality') and any(k in txt for k in SAFETY_QUAL_KW):
        dclass='2_quality_safety'; reasons.append('quality safety (stability/solvency)')
    # rule 1 fallback: family D generic
    elif fam_defense:
        dclass='1_family_D'; reasons.append('family=defense')

    # extra: macro_sensitivity=defensive OR crisis=positive strongly implies defensive tilt
    macro_def = (macro=='defensive')
    crisis_pos = (crisis=='positive')

    if dclass is None:
        # catch macro-defensive-labeled but not keyword-matched (e.g. some R/RE)
        if macro_def or (crisis_pos and (code.startswith('R') or code.startswith('RE') or fam in ('risk',))):
            dclass='1_family_D'; reasons.append('macro_sensitivity=defensive / crisis-positive risk factor')

    is_def = dclass is not None
    return is_def, dclass, macro_def, crisis_pos, cat, fam, e.get('direction'), '; '.join(reasons)

rows=[]
fam_counts={}
for code,e in reg.items():
    if not isinstance(e,dict): continue
    is_def, dclass, macro_def, crisis_pos, cat, fam, direction, reason = classify(code,e)
    if is_def:
        rows.append(dict(code=code, name=e.get('name'), category=cat,
                         economic_family=fam, defclass=dclass, direction=direction,
                         macro_defensive=macro_def, crisis_positive=crisis_pos,
                         definition=(e.get('definition') or '')[:160], reason=reason))
        fam_counts[dclass]=fam_counts.get(dclass,0)+1

rows.sort(key=lambda r:(r['defclass'], r['code']))

os.makedirs(OUT,exist_ok=True)
with open(OUT+"/step1_defense_candidates.csv",'w',newline='',encoding='utf-8-sig') as f:
    w=csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    for r in rows: w.writerow(r)

print("TOTAL factors in registry:", len(reg))
print("DEFENSE candidates identified:", len(rows))
print("\nby defclass:")
for k in sorted(fam_counts): print(f"  {k}: {fam_counts[k]}")
# family prefix distribution
pref={}
for r in rows:
    p=re.match(r'^[A-Z]+',r['code']).group(0)
    pref[p]=pref.get(p,0)+1
print("\nby code-prefix family:")
for k in sorted(pref): print(f"  {k}: {pref[k]}")
# how many book 3 present
for c in ['Q07_Earnings_Stability','M08_Residual_Mom','Q25_Ohlson_O']:
    hit=[r for r in rows if r['code']==c]
    print(f"book-3 {c}: {'CLASSIFIED DEFENSE' if hit else 'NOT classified defense'}")
print("saved:", OUT+"/step1_defense_candidates.csv")
