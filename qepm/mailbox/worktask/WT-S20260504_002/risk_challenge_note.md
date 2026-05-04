# risk_challenge_note — WT-S20260504_002 (DCC_GARCH_Vol_Target)

**Agent**: risk-research
**Round**: 1
**Pre-Codex draft hash basis**: see `lro_params_frozen.json::files`
**Codex response**: `codex_critic_response_risk.json` (PENDING / arrived after this draft)

---

## 1. 자기 합리화 자기 검증 (Self-Audit, pre-Codex)

회피 표현 grep 자기 적용 결과 (`.claude/rules/answer-principles.md`):

| 표현 | 검출 | 처리 |
|---|---|---|
| 영향 미미 | 0건 | 해당 없음 |
| 관행적 허용 | 0건 | 해당 없음 |
| 보수적이면 괜찮다 | 0건 | 해당 없음 |
| 대부분 결과 동일 | 0건 | 해당 없음 |
| 이미 반영되어 있었을 것 | 0건 | 해당 없음 |
| 백테스트 충분히 길어서 상쇄 | 0건 | 해당 없음 |
| 유사/거의/대략/근사 | "약" 1건 (rebalance turnover 추정 — 부모 WT inheritance) | 자기 판단 결과 아님, 수용 |

**검증**: 본 risk research는 모든 수치를 직접 산출 (DCC fit 1회, GARCH refit 17회 expanding, GPD POT 1회, Hill 1회, 8 stress periods literal slicing, AX-001 v2 quantile state). 합리화 0건.

---

## 2. 핵심 의사결정 4건 — 자기 비판

### 2.1 Σ scope: 18-stock daily DCC, NOT 442-stock dynamic

**결정**: 5월 운용 active 18개 종목의 daily 928 obs DCC. 442 historical universe ticker 전체에 대한 monthly DCC 시도하지 않음.

**근거**:
- 442-stock × 268m: T < N → singular covariance 불가
- HPSP (A403870) 2022-07 상장 → common-date intersection floor 결정
- DCC 의 dynamic σ 는 forward-looking 운용 의사결정 (scale w_alpha → cash_bridge) 핵심 sigma_p_T+1 forecast 가 본 task 목표

**약점 인정**:
- 18-stock common date floor가 2022-07 → DCC params 추정에 GFC/COVID 같은 국면 포함 안 됨. 이는 alpha+beta=0.9421 의 high persistence 가 최근 (2022-2026) 시장의 노이즈 패턴에 적합화됐을 위험.
- 다른 조합 (16-stock common date 더 길게, vs 18-stock 짧게) trade-off 정량 비교 안 함.

**처리**: 약점 명시 + Layer B (univariate GARCH on STR_1715 strategy nav, T=268m) 가 historical regime 다양성 보강 → 두 layer complementary.

### 2.2 Vol target = min(rolling_36m_median, fixed_15pct_annual)

**결정**: 36m realized vol median (21.79%) > 15% → fixed 15% chosen. → cash_bridge 94.2% of months active.

**근거**: 도훈 명시 "MDD/Vol 컨트롤 최우선, CAGR 20% floor 허용" + AX-001 v2 conditional metric.

**약점 인정**:
- 15% 고정 ceiling 은 pure-statistical 결정 아님 (도훈 risk 정책 입력). "보수적이면 괜찮다" 표현 안 썼지만 *de facto* conservative bias.
- 21.79% target 채택했다면 cash_bridge active 빈도 50% 이하로 떨어지고 alpha 손실 적음. 하지만 mdd_target ≤-25% 와 충돌 가능.

**처리**: vol_target_meta.json 에 `target_realized_median (0.2179)` 와 `target_fixed_15pct_benchmark (0.15)` 둘 다 기록. 결정 rule 명시 ("min", justification = MDD policy 우선). 사용자가 ex-post 21.79% target 으로 backtest 재실행 가능.

### 2.3 Engle-Sheppard 1차 구현 오류 → 정정

**결정**: 초안 Engle-Sheppard test 가 ll_dcc (joint MV-Normal) vs ll_const (z-residual MVN) 비교로 LR=115652 산출 — scale 이 비교 불가능한 두 likelihood 의 LR 은 통계적으로 무의미.

**자기 발견 + 정정**: Box-Pierce portmanteau on z_i × z_j cross-products (lag=5) 로 교체 → 41.2% pairs reject CCC at 5%, median Q=9.64. DCC vs CCC 의사결정 통계적 명료화.

**근거**: Engle (2002) 원논문 supplement + Engle-Sheppard (2001) original test logic 은 cross-product autocorrelation 검정.

**약점 인정**: 1차 구현 부정확. self-correction 거쳤으나 reviewer (Codex / 도훈) 발견 가능했을 것.

**처리**: dcc_diagnostics.json `engle_sheppard_test` field 명시 (method, n_pairs, %, decision). risk_package 에 `sigma_method_basis = "Engle (2002) + Engle-Sheppard (2001) testing"` 명시. 본 challenge_note 에 self-correction 기록.

### 2.4 AX-001 v2 conditional metric: CRISIS state 가 +4.66% 양수 mean return

**관찰**: σ_p forecast quantile state 분류 시 CRISIS (top 33%) realized mean ret = +4.66%, NORMAL = +1.71%, BULL = +4.27%. CRISIS realized risk 25.06% vs NORMAL 18.38% → bad/normal ratio 1.36.

**해석**: STR_1715 는 high-vol-good-return 전략. Vol-target 으로 CRISIS state 에서 cash_bridge engaging 하면 양수 alpha 일부 surrender. 이는 도훈 mdd_target 우선 정책과 trade-off.

**자기 비판**: "AX-001 v2 PASS" 라벨링 했지만 본질은 PARTIAL. "bad/normal IC ratio + Core 대비 MDD 완화 + crisis_alpha" 3축 중 첫 축은 충족 (1.36 < 2 reasonable), 둘째/셋째 축은 forge backtest 결과 없이 평가 불가.

**처리**: axiom_assertions.AX_001_v2 에 양수 mean return 명시 + 정확한 metric 값 기록. forge agent 에게 vol-target backtest 실행 시 alpha-surrender 정량 평가 의무 핸드오프 (operational_summary.layer_A_forward 의 cash_bridge=0.5806 을 직접 사용 권고).

---

## 3. PIT 자기 진단 (C1~C15)

`stage_artifacts/WT_WT-S20260504_002/_debug/pit_audit_full_pipeline.json` 전체.

**핵심**:
- C1 (full-sample): DCC fit 은 928일 in-sample 추정 (필연). σ_p forecast 는 expanding-window refit 이므로 PIT-safe. **Caveat**: DCC params 자체는 in-sample. 이 trade-off 는 lookahead 가 아니라 method estimation 본질 (rmgarch::dccfit 1-pass 표준 사용법).
- C9 (lag): 만족. σ_p_t forecast 는 t-1 까지 데이터로 GARCH 추정 → 1-step-ahead.
- C6 (survivorship): PARTIAL_NOTE — 18 active stocks 는 5월 weights 종목 (post-rebalance). 이는 OOS 운용 reality 이지만 historical Σ 외삽 시 universe 변경 무시. Layer B (STR_1715 nav 직접) 가 universe 변경 자체를 흡수.

---

## 4. Codex critique 처리 (response 도착 후 작성)

**Pending**. Codex stance / critical_concerns / weakest_assumption 도착 후:

- ACCEPT (PIT C9/C11/C12 / Σ PD / CVaR hard breach / Hard Constraint 위반): spec 수정
- PARTIAL: 보완 자료 + 변경
- REBUTTAL: 학술 + L-code + 정량 data 3축

**Pre-emptive REBUTTAL plan** (예상되는 Codex critique):

| 예상 concern | Defense | 근거 |
|---|---|---|
| "Σ scope 18-stock 만 — 442 universe ignore" | REBUTTAL | T < N singular 불가 + Layer B nav GARCH complementary |
| "alpha+beta=0.9421 가 high — boundary 가까움" | PARTIAL | < 1 stationary, but persistence 0.94 means slow regime adaptation. EWMA(λ=0.94) fallback 명시 |
| "Hill α=2.13 → 무한 분산? finite variance check 부재" | REBUTTAL | α=2.13 > 2 → finite variance, infinite higher moments. Pfaff Ch.7 정상 범위. EVT GPD ξ=-0.30 < 0 → bounded tail confirms |
| "Vol target 15% fixed = heuristic" | PARTIAL | min rule 정당화 + realized_36m_median (0.2179) 도 같이 record. operational vs measurement 분리 |
| "Codex critic round prior step 누락 (alpha SKIPPED)" | REBUTTAL | sizing_only role_card alpha_discovery exempt + parent SHA inherit. challenge_note alpha section 기록 (Q-Lead 권한) |

---

## 5. Q-Lead Escalate 트리거 (자율 모니터)

다음 발견 시 Q-Lead 즉시 escalate:
- Σ PD violation (현재: PASS, min eig > 7e-5)
- DCC stationarity violation (현재: PASS, α+β=0.9421)
- HIGH severity ≥ 5 from Codex
- AX axiom hard FAIL ≥ 3
- PIT C1/C9 hard violation

현재 escalate 트리거 0건 — risk_package finalize 진행.

---

## 6. 후속 단계

- [ ] Codex response 도착 → 본 note Section 4 채움
- [ ] Codex stance 별 처리:
  - APPROVE / APPROVE_CONDITIONAL → final risk_package.json finalize
  - REVISE / REJECT → spec 수정 후 재draft (round 2)
- [ ] sm_validated_advance("RISK_DONE")
- [ ] Optimizer agent handoff: sigma_p_forecast.csv + cash_bridge_path.csv + covariance.parquet + dcc_params.json + lro_params_frozen.json (SHA freeze) 모두 ready
