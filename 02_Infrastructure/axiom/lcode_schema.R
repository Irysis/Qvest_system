# lcode_schema.R — L-code 입력 품질 게이트 v3 (2026-08-23 v9 Lean Loop)
#
# validate_lcode(): 신규 L-code 적립 시점에 필수필드 + sanity bound를 검증한다.
#   위반(hard error) 시 호출부가 write를 차단 → garbage(예: -2028.7%p bm 정렬버그,
#   한 줄 템플릿) corpus 진입을 막는다. = 자동 승격 파이프라인 안전핀 #1 (INV-1 전제).
#
# v2 (2026-07-04 — 도훈 mandate "emit이 축을 채우게"):
#   승격 0의 인과 = 문턱이 아니라 emit 입력 결측(falsification 0/598 · portfolio_alpha_t
#   98% 결측). 따라서 required_for_promotion 계층을 신설한다 — 문턱·INV 일절 불변.
#
#   [base required — hard error, v1과 동일 + record_type 조건부]
#     l_code / strategy_id / lesson_text / research_mode / metric_type
#     grade: record_type=performance(기본)일 때만 필수. enum A/B/C/F 강제
#            (legacy alias는 수용 + WARN + normalize_lcode()가 canonical로 정규화).
#   [required_for_promotion — 승격축 입력. strict=TRUE(promotion 시점)면 error,
#    strict=FALSE(emit 시점, 기본)면 WARN + missing_promotion_fields 반환.
#    emit BLOCK 승격은 2사이클 관찰 후 도훈 confirm — 지금 미도입]
#     mechanism_hypothesis  — Mechanism 축. 보일러플레이트("unknown"/"TBD"/공란/
#                             "…지배 요인:" 뒤 공란) 불인정
#     construction_type     — Independence 축. controlled vocab. selection_type 값
#                             (chain/sweep)은 거부 → selection_type 별도 필드로 분리
#     next_probe            — ★v3 신설. **연속성 계약의 집**(v9 Lean Loop). grade C/F는
#                             2건 이상, A/B는 1건 이상. 리스트(next_probes) 또는
#                             " | " 조인 문자열 둘 다 인정. 실패가 다음 가설의 생성기가
#                             되지 못하면 그 L-code는 승격축에 못 오른다.
#   [recommended — 결측 시 WARN]
#     falsification_attempts — Falsification 축. 구조체 list [{test, result∈{survived,
#                              falsified,weakened}, effect_retained}] 권장. 문자열도
#                              수용하되 WARN (promote.R .axis_falsification 보수 처리)
#     metric_type=backtested 시 portfolio_alpha_t 결측 WARN (Rigor 축)
#
# v3 변경 (2026-08-23 — v9 Lean Loop §3.4(d)):
#   - LCODE_SCHEMA_VERSION 3L. required_for_promotion = {mechanism, construction_type,
#     next_probe}. metric_type 은 base required 와 중복이라 승격축 목록에서 제거(검증 동일).
#   - oos_months / oos_effect_vs_is 를 recommended 에서 제거 — **읽기는 계속 허용**
#     (기존 원장 필드 보존, 검증에서 요구만 안 함). 근거: r7 설계의 External 축은
#     728회 review 실측 중앙값 −0.04 로 이 통계량으로는 도달 자체가 불가였고,
#     "결측 WARN"이 매 L-code 에 붙어 실제 결함과 구분되지 않는 잡음이 됐다.
#
# 하위호환: 구 L-code(스키마 v1, lcode_schema_version 필드 부재)는 읽기/재검증 시
#   strict=FALSE로 통과 (required_for_promotion은 WARN까지만). 정직 원장 보존.
#
# r7 정합 필드(00_Lawbook/Axiom_아키텍처/r7_axiom_design.md):
#   construction_type   — Independence 축(같은 construction = 상관 1건)
#   mechanism_hypothesis — Mechanism 축(경제적 설명, 없으면 unknown)
#   falsification_attempts — Falsification 축(적극 반증 기록)
#
# 참조: .claude/rules/measurement-graduation.md(metric_type) /
#       docs/rules/axiom-engine.md(§emit 필수·권장 필드표) /
#       06_Registry/lcode_distill_plan_20260704.json(grade_normalization_map SOT).

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

LCODE_SCHEMA_VERSION <- 3L

# ── grade: canonical enum + legacy alias (distill plan grade_normalization_map과 동일) ──
LCODE_VALID_GRADES <- c("A", "B", "C", "F")
LCODE_GRADE_ALIASES <- c(
  # 성과등급 alias → canonical
  "A_NOVEL" = "A", "A_DEF" = "A", "A_CONDITIONAL" = "A", "A_CONDITIONAL_REAFFIRMED" = "A",
  "B_ARCHIVE" = "B", "REJECT" = "F"
)
# 비성과(PROCESS) legacy grade → record_type으로 이동 (grade 아님)
LCODE_PROCESS_GRADE_MAP <- c(
  "INFRASTRUCTURE" = "infra", "INFRASTRUCTURE_CRITICAL" = "infra",
  "INFRASTRUCTURE_PROCESS" = "infra",
  "METHODOLOGY" = "process", "PROCESS_INTEGRITY_RULE" = "process",
  "ROLE_HONESTY_RULE" = "process", "SR_CEILING_FINDING" = "process",
  "PROCESS_RULE (Defense composite admission operational rule)" = "process",
  "PROCESS_RULE (infra bug pattern)" = "process",
  "N/A (factor-level discovery)" = "process",
  "N/A (axiom-level discovery synthesis)" = "process",
  "TIER2_SUMMARY" = "summary", "TIER3_SUMMARY" = "summary"
)

LCODE_VALID_RECORD_TYPES <- c("performance", "process", "infra", "summary")

# canonical_screen 추가 (measurement-graduation §1 정합 — canonical_screen_bt 실측 라벨)
LCODE_VALID_METRIC_TYPES <- c("proxy", "estimated", "canonical_screen", "backtested", "unavailable")

LCODE_VALID_MODES <- c("alpha_search", "alpha_research", "qepm_legacy",
                       "judge_gate", "governor_admission",
                       "strategy_rotation", # 2026-08-24 v9.21: 구 factor_rotation 개명 (아래 alias)
                       "factor_rotation",   # ★역사 라벨로 존치 — 기존 L-code 1건이 이 값을 갖는다
                       "regime_research",
                       "ramp",              # 2026-06-18: RAMP 자가발전 4번째 모드 (v9.21 모드 지위 퇴임 — 라벨은 존치)
                       "overlay_research",  # 2026-07-06: OVL 오버레이 자가발전 모드 (lcode_emit OVL prefix와 정합)
                       "paper_replication", # ★v10 2026-08-29: 1계층 충실구현 라운드 (prefix RP)
                       "reinforcement",     # ★v10 2026-08-29: 강화 프로세스 (1계층 ≤20회 / 2계층 무한, prefix RF)
                       ## ★2026-09-23 (플랜 P0-M3 · 감사 D6-03): **재라벨 전용 역사 라벨** — 발행 모드가 아니다.
                       ##   강화 셀 1,106건이 run_paper_replication 경유로 mode=paper_replication '충실구현' L-code 로
                       ##   오발행됐다(corpus 57%). 제자리 재라벨(relabeled_from 보존 · 삭제 없음)한 값이 이것이다.
                       ##   enum 에 없으면 validate_lcode 가 정정된 기록을 '비표준'으로 뒤집는다(역사는 판정이 아니다).
                       ##   신규 발행은 없다 — 워커가 QVEST_RP_NO_LCODE=1 로 막고, 셀 교훈 정본은 블록 L-code(reinforcement).
                       ##   prefix 맵(lcode_emit/promote/cluster_extractor)에는 넣지 않는다 — paper_replication·reinforcement 와
                       ##   같은 GEN 폴백(선행 부채)이며, id 는 원 L-RP-* 그대로 둔다(불투명 식별자).
                       "reinforcement_cell")
# research_mode normalize 규칙 (promote GEN 폴백 봉합, A2-F8②)
## ★v9.21 개명 (도훈 지시 2026-08-24 "팩터 로테이션은 전략 로테이션으로"):
##   `factor_rotation` → `strategy_rotation`. **이름이 코드 현실과 오히려 일치하게 된다** —
##   FR 입력은 이미 팩터가 아니라 완성 전략 모듈(module_performance.json)이고,
##   팩터 분해(PCA/hclust/FWL)는 RAMP 쪽에만 있다.
##   ★기존 값을 enum 에서 빼지 않는다 — 원장의 L-code 1건이 그 값을 갖고 있고, 빼면
##     validate_lcode 가 **과거 기록을 무효로 만든다**(역사는 판정이 아니다). alias 가
##     신규 발행만 새 이름으로 정규화한다.
##   ★prefix 는 `FR` 유지 — id 는 불투명 식별자다. 바꾸면 기존 `L-FR-*` 2건이 끊긴다.
LCODE_MODE_ALIASES <- c("qepm" = "qepm_legacy",
                        "factor_rotation" = "strategy_rotation")

# selection_type — measurement-graduation §3 selection operator (construction과 별개 축)
LCODE_VALID_SELECTION_TYPES <- c("chain", "sweep", "single")

# ── 원천 철회 표식 (2026-09-23 · Axiom 전수감사 K3 · 도훈 AX-D4-PIT-RETRACT) ─────────────────────
#   L-code 원천 파일에 **추가만** 하는 필드(원 필드 불변 — 철회는 삭제가 아니다, AX-000·INV-7).
#     pit_invalid        logical  PIT 위반(C1~C15)으로 측정 자체 무효. 결론이 뒤에 재확인돼도 이 측정은 무효.
#     retracted_by       chr      철회 근거 참조(정정 L-code id · 레지스트리 경로 · 보고서 절). pit_invalid=TRUE 면 필수.
#     retracted_at       chr      철회가 확정된 날(표식을 단 날 아님).
#     retraction_reason  chr      기전 1~2문장.
#     retraction_decision_ref / retraction_marked_at / retraction_marked_by — 표식 행위의 감사 흔적.
#   ★"소비해도 되는가" 판정 함수는 **하나**다: 02_Infrastructure/axiom/lcode_validity.py::lcode_invalidation.
#     여기(R)에는 필드 **형식** 검증만 둔다(validate_lcode). R 소비자(P3 rf_lessons 적재 등)가 원천 파일을
#     직접 읽어야 하면 아래 lcode_invalidation_check() 로 **같은 파이썬 함수**를 부른다 — R 로 판정 재구현 금지.
#     corpus(.cache/lcode_corpus.json::lcodes)는 수확 단계(lcode_harvester.py)에서 이미 걸러져 있다.
#   표식 writer = lcode_validity.py mark (백업 + 원자 쓰기 + CRLF 보존 + 되읽기 판정).
LCODE_INVALIDATION_FIELDS <- c("pit_invalid", "retracted_by")          # 판정 필드(둘 중 하나면 소비 불가)
LCODE_INVALIDATION_AUDIT_FIELDS <- c("retracted_at", "retraction_reason", "retraction_decision_ref",
                                     "retraction_marked_at", "retraction_marked_by")
LCODE_VALIDITY_PY <- "02_Infrastructure/axiom/lcode_validity.py"

#' 원천 L-code 파일들의 철회 판정 — 단일 정본(lcode_validity.py::lcode_invalidation)을 CLI 로 부른다.
#' @return data.frame(path, l_code, invalid, reason). invalid=NA = 읽지 못함(판정 불가 — 조용히 유효 처리 금지).
lcode_invalidation_check <- function(paths, root = Sys.getenv("QM_ROOT", getwd()),
                                     py = Sys.getenv("QVEST_PY", "")) {
  if (!length(paths)) return(data.frame(path = character(0), l_code = character(0),
                                        invalid = logical(0), reason = character(0)))
  if (!nzchar(py)) py <- file.path(root, ".venv_qvest_ml", "Scripts", "python.exe")
  script <- file.path(root, LCODE_VALIDITY_PY)
  if (!file.exists(script)) stop("lcode_validity.py 부재 — 판정 불가: ", script)
  had <- Sys.getenv("PYTHONUTF8", NA_character_); Sys.setenv(PYTHONUTF8 = "1")
  out <- suppressWarnings(system2(py, c(shQuote(script), "check", shQuote(paths)), stdout = TRUE, stderr = FALSE))
  if (is.na(had)) Sys.unsetenv("PYTHONUTF8") else Sys.setenv(PYTHONUTF8 = had)
  st <- attr(out, "status")
  if (!is.null(st) && st != 0) stop("lcode_validity.py check 실패(status=", st, ")")
  r <- jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = TRUE)
  data.frame(path = r$path, l_code = as.character(r$l_code), invalid = as.logical(r$invalid),
             reason = as.character(r$reason), stringsAsFactors = FALSE)
}

# construction_type controlled vocab (r7 Independence 축; corpus 실측 값 + 스펙 확장 포함)
LCODE_VALID_CONSTRUCTION_TYPES <- c(
  "momentum", "reversal", "value", "quality", "low_vol", "dividend", "size",
  "liquidity", "flow", "consensus", "earnings_event", "seasonality",
  "ml_sizing", "overlay_regime", "multi_sleeve", "long_short",
  "single_factor_long_only", "single_sleeve_long_only_topN",
  "volatility_timing_overlay", "dynamic_timing_overlay", "hedge_overlay",
  "regime_rotation", "structural_limit", "composite", "event_time"
)

# ── 정규화: legacy 값 → v2 canonical. validate 이전에 emit/재검증 경로가 호출 ──
#   반환: list(lcode=정규화본, notes=chr 정규화 내역)
normalize_lcode <- function(lcode) {
  notes <- character(0)

  # research_mode qepm → qepm_legacy
  rm0 <- as.character(lcode[["research_mode"]] %||% "")
  if (nzchar(rm0) && rm0 %in% names(LCODE_MODE_ALIASES)) {
    lcode$research_mode <- unname(LCODE_MODE_ALIASES[rm0])
    notes <- c(notes, sprintf("research_mode '%s'→'%s' normalize", rm0, lcode$research_mode))
  }

  # grade legacy alias / PROCESS-class → record_type 분리
  g0 <- as.character(lcode[["grade"]] %||% "")
  if (nzchar(g0) && !(g0 %in% LCODE_VALID_GRADES)) {
    if (g0 %in% names(LCODE_GRADE_ALIASES)) {
      lcode$grade_raw <- g0
      lcode$grade <- unname(LCODE_GRADE_ALIASES[g0])
      notes <- c(notes, sprintf("grade legacy alias '%s'→'%s'", g0, lcode$grade))
    } else if (g0 %in% names(LCODE_PROCESS_GRADE_MAP)) {
      lcode$grade_raw <- g0
      lcode$grade <- NULL
      if (!nzchar(as.character(lcode[["record_type"]] %||% "")))
        lcode$record_type <- unname(LCODE_PROCESS_GRADE_MAP[g0])
      notes <- c(notes, sprintf("비성과 grade '%s' → record_type='%s' 이동 (grade 제거)", g0, lcode$record_type))
    }
  }
  if (!nzchar(as.character(lcode[["record_type"]] %||% ""))) lcode$record_type <- "performance"

  # construction_type에 selection_type 값이 들어온 경우 → 별도 필드 분리
  ct <- as.character(lcode[["construction_type"]] %||% "")
  if (nzchar(ct) && ct %in% LCODE_VALID_SELECTION_TYPES) {
    if (!nzchar(as.character(lcode[["selection_type"]] %||% ""))) lcode$selection_type <- ct
    lcode$construction_type <- ""
    notes <- c(notes, sprintf("construction_type='%s'는 selection_type 값 → selection_type으로 이동 (construction 결측 처리)", ct))
  }

  list(lcode = lcode, notes = notes)
}

# construction_type 간이 추론 (Independence 축용 — name/idea 키워드 기반)
infer_construction_type <- function(name = "", idea = "") {
  s <- tolower(paste(name %||% "", idea %||% ""))
  if (grepl("overlay|오버레이|regime|국면|vol.?target|타이밍|timing|절대모멘텀", s)) return("overlay_regime")
  if (grepl("모멘텀|momentum|12-1|6-1|추세|trend", s))           return("momentum")
  if (grepl("revers|52[- ]?주\\s*(저|low)|mean.?rev|단기반전", s)) return("reversal")
  if (grepl("ml|xgb|lightgbm|딥러닝|신경망|ensemble|앙상블|rl\\b", s)) return("ml_sizing")
  if (grepl("value|밸류|per|pbr|\\bep\\b|저평가|장부", s))        return("value")
  if (grepl("quality|퀄리티|\\bgp\\b|수익성|profitab", s))        return("quality")
  if (grepl("저변동|low.?vol|변동성", s))                        return("low_vol")
  if (grepl("배당|dividend", s))                                 return("dividend")
  if (grepl("규모|size|소형|중소형|small.?cap", s))               return("size")
  return("single_factor_long_only")
}

# mechanism 보일러플레이트 판정 (r7 Mechanism 축 — 있는 척 금지)
.is_boilerplate_mechanism <- function(x) {
  s <- trimws(tolower(as.character(x %||% "")))
  if (!nzchar(s)) return(TRUE)
  if (s %in% c("unknown", "n/a", "na", "none", "null", "tbd", "없음", "미정", "-")) return(TRUE)
  # [v3 2026-08-23] 템플릿 껍데기 거부: run_alpha_search 의 mechanism 은
  #   "가설 '<아이디어>' — 검증 결과 지배 요인: <축>" 형식인데, 판정축이 비면
  #   콜론 뒤가 공란인 채로 원장에 들어간다 — 길이는 아이디어 덕에 10자를 넘으므로
  #   기존 규칙을 통과했다(=길이 검사만으로는 안 잡히는 부류). 지배 요인이 없으면
  #   그건 메커니즘 진술이 아니다.
  if (grepl("지배\\s*요인\\s*[:：]\\s*$", s)) return(TRUE)
  nchar(s) < 10  # 10자 미만 = 경제적 설명으로 불인정
}

# next_probe 건수 판정 (연속성 계약 — 리스트/문자벡터/" | " 조인 문자열 모두 인정)
#   반환: 유효(비공란) 제안 건수. 필드 부재/공란 = 0.
.next_probe_count <- function(x) {
  if (is.null(x)) return(0L)
  if (is.list(x)) x <- unlist(x, use.names = FALSE)
  x <- as.character(x)
  if (length(x) == 1L) x <- strsplit(x, "\\|")[[1]]   # 단일 문자열은 " | " 조인으로 간주
  x <- trimws(x)
  sum(nzchar(x))
}

# falsification_attempts 형태 판정: "structured" / "string" / "empty" / "invalid"
.fals_shape <- function(fa) {
  if (is.null(fa) || (is.character(fa) && !any(nzchar(fa))) || (is.list(fa) && !length(fa))) return("empty")
  if (is.character(fa)) return("string")
  if (is.list(fa)) {
    shapes <- vapply(fa, function(a) {
      if (is.list(a) && !is.null(a$test) && !is.null(a$result)) "structured"
      else if (is.character(a) && length(a) == 1L && nzchar(a)) "string"
      else "invalid"
    }, character(1))
    if (all(shapes == "structured")) return("structured")
    if (any(shapes == "invalid")) return("invalid")
    return("string")  # 혼재 포함 — 문자열 포함분은 WARN
  }
  "invalid"
}

# ── 메인 검증 ──
# strict = FALSE (기본, emit 시점): required_for_promotion 결측 = WARN.
# strict = TRUE  (promotion 시점): required_for_promotion 결측 = error.
# 반환: list(valid, errors, warnings, promotion_ready, missing_promotion_fields)
validate_lcode <- function(lcode, strict = FALSE) {
  errors <- character(0); warnings <- character(0)
  missing_promo <- character(0)

  rt <- as.character(lcode[["record_type"]] %||% "performance")
  if (!(rt %in% LCODE_VALID_RECORD_TYPES))
    errors <- c(errors, sprintf("record_type='%s' 비표준 (허용: %s)", rt, paste(LCODE_VALID_RECORD_TYPES, collapse = "/")))

  req <- c("l_code", "strategy_id", "lesson_text", "research_mode", "metric_type")
  if (rt == "performance") req <- c(req, "grade")
  for (f in req) {
    v <- lcode[[f]]
    if (is.null(v) || (is.character(v) && !nzchar(v)))
      errors <- c(errors, sprintf("필수 필드 누락/공란: %s", f))
  }

  # grade enum (A/B/C/F 강제; legacy alias 수용 + WARN — normalize_lcode 경유 권장)
  g <- as.character(lcode[["grade"]] %||% "")
  if (nzchar(g) && !(g %in% LCODE_VALID_GRADES)) {
    if (g %in% names(LCODE_GRADE_ALIASES)) {
      warnings <- c(warnings, sprintf("grade='%s' legacy alias — canonical '%s' 권장 (normalize_lcode 적용)", g, LCODE_GRADE_ALIASES[g]))
    } else if (g %in% names(LCODE_PROCESS_GRADE_MAP)) {
      warnings <- c(warnings, sprintf("grade='%s'는 비성과 기록 — record_type='%s' + grade 제거 권장 (normalize_lcode 적용)", g, LCODE_PROCESS_GRADE_MAP[g]))
    } else {
      errors <- c(errors, sprintf("grade='%s' 비표준 (허용: %s + legacy alias)", g, paste(LCODE_VALID_GRADES, collapse = "/")))
    }
  }

  mt <- as.character(lcode$metric_type %||% "")
  rm_ <- as.character(lcode[["research_mode"]] %||% "")
  if (nzchar(mt) && !(mt %in% LCODE_VALID_METRIC_TYPES))
    errors <- c(errors, sprintf("metric_type='%s' 비표준 (허용: %s)", mt, paste(LCODE_VALID_METRIC_TYPES, collapse = "/")))
  if (nzchar(rm_) && !(rm_ %in% LCODE_VALID_MODES)) {
    if (rm_ %in% names(LCODE_MODE_ALIASES)) {
      warnings <- c(warnings, sprintf("research_mode='%s' → '%s' normalize 권장", rm_, LCODE_MODE_ALIASES[rm_]))
    } else {
      errors <- c(errors, sprintf("research_mode='%s' 비표준", rm_))
    }
  }

  st <- as.character(lcode[["selection_type"]] %||% "")
  if (nzchar(st) && !(st %in% LCODE_VALID_SELECTION_TYPES))
    warnings <- c(warnings, sprintf("selection_type='%s' 비표준 (허용: %s)", st, paste(LCODE_VALID_SELECTION_TYPES, collapse = "/")))

  # 원천 철회 표식 형식 (2026-09-23 · 위 LCODE_INVALIDATION_FIELDS). 판정은 lcode_validity.py — 여기는 형식만.
  pv <- lcode[["pit_invalid"]]
  if (!is.null(pv) && !(is.logical(pv) && length(pv) == 1L && !is.na(pv)))
    errors <- c(errors, "pit_invalid 는 논리값 1개(true/false)여야 한다 — 모호한 표식은 소비 판정을 흐린다")
  rb <- lcode[["retracted_by"]]
  if (!is.null(rb) && !(is.character(rb) && length(rb) == 1L && nzchar(trimws(rb))))
    errors <- c(errors, "retracted_by 는 비지 않은 문자열 1개(철회 근거 참조)여야 한다")
  if (isTRUE(pv) && is.null(rb))
    errors <- c(errors, "pit_invalid=true 인데 retracted_by 부재 — 근거 없는 무효 표식은 기록이 아니다")

  # sanity bounds (v1과 동일 — 불변)
  .num <- function(x) { y <- suppressWarnings(as.numeric(x %||% NA)); if (length(y)) y[1] else NA_real_ }
  cagr <- .num(lcode$cagr_pct %||% lcode$cagr)
  shp  <- .num(lcode$sharpe)
  mdd  <- .num(lcode$mdd_pct %||% lcode$mdd)
  exc  <- .num(lcode$excess_cagr)
  if (!is.na(cagr) && abs(cagr) > 500)
    errors <- c(errors, sprintf("cagr=%.0f%% |.|>500%% → annualize 폭발(bm_xts 정렬/결측 산식오류)", cagr))
  if (!is.na(shp) && abs(shp) > 10)
    errors <- c(errors, sprintf("sharpe=%.2f |.|>10 → 데이터 오염", shp))
  if (!is.na(mdd) && (mdd < 0 || mdd > 100))
    errors <- c(errors, sprintf("mdd=%.1f 범위밖[0,100]%%", mdd))
  if (!is.na(exc) && abs(exc) > 1000)
    errors <- c(errors, sprintf("excess_cagr=%+.0f%%p |.|>1000 → 벤치 정렬버그(-2028%%p 류)", exc))

  # ── required_for_promotion 계층 (performance 기록 대상; process/infra/summary는 면제) ──
  if (rt == "performance") {
    # mechanism_hypothesis — 필수 (보일러플레이트 불인정)
    if (.is_boilerplate_mechanism(lcode[["mechanism_hypothesis"]]))
      missing_promo <- c(missing_promo, "mechanism_hypothesis")
    # construction_type — 필수 + controlled vocab
    ct <- as.character(lcode[["construction_type"]] %||% "")
    if (!nzchar(ct)) {
      missing_promo <- c(missing_promo, "construction_type")
    } else if (ct %in% LCODE_VALID_SELECTION_TYPES) {
      missing_promo <- c(missing_promo, "construction_type")
      warnings <- c(warnings, sprintf("construction_type='%s'는 selection_type 값 — selection_type 필드로 분리 필수 (normalize_lcode 적용)", ct))
    } else if (!(ct %in% LCODE_VALID_CONSTRUCTION_TYPES)) {
      warnings <- c(warnings, sprintf("construction_type='%s' controlled vocab 밖 — 신규 유형이면 LCODE_VALID_CONSTRUCTION_TYPES 등재 검토", ct))
    }
    # next_probe — 필수 (v3 연속성 계약). C/F는 ≥2, A/B는 ≥1.
    #   ★"실패 = 다음 가설의 생성기"가 성립하는지의 유일한 기계 검사 지점.
    #   next_probes(리스트) 우선, 없으면 next_probe(리스트 또는 " | " 조인 문자열).
    np_n <- max(.next_probe_count(lcode[["next_probes"]]),
                .next_probe_count(lcode[["next_probe"]]))
    g_can <- if (nzchar(g) && g %in% names(LCODE_GRADE_ALIASES)) unname(LCODE_GRADE_ALIASES[g]) else g
    np_min <- if (g_can %in% c("C", "F")) 2L else 1L
    if (np_n < np_min) {
      missing_promo <- c(missing_promo, "next_probe")
      warnings <- c(warnings, sprintf(
        "next_probe %d건 < 요구 %d건(grade %s) — 연속성 계약 미충족 (C/F는 2건 이상, A/B는 1건 이상)",
        np_n, np_min, if (nzchar(g_can)) g_can else "?"))
    }
    # falsification_attempts — 권장 (구조체 권장, 문자열 WARN)
    fs <- .fals_shape(lcode[["falsification_attempts"]])
    if (fs == "empty") {
      warnings <- c(warnings, "falsification_attempts 결측 — Falsification 축 도달 불가 (구조체 [{test,result,effect_retained}] 권장)")
    } else if (fs == "string") {
      warnings <- c(warnings, "falsification_attempts 문자열 기록 — 구조체 [{test,result∈{survived,falsified,weakened},effect_retained}] 권장 (promote.R은 n 카운트 보수 처리)")
    } else if (fs == "invalid") {
      warnings <- c(warnings, "falsification_attempts 형식 불량 — 구조체 [{test,result,effect_retained}] 또는 문자열만 허용")
    }
    # [v3 삭제] oos_retention 결측 "External 축 도달 불가" WARN 2종 제거.
    #   근거: 그 축은 통계량 자체가 도달 불가였는데(review_log 728회 실측 중앙값 −0.04)
    #   WARN 은 "입력을 더 채우라"고 지시해 실제 결함 WARN 을 묻었다. 필드는 계속 읽고
    #   기록한다 — 요구만 하지 않는다.
    # backtested/canonical_screen인데 portfolio_alpha_t 결측 → WARN (Rigor 축은 도달 가능)
    if (mt %in% c("backtested", "canonical_screen")) {
      if (is.na(.num(lcode[["portfolio_alpha_t"]])))
        warnings <- c(warnings, sprintf("metric_type=%s인데 portfolio_alpha_t 결측 — Rigor 축(global weakest_t 2.95) 도달 불가", mt))
    }
  }

  if (length(missing_promo)) {
    msg <- sprintf("required_for_promotion 결측: %s — 승격축 도달 불가 (emit BLOCK 승격은 2사이클 후 도훈 confirm, 지금은 WARN)",
                   paste(missing_promo, collapse = ", "))
    if (isTRUE(strict)) errors <- c(errors, msg) else warnings <- c(warnings, msg)
  }

  list(valid = length(errors) == 0L, errors = errors, warnings = warnings,
       promotion_ready = length(missing_promo) == 0L,
       missing_promotion_fields = missing_promo)
}

# selftest (Rscript lcode_schema.R 직접 실행 시)
if (sys.nframe() == 0L && !interactive()) {
  # 1) v3 완전체 — valid + promotion_ready (next_probes 2건 = C/F 요구 충족)
  full <- validate_lcode(list(l_code = "L-AS-X", strategy_id = "STR_AS_X", grade = "F",
    lesson_text = "t", research_mode = "alpha_search", metric_type = "canonical_screen",
    construction_type = "momentum",
    mechanism_hypothesis = "KR 단기 모멘텀은 수급 주도 과잉반응으로 net 음수",
    next_probes = list("보유기간 재설계", "역방향 가설 1건"),
    live_trigger = "hard_fail 축 해소 후 score>=25 회복 시",
    falsification_attempts = list(list(test = "placebo shuffle", result = "survived", effect_retained = 0.8)),
    oos_retention = 0.62, portfolio_alpha_t = 1.2,
    cagr_pct = -20.7, sharpe = -0.57, mdd_pct = 30, excess_cagr = -2.1))
  # 2) sanity 폭발 — invalid (v1 회귀)
  bad <- validate_lcode(list(l_code = "L-AS-Y", strategy_id = "STR_AS_Y", grade = "F",
    lesson_text = "t", research_mode = "alpha_search", metric_type = "proxy", excess_cagr = -2028.7))
  # 3) 구 L-code (v1 스키마, 승격축 전무) — valid(하위호환) + promotion_ready=FALSE + WARN
  legacy <- validate_lcode(list(l_code = "L-132", strategy_id = "STR_1622", grade = "F",
    lesson_text = "t", research_mode = "qepm_legacy", metric_type = "estimated"))
  # 4) strict(promotion 시점) — 같은 legacy가 invalid
  legacy_strict <- validate_lcode(list(l_code = "L-132", strategy_id = "STR_1622", grade = "F",
    lesson_text = "t", research_mode = "qepm_legacy", metric_type = "estimated"), strict = TRUE)
  # 5) legacy grade alias + qepm 모드 + chain construction → normalize
  nz <- normalize_lcode(list(l_code = "L-Q", strategy_id = "S", grade = "A_DEF",
    lesson_text = "t", research_mode = "qepm", metric_type = "backtested",
    construction_type = "chain"))
  v5 <- validate_lcode(nz$lcode)
  # 6) 비성과 legacy grade → record_type 이동
  np <- normalize_lcode(list(l_code = "L-P", strategy_id = "S2", grade = "INFRASTRUCTURE_CRITICAL",
    lesson_text = "hook bug", research_mode = "qepm_legacy", metric_type = "unavailable"))
  v6 <- validate_lcode(np$lcode)
  # 7) [v3] 연속성 계약 — F등급에 next_probe 1건만 = promotion_ready FALSE, 2건이면 TRUE.
  #    " | " 조인 문자열도 리스트와 동등하게 세는지 함께 확인(구 소비자 호환).
  .base7 <- list(l_code = "L-AS-Z", strategy_id = "STR_AS_Z", grade = "F",
    lesson_text = "t", research_mode = "alpha_search", metric_type = "proxy",
    construction_type = "momentum",
    mechanism_hypothesis = "KR 저유동 소형주에서 신호가 비용에 소진된다")
  np1 <- validate_lcode(c(.base7, list(next_probe = "축 해소 변형 1건")))
  np2 <- validate_lcode(c(.base7, list(next_probe = "축 해소 변형 1건 | 역방향 가설 1건")))
  #    A등급은 1건으로 충족
  npA <- validate_lcode(c(.base7[setdiff(names(.base7), "grade")],
                          list(grade = "A", next_probes = list("QEPM 정밀검증 이행"))))
  # 8) [v3] mechanism 템플릿 껍데기(지배 요인 뒤 공란) 거부 — 길이는 10자를 넘는다
  bp <- validate_lcode(c(.base7[setdiff(names(.base7), "mechanism_hypothesis")],
                         list(mechanism_hypothesis = "가설 '모멘텀 12-1 검증' — 검증 결과 지배 요인: ",
                              next_probes = list("a", "b"))))

  # 9) [2026-09-23] 철회 표식 형식 — 정상 표식 valid / 모호 표식(문자열 'yes') error / 근거 없는 pit_invalid error
  .base9 <- c(.base7, list(next_probes = list("a", "b")))
  rt_ok  <- validate_lcode(c(.base9, list(pit_invalid = TRUE, retracted_by = "L-RAMP-20260820_212848",
                                          retracted_at = "2026-08-20")))
  rt_amb <- validate_lcode(c(.base9, list(pit_invalid = "yes", retracted_by = "x")))
  rt_nob <- validate_lcode(c(.base9, list(pit_invalid = TRUE)))
  rt_emp <- validate_lcode(c(.base9, list(retracted_by = "  ")))
  stopifnot(isTRUE(rt_ok$valid), !isTRUE(rt_amb$valid), !isTRUE(rt_nob$valid), !isTRUE(rt_emp$valid),
            identical(LCODE_INVALIDATION_FIELDS, c("pit_invalid", "retracted_by")))
  cat(sprintf("[lcode_schema selftest 9] retraction ok=%s ambiguous=%s no_ref=%s empty_ref=%s\n",
              rt_ok$valid, rt_amb$valid, rt_nob$valid, rt_emp$valid))

  cat(sprintf("[lcode_schema v3 selftest] full=%s/%s bad=%s legacy=%s/%s strict=%s norm5=%s(%s/%s) norm6=%s(rt=%s) np1=%s np2=%s npA=%s bp=%s\n",
    full$valid, full$promotion_ready, bad$valid, legacy$valid, legacy$promotion_ready,
    legacy_strict$valid, v5$valid, nz$lcode$grade, nz$lcode$selection_type, v6$valid, np$lcode$record_type,
    np1$promotion_ready, np2$promotion_ready, npA$promotion_ready, bp$promotion_ready))
  stopifnot(identical(LCODE_SCHEMA_VERSION, 3L),
            isTRUE(full$valid), isTRUE(full$promotion_ready),
            !isTRUE(bad$valid),
            isTRUE(legacy$valid), !isTRUE(legacy$promotion_ready), length(legacy$warnings) > 0,
            !isTRUE(legacy_strict$valid),
            isTRUE(v5$valid), identical(nz$lcode$grade, "A"), identical(nz$lcode$selection_type, "chain"),
            isTRUE(v6$valid), identical(np$lcode$record_type, "infra"), is.null(np$lcode[["grade"]]),
            # v3 연속성 계약: 1건 미달 / 2건 충족 / A는 1건 충족
            !isTRUE(np1$promotion_ready), "next_probe" %in% np1$missing_promotion_fields,
            isTRUE(np2$promotion_ready), isTRUE(npA$promotion_ready),
            isTRUE(np1$valid),   # 미충족이어도 emit(strict=FALSE)은 통과 = 차단 아님
            # v3 보일러플레이트: 템플릿 껍데기는 mechanism 결측 취급
            !isTRUE(bp$promotion_ready), "mechanism_hypothesis" %in% bp$missing_promotion_fields,
            # oos_retention 결측이 더 이상 WARN을 만들지 않는다(External 축 문구 제거)
            !any(grepl("External", np2$warnings)))
  cat("  PASS (9 cases)\n")
}
