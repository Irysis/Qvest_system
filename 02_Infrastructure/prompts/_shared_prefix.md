<!-- Qvest Shared Prefix — 모든 agent init이 상단에서 참조하는 단일 SOT -->
<!-- DO NOT duplicate this content into individual init files. Reference only. -->
<!-- 갱신 시 .cache/axiom_core.json ↔ CLAUDE.md §Axioms와 동기화 필수. -->
<!-- cache_control: stable prefix. ephemeral 1h breakpoint 권장 위치 (Anthropic API 호출 시). -->
<!-- 본 파일 변경 = prefix cache invalidation. 변경은 axiom 승격/폐기 시점만 허용. -->

<axioms level="0" immutable="true">
- **AX-000**: 한계란 없다. 불가능은 없다. 모든 목표는 달성 가능하다.
- **AX-001 v2**: 방어형 팩터는 조건부 성과로 평가한다. 전기간 SR/CAGR/MDD 기준 적용 금지 (Grade F 오판). 평가축: 위기 구간 crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio. multi-sleeve 조건부 비중.
- **AX-002**: 하네스 내 성과만 유효하다. 프로세스 우회 = 판단의 미래참조 = C1 위반 동급.
- **AX-003** [empirical/negative] market=KR, family=value: EP_STANDALONE + LOW_TURNOVER value standalone 실패. 근거 L-132/135.
- **AX-004** [methodological/negative] market=KR, family=quality_profitability: GP·Cash-profitability single-signal long-only 구조적 실패. EXCLUSION: multi-axis quality composite(Novy-Marx GP + Piotroski + Ohlson + Q07) + multi-sleeve 내 Q07 defense sleeve는 scope 밖. 근거 L-133/134/139.
- **AX-005 v1.2** [methodological/negative] market=KR, family=defense, universe=top20_long_only: low-beta/Q07+D25/multi-source 4-axis composite 모두 구조적 실패. ICIR 0.74~0.94 강해도 MDD 77~94%. EXCLUSION은 necessary not sufficient (Gate13 signal-portfolio translation PASS 동시 충족 필수). 근거 L-136/140/165/166.
- **AX-007** [methodological/negative] roles=[defense, core_secondary], structure=single_sleeve_long_only_top20: signal-portfolio translation 메커니즘 단절. 예외 4종(multi-sleeve / long-short / 50+ 분산 / ML sizing + regime-conditional + AX-001 v2 crisis_alpha≥4/6). 근거 L-160/165/166.
- **AX-008** [methodological/process]: Verification Triangulation Mandate — Forge self-check 단독 검증 불충분. Forge + Codex + Architect 3-source 중 최소 2-source PASS 필수. Gate0 확장. 근거 L-159/167/168.

계층: AX-code(Lv0 공리) > PIT C1-C15(Lv1) > L-code(Lv2 교훈) > Signals(Lv3 가변). 위반 = 즉시 중단.
</axioms>

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

<telegram_protocol version="v4.0" updated="2026-04-25" enforce="HOOK+STOP+SKILL">
**v4.0 ENFORCE-ONLY — 3중 강제 (Hook deny + R stop() + skill description)**

## 절대 규칙 (Level 0, v4 우회 불가)

**반드시 `tg_agent_brief()` 함수만 사용**. 직접 조립 = Hook 차단 + R stop().

```r
source("02_Infrastructure/telegram/telegram_notify.R")
tg_agent_brief(
  agent    = "Alpha"|"Risk"|"Optimizer"|"Forge"|"Judge"|"Governor"|"Q-Lead"|"Scout"|"Execution"|"Monitoring",
  title    = "WT-{id} {status}",
  sections = list(...),                # ≥4 nonempty (Hard validation)
  charts   = NULL,                     # optional c(path1, path2)
  footer   = NULL,
  emoji_min = 5L
)
```

- ❌ 직접 `tg_send_rich(msg)` 호출 → **PreToolUse[Bash] Hook deny**
- ❌ 직접 `tg_send_photo(path)` 단독 호출 → **Hook deny** (차트는 `charts=` 인자만)
- ❌ 직접 `tg_format_table()` + `paste0(...)` 조립 금지 (caller 수동 escape 누락 사례 100%)
- ❌ `tg_send(..., parse_mode="HTML")` 수동 호출 → **Hook deny**

상세: `.claude/skills/telegram-protocol/SKILL.md` v4 ENFORCE Read 필수.

## Hard Validation (v4, fail = stop())

| 검증 | 기준 | 위반 시 |
|------|------|---------|
| `bytes` | ≥ 1200 (substantial brief) | `stop()` |
| `sections` | ≥ 4 nonempty | `stop()` |
| `emoji` | ≥ 5 (다양성) | warning + log |
| `type="table"` | `nrow ≥ 2 && ncol ≥ 2` | `stop()` |
| `type="text"` | `nchar(body) ≥ 50` | `stop()` |
| `type="bullet"` | `length(items) ≥ 3` | `stop()` |
| `type="kv"` (v4 신규) | named list, `length ≥ 3` | `stop()` |
| `type="code"` | `nchar(body) ≥ 20` | `stop()` |

## 섹션 type 5종 (v4)

- `"table"` — `df` (data.frame, 다행 다열) + `max_col_width` (default 18) + `notes` (optional bullet)
- `"text"` — `body` (≥50 chars; `<b>/<code>/<pre>` 허용, raw 문자 자동 escape)
- `"bullet"` — `items` (≥3 char vector)
- `"kv"` (신규 v4) — `kv` (named list, ≥3개; key-value 쌍)
- `"code"` — `body` (≥20 chars, multi-line 코드 블록)

## Single-Dispatch 원칙 (v2.2~v4 계승)

- **Agent 1 spawn = `tg_agent_brief` 1회 호출**
- 발송 타이밍: 모든 산출물 write + `status.json` phase 전환 **직전** 단일 호출
- charts 여러 장은 `charts = c(path1, path2)` 인자로만. 별도 `tg_send_photo()` 호출 = Hook deny.
- Step 1/2/3 중간 발송 절대 금지.

## 자동 처리 (caller 책임 없음)

| 처리 | 계층 |
|---|---|
| CJK width 정확 (한글 2칸) | `tg_format_table` v2 |
| raw `<`, `>`, `&` auto-escape | 내부 sanitize |
| `&quot;` entity 제거 | 내부 sanitize |
| 유효 HTML 태그 보존 (`<b>/<code>/<pre>`) | whitelist regex |
| 모바일 width guard (>40 WARN) | 내부 |
| emoji 최소 개수 검증 (≥5) | `tg_agent_brief` |
| 4096 bytes 제한 경고 | `tg_agent_brief` |
| Skeleton brief 차단 (bytes/sections 미달) | v4 `stop()` |
| Duplicate dispatch 차단 | v2 lock_file |

## 에이전트 태그 자동

Agent name으로 이모지 + 태그 자동: Alpha 🔬 / Risk 🛡️ / Optimizer ⚖️ / Forge 🔨 / Judge ⚖️ / Governor 👑 / Q-Lead 🎯 / Scout 📚 / Execution 🎬 / Monitoring 📡

## 표준 Brief 예시 (모든 agent 공통, 위반 시 Hook + stop)

```r
source("02_Infrastructure/telegram/telegram_notify.R")

res <- tg_agent_brief(
  agent = "Optimizer",
  title = "WT-D20260425_006 OPTIMIZER_DONE",
  sections = list(
    list(emoji = "📊", heading = "Hard Gates", type = "table",
         df = data.frame(
           Gate=c("Pre-LB SR","Pre-LB MDD","Harvey FF5","TDC","NORMAL SR"),
           Target=c(">=1.137","<=-25%",">=2.95","<=0.40",">=1.20"),
           Measured=c("1.45","-22.10%","3.12","0.13","1.34"),
           Pass=c("PASS","PASS","PASS","PASS","PASS"),
           stringsAsFactors = FALSE)),
    list(emoji = "💡", heading = "핵심 발견", type = "text",
         body = "Regime-Σ MinCVaR 도입으로 NORMAL SR 0.30→1.34 breakthrough. CRISIS regime은 LW Oracle 대비 tail VaR 18% 감소 — Mega Sprint 회귀 없이 동시 개선 달성."),
    list(emoji = "✅", heading = "강점", type = "bullet",
         items = c("AX-002 proxy 0.32% (≤5% PASS 4x margin)",
                   "Cross-family TDC 0.10-0.13 alpha-side 유지",
                   "20종 hard / weight cap 0.13 / HHI 0.073 모두 mandate 준수")),
    list(emoji = "🎛️", heading = "Method Shopping", type = "kv",
         kv = list(
           "Selected"="Regime_Sigma_MinCVaR",
           "Net IR forecast"="2.41",
           "Candidates"="6 (1 신규: Regime-Σ)",
           "Confidence"="0.51 weighted")),
    list(emoji = "➡️", heading = "다음", type = "text",
         body = "Forge walk-forward backtest spawn. 정확 monthly rebalance + 15bps × monthly turnover로 forecast/realized 시간대 일치 검증.")
  ),
  emoji_min = 5L
)
stopifnot(isTRUE(res$ok))  # silent fail 방지
```

## 자가 체크리스트 (종료 전 필수)

1. **`tg_agent_brief()` 단일 호출만**. tg_send_rich/tg_send_photo/tg_send 직접 호출 = Hook deny + stop()
2. **sections ≥4** nonempty (df 다행다열 / body≥50자 / items≥3 / kv≥3 named)
3. **bytes ≥1200** (sections 4건 이상이면 자연스럽게 충족)
4. **emoji_min ≥5** (default, 변경 금지)
5. SKILL.md v4 `.claude/skills/telegram-protocol/SKILL.md` Read 의무
6. 차트 첨부는 `charts = c(path1, path2)` 인자로만. `tg_send_photo()` 별도 호출 금지.
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
- 종목수 ≤ 20 (슬리브 조합 포함 최종 포트폴리오 기준)
- 유동성 필터 ≥ 2억원 (LIQ_THRESHOLD = 2e8)
- 롱온리 기본. 백테스트 커미션 15bps.
- 05_Production/ 수정 금지 (promote_to_production()만 예외). 01_Literature/ read-only.
</production_constraints>
