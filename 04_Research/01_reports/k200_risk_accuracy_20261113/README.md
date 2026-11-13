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
자료 판본: benchmark md5 `5056b678` · 최신일 2026-11-12 · 공통 예측일 3,386일 · IS 2,444일 / OOS 942일

### 2.1 판정 (사전등록 v1 규칙 그대로 · `output/verdict_v1.json`)
| 변형 | 가설 | OOS ΔLS/일 | DM t | 단측 p | Holm 문턱 | 관문 A · B · C | IS ΔLS/일 | 판정 |
|---|---|---|---|---|---|---|---|---|
| `DR_news` | H2 분포 회귀(같은 정보) | +0.0186 | 1.25 | 0.11 | 0.0250 | ○○○ | +0.0126 | 미달 |
| `DR_newsvk` | H1 분포 회귀 + V-KOSPI200 | +0.0663 | 3.98 | 3.5e-05 | 0.0167 | ○○○ | +0.0444 | **통과 · 채택 권고** |
| `QR_newsvk` | H3 P3 + 당일 수익 · V-KOSPI200 | +0.0208 | 1.19 | 0.12 | 0.0500 | ○×× | -0.0529 | 미달 |

### 2.2 점수표 (일 평균 · LS 높을수록 · 나머지 낮을수록 좋음 · `output/eval_final.json`)
| 모형 | IS LS | OOS LS | OOS CRPS | OOS 왼꼬리 CRPS | OOS FZ0 5% | OOS VaR 5% 위반 | OOS VaR 1% 위반 | OOS PIT χ² p |
|---|---|---|---|---|---|---|---|---|
| P3 | -1.3423 | -1.9044 | 1.0310 | 0.3257 | 1.4043 | 6.4% | 1.8% | 0.106 |
| GJR | -1.3276 | -1.8830 | 1.0299 | 0.3248 | 1.3439 | 6.3% | 1.4% | 0.000 |
| EWMA | -1.3286 | -1.8770 | 1.0304 | 0.3256 | 1.3547 | 5.2% | 1.3% | 0.099 |
| HS500 | — | — | 1.0670 | 0.3404 | 1.6271 | 7.5% | 2.5% | 0.000 |
| DR_news | -1.3297 | -1.8858 | 1.0365 | 0.3281 | 1.3488 | 5.7% | 1.6% | 0.013 |
| DR_newsvk | -1.2980 | -1.8381 | 1.0143 | 0.3201 | 1.2507 | 6.2% | 0.8% | 0.007 |
| QR_newsvk | -1.3952 | -1.8836 | 1.0265 | 0.3268 | 1.3548 | 6.7% | 2.0% | 0.000 |

- 강건성(H1): 상하위 1% 절사 평균 IS +0.0372 · OOS +0.0514 · 중앙값 +0.0417 · +0.0311 · 이긴 날 59% · 55% · 연도별 양수 14/14
- H3 실패 기전: 매일 분위 11점 → Hansen 재적합 골격에 특징을 더하자 경계 적합이 늘었다(λ 경계 3 → 24일 · ν 상한 91 → 679일 · ν 하한 312 → 376일). 최악 6일이 IS 손실의 72%.
- 읽는 법(사전등록 §H3): C2 통과 · C3 실패 = 이득의 원천에 분포 층(2단 Hansen 재적합 → 우도 추정)까지 포함된다. 같은 V-KOSPI 정보라도 P3 골격에서는 안정적으로 쓰이지 않는다.
- 운영 기록 대조: 운영 136행 중 재현과 같은 값 4행(2026-10-19 이후). 2026-07-31~2026-08-07 운영 브리핑 5회는 σ 20.9~44.5%(현재 자료 재현 4.8~7.0%)를 발송했다 — 입력 점검 장치 필요.
- 구현 수정(판정 무관): FZ0 는 ES < 0 에서만 정의 — 구판이 정의역 밖 1일(H3 · 2015-03-17 · σ 0.004% 붕괴 예측)을 −1e-9 로 눌러 −1천만이 나왔다. 결측 처리 후 재계산(OOS 영향 없음 · 판정 동일).
- 보고: 텔레그램 1통(2026-11-13 19시대 · 차트 5장 `charts/fig1~5` · 본문 `output/report_message.json`).

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
.venv_qvest_ml/Scripts/python.exe .../scripts/24_production_audit.py
.venv_qvest_ml/Scripts/python.exe .../scripts/40_report_charts.py --challengers DR_news,DR_newsvk,QR_newsvk --labels "H2 분포회귀(같은 정보),H1 분포회귀+V-KOSPI,H3 P3+V-KOSPI" --best DR_newsvk
.venv_qvest_ml/Scripts/python.exe .../scripts/41_report_message.py
Rscript --no-save .../scripts/50_tg_send.R          # 미리보기 · 'send' 인자로 발송
```
- 차트 PNG · 일별 예측/점수 parquet 은 저장소 .gitignore 대상이라 커밋에 없다 — 위 명령으로 다시 만든다(자료 판본 md5 를 먼저 대조).
