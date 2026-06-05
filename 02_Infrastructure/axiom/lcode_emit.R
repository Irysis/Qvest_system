# lcode_emit.R — 모드별 L-code 적립 helper (v8.0 Phase 1, 3-mode axiom 엔진)
#
# alpha_search 외 모드(QEPM / factor_rotation)가 백테스트 교훈을 L-code로 적립한다.
# 모두 validate_lcode(lcode_schema.R) 게이트를 경유하고 모드별 디렉터리
# stage_artifacts/l_code/<mode>/ 에 쓴다. research_mode 필드를 명시하므로
# harvester _infer_mode가 explicit로 인식한다.
#
# metric_type: QEPM/factor_rotation = backtested(build_bt_result+essence_score) → INV-1상 global 승격 가능.
#              (alpha_search만 proxy → run_alpha_search.R::.write_lcode에서 별도 적립.)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

.LCODE_MODE_PREFIX <- c(alpha_search = "AS", alpha_research = "AR", qepm_legacy = "QPM",
                        judge_gate = "JG", governor_admission = "GV",
                        factor_rotation = "FR", regime_research = "RR")

# 핵심 진입점. metrics = list(cagr_pct=, sharpe=, mdd_pct=, excess_cagr=, portfolio_alpha_t=, ...)
emit_lcode <- function(mode, strategy_id, grade, lesson_text,
                       metric_type = "backtested", construction_type = NULL,
                       mechanism_hypothesis = NULL, core_reference = "",
                       tags = NULL, metrics = list(), project_root = NULL,
                       l_code = NULL, dry_run = FALSE) {
  suppressPackageStartupMessages(library(jsonlite))
  root <- project_root %||% Sys.getenv("CLAUDE_PROJECT_DIR",
            Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
  schema_src <- file.path(root, "02_Infrastructure", "axiom", "lcode_schema.R")
  if (file.exists(schema_src)) source(schema_src, local = TRUE)

  prefix <- .LCODE_MODE_PREFIX[[mode]] %||% "GEN"
  if (is.null(l_code))
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
    mechanism_hypothesis = mechanism_hypothesis %||% ""
  ), metrics)

  if (exists("validate_lcode", mode = "function")) {
    v <- validate_lcode(lcode)
    if (!isTRUE(v$valid)) {
      cat(sprintf("[emit_lcode][BLOCKED] %s/%s: %s\n", mode, strategy_id, paste(v$errors, collapse = "; ")))
      return(invisible(NULL))
    }
    if (length(v$warnings))
      cat(sprintf("[emit_lcode][WARN] %s: %s\n", l_code, paste(v$warnings, collapse = "; ")))
  }
  if (isTRUE(dry_run)) {
    cat(sprintf("[emit_lcode][dry-run] %s (%s, %s)\n", l_code, mode, metric_type))
    return(invisible(lcode))
  }

  lc_dir <- file.path(root, "stage_artifacts", "l_code", mode)
  dir.create(lc_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(lc_dir, sprintf("l_code_%s.json", strategy_id))
  write_json(lcode, path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[emit_lcode] %s 적립: %s\n", mode, path))
  path
}

# ── QEPM 편의 wrapper: judge gate FAIL / governor DEFER / alpha 검증 실패 ──
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

if (sys.nframe() == 0L && !interactive()) {
  r <- emit_fr_lcode("FR_TEST_001", "C",
         "현 12-모듈 풀 로테이션·오버레이 OOS 무가치(EW 천장), 직교 슬리브 추가가 선행조건.",
         track = "factor_rotation", construction_type = "regime_rotation",
         mechanism_hypothesis = "모듈 간 return 상관 高 → 국면배분 분산효익 미미, EW 대비 edge 0",
         metrics = list(cagr_pct = 8.2, sharpe = 0.9, mdd_pct = 22, excess_cagr = 1.1),
         dry_run = TRUE)
  cat(sprintf("[lcode_emit selftest] dry-run ok=%s\n", !is.null(r)))
  stopifnot(!is.null(r))
  cat("  PASS\n")
}
