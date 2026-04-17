# v53 Sprint 1: Briefing Daily (5% → 50%)
# 일 1회 텔레그램 전송:
#   - Grade 카운트 (A / B / C / F)
#   - 최신 L-code 5건
#   - memory drift 상태 (stale 파일)
#   - 현재 regime + portfolio gap

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

.brief_root <- function() {
  cands <- c(
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

.count_grades <- function(root) {
  dir <- file.path(root, "04_Research/strategies")
  if (!dir.exists(dir)) return(list(A = 0, B = 0, C = 0, F = 0))
  files <- list.files(dir, pattern = "hurdle_result\\.json$", recursive = TRUE, full.names = TRUE)
  counts <- list(A = 0, B = 0, C = 0, F = 0, A_NOVEL = 0, A_CONDITIONAL = 0)
  for (f in files) {
    g <- tryCatch({
      d <- jsonlite::fromJSON(f, simplifyVector = TRUE)
      v <- if (!is.null(d$verdict)) d$verdict else d
      as.character(v$grade %||% "F")
    }, error = function(e) "F")
    if (!is.null(counts[[g]])) counts[[g]] <- counts[[g]] + 1
  }
  counts
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a

.latest_lcodes <- function(root, n = 5) {
  mm <- file.path(root, "qepm/memory/methodology_memory.md")
  if (!file.exists(mm)) return(character(0))
  lines <- readLines(mm, warn = FALSE)
  lcodes <- grep("^L-[0-9]{3}", lines, value = TRUE)
  tail(lcodes, n)
}

.gap_summary <- function(root) {
  gap_path <- file.path(root, ".cache/portfolio_gap_vector.json")
  if (!file.exists(gap_path)) return(list())
  tryCatch(jsonlite::fromJSON(gap_path, simplifyVector = TRUE), error = function(e) list())
}

.memory_health <- function(root) {
  files <- c("MEMORY.md", "methodology_memory.md", "evolution_roadmap.md")
  mem_dir <- file.path(root, "qepm/memory")
  stale <- c()
  for (f in files) {
    p <- file.path(mem_dir, f)
    if (file.exists(p)) {
      age <- as.integer(Sys.Date() - as.Date(file.info(p)$mtime))
      if (!is.na(age) && age > 3) stale <- c(stale, sprintf("%s(%dd)", f, age))
    }
  }
  stale
}

briefing_daily <- function(root = .brief_root(), dry_run = FALSE) {
  grades <- .count_grades(root)
  lcodes <- .latest_lcodes(root, 5)
  gap <- .gap_summary(root)
  stale <- .memory_health(root)

  lines <- c(
    sprintf("\U0001F4CA [Q-Lead] Daily Brief %s", format(Sys.Date(), "%Y-%m-%d")),
    "",
    sprintf("\U0001F3C6 Grade: A=%d A_NOVEL=%d A_COND=%d | B=%d | C=%d | F=%d",
            grades$A, grades$A_NOVEL, grades$A_CONDITIONAL, grades$B, grades$C, grades$F),
    sprintf("\U0001F4CD Regime: %s (score %.1f)",
            gap$regime_state$category %||% "?", as.numeric(gap$regime_state$score %||% NA)),
    sprintf("\U0001F3AF Gap: SR %+.3f | CAGR %+.1f%% | MDD %+.1f%% | sleeve=%s",
            as.numeric(gap$gap$sharpe_gap %||% NA),
            100 * as.numeric(gap$gap$cagr_gap %||% NA),
            100 * as.numeric(gap$gap$mdd_gap %||% NA),
            paste(gap$sleeve_needs %||% "-", collapse = "+")),
    "",
    "\U0001F4DA Latest L-codes:",
    paste0("  - ", lcodes, collapse = "\n")
  )
  if (length(stale) > 0) {
    lines <- c(lines, "", sprintf("\u26A0\uFE0F Memory stale: %s", paste(stale, collapse = ", ")))
  }
  msg <- paste(lines, collapse = "\n")

  if (dry_run) {
    cat(msg, "\n", sep = "")
    return(invisible(msg))
  }
  # 실제 텔레그램 전송
  tg_path <- file.path(root, "02_Infrastructure/telegram/telegram_notify.R")
  if (file.exists(tg_path)) {
    tryCatch({
      source(tg_path, local = TRUE)
      if (exists("tg_send", mode = "function")) tg_send(msg)
    }, error = function(e) {
      message("[briefing_daily] tg_send failed: ", conditionMessage(e))
      cat(msg, "\n", sep = "")
    })
  } else {
    cat(msg, "\n", sep = "")
  }
  invisible(msg)
}

# 직접 실행
if (!interactive() && identical(sys.nframe(), 0L)) {
  briefing_daily()
}
