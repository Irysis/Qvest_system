"""table_signature.py — 재무 병합 표 · 분기 표의 항목별 서명(행 수 · 값 합 · Factor_Date 합) (2026-11-10 총부채 수리)

쓰임: 세션이 대조한 후보의 서명을 남기고(--write), 체인이 교체된 정본의 서명과 맞춘다(--check). 큰 후보 파일을 들고 다니지 않는다.
  python table_signature.py --write <merged.parquet> <xlsx.parquet> <out.json>
  python table_signature.py --check <merged.parquet> <xlsx.parquet> <sig.json>     # 종료 0 = 같음 · 1 = 다름
"""
import json
import sys

import pyarrow.parquet as pq


def sig(path):
    d = pq.read_table(path, columns=["Item", "Value", "Factor_Date"]).to_pandas()
    d["fd"] = d["Factor_Date"].astype("datetime64[s]").astype("int64")
    g = d.groupby("Item").agg(n=("Value", "size"), s=("Value", "sum"), f=("fd", "sum"))
    return {"rows": int(len(d)), "items": {k: [int(r.n), float(r.s), int(r.f)] for k, r in g.iterrows()}}


def same(a, b):
    if a["rows"] != b["rows"] or set(a["items"]) != set(b["items"]):
        return False
    for k, (n, s, f) in a["items"].items():
        n2, s2, f2 = b["items"][k]
        if n != n2 or f != f2 or abs(s - s2) > 1e-9 * max(1.0, abs(s2)):
            return False
    return True


if __name__ == "__main__":
    mode, merged, xlsx, js = sys.argv[1:5]
    cur = {"merged": sig(merged), "xlsx": sig(xlsx)}
    if mode == "--write":
        json.dump(cur, open(js, "w", encoding="utf-8"), ensure_ascii=False)
        print(f"[signature] 저장 {js} · 병합 {cur['merged']['rows']:,}행 · 분기 {cur['xlsx']['rows']:,}행")
        sys.exit(0)
    ref = json.load(open(js, encoding="utf-8"))
    ok = {k: same(cur[k], ref[k]) for k in ("merged", "xlsx")}
    print(f"[signature] 병합 {cur['merged']['rows']:,} vs {ref['merged']['rows']:,} 같음={ok['merged']} · "
          f"분기 {cur['xlsx']['rows']:,} vs {ref['xlsx']['rows']:,} 같음={ok['xlsx']}")
    sys.exit(0 if all(ok.values()) else 1)
