# Aggregate lo_screen/*.json into a results table + candidate selection (long-only only)
import json, glob, os
D = "G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/lo_screen"
rows = []
for f in sorted(glob.glob(os.path.join(D, "*.json"))):
    if os.path.basename(f).startswith("_"):
        continue
    try:
        d = json.load(open(f, encoding="utf-8"))
    except Exception as e:
        print("ERR", f, e); continue
    a = d.get("long_only_top25", {})
    v = d.get("verdict", {})
    c = d.get("multi_axis_corr", {})
    rows.append(dict(
        factor=d.get("factor", "?"),
        grade=a.get("essence", {}).get("grade"),
        sharpe=a.get("sharpe"), cagr=a.get("cagr_pct"), mdd=a.get("mdd_pct"),
        calmar=a.get("calmar"), net_ir=a.get("net_ir"), port_t=a.get("portfolio_alpha_t_nw_lag3"),
        oos_ret=a.get("oos_retention"), sr_is=a.get("active_sr_is"), sr_oos=a.get("active_sr_oos"),
        c4_t=a.get("carhart4_alpha_t"),
        corr_val=c.get("vs_value_bm_lo"), corr_1715=c.get("vs_STR_1715"), max_corr=c.get("max_abs_corr"),
        oos_robust=v.get("oos_robust_orthogonal_candidate"), defense=v.get("defense_candidate"),
        verdict=v.get("interpretation", "")[:40],
    ))

def fmt(x, n=2):
    return f"{x:.{n}f}" if isinstance(x, (int, float)) else str(x)

hdr = f"{'factor':30s} {'grd':3s} {'SR':>6s} {'CAGR%':>6s} {'MDD%':>6s} {'Calmar':>6s} {'netIR':>6s} {'PORTt':>6s} {'OOSret':>7s} {'srIS':>6s} {'srOOS':>6s} {'C4t':>6s} {'cVAL':>6s} {'c1715':>6s} {'ROBUST':>6s} {'DEF':>4s}"
print(hdr); print("-"*len(hdr))
# sort: oos_robust first, then defense, then by sharpe
rows.sort(key=lambda r: (not bool(r["oos_robust"]), not bool(r["defense"]), -(r["sharpe"] or -9)))
for r in rows:
    print(f"{r['factor']:30s} {str(r['grade']):3s} {fmt(r['sharpe']):>6s} {fmt(r['cagr'],1):>6s} {fmt(r['mdd'],1):>6s} {fmt(r['calmar']):>6s} {fmt(r['net_ir']):>6s} {fmt(r['port_t']):>6s} {fmt(r['oos_ret']):>7s} {fmt(r['sr_is']):>6s} {fmt(r['sr_oos']):>6s} {fmt(r['c4_t']):>6s} {fmt(r['corr_val']):>6s} {fmt(r['corr_1715']):>6s} {('YES' if r['oos_robust'] else '-'):>6s} {('Y' if r['defense'] else '-'):>4s}")

print()
robust = [r["factor"] for r in rows if r["oos_robust"]]
defense = [r["factor"] for r in rows if r["defense"] and not r["oos_robust"]]
print(f"TOTAL completed: {len(rows)}")
print(f"★ OOS robust orthogonal candidates (retention>=0.5 + IS/OOS active SR>0 + corr<0.3): {robust or 'NONE'}")
print(f"방어 candidates (MDD<30%, not robust): {defense or 'NONE'}")
