#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
probe_export_ratio.py — FQ-073 타당성의 핵심 변수인 '수출 비중'이 사업보고서에서
추출 가능한지 실측한다.

왜 중요한가: crosswalk는 "이 회사가 HS85 재화를 만든다"까지만 말한다. 관세청 HS 통계가
그 회사 실적의 선행지표가 되려면 (a) 수출 비중이 유의미하고 (b) **한국에서 선적**되어야
한다. 해외 현지생산분은 한국 관세청 통계에 아예 안 잡히므로 (b)가 깨지면 신호가 죽는다.
"""
import os, re, json, glob, unicodedata
import pandas as pd

FQ = os.path.dirname(os.path.abspath(__file__))
TOC = re.compile(r"-{3,}")
PAT_EXPORT_KW = re.compile(r"(수출|해외\s*매출|해외\s*법인|국내\s*및\s*해외|내수)")
PAT_EXPORT_PCT = re.compile(r"수출[^.]{0,40}?(\d{1,3}(?:\.\d)?)\s*%")
PAT_OVERSEAS_PLANT = re.compile(r"(해외\s*(생산|공장|법인|사업장)|현지\s*생산|중국\s*공장|"
                                r"베트남\s*(공장|법인)|미국\s*공장|인도\s*공장|멕시코\s*공장|헝가리\s*공장|폴란드\s*공장)")


def clean(rec):
    parts = []
    for f in ("text_sales", "text_overview"):
        for seg in (rec.get(f) or "").split(" ||| "):
            if len(TOC.findall(seg)) >= 3:
                continue
            parts.append(seg)
    return unicodedata.normalize("NFKC", " ".join(parts))


df = pd.read_parquet(os.path.join(FQ, "firm_hs_crosswalk.parquet"))
mapped = set(df.loc[df.hs4.notna(), "Ticker"])

rows = []
for fp in glob.glob(os.path.join(FQ, "dart_products", "*.json")):
    rec = json.load(open(fp, encoding="utf-8"))
    tk = rec.get("Ticker")
    t = clean(rec)
    pcts = [float(x) for x in PAT_EXPORT_PCT.findall(t)]
    rows.append({"Ticker": tk, "mapped": tk in mapped,
                 "has_export_kw": bool(PAT_EXPORT_KW.search(t)),
                 "n_export_pct": len(pcts),
                 "export_pct_first": (pcts[0] if pcts else None),
                 "has_overseas_plant": bool(PAT_OVERSEAS_PLANT.search(t))})
r = pd.DataFrame(rows)
m = r[r.mapped]
out = {
    "_meta": "DART 사업보고서 발췌 텍스트 기준. 정규식 추출이라 상한 추정치(오탐 포함 가능).",
    "n_mapped_firms": int(len(m)),
    "export_keyword_present": {"n": int(m.has_export_kw.sum()),
                               "pct": round(100 * m.has_export_kw.mean(), 1)},
    "explicit_export_pct_extracted": {
        "n": int((m.n_export_pct > 0).sum()),
        "pct": round(100 * (m.n_export_pct > 0).mean(), 1),
        "median_first_value": (float(m.loc[m.n_export_pct > 0, "export_pct_first"].median())
                               if (m.n_export_pct > 0).any() else None),
        "verdict": "수출 비중은 표준 필드가 아니라 서술문 안에 흩어져 있다 → 정규식 상한이 이 정도이며 "
                   "신뢰 가능한 firm-level 수출비중 패널은 본 라운드에서 확보하지 못했다."},
    "overseas_production_mentioned": {
        "n": int(m.has_overseas_plant.sum()),
        "pct": round(100 * m.has_overseas_plant.mean(), 1),
        "why_it_matters": "해외 현지생산분은 한국 관세청 수출입 통계에 잡히지 않는다. 이 비율이 높을수록 "
                          "HS 통계와 해당 기업 실적의 연결이 약해진다 = FQ-073 최대 타당성 위협."},
}
json.dump(out, open(os.path.join(FQ, "export_exposure_probe.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
r.to_csv(os.path.join(FQ, "export_exposure_by_firm.csv"), index=False, encoding="utf-8-sig")
print(json.dumps(out, ensure_ascii=False, indent=2))
