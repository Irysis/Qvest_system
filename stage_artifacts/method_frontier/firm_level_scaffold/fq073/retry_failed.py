#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""retry_failed.py — pull 실패 6건 개별 재시도 + 실패 원인 실측(본문 확인)."""
import os, io, re, json, zipfile, time, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pull_dart_products import get, KEY, DOUT, FQ, strip_tags, decode_any, extract, ANCHOR_SALES, ANCHOR_OVW

TARGETS = ["A000120", "A010060", "A086280", "A091990", "A121600", "A316140"]
out = []
for tk in TARGETS:
    fp = os.path.join(DOUT, "%s.json" % tk)
    j = json.load(open(fp, encoding="utf-8"))
    cc, nm = j["corp_code"], j["corp_name"]
    # 1) 사업보고서 목록 재조회 — 창을 넓힌다(2023~)
    st, body = get("list.json", dict(crtfc_key=KEY, corp_code=cc, bgn_de="20230101",
                                     end_de="20251231", pblntf_ty="A", page_count="100"))
    lst = (json.loads(body).get("list") or []) if st == 200 else []
    biz = [x for x in lst if re.search(r"사업보고서", x.get("report_nm", ""))
           and not re.search(r"분기|반기", x.get("report_nm", ""))]
    biz.sort(key=lambda x: x.get("rcept_dt", ""), reverse=True)
    if not biz:
        out.append({"Ticker": tk, "corp_name": nm, "result": "no_annual_report_even_2023+",
                    "list_http": st, "report_nms": [x.get("report_nm") for x in lst[:8]]})
        continue
    ok = False
    for cand in biz[:2]:
        st2, raw = get("document.xml", dict(crtfc_key=KEY, rcept_no=cand["rcept_no"]),
                       binary=True, timeout=300)
        head = bytes(raw[:200]) if isinstance(raw, (bytes, bytearray)) else b""
        try:
            zf = zipfile.ZipFile(io.BytesIO(raw))
            main = max(zf.namelist(), key=lambda n: zf.getinfo(n).file_size)
            plain = strip_tags(decode_any(zf.read(main)))
            j.update(rcept_no=cand["rcept_no"], report_nm=cand.get("report_nm"),
                     rcept_dt=cand.get("rcept_dt"), n_bytes_raw=len(raw),
                     text_sales=extract(plain, ANCHOR_SALES),
                     text_overview=extract(plain, ANCHOR_OVW, budget=8000, span=2000),
                     status="ok_retry")
            json.dump(j, open(fp, "w", encoding="utf-8"), ensure_ascii=False)
            out.append({"Ticker": tk, "corp_name": nm, "result": "ok_retry",
                        "rcept_no": cand["rcept_no"], "bytes": len(raw),
                        "sales_len": len(j["text_sales"])})
            ok = True
            break
        except Exception as e:
            out.append({"Ticker": tk, "corp_name": nm, "result": "fail_%s" % type(e).__name__,
                        "rcept_no": cand["rcept_no"], "http": st2,
                        "bytes": len(raw) if isinstance(raw, (bytes, bytearray)) else -1,
                        "head": head.decode("utf-8", "replace")[:180]})
        time.sleep(1)
    time.sleep(0.5)

print(json.dumps(out, ensure_ascii=False, indent=2))
json.dump(out, open(os.path.join(FQ, "retry_failed.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
