# read-only: catalog module provenance scan (meta + bt_result dir json/R + manifest + replication spec + engine)
import json, re, os, collections
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(OUT, "scan_ledger.py"), encoding="utf-8").read().split("rows = []")[0])
cat = json.load(open(os.path.join(ROOT, "06_Registry", "module_catalog.json"), encoding="utf-8"))["modules"]

def J(p):
    return p if re.match(r"^[A-Za-z]:/", p.replace("\\", "/")) else os.path.join(ROOT, p)

def dir_files(d):
    out = []
    if not os.path.isdir(d):
        return out
    for f in os.listdir(d):
        fp = os.path.join(d, f)
        if os.path.isfile(fp) and f.endswith((".json", ".R", ".py", ".txt")) and os.path.getsize(fp) < 5_000_000:
            out.append(fp)
        elif f in ("01_strategy_spec.csv", "00_manifest.csv"):
            out.append(fp)
    return out

rows = []
for sid, m in cat.items():
    srcs = []
    txt = json.dumps(m, ensure_ascii=False)
    h = {g: set(v) for g, v in hits(txt).items()}
    dirs = set()
    if m.get("bt_result_path"):
        dirs.add(os.path.dirname(J(m["bt_result_path"])))
    ad = (m.get("meta") or {}).get("artifacts_dir")
    if ad:
        dirs.add(J(ad))
    mp = (m.get("meta") or {}).get("strategy_manifest_path")
    files = []
    for d in dirs:
        files += dir_files(d)
    if mp:
        files.append(J(mp))
    engine_paths = set()
    for fp in files:
        t = read_text(fp)
        for g, v in hits(t).items():
            h.setdefault(g, set()).update(v)
        # follow engine / spec paths mentioned in spec files
        for mm in re.findall(r"(?:04_Research/strategies/[^\"'\s,]+?\.R|\.cache/rf_parallel/spec_[^\"'\s,]+?\.json)", t):
            engine_paths.add(mm)
    for ep in engine_paths:
        t = read_text(J(ep)) if not ep.startswith(".cache") else read_text(os.path.join(ROOT, ep))
        for g, v in hits(t).items():
            h.setdefault(g, set()).update(v)
    rows.append(dict(sid=sid, grade=m.get("grade"), essence=m.get("essence_grade"), fr=m.get("fr_eligible"),
                     contract_pass=(m.get("contract") or {}).get("contract_pass"),
                     admission=(m.get("meta") or {}).get("admission_route"), origin=m.get("origin_mode"),
                     n_files=len(files), n_eng=len(engine_paths), hits={g: sorted(v) for g, v in h.items()}))
json.dump(rows, open(os.path.join(OUT, "module_rows.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print("modules", len(rows), "with files", sum(1 for r in rows if r["n_files"]), "with engine refs", sum(1 for r in rows if r["n_eng"]))
c = collections.Counter()
for r in rows:
    for g in r["hits"]:
        c[(g, str(r["grade"]), str(r["essence"]), str(r["fr"]))] += 1
for k in sorted(c):
    print(k, c[k])
print("--- hit modules ---")
for r in rows:
    if r["hits"]:
        print(r["sid"], r["grade"], r["essence"], r["fr"], r["admission"], r["origin"], r["hits"])
