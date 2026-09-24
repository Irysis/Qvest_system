# read-only: find catalog modules (and ledger base engines) that load the WHOLE factor DB (dynamic consumption path)
import json, re, os, collections
ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = os.path.dirname(os.path.abspath(__file__))
SD = os.path.join(ROOT, "04_Research", "strategies")
cat = json.load(open(os.path.join(ROOT, "06_Registry", "module_catalog.json"), encoding="utf-8"))["modules"]

CALL = re.compile(r"(load_month_factors|load_daily_factors|compute_rolling_ic_all|open_dataset\([^)]*factor_db|read_parquet\([^)]*(factor_db|fdb_daily))\s*\(?([^\n]*)")
FILTER = re.compile(r"Factor_Name\s*(%in%|==)|factor_names\s*=|factors\s*=\s*c\(|\bfactors\s*=\s*[A-Za-z_.]+")
SKIPD = {"cache", "_work", "__pycache__", "output", "outputs"}

def scan_dir(p):
    calls = []
    for dp, dn, fn in os.walk(p):
        dn[:] = [d for d in dn if d not in SKIPD]
        for f in fn:
            if not f.endswith((".R", ".r", ".py")):
                continue
            fp = os.path.join(dp, f)
            try:
                if os.path.getsize(fp) > 3_000_000:
                    continue
                txt = open(fp, encoding="utf-8", errors="replace").read()
            except Exception:
                continue
            for i, line in enumerate(txt.splitlines()):
                s = line.strip()
                if s.startswith("#"):
                    continue
                m = CALL.search(line)
                if m:
                    named = bool(re.search(r"factor_names\s*=|factors\s*=", line))
                    calls.append(dict(file=os.path.relpath(fp, p).replace("\\", "/"), line=i + 1, named=named,
                                      src=s[:160], file_has_name_filter=bool(FILTER.search(txt))))
    return calls

rows = []
for sid, m in cat.items():
    p = os.path.join(SD, sid)
    if not os.path.isdir(p):
        rows.append(dict(sid=sid, grade=m.get("grade"), essence=m.get("essence_grade"), fr=m.get("fr_eligible"), dir=False, calls=[]))
        continue
    rows.append(dict(sid=sid, grade=m.get("grade"), essence=m.get("essence_grade"), fr=m.get("fr_eligible"), dir=True,
                     origin=m.get("origin_mode"), calls=scan_dir(p)))
json.dump(rows, open(os.path.join(OUT, "zoo_rows.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)

c = collections.Counter()
for r in rows:
    unnamed = [x for x in r["calls"] if not x["named"]]
    key = ("nodir" if not r["dir"] else ("no_fdb_call" if not r["calls"] else ("all_named" if not unnamed else "has_unnamed")))
    c[(key, str(r["grade"]), str(r["essence"]), str(r["fr"]))] += 1
for k in sorted(c):
    print(k, c[k])
print("--- unnamed-call modules with grade/essence in {A,B} ---")
for r in rows:
    unnamed = [x for x in r["calls"] if not x["named"]]
    if unnamed and (str(r["grade"]) in ("A", "B") or str(r["essence"]) in ("A", "B")):
        print(r["sid"], r["grade"], r["essence"], r["fr"], r.get("origin"), [(x["file"], x["line"], x["file_has_name_filter"], x["src"][:90]) for x in unnamed][:3])
