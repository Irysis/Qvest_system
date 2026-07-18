# lcode_emit.R — 모드별 L-code 적립 helper v2 (2026-07-04 엔진 재설계, 3층 산출물 모델)
#
# 4모드(alpha_search/QEPM/factor_rotation/RAMP)가 백테스트 교훈을 L-code(①Ledger)로
# 적립한다. 모두 validate_lcode(lcode_schema.R v2) 게이트를 경유하고 모드별 디렉터리
# stage_artifacts/l_code/<mode>/ 에 쓴다. research_mode 필드를 명시하므로
# harvester _infer_mode가 explicit로 인식한다.
#
# v2 변경 (도훈 mandate "emit이 축을 채우게" — 문턱·INV 불변):
#   - 승격축 4필드를 1급 인자로 승격: mechanism_hypothesis / falsification_attempts /
#     oos_retention / portfolio_alpha_t (+oos_months, selection_type, record_type).
#     기존 metrics=list(...) 자유목록 전달도 계속 동작 (back-compat — 1급 인자가 우선).
#   - WARN 정책: metric_type=backtested/canonical_screen인데 portfolio_alpha_t/oos_retention
#     결측이면 WARN 출력. **BLOCK 승격은 2사이클 관찰 후 도훈 confirm — 지금 미도입.**
#   - normalize_lcode 경유: grade legacy alias→canonical, research_mode qepm→qepm_legacy,
#     construction_type에 chain/sweep 유입 시 selection_type으로 분리.
#   - 신규 ID 채번 중복 가드(A1-F6 재발 방지): 자동 채번 l_code가 기존 원장과 충돌 시
#     suffix 재발급. strategy_id 파일 덮어쓰기 시 l_code 상이하면 WARN.
#
# metric_type: QEPM/factor_rotation/RAMP = backtested(build_bt_result+essence_score)
#              → INV-1상 global 승격 가능. canonical_screen = canonical_screen_bt 실측.
#              (alpha_search만 proxy → run_alpha_search.R::.write_lcode에서 별도 적립.)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

.LCODE_MODE_PREFIX <- c(alpha_search = "AS", alpha_research = "AR", qepm_legacy = "QPM",
                        judge_gate = "JG", governor_admission = "GV",
                        factor_rotation = "FR", regime_research = "RR",
                        ramp = "RAMP", overlay_research = "OVL")

# 기존 원장에서 사용 중인 l_code ID 집합 (충돌 가드용 — corpus 캐시 + 원장 파일 스캔)
.existing_lcode_ids <- function(root) {
  ids <- character(0)
  cp <- file.path(root, ".cache", "lcode_corpus.json")
  if (file.exists(cp)) {
    co <- tryCatch(jsonlite::fromJSON(cp, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(co)) ids <- vapply(co$lcodes %||% list(), function(x) as.character(x$l_code %||% ""), character(1))
  }
  # corpus가 stale할 수 있으므로 최근 수정 원장 파일도 스캔 (파일명 기준 경량)
  lc_root <- file.path(root, "stage_artifacts", "l_code")
  files <- c(list.files(file.path(root, "stage_artifacts"), pattern = "^l_code_.*\\.json$", full.names = TRUE),
             if (dir.exists(lc_root)) list.files(lc_root, pattern = "^l_code_.*\\.json$", recursive = TRUE, full.names = TRUE))
  recent <- files[file.mtime(files) > Sys.time() - 7 * 86400]  # 최근 7일분만 내용 파싱 (corpus 미반영분)
  for (f in recent) {
    d <- tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(d) && !is.null(d$l_code)) ids <- c(ids, as.character(d$l_code))
  }
  unique(ids[nzchar(ids)])
}

# 핵심 진입점 (v2 시그니처 — 승격축 4필드 1급 인자. 기존 호출 back-compat 유지).
# falsification_attempts: list(list(test=, result=survived|falsified|weakened, effect_retained=), ...)
#                         (문자열도 수용하되 WARN — 구조체 권장)
emit_lcode <- function(mode, strategy_id, grade, lesson_text,
                       metric_type = "backtested", construction_type = NULL,
                       mechanism_hypothesis = NULL,
                       falsification_attempts = NULL,
                       oos_retention = NULL, oos_months = NULL,
                       portfolio_alpha_t = NULL,
                       selection_type = NULL, record_type = NULL,
                       core_reference = "",
                       tags = NULL, metrics = list(), project_root = NULL,
                       l_code = NULL, dry_run = FALSE) {
  suppressPackageStartupMessages(library(jsonlite))
  root <- project_root %||% Sys.getenv("CLAUDE_PROJECT_DIR",
            Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
  schema_src <- file.path(root, "02_Infrastructure", "axiom", "lcode_schema.R")
  if (file.exists(schema_src)) source(schema_src, local = TRUE)
  # P0#5 emit 방화벽 backstop (그룹 F3): 제약-귀속/완화-레버 위반이 원장에 오염표식 없이
  # 유입되던 갭 배선. constraint_firewall.R는 그룹 밖 — source만. backstop 모드(결정론
  # 1차 필터, 비-소진적)로 lesson_text/mechanism_hypothesis/next_probe를 검사. ★emit은
  # 막지 않는다(원장 정직 기록 유지) — firewall_violation=TRUE 플래그 + WARN만 부착해
  # 원시 조회에도 오염 표식이 따라가게 한다.
  fw_src <- file.path(root, "02_Infrastructure", "axiom", "constraint_firewall.R")
  if (file.exists(fw_src)) source(fw_src, local = TRUE)

  # back-compat: 1급 인자 미전달 + metrics 자유목록에 있으면 승격 (1급 인자가 우선)
  .pick <- function(arg, key) arg %||% metrics[[key]]
  mechanism_hypothesis   <- .pick(mechanism_hypothesis, "mechanism_hypothesis")
  falsification_attempts <- .pick(falsification_attempts, "falsification_attempts")
  oos_retention          <- .pick(oos_retention, "oos_retention")
  oos_months             <- .pick(oos_months, "oos_months")
  portfolio_alpha_t      <- .pick(portfolio_alpha_t, "portfolio_alpha_t")
  selection_type         <- .pick(selection_type, "selection_type")
  record_type            <- .pick(record_type, "record_type")
  metrics <- metrics[setdiff(names(metrics),
    c("mechanism_hypothesis", "falsification_attempts", "oos_retention", "oos_months",
      "portfolio_alpha_t", "selection_type", "record_type"))]

  # construction_type 미전달 → 키워드 추론 폴백 (WARN — 승격축 정확도는 명시 전달이 우선)
  ct_inferred <- FALSE
  if (!nzchar(as.character(construction_type %||% "")) &&
      exists("infer_construction_type", mode = "function")) {
    construction_type <- infer_construction_type(strategy_id, lesson_text)
    ct_inferred <- TRUE
  }

  prefix <- .LCODE_MODE_PREFIX[[mode]] %||% "GEN"
  auto_id <- is.null(l_code)
  if (auto_id)
    l_code <- sprintf("L-%s-%s", prefix, format(Sys.time(), "%Y%m%d_%H%M%S"))

  lcode <- c(list(
    l_code            = l_code,
    strategy_id       = strategy_id,
    grade             = grade,
    core_reference    = core_reference,
    lesson_text       = lesson_text,
    tags              = tags %||% toupper(mode),
    created_at        = format(Sys.Date()),
    research_mode     = mode,
    created_by        = sprintf("emit:%s", mode),
    metric_type       = metric_type,
    construction_type = construction_type %||% "",
    mechanism_hypothesis = mechanism_hypothesis %||% "",
    lcode_schema_version = if (exists("LCODE_SCHEMA_VERSION")) LCODE_SCHEMA_VERSION else 2L
  ), metrics)
  # 승격축/분류 필드 — 값 있을 때만 기록 (없는 필드 = 정직한 결측)
  if (!is.null(falsification_attempts)) lcode$falsification_attempts <- falsification_attempts
  if (!is.null(oos_retention))          lcode$oos_retention <- oos_retention
  if (!is.null(oos_months))             lcode$oos_months <- oos_months
  if (!is.null(portfolio_alpha_t))      lcode$portfolio_alpha_t <- portfolio_alpha_t
  if (!is.null(selection_type))         lcode$selection_type <- selection_type
  if (!is.null(record_type))            lcode$record_type <- record_type

  # P0#5 emit 방화벽 backstop 게이트 — 제약-귀속/완화-레버 위반 오염표식 부착 (emit 비차단)
  if (exists("check_constraint_firewall", mode = "function")) {
    fw_text <- paste(c(lesson_text, mechanism_hypothesis,
                       lcode$next_probe %||% metrics[["next_probe"]] %||% NULL),
                     collapse = " \n ")
    fw <- tryCatch(check_constraint_firewall(fw_text, mode = "backstop"),
                   error = function(e) NULL)
    if (!is.null(fw) && isFALSE(fw$pass)) {
      lcode$firewall_violation <- TRUE
      lcode$firewall_note <- paste(vapply(fw$violations, function(v)
        sprintf("[%s] %s", v$pattern_class %||% "?", v$matched %||% ""), character(1)),
        collapse = "; ")
      cat(sprintf("[emit_lcode][WARN][firewall] %s: 제약 방화벽 backstop 위반 감지 (firewall_violation=TRUE, emit 비차단·오염표식) — %s\n",
                  l_code, lcode$firewall_note))
    }
  }

  # normalize (grade alias / qepm→qepm_legacy / construction↔selection 분리)
  if (exists("normalize_lcode", mode = "function")) {
    nz <- normalize_lcode(lcode)
    lcode <- nz$lcode
    if (length(nz$notes))
      cat(sprintf("[emit_lcode][normalize] %s: %s\n", l_code, paste(nz$notes, collapse = "; ")))
  }
  if (ct_inferred)
    cat(sprintf("[emit_lcode][WARN] %s: construction_type 미전달 → '%s' 키워드 추론 (명시 전달 권장)\n",
                l_code, lcode$construction_type %||% ""))

  if (exists("validate_lcode", mode = "function")) {
    v <- validate_lcode(lcode)  # strict=FALSE: required_for_promotion 결측 = WARN
                                # (BLOCK 승격은 2사이클 관찰 후 도훈 confirm — 지금 미도입)
    if (!isTRUE(v$valid)) {
      cat(sprintf("[emit_lcode][BLOCKED] %s/%s: %s\n", mode, strategy_id, paste(v$errors, collapse = "; ")))
      return(invisible(NULL))
    }
    if (length(v$warnings))
      cat(sprintf("[emit_lcode][WARN] %s: %s\n", l_code, paste(v$warnings, collapse = "; ")))
    if (!isTRUE(v$promotion_ready))
      cat(sprintf("[emit_lcode][WARN] %s: 승격축 입력 미완(promotion_ready=FALSE) — missing: %s\n",
                  l_code, paste(v$missing_promotion_fields, collapse = ", ")))
  } else {
    # [2026-07-17 운영감사 A4] validate fail-open 봉합 — lcode_schema.R 미로드 시에도
    # 최소 게이트(metric_type enum)는 실경유. 비enum 신조어('observational_monitoring',
    # l_code_R42 실물)가 BLOCKED 없이 디스크 착지하던 갭. fail-soft 보존: enum 통과분은
    # WARN 후 emit 계속 (전체 스키마 검증은 schema 복구 후 harvester 재검증이 담당).
    cat(sprintf("[emit_lcode][WARN] lcode_schema.R 미로드(%s) — metric_type enum 폴백 게이트로 검증\n", schema_src))
    .mt_enum <- c("proxy", "estimated", "canonical_screen", "backtested", "unavailable")
    mt_chk <- as.character(lcode$metric_type %||% "")
    if (!(mt_chk %in% .mt_enum)) {
      cat(sprintf("[emit_lcode][BLOCKED] %s/%s: metric_type='%s' 비표준 (허용: %s) — 폴백 enum 게이트\n",
                  mode, strategy_id, mt_chk, paste(.mt_enum, collapse = "/")))
      return(invisible(NULL))
    }
  }
  if (isTRUE(dry_run)) {
    cat(sprintf("[emit_lcode][dry-run] %s (%s, %s)\n", lcode$l_code, mode, metric_type))
    return(invisible(lcode))
  }

  # 신규 ID 채번 중복 가드 (A1-F6 재발 방지): 자동 채번분만 — 명시 l_code는 호출자 책임
  if (auto_id) {
    existing <- tryCatch(.existing_lcode_ids(root), error = function(e) character(0))
    if (lcode$l_code %in% existing) {
      k <- 2L
      while (sprintf("%s_%02d", lcode$l_code, k) %in% existing) k <- k + 1L
      new_id <- sprintf("%s_%02d", lcode$l_code, k)
      cat(sprintf("[emit_lcode][WARN] l_code 충돌 감지: %s 기존재 → %s 재발급\n", lcode$l_code, new_id))
      lcode$l_code <- new_id
    }
  }

  lc_dir <- file.path(root, "stage_artifacts", "l_code", mode)
  dir.create(lc_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(lc_dir, sprintf("l_code_%s.json", strategy_id))
  if (file.exists(path)) {
    old <- tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(old) && !identical(as.character(old$l_code %||% ""), as.character(lcode$l_code)))
      cat(sprintf("[emit_lcode][WARN] %s 덮어쓰기: 기존 l_code=%s ≠ 신규 %s (동일 strategy 재적립 확인)\n",
                  basename(path), old$l_code %||% "?", lcode$l_code))
  }
  write_json(lcode, path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[emit_lcode] %s 적립: %s\n", mode, path))
  path
}

# ── QEPM 편의 wrapper: judge gate FAIL / governor DEFER / alpha 검증 실패 ──
#   v2: 승격축 4필드(mechanism_hypothesis/falsification_attempts/oos_retention/
#   portfolio_alpha_t)를 ...로 그대로 전달 가능 (emit_lcode 1급 인자).
emit_qepm_lcode <- function(strategy_id, grade, lesson_text,
                            source = c("judge_gate", "governor_admission", "alpha_research"),
                            metric_type = "backtested", ...) {
  source <- match.arg(source)
  emit_lcode(mode = source, strategy_id = strategy_id, grade = grade,
             lesson_text = lesson_text, metric_type = metric_type, ...)
}

# ── factor_rotation 편의 wrapper: Track1 regime 판별력 / Track2 RCMA / 로테이션 결과 ──
emit_fr_lcode <- function(strategy_id, grade, lesson_text,
                          track = c("factor_rotation", "regime_research"),
                          metric_type = "backtested", ...) {
  track <- match.arg(track)
  emit_lcode(mode = track, strategy_id = strategy_id, grade = grade,
             lesson_text = lesson_text, metric_type = metric_type, ...)
}

# ── RAMP 편의 wrapper: Gate별 교훈(순수팩터 생존/사멸, 잠재팩터 구조, M-code 국면적합, 잔차-α) ──
# RAMP modecode=RAMP, 티어=backtested(canonical_screen_bt/build_bt_result) → INV-1상 global 승격 자격.
emit_ramp_lcode <- function(strategy_id, grade, lesson_text,
                            metric_type = "backtested", ...) {
  emit_lcode(mode = "ramp", strategy_id = strategy_id, grade = grade,
             lesson_text = lesson_text, metric_type = metric_type, ...)
}

if (sys.nframe() == 0L && !interactive()) {
  # 1) v2 완전체 — 승격축 4필드 1급 인자 (promotion_ready 기대)
  r1 <- emit_fr_lcode("FR_TEST_001", "C",
         "현 12-모듈 풀 로테이션·오버레이 OOS 무가치(EW 천장), 직교 슬리브 추가가 선행조건.",
         track = "factor_rotation", construction_type = "regime_rotation",
         mechanism_hypothesis = "모듈 간 return 상관 高 → 국면배분 분산효익 미미, EW 대비 edge 0",
         falsification_attempts = list(
           list(test = "EW 벤치 대비 paired NW-t", result = "survived", effect_retained = 0.9),
           list(test = "regime 라벨 셔플 placebo", result = "survived", effect_retained = 0.8)),
         oos_retention = 0.55, portfolio_alpha_t = 1.1, selection_type = "chain",
         metrics = list(cagr_pct = 8.2, sharpe = 0.9, mdd_pct = 22, excess_cagr = 1.1),
         dry_run = TRUE)
  # 2) 구 시그니처 호출 back-compat — metrics 자유목록 + 승격축 미전달 (WARN 나오되 dry-run 성공)
  r2 <- emit_qepm_lcode("STR_TEST_OLDSTYLE", "F",
         "구 스타일 호출 — 승격축 미전달이어도 적립은 차단하지 않는다 (WARN only).",
         source = "judge_gate",
         metrics = list(sharpe = 0.4, portfolio_alpha_t = 2.1), dry_run = TRUE)
  # 3) legacy grade alias + qepm 스타일 normalize 확인
  r3 <- emit_lcode("ramp", "RAMP_TEST_002", "A_DEF",
         "legacy alias grade 전달 시 canonical A로 normalize 되는지 확인용 dry-run.",
         mechanism_hypothesis = "저변동 방어 팩터의 위기 조건부 보상 구조 확인",
         construction_type = "low_vol", oos_retention = 0.7, portfolio_alpha_t = 3.0,
         falsification_attempts = list(list(test = "subperiod split", result = "survived", effect_retained = 0.75)),
         dry_run = TRUE)
  cat(sprintf("[lcode_emit v2 selftest] r1=%s r2=%s r3=%s(grade=%s)\n",
              !is.null(r1), !is.null(r2), !is.null(r3), r3$grade %||% "?"))
  stopifnot(!is.null(r1), !is.null(r2), !is.null(r3), identical(r3$grade, "A"),
            identical(r2$portfolio_alpha_t, 2.1))  # metrics 자유목록 → 1급 필드 승격 확인
  cat("  PASS (3 cases)\n")
}
