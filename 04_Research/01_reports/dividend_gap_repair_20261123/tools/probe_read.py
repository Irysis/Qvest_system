# probe_read.py — rebuild_factor_subset.R --dry-run 기록(jsonl)을 팩터별로 풀어 '실제로 달라진 팩터'를 낸다.
#   달라짐 = 새 산출이 있는 팩터(n_new > 0)에서 값 바뀜(양쪽 유한 − 그대로) · 새로 생김 · 사라짐 중 하나라도 0 이 아님.
#   '그대로'와 '부호 반전/역수'는 값이 ±1 · 0 근처면 겹쳐 세어지므로 바뀜 = 양쪽 유한 − 그대로 로 다시 센다.
import json, sys
from collections import defaultdict
path = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else None
aff = defaultdict(dict); notbuilt = defaultdict(int); months = []
for line in open(path, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    r = json.loads(line)
    if "per_factor" not in r:
        print("  %s 기록(대조 없음): %s" % (r.get("ym"), r.get("note"))); continue
    months.append(r["ym"])
    for f, c in r["per_factor"].items():
        if c["n_new"] == 0:
            if c["n_old"] > 0:
                notbuilt[f] += 1
            continue
        both = c["n_old"] - c["only_old"]            # 옛 값이 있고 새 값도 유한
        chg = both - c["same"]
        if chg or c["only_new"] or c["only_old"]:
            aff[f][r["ym"]] = {"changed": chg, "only_new": c["only_new"], "only_old": c["only_old"], "n_old": c["n_old"], "n_new": c["n_new"]}
print("달:", ",".join(months))
print("네 모듈이 만들지 않는 대상(옛 값만 있음):", len(notbuilt), sorted(notbuilt)[:40])
print("달라진 팩터:", len(aff))
for f in sorted(aff):
    print("  %-30s %s" % (f, " | ".join("%s 바뀜 %d · 생김 %d · 사라짐 %d (옛 %d → 새 %d)" % (ym, v["changed"], v["only_new"], v["only_old"], v["n_old"], v["n_new"]) for ym, v in sorted(aff[f].items()))))
if out:
    json.dump({"months": months, "affected": aff, "not_built": sorted(notbuilt)}, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
