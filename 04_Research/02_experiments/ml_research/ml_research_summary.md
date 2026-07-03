# ML Research Summary — Session 57
# 최종 업데이트: 2026-04-09

## 1. 실행 파일 목록

| 파일 | 용도 | 상태 |
|------|------|------|
| `04_Research/ml_xgboost_pilot.R` | XGBoost Walk-Forward (월말, 300팩터) | 완료 |
| `04_Research/ml_elastic_net_selection.R` | ElasticNet 팩터 선별 (FM-style) | 완료 (step6 오류) |
| `04_Research/ml_linear_baseline.R` | Ridge 일간 학습 (L-123 준수) | 오버나잇 통합 |
| `04_Research/ml_overnight_research.R` | 4모델 통합 오버나잇 | 실행 중 |
| `04_Research/ml_logistic_research.R` | Logistic Regression 별도 | 실행 중 |

## 2. 산출물 디렉토리

### `04_Research/ml_xgboost_pilot_output/`
- `performance.json` — CAGR 23.71%, SR 0.923, MDD -57.24%, IC 0.0669, ICIR 0.7206
- `oos_ic_monthly.csv` — 209개월 OOS IC (월별)
- `feature_importance_avg.csv` — 295개 팩터 gain 순위
- `feature_importance_yearly.csv` — 연도별 gain
- `monthly_portfolio_scores.csv` — 월별 Top30 종목 + ml_score
- `nav.csv` — 일간 NAV (Strategy_Ret 컬럼)
- `xgb_model_2008.rds ~ xgb_model_2025.rds` — 18개 연도별 모델
- `val_metrics_by_year.csv` — Validation IC by OOS year (미생성, 원본에서 추출 가능)

### `04_Research/ml_elastic_net_output/`
- `factor_selection_frequency.csv` — 300팩터 선택 빈도 (15%+ = 87개 Core)
- `run_log.txt` — Phase 1 완료, Phase 2 완료, step 6 stability selection 오류

### `04_Research/ml_overnight_output/` (실행 중)
- `run_log.txt` — 4모델 진행 로그
- `ic_all_models.csv` — 모든 모델 월별 OOS IC (완료 시)
- `ic_summary.csv` — 모델별 IC/ICIR 요약 (완료 시)
- `ridge_nav.csv / enet_nav.csv / xgb_nav.csv / rf_nav.csv` — 모델별 NAV
- `ensemble_nav.csv` — 상위2 앙상블 NAV
- `*_tail_risk.json` — 모델별 tail risk (EVT/CF/CDaR)
- `final_comparison.json / .csv` — 최종 비교표
- `prefilter_log.csv` — 연도별 IC prefilter 선택 팩터

### `04_Research/ml_logistic_output/` (실행 중)
- `run_log.txt` — Logistic 진행 로그
- `logit_oos_ic_monthly.csv` — 월별 OOS IC
- `logit_nav.csv` — NAV
- `result.json` — IC/ICIR 요약

### `04_Research/ml_linear_baseline_output/` (이전 실행 결과)
- `run_log.txt` — Ridge 단독 실행 결과 (부분 완료)

## 3. XGBoost Pilot 결과 (확정)

| 지표 | 값 |
|------|-----|
| OOS IC (월평균) | 0.0669 |
| OOS ICIR | 0.7206 |
| CAGR | 23.71% |
| Sharpe | 0.923 |
| MDD | -57.24% (Hard Fail) |
| WinRate | 54.3% |
| OOS 기간 | 2008-02 ~ 2026-04 |
| Harvey t-stat | 10.42 |

### Val IC by Year
| Year | Val IC | Year | Val IC |
|------|--------|------|--------|
| 2008 | 0.029 | 2017 | 0.167 |
| 2009 | 0.231 | 2018 | -0.003 |
| 2010 | 0.127 | 2019 | 0.074 |
| 2011 | 0.028 | 2020 | 0.232 |
| 2012 | 0.063 | 2021 | 0.017 |
| 2013 | 0.074 | 2022 | 0.111 |
| 2014 | 0.085 | 2023 | 0.005 |
| 2015 | 0.096 | 2024 | 0.025 |
| 2016 | 0.044 | 2025 | 0.022 |

### Feature Importance Top 20
| Rank | Factor | Gain% | Family |
|------|--------|-------|--------|
| 1 | RE02_Vol_Regime_Pctile | 11.59 | regime |
| 2 | RE03_Mkt_Drawdown | 7.25 | regime |
| 3 | M31_Breadth_Mom | 6.39 | momentum |
| 4 | V20_SP | 5.50 | value |
| 5 | R14_DUVOL | 2.38 | risk |
| 6 | T04_OBV21 | 2.13 | technical |
| 7 | R17_Market_Leverage | 1.97 | risk |
| 8 | V07_EV_EBITDA | 1.66 | value |
| 9 | RE08_Down_Market_Excess | 1.63 | regime |
| 10 | L13_Vol_Variance_Ratio | 1.59 | liquidity |
| 11 | L18_Eff_Spread_Proxy | 1.44 | liquidity |
| 12 | Q30_Receivables_Turnover | 1.28 | quality |
| 13 | RE09_Capture_Ratio | 1.27 | regime |
| 14 | M22_Max_Return | 1.16 | momentum |
| 15 | L37_Relative_Vol | 1.11 | liquidity |
| 16 | D35_RealVol_63d | 1.08 | defense |
| 17 | T13_Gap | 1.06 | technical |
| 18 | V16_Tobins_Q | 1.05 | value |
| 19 | D58_Vol_Asymmetry | 1.00 | defense |
| 20 | D14_Beta_Change | 1.00 | defense |

### Family 집중도
| Family | Gain% | Top Factors |
|--------|-------|-------------|
| Regime | 22.7% | RE02, RE03, RE08, RE09 |
| Momentum/Tech | 14.9% | M31, T04, M22, T13, M21 |
| Value | 8.2% | V20, V07, V16 |
| Risk/Defense | 7.3% | R14, R17, D35, D58, D14 |
| Liquidity | 5.9% | L13, L18, L37, L26 |
| Quality | 2.3% | Q30, Q16 |
| Consensus | 0.99% | (STR_1631과 overlap 극미) |

## 4. Elastic Net 팩터 선별 결과

- 총 300팩터 중 87개가 15%+ 선택 빈도 (Core Set)
- 선택 패턴: 위기기(GFC/COVID) 60-90개, 평시 0-30개 (월별 변동 극심)
- XGBoost Feature Importance와 교차 확인된 공통 팩터: RE02, L37, V16, RE08, T13

## 5. S0 Debate 결과 (REVISE 55/100)

| 패널 | 점수 | 핵심 지적 |
|------|------|----------|
| Quant | 14/25 | 위기IC 음전환(-0.151 COVID), ICIR decay |
| Academic | 17/25 | 한국 ML 실증 부재, Chen et al. 인용 오류 |
| Gov-proxy | 15/25 | Family 5/5, MDD 0/5 (Hard Fail) |
| Codex Critic | 9/25 | L-123 MI prefilter 미적용, PIT 우려 |

### REVISE 반영 현황
| 지적 | 상태 |
|------|------|
| MI prefilter 309->50 | 오버나잇에서 적용 중 |
| 일간 DB 학습 | 오버나잇에서 적용 중 |
| 위기 IC 분석 | 결과 대기 |
| Chen et al. 인용 수정 | 가설 재작성 시 반영 |
| 30종목 score blending | 설계 필요 |
| Alpha decay 모니터링 | 결과 대기 |

## 6. 인프라 변경 (Session 57)

| 항목 | 내용 |
|------|------|
| hurdle_gate D084-D086 | Tail Risk / Stress Severity / Risk Coherence 배선 완료 |
| OPT-7 ML Guard Hook | forge_code_guard.sh에 MC-P1~P3 자동 차단 추가 |
| AX-001 | L-112 "Defense 조건부 평가" → AXIOM 승격 |
| axiom_core.json | v1.0 -> v1.1 (AX-001 추가) |
| ml_factor_model.md | 기존 스킬 (v1.0) — L-123 규칙 정본 |

## 7. 오버나잇 리서치 진행 (실행 중)

### 4모델 통합 (PID 2311452)
- Ridge (alpha=0) + ElasticNet (alpha=0.5) + XGBoost + RandomForest
- 2008 진행: R:0.160, E:0.155, X:0.147
- 완료 후: 앙상블 + tail_risk_suite + 앵커 상관

### Logistic 별도 (PID 2313350)
- 200K 서브샘플 + top50 + binomial
- 시작됨

## 8. 다음 단계 (리서치 완료 후)

1. 최고 모델 ICIR 확인 -> Alpha Lab Gate (0.20)
2. 앵커 상관 < 0.30 확인 -> Diversifier 적합성
3. tail_risk_suite 결과 확인 -> D084/D085/D086
4. S0 REVISE 재제출 (MI prefilter + 일간 학습 반영)
5. APPROVE 시 STR 번호 할당 -> S1 구현
