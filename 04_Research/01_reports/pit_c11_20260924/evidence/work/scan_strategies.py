# read-only: scan every 04_Research/strategies/<id>/ code+spec for overseas tokens; join with module_catalog
import json, re, os, collections
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(OUT, "scan_ledger.py"), encoding="utf-8").read().split("rows = []")[0])

EXT = (".R", ".r", ".py", ".json", ".sh")
SKIPD = {"cache", "_work", "__pycache__", "output", "outputs", "plots", "charts"}
SD = os.path.join(ROOT, "04_Research", "strategies")
res = {}
for sid in sorted(os.listdir(SD)):
    p = os.path.join(SD, sid)
    if not os.path.isdir(p):
        continue
    h = {}
    files_hit = collections.defaultdict(set)
    nfiles = 0
    for dp, dn, fn in os.walk(p):
        dn[:] = [d for d in dn if d not in SKIPD]
        for f in fn:
            if not f.endswith(EXT):
                continue
            fp = os.path.join(dp, f)
            try:
                if os.path.getsize(fp) > 3_000_000:
                    continue
            except OSError:
                continue
            nfiles += 1
            hh = hits(read_text(fp))
            for g, v in hh.items():
                h.setdefault(g, set()).update(v)
                files_hit[g].add(os.path.relpath(fp, p).replace("\\", "/"))
    res[sid] = dict(hits={g: sorted(v) for g, v in h.items()}, files={g: sorted(v)[:8] for g, v in files_hit.items()}, nfiles=nfiles)

cat = json.load(open(os.path.join(ROOT, "06_Registry", "module_catalog.json"), encoding="utf-8"))["modules"]
json.dump(res, open(os.path.join(OUT, "strategy_hits.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)

print("strategy dirs:", len(res), " with any hit:", sum(1 for v in res.values() if v["hits"]))
tab = collections.Counter()
for sid, v in res.items():
    if not v["hits"]:
        continue
    m = cat.get(sid)
    g = (m or {}).get("grade", "not_in_catalog")
    eg = (m or {}).get("essence_grade", "-")
    fre = (m or {}).get("fr_eligible", "-")
    for grp in v["hits"]:
        tab[(grp, g)] += 1
    print(sid, "| cat_grade", g, "| essence", eg, "| fr_eligible", fre, "|", v["hits"], "|", v["files"])
print("--- tally (group, catalog grade) ---")
for k in sorted(tab):
    print(k, tab[k])
