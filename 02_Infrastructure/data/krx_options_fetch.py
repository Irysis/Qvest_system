#!/usr/bin/env python3
"""
KRX OpenAPI Plus 옵션 chain 일별 fetch
- Range: 2010-01-04 ~ today
- Endpoint: opt_bydd_trd (KOSPI200 옵션 + 미니 + 위클리 + 통화/상품옵션)
- Output: .cache/krx_options/<YYYYMMDD>.parquet (daily)
- Index: .cache/krx_options/_index.parquet (manifest)
- Rate limit: 0.5 sec/call (안전)
- Resumable: 기존 cache 있으면 skip
"""
import os, sys, time, datetime as dt
from pathlib import Path
import requests
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

PROJ = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
CACHE = PROJ / ".cache" / "krx_options"
CACHE.mkdir(parents=True, exist_ok=True)
LOG = Path("/tmp/krx_options_fetch.log")

# Load API key
with open(PROJ / ".env") as f:
    for ln in f:
        if ln.startswith("KRX_API_KEY="):
            KEY = ln.split("=", 1)[1].strip().strip("\r")

URL = "http://data-dbg.krx.co.kr/svc/apis/drv/opt_bydd_trd"

# KRX 거래일 — 단순 weekday filter (정확한 휴장일은 응답 빈 처리)
def daterange(start, end):
    d = start
    while d <= end:
        if d.weekday() < 5:  # Mon~Fri
            yield d
        d += dt.timedelta(days=1)

START = dt.date(2010, 1, 4)
END = dt.date.today()

def log(msg):
    ts = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"{ts} {msg}"
    print(line, flush=True)
    with LOG.open("a") as f:
        f.write(line + "\n")

def fetch_day(d):
    bas = d.strftime("%Y%m%d")
    out = CACHE / f"{bas}.parquet"
    if out.exists():
        return "skip"
    try:
        r = requests.get(URL, params={"basDd": bas},
                         headers={"AUTH_KEY": KEY}, timeout=30)
        if r.status_code != 200:
            return f"http_{r.status_code}"
        rows = r.json().get("OutBlock_1", [])
        if not rows:
            return "empty"
        df = pd.DataFrame(rows)
        # Filter KOSPI200 옵션만 (KOSPI200 / 미니 / 위클리)
        # PROD_NM contains "코스피200" or KOSPI200
        df_k200 = df[df["PROD_NM"].str.contains("코스피200|KOSPI200|미니코스피", na=False, regex=True)]
        if len(df_k200) == 0:
            return "no_k200"
        df_k200.to_parquet(out, index=False)
        return f"ok_{len(df_k200)}"
    except Exception as e:
        return f"err_{str(e)[:60]}"

log(f"=== KRX options fetch start: {START} -> {END} ===")
days = list(daterange(START, END))
log(f"Total weekdays: {len(days)}")

stats = {"ok": 0, "skip": 0, "empty": 0, "no_k200": 0, "err": 0, "rows": 0}
for i, d in enumerate(days):
    res = fetch_day(d)
    if res.startswith("ok_"):
        stats["ok"] += 1
        stats["rows"] += int(res.split("_")[1])
    elif res == "skip":
        stats["skip"] += 1
    elif res == "empty":
        stats["empty"] += 1
    elif res == "no_k200":
        stats["no_k200"] += 1
    else:
        stats["err"] += 1
    if (i + 1) % 100 == 0:
        log(f"  [{i+1}/{len(days)}] {d} {res} stats={stats}")
    time.sleep(0.5)  # rate limit safety

log(f"=== Done. final stats={stats} ===")
print(f"OK={stats['ok']} skip={stats['skip']} empty={stats['empty']} no_k200={stats['no_k200']} err={stats['err']}")
print(f"Total rows accumulated: {stats['rows']:,}")
