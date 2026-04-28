## Forward Weights Orchestrator (Phase 1, Plan v1.0 2026-04-29)
##
## Goal: 3 마일스톤 admitted 전략의 forward production weights 통합 entry-point
##   - STR_1715 (현 PG2 100%)
##   - STR_1631_SYN_06 (이전 PG2 80% diversifier 기반)
##   - STR_1656_MLRA_M05 (ML diversifier; STUB Phase 1)
##
## 도훈 명령 enforcement:
##   - apply_mandate_cap = "cap_0.20" default 강제
##   - measurement_basis_primary = "forge_realized_share_based"
##   - 추정 표현 금지

suppressMessages({
  library(data.table); library(jsonlite)
})
options(scipen = 999)

orchestrate_forward_weights <- function(
  as_of_date         = NULL,
  apply_mandate_cap  = "cap_0.20",
  strategies         = c("STR_1715", "STR_1631_SYN_06", "STR_1656_MLRA"),
  send_telegram      = FALSE,
  manifest_root      = NULL
) {
  PROJECT_ROOT <- normalizePath(file.path(
    dirname(sys.frame(1)$ofile %||% getwd()), "..", ".."))

  results <- list()

  if ("STR_1715" %in% strategies) {
    cat("\n========== STR_1715 ==========\n")
    src_path <- file.path(
      PROJECT_ROOT,
      "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/forward_weights.R")
    if (file.exists(src_path)) {
      source(src_path, local = TRUE, chdir = TRUE)
      res <- generate_forward_weights_str1715(
        as_of_date = as_of_date, apply_mandate_cap = apply_mandate_cap)
      results[["STR_1715"]] <- res$manifest
    } else {
      cat("[orchestrator] STR_1715 forward_weights.R not found\n")
      results[["STR_1715"]] <- list(status = "MISSING_WRAPPER")
    }
  }

  if ("STR_1631_SYN_06" %in% strategies) {
    cat("\n========== STR_1631_SYN_06 ==========\n")
    src_path <- file.path(
      PROJECT_ROOT,
      "04_Research/strategies/STR_1631_SYN_06/forward_weights.R")
    if (file.exists(src_path)) {
      source(src_path, local = TRUE, chdir = TRUE)
      res <- generate_forward_weights_str1631_syn06(
        as_of_date = as_of_date, apply_mandate_cap = apply_mandate_cap)
      results[["STR_1631_SYN_06"]] <- res$manifest
    } else {
      cat("[orchestrator] STR_1631_SYN_06 forward_weights.R not found\n")
      results[["STR_1631_SYN_06"]] <- list(status = "MISSING_WRAPPER")
    }
  }

  if ("STR_1656_MLRA" %in% strategies) {
    cat("\n========== STR_1656_MLRA_M05 ==========\n")
    src_path <- file.path(
      PROJECT_ROOT,
      "04_Research/strategies/STR_1656_MLRA/forward_weights.R")
    if (file.exists(src_path)) {
      source(src_path, local = TRUE, chdir = TRUE)
      res <- generate_forward_weights_str1656_mlra(
        as_of_date = as_of_date, apply_mandate_cap = apply_mandate_cap)
      results[["STR_1656_MLRA"]] <- res$manifest
    } else {
      cat("[orchestrator] STR_1656_MLRA forward_weights.R not found\n")
      results[["STR_1656_MLRA"]] <- list(status = "MISSING_WRAPPER")
    }
  }

  # ─── Manifest 통합 저장 ──────────────────────────────
  if (is.null(manifest_root)) {
    manifest_root <- file.path(PROJECT_ROOT, "qepm/mailbox/governor/forward_weights_manifests")
  }
  dir.create(manifest_root, recursive = TRUE, showWarnings = FALSE)

  date_tag <- if (is.null(as_of_date)) format(Sys.Date(), "%Y%m%d") else
              format(as.Date(as_of_date), "%Y%m%d")
  manifest_path <- file.path(manifest_root,
                              sprintf("manifest_%s_%s.json", date_tag, apply_mandate_cap))

  combined <- list(
    orchestrated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    as_of_date = if (is.null(as_of_date)) NA else as.character(as_of_date),
    apply_mandate_cap = apply_mandate_cap,
    strategies = results,
    measurement_basis_primary = "forge_realized_share_based",
    plan_version = "v1.0_2026-04-29"
  )
  write_json(combined, manifest_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("\n[orchestrator] manifest: %s\n", manifest_path))

  # ─── Telegram brief (optional) ───────────────────────
  if (send_telegram) {
    tg_path <- file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R")
    if (file.exists(tg_path)) {
      tryCatch({
        source(tg_path)
        msg_lines <- c(
          "[Q-Lead] Forward Weights Orchestrator",
          sprintf("as_of_date: %s | mandate: %s",
                  if (is.null(as_of_date)) "max(schedule)" else as.character(as_of_date),
                  apply_mandate_cap),
          "",
          sprintf("STR_1715: %s",
                  results[["STR_1715"]]$status %||% "ok"),
          sprintf("STR_1631_SYN_06: %s",
                  results[["STR_1631_SYN_06"]]$status %||% "ok"),
          sprintf("STR_1656_MLRA: %s",
                  results[["STR_1656_MLRA"]]$status %||% "STUB"),
          "",
          sprintf("manifest: %s", manifest_path)
        )
        if (exists("tg_send")) tg_send(paste(msg_lines, collapse = "\n"))
      }, error = function(e) cat(sprintf("[orchestrator] telegram send failed: %s\n",
                                          conditionMessage(e))))
    }
  }

  invisible(combined)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

if (!interactive() && sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  as_of <- if (length(args) >= 1 && nchar(args[1]) > 0) args[1] else NULL
  cap_mode <- if (length(args) >= 2) args[2] else "cap_0.20"
  send_tg <- if (length(args) >= 3) as.logical(args[3]) else FALSE
  orchestrate_forward_weights(as_of_date = as_of,
                               apply_mandate_cap = cap_mode,
                               send_telegram = send_tg)
}
