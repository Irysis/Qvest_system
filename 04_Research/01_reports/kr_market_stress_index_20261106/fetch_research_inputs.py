#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""연구용 직접 수급 — ECOS 817Y002(시장금리 · 일별) · 731Y001(원/달러) · 731Y002(주요국 환율) · FRED(VIX · STLFSI · HY/BBB OAS).

v1(자본시장 전체) 지수의 금리 · 환율 · 해외 입력을 파이프라인 캐시(.cache)와 별개로 이 보고서 폴더(output/)에 받는다.
  * 왜 따로 받나: 캐시가 2026-10-20 에 멈춰 있고(daily_refresh [4] 단계 정체), 캐시 수집기의 817Y002 항목 코드 매핑이
    ECOS 항목 목록과 어긋나는지 여기서 대조한다(아래 verify_against_cache). 파이프라인(.cache)은 건드리지 않는다.
  * 키: ECOS = 수집기 파일(data_collector_ecos.R)의 기본값을 읽는다(출력하지 않음) · FRED = 환경변수 FRED_API_KEY.
  * 가용일 규칙: 받은 계열은 v1 에서 fred_asof_join 으로 붙인다 — 등록부에 없는 계열(CP91 · 국고채 1/5/20년 · 통안증권 · MMF 등)은
    연구용 규칙 사본 output/fred_availability_rules_research.json 에 817Y002 형제 계열과 같은 규칙(다음 한국 거래일)으로 추가한다.
실행: <repo>/.venv_qvest_ml/Scripts/python.exe fetch_research_inputs.py
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import time
import urllib.parse
import urllib.request

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..")).replace("\\", "/")
OUT = HERE + "/output"
os.makedirs(OUT, exist_ok=True)
TODAY = dt.date.today().strftime("%Y%m%d")

# ECOS 817Y002 항목 — 2026-11-06 StatisticItemList 로 확인한 코드(이름은 ECOS 표기 그대로)
ECOS_RATES = {
    "010101000": ("KR_Call1D", "콜금리(1일, 전체거래)"),
    "010190000": ("KR_Gov1Y", "국고채(1년)"),
    "010200000": ("KR_Gov3Y", "국고채(3년)"),
    "010200001": ("KR_Gov5Y", "국고채(5년)"),
    "010210000": ("KR_Gov10Y", "국고채(10년)"),
    "010220000": ("KR_Gov20Y", "국고채(20년)"),
    "010400000": ("KR_MSB91D", "통안증권(91일)"),
    "010400001": ("KR_MSB1Y", "통안증권(1년)"),
    "010400002": ("KR_MSB2Y", "통안증권(2년)"),
    "010502000": ("KR_CD91", "CD(91일)"),
    "010503000": ("KR_CP91", "CP(91일)"),
    "010150000": ("KR_KORIBOR3M", "KORIBOR(3개월)"),
    "010300000": ("KR_CorpAA", "회사채(3년, AA-)"),
    "010320000": ("KR_CorpBBB", "회사채(3년, BBB-)"),
    "010501000": ("KR_MMF7D", "MMF(7일)"),
    "010260000": ("KR_KDB1Y", "산금채(1년)"),
}
FRED_SERIES = {"VIXCLS": "VIX", "STLFSI4": "StL_Fin_Stress", "BAMLH0A0HYM2": "HY_Spread", "BAMLC0A4CBBB": "BBB_Spread"}
# ICE 달러지수 공식(가중 기하평균) — ecos_fx_majors 의 ECOS_DXY_PROXY 와 같은 식
DXY_W = {"EURUSD": -0.576, "USDJPY": 0.136, "GBPUSD": -0.119, "USDCAD": 0.091, "USDSEK": 0.042, "USDCHF": 0.036}
DXY_K = 50.14348112


def log(*a):
    print("[fetch]", *a, flush=True)


def ecos_key():
    src = open(ROOT + "/02_Infrastructure/data/data_collector_ecos.R", encoding="utf-8").read()
    m = re.search(r'ECOS_API_KEY <- "([A-Z0-9]+)"', src)
    if not m:
        raise SystemExit("[fetch] ECOS 키를 수집기 파일에서 찾지 못했다")
    return m.group(1)


def _get_json(url, tries=3):
    for i in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            if i == tries - 1:
                raise
            log(f"retry {i + 1}: {type(e).__name__}")
            time.sleep(5)


def ecos_series(key, stat, item, start="19950101", end=None, freq="D"):
    end = end or TODAY
    url = f"https://ecos.bok.or.kr/api/StatisticSearch/{key}/json/kr/1/10000/{stat}/{freq}/{start}/{end}/{item}"
    j = _get_json(url)
    body = j.get("StatisticSearch")
    if not body:
        raise RuntimeError(f"ECOS {stat}/{item}: {str(j)[:200]}")
    rows = body.get("row", [])
    n_total = int(body.get("list_total_count", len(rows)))
    if n_total > len(rows):
        raise RuntimeError(f"ECOS {stat}/{item}: {n_total} 행 중 {len(rows)} 만 수신 — 페이지 분할 필요")
    df = pd.DataFrame(rows)
    t = df["TIME"].astype(str)
    df["Date"] = pd.to_datetime(t, format="%Y%m%d" if freq == "D" else "%Y%m", errors="coerce")
    df["Value"] = pd.to_numeric(df["DATA_VALUE"], errors="coerce")
    df["Item_name"] = df["ITEM_NAME1"]
    return df[["Date", "Value", "Item_name"]].dropna(subset=["Date"]).sort_values("Date").reset_index(drop=True)


def ecos_items(key, stat):
    j = _get_json(f"https://ecos.bok.or.kr/api/StatisticItemList/{key}/json/kr/1/200/{stat}")
    return j.get("StatisticItemList", {}).get("row", [])


def fetch_rates(key):
    parts = []
    for code, (sid, kname) in ECOS_RATES.items():
        df = ecos_series(key, "817Y002", code)
        df["Series"] = sid
        df["Item_code"] = code
        parts.append(df)
        log(f"817Y002 {sid:<13} {kname:<16} {len(df):>5}행 {df.Date.min().date()}~{df.Date.max().date()} · ECOS 이름 '{df.Item_name.iloc[0]}'")
        time.sleep(0.3)
    out = pd.concat(parts, ignore_index=True)
    out.to_parquet(OUT + "/research_pull_ecos_817Y002.parquet", index=False)
    return out


def fetch_krw(key):
    df = ecos_series(key, "731Y001", "0000001", start="20000101")
    df["Series"] = "ECOS_KRW_USD"
    df.to_parquet(OUT + "/research_pull_ecos_krw.parquet", index=False)
    log(f"731Y001 원/달러 {len(df)}행 {df.Date.min().date()}~{df.Date.max().date()}")
    return df


def fetch_fx_majors(key):
    """731Y002 주요국 통화의 대미달러 환율(ECOS 표기 '일본엔/달러' 등) → ICE 공식 DXY 프록시(캐시 ECOS_DXY_PROXY 와 같은 식)."""
    items = ecos_items(key, "731Y002")
    want = {"일본엔/달러": "USDJPY", "달러/유로": "EURUSD", "달러/영국파운드": "GBPUSD",
            "캐나다달러/달러": "USDCAD", "스웨덴크로나/달러": "USDSEK", "스위스프랑/달러": "USDCHF"}
    code = {}
    for it in items:
        nm = it["ITEM_NAME"].replace(" ", "")
        if nm in want and want[nm] not in code:
            code[want[nm]] = it["ITEM_CODE"]
    missing = [v for v in want.values() if v not in code]
    if missing:
        raise RuntimeError(f"731Y002 항목 미발견: {missing} · 목록={[i['ITEM_NAME'] for i in items][:40]}")
    cross = None
    for v, c in code.items():
        df = ecos_series(key, "731Y002", c, start="19990101")[["Date", "Value"]].rename(columns={"Value": v})
        cross = df if cross is None else cross.merge(df, on="Date", how="outer")
        time.sleep(0.3)
    cross = cross.sort_values("Date").reset_index(drop=True)
    dxy = DXY_K
    for k, w in DXY_W.items():
        dxy = dxy * cross[k] ** w
    cross["DXY_PROXY"] = dxy
    cross.to_parquet(OUT + "/research_pull_ecos_fx_majors.parquet", index=False)
    log(f"731Y002 6통화 → DXY 프록시 {len(cross)}행 {cross.Date.min().date()}~{cross.Date.max().date()} · 최근 {cross.DXY_PROXY.dropna().iloc[-1]:.2f}")
    return cross


def fetch_fred():
    key = os.environ.get("FRED_API_KEY", "")
    if not key:
        log("FRED_API_KEY 없음 — FRED 직접 수급 생략(캐시 사용)")
        return None
    parts = []
    for sid, name in FRED_SERIES.items():
        q = urllib.parse.urlencode({"series_id": sid, "api_key": key, "file_type": "json", "observation_start": "1996-01-01"})
        j = _get_json("https://api.stlouisfed.org/fred/series/observations?" + q)
        df = pd.DataFrame(j["observations"])[["date", "value"]]
        df["Date"] = pd.to_datetime(df["date"])
        df["Value"] = pd.to_numeric(df["value"], errors="coerce")
        df["Series_ID"] = sid
        df["Series"] = name
        parts.append(df[["Date", "Value", "Series_ID", "Series"]])
        v = df.dropna(subset=["Value"])
        log(f"FRED {sid:<13} {len(v)}행 {v.Date.min().date()}~{v.Date.max().date()} · 최근 {v.Value.iloc[-1]}")
        time.sleep(0.3)
    out = pd.concat(parts, ignore_index=True)
    out.to_parquet(OUT + "/research_pull_fred.parquet", index=False)
    return out


def verify_against_cache(rates):
    """캐시 ecos_bond_rates 의 KR_Gov3Y · KR_CD91 이 ECOS 어느 항목과 일치하는지 대조(수집기 항목 코드 검증)."""
    cache = pd.read_parquet(ROOT + "/.cache/ecos_bond_rates.parquet")
    cache["Date"] = pd.to_datetime(cache["Date"])
    rep = {}
    for cached_name, candidates in {"KR_Gov3Y": ["KR_Gov1Y", "KR_Gov3Y"], "KR_CD91": ["KR_KORIBOR3M", "KR_CD91"],
                                    "KR_Gov10Y": ["KR_Gov10Y"], "KR_CorpAA": ["KR_CorpAA"], "KR_Call1D": ["KR_Call1D"]}.items():
        c = cache[cache.Series == cached_name][["Date", "Value"]].rename(columns={"Value": "cached"})
        for cand in candidates:
            r = rates[rates.Series == cand][["Date", "Value"]].rename(columns={"Value": "ecos"})
            m = c.merge(r, on="Date").dropna()
            if len(m) == 0:
                continue
            d = (m.cached - m.ecos).abs()
            rep[f"{cached_name} vs ECOS {cand}"] = {"n": int(len(m)), "mean_abs_diff": round(float(d.mean()), 4),
                                                    "share_exact": round(float((d < 1e-9).mean()), 4)}
    for k, v in rep.items():
        log(f"verify {k}: n={v['n']} mean|diff|={v['mean_abs_diff']} exact={v['share_exact']}")
    return rep


def write_rules_copy():
    """등록부 규칙 파일을 복사해 연구용 계열을 추가(등록부 원본 무변경)."""
    src = ROOT + "/06_Registry/fred_availability_rules.json"
    R = json.load(open(src, encoding="utf-8"))
    have = {s["id"] for s in R["series"]} | {a for s in R["series"] for a in (s.get("aliases") or [])}
    sib = next(s for s in R["series"] if s["id"] == "KR_Gov10Y")
    added = []
    for code, (sid, kname) in ECOS_RATES.items():
        if sid in have:
            continue
        s = json.loads(json.dumps(sib))
        s["id"] = sid
        s["name"] = f"{kname}(ECOS 817Y002 {code} · 연구용)"
        s["aliases"] = []
        for b in s["bounds"]:
            b["basis"] = f"연구용 사본 — 817Y002 형제 계열(KR_Gov10Y)과 같은 규칙(다음 한국 거래일). 원본 규칙 파일은 무변경 · {TODAY}"
        R["series"].append(s)
        added.append(sid)
    R["version"] = R["version"] + f"+research{TODAY}"
    dst = OUT + "/fred_availability_rules_research.json"
    json.dump(R, open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    log(f"rules copy → {dst} · added {added}")
    return dst, added


def main():
    t0 = time.time()
    key = ecos_key()
    rates = fetch_rates(key)
    krw = fetch_krw(key)
    fx = fetch_fx_majors(key)
    fred = fetch_fred()
    rep = verify_against_cache(rates)
    rules_path, added = write_rules_copy()
    meta = {"fetched_at": dt.datetime.now().isoformat(timespec="seconds"),
            "ecos_817Y002_items": {c: {"series": s, "ecos_name": n} for c, (s, n) in ECOS_RATES.items()},
            "ecos_817Y002_last_date": str(rates.groupby("Series").Date.max().min().date()),
            "krw_last_date": str(krw.Date.max().date()), "fx_last_date": str(fx.Date.max().date()),
            "fred_last_dates": None if fred is None else {k: str(v.date()) for k, v in fred.dropna(subset=["Value"]).groupby("Series_ID").Date.max().items()},
            "cache_item_code_verification": rep, "rules_research_copy": rules_path, "rules_added_series": added,
            "elapsed_sec": round(time.time() - t0, 1)}
    json.dump(meta, open(OUT + "/research_pull_meta.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    log("done", meta["elapsed_sec"], "s")


if __name__ == "__main__":
    main()
