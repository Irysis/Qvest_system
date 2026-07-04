<!-- Qvest Shared Prefix — 모든 agent init이 상단에서 참조하는 단일 SOT -->
<!-- DO NOT duplicate this content into individual init files. Reference only. -->
<!-- 갱신 시 .cache/axiom_core.json ↔ CLAUDE.md §Axioms와 동기화 필수. -->
<!-- cache_control: stable prefix. ephemeral 1h breakpoint 권장 위치 (Anthropic API 호출 시). -->
<!-- 본 파일 변경 = prefix cache invalidation. 변경은 axiom 승격/폐기 시점만 허용. -->

<axioms level="0" immutable="true" injection="hook-authoritative">
<!-- (P0 이중주입 소거 2026-07-04 감사) axiom 본문(statement)의 *실주입*은 PreToolUse[Agent] 훅 -->
<!-- `02_Infrastructure/hooks/axiom_context_inject.sh`가 additionalContext로 라이브 수행한다.       -->
<!-- 과거 이 블록이 본문을 정적 임베드 → 훅 additionalContext와 이중 주입 → 예산(2500자) 낭비+중복.  -->
<!-- 따라서 본 블록은 이제 *참조 스텁*: ID·계층·polarity 인덱스만 남기고 본문은 훅 단일 출처로 통일. -->
<!-- 문서-권위(hard-fail SOT)는 여전히 `.claude/rules/axioms.md` ↔ active/*.json (sot_map). -->
활성 공리(본문 = 훅 주입, 여기선 인덱스만). **active Law 4건**:
- **AX-000** [IMMUTABLE] · **AX-001 v2** [conditional-defense] · **AX-001 v2.1** [META-ALLOCATION-EXEMPT] · **AX-002** [IMMUTABLE]
- **AX-008** [process] Verification Triangulation (Forge + Self-Adversarial + Architect 2/3)

**Distilled 강등(2026-07-05, INV-7 — Law 아닌 탐색지도)**: ~~AX-003 value~~ · ~~AX-004 quality~~ · ~~AX-005 defense~~ · ~~AX-007 translation-break~~ → DIST 카드/Ledger(`hypothesis_index` 검색·`revival_spec` 부활). active enforcement 대상 아님.

본문·근거 L-code·mode-local AX는 훅 주입(additionalContext) + `.claude/rules/axioms.md`(문서 SOT) 참조.
계층: AX-code(Lv0 공리) > PIT C1-C15(Lv1) > L-code(Lv2 교훈) > Signals(Lv3 가변). 위반 = 즉시 중단.
</axioms>

<research_philosophy level="0" version="v1.0" effective="2026-05-14" sot="02_Infrastructure/docs/qvest_research_philosophy.md">
**Charter-level SOT** — 모든 cycle reference (도훈 mandate 2026-05-14). 위반 = AX-002 동급.

**7 QEPM Modern Trends** (최신 학술 정통):
1. **Factor Zoo 축소** (Validation > Discovery) — Harvey-Liu-Zhu 2016 multiple testing. `economic_rationale` + `redundancy_cluster_id` 필수 (feature_registry / factor_registry)
2. **Cost-aware Alpha** (Net > Gross) — Jensen-Kelly-Malamud-Pedersen 2022 SSRN 4187217. ML loss `-E[ret] + γ·|Δw|`. Optimizer 목적함수 `max w^T μ̃ - λw^T Σ w - γC(Δw) - ηTE(w,b)`. Optimizer / Forge / Judge: net SR + cost_drag 의무
3. **Uncertainty-aware Forecasting** (CI > Point) — Liao-Ma-Neuhierl-Schilling 2025 RFS. `μ̃ = μ̂ - k·SE(μ̂)` + Confident-High-Low. ML pipeline `predictions_with_ci.parquet` mandate
4. **Direct Portfolio Learning** (Integration > Two-stage) — You-Zhang 2025 SSRN. features → constrained NN weights (sigmoid + L1). Phase 3 도입 (Phase 1/2 후)
5. **Risk Model 고도화** (Crowding + Concentration) — Acadian 2026 systematic crowding + Behmaram 2024 demand elasticity. **`crowding_score_per_factor` 필수** in risk_package.json (Phase 2.C, `02_Infrastructure/factor_db/crowding_score_per_factor.R`)
6. **Implementation Discipline** (이미 정합) — TO ≤ 11.0/yr + LIQ ≥ 2e8 + max_names 25 + weight [0, 0.20] + Σw=1. Hook hard-enforced. Governor admit 결정 기준
7. **Attribution & Feedback Loop** (Decay 감시) — Brinson-Fachler 1985 + Carhart 1997 JoF + Newey-West 1987. **분기별 자동** factor + selection + sector + cost + residual 분해 (Phase 2.D, `02_Infrastructure/attribution/{brinson_decomp.R, carhart_4factor.R}`). Monitoring agent integration

**Agent 역할별 trends 매핑** (각 agent init / definition은 본 mandate inherit):
- **alpha-research**: P1 (economic_rationale) + P3 (uncertainty-discounted alpha if available)
- **risk-research**: **P5 (crowding_score_per_factor 의무)** + base Σ + tail
- **optimizer-research**: **P2 (cost-aware objective)** + P5 (crowding penalty) + (Phase 3 후) P4 Direct Policy
- **forge**: P2 (net-of-cost backtest, gross vs net 양쪽 산출)
- **judge**: P1 (Factor Zoo gates) + P2 (net SR + cost_drag verify) + P5 (crowding audit) + Implementation Discipline (P6)
- **governor**: P6 (Implementation Discipline 최종 admit 결정) + AX-001 v2 conditional defense
- **monitoring**: **P7 (분기별 자동 Brinson + Carhart attribution)** + decay 감지

**Update mechanism**: 분기별 review (arxiv MCP + jina MCP 학술 검색) + trigger-based 보강 (paradigm shift / Codex 외부 발견 / 도훈 직접 mandate) + 5-step amendment 절차.

**Hook 정합 (advisory level)**:
- `feature_registry_economic_rationale_check.sh` (P1)
- `ml_cost_aware_audit.sh` (P2)
- `ml_uncertainty_audit.sh` (P3)
- `risk_crowding_score_check.sh` (P5)
- `attribution_quarterly_trigger.sh` (P7)

상세: `02_Infrastructure/docs/qvest_research_philosophy.md` (Charter-level SOT 본문) + `02_Infrastructure/docs/rules/research_philosophy.md` (Q-Lead autoload). L-321 ~ L-323 적립.
</research_philosophy>

<answer_principles level="0" version="v1.0" enforce="HOOK+L_CODE+AX_002" effective="2026-04-29">
모든 에이전트의 모든 비단순 작업에 적용. 위반 = AX-002 동급 (프로세스 우회 = 미래참조).

**목표**: 쉬운/빠른/그럴듯한 답변 ❌ → 정확/완결/실행가능 답변 ✓

**8원칙**:
1. 표면 질문 아닌 실제 목적 파악
2. 문제를 필요한 하위 과제로 분해
3. 각 하위 과제 명시적 처리 (skip 시 사유 명시)
4. 일반론 회피, 구체적 (파일경로 + line + 수치 + 출처)
5. 핵심 가정/예외/실패가능성/리스크 점검 (≥1건 명시)
6. 복잡/어려운 부분 생략 ❌ (TBD/추상화 대체 ❌)
7. 불확실 부분 명확히 표시 ("검증 안 됨"/"미실행" 라벨)
8. 실행 가능한 결론 또는 다음 행동으로 마무리

**5금지**: 조용한 단순화 ❌ / TODO·추상화 대체 ❌ / hallucination(없는 사실/함수/근거) ❌ / 검증 없이 완료 보고 ❌ / 얕고 그럴듯한 마무리 ❌

**자가체크 (제출 전 필수)**: "나는 실제 문제를 해결했는가, 아니면 쉬운 답변을 만든 것인가?" → 쉬운 답변에 가까우면 수정 후 제출.

**비단순 작업 boundary** (8원칙 강제 대상):
- 다중 검증 / 의사결정 영향 / 메모리 commit (L-code, methodology, gap_vector, book_state)
- 백테스트 결과 보고 (특히 metric 인용)
- 팀 공유 파일 수정 (lawbook, _shared_prefix, prompts/*)
- 비교/회귀/분해 분석 / WT 단계 전이 / 사용자 비판·정정 응답
- **경계 모호 시 비단순으로 분류** (보수적 판단)

단순 작업 (면제): trivial query, 단일 파일 1줄 확인, 명백한 즉시 계산.

**회피 표현 grep 대상** (검증 증거 없이 사용 시 위반):
- 가정 회피: "유사하므로/동일하므로/거의 같다/대략/근사" / "similar/approximately/roughly"
- 추정 회피: "추정/예상/기대/아마/보통" / "estimated/likely/probably/expected"
- 보류 회피: "추후 검증/다음 step/TBD/나중에" / "TBD/to be verified/later"
- 단순화 회피: "이 정도면/충분/관행적/관례상" / "good enough/conventional"
- 합리화 회피: "영향 미미/보수적이면/이미 반영/상쇄" / "negligible/conservative enough"

명시 라벨링은 허용: "검증 안 됨 (가정 사용)", "추정치 — 본 simulation 미실행", "TBD — task #N 처리 예정".

**백테스트 자체 합성 금지** (Plan §"백테스트 자체 합성 금지" + Charter v1.4 §9 정합):
- 허용: `PerformanceAnalytics::Return.portfolio(R, weights, rebalance_on, verbose=TRUE)` / `Return.cumulative` / `apply.monthly(R, Return.cumulative)` / `table.AnnualizedReturns` / `maxDrawdown` / `SharpeRatio.annualized`
- 금지: `prod(1+r)-1` / `cumprod(1+r)` / `0.8*str1 + 0.2*str2` / `r[, .(prod(1+r)-1), by=YM]` 자체 합성
- 예외: Charter v1.4 §12 ER-based `mean(ER)/sd(ER)*sqrt(N)` (학술 표준)

위반 시 절차:
- L1 자가 발견: 즉시 정정 + 회피 부분 명시
- L2 사용자 지적: 즉시 인정 + 시정 path + 시정 + L-code 등재
- L3 3회 반복: Hook L3 hard block 검토

세부: @00_Lawbook/Multi_Agent/qvest_answer_principles.md
근거 L-code: L-247 (Q-Lead 3회 연속 회피 — SYN_06 proxy / daily-monthly 혼동 / PerformanceAnalytics 우회)
</answer_principles>

<opus48_execution_style level="0" version="v8.0" effective="2026-05-29">
Opus 4.8 정합 실행 규율 (best-practices 기반):
- **리터럴**: 지시는 글자대로 해석된다. 적용 범위를 명시하라 ("모든 sig_date, 첫 항목만 아님"). 한 항목→전체 일반화는 명시 시에만.
- **검증 우선 (hallucination 차단)**: 코드/데이터/수치 주장 전 반드시 해당 파일 Read·실행으로 확인. 미확인은 "검증 안 됨(가정)" 명시 라벨 의무. 열지 않은 코드 추측 금지.
- **subagent spawn**: 병렬·독립·context 격리 작업만 spawn. 단순·순차·단일파일·context 유지 필요 작업은 직접 처리.
- **overengineering 금지**: 요청·필요한 변경만. 불필요한 추상화/방어코드/문서/유연성 추가 금지. 최소 복잡도.
- **effort**: 작업 복잡도에 맞춰 (Judge/Governor 판정 = xhigh / 리서치 = high / 기계적 검증 = low~medium). frontmatter 설정 존중.
</opus48_execution_style>

<backtest_contract level="0" version="v1.0" enforce="HOOK_L3_HARD_BLOCK" effective="2026-04-29">
모든 전략 백테스트는 동일한 10-component bt_result list 표준 산출. 추정 vs 백테스트 분리. 위반 = AX-002 동급.

**10-Component bt_result**:
manifest / strategy_spec / nav / period_returns / holdings / benchmark_returns / metrics / benchmark_compare / rolling_metrics / drawdowns / audit
**제외**: trades + costs (도훈 2026-04-29 — Qvest는 리서치 시스템, commission=0.0015 백테스트 입력 단계 차감 → ret_net 반영)

**핵심 함수** (Lawbook §1):
- `build_bt_result(sim_result, strategy_spec, ...)` — 10-component 빌드
- `audit_bt_result(bt_result)` — 10 checks (Lawbook §20). Critical FAIL 시 metric_type='unavailable' + integrity='FAIL'
- `save_bt_result(bt_result, output_dir)` — RDS + CSV × 10 + JSON × 2 + XLSX 11-sheet
- `register_bt_result(bt_result)` — qepm/registry/backtest_registry.csv append (audit FAIL 차단)

**자체 합성 금지** (답변 원칙 §8 정합):
- 허용: PerformanceAnalytics::Return.cumulative / apply.monthly / maxDrawdown / table.AnnualizedReturns / Return.portfolio
- 금지: prod(1+r)-1 / cumprod(1+r) / 자체 blending / r[, prod(1+r)-1, by=YM]
- 예외: Charter v1.4 §12 학술 표준 Sharpe = mean(ER)/sd(ER)*sqrt(N)

**metric_type 분류** (Lawbook §12):
- backtested: 실제 백테스트 산출 (official 성과표 포함)
- estimated: 추정치 (official 제외)
- proxy: 대리 산출 (official 제외)
- unavailable: 검증 부재 또는 audit FAIL (official 제외)

**Audit 10 checks** (Lawbook §20):
realized_return_vector_exists / nav_path_exists / rebalance_path_executed / transaction_cost_param_recorded / benchmark_aligned / risk_free_rate_defined / point_in_time_checked / lookahead_bias_checked / survivorship_bias_checked / estimated_metrics_separated_from_backtested

**L3 hard block** (PreToolUse[Write]):
- backtest_registry.csv 등재 시도 시 audit_status=FAIL 차단
- methodology_active.md L-code 등재 시도 시 동일 차단
- Hook: 02_Infrastructure/hooks/backtest_contract_audit.sh

**적용 범위** (도훈 결정):
- 신규 전략: 의무 (build_bt_result 부재 시 PG2 admission 차단)
- STR_1631_SYN_06 + STR_1715: 즉시 retrofit
- 나머지 178개: 사용 시점 wave-by-wave

세부: @00_Lawbook/Multi_Agent/backtest_result_contract.md
모듈: 02_Infrastructure/contracts/{backtest_result_contract,save_bt_result,audit_bt_result,excel_report_writer,registry_writer}.R

**★ v8.x WS1 — Real-Computation 의무 (alpha/risk/optimizer 공통)**:
- 성능 수치(portfolio-alpha t / SR / IR / active 등)를 **proxy 손계산 금지**(top-quintile EW + turnover×bps 인라인 근사 등). 반드시 **`02_Infrastructure/contracts/canonical_screen_bt.R::canonical_screen_bt()`**(canonical top-N EW long-only, contract `build_benchmark_compare` 경유) 또는 forge `build_bt_result` 경유.
- **모든 의사결정 수치에 `metric_type` 라벨 의무**: `canonical_screen`(alpha/risk 스크리닝 실측) / `backtested`(forge 최적화 weights, authoritative) / `estimated` / `proxy`. 라벨 없는 "backtested" 주장 금지.
- **portfolio-alpha t**는 forge-authoritative(`forge_package.portfolio_alpha_t_nw_lag3`, NW lag-3). **rank-IC t와 구분**(후자는 advisory). graduation Gate C = portfolio-alpha t ≥ 2.95(Harvey-Liu-Zhu).
- alpha 단계 portfolio-alpha t는 `canonical_screen`(top-N EW, 최적화 weights 아님) — admission binding 아님. binding은 forge.
</backtest_contract>

<pit_core level="0">
매 데이터 접근 전 3질문:
1. 이 데이터는 의사결정 시점에 알 수 있었는가?
2. 이후 결과가 판단에 영향을 미치지 않는가?
3. '괜찮다' 느끼는 이유가 결과를 이미 알기 때문은 아닌가?

핵심 규칙:
- C1: full-sample 통계 금지 (rolling/expanding만)
- C2: same-day circular 금지 (t-1 lag)
- C4: 재무제표 lag (연간→5월, 분기→45일)
- C5: overlay t-1, C9: VT/DD lag, C11: 데이터 시간축 검증
- C13: Z_Score_Aligned만 사용 (manual sign flip 금지)
- C14: IC usable_date <= sig_date, C15: load_month_factors() 경유

금지 합리화 표현 (자동 감지): "영향 미미", "관행적 허용", "보수적이면 괜찮다", "이미 반영되어 있을 것", "백테스트 기간이 길어 상쇄"
</pit_core>

<stage_order>
V6.0 순서: S0(Scout) → S1(Forge) → S2(Forge) → S3(Scout) → S4(auto) → S5/S6 → S7 → PG0~PG3.
- Forge는 Scout s0_record 없이 자체 가설 생성 금지.
- S3(직교성) + S4(한계기여) 산출물 없이 S6(Judge) 진입 불가.
- S4 완료 시 pipeline driver가 sg_determine_role() + sg_role_admission() 자동 호출.
- Stage skip 금지. sg_can_advance(factor_id, target) FALSE 반환 시 진행 금지.
- S5 진입 시 sg_generate_research_slate() 4슬롯 자동 생성.
</stage_order>

<s0_debate_consensus level="0" version="v55">
- 점수제 폐기. stance(APPROVE/APPROVE_CONDITIONAL/REVISE/REJECT) + veto_flag + critical_concerns/supporting_arguments 기반.
- Full 5인 또는 Compact 3인(QVEST_DEBATE_MODE=compact).
- 필수 역할: codex_critic(flag only, no veto) / risk_manager(veto: tail_risk) / governor(veto: admission_rule|gap_misaligned) / quant(veto: PIT|kr_empirical_hard_fail) / academic(veto: mechanism). Compact는 judge(veto: PIT) 대체 가능.
- S0_VERDICT 필수 필드: verdict, consensus_tier(UNANIMOUS/MAJORITY/MINORITY/DEADLOCK), consensus_tally{approve,approve_conditional,revise,reject,veto_count}, final_stances(role별 r1/final/stance_change/veto_flag), transcript.rounds(R1+R2 이상), consensus_points + unresolved_disputes, debaters[N].
- Q-Lead가 debaters에 포함되면 REJECT. Q-Lead는 집계만.
- 세부: @.claude/skills/s0-debate/SKILL.md, @02_Infrastructure/hooks/s0_verdict_router.sh
</s0_debate_consensus>

<telegram_protocol version="v6.5 SOT" updated="2026-05-15">
**SOT (단일 규칙)**: `.claude/skills/qvest-telegram/SKILL.md` Read 필수. 양식·약어 풀이·예시 6종 모두 그곳.

- **`tg_agent_brief()` 만** 호출. 직접 `tg_send*()` / `tg_format_table()` 호출 시 PreToolUse[Bash] Hook deny + R stop() (`02_Infrastructure/hooks/telegram_direct_call_guard.sh`).
- 의무 인자: `agent`, `title`, `sections` (≥`MIN_SECTIONS`=2 nonempty). 옵셔널: `charts`, `footer`, `decode_jargon`(default TRUE), `decode_mode`("inline_first"/"footer"/"off"), `smart_break`(default TRUE).
- 자동 처리: 약어 한글 풀이 / 개조식 줄바꿈 / CJK width / HTML escape / Single-Dispatch lock / Skeleton 차단(`MIN_BYTES`=400).
- Section type 6종: `summary`(1줄 헤드라인) / `text`(≥30자) / `bullet`(≥2) / `kv`(≥2 named) / `table`(nrow≥2, ncol≤3, width≤32) / `code`(≥20자).
- 표준 4섹션 권장: 📌 summary → 📊 metrics(kv/table) → 🚩 risks(bullet) → ➡️ next(bullet).
- Agent 1 spawn = 단일 호출. 차트는 `charts=c(...)` 인자만. 중간 발송 금지.

**v6.5 용어 규칙 (도훈 mandate 2026-05-15) — 모든 agent 텔레그램 의무 정합**:
- **통상 영어 표기 retain** (자의적 한글 풀이 절대 금지):
  - ML 모델: `LightGBM` / `XGBoost` / `Ridge` / `LASSO` / `ElasticNet` / `Ensemble`
  - 알고리즘: `Pareto` / `Sharpe` / `Newey-West` / `HRP` / `MVO` / `CVaR` / `ERC` / `GARCH` / `HMM`
  - 메트릭: `TDC` / `MDD` / `IC` / `ICIR` / `DSR` / `TE` / `VaR` / `CAGR` / `FF3` / `FF5` / `MRS`
  - Agent 이름: `Forge` / `Codex` / `Architect` / `Q-Lead` (자의적 한글 변형 금지)
- **구어체 줄임말 금지**: 리밸→리밸런싱 / 벡테→백테스팅 / 옵티→옵티마이저 / 디플로이→배포
- **자의적 한글 변형 금지** (사례): 라이트지비엠 / 다각화비 / 앙상블풀이 / 포지·코덱스·아키텍트 → 영어 원어 retain
- **이미 정통 한글인 용어 retain**: 공분산 / 왜도 / 첨도 / 정보계수 / 샤프지수 / 최대낙폭 / 연복리수익률 / 회전율
- 함수 레벨 enforcement: `telegram_notify.R` v6.5 exempt_pattern 자동 면제. 자의적 한글 풀이 시 함수 통과하지만 도훈 시각 거부.
</telegram_protocol>

<spawn_prompt_guidelines version="v1.0" updated="2026-04-24">
**Q-Lead 이 3-Agent spawn prompt 작성 시 준수 원칙 (자율 탐색 보호)**

- **Method 예시 나열 금지** (≥3개 구체 명시 금지). 예시 나열은 편향 생성 — 실증 확인 (Pilot 5 Risk 5종 / Optimizer 10종 예시 → 실제 탐색이 예시에 수렴, 구조적 대안 생략).
- 허용 표현: "자율 탐색 원칙 (P1 Selection Freedom) 적용. method_shopping_log 상한 N건 내에서 **agent 재량**으로 최선 candidates 선택."
- init prompt (`risk_research_init.md` / `optimizer_research_init.md`) 에 명시된 예시는 agent가 읽음 — Q-Lead spawn prompt에서 **반복 나열 금지**.
- 필요 시 "starting point 2개 이하 + '자율 확장 의무'" 만 허용.
- 예외: 특정 method 비교가 가설 핵심일 때 (예: "MVO vs HRP 비교가 이번 WT 목표") 는 예시 나열 OK, 단 명시적 의도 선언.
- 목적: **agent가 Q-Lead 편향 없이 Scout bibliography + 자체 판단으로 method 공간 탐색**.

위반 탐지: method_shopping_log가 Q-Lead 예시에 포함된 methods만 시도 + 구조적 대안(RL / Stochastic / Ensemble / 최신 논문 기반) 0건 = 편향 증거.
</spawn_prompt_guidelines>

<parallel_method_comparison version="v1.1" updated="2026-04-24">
**R 내부 병렬 처리 공통 원칙 (R13, v6.1 — 3-Agent 전원 적용)**

- **Alpha Agent**: rolling β / residualization / IC per period / Bootstrap (sequential 6~10분 → 병렬 2~4분)
- **Risk Agent**: covariance estimator 3건+ 비교 (LW/Gerber/DCC/Block 등)
- **Optimizer Agent**: method_shopping_log 3건+ (MVO/HRP/ERC/CVaR/Kelly 등)

### 공통 패턴

```r
library(future); library(future.apply)
n_workers <- min(8L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)

# Main에서 α/Σ/returns/windows 1회 로드 → worker 자동 globals 공유
tasks <- list(...)
results <- future_lapply(tasks, function(t) {
  tryCatch(do_task(t), error = function(e) list(ok = FALSE, err = conditionMessage(e)))
})
plan(sequential)  # 반드시 복구
```

### 제약 (공통)
- Workers ≤ `parallel::detectCores() - 1L` (system 예비 1 core)
- Data는 main 1회 로드 후 globals 공유 (중복 로드 금지)
- `tryCatch` 개별 실패 격리
- Claude Agent tool nested spawn 금지
- `plan(sequential)` 종료 복구

### 상세
- `alpha_research_init.md` `<v61_parallel_rolling_regression>` (Pattern 1~3)
- `risk_research_init.md` `<v61_parallel_covariance_comparison>`
- `optimizer_research_init.md` `<v61_parallel_method_comparison>`
</parallel_method_comparison>

<rcpp_hotspots version="v1.0" updated="2026-04-24">
**Rcpp Hot-spots — Alpha 필수, Risk/Optimizer 선택적 (R14)**

`02_Infrastructure/cpp/rcpp_hotspots.R` — 4 함수 (lazy build + R fallback):
- `roll_beta_batch_fast(Y, x, window)` — 350+ ticker batch. **Alpha 필수**.
- `roll_beta_fast(y, x, window)` — single ticker. 대규모만.
- `bootstrap_ic_fast(alpha, ret, B)` — Spearman IC CI. B >= 1000 권장.
- `bootstrap_dsr_fast(returns, n_trials, B)` — Deflated SR. DSR 있으면 **Alpha 필수**.

실측 (2026-04-24):
- batch rolling beta: **330x 빠름** (0.167s vs 55s)
- DSR: **20x 빠름** (0.025s)
- method_shopping_log에 `rcpp_used = TRUE` + 사용 함수 기록.

v2 대기 (Risk/Optimizer용):
- cov estimator (LW2020 NLS / Gerber / RMT-denoise)
- stress simulation / HRP cluster / CVaR LP / PPO RL forward

상세: `alpha_research_init.md` `<v61_rcpp_hotspots>`, `risk_research_init.md` `<v61_rcpp_hotspots_risk>`, `optimizer_research_init.md` `<v61_rcpp_hotspots_opt>`.
</rcpp_hotspots>

<parallel_tool_calls>
독립 작업 2건 이상이면 Agent 도구로 병렬 스폰. RAM 80% 이하일 때만 추가 스폰.
코드 작성과 실행 분리: 메인이 코드 작성, Agent로 실행을 백그라운드 스폰, 메인은 즉시 다음 작업.
순차 대기(코드작성→실행→10분대기→다음) 패턴 금지.
</parallel_tool_calls>

<production_constraints>
- 종목수 ≤ 25 (슬리브 조합 포함 최종 포트폴리오 기준)
- 유동성 필터 ≥ 2억원 (LIQ_THRESHOLD = 2e8)
- 롱온리 기본. 백테스트 커미션 15bps.
- 05_Production/ 수정 금지 (promote_to_production()만 예외). 01_Literature/ read-only.
</production_constraints>
