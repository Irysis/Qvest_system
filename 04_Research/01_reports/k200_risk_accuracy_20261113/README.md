# K200 일간 위험 브리핑 — 예측 정확도 개선 연구 (2026-11-13 · 1차)

- 지시: 도훈 11-13 "K200 일간 위험 브리핑 예측정확도 개선 연구 새 세션에서 시작해줘"
- 대상: 모닝 체인 [6/6] P3(v3-fast Hansen · LASSO 분위회귀 11분위 → Hansen 비대칭 t) — `04_Research/decision_framework/bearish_forecast_v3`
- 성격: 연구(운영 무변경). 운영 반영은 도훈 확인 뒤 스크래치 사본 → 시험 → 원자 교체.
- 정본 문서: 평가 규약 [prereg/PROTOCOL_v1.md](prereg/PROTOCOL_v1.md) · 가설 [prereg/PREREG_v1.md](prereg/PREREG_v1.md) · 기계 판독 [prereg/prereg_v1.json](prereg/prereg_v1.json)

## 1. 현행 모형 지도 (P3 · 운영)
| 항목 | 현행 | 근거(코드) |
|---|---|---|
| 표적 | 다음 거래일 KOSPI200 로그수익(%) `ret_fwd = log(C_{t+1}/C_t)·100` | `472_p1_patch_v2.py::load_data` |
| 지평 | 1거래일(브리핑 '적용 대상: 다음 1 거래일') | `600_morning_brief.py` |
| 하락 사건 | 표시만: P(≤−5%) · P(≤−7%) · P(≤−10%) = 예측 분포 CDF | `p3_hansen_skewt_bounded.py::derive_metrics_per_obs` |
| 입력(12) | r(t−1) · r(t−2) · r(t−5) · r(t−22) · 실현 표준편차 5 · 22 · 60일 · 평균수익 5 · 22 · 60일 · rv22 확장 z · 낙폭 확장 z — **전부 벤치마크 종가 1개 계열** | `load_data` |
| 입력 PIT | 모두 t 종가까지(롤링 · 확장 창) — 위반 없음. 단 `log_ret_lag_1` = r(t−1)(shift 1) → **당일 수익 r(t) 미사용** | `load_data` |
| 학습 창 | [t − 21일 − 12년, t − 21일](달력일) · 하한 1,008행 | `601_daily_inference.py` |
| 재적합 | 매일(07:10 체인에서 그날 1회) | `morning_briefing.sh [6a]` |
| 모형 | sklearn `QuantileRegressor`(L1 α 6.68e-4 · 표준화 · HiGHS) × 11분위 → 정렬(교차 수리) → 그날 11점에 Hansen 비대칭 t 를 CDF 최소제곱 적합(ν ∈ (2.5, 50) · λ ∈ (−0.98, 0.98)) | `a1_lasso_quantile.py` · `p3_hansen_skewt_bounded.py` |
| 하이퍼파라미터 | α · 창 = 2026-05 Optuna(TPE) — 워크포워드 CRPS 최소 + Kupiec 벌점 · 탐색 표본이 2026-05 까지 | `481_p2_optuna_bayesian.py` |
| 보정 | 없음(사후 재보정 · 등각 보정 미적용) | — |
| ES | 400점 **무작위** MC(시드 없음 — 재실행마다 값이 흔들림) | `derive_metrics_per_obs` |
| 사람에게 보이는 수치 | σ · λ · ν · μ(+상태 문구) · VaR 5/1/0.5% · ES 5% · P(≤−5/−7/−10%) · 직전 예측 검증(VaR 위반 · PIT) · 22일 추세 · 경보(σ > 2.8 · λ < −0.3 · P(−10%) > 1% 등) · 종합 위험 등급 · 9분면 대시보드 | `600_morning_brief.py` · `613_p3_9quad_riskpro.R` |

## 2. 결과
<!-- RESULTS -->

## 3. 재현
```
.venv_qvest_ml/Scripts/python.exe 04_Research/01_reports/k200_risk_accuracy_20261113/scripts/10_p3_replica_walkforward.py --workers 6
.venv_qvest_ml/Scripts/python.exe .../scripts/11_reference_models.py
.venv_qvest_ml/Scripts/python.exe .../scripts/12_score_p3.py
.venv_qvest_ml/Scripts/python.exe .../scripts/31_challenger_dr.py --name DR_news --feats lrv5,lrv22,lrv60,ddz,r0,absr0
.venv_qvest_ml/Scripts/python.exe .../scripts/31_challenger_dr.py --name DR_newsvk --feats lrv5,lrv22,lrv60,ddz,r0,absr0,lvk
.venv_qvest_ml/Scripts/python.exe .../scripts/30_challenger_qr.py --name QR_newsvk --extra r0,absr0,lvk --workers 6
.venv_qvest_ml/Scripts/python.exe .../scripts/20_evaluate.py --models P3,GJR,EWMA,HS500,DR_news,DR_newsvk,QR_newsvk --segments IS,OOS,ALL --tag final
.venv_qvest_ml/Scripts/python.exe .../scripts/22_crisis_events.py --models P3,DR_news,DR_newsvk,QR_newsvk,GJR --max_outcome 2099-12-31 --tag final
.venv_qvest_ml/Scripts/python.exe .../scripts/23_verdict.py
.venv_qvest_ml/Scripts/python.exe .../scripts/40_report_charts.py --challengers DR_news,DR_newsvk,QR_newsvk --best <권고>
```
