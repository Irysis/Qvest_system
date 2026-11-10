"""후보(차입 두 줄 기간 완비) vs 지금 정본 — 항목별 차이: 후보에만 · 정본에만 · 값 · 날짜 (2026-11-10 · 읽기 전용)"""
import sys
import pandas as pd
import pyarrow.parquet as pq

ROOT = "G:/OneDrive/Quant_Module_Moltbot/.cache/"
SP = sys.argv[1]
for label, canon, cand in [("병합 표", ROOT + "fundamental_merged.parquet", SP + "/cand_merged.parquet"),
                           ("분기 표", ROOT + "fundamental_xlsx.parquet", SP + "/cand_xlsx.parquet")]:
    cols = ["Ticker", "Period", "Item", "Value", "Factor_Date"]
    a = pq.read_table(canon, columns=cols).to_pandas()
    b = pq.read_table(cand, columns=cols).to_pandas()
    for d in (a, b):
        d["Period"] = d["Period"].astype(str)
        d["Factor_Date"] = pd.to_datetime(d["Factor_Date"]).astype("datetime64[s]")
    m = a.merge(b, on=["Ticker", "Period", "Item"], how="outer", suffixes=("_o", "_n"), indicator=True)
    both = m[m["_merge"] == "both"]
    vchg = both[~((both["Value_o"] == both["Value_n"]) | (both["Value_o"].isna() & both["Value_n"].isna()))]
    dchg = both[both["Factor_Date_o"] != both["Factor_Date_n"]]
    g = pd.DataFrame({"only_new": m[m["_merge"] == "right_only"].groupby("Item").size(),
                      "only_old": m[m["_merge"] == "left_only"].groupby("Item").size(),
                      "value_chg": vchg.groupby("Item").size(), "date_chg": dchg.groupby("Item").size()}).fillna(0).astype(int)
    g = g[(g != 0).any(axis=1)]
    print(f"== {label}: 정본 {len(a):,} → 후보 {len(b):,} ({len(b) - len(a):+,}) · 바뀐 항목 {len(g)}")
    print(g.to_string())
    nw = m[(m["_merge"] == "right_only") & m["Item"].isin(["ShortTermBorr", "LongTermBorr"])]
    print(f"   새 차입 행 값: 0 인 행 {int((nw['Value_n'] == 0).sum()):,} / {len(nw):,}")
    od = m[(m["_merge"] == "left_only") & m["Item"].isin(["ShortTermBorr", "LongTermBorr"])]
    if len(od):
        print("   정본에만 있는 차입 행(순서 계약이 새로 버린 것) 예:")
        print(od.head(5).to_string())
    if len(dchg):
        print("   날짜가 바뀐 행 예:")
        print(dchg.head(5)[["Ticker", "Period", "Item", "Factor_Date_o", "Factor_Date_n"]].to_string())
