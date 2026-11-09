"""rebuild_compare.py — 팩터 DB 전체 재빌드 뒤 검사(SWITCH_RUNBOOK §6 '덮음 대조'): 옛 사본 대 새 월 파일.

사용: python -I rebuild_compare.py <old_dir> <new_dir> <out_json> [YYYYMM ...]
  달을 주지 않으면 두 폴더에 모두 있는 달 중 매년 6월 + 가장 최근 달.
대상 = factor_registry.json 의 data_source ∈ {fundamental, fundamental_xlsx}(재무 팩터).
달마다:
  - 재무 팩터 값 있는 칸 수(옛 · 새) · 팩터별로 새 < 옛 × 0.9 인 팩터(덮음 감소)
  - 굳은 팩터(값 있는 칸이 모두 같은 값) 목록(옛 · 새)
  - Q16_Debt_to_Assets 가 정확히 0 인 비율(값 있는 칸 중 · 옛 99.9% → 새 약 36% 가 2025-06 시범 실측)
읽기 전용 — 월 파일의 Ticker · Factor_Name · Raw_Value 세 열만 읽는다(빌드 산출물 검사 · 연구 소비 아님).
"""
import json
import os
import re
import sys

import pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", r"G:/OneDrive/Quant_Module_Moltbot")
REG = os.path.join(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json")
FUND_SRC = {"fundamental", "fundamental_xlsx"}
Q16 = "Q16_Debt_to_Assets"


def fund_factors():
    r = json.load(open(REG, encoding="utf-8"))
    f = r.get("factors", r)
    it = f.items() if isinstance(f, dict) else [(x.get("name"), x) for x in f]
    return sorted(n for n, x in it if isinstance(x, dict) and x.get("data_source") in FUND_SRC)


def months_in(d):
    return sorted(m.group(1) for m in (re.match(r"^factor_db_(\d{6})\.parquet$", x) for x in os.listdir(d)) if m)


def read_month(d, ym, facs):
    t = pq.read_table(os.path.join(d, f"factor_db_{ym}.parquet"), columns=["Ticker", "Factor_Name", "Raw_Value"],
                      filters=[("Factor_Name", "in", facs)])
    return t.to_pandas()


def summarise(df, facs):
    nn = df[df.Raw_Value.notna()]
    cnt = nn.groupby("Factor_Name").size().reindex(facs, fill_value=0)
    dead = sorted(f for f, g in nn.groupby("Factor_Name") if g.Raw_Value.nunique() <= 1)
    q = nn[nn.Factor_Name == Q16].Raw_Value
    q0 = float((q == 0).mean()) if len(q) else None
    return cnt, dead, q0, int(len(q))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    old_dir, new_dir, out = args[0], args[1], args[2]
    common = sorted(set(months_in(old_dir)) & set(months_in(new_dir)))
    months = args[3:] or sorted({m for m in common if m.endswith("06")} | {common[-1]})
    facs = fund_factors()
    rows = []
    for ym in months:
        co, do, qo, nqo = summarise(read_month(old_dir, ym, facs), facs)
        cn, dn, qn, nqn = summarise(read_month(new_dir, ym, facs), facs)
        drop = sorted(f for f in facs if co[f] > 0 and cn[f] < 0.9 * co[f])
        gain = sorted(f for f in facs if cn[f] > 1.1 * max(co[f], 1))
        rows.append({
            "ym": ym, "cells_old": int(co.sum()), "cells_new": int(cn.sum()),
            "n_factor_with_values_old": int((co > 0).sum()), "n_factor_with_values_new": int((cn > 0).sum()),
            "dead_old": do, "dead_new": dn, "dead_new_not_old": sorted(set(dn) - set(do)),
            "q16_zero_share_old": qo, "q16_zero_share_new": qn, "q16_n_old": nqo, "q16_n_new": nqn,
            "coverage_drop_factors": drop, "coverage_gain_factors": gain,
        })
        r = rows[-1]
        fmt = lambda v: "NA" if v is None else f"{v:.3f}"
        print(f"{ym} 칸 {r['cells_old']:>7,} → {r['cells_new']:>7,} · 팩터(값 있음) {r['n_factor_with_values_old']}→{r['n_factor_with_values_new']}"
              f" · 굳음 {len(do)}→{len(dn)} (새로 굳음 {len(r['dead_new_not_old'])}) · Q16=0 {fmt(qo)}→{fmt(qn)}"
              f" · 감소 {len(drop)} · 증가 {len(gain)}")
    res = {"schema": "fdb_rebuild_compare_v1", "old_dir": old_dir, "new_dir": new_dir,
           "fund_factors": len(facs), "months": rows}
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(res, fh, ensure_ascii=False, indent=1)
    print("JSON:", out)


if __name__ == "__main__":
    main()
