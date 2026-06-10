# _lo_aggregate.py — lo_screen/*.json을 명세 판정 기준으로 재집계 표 출력.
#  판정(작업 명세): OOS robust 직교 후보 = OOS retention>=0.5 AND |Carhart4 t|>=1.96.
#                   방어 기여 후보 = MDD<30%.
import json, glob, os
LODIR = r'G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/lo_screen'
rows = []
for p in sorted(glob.glob(os.path.join(LODIR, '*.json'))):
    b = os.path.basename(p)
    if b.startswith('_'):  # _batch*.json 등 제외
        continue
    try:
        j = json.load(open(p, encoding='utf-8'))
    except Exception as e:
        print(f'[parse-fail] {b}: {e}'); continue
    lo = j.get('long_only_top25', {})
    mac = j.get('multi_axis_corr', {})
    fac = j.get('factor', b.replace('.json',''))
    oos = lo.get('oos_retention')
    c4t = lo.get('carhart4_alpha_t')
    mdd = lo.get('mdd_pct')
    sr  = lo.get('sharpe')
    sr_is  = lo.get('active_sr_is'); sr_oos = lo.get('active_sr_oos')
    grade = (lo.get('essence') or {}).get('grade')
    # 명세 판정: OOS retention>=0.5(IS/OOS 양수 가드 포함) AND |C4 t|>=1.96
    ax_oos = (oos is not None and oos >= 0.5 and sr_is is not None and sr_is > 0 and sr_oos is not None and sr_oos > 0)
    ax_c4  = (c4t is not None and abs(c4t) >= 1.96)
    ax_mdd = (mdd is not None and mdd < 30.0)
    oos_robust = ax_oos and ax_c4
    rows.append(dict(factor=fac, sr=sr, mdd=mdd, oos=oos, sr_is=sr_is, sr_oos=sr_oos,
                     c4t=c4t, grade=grade, corr=mac.get('max_abs_corr'),
                     oos_robust=oos_robust, defense=ax_mdd))

def f(v, d=3):
    return f'{v:.{d}f}' if isinstance(v,(int,float)) else str(v)

print(f'{"factor":32s} {"SR":>7s} {"MDD%":>7s} {"OOSret":>7s} {"C4_t":>7s} {"corr":>6s} {"Gr":>3s}  flags')
print('-'*92)
for r in sorted(rows, key=lambda x:(-(x["oos_robust"]), -(x["defense"]), x["factor"])):
    flags = []
    if r['oos_robust']: flags.append('OOS_ROBUST_ORTHO')
    if r['defense']:    flags.append('DEFENSE')
    if not flags:       flags.append('reject')
    print(f'{r["factor"]:32s} {f(r["sr"]):>7s} {f(r["mdd"],1):>7s} {f(r["oos"]):>7s} {f(r["c4t"],2):>7s} {f(r["corr"],2):>6s} {str(r["grade"]):>3s}  {", ".join(flags)}')
print('-'*92)
print(f'total={len(rows)} | OOS_robust_ortho={sum(r["oos_robust"] for r in rows)} | defense={sum(r["defense"] for r in rows)}')
