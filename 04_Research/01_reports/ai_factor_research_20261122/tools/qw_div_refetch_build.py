"""qw_div_refetch_build.py — 퀀티에서 시계열 배치로 다시 받은 배당 항목(2012Q3~2013Q4 여섯 분기)을 긴 표로 바꾸고, 연구가 쓰는 보충 표를 만든다.

배경(README '위험 평가 모형 1부'의 '자료 수리'): 퀀티 재무 v2 통합문서(피어 배치)의 배당 시트 다섯이 기간 열 201209~201312 에서 '#INVALID OPTION' 을 돌려줘
  원천 표 · 재무 캐시에 그 여섯 분기의 배당 행이 없다. 같은 항목을 시계열 배치(Time Series (Company) · Base Date = FQ0)로 조회하면 값이 온다(도훈 11-23
  '제대로 된 퀀티 세팅으로 (가)안 실행'). 조회는 인프라의 시계열 수집 스크립트(ops/qw_fund_v2_tax_ts.ps1)를 본뜬 임시판으로 했다 — 항목 코드 · 끝 날짜만 바꿨다.
하는 일(인프라의 표 · 캐시는 읽기만 한다 — 쓰는 곳은 연구 캐시 .cache/aif_research/followup/div_refetch/ 뿐):
  1 통합문서 판독 — 8행 종목 코드 · B10 항목 코드 · 11행 단위 · 12행 Base Date(FQ0 여야 한다) · 15행부터 A열 날짜 'YYYY-MM'
  2 날짜 행 → 재무 기간: 인프라의 규칙 그대로(data/qw_fund_v2_tax_ingest.py::period_from_row_date — 날짜 행 d 는 d − 3개월이 든 회계 분기 · 그 분기가 끝나는
    달력 분기로 적는다 · 결산월은 fiscal_month.parquet). 금액 항목은 천 원 단위 → 원(× 1000) · 주당 항목은 그대로(원).
  3 대조 — 피어 배치로 이미 받아 둔 분기(창 앞뒤)에서 값이 같은지. 하나라도 0 이 아닌 칸 가운데 같은 비율이 --min-same 에 못 미치면 아무것도 쓰지 않는다.
  4 여섯 분기의 긴 표 div_q.parquet(Ticker · Period · Item · Value · RowDate · fetched_at) — 인프라 원천 표와 같은 기간 표기 · 같은 단위
  5 보충 표 cashdiv_ttm_supplement.parquet — 현금배당액(전체)의 최근 4분기 합. 재무 캐시의 분기 단독 값(CashDivTotal_Q)에 여섯 분기를 끼워 201209~201409 의
    합을 내고, 쓸 수 있는 첫날은 캐시의 같은 종목 · 같은 기간 총자산 행의 값(같은 보고서)을 쓴다. 위험 모형 1부가 캐시에 그 기간 행이 없을 때만 읽는다.
수정 주당 항목(AdjDPS 등)은 받은 날의 수정 계수 기준이다 — 그 사이 무상증자 · 분할이 있던 종목은 예전에 받은 값과 배수만큼 다르다(대조에서 어긋난 칸으로 적힌다).
실행: python tools/qw_div_refetch_build.py --root <루트> --book <xlsx>:<시트>=<항목>[,<시트>=<항목>...] [--book ...] [--dry-run]
"""
import argparse
import importlib.util
import json
import os
import re
import sys

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.dataset as ds
import pyarrow.parquet as pq
from openpyxl import load_workbook

ITEMS = {  # 항목: (퀀티 코드, 종류, 원천 표)
    "CashDivTotal": ("M441800.M", "amount", "FundV2_META"), "CashDivCommon": ("M441600.M", "amount", "FundV2_META"), "AdjDPS": ("M423400.M", "per_share", "FundV2_META"),
    "AdjDPSInterim": ("M423000.M", "per_share", "FundV2_INFO"), "AdjDPSFinal": ("M423200.M", "per_share", "FundV2_INFO"),
}
GAP = ["201209", "201212", "201303", "201306", "201309", "201312"]
UNIT_SCALE = {"local thou": 1e3, "krw thou": 1e3}
OUT_REL = ".cache/aif_research/followup/div_refetch"


def load_infra_mapping(root):
    """인프라의 날짜 행 → 기간 규칙(읽기만)."""
    spec = importlib.util.spec_from_file_location("qw_tax_ingest", root + "/02_Infrastructure/data/qw_fund_v2_tax_ingest.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.period_from_row_date, m.load_fiscal_months(root)


def read_sheet(ws, item):
    code, kind, _ = ITEMS[item]
    rows = list(ws.iter_rows(min_row=1, max_row=400, values_only=True))
    b1, b10 = str(rows[0][1] or ""), str(rows[9][1] or "").strip()
    if b10 != code:
        raise SystemExit("시트 %s: B10 '%s' != 기대 코드 '%s'" % (ws.title, b10, code))
    tick = [str(v).strip() if v is not None else "" for v in rows[7][1:]]
    n = max(i for i, t in enumerate(tick) if t) + 1
    base = {str(v).strip() for v in rows[11][1:1 + n]}
    if base != {"FQ0"}:
        raise SystemExit("시트 %s: Base Date 가 FQ0 가 아니다 %s" % (ws.title, sorted(base)))
    unit = [str(v).strip().lower() if v is not None else "" for v in rows[10][1:1 + n]]
    stamp = re.search(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", b1)
    rec = []
    for r in rows[14:]:
        if r[0] is None or not str(r[0]).strip():
            continue
        d = str(r[0]).strip()[:7]
        vals = pd.to_numeric(pd.Series(list(r[1:1 + n]) + [None] * (n - len(r[1:1 + n]))), errors="coerce").to_numpy(float)
        ok = np.isfinite(vals)
        rec.append(pd.DataFrame({"Ticker": np.array(tick[:n], dtype=object)[ok], "RowDate": d, "raw": vals[ok], "unit": np.array(unit, dtype=object)[ok]}))
    df = pd.concat(rec, ignore_index=True)
    if kind == "amount":
        bad = sorted(set(df.loc[~df["unit"].isin(list(UNIT_SCALE)), "unit"]))
        if bad:
            raise SystemExit("시트 %s: 금액 항목인데 모르는 단위 %s" % (ws.title, bad))
        df["Value"] = df["raw"] * df["unit"].map(UNIT_SCALE)
    else:
        df["Value"] = df["raw"]
    df["Item"], df["fetched_at"] = item, (stamp.group(1).replace(" ", "T") if stamp else None)
    return df[["Ticker", "RowDate", "Item", "Value", "fetched_at"]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("QM_ROOT", ""))
    ap.add_argument("--book", action="append", required=True, help="<xlsx>:<시트>=<항목>[,<시트>=<항목>...]")
    ap.add_argument("--min-same", type=float, default=0.95, help="겹치는 분기에서 같은 값의 비율 하한(하나라도 0 이 아닌 칸)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    root = a.root.replace("\\", "/").rstrip("/")
    to_period, fms = load_infra_mapping(root)
    parts = []
    for b in a.book:
        path, spec = b.rsplit(":", 1)
        wb = load_workbook(path, read_only=True, data_only=True)
        for kv in spec.split(","):
            sheet, item = kv.split("=")
            parts.append(read_sheet(wb[sheet], item))
        wb.close()
    new = pd.concat(parts, ignore_index=True)
    fm = new["Ticker"].map(fms)
    no_fm = new[fm.isna()]
    new = new[fm.notna()].copy()
    key = list(zip(new["RowDate"], fm[fm.notna()].astype(int)))
    lab = {k: to_period(*k) for k in set(key)}
    new["Period"] = [lab[k] for k in key]
    dup = new.duplicated(["Ticker", "Period", "Item"], keep=False)
    if dup.any() and (new[dup].groupby(["Ticker", "Period", "Item"])["Value"].nunique() > 1).any():
        raise SystemExit("두 날짜 행이 한 기간에 서로 다른 값으로 떨어진다")
    new = new.drop_duplicates(["Ticker", "Period", "Item"]).reset_index(drop=True)

    # 대조 — 피어 배치로 받아 둔 분기(창 밖)
    rep = {"items": {}, "tickers_without_fiscal_month": {"tickers": sorted(no_fm["Ticker"].unique()), "nonzero_cells": int((no_fm["Value"] != 0).sum())}}
    ok_all = True
    for item in sorted(new["Item"].unique()):
        db = ITEMS[item][2]
        x = new[(new["Item"] == item) & ~new["Period"].isin(GAP)]
        peer = pq.read_table("%s/.cache/qw_fund_v2/%s.parquet" % (root, db), filters=[("Item", "==", item), ("Period", "in", sorted(x["Period"].unique()))]).to_pandas()
        m = x.merge(peer[["Ticker", "Period", "Value"]], on=["Ticker", "Period"], suffixes=("", "_peer"))
        nz = (m["Value"] != 0) | (m["Value_peer"] != 0)
        same = np.isclose(m["Value"], m["Value_peer"], rtol=1e-6, atol=0.5)
        bad = m[nz & ~same]
        g = new[(new["Item"] == item) & new["Period"].isin(GAP)]
        share = float((same & nz).sum() / max(nz.sum(), 1))
        rep["items"][item] = {"code": ITEMS[item][0], "overlap_periods": sorted(x["Period"].unique()), "overlap_cells": int(len(m)), "overlap_nonzero": int(nz.sum()),
                              "overlap_same": int((same & nz).sum()), "overlap_same_share": share,
                              "mismatch": [{"Ticker": r.Ticker, "Period": r.Period, "refetch": float(r.Value), "peer": float(r.Value_peer)} for r in bad.head(20).itertuples()],
                              "gap_rows": int(len(g)), "gap_nonzero_by_period": {p: int(((g["Period"] == p) & (g["Value"] != 0)).sum()) for p in GAP},
                              "gap_rows_by_period": {p: int((g["Period"] == p).sum()) for p in GAP},
                              "peer_already_has_gap_rows": int(len(pq.read_table("%s/.cache/qw_fund_v2/%s.parquet" % (root, db), filters=[("Item", "==", item), ("Period", "in", GAP)])))}
        ok_all = ok_all and share >= a.min_same and nz.sum() >= 20
        print("[대조] %-14s 겹친 칸 %d · 하나라도 0 아님 %d · 같음 %d (%.1f%%) · 여섯 분기의 행 %d(0 아님 %s)" % (
            item, len(m), int(nz.sum()), int((same & nz).sum()), 100 * share, len(g), list(rep["items"][item]["gap_nonzero_by_period"].values())))
    if not ok_all:
        print("[멈춤] 대조가 기준(%.2f)에 못 미치는 항목이 있다 — 아무것도 쓰지 않는다" % a.min_same)
        print(json.dumps(rep, ensure_ascii=False, indent=1)[:3000])
        return 3
    gap = new[new["Period"].isin(GAP)][["Ticker", "Period", "Item", "Value", "RowDate", "fetched_at"]].sort_values(["Item", "Ticker", "Period"]).reset_index(drop=True)

    # 보충 표 — 현금배당액(전체)의 최근 4분기 합(201209~201409)
    supp, rep["supplement"] = None, None
    if "CashDivTotal" in set(gap["Item"]):
        d = ds.dataset(root + "/.cache/fundamental_quarterly.parquet", format="parquet")
        per = ["201112", "201203", "201206"] + GAP + ["201403", "201406", "201409", "201412"]
        c = d.to_table(columns=["Ticker", "Period", "Period_Date", "Factor_Date", "Item", "Value"],
                       filter=ds.field("Item").isin(["CashDivTotal_Q", "CashDivTotal", "TotalAssets"]) & ds.field("Period").isin(per)).to_pandas()
        q = c[c["Item"] == "CashDivTotal_Q"][["Ticker", "Period", "Value"]]
        g = gap[gap["Item"] == "CashDivTotal"][["Ticker", "Period", "Value"]]
        g = g.merge(q[["Ticker", "Period"]], on=["Ticker", "Period"], how="left", indicator=True)
        g = g[g["_merge"] == "left_only"].drop(columns="_merge")                              # 캐시에 이미 있는 분기는 캐시 값을 쓴다
        Q = pd.concat([q, g]).pivot(index="Ticker", columns="Period", values="Value").reindex(columns=per)
        ttm = Q.T.rolling(4, min_periods=4).sum().T                                           # 네 분기가 다 있을 때만
        have = c[c["Item"] == "CashDivTotal"].set_index(["Ticker", "Period"])["Value"]
        chk = ttm.stack().rename("ttm").reset_index().merge(have.rename("cache").reset_index(), on=["Ticker", "Period"])
        dif = float(np.abs(chk["ttm"] - chk["cache"]).max()) if len(chk) else float("nan")
        want = ["201209", "201212", "201303", "201306", "201309", "201312", "201403", "201406", "201409"]
        s = ttm[want].stack().rename("Value").reset_index()
        s = s.merge(have.rename("cache").reset_index(), on=["Ticker", "Period"], how="left")
        s = s[s["cache"].isna()].drop(columns="cache")                                        # 캐시에 그 기간의 합이 없을 때만
        ta = c[c["Item"] == "TotalAssets"][["Ticker", "Period", "Period_Date", "Factor_Date"]]
        s = s.merge(ta, on=["Ticker", "Period"], how="inner")
        supp = s[["Ticker", "Period", "Period_Date", "Factor_Date", "Value"]].sort_values(["Ticker", "Period"]).reset_index(drop=True)
        rep["supplement"] = {"rows": int(len(supp)), "rows_by_period": {p: int((supp["Period"] == p).sum()) for p in want}, "nonzero_share": float((supp["Value"] != 0).mean()),
                             "formula_check_cells": int(len(chk)), "formula_check_max_abs_diff_vs_cache": dif,
                             "note": "네 분기 합 = 캐시의 분기 단독 값 + 다시 받은 여섯 분기 · 쓸 수 있는 첫날 = 캐시의 같은 기간 총자산 행 · 캐시에 그 기간의 합이 이미 있으면 넣지 않는다"}
        print("[보충] 현금배당액 최근 4분기 합 %d행(기간별 %s) · 0 이 아닌 비율 %.2f · 식 확인(캐시에 합이 있는 기간) %d칸 최대 차이 %.3g" % (
            len(supp), list(rep["supplement"]["rows_by_period"].values()), rep["supplement"]["nonzero_share"], len(chk), dif))
    rep.update(at=pd.Timestamp.now().strftime("%Y-%m-%d %H:%M:%S"), books=a.book, gap_periods=GAP, rows=int(len(gap)))
    if a.dry_run:
        print("[dry-run] 쓰지 않음 — 여섯 분기 %d행" % len(gap))
        return 0
    out = root + "/" + OUT_REL
    os.makedirs(out, exist_ok=True)

    def put(df, name):
        dst = out + "/" + name
        if os.path.exists(dst) and pq.read_table(dst).to_pandas().equals(df):                 # 내용이 같으면 그대로 둔다(파일의 수정 시각이 위험 모형 1부의 판 표식에 들어간다)
            print("[그대로] %s — 내용이 같다" % name)
            return
        tmp = "%s/%s.%d.tmp" % (out, name, os.getpid())
        pq.write_table(pa.Table.from_pandas(df, preserve_index=False), tmp, compression="zstd")
        os.replace(tmp, dst)
    put(gap, "div_q.parquet")
    if supp is not None:
        put(supp, "cashdiv_ttm_supplement.parquet")
    with open(out + "/meta.json", "w", encoding="utf-8") as fh:
        json.dump(rep, fh, ensure_ascii=False, indent=1)
    print("[저장] %s — div_q.parquet %d행%s" % (out, len(gap), " · cashdiv_ttm_supplement.parquet %d행" % len(supp) if supp is not None else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
