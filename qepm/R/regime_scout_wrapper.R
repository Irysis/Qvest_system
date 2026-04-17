# v53 Sprint 1: Regime Scout Wrapper
# 기존 02_Infrastructure/regime/regime_engine_daily.R 등 14개 무변경
# 일 1회 호출:
#   - .cache/conditional_ic_matrix_4regime.csv 갱신
#   - .cache/axiom_signals.json에 regime_blackout entries 추가

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

.regime_root <- function() {
  cands <- c(
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

regime_scout_update <- function(root = .regime_root()) {
  cache_dir <- file.path(root, ".cache")
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)

  # 1) 4-regime conditional IC 매트릭스 갱신 (기존 엔진 호출)
  daily_engine <- file.path(root, "02_Infrastructure/regime/regime_engine_daily.R")
  if (file.exists(daily_engine)) {
    tryCatch(source(daily_engine, local = new.env()), error = function(e) {
      message("[regime_scout] daily engine source failed: ", conditionMessage(e))
    })
  }

  # 2) 최신 regime 상태 (unified_regime_signal.parquet)
  unified <- file.path(cache_dir, "unified_regime_signal.parquet")
  latest <- NULL
  if (file.exists(unified)) {
    tryCatch({
      arrow_ok <- requireNamespace("arrow", quietly = TRUE)
      if (arrow_ok) {
        dt <- as.data.table(arrow::read_parquet(unified))
        if (nrow(dt) > 0) latest <- dt[.N]
      }
    }, error = function(e) NULL)
  }

  # 3) axiom_signals.json에 regime_blackout 반영
  sig_path <- file.path(cache_dir, "axiom_signals.json")
  sig <- if (file.exists(sig_path)) {
    tryCatch(jsonlite::fromJSON(sig_path, simplifyVector = FALSE), error = function(e) list())
  } else list()

  if (is.null(sig$regime_blackout)) sig$regime_blackout <- list(entries = list())
  if (!is.null(latest) && "regime_category" %in% names(latest)) {
    entry <- list(
      date = as.character(Sys.Date()),
      category = as.character(latest$regime_category),
      score = if ("regime_score" %in% names(latest)) as.numeric(latest$regime_score) else NA_real_,
      note = "regime_scout_wrapper daily update"
    )
    # 최근 30건만 유지
    sig$regime_blackout$entries <- c(list(entry), sig$regime_blackout$entries)
    if (length(sig$regime_blackout$entries) > 30) {
      sig$regime_blackout$entries <- sig$regime_blackout$entries[1:30]
    }
  }
  sig$updated_at <- as.character(Sys.time())

  jsonlite::write_json(
    sig, sig_path, auto_unbox = TRUE, pretty = TRUE, null = "null"
  )

  cat(sprintf("[regime_scout] updated signals at %s\n", Sys.time()))
  invisible(list(latest = latest, signals_path = sig_path))
}

# 직접 실행 시
if (!interactive() && identical(sys.nframe(), 0L)) {
  regime_scout_update()
}
