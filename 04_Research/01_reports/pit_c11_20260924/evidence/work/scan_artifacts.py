# read-only: scan every file/dir referenced by ledger attempts' artifacts + entry base_artifacts
import json, re, os, collections, glob
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(OUT, "scan_ledger.py"), encoding="utf-8").read().split("rows = []")[0])  # reuse GROUPS/RX/read_text/hits

EXT = (".json", ".R", ".r", ".py", ".txt", ".md", ".yaml", ".yml")
def norm(p):
    p = p.replace("\\", "/")
    if not re.match(r"^[A-Za-z]:/", p) and not p.startswith("/"):
        p = os.path.join(ROOT, p)
    return p

def collect_strings(o, acc):
    if isinstance(o, str):
        if ("/" in o or "\\" in o) and len(o) < 400:
            acc.append(o)
    elif isinstance(o, dict):
        for v in o.values():
            collect_strings(v, acc)
    elif isinstance(o, list):
        for v in o:
            collect_strings(v, acc)

_dir_cache = {}
def scan_path(p):
    p = norm(p)
    if p in _dir_cache:
        return _dir_cache[p]
    res = {}
    try:
        if os.path.isfile(p):
            if p.endswith(EXT) or p.endswith(".csv") and os.path.getsize(p) < 200_000:
                res = hits(read_text(p))
        elif os.path.isdir(p):
            files = []
            for dp, dn, fn in os.walk(p):
                # skip heavy caches
                dn[:] = [d for d in dn if d not in ("cache", "_work", "__pycache__")]
                for f in fn:
                    if f.endswith(EXT) or f in ("01_strategy_spec.csv", "00_manifest.csv"):
                        fp = os.path.join(dp, f)
                        if os.path.getsize(fp) < 5_000_000:
                            files.append(fp)
                if len(files) > 400:
                    break
            for fp in files[:400]:
                h = hits(read_text(fp))
                for g, v in h.items():
                    res.setdefault(g, set()).update(v)
            res = {g: sorted(v) for g, v in res.items()}
    except Exception as ex:
        res = {"_err": [str(ex)[:80]]}
    _dir_cache[p] = res
    return res

rows = json.load(open(os.path.join(OUT, "ledger_rows.json"), encoding="utf-8"))
ledgers = {}
for layer, fn in (("L1", "reinforce_ledger_l1.json"), ("L2", "reinforce_ledger_l2.json")):
    ledgers[layer] = json.load(open(os.path.join(ROOT, "06_Registry", fn), encoding="utf-8"))["entries"]

out = []
ent_hits = {}
for layer, E in ledgers.items():
    for e in E:
        acc = []
        collect_strings(e.get("base_artifacts"), acc)
        if e.get("engine_path"):
            acc.append(e["engine_path"])
        eh = {}
        for s in acc:
            for g, v in scan_path(s).items():
                eh.setdefault(g, set()).update(v)
        ent_hits[(layer, e.get("base_id"))] = {g: sorted(v) for g, v in eh.items()}
        for a in e.get("attempts") or []:
            acc = []
            collect_strings(a.get("artifacts"), acc)
            ah = {}
            for s in acc:
                for g, v in scan_path(s).items():
                    ah.setdefault(g, set()).update(v)
            if ah:
                out.append(dict(layer=layer, base_id=e.get("base_id"), n=a.get("n"), cell=a.get("cell_code"),
                                grade=str(a.get("grade"))[:3], hits={g: sorted(v) for g, v in ah.items()}, paths=acc[:6]))

json.dump(dict(attempt_hits=out, entry_hits={f"{k[0]}|{k[1]}": v for k, v in ent_hits.items()}),
          open(os.path.join(OUT, "artifact_hits.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print("attempts with artifact hits:", len(out))
c = collections.Counter()
for r in out:
    for g in r["hits"]:
        c[(g, r["layer"], r["grade"])] += 1
for k in sorted(c):
    print(k, c[k])
print("--- entries with base_artifacts/engine hits ---")
for k, v in ent_hits.items():
    if v:
        print(k, v)
