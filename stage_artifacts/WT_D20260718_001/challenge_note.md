# Self-Adversarial Challenge — WT-D20260718_001 (Crash-aware momentum selection)

Agent: alpha-research (Opus 4.8 native adversarial). finalize 직전 자가 적대검증 (v8.2 Codex Round 대체, AX-008 3-source 중 1).
measured_at: 2026-07-18 | pin_tag: wt_d20260718_001_20260718_205815 | pin_upstream: fq057_20260718_171024

## 자기 비평 (≥3 concerns) + 분류 + 처리

### C1 [REBUTTAL] 측정 중 벤치마크 버그 발견·수정 — 수정된 base를 신뢰할 수 있는가? FQ-058(1.34) 대비 잔차(1.91)는?
- **concern**: 최초 build_bench_m가 22.5% CAGR(비상식적)을 산출 → base PORT_t를 왜곡. 세션 중 수정한 base 신뢰성 의문.
- **근거·처리**: contemporaneous size-weighting(월말 시총으로 그 달 수익 가중)이 winner-overweight **look-ahead 버그**임을 격리 실증(`/tmp/bench_isolate.R`): Return.portfolio(PIT-lagged) 10.79% vs direct rowSums(contemporaneous) 22.5%. 수정(Return.portfolio 내부 1-period lag)은 FQ-058 벤치 CAGR **10.79% 정확 재현**. 잔차 base PORT_t 1.91 vs FQ-058 1.34 = harness 변이(canonical delta-cost·top-25 EW vs FQ-058 Return.portfolio drift-cost), 방향성 아님. **본 연구는 identical harness+bench의 paired base-vs-treatment** → 절대 수준 parity는 non-load-bearing. 학술: β-scan offset-0 정렬 확인([[reference-book-benchmark-alignment-realized-ym]]). L-code: [[reference-orthogonality-gross-vs-active]] long-only β≈0.92 정합. 정량 3축: (a) offset scan -2..+2 offset-0 최적 (b) FQ-058 재구성 10.79% 일치 (c) corr 0.992.
- **자기합리화 자동검증**: "harness 변이"는 회피어 아님 — delta-cost vs drift-cost 차이를 명시 격리. "미미"·"관행" 미사용.

### C2 [PARTIAL] IS-선택(max IS calmar)이 OOS-최악 변형(composite_l1)을 골랐다 — 사전등록 규칙이 실효(semivol)를 사보타주?
- **concern**: 사전등록 selection(IS calmar 최대화+guard)이 composite λ=1.0(IS calmar 0.618 최고이나 OOS PORT_t -1.02) 선택. semivol_0.5(OOS-robust)를 놓침.
- **처리**: 사전등록은 **IS-only(OOS 미조회) 준수** — 프로세스 정합(chain 자격 ②). IS-calmar-max가 overfit 변형을 뽑은 것 자체가 **결과**(IS calmar = robustness 목적함수로 부적합). dual-basis 전-변형 진단표(`ca_defensive_diagnostic.parquet`)로 semivol_0.5를 informative sub-finding으로 **별도 병기 보고**. 사전등록 primary는 정직히 negative, semivol은 진단으로 승계. 방법론 caveat(선택목적함수) 기록.
- **자기합리화 검증**: pre-registration 우회 유혹(semivol을 primary로 소급 승격)을 **거부** — IS-only 원칙 사수. semivol은 diagnostic-tier로만.

### C3 [REBUTTAL-partial] downside_semivol_0.5의 MDD/calmar 개선 = 진짜 crash-avoidance인가, 위장 de-risking(IS 1-episode overfit)인가?
- **concern**: semivol_0.5 full calmar 0.510→0.555, MDD 0.398→0.351 = 실효인가?
- **근거·처리**: **위장 de-risking(low-vol tilt)으로 판정**. 정량 3축: (a) **OOS MDD도 개선**(0.398→0.334) → 단일 IS episode 아님, 그러나 (b) momentum PORT_t가 λ 단조 감소(1.91→1.77→1.23)·OOS alpha 단조 악화(-0.07→-0.35→-0.59) = premium 희생으로 산 MDD, (c) **진짜 crash-risk 축(downside_beta·ncskew)은 MDD 미개선/악화**(downside_beta_0.5 MDD 0.519 WORSE) → crash-prone 종목을 ex-ante 식별해 회피한 게 아니라 단지 저변동 종목으로 이동. bad_sr 불변(~-3.1) = 위기 시 여전히 급락. 학술: DeMiguel 2009 1/N·low-vol premium, Chen-Hong-Stein NCSKEW(식별 실패=crash가 common-factor). L-code: low_vol standalone port_t -1.26(FQ-058)·[[project-pg2-offense-overlay-settled]]. → "crash-avoidance"로 과대주장 **금지**, "risk/return trade(de-risking)"로 정직 프레이밍.

### C4 [ACCEPT-flag] PIT: crash 신호는 h-1 종료(검증)이나 membership/liquidity 필터는 holding-month(t_ym) 데이터 사용(FQ-058 상속 관행) = mild look-ahead.
- **처리**: elig_at_f/liq 필터가 holding month t_ym 멤버십·avgtv20 사용 = 엄밀 PIT 아님(t-1이어야). **FQ-058 harness 상속**이며 base·전 treatment에 **동일 적용** → paired 비교 불변. flag 기록, negative 판정에 영향 없음(양측 공유). 향후 strict-PIT(t-1 membership) 재측정은 next_probe.

### C5 [PARTIAL] 20-변형 grid = sweep → 다중검정 inflation? DSR?
- **처리**: grid 열거(sweep-유사) → graduation-tier면 DSR HARD 대상이나 **alpha-stage canonical screening**(forge-authoritative 아님, measurement-graduation §3). 판정이 **NEGATIVE**(어떤 변형도 graduating 주장 안 함)이므로 다중검정이 false-positive를 제조하지 않음 — 오히려 IS-best가 OOS-fail = data-mining 반대 방향. n_trials=20 기록(감사). DSR 진단만.

## Q-Lead escalate trigger 체크
- HIGH severity ≥5? NO (1건 REBUTTAL/1 ACCEPT-flag/3 PARTIAL, hard 위반 0). AX axiom hard FAIL ≥3? NO. PIT C1(lockbox/lookahead) 위반? **벤치 look-ahead는 발견 즉시 수정·재측정 완료**(잔존 위반 아님). → escalate 불요.

## 결론
- 사전등록 primary(crash-aware SELECTION이 momentum alpha 보존하며 drawdown 개선) = **config-scoped NEGATIVE**.
- informative: SELECTION-층 MDD 레버는 존재하나(semivol) = 위장 de-risking(premium 희생), crash-avoidance 아님. 진짜 crash-risk 축은 무효 → momentum crash = common-factor(FQ-058 확인·확장).
- base momentum OOS-dead(PORT_t -0.07) → 자본 graduation 불가(≪2.95). **terminal ALPHA_DONE**(v8.3 M1 조기종결 — risk-research 진행 불요).
