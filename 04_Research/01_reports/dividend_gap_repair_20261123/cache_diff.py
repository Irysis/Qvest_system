#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""cache_diff.py — 재무 캐시 두 판(옛 · 새)의 차이를 항목별로 센다. 읽기 전용.

왜: 재무 원천을 고친 뒤 캐시를 다시 만들면 '바뀐 것이 의도한 항목뿐인가'를 팩터 재계산 전에 확인해야 한다
    (2026-11-23 배당 여섯 분기 보충 · 판 표식 FUNDAMENTAL-DIV-GAP-SUPPLEMENT-20261123).
방법(두 단계 — 7천만 행 표 둘을 한꺼번에 메모리에 올리지 않는다):
  1) 지문: 표를 배치로 흘려 읽으며 항목마다 (행 수, 행 해시 합 4조각)을 쌓는다. 행 해시 = Item 을 뺀 모든 열.
     합은 순서와 무관하므로 두 판의 지문이 같으면 그 항목의 행 집합이 같다(64비트 해시 합).
  2) 정밀 대조: 지문이 다른 항목만 두 판에서 읽어 (Ticker, Period) 로 맞춘다 —
     새로 생김 · 사라짐 · 값 바뀜(허용 오차 1e-9 상대) · Factor_Date 바뀜 · 그 밖의 열 바뀜, 기간별 개수.
사용: python -X utf8 cache_diff.py OLD_DIR NEW_DIR OUT_JSON [--batch 2000000] [--chunk 10]
      OLD_DIR · NEW_DIR = fundamental_quarterly.parquet · fundamental_annual.parquet 가 든 폴더
종료: 0(차이 유무와 무관 — 판정은 호출자가 OUT_JSON 으로) · 1 오류
"""
import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq

TABLES = ("fundamental_quarterly", "fundamental_annual")
DICT_COLS = ["Ticker", "Period", "Item", "Kind"]
DATE_COLS = ("Period_Date", "Factor_Date")
TOL = 1e-9


def fingerprint(path, batch):
    """항목 → [행 수, 해시 합 4조각(16비트씩)] · 정수 정확(조각 합 < 2^53)."""
    pf = pq.ParquetFile(str(path), read_dictionary=DICT_COLS)
    acc = {}
    cols = None
    for rb in pf.iter_batches(batch_size=batch, use_threads=False):
        t = pa.Table.from_batches([rb])
        for c in DATE_COLS:
            t = t.set_column(t.schema.get_field_index(c), c, pc.cast(t[c], pa.int32()))
        df = t.to_pandas()
        item = df.pop("Item")
        if cols is None:
            cols = list(df.columns)
        h = pd.util.hash_pandas_object(df, index=False).to_numpy()
        codes = item.cat.codes.to_numpy()
        cats = [str(x) for x in item.cat.categories]
        k = len(cats)
        parts = [np.bincount(codes, minlength=k).astype(np.int64)]
        for i in range(4):
            w = ((h >> np.uint64(16 * i)) & np.uint64(0xFFFF)).astype(np.float64)
            parts.append(np.bincount(codes, weights=w, minlength=k).astype(np.int64))
        m = np.stack(parts, axis=1)
        for j, name in enumerate(cats):
            if m[j, 0] == 0:
                continue
            if name in acc:
                acc[name] += m[j]
            else:
                acc[name] = m[j].copy()
    return acc, cols, pf.metadata.num_rows


def load_items(path, items):
    t = pq.read_table(str(path), filters=[("Item", "in", list(items))], use_threads=False)
    df = t.to_pandas()
    for c in DATE_COLS:
        df[c] = pd.to_datetime(df[c])
    return df


def exact_diff(old_path, new_path, items):
    """items 의 정밀 대조 → 항목별 dict."""
    o = load_items(old_path, items)
    n = load_items(new_path, items)
    key = ["Item", "Ticker", "Period"]
    dup_o = int(o.duplicated(key).sum())
    dup_n = int(n.duplicated(key).sum())
    m = o.merge(n, on=key, how="outer", suffixes=("_o", "_n"), indicator=True)
    out = {}
    other = [c for c in o.columns if c not in key and c not in ("Value", "Factor_Date")]
    for it, g in m.groupby("Item", sort=True):
        both = g[g["_merge"] == "both"]
        on = g[g["_merge"] == "right_only"]
        oo = g[g["_merge"] == "left_only"]
        ov = both["Value_o"].to_numpy(dtype="float64")
        nv = both["Value_n"].to_numpy(dtype="float64")
        same_nan = np.isnan(ov) & np.isnan(nv)
        with np.errstate(invalid="ignore"):
            near = np.abs(nv - ov) <= TOL * np.maximum(1.0, np.abs(ov))
        chg = ~(same_nan | near)
        chg_bits = ~(same_nan | (ov == nv))
        fd = (both["Factor_Date_o"].to_numpy() != both["Factor_Date_n"].to_numpy())
        oth = np.zeros(len(both), dtype=bool)
        for c in other:
            a = both[c + "_o"].to_numpy()
            b = both[c + "_n"].to_numpy()
            oth |= ~((a == b) | (pd.isna(a) & pd.isna(b)))
        rec = {
            "n_old": int(len(both) + len(oo)), "n_new": int(len(both) + len(on)),
            "only_new": int(len(on)), "only_new_finite": int(np.isfinite(on["Value_n"].to_numpy(dtype="float64")).sum()),
            "only_old": int(len(oo)),
            "value_changed": int(chg.sum()), "value_changed_any_bit": int(chg_bits.sum()),
            "factor_date_changed": int(fd.sum()), "other_col_changed": int(oth.sum()),
        }
        if len(on):
            rec["only_new_tickers"] = int(on["Ticker"].nunique())
            rec["only_new_by_period"] = {str(k): int(v) for k, v in on.groupby("Period", observed=True).size().sort_index().items()}
            fdn = on["Factor_Date_n"]
            rec["only_new_factor_date_range"] = [str(fdn.min().date()), str(fdn.max().date())]
        if chg.sum():
            b2 = both[chg]
            rec["value_changed_tickers"] = int(b2["Ticker"].nunique())
            rec["value_changed_by_period"] = {str(k): int(v) for k, v in b2.groupby("Period", observed=True).size().sort_index().items()}
        if fd.sum():
            rec["factor_date_changed_by_period"] = {str(k): int(v) for k, v in both[fd].groupby("Period", observed=True).size().sort_index().items()}
        if len(oo):
            rec["only_old_by_period"] = {str(k): int(v) for k, v in oo.groupby("Period", observed=True).size().sort_index().items()}
        out[str(it)] = rec
    return out, dup_o, dup_n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("old_dir")
    ap.add_argument("new_dir")
    ap.add_argument("out_json")
    ap.add_argument("--batch", type=int, default=2_000_000)
    ap.add_argument("--chunk", type=int, default=10, help="정밀 대조에서 한 번에 읽는 항목 수")
    a = ap.parse_args()
    pa.set_cpu_count(2)
    pa.set_io_thread_count(2)
    res = {"old_dir": a.old_dir, "new_dir": a.new_dir, "tol_rel": TOL, "tables": {}}
    t0 = time.time()
    for tb in TABLES:
        po = Path(a.old_dir) / (tb + ".parquet")
        pn = Path(a.new_dir) / (tb + ".parquet")
        if not po.exists() or not pn.exists():
            print("[cache-diff] 파일 없음: %s 또는 %s" % (po, pn), file=sys.stderr)
            return 1
        fo, cols_o, rows_o = fingerprint(po, a.batch)
        print("[cache-diff] %s 옛 판 지문 · 행 %s · 항목 %d · %.0fs" % (tb, format(rows_o, ","), len(fo), time.time() - t0), flush=True)
        fn, cols_n, rows_n = fingerprint(pn, a.batch)
        print("[cache-diff] %s 새 판 지문 · 행 %s · 항목 %d · %.0fs" % (tb, format(rows_n, ","), len(fn), time.time() - t0), flush=True)
        only_o = sorted(set(fo) - set(fn))
        only_n = sorted(set(fn) - set(fo))
        diff = sorted(k for k in set(fo) & set(fn) if not np.array_equal(fo[k], fn[k]))
        per = {}
        dups = [0, 0]
        todo = diff + only_o + only_n
        for i in range(0, len(todo), a.chunk):
            part, d_o, d_n = exact_diff(po, pn, todo[i:i + a.chunk])
            per.update(part)
            dups[0] += d_o
            dups[1] += d_n
            print("[cache-diff] %s 정밀 대조 %d/%d 항목 · %.0fs" % (tb, min(i + a.chunk, len(todo)), len(todo), time.time() - t0), flush=True)
        tot = {k: int(sum(v.get(k, 0) for v in per.values())) for k in
               ("only_new", "only_new_finite", "only_old", "value_changed", "value_changed_any_bit", "factor_date_changed", "other_col_changed")}
        res["tables"][tb] = {
            "rows_old": int(rows_o), "rows_new": int(rows_n), "items_old": len(fo), "items_new": len(fn),
            "columns_old": cols_o, "columns_new": cols_n, "columns_equal": cols_o == cols_n,
            "items_only_old": only_o, "items_only_new": only_n, "items_fingerprint_diff": diff,
            "items_identical": len(set(fo) & set(fn)) - len(diff),
            "duplicate_keys": {"old": dups[0], "new": dups[1]},
            "totals": tot, "per_item": per,
        }
        print("[cache-diff] %s — 같은 항목 %d · 지문 다른 항목 %d · 옛 판에만 %d · 새 판에만 %d" % (
            tb, res["tables"][tb]["items_identical"], len(diff), len(only_o), len(only_n)))
        print("[cache-diff] %s — 새로 생긴 값 %s · 사라진 값 %s · 값 바뀜 %s · Factor_Date 바뀜 %s · 그 밖 열 바뀜 %s" % (
            tb, format(tot["only_new"], ","), format(tot["only_old"], ","), format(tot["value_changed"], ","),
            format(tot["factor_date_changed"], ","), format(tot["other_col_changed"], ",")))
        fdp = {}
        for v in per.values():
            for k, c in v.get("factor_date_changed_by_period", {}).items():
                fdp[k] = fdp.get(k, 0) + c
        res["tables"][tb]["factor_date_changed_by_period"] = dict(sorted(fdp.items()))
        if fdp:
            print("[cache-diff] %s — Factor_Date 바뀜의 기간 분포: %s" % (tb, dict(sorted(fdp.items()))))
        shown = [it for it in per if per[it]["only_new"] or per[it]["only_old"] or per[it]["value_changed"]]
        only_fd = [it for it in per if it not in shown and per[it]["factor_date_changed"]]
        for it in sorted(shown, key=lambda z: -(per[z]["only_new"] + per[z]["value_changed"] + per[z]["only_old"])):
            r = per[it]
            print("    %-28s 생김 %7d · 사라짐 %7d · 값 바뀜 %7d · 날짜 바뀜 %5d" % (
                it, r["only_new"], r["only_old"], r["value_changed"], r["factor_date_changed"]))
        if only_fd:
            print("    (값은 그대로이고 날짜만 바뀐 항목 %d개)" % len(only_fd))
    res["secs"] = round(time.time() - t0, 1)
    Path(a.out_json).write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    print("[cache-diff] 끝 · %.0fs · %s" % (time.time() - t0, a.out_json))
    return 0


if __name__ == "__main__":
    sys.exit(main())
