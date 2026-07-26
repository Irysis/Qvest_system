#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
finalize_fq073.py — (1) 수작업 spot-check 정확도를 커버리지에 합산
                    (2) HS -> 종목 집계 테이블(hs_to_firms) 생성 = FQ-073 소비면 입력
                    (3) 관세청 API 조회용 HS 목록(hs_query_list) 산출
"""
import os, json
import pandas as pd

FQ = os.path.dirname(os.path.abspath(__file__))
df = pd.read_parquet(os.path.join(FQ, "firm_hs_crosswalk.parquet"))
cov = json.load(open(os.path.join(FQ, "hs_coverage.json"), encoding="utf-8"))
sp = json.load(open(os.path.join(FQ, "spotcheck_manual.json"), encoding="utf-8"))

# ── (1) spot-check 집계 ───────────────────────────────────────────────────
v = [r["verdict"] for r in sp["sample"]]
n = len(v)
hs4_ok = v.count("OK")
chap_ok = n - v.count("WRONG_CHAP")
cov["accuracy_spotcheck"] = {
    "method": sp["_meta"]["sample_spec"],
    "n_reviewed": n,
    "verdict_counts": {k: v.count(k) for k in
                       ("OK", "CHAP_OK_HS4_ARG", "WRONG_HS4", "WRONG_CHAP")},
    "hs4_exact_accuracy_pct": round(100 * hs4_ok / n, 1),
    "hs_chapter_accuracy_pct": round(100 * chap_ok / n, 1),
    "conclusion": ("HS 章(2자리)이 신뢰 단위(%.1f%%)이고 HS4는 보조(%.1f%%). "
                   "다제품 기업의 단일 HS4는 원리상 부정확하므로 소비 시 章 단위 사용 권장, "
                   "HS4는 multi_hs=False 인 건에 한해 사용."
                   % (100 * chap_ok / n, 100 * hs4_ok / n)),
    "observed_error_modes": [
        "전방산업 오인: 소재 기업이 자기 제품의 '용도'(SSD·선박·전지)를 서술해 완제품 HS로 끌림 "
        "(네오셈→8471, 리튬포어스→8507, 한국카본→8901)",
        "형제 heading 오선택: 章은 맞으나 다부문 중 2위 부문이 argmax (삼성전기 8534 vs MLCC 8532, "
        "LG이노텍 8534 vs 카메라모듈 8529, 케이엠더블유 8541 vs 안테나 8517)",
        "근거 희박: text_chapter_score<20 구간에서 오배정 집중(덕산테코피아 8점)"
    ],
    "reviewer": "본 세션(모델) 자기평가 — 독립 검수 아님. 도훈 검수 전까지 자기평가로 취급",
}
# 근거 강도별 분포(오류가 어디 몰리는지 소비자가 직접 필터링할 수 있도록)
b = [0, 20, 50, 100, 10 ** 9]
lab = ["<20(취약)", "20-50", "50-100", ">=100(강)"]
mm = df.hs4.notna()
cov["evidence_strength_distribution"] = (
    df[mm].groupby(pd.cut(df.loc[mm, "text_chapter_score"], b, labels=lab, right=False),
                   observed=True).agg(
        n=("Ticker", "size"),
        mktcap_pct=("mktcap_krw_mn", lambda s: round(
            100 * s.fillna(0).sum() / df["mktcap_krw_mn"].fillna(0).sum(), 2))
    ).to_dict("index"))

# ── (2) HS -> 종목 집계 (소비면 입력) ─────────────────────────────────────
m = df.hs4.notna()
tot_cap = df.loc[m, "mktcap_krw_mn"].fillna(0).sum()
g4 = (df[m].groupby(["hs4", "hs4_desc"])
      .agg(n_firms=("Ticker", "size"),
           mktcap_krw_mn=("mktcap_krw_mn", lambda s: float(s.fillna(0).sum())),
           n_grade_A=("confidence", lambda s: int((s == "A").sum())),
           n_multi_hs=("multi_hs", lambda s: int(s.sum())),
           tickers=("Ticker", lambda s: ",".join(sorted(s))))
      .reset_index())
g4["mktcap_share_of_mapped_pct"] = (100 * g4.mktcap_krw_mn / tot_cap).round(3)
g4 = g4.sort_values("mktcap_krw_mn", ascending=False)
g4.to_csv(os.path.join(FQ, "hs4_to_firms.csv"), index=False, encoding="utf-8-sig")
g4.to_parquet(os.path.join(FQ, "hs4_to_firms.parquet"), index=False)

g2 = (df[m].groupby(df.hs4.str[:2])
      .agg(n_firms=("Ticker", "size"),
           mktcap_krw_mn=("mktcap_krw_mn", lambda s: float(s.fillna(0).sum())),
           n_grade_A=("confidence", lambda s: int((s == "A").sum())),
           tickers=("Ticker", lambda s: ",".join(sorted(s))))
      .reset_index().rename(columns={"hs4": "hs_chapter"}))
g2["mktcap_share_of_mapped_pct"] = (100 * g2.mktcap_krw_mn / tot_cap).round(3)
g2 = g2.sort_values("mktcap_krw_mn", ascending=False)
g2.to_csv(os.path.join(FQ, "hs_chapter_to_firms.csv"), index=False, encoding="utf-8-sig")
g2.to_parquet(os.path.join(FQ, "hs_chapter_to_firms.parquet"), index=False)

# ── (3) 관세청 API 조회 목록 (승인 후 즉시 사용) ──────────────────────────
q = {
    "_meta": {
        "use": "관세청 15101609 getItemtradeList 의 hsSgn 파라미터 입력 목록. "
               "章(2자리) 우선 — spot-check상 章이 신뢰 단위. HS4는 보조 조회.",
        "api_status": "★2026-07-25 현재 HTTP 403(활용신청 미승인) — 도훈 승인 후 사용 가능",
        "call_budget_note": "조회 윈도우 1년/호출, 페이지네이션 없음. 章 단위 %d개 x 연도 수 = 호출수" % len(g2),
    },
    "chapters": g2[["hs_chapter", "n_firms", "mktcap_share_of_mapped_pct"]].to_dict("records"),
    "hs4_secondary": g4[g4.n_multi_hs == 0][
        ["hs4", "hs4_desc", "n_firms", "mktcap_share_of_mapped_pct"]].head(40).to_dict("records"),
}
json.dump(q, open(os.path.join(FQ, "hs_query_list.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)

json.dump(cov, open(os.path.join(FQ, "hs_coverage.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2, default=str)

print(json.dumps(cov["accuracy_spotcheck"], ensure_ascii=False, indent=2))
print("\n[evidence strength]", json.dumps(cov["evidence_strength_distribution"], ensure_ascii=False))
print("\n[HS 章 상위 12]")
print(g2.head(12)[["hs_chapter", "n_firms", "n_grade_A", "mktcap_share_of_mapped_pct"]].to_string(index=False))
print("\n[saved] hs4_to_firms.{csv,parquet} · hs_chapter_to_firms.{csv,parquet} · hs_query_list.json")
