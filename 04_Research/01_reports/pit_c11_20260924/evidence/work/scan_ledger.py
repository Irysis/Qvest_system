# read-only scan: ledger attempts x overseas-dependent factor tokens
import json, re, os, collections, sys
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = os.path.dirname(os.path.abspath(__file__))

GROUPS = {
    "G1_D32_VIX_samedate": [r"D32_Beta_VIX", r"\bD32\b"],
    "G2_RE10_11_13_14": [r"RE10_VIX_Pctile", r"RE11_VIX_Change_EWMA", r"RE13_Credit_Spread_Pctile", r"RE14_Inflation_YoY"],
    "G3_MA_RE12_RE16": [r"MA0[1-57]_[A-Za-z_]+", r"RE12_VIX_Regime_3State", r"RE16_Canary_Signal"],
    "G4_regime_v2_fdb": [r"RE_MRS", r"RE_exposure", r"RE_VIX_z", r"RE_HY_z", r"RE_TS_z"],
    "G4b_RE04_05": [r"RE04_HighVol_Beta", r"RE05_LowVol_Beta"],
    "G5_rawfile": [r"macro_fred", r"fred_macro", r"regime_daily_v2", r"unified_regime_signal", r"macro_regime",
                   r"regime_jump_daily", r"ae_regime_signal", r"VIXCLS", r"regime_forecast_series", r"msm_daily"],
}
RX = {g: re.compile("|".join(p)) for g, p in GROUPS.items()}

_cache = {}
def read_text(p):
    if not p or not isinstance(p, str):
        return ""
    p = p.replace("\\", "/")
    if not os.path.isabs(p) and not re.match(r"^[A-Za-z]:/", p):
        p = os.path.join(ROOT, p)
    if p in _cache:
        return _cache[p]
    t = ""
    try:
        if os.path.isfile(p) and os.path.getsize(p) < 20_000_000:
            with open(p, encoding="utf-8", errors="replace") as f:
                t = f.read()
    except Exception:
        t = ""
    _cache[p] = t
    return t

def hits(text):
    out = {}
    for g, rx in RX.items():
        m = sorted(set(rx.findall(text)))
        if m:
            out[g] = m
    return out

def grade_of(a):
    g = a.get("grade")
    if g is None:
        return "None"
    g = str(g)
    return g if g in ("A", "B", "C", "F") else "NA"

rows = []
for layer, fn in (("L1", "reinforce_ledger_l1.json"), ("L2", "reinforce_ledger_l2.json")):
    d = json.load(open(os.path.join(ROOT, "06_Registry", fn), encoding="utf-8"))
    for e in d["entries"]:
        eng_txt = read_text(e.get("engine_path"))
        eng_hits = hits(eng_txt)
        for a in e.get("attempts") or []:
            blob = json.dumps(a, ensure_ascii=False)
            ess = a.get("essence") if isinstance(a.get("essence"), dict) else {}
            spec_p = ess.get("spec")
            spec_txt = read_text(spec_p)
            h_att = hits(blob)
            h_spec = hits(spec_txt)
            # spec-declared factor ids (structured)
            spec_factors = []
            spec_overlay = None
            spec_sleeve = None
            spec_base_engine = None
            if spec_txt.strip().startswith("{"):
                try:
                    sj = json.loads(spec_txt)
                    for f in sj.get("factors") or []:
                        if isinstance(f, dict):
                            spec_factors.append(f"{f.get('kind')}:{f.get('id')}")
                    spec_overlay = json.dumps(sj.get("overlay"), ensure_ascii=False)
                    spec_sleeve = json.dumps(sj.get("defense_sleeve"), ensure_ascii=False)
                    bs = sj.get("base_signal") or {}
                    spec_base_engine = bs.get("path") if isinstance(bs, dict) else None
                except Exception:
                    pass
            base_eng_hits = hits(read_text(spec_base_engine)) if spec_base_engine else {}
            rows.append(dict(layer=layer, base_id=e.get("base_id"), base_grade=e.get("base_grade"),
                             entry_status=e.get("status"), measurement_axis=e.get("measurement_axis"),
                             n=a.get("n"), cell=a.get("cell_code"), grade=grade_of(a),
                             port_t=ess.get("port_t"), calmar=ess.get("calmar"),
                             spec=spec_p, spec_exists=bool(spec_txt), spec_factors=spec_factors,
                             overlay=spec_overlay, sleeve=spec_sleeve,
                             h_att=h_att, h_spec=h_spec, h_entry_engine=eng_hits, h_spec_base_engine=base_eng_hits,
                             idea=(a.get("idea") or "")[:300]))

json.dump(rows, open(os.path.join(OUT, "ledger_rows.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)

def any_hit(r, keys=("h_att", "h_spec")):
    s = set()
    for k in keys:
        s |= set(r[k].keys())
    return s

print("total attempts", len(rows), "spec_exists", sum(r["spec_exists"] for r in rows))
tab = collections.Counter()
for r in rows:
    gs = any_hit(r)
    for g in gs:
        tab[(g, r["layer"], r["grade"])] += 1
for k in sorted(tab):
    print(k, tab[k])
print("--- entry engine hits (by entry) ---")
seen = set()
for r in rows:
    if r["h_entry_engine"] and r["base_id"] not in seen:
        seen.add(r["base_id"]); print(r["layer"], r["base_id"], r["base_grade"], r["h_entry_engine"])
print("--- spec base engine hits ---")
seen = set()
for r in rows:
    if r["h_spec_base_engine"]:
        key = (r["base_id"])
        if key not in seen:
            seen.add(key); print(r["layer"], r["base_id"], r["h_spec_base_engine"])
