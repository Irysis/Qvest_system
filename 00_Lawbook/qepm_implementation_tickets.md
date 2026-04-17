# QEPM Multi-Agent System — Implementation Ticket Set
# Claude Code에 Phase별로 전달하여 순차 구현

> **사용법**: 각 Phase를 Claude Code 세션에 이 파일 전체 + Lawbook zip과 함께 전달하고,
> "Phase N을 구현해줘"라고 요청한다.
> Phase 0부터 순서대로 진행한다. 각 Phase 완료 후 테스트 통과를 확인하고 다음으로 넘어간다.

---

# 프로젝트 컨텍스트

## 목표
QEPM Lawbook v1.4.2를 기반으로, 퀀트 투자 리서치 → 전략 구현 → 백테스트 → 심사 → 개선 루프 → 월간 리밸런싱을 자동화하는 멀티 에이전트 시스템을 구축한다.

## 최종 목표 지표
- 한국시장 포트폴리오 CAGR 16%+, Sharpe 2+, MDD < 25%
- FF3/Carhart4/FF5 및 Fama–MacBeth 통계 검증 통과

## 기술 스택 (확정)
- **코어 언어**: R (모든 퀀트 로직, 백테스트, 팩터 모델)
- **오케스트레이션**: R + Anthropic Messages API (httr2)
- **저장소**: JSON 파일 (기억/레지스트리) + DuckDB (데이터레이크/피처스토어)
- **LLM API**: Anthropic Claude (Haiku/Sonnet/Opus 차등 사용)
- **설정/프롬프트**: YAML + Markdown
- **테스트**: testthat
- **환경**: 로컬 (보안 우선, 인터넷은 허용 API만)

## 디렉토리 구조 (Phase 0에서 생성)

```
qepm/
├── DESCRIPTION
├── NAMESPACE
├── R/
│   ├── agents/           # 에이전트별 실행 로직
│   ├── memory/           # 기억 증류 파이프라인
│   ├── orchestration/    # 오케스트레이션 엔진
│   ├── tools/            # 에이전트 도구 함수
│   ├── backtest/         # 백테스트 하네스
│   └── utils/            # 공통 유틸리티
├── inst/
│   ├── prompts/          # 시스템 프롬프트 + 검증 프롬프트
│   │   ├── system/       # 에이전트별 시스템 프롬프트
│   │   └── verification/ # 증류 검증 프롬프트
│   ├── lawbook/          # Lawbook .md 파일들 (원본)
│   ├── config/           # 설정 YAML
│   └── schemas/          # JSON 스키마
├── data/
│   ├── raw/              # L0 immutable
│   ├── staging/          # L1 normalized
│   ├── features/         # L2 PIT
│   └── universe/         # L3 tidy
├── memory/
│   ├── raw_artifacts/    # R0
│   ├── episodes/         # R1 experiment digests
│   ├── families/         # R2 family/mechanism memory
│   ├── evidence/         # R3 statistical evidence
│   ├── regime_payoff/    # R4
│   ├── portfolio_policy/ # R5
│   ├── post_trade/       # R6
│   └── lessons/          # L-### lessons
├── registry/
│   ├── experiments.json  # experiment registry (15장)
│   ├── strategies.json   # strategy lifecycle (17장)
│   ├── families.json     # family accounting (16장)
│   └── backlog.json      # research backlog
├── artifacts/            # 태스크별 산출물
├── logs/                 # 실행 로그
├── tests/
│   └── testthat/
└── scripts/              # 실행 스크립트
```

## 핵심 설계 원칙 (Anthropic + Lawbook 교차)

1. **목적함수 우선순위**: Validity > Implementability > Robustness > Performance > Novelty
2. **Hard Law / Soft Prior 분리**: Hard Law는 코드에서 강제, Soft Prior는 기억으로 관리
3. **산출물 없는 진척 금지**: 모든 에이전트 실행은 artifact를 남겨야 함
4. **3-Layer Context Injection**: System Prompt(고정) + Task Context(동적) + Just-in-Time Retrieval(도구)
5. **deliverable_format 차등**: concise/detailed/stats_only로 토큰 효율 관리
6. **기억 = 연구 결과 우선**: 대화 기억이 아니라 실험 결과 중심 장기기억

---

# Phase 0: Project Scaffolding + Infrastructure

## 목표
프로젝트 디렉토리 구조, R 패키지 뼈대, 설정 파일, Lawbook 파싱 인프라를 구축한다.

## 구현 항목

### 0-1. R 패키지 초기화
- `DESCRIPTION` 파일 생성 (패키지명: qepm)
- 의존성: httr2, jsonlite, yaml, DBI, duckdb, digest, testthat, glue, cli, logger
- `NAMESPACE` 생성

### 0-2. 디렉토리 구조 생성
- 위 구조대로 모든 디렉토리 생성
- 각 디렉토리에 `.gitkeep` 또는 `README.md` 배치

### 0-3. 설정 파일 (`inst/config/`)

**`config.yaml`:**
```yaml
project:
  name: "QEPM Multi-Agent System"
  version: "1.4.2"
  market: "KR"
  language: "R"
  rebalance_freq: "monthly"
  benchmark: "KOSPI200_TR"

llm:
  provider: "anthropic"
  models:
    distill_light: "claude-haiku-4-5-20251001"
    distill_medium: "claude-sonnet-4-6"
    distill_heavy: "claude-opus-4-6"
    verify: "claude-haiku-4-5-20251001"
    orchestrate: "claude-sonnet-4-6"
  api_key_env: "ANTHROPIC_API_KEY"
  max_tokens_default: 4096
  prompt_caching: true

memory:
  token_budget:
    total: 8000
    schema: 500
    stat_evidence: 1500
    regime_payoff: 1500
    portfolio_policy: 1500
    recent_digests: 2000
    working: 1000
  promotion:
    r1_auto: true
    r2_min_experiments: 3
    r4_min_regime_months: 24
    r4_low_confidence_threshold: 0.3
    r4_med_confidence_threshold: 0.5
  verification:
    r0r1_model: "verify"
    r1r2_model: "distill_medium"
    r1r3_model: "verify"
    r4_model: "distill_medium"
    r5_model: "distill_medium"
    r6_model: "verify"
    max_retries: 2

orchestration:
  max_wip: 3
  daily_chunk_limit: 20
  loop_default: "on"
  mode_default: "research"
  production_window_days: [1, 2, 3]

research:
  budget_split:
    exploit: 0.50
    orthogonal: 0.30
    counterfactual: 0.20
  family_concentration_cap: 0.40
  cooldown_after_fails: 3

kpi:
  sharpe_primary: "sharpe0_m_ann"
  tail_primary: "es99_m"
  sharpe_secondary: "sharpe0_d_ann"
  tail_secondary: "es99_d"
  target_cagr: 0.16
  target_sharpe: 2.0
  target_mdd: -0.25

briefing:
  triggers:
    sharpe_improvement: 0.10
    es99_improvement: 0.003
    mdd_improvement: 0.02
    turnover_improvement: 1.0
  dedup_window_hours: 24
  daily_max: 12
```

### 0-4. Lawbook 파싱 인프라 (`R/tools/lawbook.R`)

```r
# inst/lawbook/ 에 Lawbook .md 파일들을 배치한다고 가정
# 이 모듈은 에이전트가 Just-in-Time으로 Lawbook 특정 장을 로드하는 도구

#' Lawbook 특정 장/섹션 로드
#' @param chapter 장 번호 ("00", "06", "25") 또는 키워드
#' @param section 특정 섹션 (예: "Gate4", "R2"). NULL이면 전체 장.
#' @param format "concise" (핵심 규칙만) 또는 "full" (전체)
#' @return list(content, token_count, chapter_title)
lawbook_lookup <- function(chapter, section = NULL, format = "concise") {
  # 구현: inst/lawbook/ 에서 해당 .md 파일을 읽고,

  # section이 있으면 해당 섹션만 추출,
  # format == "concise"이면 LLM으로 요약하지 않고
  # 사전 준비된 concise 버전을 반환 (inst/lawbook/concise/ 디렉토리)
}

#' Lawbook 키워드 검색
#' @param query 검색 키워드
#' @param top_k 반환할 섹션 수
#' @return list of matching sections with chapter/section/snippet
lawbook_search <- function(query, top_k = 3) {
  # 구현: 단순 grep 기반 검색 (벡터DB 아님, 로컬 우선)
}
```

### 0-5. Anthropic API 래퍼 (`R/utils/llm_api.R`)

```r
#' Anthropic Messages API 호출
#' @param messages list of list(role, content)
#' @param model 모델 키 ("verify", "distill_light", "distill_medium", "distill_heavy")
#' @param system system prompt 문자열
#' @param max_tokens 최대 토큰
#' @param temperature 온도 (기본 0)
#' @param response_format "text" 또는 "json"
#' @return 파싱된 응답 (text 또는 list)
call_llm <- function(messages, model = "distill_light", system = NULL,
                     max_tokens = NULL, temperature = 0,
                     response_format = "text") {
  # config.yaml에서 모델명 resolve
  # httr2로 API 호출
  # response_format == "json"이면 jsonlite::fromJSON으로 파싱
  # 에러 핸들링 + 재시도 (429/500)
  # 토큰 사용량 로깅
}

#' 토큰 수 추정 (근사)
#' @param text 문자열
#' @return 추정 토큰 수
estimate_tokens <- function(text) {
  # 한국어+영어 혼합: 대략 문자수/2.5 (근사)
  ceiling(nchar(text) / 2.5)
}
```

### 0-6. 공통 유틸리티 (`R/utils/common.R`)

```r
#' SHA256 해시 생성
artifact_hash <- function(file_path) {
  digest::digest(file = file_path, algo = "sha256")
}

#' 타임스탬프 생성 (KST)
now_kst <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00", tz = "Asia/Seoul")
}

#' JSON 안전 읽기/쓰기
read_json_safe <- function(path) {
  if (!file.exists(path)) return(NULL)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

write_json_safe <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE)
}

#' 태스크 ID 생성
generate_task_id <- function(prefix = "TASK") {
  glue::glue("{prefix}_{format(Sys.Date(), '%Y%m%d')}_{sprintf('%04d', sample(1:9999, 1))}")
}

#' 전략 fingerprint 생성
strategy_fingerprint <- function(spec) {
  # spec의 핵심 정의 필드를 정렬+직렬화 후 해시
  key_fields <- spec[c("universe", "factor_family", "signal_formula",
                        "rebalance_rule", "n_holdings", "weighting_rule",
                        "risk_overlay", "buffer_rule", "cost_model", "benchmark")]
  digest::digest(key_fields, algo = "sha256")
}
```

## 산출물
- 위 디렉토리 구조 전체
- `DESCRIPTION`, `NAMESPACE`
- `inst/config/config.yaml`
- `R/tools/lawbook.R`
- `R/utils/llm_api.R`
- `R/utils/common.R`
- `tests/testthat/test-utils.R` (해시/타임스탬프/JSON 기본 테스트)

## 검증 기준
- `devtools::load_all()` 성공
- `testthat::test_dir("tests/testthat")` 전체 PASS
- `config.yaml` 로드 시 모든 필드 접근 가능

---

# Phase 1: Memory Pipeline R0/R1 + Verification

## 목표
실험 종료 시 raw artifacts를 R0에 저장하고, experiment_digest.json을 자동 생성하며,
hallucination/loss/distortion 검증을 수행하는 파이프라인을 구축한다.

## 선행 조건
- Phase 0 완료

## 구현 항목

### 1-1. R0 Raw Artifact Store (`R/memory/r0_store.R`)

```r
#' R0: Raw artifact 저장 (immutable)
#' @param exp_id 실험 ID
#' @param artifacts named list: name → file_path
#' @param metadata list(data_snapshot_id, code_version, parameters, metric_version)
#' @return R0 저장 경로
r0_store <- function(exp_id, artifacts, metadata) {
  # 1. memory/raw_artifacts/{exp_id}/ 디렉토리 생성
  # 2. 각 artifact 파일 복사 (원본 보존)
  # 3. 각 파일의 hash 계산
  # 4. manifest.json 생성: {exp_id, stored_at, files: [{name, hash, size}], metadata}
  # 5. manifest.json도 함께 저장
  # 6. 저장 후 파일 쓰기 권한 제거 (immutable 강제, Sys.chmod)
}
```

### 1-2. R1 Experiment Digest Generator (`R/memory/r1_distill.R`)

```r
#' R1: Experiment Digest 생성
#' @param exp_id 실험 ID
#' @param backtest_report_path backtest_report.md 경로
#' @param risk_audit_path risk_audit.json 경로 (있으면)
#' @param stat_defense_path stat_defense_report.md 경로 (있으면)
#' @param strategy_spec_path strategy_spec.md 경로
#' @return experiment_digest.json 경로
r1_distill <- function(exp_id, backtest_report_path, risk_audit_path = NULL,
                       stat_defense_path = NULL, strategy_spec_path = NULL) {
  # 1. 원시 파일들을 읽어서 LLM 입력 구성
  # 2. 증류 프롬프트 로드 (inst/prompts/distill_r1.yaml)
  # 3. call_llm(model = "distill_light", response_format = "json")
  # 4. 결과를 experiment_digest.json으로 저장
  # 5. r1_verify() 호출
  # 6. 검증 PASS면 memory/episodes/{exp_id}.json 에 저장
  # 7. 검증 FAIL이면 재증류 (최대 2회)
}
```

**증류 프롬프트 (`inst/prompts/distill_r1.yaml`):**

```yaml
system: |
  당신은 QEPM 실험 증류기다. 아래 원시 산출물을 읽고
  experiment_digest.json 형식으로 압축한다.

  반드시 지킬 규칙:
  - 수치는 원시 산출물의 값을 그대로 옮긴다 (반올림/변환 금지)
  - grade/verdict/role은 risk_audit의 판정을 그대로 따른다
  - 존재하지 않는 alpha test 결과를 만들지 않는다
  - fail_reasons는 risk_audit에 기록된 것만 포함한다
  - artifact_paths는 실제 존재하는 파일만 기록한다

  출력 형식 (JSON only, 다른 텍스트 금지):
  {
    "exp_id": "...",
    "strategy_id": "...",
    "family": "...",
    "construction": {
      "rebalance": "...",
      "weighting": "...",
      "buffer_zone": bool,
      "cooldown": int,
      "neutralization": "..."
    },
    "metrics": {
      "net_cagr": float,
      "sharpe0_m_ann": float,
      "mdd": float,
      "es99_m": float,
      "turnover_ann": float,
      "ic_mean": float | null,
      "icir": float | null
    },
    "alpha_tests": {
      "ff3_alpha": float | null,
      "ff3_t": float | null,
      "carhart4_alpha": float | null,
      "carhart4_t": float | null,
      "ff5_alpha": float | null,
      "ff5_t": float | null,
      "fmb_slope": float | null,
      "fmb_t": float | null
    },
    "grade": "A" | "B" | "C" | "F",
    "role": "core" | "defensive" | "diversifier" | null,
    "verdict": "PASS" | "FAIL" | "NEAR_MISS",
    "fail_reasons": [...],
    "artifact_paths": [...]
  }

user_template: |
  ## 원시 산출물

  ### Strategy Spec
  {strategy_spec}

  ### Backtest Report
  {backtest_report}

  ### Risk Audit
  {risk_audit}

  ### Statistical Defense
  {stat_defense}
```

### 1-3. R1 Verification (`R/memory/r1_verify.R`)

```r
#' R1 Digest 검증
#' @param digest_path 생성된 digest JSON 경로
#' @param raw_artifact_dir R0 원시 산출물 디렉토리
#' @return list(verdict, action, details)
r1_verify <- function(digest_path, raw_artifact_dir) {
  # 1. digest와 원시 산출물을 함께 로드
  # 2. 검증 프롬프트 로드 (inst/prompts/verification/ver_r0r1.yaml)
  # 3. call_llm(model = "verify", response_format = "json")
  # 4. verdict에 따라:
  #    - PASS: 그대로 반환
  #    - FAIL_MINOR: re_distill 액션 반환
  #    - FAIL_SEVERE: escalate 액션 반환 + 로그
}
```

**검증 프롬프트 (`inst/prompts/verification/ver_r0r1.yaml`):**

```yaml
system: |
  당신은 QEPM 기억 검증관이다.
  [원시 산출물]과 [생성된 요약]을 비교하여 3가지를 판단한다.

  1. HALLUCINATION: 요약에 원시에 없는 수치/등급/역할/검증 결과가 있는가?
     - 수치는 소수점 3자리까지 일치해야 한다.
  2. INFORMATION_LOSS: 필수 항목이 누락되었는가?
     필수: exp_id, strategy_id, family, data_snapshot_id,
           metrics(net_cagr, sharpe0_m_ann, mdd, es99_m, turnover_ann),
           verdict, fail_reasons(FAIL시), artifact_paths(최소 1개)
  3. DISTORTION: grade/verdict/role 방향이 원시와 일치하는가?

  출력 (JSON only):
  {
    "hallucination": {"detected": bool, "details": [...]},
    "information_loss": {"detected": bool, "missing_fields": [...]},
    "distortion": {"detected": bool, "details": [...]},
    "verdict": "PASS" | "FAIL_MINOR" | "FAIL_SEVERE",
    "action": "accept" | "re_distill" | "escalate"
  }

user_template: |
  ## 원시 산출물
  {raw_content}

  ## 생성된 Digest
  {digest_content}
```

### 1-4. Experiment Registry 연결 (`R/memory/registry.R`)

```r
#' Registry에 실험 레코드 추가
#' @param digest experiment_digest (list)
#' @return 업데이트된 registry
registry_add_experiment <- function(digest) {
  # registry/experiments.json에 레코드 append
  # 중복 exp_id 체크
  # family_trial_count 업데이트 → registry/families.json
}

#' Registry 검색
#' @param family family 이름
#' @param verdict 필터 (PASS/FAIL/NEAR_MISS)
#' @param top_k 최대 반환 수
registry_search <- function(family = NULL, verdict = NULL, top_k = 20) {
  # registry/experiments.json에서 조건 필터링
}

#' Family trial count 조회
registry_family_trials <- function(family) {
  # registry/families.json에서 해당 family의 trial_count, pass_count, fail_streak 반환
}
```

## 산출물
- `R/memory/r0_store.R`
- `R/memory/r1_distill.R`
- `R/memory/r1_verify.R`
- `R/memory/registry.R`
- `inst/prompts/distill_r1.yaml`
- `inst/prompts/verification/ver_r0r1.yaml`
- `tests/testthat/test-memory-r0r1.R`

## 검증 기준
- 예시 backtest_report.md + risk_audit.json을 넣으면 digest JSON이 생성됨
- digest의 수치가 원시와 소수점 3자리까지 일치
- 의도적으로 수치를 변조한 digest를 넣으면 verification이 FAIL 반환
- registry에 레코드가 정상 추가됨

---

# Phase 2: Orchestration Engine

## 목표
에이전트 간 메시지 발행/수신, 상태 관리, 작업 큐를 구현한다.
10장 메시지 스펙의 강화 버전(deliverable_format, memory_context, fail_guidance)을 반영한다.

## 선행 조건
- Phase 0, 1 완료

## 구현 항목

### 2-1. 메시지 생성/파싱 (`R/orchestration/messages.R`)

```r
#' 작업 발행 메시지 생성
create_task_message <- function(
  issuer, assignee, objective,
  inputs, constraints, deliverables,
  task_family = NULL,
  mode = "research",
  priority_score = 0.5,
  deliverable_format = "concise",
  memory_context = NULL,
  quality_gates = NULL,
  fail_guidance = NULL
) {
  # 10장 Enhanced Message Spec에 따라 JSON 구조 생성
  # task_id 자동 생성
  # idempotency_key = hash(inputs + constraints + objective)
  # artifact_hashes 자동 계산
  # metric_version, cost_model_version, factor_model_version은 config에서 로드
}

#' 작업 응답 메시지 생성
create_response_message <- function(
  task_id, respondent, state,
  result_summary,
  deliverables,
  memory_promotion_candidates = NULL,
  next_actions = NULL,
  compute_metrics = NULL
) {
  # deliverables는 {name: {path, hash, token_count}} 형태
}

#' Memory Pipeline 이벤트 생성
create_memory_event <- function(
  event_type,  # EPISODE_CREATED, FACT_PROMOTED, DISTILLATION_VERIFY_FAIL 등
  source_task_id,
  stage,
  target_id,
  digest_summary = NULL,
  promotion_eligible = NULL,
  verification_required = TRUE
) {}
```

### 2-2. 상태 관리 (`R/orchestration/state.R`)

```r
#' 글로벌 상태 관리자
#' 상태: BOOT → MEMORY_LOAD → BACKLOG_REFRESH → DISPATCH → RUN_CHUNK →
#'       EVALUATE → MEMORY_COMMIT → BRIEF_IF_NEEDED → BACKLOG_REFRESH (반복)
create_state_manager <- function() {
  # 환경(environment) 기반 상태 객체 반환
  # $get_state(), $set_state(), $get_mode(), $set_mode()
  # $get_loop(), $set_loop()
  # $get_wip_count(), $increment_wip(), $decrement_wip()
  # $is_production_window() — config의 production_window_days 기준
}

#' 태스크 상태 추적
#' 상태코드: created, queued, running, blocked, paused, failed, done,
#'           rejected, invalidated, superseded
task_tracker <- function() {
  # tasks/{task_id}.json으로 상태 추적
  # $create(), $update_state(), $get_state(), $list_by_state()
}
```

### 2-3. 작업 큐 (`R/orchestration/queue.R`)

```r
#' Priority Queue (ResearchOps 연동)
create_task_queue <- function() {
  # registry/backlog.json 기반
  # $enqueue(task_message, priority_score)
  # $dequeue() — 가장 높은 priority_score 반환
  # $peek(n) — 상위 n개 미리보기
  # $size()
  # $filter_by_family(family)
  # $apply_family_penalty() — 동일 family 감점
}
```

### 2-4. 디스패처 (`R/orchestration/dispatcher.R`)

```r
#' 에이전트 디스패치
dispatch_to_agent <- function(task_message, agent_registry) {
  # 1. assignee로 에이전트 함수 resolve
  # 2. 시스템 프롬프트 로드 (inst/prompts/system/{agent_name}.yaml)
  # 3. memory_context 구성 (retrieval packet 생성)
  # 4. 에이전트 실행
  # 5. 응답 메시지 파싱
  # 6. 상태 업데이트
  # 7. compute_metrics 기록
}

#' 에이전트 레지스트리
agent_registry <- function() {
  # 에이전트명 → 실행 함수 매핑
  # "FactorStrategyBuilder" → agent_strategy_builder()
  # "RiskAuditor" → agent_risk_auditor()
  # "ResearchOps" → agent_researchops()
  # "BlenderAgent" → agent_blender()
  # "ValuationAgent" → agent_valuation()
  # "ControlTower" → agent_control_tower()
}
```

## 산출물
- `R/orchestration/messages.R`
- `R/orchestration/state.R`
- `R/orchestration/queue.R`
- `R/orchestration/dispatcher.R`
- `inst/schemas/task_message.json` (JSON Schema for validation)
- `inst/schemas/response_message.json`
- `inst/schemas/memory_event.json`
- `tests/testthat/test-orchestration.R`

## 검증 기준
- 메시지 생성 → JSON Schema validation 통과
- 상태 전이: created → queued → running → done 정상 추적
- 큐에 3개 태스크 넣고 priority 순으로 dequeue
- family penalty 적용 후 같은 family 태스크의 priority 감소 확인
- WIP 상한(3) 초과 시 dispatch 거부

---

# Phase 3: Agent System Prompts + Retrieval Tools

## 목표
에이전트별 시스템 프롬프트를 YAML로 구현하고, Lawbook/Memory retrieval 도구를 완성한다.

## 선행 조건
- Phase 0, 1, 2 완료

## 구현 항목

### 3-1. 공통 시스템 프롬프트 뼈대 (`inst/prompts/system/_base.yaml`)

```yaml
# 모든 에이전트가 공유하는 기본 지시
objective_hierarchy: |
  목적함수 우선순위 (위반 불가):
  1. Validity (PIT, 데이터 무결성, 재현성)
  2. Implementability (TO, 비용, 유동성, 집행 가능성)
  3. Robustness (OOS, Stress, Tail Risk)
  4. Performance (Sharpe0, CAGR, IR)
  5. Novelty (새로운 알파 원천, 직교성, 학습가치)
  상위 단계 FAIL이면 하위 성과가 좋아도 승격 불가.

hard_laws: |
  절대 위반 불가:
  - PIT: available_date <= rebal_date 데이터만 사용
  - 재현성: 동일 입력 → 동일 결과
  - 비용 반영: 거래비용/슬리피지 미반영 결과는 무효
  - 허들: 임의 변경 금지
  - fingerprint: 동일 fingerprint는 새 전략이 아님
  - 테스트 봉인: 테스트 구간 확인 후 규칙 변경 시 즉시 탈락
  - 산출물 없는 진척 금지

artifact_standard: |
  모든 산출물 필수 포함:
  1. Artifact (.md/.json/.csv/.parquet)
  2. Provenance (data_snapshot_id + 파라미터 + 코드버전)
  3. Decision Log (왜 그렇게 했는지, 무엇을 버렸는지)
  4. Fingerprint (핵심 정의 해시)

kpi_standard: |
  기본 Sharpe: Sharpe0_m_ann (월간 수익률 기반 연환산, Rf=0%)
  기본 Tail: ES99_m (월간 ES 99%, 양의 손실 크기)
  보조: Sharpe0_d_ann, ES99_d (일간, 진단용)
```

### 3-2. 에이전트별 시스템 프롬프트

아래 YAML 파일 각각 생성:
- `inst/prompts/system/manager.yaml`
- `inst/prompts/system/strategy_builder.yaml`
- `inst/prompts/system/risk_auditor.yaml`
- `inst/prompts/system/researchops.yaml`
- `inst/prompts/system/blender.yaml`
- `inst/prompts/system/valuation.yaml`
- `inst/prompts/system/control_tower.yaml`
- `inst/prompts/system/catalyst.yaml`
- `inst/prompts/system/idea_compiler.yaml`

각 YAML 구조:
```yaml
agent_name: "FactorStrategyBuilder"
extends: "_base"  # 공통 뼈대 상속

role: |
  단일/멀티팩터 전략 설계(신호→포트폴리오 구성).
  거래비용/제약 반영한 실전형 스펙 제출.
  최근 실패 전략을 family 단위로 사후 검토.

authority_boundaries: |
  - 허들(합격 기준) 임의 변경 불가
  - 데이터/피처 정의 임의 변경 불가
  - 테스트 구간 확인 후 규칙 변경 금지

agent_specific_rules: |
  {에이전트 특화 규칙 — 앞서 Part 2에서 설계한 내용}

tools:
  - memory_retrieve
  - lesson_search
  - registry_search
  - lawbook_lookup
  - fingerprint_check

memory_access:
  research_design:
    priority: [family_memory, recent_lessons, stat_evidence, backlog_context, working]
  rebalance:
    priority: [schema, stat_evidence, regime_payoff, portfolio_policy, digests, working]
```

### 3-3. 시스템 프롬프트 조립기 (`R/agents/prompt_builder.R`)

```r
#' 에이전트 시스템 프롬프트 조립
#' @param agent_name 에이전트 이름
#' @param task_context 태스크별 추가 컨텍스트 (선택)
#' @param memory_packet retrieval packet (선택)
#' @return 조립된 시스템 프롬프트 문자열
build_system_prompt <- function(agent_name, task_context = NULL, memory_packet = NULL) {
  # 1. _base.yaml 로드
  # 2. {agent_name}.yaml 로드
  # 3. extends 필드에 따라 base 병합
  # 4. task_context가 있으면 "## 현재 태스크 컨텍스트" 섹션 추가
  # 5. memory_packet이 있으면 "## 관련 기억" 섹션 추가
  #    - 토큰 버짓 내에서 priority 순으로 주입
  #    - confidence < threshold인 기억은 shrink 표시
  # 6. 최종 프롬프트 문자열 반환 + token_count 계산
}
```

### 3-4. Memory Retrieval Tool (`R/tools/memory_retrieve.R`)

```r
#' Memory Retrieval — 25장 기준
#' @param query_context "rebalance" | "research_design" | "validation" | "control_tower"
#' @param agent_name 요청 에이전트 이름
#' @param query 검색 키워드 (family, strategy_id 등)
#' @param token_budget 토큰 버짓
#' @return retrieval_packet (list)
memory_retrieve <- function(query_context, agent_name, query = NULL,
                            token_budget = NULL) {
  # config에서 기본 토큰 버짓 로드
  # query_context에 따라 우선순위 결정:
  #   rebalance: schema → stat_evidence → regime_payoff → portfolio_policy → digests → working
  #   research_design: family_memory → lessons → stat_evidence → backlog → working
  #   validation: stat_evidence → family_memory → lessons → working
  #   control_tower: portfolio_policy → post_trade → regime_payoff → working

  # 각 레이어에서 관련 기억 로드
  # confidence 기반 shrink 적용
  # 토큰 버짓 내에서 잘라내기 (truncation_rule: lowest_confidence_first)
  # retrieval_packet JSON 구성 + 반환
}

#' Lesson 검색
#' @param query 키워드
#' @param top_k 반환 수
lesson_search <- function(query, top_k = 3) {
  # memory/lessons/ 디렉토리의 .md 파일들을 grep 검색
  # 태그/조건/family 기준 필터링
}
```

## 산출물
- `inst/prompts/system/_base.yaml`
- `inst/prompts/system/{agent_name}.yaml` × 9개
- `R/agents/prompt_builder.R`
- `R/tools/memory_retrieve.R`
- `R/tools/lawbook.R` (Phase 0에서 스켈레톤, 여기서 완성)
- `tests/testthat/test-prompts.R`
- `tests/testthat/test-retrieval.R`

## 검증 기준
- 각 에이전트 시스템 프롬프트 조립 시 토큰 수 1500 이하
- memory_retrieve가 query_context별로 다른 우선순위 적용
- 토큰 버짓 초과 시 lowest confidence 기억이 먼저 제거됨
- lawbook_lookup("06", "Gate4", "concise")가 200 tokens 이내 반환

---

# Phase 4: R2/R3 Family Memory + Statistical Evidence

## 목표
동일 family 실험들을 일반화하는 Family Memory(R2)와
통계 검증 결과를 보관하는 Statistical Evidence Store(R3)를 구현한다.

## 선행 조건
- Phase 0, 1 완료

## 구현 항목

### 4-1. R2 Family Memory (`R/memory/r2_family.R`)

```r
#' R2: Family Memory 생성/업데이트
#' @param family_id family 이름
#' @return family_memory.json 경로
r2_distill_family <- function(family_id) {
  # 1. registry에서 해당 family의 모든 experiment digests 로드
  # 2. 최소 3개 이상인지 확인 (미달이면 NULL 반환)
  # 3. 증류 프롬프트 로드 (inst/prompts/distill_r2.yaml)
  # 4. call_llm(model = "distill_medium")
  # 5. r2_verify() 검증
  # 6. PASS면 memory/families/{family_id}.json 저장
}

#' R2 검증
r2_verify <- function(family_memory_path, source_digests) {
  # inst/prompts/verification/ver_r1r2.yaml 로드
  # Soft Prior violation 검사 포함
  # evidence_count vs 실제 실험 수 대조
}
```

### 4-2. R3 Statistical Evidence Store (`R/memory/r3_evidence.R`)

```r
#' R3: Statistical Evidence 저장
#' @param strategy_id 전략 ID
#' @param alpha_validation alpha_validation.json 경로
#' @param fm_validation fm_validation.json 경로 (선택)
#' @param stat_defense stat_defense_report.md 경로 (선택)
#' @return evidence.json 경로
r3_store_evidence <- function(strategy_id, alpha_validation,
                              fm_validation = NULL, stat_defense = NULL) {
  # 1. 원시 파일에서 수치 추출
  # 2. tier 자동 판정 (strong/moderate/weak/insufficient)
  # 3. r3_verify() 검증
  # 4. memory/evidence/{strategy_id}.json 저장
}

#' tier 판정 규칙
determine_evidence_tier <- function(alpha_results) {
  # strong: FF3/Carhart4/FF5 중 2개 이상 양(+) alpha + 유의 t-stat, FMB 통과
  # moderate: 1개 이상 통과, 나머지 약함
  # weak: 모두 약하거나 음(-)
  # insufficient: 검증 미수행
}
```

### 4-3. 증류/검증 프롬프트 파일들
- `inst/prompts/distill_r2.yaml`
- `inst/prompts/verification/ver_r1r2.yaml`
- `inst/prompts/verification/ver_r1r3.yaml`

## 산출물
- `R/memory/r2_family.R`
- `R/memory/r3_evidence.R`
- 프롬프트 YAML 3개
- `tests/testthat/test-memory-r2r3.R`

## 검증 기준
- 동일 family 실험 5개를 넣으면 family memory가 생성됨
- family memory의 works_when/fails_when이 소스 실험과 일관적
- "반드시", "항상" 같은 Hard Law 표현 사용 시 검증 FAIL
- statistical evidence tier 판정이 수치와 일치

---

# Phase 5: R4/R5/R6 Regime + Policy + Post-Trade

## 목표
국면별 기대보수(R4), 포트폴리오 정책(R5), 사후운용 학습(R6)을 구현한다.

## 선행 조건
- Phase 0, 1, 4 완료

## 구현 항목

### 5-1. R4 Regime Payoff Tensor (`R/memory/r4_regime.R`)

```r
r4_distill_regime <- function(family_id, regime_id, construction_id) {
  # 1. 해당 family × regime × construction의 조건부 백테스트 결과 로드
  # 2. 표본 수 확인 (< 24개월이면 confidence < 0.5 강제)
  # 3. 증류 + 검증 (자기강화 방지 포함)
  # 4. memory/regime_payoff/{family_id}_{regime_id}_{construction_id}.json 저장
}
```

### 5-2. R5 Portfolio Policy Memory (`R/memory/r5_policy.R`)

```r
r5_store_policy <- function(policy_id, sleeves, baseline, overlay,
                            portfolio_metrics, loo_results) {
  # baseline 대비 개선 확인
  # leave-one-out 통과 확인
  # memory/portfolio_policy/{policy_id}.json 저장
}
```

### 5-3. R6 Post-Trade Learning (`R/memory/r6_post_trade.R`)

```r
r6_store_learning <- function(strategy_id, period,
                              intended_exposures, realized_exposures,
                              realized_turnover, slippage,
                              regime_events, lifecycle_events) {
  # memory/post_trade/{strategy_id}_{period}.json 저장
}
```

### 5-4. 검증 프롬프트
- `inst/prompts/verification/ver_r4.yaml`
- `inst/prompts/verification/ver_r5.yaml`
- `inst/prompts/verification/ver_r6.yaml`

## 산출물
- `R/memory/r4_regime.R`, `r5_policy.R`, `r6_post_trade.R`
- 검증 프롬프트 3개
- `tests/testthat/test-memory-r4r5r6.R`

## 검증 기준
- R4에서 표본 < 24개월이면 confidence < 0.5 강제
- R5에서 LOO 미통과 시 저장 거부
- R6에서 intended vs realized drift가 정확히 기록됨

---

# Phase 6: Agent Implementations

## 목표
핵심 에이전트 5개의 실행 로직을 구현한다.
각 에이전트는 LLM API를 호출하여 태스크를 수행하고, 표준 응답 메시지를 반환한다.

## 선행 조건
- Phase 0~5 완료

## 구현 항목

### 6-1. Agent 기본 클래스 (`R/agents/base_agent.R`)

```r
#' 에이전트 실행 프레임워크
run_agent <- function(agent_name, task_message) {
  # 1. 시스템 프롬프트 조립 (build_system_prompt)
  # 2. memory retrieval packet 생성 (memory_retrieve)
  # 3. 태스크 메시지를 user prompt로 변환
  # 4. call_llm() 호출
  # 5. 응답 파싱 → 산출물 저장 → 응답 메시지 생성
  # 6. compute_metrics 기록
  # 7. create_response_message() 반환
}
```

### 6-2. 개별 에이전트 (`R/agents/`)

각 에이전트 파일:
- `agent_strategy_builder.R` — 전략 설계 + 실험 계약서 생성
- `agent_risk_auditor.R` — Gate 0~5 순차 심사 + 통계 검증
- `agent_researchops.R` — Priority Score 계산 + 백로그 관리
- `agent_blender.R` — 앙상블 설계 + LOO + overlay 적용
- `agent_control_tower.R` — intended vs realized 비교 + drift 감지

각 에이전트는 `run_agent()` 프레임워크를 사용하되,
도구 호출(tool use) 로직은 에이전트별로 다르다.

### 6-3. Manager Orchestrator (`R/agents/agent_manager.R`)

```r
#' 영구기관 메인 루프
run_perpetual_engine <- function() {
  state <- create_state_manager()
  queue <- create_task_queue()
  tracker <- task_tracker()

  # BOOT
  state$set_state("BOOT")
  config <- load_config()

  # MEMORY_LOAD
  state$set_state("MEMORY_LOAD")
  # 기존 기억 인덱스 로드

  while (state$get_loop() == "on") {
    # BACKLOG_REFRESH
    state$set_state("BACKLOG_REFRESH")
    refresh_backlog(queue, state)  # 빈 backlog면 자동 생성

    # DISPATCH
    state$set_state("DISPATCH")
    if (state$get_wip_count() >= config$orchestration$max_wip) next
    task <- queue$dequeue()
    if (is.null(task)) next

    # RUN_CHUNK
    state$set_state("RUN_CHUNK")
    tracker$update_state(task$task_id, "running")
    response <- dispatch_to_agent(task, agent_registry())

    # EVALUATE
    state$set_state("EVALUATE")
    # 응답의 verdict/grade 확인

    # MEMORY_COMMIT
    state$set_state("MEMORY_COMMIT")
    commit_to_memory(response)  # R0 → R1 → 승격 판단

    # BRIEF_IF_NEEDED
    state$set_state("BRIEF_IF_NEEDED")
    check_briefing_triggers(response)

    # 루프 제어
    if (state$get_mode() == "production" && state$is_production_window()) {
      # production 태스크 우선
    }
  }
}

#' Backlog 자동 생성 (IDLE 금지)
refresh_backlog <- function(queue, state) {
  if (queue$size() > 0) return()

  # Memory-driven: 기억의 공백을 확인
  # 1. Regime Payoff 공백 (미충족 regime × family 조합)
  # 2. Portfolio Policy의 role imbalance
  # 3. Family Memory의 실패 패턴에서 개선 기회
  # 4. 위 없으면 Catalyst/Explore 모드

  # 청크 생성 → queue에 enqueue
}
```

## 산출물
- `R/agents/base_agent.R`
- `R/agents/agent_strategy_builder.R`
- `R/agents/agent_risk_auditor.R`
- `R/agents/agent_researchops.R`
- `R/agents/agent_blender.R`
- `R/agents/agent_control_tower.R`
- `R/agents/agent_manager.R`
- `tests/testthat/test-agents.R`

## 검증 기준
- 각 에이전트가 표준 태스크 메시지를 받고 표준 응답 메시지를 반환
- Manager 루프가 3회 iteration을 문제없이 완료
- 빈 backlog에서 자동으로 새 청크가 생성됨
- WIP 상한 초과 시 dispatch 대기

---

# Phase 7: Self-Evolution + ResearchOps Integration

## 목표
자가발전 루프(13장), ResearchOps 큐 경제학(16장), 탐색 모드 분할,
Circuit Breaker를 통합한다.

## 선행 조건
- Phase 0~6 완료

## 구현 항목

### 7-1. ResearchOps Priority Calculator (`R/orchestration/researchops.R`)

```r
#' VoE 기반 Priority Score 계산
calculate_priority <- function(chunk_proposal) {
  # Gain (0~5): 목표 지표 개선 가능성
  # Learning (0~5): 실패해도 교훈 가치
  # Novelty (0~5): 최근 20개 실험과의 차별성
  # Cost (0~5): 실행시간/메모리/복잡도
  # DependencyRisk (0~5): 인프라/데이터 의존성
  # FamilyPenalty: family_trial_count 기반

  # Priority = 0.30*Gain + 0.25*Learning + 0.20*Novelty
  #          - 0.15*Cost - 0.10*DependencyRisk - FamilyPenalty

  # Memory-driven 가산:
  # - Regime Payoff 공백 → +1.0
  # - Portfolio Policy role imbalance → +0.5
  # - Family에 강한 실패 패턴 → FamilyPenalty 강화
}

#' 탐색 예산 분할 확인
check_budget_split <- function(active_chunks) {
  # exploit/orthogonal/counterfactual 비율 확인
  # 동일 family > 40%이면 경고
  # 3회 연속 PASS → counterfactual 의무 확인
}
```

### 7-2. Circuit Breaker (`R/orchestration/circuit_breaker.R`)

```r
#' 안전 회로
circuit_breaker <- function() {
  # SE-CB-01: 같은 실패 사유 3회 연속 → family COOL_DOWN
  # SE-CB-02: 일일 실행 상한 / 디스크 상한 / 단일 청크 시간 상한
  # SE-CB-03: PIT 위반 감지 → 즉시 중단 + 경보
  # SE-CB-04: 고급 기법 불안정 → 단순 baseline 폴백
}
```

### 7-3. 브리핑 엔진 (`R/orchestration/briefing.R`)

```r
#' 브리핑 트리거 체크 + 발송
check_briefing_triggers <- function(response) {
  # 정량 트리거: Sharpe0 +0.10, ES99 0.30%p, MDD 2.0%p, TO 100%p/yr
  # msg_hash 기반 dedup (24시간)
  # 일일 최대 12건
  # 초과분은 digest로 묶음
}
```

## 산출물
- `R/orchestration/researchops.R`
- `R/orchestration/circuit_breaker.R`
- `R/orchestration/briefing.R`
- `tests/testthat/test-self-evolution.R`

## 검증 기준
- priority_score가 Memory 기반 가산을 반영
- family concentration > 40% 시 경고 발생
- 3회 연속 동일 실패 시 COOL_DOWN 상태 전환
- 브리핑 dedup이 24시간 내 동일 msg_hash 차단

---

# Phase 8: End-to-End Integration Test

## 목표
전체 시스템을 연결하여 1개의 Research Chunk가 생성→실행→심사→기억 승격→브리핑까지 완주하는 것을 검증한다.

## 선행 조건
- Phase 0~7 전체 완료

## 시나리오

### E2E-01: 단일 Research Chunk 생명주기

```r
test_that("single research chunk completes full lifecycle", {
  # 1. 예시 데이터 세팅 (mock universe, mock backtest results)
  # 2. Manager BOOT → MEMORY_LOAD
  # 3. Backlog에 1개 청크 수동 등록
  # 4. DISPATCH → Strategy Builder 실행
  # 5. EVALUATE → Risk Auditor 실행
  # 6. MEMORY_COMMIT:
  #    - R0 저장 확인
  #    - R1 digest 생성 + 검증 PASS 확인
  #    - Registry 레코드 추가 확인
  # 7. BRIEF_IF_NEEDED: 트리거 조건에 따라 브리핑 발송 여부 확인
  # 8. 상태가 BACKLOG_REFRESH로 돌아옴 확인
})
```

### E2E-02: Memory 승격 체인

```r
test_that("memory promotes from R1 through R3", {
  # 1. 동일 family 실험 3개를 순차 실행
  # 2. R2 Family Memory 자동 생성 확인
  # 3. 통계 검증 수행 후 R3 Evidence Store 저장 확인
  # 4. R2/R3 검증 PASS 확인
})
```

### E2E-03: Backlog 자동 생성 (IDLE 금지)

```r
test_that("empty backlog triggers automatic chunk generation", {
  # 1. 빈 backlog + 빈 registry로 시작
  # 2. Manager가 BACKLOG_REFRESH에서 자동 청크 생성
  # 3. 생성된 청크가 Memory 공백을 반영하는지 확인
})
```

### E2E-04: Circuit Breaker 작동

```r
test_that("circuit breaker triggers on repeated failures", {
  # 1. 동일 family 3회 연속 FAIL
  # 2. COOL_DOWN 상태 전환 확인
  # 3. 다른 family로 dispatch 전환 확인
})
```

## 산출물
- `tests/testthat/test-e2e.R`
- `scripts/run_e2e_test.R` (전체 통합 테스트 스크립트)
- `scripts/demo_single_chunk.R` (데모용 단일 청크 실행)

## 검증 기준
- E2E-01~04 전체 PASS
- 실행 중 에러 없이 상태 전이 완료
- 모든 산출물이 표준 형식으로 저장됨
- 로그에 전체 실행 경로가 추적 가능

---

# 실행 가이드

## Claude Code에 전달하는 방법

### 세션 1: Phase 0
```
이 파일(구현 티켓)과 QEPM Lawbook v1.4.2 전체를 읽어줘.
Phase 0을 구현해줘. 디렉토리 구조, R 패키지 뼈대, config.yaml, 유틸리티 함수들.
테스트가 통과하는지 확인해줘.
```

### 세션 2: Phase 1
```
Phase 0이 완료된 프로젝트에서 Phase 1을 구현해줘.
R0/R1 Memory Store, Digest Generator, Verification.
inst/prompts/ 에 증류/검증 프롬프트도 만들어줘.
테스트가 통과하는지 확인해줘.
```

### 세션 3~8: Phase 2~7 (동일 패턴)
```
Phase {N-1}이 완료된 프로젝트에서 Phase {N}을 구현해줘.
{해당 Phase의 목표 설명}
테스트가 통과하는지 확인해줘.
```

### 세션 9: Phase 8
```
전체 Phase가 완료된 프로젝트에서 Phase 8 End-to-End 테스트를 구현하고 실행해줘.
E2E-01~04 시나리오가 모두 통과해야 해.
```

## 주의사항

1. **각 Phase는 독립 세션으로**: Claude Code의 컨텍스트 윈도우를 효율적으로 사용하기 위해, Phase별로 세션을 나눈다. 단, 이 티켓 파일은 매 세션에 함께 전달한다.

2. **Lawbook은 참조용**: inst/lawbook/에 배치하되, 시스템 프롬프트에 전체를 넣지 않는다. 3-Layer Injection을 따른다.

3. **API 키 없이도 테스트 가능하게**: LLM API 호출이 필요한 테스트는 mock 응답을 사용한다. `tests/testthat/fixtures/` 에 mock JSON을 준비한다.

4. **R 패키지 구조 유지**: `devtools::load_all()`이 항상 성공해야 한다. NAMESPACE 자동 생성(roxygen2) 사용.

5. **한국어 코멘트 허용**: 코드 코멘트는 한국어 OK. 함수명/변수명은 영문.
