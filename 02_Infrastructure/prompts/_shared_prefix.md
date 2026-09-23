<!-- Qvest Shared Prefix — 모든 agent init이 상단에서 참조하는 단일 SOT -->
<!-- DO NOT duplicate this content into individual init files. Reference only. -->
<!-- 갱신 시 .cache/axiom_core.json ↔ CLAUDE.md §Axioms와 동기화 필수. -->
<!-- cache_control: stable prefix. ephemeral 1h breakpoint 권장 위치 (Anthropic API 호출 시). -->
<!-- 본 파일 변경 = prefix cache invalidation. 변경은 axiom 승격/폐기 또는 세션 경계 정합 개정 시점만 (2026-07-24 C6). -->
<!-- (2026-07-24 도훈 승인 C6) 중복 대수술: answer_principles·backtest_contract·telegram = rule/SOT 포인터 스텁 전환 -->
<!--   (드리프트 방지 — 전문 사본 재생성 금지, rule 파일이 유일 전문). stage_order·s0_debate = v6.0/v55 사멸로 삭제. -->

<axioms level="0" immutable="true" injection="hook-authoritative">
<!-- (P0 이중주입 소거 2026-07-04 감사) axiom 본문(statement)의 *실주입*은 PreToolUse[Agent] 훅 -->
<!-- `02_Infrastructure/hooks/axiom_context_inject.sh`가 additionalContext로 라이브 수행한다.       -->
<!-- 과거 이 블록이 본문을 정적 임베드 → 훅 additionalContext와 이중 주입 → 예산(2500자) 낭비+중복.  -->
<!-- 따라서 본 블록은 이제 *참조 스텁*: ID·계층·polarity 인덱스만 남기고 본문은 훅 단일 출처로 통일. -->
<!-- 문서-권위(hard-fail SOT)는 여전히 `.claude/rules/axioms.md` ↔ active/*.json (sot_map). -->
활성 공리(본문 = 훅 주입, 여기선 인덱스만). **active Law 4건**:
- **AX-000** [IMMUTABLE] · **AX-001 v3** [defensive-disposition — 전기간 등급 단독 처분 금지 · defensive_score 계약] · **AX-002** [IMMUTABLE]
- **AX-008 v2.0** [process] 결정 수치는 계약 산출만 인용 · 독립 검증 = Judge
- (2026-09-23 개정 — 도훈 AX-D5-TEXT. 구 AX-001 v2/v2.1 · AX-008 v1.1 '3-source 2/3' 는 각 JSON `history` 사료)

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
6. **Implementation Discipline** (이미 정합) — TO ≤ 11.0/yr + LIQ ≥ 2e8 + max_names 25 + Σw=1 (v10 2026-08-29: 종목별 비중 상한 폐지). Hook hard-enforced. Governor admit 결정 기준
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

<answer_principles level="0" version="v2.0-stub" enforce="HOOK+L_CODE+AX_002" effective="2026-04-29" updated="2026-07-24">
**SOT = `02_Infrastructure/docs/rules/answer-principles.md` — 비단순 작업 착수 전 Read 의무.** (2026-08-23 v9 이동 — 구 경로 `.claude/rules/`. lean 라운드는 3호만 적용 — `.claude/rules/lean-loop.md`) 위반 = AX-002 동급. (2026-07-24 도훈 승인 C6: 전문 사본이 rule 대비 드리프트(07-13 리서치 연속성 6항·금칙표현 누락) 발생해 포인터화 — 사본 유지 금지, rule 파일이 유일 전문.)

핵심 인덱스: 8원칙(실제 목적·분해·명시 처리·구체성·리스크 점검·생략 금지·불확실 라벨·실행가능 결론) + 5금지(조용한 단순화/TODO 대체/hallucination/무검증 완료/얕은 마무리) + 회피표현 grep + 백테스트 자체합성 금지(PerformanceAnalytics 표준만) + 리서치 연속성(next_probe≥2·종결어휘 금지) + 금칙표현.

위반 시 절차 (prefix 고유 — 보존):
- L1 자가 발견: 즉시 정정 + 회피 부분 명시
- L2 사용자 지적: 즉시 인정 + 시정 path + 시정 + L-code 등재
- L3 3회 반복: Hook L3 hard block 검토
근거 L-code: L-247.
</answer_principles>

<execution_style level="0" version="v8.3.1" effective="2026-05-29" updated="2026-07-24">
세션 모델 정합 실행 규율 (현행 Fable 5 — 모델 불문 적용, 구 태그명 opus48_execution_style):
- **리터럴**: 지시는 글자대로 해석된다. 적용 범위를 명시하라 ("모든 sig_date, 첫 항목만 아님"). 한 항목→전체 일반화는 명시 시에만.
- **검증 우선 (hallucination 차단)**: 코드/데이터/수치 주장 전 반드시 해당 파일 Read·실행으로 확인. 미확인은 "검증 안 됨(가정)" 명시 라벨 의무. 열지 않은 코드 추측 금지.
- **subagent spawn**: 병렬·독립·context 격리 작업만 spawn. 단순·순차·단일파일·context 유지 필요 작업은 직접 처리.
- **overengineering 금지**: 요청·필요한 변경만. 불필요한 추상화/방어코드/문서/유연성 추가 금지. 최소 복잡도.
- **effort**: 작업 복잡도에 맞춰 (Judge/Governor 판정 = xhigh / 리서치 = high / 기계적 검증 = low~medium). frontmatter 설정 존중.
- **모델**: frontmatter model 핀 금지(세션 모델 상속 — 2026-07-24). 한도/스폰 실패 시 opus 폴백(도훈 07-14).
</execution_style>

<backtest_contract level="0" version="v2.0-stub" enforce="HOOK_L3_HARD_BLOCK" effective="2026-04-29" updated="2026-07-24">
**SOT = `.claude/rules/backtest-contract.md`(10-component 계약) + `.claude/rules/measurement-graduation.md` §1~§4(real-computation·graduation HARD) — 백테/측정 작업 착수 전 Read 의무.** 위반 = AX-002 동급. (2026-07-24 도훈 승인 C6: 축자 사본 포인터화 — rule 파일이 유일 전문.)

절대 최소 인덱스 (상세·예외는 SOT):
- **10-component `bt_result`**는 `02_Infrastructure/contracts/build_bt_result()` 경유만. audit FAIL 시 metric_type='unavailable'.
- **자체합성 금지**: `prod(1+r)-1`/`cumprod`/자체 blending 금지 — PerformanceAnalytics 표준 함수만.
- **Real-Computation 의무**: 성능 수치 proxy 손계산 금지 — `canonical_screen_bt()` 또는 forge `build_bt_result` 경유 + 모든 의사결정 수치에 `metric_type` 라벨(canonical_screen/backtested/estimated/proxy).
- **portfolio-alpha t = forge-authoritative**(NW lag-3, graduation Gate C ≥ 2.95). rank-IC t는 advisory. alpha 단계 수치는 canonical_screen 라벨 — admission binding은 forge.
- Hook: `backtest_contract_audit.sh` (L3 hard block — registry/L-code 등재 시 audit FAIL 차단).
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

<!-- (2026-07-24 도훈 승인 C6) <stage_order>·<s0_debate_consensus> v6.0/v55 legacy 블록 삭제 —
     S0~S7 stage 스킬 8종은 2026-07-05 삭제·/scout 2026-06-10 제거로 절차 실체 부재.
     역사 = git + qvest_legacy_boundary.md. 현행 진입점 = CLAUDE.md Active Entrypoints(4-Mode). -->

<telegram_protocol version="v7-stub" updated="2026-07-24">
**SOT = `.claude/skills/qvest-telegram/SKILL.md` (v7) — 텔레그램 발송 전 Read 의무.** 양식·섹션 타입·약어/용어 규칙·비전공자 3장치·예시 전부 그곳. (2026-07-24 도훈 승인 C6: 구 v6.5 축자 사본 포인터화 — 버전 불일치 드리프트 해소.)
- **`tg_agent_brief()` 만** 호출 — 직접 `tg_send*()` 호출은 PreToolUse[Bash] Hook deny(`telegram_direct_call_guard.sh`).
- Agent 1 spawn = 단일 호출. 차트는 `charts=c(...)` 인자만. 용어는 통상 영어 표기 retain(자의적 한글 풀이 금지 — 상세 SOT).
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

<!-- (v9 Lean Loop 2026-08-23) 생성 블록 distilled_map 제거.
     사유: 이 블록은 negative/conditional DIST 카드 top-5 를 모든 agent 의 의무 pull 면에
     싣고 있었다 — 주입 훅과 합쳐 "죽은 방향 재제안 금지" 가 지식 입력의 대부분을 차지.
     v9 은 양성 지식(통한 전략 + 최근 교훈)을 주입면으로 쓰고, 음성 지식은 착수 전
     `Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <kw>` 1줄 조회로 강등한다.
     카드 자체는 06_Registry/distilled_knowledge.json 에 그대로 있고 삭제 아님(INV-7 보존).
     생산자 build_distilled_usage.py 는 .cache/distilled_usage.json 만 계속 쓴다. -->
