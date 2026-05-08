# Challenge Note — WT-D20260508_002 Alpha Research

**Pending**: This note is staged before alpha_package_draft completes ML training (v4 in progress month ~30/136). Will be updated with final empirical numbers + Codex disposition after run completes + critic round.

**Status (작성 시점)**: v4 ML training 진행 중. draft, codex critic, final disposition 미완료.

---

## 1. Hypothesis 정의

**제목**: ML residual cross-section per-name alpha — Hybrid 70/15/15 explained variance 차감 후 잔차에서 추출

**Mechanism (학술 출처 직접 인용)**:
- Gu/Kelly/Xiu (2020) RFS — XGBoost / RF / NN ensemble로 cross-section forward return 예측. 1500+ citations.
- Bryzgalova/Pelger/Zhu (2024) RFS — Random Forest 기반 anomaly tree 구조. 결정 트리가 비선형 factor interaction 포착.
- Chen/Pelger/Zhu (2024) — Deep Learning factor pricing kernel.
- Lopez de Prado (2018) Advances in Financial ML — Combinatorial purged CV, time-series leakage 방지.
- Lopez de Prado (2020) ML for Asset Managers — DSR Bailey-LdP, multi-trial Sharpe inflation 보정.
- Jensen/Kelly/Pedersen (2023) JF — Replication crisis Bayesian framework. KR market subsample factor decay 진단.
- Avramov/Cheng/Metzker (2023) MS — ML overfitting vs economic restriction tradeoff.

**도훈 추가 reference (중국 저자 인용수 최상위)**:
- Liu/Stambaugh/Yuan (2019) JFE "Size and Value in China" — CH-3 factor (SMB / VMG). 800+ citations. KR≈China emerging Asia 적용 가능. v4 코드에 SMB/VMG 후보 통합 시도 (실측: 직접 매칭 0, q-factor profitability 22 hit, q_ROE composite 1건 retained).
- Hou/Xue/Zhang (2015) RFS "Digesting Anomalies — q-factor" — investment + profitability axis. 1200+ citations. Factor DB Q01-Q34 covered + v4 직접 q_ROE composite.
- Hou/Xue/Zhang (2020) RFS "Replicating Anomalies" — replication crisis 직접 입증, KR L-228 (KR top universe alpha discovery limit) 정합.

## 2. Korean Market 적용성 정량 평가

| Reference | KR 적용성 | v4 통합 결과 |
|---|---|---|
| Gu-Kelly-Xiu 2020 | ★★★★★ | XGBoost / RF / Ridge / EN / MLP / Ensemble 6모델 직접 적용 |
| Bryzgalova-Pelger-Zhu 2024 | ★★★★ | ranger RF 200 trees mtry=√81 적용 |
| Chen-Pelger-Zhu 2024 | ★★★★ | torch MLP CPU build (CUDA 미가용 정직 보고) |
| Lopez de Prado 2018 | ★★★★★ | rolling expanding window + 1m purge 적용 (full CPCV는 단순화) |
| Lopez de Prado 2020 | ★★★★★ | DSR Bailey-LdP skew/kurt 보정 SR 산출 |
| Jensen-Kelly-Pedersen 2023 | ★★★★ | sub-period stability 3-period 분할 적용 |
| Avramov-Cheng-Metzker 2023 | ★★★ | feature engineering economic restriction (lag-1 only, no contemporary) |
| Liu-Stambaugh-Yuan 2019 | ★★★★ | CH-3 candidates 검색 (size/value 직접 매칭 0건 — Korean Factor DB Q-prefix 명명 차이) |
| Hou-Xue-Zhang 2015 | ★★★★ | q-factor profitability 22 hit, q_ROE composite 통합 |
| Hou-Xue-Zhang 2020 | ★★★★ | KR L-228 정합 — 본 WT 결과로 직접 검증 |

## 3. WT_001 lessons 직접 적용 (의무)

| Lesson | WT_001 사례 | WT_002 v4 적용 |
|---|---|---|
| L1: predictor lag-1 autocor pre-check | v1 IC 0.957 = autocor 0.404 mistaken alpha | 280 factor median autocor 0.865 (high), AC>0.95 = 53 factors warning. 290 factor 시 v3, 75 factor 시 v4 median 0.865 ≥0.80=48/75. **flag**: high autocor warning challenge_flag 통합 |
| L2: feature leakage check | v2 ML XGBoost IC 0.9953 = r_AR_lag1 leakage | 모든 feature lag-1 explicit shift 의무. r_Hybrid는 t (target month) 값으로 차감 (잔차 정의 자체 보존), feature는 모두 t-1 |
| L3: naive long bias check | XGBoost SR 1.62 = 95.8% positive prediction = naive long | pos_pred_frac in [0.3, 0.7] check. 극단 위치 시 NAIVE_LONG_BIAS_RISK challenge_flag |
| L4: cost integration | LS SR_net -0.43 = 15bps × TO 5.65 absorbed all | cost-aware net SR 의무. 15bps × turnover_ann × 2 round-trip 차감 후 long_sr_net 산출. >0 시만 operational_alpha_pass |
| L5: DSR strict | DSR -1.47 < 0 | Bailey-LdP skew/kurt 보정. >=0.5 gate |

## 4. GPU 가속 검토 — 도훈 명시 의무 + 환경 한계 정직 보고

**도훈 명시**: RTX 4080 SUPER 16GB / CUDA 13.1 driver / 12.6 toolkit 가용. ML 모델 train 시 GPU 활용 가능한 method는 GPU 사용 권고.

**v4 Step 0 GPU diagnostic 실측**:
```
hardware_present: TRUE (libcudart.so.12 detected /usr/local/cuda-12.6/lib64/)
hardware_name: NVIDIA GeForce RTX 4080 SUPER
torch::cuda_is_available(): FALSE
backends_cudnn_is_available(): FALSE
xgboost device='cuda' runtime: WARNING "Device is changed from GPU to CPU 
                              as we couldn't find any available GPU on the system"
xgboost CPU build verified: 5k×50 train CPU 0.525s, requested GPU 0.21s 
                            (실제로는 CPU fallback — GPU init zero overhead로 빨라보임)
```

**진단**:
- WSL2 환경 R `xgboost` 3.2.0 CRAN binary = **CPU-only build** (libxgboost.so GPU support 미컴파일)
- R `torch` 패키지 libtorch CPU build (libtorch_cuda.so 미설치)
- CUDA toolkit 자체는 가용 — R 패키지 CUDA 바인딩 부재가 root cause

**GPU 활용 가능했을 method**:
- XGBoost `tree_method='hist', device='cuda'` (XGBoost 2.0+) — 현 binary CPU fallback, 가속률 0x
- torch MLP `torch_device('cuda')` — torch::cuda_is_available()=FALSE, GPU init 불가

**가속률 정량 (cross-section per-month size 1k~3k rows × 81 features)**:
- XGBoost CPU 32-thread (16-core hyperthread): month당 ~1-2s
- 이론적 GPU 가속률 (XGBoost docs): 100k+ rows에서 5-10x. 본 size (3k rows) = GPU init overhead가 train time 대비 dominant → 예상 가속률 **<1.5x** 또는 오히려 더 느림
- 따라서 본 WT data scale에서 GPU benefit minimal — full panel single-train (72k rows) 시는 의미 있을 수 있음

**결정**: 결과 산출 의무 우선 → CPU 16-core 활용 + 도훈 명시 정직 보고 (회피 표현 사용 X). 후속 architect agent 인프라 WT 권고.

**후속 권고 (architect agent에 spawn 권고)**:
1. R `xgboost` GPU-enabled source build (~30분 build + CUDA toolkit linkage). 또는 GPU-enabled docker container.
2. R `torch` libtorch CUDA build install — `torch::install_torch(reinstall=TRUE)` 후 `cuda_is_available()` 검증.
3. Full-panel single-train benchmark (72k rows × 81 features) CPU vs GPU 정량 비교 — cross-section per-month rolling은 GPU benefit 제한적이지만 large-batch는 5x+ 기대.

## 5. v3 → v4 진화 (방법론 honest disclosure)

**v3 발견 문제**:
- dcast 125M rows × 290 factors → OOM/slow (>10min)
- BM_Ret proxy 사용한 r_Hybrid (도훈 challenge: real STR_1715 backtest series 사용 의무)

**v4 fix**:
- Per-month wide pivot (월별 작은 size로 dcast → 빠른 join)
- Factor pre-filter: top 80 by coverage (Korean economic relevance retained)
- **Real STR_1715 r_Hybrid** 직접 load (`bt_result.rds` portfolio nav 기반)
- C15-compliant `load_month_factors()` 경유 의무 충족
- Chinese-author features (CH-3 + q-factor) 통합
- torch MLP (Chen-Pelger-Zhu mechanism)
- GPU diagnostic Step 0 통합 (honest disclosure)

**v4 panel summary**:
- Date range: 2008-02 ~ 2026-04
- Sample size: median 348, mean 330.5 per month
- Final panel rows: 72272
- Features: 81 (74 factor + 1 q_ROE composite + 6 engineered)
- Test months: 136 (2015-01 ~ 2026-04)

## 6. Challenge_flags (사전 예상 / 실측 후 갱신)

**작성 시점 사전 예상**:
- HIGH_PREDICTOR_AUTOCOR — median autocor 0.865 (>0.80 48/75 factor) 매우 높음. WT_001 lesson 1 정합. t_NW 보수적 해석 의무.
- POTENTIAL_REPLICATION_CRISIS — KR universe + 76 monthly factors × 6 ML models = 456 trial multi-testing. Harvey-Liu-Zhu t>3.0 + DSR strict 적용 의무.
- HYBRID_PROXY_ROBUSTNESS — Real STR_1715 series는 v4에서 사용했으나 PG2 admit 후 effective 2026-06-01. 현재 5월 운용 70%+30% cash 와 차이. 백테 windows 상 Hybrid 70/15/15 weights는 forward로 확장 적용한 가정.
- AX-007 EXCEPTION_VERIFY — single_sleeve_long_only_top20 메커니즘 단절 axiom. 본 WT는 ML sizing 예외 4종 중 하나 (per-name cross-section ML alpha). 명시적 충족 입증 필요 — Risk-research stage에서 50+ 분산 또는 ML sizing 의무.

**실측 후 추가/수정** — v4 완주 후 갱신.

## 7. AX 공리 disposition (사전)

| Axiom | Status | Note |
|---|---|---|
| AX-000 | OBSERVE — 한계 없다 자율 탐색 | ML residual approach 신규 path |
| AX-001 v2 | NA at alpha stage | Risk stage에서 defense 평가 |
| AX-002 | PASS | WT_001 lesson 5건 모두 직접 통합 + GPU 정직 보고 |
| AX-003 | PASS — value EP_STANDALONE 회피 | ML residual은 value 단일 의존 X |
| AX-004 | PASS — quality_profitability single-signal 회피 | q_ROE composite 1건만 (multi-axis 결합) |
| AX-005 v1.2 | NA at alpha stage | EXCLUSION 검증 Risk stage에서 |
| AX-007 | TARGETING — ML sizing 예외 path | per-name cross-section ML alpha = 4 예외 중 ML sizing |
| AX-008 | TARGETING — alpha first stage | Codex critic + Architect 후속 검증 의무 |

## 8. 합리화 자기 검증

회피 표현 grep self-check (Charter §8 No Silent Override):
- "영향 미미" — 사용 0건
- "관행적" — 사용 0건
- "보수적이면 OK" — 사용 0건
- "대부분 결과 동일" — 사용 0건
- "이미 반영" — 사용 0건
- "실무적" — 사용 0건

명시 라벨 사용:
- "검증 안 됨 (가정)" / "TBD — task #N 후속" 적용 시 명시
- "GPU 환경 build 한계로 미실현" = 실측 정량 보고 (회피 X)
- "후속 권고" 적용 시 architect agent + 이유 명시

---

## 9. Codex Critic Round (post-execute 갱신 예정)

**Step 1**: alpha_package_draft.json Write 후 codex_round_auto_trigger.sh background spawn
**Step 2**: ~9-15분 대기, codex_critic_response_alpha.json 도착
**Step 3**: stance / critical_concerns / weakest_assumption 분석
**Step 4**: 본 challenge_note에 ACCEPT / PARTIAL / REBUTTAL 기록 (학술 1+ + L-code 1+ + 정량 3축)
**Step 5**: alpha_package.json final 작성 (codex_round_pre_enforcer.sh 통과)

## 10. 후속 결정 path (사전)

**op_pass=TRUE 시**:
- Codex critic round → APPROVE 또는 APPROVE_CONDITIONAL → Risk-research spawn
- AX-007 ML sizing 예외 검증 (50+ 분산 또는 ML weight scheme)
- AX-008 Forge + Architect verification triangulation

**op_pass=FALSE 시 (WT_001 정합)**:
- DISCOVERY_FAIL_HONEST_NO_ADMIT 명시
- 후속 pivot 권고:
  1. VKOSPI direct via KRX OpenAPI (WT_001 priority 1, 데이터 인프라 fetch ~3-5h)
  2. Defensive_LowVol_KR multi-sleeve EXCLUSION (AX-005 v1.2)
  3. Commodity Gold/Copper KR ETF (cycle 2 cor_hybrid 0.023)
  4. 추가 — IPCA latent factor (Kelly-Pruitt-Su 2019 JFE) — characteristics-loadings 통합 mechanism
  5. 추가 — RL portfolio (Cong-Tang-Wang-Zhang 2021 AlphaPortfolio) — supervised ML 다른 mechanism

---

**작성일**: 2026-05-08 10:55
**상태**: PENDING_FINAL — v4 ML training 진행 중 (month ~30/136), 완주 후 empirical numbers + Codex disposition 갱신 의무

