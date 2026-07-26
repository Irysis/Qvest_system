#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
add_interop_columns.py — 병행 세션 러너(`PIT_plan_fq073.md` §4-c-2)와의 접속 컬럼 추가.

병행 세션이 본 crosswalk를 감사해 '자본 게이트 부적격'으로 판정했고 그 지적은 타당하다.
여기서는 지적 3건 중 **오해 불가능한 형태로** 대응한다:

  1) vintage 차원 부재 → `effective_from`(해당 사업보고서 접수일) + `map_vintage_mode`
     + `gate_eligible=False` 를 **데이터 자체에 박아** 정적 맵이 게이트로 새는 길을 막는다.
     (연도별 다행 전개는 미실행 — 연도별 재pull 필요. MAPPING_RATIONALE §10-1)
  2) 컬럼명 불일치 → `hs_code` (= hs4) 별칭 추가.
  3) weight 부재 → `weight_heuristic` 추가. ★단 이것은 **매출 비중이 아니라 키워드 점유율**이며
     `weight_method` 컬럼에 그 사실을 행마다 기록한다. 매출-가중이 필요하면 §6대로 별도 파서 필요.
     (명시 매출비중 표는 474사 중 11사만 합계검증 통과 → 가중 산출에 쓸 수 없다)
"""
import os, json
import pandas as pd

FQ = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(FQ, "firm_hs_crosswalk.parquet")
df = pd.read_parquet(p)

# 1) vintage / 게이트 적격성 — 데이터에 박아 오용 차단
df["effective_from"] = pd.to_datetime(df["dart_rcept_dt"], format="%Y%m%d", errors="coerce")
df["map_vintage_mode"] = "static_current"
df["gate_eligible"] = False
df["gate_ineligible_reason"] = (
    "ticker당 1행 정적 현재-믹스. 최신 사업보고서 1 vintage로 과거 기간을 귀속하면 "
    "사업구성 look-ahead(C1/C3). 연도별 vintage 다행 전개 전까지 진단 상한.")

# 2) 컬럼 별칭
df["hs_code"] = df["hs4"]

# 3) weight — 키워드 점유율 기반(매출 아님), primary/secondary 정규화
prim = df["hs4_score_share"].fillna(0.0)
has_sec = df["hs4_secondary"].notna()
w_prim = prim.where(prim > 0, 1.0)
df["weight_heuristic"] = 1.0
df.loc[df["hs4"].isna(), "weight_heuristic"] = pd.NA
# secondary가 있으면 primary/secondary를 점수비로 분배 (합=1)
den = (df["text_top_hs4_score"].fillna(0) + df["text_runnerup_score"].fillna(0)).replace(0, pd.NA)
share_p = (df["text_top_hs4_score"] / den).clip(0.5, 0.95)
df.loc[has_sec & df["hs4"].notna(), "weight_heuristic"] = share_p[has_sec & df["hs4"].notna()]
df["weight_secondary_heuristic"] = pd.NA
df.loc[has_sec & df["hs4"].notna(), "weight_secondary_heuristic"] = (
    1.0 - df.loc[has_sec & df["hs4"].notna(), "weight_heuristic"])
df["weight_method"] = pd.NA
df.loc[df["hs4"].notna(), "weight_method"] = "keyword_score_share_NOT_revenue"

# 4) 소비 필터 힌트
df["consume_ok_chapter"] = df["confidence"].isin(["A", "B"])
df["consume_ok_hs4"] = df["confidence"].isin(["A", "B"]) & (~df["multi_hs"].astype(bool))

df.to_parquet(p, index=False)
df.to_csv(os.path.join(FQ, "firm_hs_crosswalk.csv"), index=False, encoding="utf-8-sig")

cov = json.load(open(os.path.join(FQ, "hs_coverage.json"), encoding="utf-8"))
cov["interop_contract"] = {
    "for": "병행 세션 러너 (PIT_plan_fq073.md §4-c-2)",
    "gate_eligible": False,
    "map_vintage_mode": "static_current",
    "reason": df["gate_ineligible_reason"].iloc[0],
    "effective_from_range": [str(df.effective_from.min().date()), str(df.effective_from.max().date())],
    "aliases": {"hs_code": "hs4", "weight_heuristic": "primary HS 비중(키워드 점유율)",
                "weight_secondary_heuristic": "secondary HS 비중"},
    "weight_warning": "weight_heuristic 은 매출 비중이 아니다(키워드 점유율). 명시 매출비중 표는 "
                      "합계검증 통과가 474사 중 11사뿐이라 가중 산출에 쓸 수 없었다.",
    "consume_filters": {
        "consume_ok_chapter": int(df.consume_ok_chapter.sum()),
        "consume_ok_hs4": int(df.consume_ok_hs4.sum()),
        "note": "章 소비는 confidence A/B, HS4 소비는 추가로 multi_hs=False 만. "
                "spot-check 정확도가 章 95.0% vs HS4 70.0% 이므로 기본 소비 단위는 章."},
    "note_on_sibling_audit": "병행 세션 감사표의 등급 분포(A 290/B 116/X 53)는 v1 빌드 수치다. "
                             "그 후 경계가드·비교역사전·章우선집계·근거하한 수리로 재빌드되어 "
                             "현행은 A 262 / B 53 / C 1 / T 15 / X 143 이다.",
}
json.dump(cov, open(os.path.join(FQ, "hs_coverage.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2, default=str)

print("[interop] cols=%d  gate_eligible=False  consume_ok_chapter=%d  consume_ok_hs4=%d"
      % (len(df.columns), df.consume_ok_chapter.sum(), df.consume_ok_hs4.sum()))
print("[interop] effective_from:", df.effective_from.min().date(), "~", df.effective_from.max().date())
