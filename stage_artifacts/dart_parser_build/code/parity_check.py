#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
파리티 검증: document.xml 원문파서 vs elestock.json 기존 24m 데이터.
report-level(rcept_no 매칭) + ticker-month net-buy 신호 level 대조.
파서 정확성 입증 = 자본급 백필 착수 조건.
"""
import os, re, json
import pandas as pd

ROOT = os.environ.get("QM_ROOT", r"C:\Users\99922\OneDrive\Quant_Module_Moltbot")
BUILD = os.path.join(ROOT, "stage_artifacts", "dart_parser_build")
CKDIR = os.path.join(BUILD, "cache", "monthly")


def to_int(x):
    if x is None: return None
    t = re.sub(r"[^0-9\-]", "", str(x))
    if t in ("", "-"): return None
    try: return int(t)
    except: return None


def main():
    # elestock baseline
    ele = pd.read_parquet(os.path.join(ROOT, ".cache", "dart", "insider_trades.parquet"))
    ele["rcept_no"] = ele["rcept_no"].astype(str)
    ele["ele_net"] = ele["sp_stock_lmp_irds_cnt"].map(to_int)
    ele["ele_after"] = ele["sp_stock_lmp_cnt"].map(to_int)
    ele["ele_reporter"] = ele["repror"]

    # parsed months available
    months = [f[:6] for f in os.listdir(CKDIR) if f.endswith(".parquet")]
    parsed = []
    for m in months:
        df = pd.read_parquet(os.path.join(CKDIR, m + ".parquet"))
        if "ok" in df.columns:
            df = df[df["ok"] == True]
        parsed.append(df)
    if not parsed:
        print("no parsed checkpoints"); return
    par = pd.concat(parsed, ignore_index=True)
    par["rcept_no"] = par["rcept_no"].astype(str)

    print(f"=== PARITY: parsed months={sorted(months)} ===")
    print(f"parsed reports (ok): {len(par)}   elestock total: {len(ele)}")

    # report-level join on rcept_no
    j = par.merge(ele[["rcept_no", "ele_net", "ele_after", "ele_reporter", "Ticker"]],
                  on="rcept_no", how="inner")
    print(f"\n--- report-level matched on rcept_no: {len(j)} ---")
    if len(j) == 0:
        print("NO OVERLAP — check month coverage"); return

    # net change agreement
    j["net_match"] = (j["net_change_qty"] == j["ele_net"])
    j["after_match"] = (j["after_qty"] == j["ele_after"])
    j["reporter_match"] = (j["reporter_name"].astype(str).str.strip() ==
                           j["ele_reporter"].astype(str).str.strip())
    n = len(j)
    print(f"net_change_qty exact match: {j['net_match'].sum()}/{n} ({100*j['net_match'].mean():.1f}%)")
    print(f"after_qty exact match:      {j['after_match'].sum()}/{n} ({100*j['after_match'].mean():.1f}%)")
    print(f"reporter_name match:        {j['reporter_match'].sum()}/{n} ({100*j['reporter_match'].mean():.1f}%)")

    # mismatches
    mism = j[~j["net_match"]]
    if len(mism):
        print(f"\n--- net mismatches ({len(mism)}) sample ---")
        print(mism[["rcept_no", "corp_name", "reporter_name", "net_change_qty", "ele_net",
                    "n_txns", "formula_version"]].head(15).to_string())

    # ticker-month net-buy signal parity (the real deliverable)
    par2 = par.copy()
    par2["ym"] = par2["rcept_dt"].astype(str).str[:6]
    par2["net"] = par2["net_change_qty"]
    par2["tk"] = par2["stock_code"].astype(str).str.zfill(6)
    sig_par = par2.groupby(["tk", "ym"]).agg(
        par_net=("net", "sum"),
        par_nbuy=("net", lambda s: (s > 0).sum()),
        par_nsell=("net", lambda s: (s < 0).sum()),
    ).reset_index()

    ele2 = ele.copy()
    ele2["ym"] = pd.to_datetime(ele2["rcept_dt"]).dt.strftime("%Y%m")
    ele2["tk"] = ele2["Ticker"].astype(str).str.replace("A", "", regex=False).str.zfill(6)
    ele2["net"] = ele2["ele_net"]
    sig_ele = ele2.groupby(["tk", "ym"]).agg(
        ele_net=("net", "sum"),
        ele_nbuy=("net", lambda s: (s > 0).sum()),
        ele_nsell=("net", lambda s: (s < 0).sum()),
    ).reset_index()

    sig = sig_par.merge(sig_ele, on=["tk", "ym"], how="inner")
    print(f"\n--- ticker-month net-buy signal: matched cells {len(sig)} ---")
    if len(sig):
        net_corr = sig["par_net"].corr(sig["ele_net"])
        nbuy_corr = sig["par_nbuy"].corr(sig["ele_nbuy"])
        exact_net = (sig["par_net"] == sig["ele_net"]).mean()
        print(f"net qty corr(par,ele):    {net_corr:.4f}")
        print(f"n_buy count corr:         {nbuy_corr:.4f}")
        print(f"net qty exact-match rate: {100*exact_net:.1f}%")

    # save report
    rep = {
        "parsed_months": sorted(months),
        "parsed_reports_ok": int(len(par)),
        "matched_reports": int(n),
        "net_match_rate": float(j["net_match"].mean()),
        "after_match_rate": float(j["after_match"].mean()),
        "reporter_match_rate": float(j["reporter_match"].mean()),
    }
    if len(sig):
        rep["signal_net_corr"] = float(net_corr)
        rep["signal_nbuy_corr"] = float(nbuy_corr)
        rep["signal_net_exact_rate"] = float(exact_net)
    outp = os.path.join(BUILD, "reports", "parity_report.json")
    json.dump(rep, open(outp, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"\nsaved -> {outp}")


if __name__ == "__main__":
    main()
