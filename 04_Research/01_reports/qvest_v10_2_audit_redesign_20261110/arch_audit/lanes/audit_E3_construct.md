# 레인 E3 — 구성 엔진(요인 위험모형 Σ 공급자 · CDaR 낙폭 목적 구성) (2026-11-10)

범위: 비중 카탈로그 현황 재도출 · CDaR_LP 시간 초과 원인 특정 · 새 모듈 2개 + 어댑터 2개 + 시험 3개 · 카탈로그 등록 절차 · 사전등록 문장 제안.
실제 측정(러너) · 운영 등록부 쓰기 · 셀 엔진 수정은 하지 않았다. 합성 자료 시험과 소요 시간 실측까지.

## 1. 현황 재도출 (코드로 확인)

### 1-1. 살아 있는 Σ 는 어디서 오나
- 셀 엔진 catalog 분기 `rf_cell_engine.R:554`(E2 수정 중 판 기준 · 감사 메모의 `weight_catalog.R:637` 은 probe 용 합성 fixture `.wc_fixture` 다 — 살아 있는 경로가 아니다):
  `ctx <- list(assets, R = 창 252일(.wt$lookback_days 기본), mu = 엔진 점수, Sigma = stats::cov(R), ub = 1, ...)` → 산출 비중을 `w / sum(w)`(:558)로 다시 맞춘다.
- `ctx$Sigma` 를 실제로 읽는 arm: qepm 레지스트리(MVO · MVO_grid · HRP · ERC · MaxDiv · PPO_RL · Genetic · DPL — `requires = cov`) + 논문 어댑터 5종(conformal_kelly · erc · hrp · michaud · nco). **lean 빌트인 20종은 ctx$Sigma 도 ctx$lookback_days 도 읽지 않는다** — 캐리어(`weight_catalog.R:245-246`)가 `max_w` 만 넘기므로 각 함수 기본 창(ivol 60일 · 나머지 120일)으로 다시 자르고, cov_hook 이 있는 hrp 등도 cov_method 기본값(표본)으로 돈다. qepm 번역층은 창 전체를 넘긴다(`weight_method_registry.R:214-215`).

### 1-2. 비중 카탈로그 입력 표 (58종 · `06_Registry/weight_catalog.json` 실측 분포: lean active 20 · degraded 3 · qepm active 11 · blocked 3 · paper active 10 · blocked 2 · gen active 4 · unverified 5)

| 계열 | 기대수익 | 공분산 추정기 | 창 | 비용 항 |
|---|---|---|---|---|
| lean 위험 기반(ivol · hrp · minvar · riskparity · nco · factor_rp · maxdiv · resampled · robust_mv · kelly · higher_moment) | 없음 | 함수 내부 표본(cov_method 미전달) | 기본값 60(ivol) · 120 — **셀의 lookback 252 무시** | 없음 |
| lean 점수 혼합(score_tilt · rank/softmax/winsor_tilt · nco_score_tilt · entropy) | ctx$mu(점수) | 내부 표본 | 120 | 없음 |
| lean 꼬리(cvar · omega) | 없음 | 시나리오(과거 수익) | 120 | 없음 |
| qepm MVO · MVO_grid | ctx$mu | **ctx$Sigma = 표본(창 252)** | 252 | turnover_penalty 배선은 있으나(`mean_variance_optimizer.R:236`) 캐리어가 current_weights 를 안 넘김 → 사실상 없음 |
| qepm HRP · ERC · MaxDiv | 없음 | ctx$Sigma(표본) | 252 | 없음 |
| qepm CVaR_LP · CDaR_LP · Protection_ES | 없음 | 시나리오(창 252) | 252 | 없음 |
| 논문 어댑터(erc · hrp · nco · michaud · conformal_kelly) | 일부 ctx$mu | ctx$Sigma(표본) | 252 | 없음 |
| 논문 어댑터(cvar_lp_ru2000 · eigen_clean · schur 등) | 없음 | ctx$R 에서 자체(고유값 정리 등) | 252 | 없음 |
| gen(`qepm_MVO__shr_*`) | ctx$mu | 수축 변형(lw_nls 만 active) | 252 | 없음 |

판독: 요인 구조 Σ · 위기 조건부 Σ · 비용 항은 카탈로그 어디에도 없다. 구성 처방이 할 수 있는 일은 '표본 Σ 위 최적화 또는 점수 기울기'뿐이다.

### 1-3. CDaR_LP 시간 초과 — 원인 특정
- 문제 크기: 변수 p + 3T + 1(p 25 · T 252 → 782) · 제약 ≈ 6T + 2p(≈ 1,564) — **밀집 행렬 전체를 만든다**(`advanced_weights.R:1125-1191`).
- 해법기: 09-07 이전 유일 경로 = cccp 밀집 콘 내부점법(비용 ~T³) — 실측 기록 T 120 2.4 s · T 252 27~36 s(`advanced_weights.R:1105`).
- 호출 빈도: 신호일마다 1회 × 약 260회 → ≈ 140 분 > 워커 상한 90 분 → 09-06 promo2 B2_7 · 09-07 combo B2_9 · B2_10 이 두 번씩 미측정(`run_all_hooks.sh` 주석 · L1 원장 재개 사유 원문 "cccp 밀집 IPM ~T^3(T=252 월 30초 x 260회 = 130분 > 상한 90분)").
- 09-07 수리(lpSolve 1차 · 68f2367b7) 뒤 이 PC 실측: 같은 문제 0.25 s(새 시험 [4]).
- ★감사 메모 정정: "이후 측정 기록 없음"은 사실이 아니다. L1 원장에 CDaR_LP 칸 기록이 09-04~10-05 에 여러 건 있고(essence 붙은 것 ≥ 5 · 커버리지 59% 실패 1 등) **전부 구 축 `k200_kq150`** 이며 다수에 AUTOMEM-EXPOSED-CELLS-DISPOSITION 표식(A 보류 · 재측정 금지)이 붙었다. 현 측정 축 epoch 에서는 한 번도 안 쟀다. (원장 수치는 τ_D 여부를 가리지 않은 기록이라 인용하지 않는다.)
- 남은 구조 문제: CDaR_LP 는 **최소 CDaR 끝점**(μ 무시 · Σw = 1)이라 '점수를 살리면서 낙폭 경로를 관리하는' 칸이 아니다. 그리고 카탈로그 경로는 현금을 낼 수 없다(:558 재정규화 + wrap_adapter target_sum = 1).

## 2. 구현

| 파일 | 내용 |
|---|---|
| `02_Infrastructure/reinforcement/rf_factor_cov.R` | 순수 함수 — `rfc_ts_cov`(관측 FF6 · Fan-Fan-Lv 2008) · `rfc_pca_cov`(주성분 + Bai-Ng IC_p2) · `rfc_cs_cov`(특성 노출 · BARRA 형) · 변형 base/downside/dd_state · `rfc_lw2004` · `rfc_guard`(조건수) · 날짜 진입점 `rfc_sigma_asof`(유일한 PIT 컷 · (Date,Ticker) 겹침 차단 · 요인 표 날짜 덮음 검사 · 종점 단언) · ctx 판 `rfc_sigma_ctx`(공급자 없음/낡음 → pca + 사유) · 로더 `rfc_load_factor_returns`(Date < d) · `rfc_load_exposures`(fc_load_month 경유) · `rfc_register_ctx_provider`(명시 호출) |
| `02_Infrastructure/reinforcement/rf_factor_cov.json` | 설정 초안 + 키마다 근거(논문 원문 링크) |
| `02_Infrastructure/reinforcement/rf_cdar_construct.R` | 희소 삼중항 LP(lpSolve dense.const) · min_cdar / max_mu_cdar_cap · budget eq/le(현금) · ν = κ × EW CDaR(또는 시장 경로) · 후보 선별(pool) → 풀이 → 25종 가지치기 · 회전 인지 항(선택) · 독립 평가기(CUZ 비복리 · 카드 판 복리) · 날짜 진입점 `rcd_construct_asof` |
| `02_Infrastructure/reinforcement/rf_cdar_construct.json` | 설정 초안 + 근거 |
| `02_Infrastructure/methods/adapters/cdar_lp_chekhlov_uryasev_zabarankin_2005.R` | weight 어댑터(method_weights) — max μᵀw s.t. CDaR ≤ CDaR(EW) · Σw = 1 · μ 없으면 min_cdar |
| `02_Infrastructure/methods/adapters/factor_cov_fan_fan_lv_2008.R` | sigma 어댑터(sigma_estimate) — ctx$factor_returns 있으면 ts, 없으면 pca(진단 줄에 mode · 사유) |

기존 파일 수정 0(카탈로그 · 어댑터 등록부 · 셀 엔진 · weight_catalog.R 모두 그대로) → 기존 방법 결과 불변(새 어댑터는 method_registry.json 에 등록되기 전에는 카탈로그가 색인하지 않는다 — `.wc_paper_specs` 는 등록부만, `.wc_generated_specs` 는 adapters/gen/ 만 본다).

## 3. 시험 (전부 통과 · 합성 자료 · 운영 쓰기 0)

| 파일 | 결과 | 시간 |
|---|---|---|
| `08_Tests/reinforcement/test_rf_factor_cov.R` | 31/31 | 1.8 s |
| `08_Tests/reinforcement/test_rf_cdar_construct.R` | 22/22 (시간 격자 전체판 `RCD_TIME_GRID=1` 21/21) | 12 s |
| `08_Tests/scenarios/test_scn_construct_pit_leak.R` | 15/15 | 5 s |
| (회귀) `08_Tests/ops/test_method_adapter_contract.R` | 61/61 | 5 s |
| (등재 검증) `register_method.R::verify_adapter` 기본 8종 fixture | CDaRCapCUZ2005 ok(max|w−EW| 0.727 · 최근접 PreferenceRobustDistortion 0.363) · FactorCovFFL2008 ok(rel_dev 0.0164 · 최근접 LMGarch2DMC 0.375) | — |

요인 Σ 주요 실측(N 60 · T 252 · K 3 합성): Σ 상대 Frobenius 오차 요인 0.190 vs 표본 0.222 · GMV 참 분산 4.78e-5 vs 5.94e-5 · 새 경로 실현 분산 4.14e-5 vs 5.07e-5 · 롱온리 무작위 200개 로그 분산 예측 MSE 0.0119 vs 0.0114(★요인판이 약간 나쁨 — 시장 요인이 지배하는 롱온리 포트폴리오는 둘 다 잘 맞힌다 · 1.05배 허용으로 통과 · 이득은 역행렬을 쓰는 최적화 쪽) · N 300 > T 120 에서 요인 Σ PD(표본은 특이) · B 상관 ≥ 0.953 · Bai-Ng 퍼진 요인 K 3 정확 · 약한 요인은 과소 선택(K 2).
CDaR 주요 실측: LP 목적 = 독립 평가기(1e-8) · 무작위 2,000개 중 LP 보다 낮은 CDaR 0 · 현행 밀집 판과 CDaR 동일(1e-6) · max_mu 해는 CDaR ≤ ν · μᵀw ≥ EW · Σw ≤ 1 판(κ 0.5)은 현금 0.415 · 회전 인지 항 단조.

시나리오: (a) 12개월 월 1회 전부 종점 < 결정일 (b) 요인 열 결손 → ts 멈춤 · ctx 경로 pca + 사유 · ν 실행 불가 → min_cdar 복원 기록 (c) 요인 표 60일 낡음 → as-of 멈춤("60/252일 없음") · ctx 끝 맞춤 → pca + "낡음" (d) 재실행 비트 동일 (e) 결정일 이후 21거래일 극단값 주입에 Σ · 비중 비트 불변 · 돌연변이 4종(소스 텍스트 치환 · 치환 수 단언) 모두 검출 — 종목 컷 제거 → 2선 단언 · 컷+단언 제거 → 출력 변화 · 요인 이력 컷만 제거 → dd_state Ω 표본에 미래 급락이 섞임(322 → 573) · CDaR 컷+단언 제거 → 비중 변화.

내 코드에서 시험이 잡은 결함 2건(고침): ① 요인 표 왼쪽 조인이 빠진 날을 NA 행으로 채워 "요인이 없다"는 엉뚱한 진단 → 날짜 집합으로 직접 세어 "덮지 못한다(n/252일 · 마지막 날)" ② 주입 시험이 (Date, Ticker) 겹침을 만들자 dcast 가 경고만 내고 값을 개수로 바꿈(메모리 카드 'dcast 기본 length' 계통) → 두 진입점에 겹침 차단 단언.

## 4. 소요 시간 실측 (이 PC · lpSolve 5.6.23 · 희소 입력 · 초)

| T \ n | 25 (min · max) | 50 | 100 |
|---|---|---|---|
| 252 | 0.13 · 0.11 | 0.13 · 0.09 | 1.20 · 0.14 |
| 504 | 0.20 · 0.22 | 0.83 · 0.25 | 0.43 · 0.25 |
| 1260 | 0.73 · 0.57 | 1.56 · 1.05 | **132.6** · 0.96 |

- 셀 엔진 경로(n ≤ 25 · T 252): 호출당 ≈ 0.13 s × 신호일 312 ≈ 40 s/칸 — 09-07 이전 ≈ 140 분 대비.
- T 1260 × n 100 최소 CDaR 은 단체법 퇴화로 132 s — pool_size 50 · T ≤ 504 를 권장 상한으로 둔다(설정 문구에 기록).
- 따뜻한 시작: lpSolve R 인터페이스는 기저 재사용을 노출하지 않고 lpSolveAPI · highs · Rglpk 미설치 — 쓰지 않았다(필요하면 도구 세션 밖 설치 · 지금 크기에선 불필요).
- 요인 Σ: 시험 전체 1.8 s(31 단언 · N 300 포함) — 월 1회 호출 비용은 무시할 크기.

## 5. 카탈로그 등록 절차 (총괄 실행 · 필요한 줄)

1. `register_method.R::register_method(method_id = "CDaRCapCUZ2005", paper_id = "doi:10.1142/S0219024905002767", paper_title = "Drawdown Measure in Portfolio Optimization", route = "optimizer", adapter_kind = "weight", adapter = "02_Infrastructure/methods/adapters/cdar_lp_chekhlov_uryasev_zabarankin_2005.R")` — verify_adapter 통과 확인함. `selection_type = "chain"` · `mechanism`/`kr_mapping` 은 어댑터 머리 주석 문장.
2. 같은 방식으로 `FactorCovFFL2008`(adapter_kind = "sigma" · paper_id = "doi:10.1016/j.jeconom.2008.09.017"). 위기판은 별도 method_id(`FactorCovFFL2008_ddstate` — 어댑터 사본에서 `FCOV_VARIANT <- "dd_state"` 한 줄만 다름)로 등재해 시행 집합에 따로 센다.
3. `source("02_Infrastructure/portfolio/weight_catalog.R"); sync_catalog(probe = TRUE)` → `paper:CDaRCapCUZ2005` active. (sigma 는 카탈로그 비중 arm 이 아니다 — Σ-A/B 배터리 `auto_sigma_weighting_ab.R` 와 아래 P-1 이 소비.)
4. ctx 공급자: `ctx_providers.R` 끝에 `source(rf_factor_cov.R); rfc_register_ctx_provider()` 한 줄(지연 thunk 라 다른 arm 결과 불변) — 소유 밖이라 제안만.
5. `reinforce_program.json` B2 블록 어휘에 catalog_id 추가 · 새 키 `weighting.sigma_provider` 를 셀 서명(`rf_spec_sig.R`)에 넣어 시행 회계가 Σ 변경을 다른 칸으로 세게 한다.
6. 등록부 편입 여부(설정 JSON 2개를 06_Registry 로 옮길지)는 총괄 결정.

## 6. 셀 엔진 패치 제안 (E2 소유 · 읽기 전용 · 현재 판 줄 번호)

- **P-1 Σ 공급자 + 날짜 전달**(`rf_cell_engine.R:547-556`): 루프 앞에 `.sp <- .wt$sigma_provider %||% "sample"`(기본 = 현행 · 결과 불변). `"factor:ts:<variant>"` 면 `rf_factor_cov.R` source · 요인 표 1회 적재(`rfc_load_factor_returns(max(.sig_dates) + 1)`) · ctx 에 `R_dates = M$Date` 와 `factor_returns = function() .FR[Date < d]` 를 싣고 `Sigma = rfc_sigma_ctx(ctx, cfg, variant)$Sigma`. 진단 줄을 엔진 로그에 남기고 pca 로 떨어진 신호일 수를 센다(과반이면 측정 무효 — 기존 EW 폴백 가드와 같은 규율).
- **P-2 현금 통과**(`:558 w <- w / sum(w)` + `method_registry.R:79 normalize_long_only(target_sum = 1)`): `weighting.allow_cash = TRUE` 칸만 Σw ≤ 1 을 그대로 두는 래퍼 판(`wrap_adapter_le` — 같은 단언 · 합 ≤ 1). 포트폴리오 단언(:1175 Σw ≤ 1)은 이미 허용. 정규형 변경이라 총괄 결정.
- **P-3 lean 창**(`weight_catalog.R:245`): 캐리어가 `n_days = nrow(ctx$R)` 를 넘기지 않아 lean 20종이 셀 lookback 과 다른 창(60/120)을 쓴다. 고치면 lean arm 결과가 바뀌므로(과거 칸과 비교 불가) 새 판 표식과 함께 — 결정 사항.

## 7. 사전등록 문장 제안 (강화 사슬 P4 · 한 걸음 = 가설 하나 · 칸 하나 · 블록 유형 하나 · 판정 창 = τ_D 이전)

- **S1 [B2 비중 · paper:CDaRCapCUZ2005]** "기저 선정 그대로, 비중만 '점수 최대화 s.t. 창 252일 CDaR_0.95 ≤ 같은 후보 EW 의 CDaR'로 바꾸면, 2022-12-31 이전 LT 위기의 위기 하락 포착 중앙값이 기저보다 낮아지고 상승 포착은 0.55 이상을 유지하며 전기간 CDaR(행동 카드)이 기저보다 낮다. 반증: β 짝(같은 β 현금 사본) 대비 깊은 위기 과반에서 이기지 못하면(노출 방어 귀속) 또는 CDaR 이 기저 이상이면 기각. 유효 종목 수 · 최대 비중을 기록하고 헌장 '집중' 형태로 판정한다."
- **S2 [B2 Σ 공급자 · factor:ts:base]** "사슬이 채택한 Σ 소비 비중 방법(qepm:ERC 또는 MVO)을 고정하고 Σ 만 표본 → FF6 요인 구조로 바꾸면 위기 하락 포착이 낮아지고 상승 포착 · 회전은 악화되지 않는다. 반증: 위기 하락 포착 개선이 무작위 짝 플라시보 분위 안(잡음)이면 기각." (P-1 선행)
- **S3 [B2 Σ 공급자 · factor:ts:dd_state]** "S2 채택 시에만 — Ω 를 결정 시점 이전 약세장(누적 경로 고점 대비 20% 밑) 날들로 바꾸면 깊은 위기 하락 포착이 S2 보다 낮고 강세 상승 포착 손실은 0.55 하한 안이다. 반증: 깊은 위기 과반 개선 없음 또는 상승 포착 < 0.55."
- 사슬 끝: 기저 + S1~S3 칸 전부를 시행 집합으로 `selection_regrade.R` 선택 현실 점검. S2 · S3 는 팩터 DB 와 무관(요인 수익 파일 · 11-10 v1.1 빌드)이라 `factor_db_vintage` 보류 대상이 아니다 — cs 모형을 쓰면 대상이다.

## 8. P/L 우상향 관점 최대 제약 3

1. **현금이 구성 층을 통과하지 못한다** — 카탈로그 경로는 두 곳(:558 · wrap_adapter)에서 Σw = 1 로 다시 맞춘다. 낙폭 예산(CDaR ≤ ν) 구성은 Σw ≤ 1 에서 비로소 '덜 잃는' 수단이 되는데(시험: κ 0.5 → 현금 0.415 로 ν 충족), 지금 현금을 만드는 층은 오버레이뿐이고 그 방어는 전부 노출(β) 방어로 귀속됐다. 증거 = 코드 2곳 + CLAUDE.md MC5 "현금을 만드는 층은 아직 오버레이뿐".
2. **Σ 를 바꿔도 lean 20종에는 닿지 않는다** — lean 캐리어는 ctx$Sigma · lookback 을 무시하고 자체 표본 창(60/120)으로 돈다. 요인 Σ 의 영향 범위는 qepm 8 + 논문 5 arm 뿐. 'P3 구성 레버 포화' 판정은 이 표본 Σ · 짧은 창 위의 포화다.
3. **낙폭 목적 LP 해는 집중한다** — max_mu 판 합성 해: 활성 3 · 최대 비중 0.73 · 유효 종목 1.75(종목 상한 없는 고정 축). 표본 밖 낙폭은 고유 위험이 키울 수 있어 헌장 '집중' 실패 형태와 맞닿는다. 최소 CDaR 끝점은 5~17종으로 덜하다. 사전등록에 유효 종목 수 기록을 의무로 넣었다.

## 9. 도훈 결정이 필요한 것

- P-2 현금 통과 정규형(Σw ≤ 1 래퍼) — 권고: 칸 단위 opt-in(`allow_cash`)으로 도입. 대안 = 오버레이 층에만 현금 유지(현행).
- P-3 lean 창 정합 — 권고: 새 판 표식과 함께 고친다(과거 칸 소급 비교 금지). 대안 = 현행 유지하고 lookback 이 lean 에 안 닿는다고 문서화.
- 종목 상한 없는 고정 축에서 LP 집중을 다루는 방식 — 권고: 축은 그대로 두고 기록 · 헌장 판정으로만(INV-7 · 축 완화 금지). 대안 = ν 를 시장 경로 기준(bench)으로 바꿔 더 느슨한 예산.

## 10. 확인 못 한 것

- 실데이터 로더(`rfc_load_factor_returns` · `rfc_load_exposures`) 실행 — 운영 자료 미적재(기계 바쁨 · 팩터 DB 수리 중). 요인 파일 열 구조만 확인(MKT_TOTAL · SMB5 · HML · RMW · CMA · WML · 2000-01-04~2026-11-06 · 초기 구간 재무 요인 NA → 창에서 자동 제외).
- 결합용 뷰에 업종 열이 있는지 — 미확인(업종 더미 미포함).
- 셀 엔진에서의 실제 동작(P-1 미적용) · 실데이터 소요 시간.
- L1 원장 CDaR_LP 칸 수의 정확한 전수(표본 조회 기준 ≥ 6건).

## 11. 2단계(P-2b · P-3b) — 구성 층 현금 통과 · lean 창 전달 (11-10 오후)

| 파일 | 변경 |
|---|---|
| `02_Infrastructure/methods/method_registry.R` | `wrap_adapter(..., budget = "eq")` 인자 추가(기본 = 종전 경로 그대로) · `budget = "le"` ∧ `ctx$allow_cash` 일 때만 `.wrap_le_finalize`(값 그대로 · 비유한/음수/합 > 1/상한 초과 = stop · 재분배 없음) · 어휘 밖 budget = stop |
| `02_Infrastructure/portfolio/weight_catalog.R` | `.wc_entry_budget`(엔트리/리졸버 `budget` > 어댑터 `METHOD_BUDGET` > "eq") · `.wc_adapter_env`(어댑터 환경 캐시 — 진입점 · 표식 같은 환경) · `as_ctx_adapter` 는 표식 arm 만 `budget = "le"` 로 감싼다 · lean 캐리어가 `ctx$n_days` 있을 때만 빌트인 `n_days` 전달(`.wc_n_days` 검증 · score_pure 포함) |
| `02_Infrastructure/methods/adapters/cdar_lp_chekhlov_uryasev_zabarankin_2005.R` | `METHOD_BUDGET <- "le"` · LP 예산 = `ctx$allow_cash` ∧ μ 있음이면 le · 진단 줄에 budget · cash |
| `02_Infrastructure/reinforcement/rf_cell_engine.R` (최소 2줄) | `if (.CASH) ctx$allow_cash <- TRUE` 1줄 · 현금 0 멈춤 문장의 낡은 'P-2b 필요' 문구 교정(검사 부분 문자열 유지) |
| `08_Tests/scenarios/test_scn_rx_construct_link.R` | D2 유지(표식 없는 arm = 멈춤) + D2b 배선 · D4 → P-3b 양성(완주 · 기본 창과 다름) · E3 → 가드 양성 대조(판독 토큰을 바꾸면 멈춤) |
| `08_Tests/contracts/test_weight_catalog.R:41` | ★결함 수리 — `sync_catalog(root = ROOT)` 가 운영 `06_Registry/weight_catalog.json` 을 다시 썼다(이 세션 14:34 실측 · git checkout 으로 원복 · HEAD 10-16 판과 동일 확인) → `write = FALSE` |
| 새 시험 `08_Tests/reinforcement/test_rf_cash_budget_link.R` | 20/20 · 돌연변이 7(method_registry 4 · weight_catalog 3 · 치환 수 단언) |

결과 불변 증거: 카탈로그 58 arm × (기본 ctx · allow_cash ctx) 116 스냅샷 — 수정 전/후 비트 동일 116/116(합성 fixture · 스크립트 e3_baseline.R).
남은 것: ① CDaR arm 은 등록 전이라 셀 엔진 실경로 현금 칸은 미실행 ② κ = 1(ν = EW CDaR)이면 max μ 해는 대개 완전 투자 → allow_cash 칸이 엔진의 '현금 신호일 0' 가드에 걸린다. 현금이 실제로 생기려면 ν 를 묶는 근거 있는 규칙이 필요 — 후보 = nu_rule bench(ν = 같은 창 KOSPI200 경로 CDaR × 1 · 등급 CR '강함' = 전략 MDD ≤ 벤치 MDD 와 대응) · 엔진이 ctx 에 같은 창 벤치 수익(BM_DT · Date < d)을 실어야 함(패치 1줄 + 어댑터 1줄) — 총괄 · 도훈 결정.

## 12. 3단계 — 벤치 낙폭 예산 선택지 nu_rule = "bench" (11-10 저녁)
- `rf_cdar_construct.R`: `rcd_nu_rule`(ew → ew_candidates 별칭 · 어휘 밖 멈춤) · `rcd_bench_align`(벤치 Date < d · R 행도 < d · 날짜 교집합 · 시나리오를 교집합으로 줄임 · 최소 관측 = ceiling(1/(1−α)) = 20 — 설정 alpha 에서 유도) · `rcd_construct(nu_rule =)` 인자(기본 NULL = 설정값 · 비트 동일).
- 어댑터: `ctx$cdar_nu_rule` 판독 · bench 면 정렬 뒤 ν = CDaR(벤치) × 1 · 진단 줄에 nu_rule.
- 셀 엔진(2줄): 루프 앞 = `weighting.cdar_nu_rule` 어휘(ew | bench) · bench 인데 BM_DT 없음 = 멈춤 · 루프 안 = 선택 시만 ctx 에 규칙 · R_dates · `BM_DT[Date < d]`(엔진이 이미 받는 공표 KOSPI200 계열).
- 시험 `08_Tests/reinforcement/test_rf_cdar_bench_budget.R` 24/24 — 빡빡(β 1.5): Σw 0.798 · CDaR ≤ ν · 느슨(β 0.5): Σw 1 · PIT 2종 · 기본 비트 동일 · 멈춤 4종 · 엔진 두 줄 실제 문장 평가 · 돌연변이 4.
- ★한계: 어댑터 안의 멈춤은 wrap_adapter 가 EW 폴백(호명)으로 바꾼다 — 칸 단위 멈춤은 엔진의 EW 폴백 과반 가드가 맡는다(신호일 일부만 실패하면 그 날만 EW). BM_DT 부재는 엔진이 직접 멈춘다.
- 등록 절차 추가 줄: `reinforce_program.json` B2 어휘에 `weighting.cdar_nu_rule`(ew 기본 | bench = 같은 창 KOSPI200 CDaR × 1 · CR '강함' 기준) 서술 · `test_rf_cdar_bench_budget.R` SUITES 편입.
