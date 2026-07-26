#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
pull_dart_products.py — 474 상장사 사업보고서 원문에서 '제품/매출' 텍스트 섹션 추출.

★API vs 파싱 경계 (실측 근거, probe_dart_segment.json):
   - fnlttSinglAcntAll.json = HTTP 200, 213 line / 121 distinct account, 부문·제품 라인 0건
     → **DART OpenAPI 정형 엔드포인트에 제품별 매출은 없다** (재무제표 본표만).
   - 따라서 제품별 매출은 document.xml(공시서류 원본) 파싱이 유일 경로.

절차: list.json(pblntf_ty=A) → 사업보고서 rcept_no → document.xml(zip) → 본문 XML
      → 'II. 사업의 내용' 중 매출/제품 관련 구간만 추출해 경량 텍스트로 저장.

출력: fq073/dart_products/<Ticker>.json  { Ticker, corp_code, corp_name, rcept_no,
        report_nm, rcept_dt, text_sales(발췌), text_overview(발췌), n_bytes_raw }
      fq073/pull_dart_products_log.json
"""
import os, re, sys, io, json, zipfile, time, threading
import urllib.request, urllib.parse
from concurrent.futures import ThreadPoolExecutor

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
FQ = os.path.join(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold/fq073")
DOUT = os.path.join(FQ, "dart_products")
os.makedirs(DOUT, exist_ok=True)

BGN = os.environ.get("FQ073_BGN", "20240101")
END = os.environ.get("FQ073_END", "20251231")


def load_key(name="DART_API_KEY"):
    with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8", errors="ignore") as f:
        for ln in f:
            ln = ln.strip()
            if ln.startswith(name + "="):
                return ln.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("[pull] DART_API_KEY 부재")


KEY = load_key()
BASE = "https://opendart.fss.or.kr/api/"
_lock = threading.Lock()
_done = [0]


def get(path, params, binary=False, timeout=180):
    full = BASE + path + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(full, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                b = r.read()
                return r.status, (b if binary else b.decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            return e.code, e.read()[:300].decode("utf-8", "replace")
        except Exception as e:
            if attempt == 2:
                return -1, "EXC:%s" % type(e).__name__
            time.sleep(1.5 * (attempt + 1))
    return -1, "EXC:retry_exhausted"


def strip_tags(x):
    x = re.sub(r"<[^>]+>", " ", x)
    x = x.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    return re.sub(r"[ \t\u00a0]+", " ", x)


def decode_any(raw):
    for enc in ("utf-8", "cp949", "euc-kr"):
        try:
            return raw.decode(enc)
        except Exception:
            pass
    return raw.decode("utf-8", "replace")


# 제품/매출 관련 섹션 앵커
ANCHOR_SALES = re.compile(r"(매출\s*및\s*수주\s*상황|매출\s*실적|판매\s*경로|주요\s*제품\s*등의\s*현황|"
                          r"주요\s*제품\s*및\s*서비스|부문별\s*매출|제품별\s*매출|매출\s*유형)")
ANCHOR_OVW = re.compile(r"(사업의\s*개요|주요\s*사업의\s*내용|영업의\s*개황|주요\s*제품)")


def extract(plain, anchor, budget=14000, span=2600):
    out, used = [], 0
    for m in anchor.finditer(plain):
        if used >= budget:
            break
        s = plain[m.start(): m.start() + span]
        out.append(s)
        used += len(s)
    return re.sub(r"\s+", " ", " ||| ".join(out))[:budget]


def work(row):
    tk, cc, nm = row["Ticker"], row["corp_code"], row["corp_name"]
    fp = os.path.join(DOUT, "%s.json" % tk)
    if os.path.exists(fp) and os.path.getsize(fp) > 200:
        with _lock:
            _done[0] += 1
        return {"Ticker": tk, "status": "cached"}

    st, body = get("list.json", dict(crtfc_key=KEY, corp_code=cc, bgn_de=BGN, end_de=END,
                                     pblntf_ty="A", page_count="100"))
    rec = {"Ticker": tk, "corp_code": cc, "corp_name": nm, "list_http": st}
    if st != 200:
        rec["status"] = "list_http_%s" % st
    else:
        try:
            j = json.loads(body)
        except Exception:
            j = {}
        rec["list_status"] = j.get("status")
        lst = j.get("list", []) or []
        # 정기 사업보고서 우선 (분기/반기 제외)
        biz = [x for x in lst if re.search(r"사업보고서", x.get("report_nm", ""))
               and not re.search(r"분기|반기", x.get("report_nm", ""))]
        biz.sort(key=lambda x: x.get("rcept_dt", ""), reverse=True)
        if not biz:
            rec["status"] = "no_annual_report"
        else:
            b = biz[0]
            rec.update(rcept_no=b["rcept_no"], report_nm=b.get("report_nm"), rcept_dt=b.get("rcept_dt"))
            st2, raw = get("document.xml", dict(crtfc_key=KEY, rcept_no=b["rcept_no"]), binary=True)
            rec["doc_http"] = st2
            if st2 != 200 or not isinstance(raw, (bytes, bytearray)):
                rec["status"] = "doc_http_%s" % st2
            else:
                try:
                    zf = zipfile.ZipFile(io.BytesIO(raw))
                    names = zf.namelist()
                    main = max(names, key=lambda n: zf.getinfo(n).file_size)
                    txt = decode_any(zf.read(main))
                    plain = strip_tags(txt)
                    rec["n_bytes_raw"] = len(raw)
                    rec["text_sales"] = extract(plain, ANCHOR_SALES)
                    rec["text_overview"] = extract(plain, ANCHOR_OVW, budget=8000, span=2000)
                    rec["status"] = "ok" if (rec["text_sales"] or rec["text_overview"]) else "no_section"
                except Exception as e:
                    rec["status"] = "zip_fail_%s" % type(e).__name__
    with open(fp, "w", encoding="utf-8") as f:
        json.dump(rec, f, ensure_ascii=False)
    with _lock:
        _done[0] += 1
        if _done[0] % 25 == 0:
            print("[pull] %d done" % _done[0], flush=True)
    time.sleep(0.15)
    return {"Ticker": tk, "status": rec.get("status")}


if __name__ == "__main__":
    import pandas as pd
    xw = pd.read_parquet(os.path.join(ROOT,
        "stage_artifacts/method_frontier/firm_level_scaffold/firm_crosswalk.parquet"))
    rows = xw[["Ticker", "corp_code", "corp_name"]].to_dict("records")
    print("[pull] targets=%d  window=%s~%s" % (len(rows), BGN, END), flush=True)
    with ThreadPoolExecutor(max_workers=4) as ex:
        res = list(ex.map(work, rows))
    from collections import Counter
    cnt = Counter(r["status"] for r in res)
    log = {"n": len(res), "status_counts": dict(cnt), "window": [BGN, END]}
    with open(os.path.join(FQ, "pull_dart_products_log.json"), "w", encoding="utf-8") as f:
        json.dump(log, f, ensure_ascii=False, indent=2)
    print("[pull] DONE", json.dumps(dict(cnt), ensure_ascii=False), flush=True)
