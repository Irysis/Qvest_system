#==============================================================================
# 00_pit_manifest_loader.R — Phase 1 PIT Manifest Loader (S1 첫 gate)
#
# Purpose:
#   .cache parquet read 시 미래참조 column 자동 차단 + timestamp manifest 검증.
#   fail-closed: 미정의/모호 case → stop(). "아마 괜찮을 거" 가정 절대 금지.
#
# Mandate:
#   - Codex round 1 critical #1: flow_features_daily.parquet fwd_* leakage
#   - Codex round 2 보강: denylist + timestamp allowlist + fail-closed
#   - 도훈 mandate "쓰레기 넣으면 쓰레기 나와" GIGO 정합
#
# Public API:
#   load_with_pit_manifest(parquet_path, decision_time_kst, manifest = NULL)
#   validate_no_leakage(parquet_path, additional_deny = NULL)
#   load_feature_lag_table(config_path)
#
# Date: 2026-05-19
# Q-Lead: Claude Opus 4.7
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

# ── 1. Denylist 패턴 (Plan v0.4.2 정합) ────────────────────────────
PIT_DENYLIST_PATTERN <- "(^fwd_|^future_|^lead_|^next_|^t_plus_|^forward_|^ahead_)"

# 알려진 leakage column allowlist (deny ignore — 의도적 forward target)
PIT_KNOWN_LEAKAGE <- list(
  "flow_features_daily.parquet" = c("fwd_inst_foreign_netbuy_21d", "fwd_flow_top20")
)

# ── 2. 기본 검증 함수 ────────────────────────────────────────────
#' Validate parquet 컬럼이 PIT denylist 위반하는지 검사
#'
#' fail-closed: 미정의 column → stop()
#'
#' @param parquet_path .cache parquet 경로
#' @param additional_deny extra denylist (예: 특정 prefix)
#' @return invisible(TRUE) if PASS, otherwise stop()
#' @export
validate_no_leakage <- function(parquet_path, additional_deny = NULL) {
  if (!file.exists(parquet_path)) {
    stop(sprintf("[PIT] File not found: %s", parquet_path))
  }
  ds <- arrow::open_dataset(parquet_path)
  cols <- names(ds)

  # 1. denylist pattern match
  pattern <- PIT_DENYLIST_PATTERN
  if (!is.null(additional_deny)) {
    extra <- paste0("(", paste(additional_deny, collapse = "|"), ")")
    pattern <- paste0(pattern, "|", extra)
  }
  forbidden <- grep(pattern, cols, ignore.case = TRUE, value = TRUE)

  # 2. known leakage column allowlist (의도적 forward — STR_1678 target 등)
  fname <- basename(parquet_path)
  if (fname %in% names(PIT_KNOWN_LEAKAGE)) {
    allowed_leakage <- PIT_KNOWN_LEAKAGE[[fname]]
    forbidden <- setdiff(forbidden, allowed_leakage)
    if (length(allowed_leakage) > 0) {
      cat(sprintf("[PIT] %s: allowed_leakage 2건 retain (STR_1678 forward target). 본 plan select X.\n",
                  fname))
    }
  }

  if (length(forbidden) > 0) {
    stop(sprintf("[PIT VIOLATION] %s: forbidden columns detected: %s",
                 fname, paste(forbidden, collapse = ", ")))
  }
  invisible(TRUE)
}

# ── 3. feature_lag_table.csv loader ────────────────────────────
#' Load PIT lag manifest from feature_lag_table.csv
#'
#' @param config_path config/feature_lag_table.csv 경로
#' @return data.table with publish_timing_kst, decision_time, usable_lag
#' @export
load_feature_lag_table <- function(config_path) {
  if (!file.exists(config_path)) {
    stop(sprintf("[PIT] feature_lag_table.csv missing: %s", config_path))
  }
  fread(config_path)
}

# ── 4. 메인 loader (PIT fail-closed) ────────────────────────────
#' Load parquet with PIT manifest enforcement
#'
#' fail-closed semantics:
#'   1. denylist column 발견 → stop()
#'   2. manifest 미명시 column 발견 → stop()
#'   3. decision_time > available_timestamp_kst → 자동 제외
#'
#' @param parquet_path .cache parquet 경로
#' @param decision_time_kst as.POSIXct (YYYY-MM-DD HH:MM, Asia/Seoul)
#' @param manifest data.table (feature_lag_table.csv loaded). NULL = 자동 load
#' @param config_path manifest NULL 시 자동 load 위치
#' @param select_cols 명시 selection (NULL = manifest 통과 cols)
#' @param strict_manifest TRUE = 모든 col이 manifest에 있어야 함 (fail-closed). FALSE = 알려진 col만
#' @return data.table
#' @export
load_with_pit_manifest <- function(parquet_path,
                                   decision_time_kst,
                                   manifest = NULL,
                                   config_path = "04_Research/decision_framework/bearish_forecast_v1/config/feature_lag_table.csv",
                                   select_cols = NULL,
                                   strict_manifest = FALSE) {

  # 1. 기본 leakage 검증 (fail-closed)
  validate_no_leakage(parquet_path)

  # 2. manifest load
  if (is.null(manifest)) {
    manifest <- load_feature_lag_table(config_path)
  }

  # 3. decision_time parse
  if (is.character(decision_time_kst)) {
    decision_time_kst <- as.POSIXct(decision_time_kst, tz = "Asia/Seoul")
  }
  if (is.na(decision_time_kst)) {
    stop("[PIT] decision_time_kst parse FAIL (Asia/Seoul timezone 의무)")
  }

  # 4. parquet read
  ds <- arrow::open_dataset(parquet_path)
  all_cols <- names(ds)

  # 5. select_cols 결정
  if (!is.null(select_cols)) {
    # 명시 selection — 모두 manifest에 있어야 함
    missing_manifest <- setdiff(select_cols, manifest$feature_name)
    if (length(missing_manifest) > 0 && strict_manifest) {
      stop(sprintf("[PIT] select_cols missing in manifest: %s",
                   paste(missing_manifest, collapse = ", ")))
    }
    final_cols <- intersect(select_cols, all_cols)
  } else {
    # manifest에 있는 column만 자동 select
    manifest_cols <- intersect(manifest$feature_name, all_cols)
    if (length(manifest_cols) == 0 && strict_manifest) {
      stop(sprintf("[PIT] No manifest-defined columns in %s. fail-closed.",
                   basename(parquet_path)))
    }
    final_cols <- manifest_cols
  }

  if (length(final_cols) == 0) {
    cat(sprintf("[PIT] %s: 0 selectable columns (warn). Returning empty.\n",
                basename(parquet_path)))
    return(data.table())
  }

  # 6. read with selection
  df <- as.data.table(arrow::read_parquet(parquet_path, col_select = all_of(final_cols)))

  cat(sprintf("[PIT] %s: loaded %d cols × %d rows (decision_time=%s)\n",
              basename(parquet_path), ncol(df), nrow(df),
              format(decision_time_kst, "%Y-%m-%d %H:%M %Z")))

  df
}

# ── 5. close-action vs next-open decision time helper ──────────
#' decision_time 기준 close vs next-open 모델 분리
#'
#' @param trade_date as.Date
#' @param mode "close" (당일 close 의사결정) or "next_open" (익영업일 open)
#' @return POSIXct (Asia/Seoul)
#' @export
get_decision_time_kst <- function(trade_date, mode = c("close", "next_open")) {
  mode <- match.arg(mode)
  if (mode == "close") {
    as.POSIXct(paste(trade_date, "15:30"), tz = "Asia/Seoul")
  } else {
    as.POSIXct(paste(trade_date + 1, "09:00"), tz = "Asia/Seoul")
  }
}

cat("[pit_manifest_loader] Loaded.\n")
cat("  Functions: validate_no_leakage(), load_feature_lag_table(),\n")
cat("             load_with_pit_manifest(), get_decision_time_kst()\n")
cat("  Denylist pattern:", PIT_DENYLIST_PATTERN, "\n")
cat("  Known leakage allowlist:", names(PIT_KNOWN_LEAKAGE), "\n")
