# 퇴역한 구 FF5 트래커 산출 — 2026-11-24 07:19 판에서 멈춤

구 `02_Infrastructure/reports/ff5_kr_tracker.R` 의 산출이다. 도훈 11-24 '퇴역'(스타일 국면 브리핑 v4.2)으로 더는 갱신되지 않는다.
CMA 부호 반전 · 월말 종가 비율 수익(가격 이음매) · 판 개정 결함이 있어 수치를 인용하지 않는다(검토 `04_Research/01_reports/style_regime_brief_review_20261124/README.md`).

FF5 월간 · 일간 수치 = 한국 FF 요인 정본 `.cache/kr_factor_returns_v2.parquet` · `.cache/kr_factor_returns_daily.parquet`
(`02_Infrastructure/data/build_kr_factor_returns.R` · 밤 갱신 [5c]). 퇴역 사유 · 되살리기 = `99_Archive/retired_ff5_kr_tracker_20261124/README.md`.
