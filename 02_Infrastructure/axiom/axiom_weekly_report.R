# axiom_weekly_report.R — 주간 점검 리포트 (v8.0 INV-3 안전망)
#
# 완전 자동 승격의 사후 안전망. 지난주 승격(mode-local+global)/NARROW/deprecation/pending +
# proxy 유래·전 global 공리 "도훈 검토 요망" 플래그 + hook-enforcement confirm 대기 + 롤백 후보.
# 파일 저장 + (옵션) tg_agent_brief 발송. cron 주간.
#
# Usage: Rscript axiom_weekly_report.R [--telegram]
suppressPackageStartupMessages({ library(jsonlite) })

.wr_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
             Sys.getenv("QVEST_PROJECT_DIR", ""), Sys.getenv("PROJECT_ROOT", ""), getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

axiom_weekly_report <- function(send_telegram = FALSE) {
  root <- .wr_root()
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  files <- list.files(active_dir, pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE)
  cutoff <- Sys.Date() - 7

  flagged <- character(0); recent <- character(0); rollback_cand <- character(0); enforce_wait <- character(0)
  for (f in files) {
    ax <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL); if (is.null(ax)) next
    id <- ax$axiom_id %||% ax$memory_id %||% basename(f)
    tier <- ax$tier %||% (if (grepl("^AX-[A-Z]+-", id)) "mode_local" else "global")
    metric <- ax$metric_type %||% "?"
    pat <- ax$promotion$promoted_at %||% ""
    # 검토 요망: proxy/estimated 유래 또는 global tier (INV-3)
    if (metric %in% c("proxy", "estimated") || tier == "global")
      flagged <- c(flagged, sprintf("%s [%s/%s]", id, tier, metric))
    # 최근 승격
    if (nzchar(pat) && !is.na(suppressWarnings(as.Date(pat))) && as.Date(pat) >= cutoff)
      recent <- c(recent, sprintf("%s [%s] %s", id, tier, substr(ax$statement %||% "", 1, 50)))
    # hook-enforcement confirm 대기: enforcement_mode=documented이나 검토로 block 후보 (provisional 제외)
    if (identical(ax$enforcement_mode %||% "documented", "documented") && tier == "global" &&
        !identical(ax$epistemic_status %||% "", "provisional"))
      enforce_wait <- c(enforce_wait, id)
    # 롤백 후보: needs_refinement 또는 expiry 임박
    if (isTRUE(ax$needs_refinement)) rollback_cand <- c(rollback_cand, sprintf("%s (needs_refinement)", id))
    if (!is.null(ax$expiry) && !is.na(suppressWarnings(as.Date(ax$expiry))) && as.Date(ax$expiry) <= Sys.Date() + 14)
      rollback_cand <- c(rollback_cand, sprintf("%s (expiry %s 임박)", id, ax$expiry))
  }
  cand_dir <- file.path(root, "qepm", "memory", "axioms", "candidates")
  pending <- list.files(cand_dir, pattern = "^CAND_.*\\.json$")

  report <- list(
    schema_version = "v8.0_weekly_report",
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    n_active = length(files), n_pending = length(pending),
    human_review_flagged = as.list(flagged),     # proxy/global 전건 도훈 검토
    recent_promotions = as.list(recent),
    hook_enforcement_confirm_wait = as.list(enforce_wait),  # block 부여는 도훈 confirm
    rollback_candidates = as.list(rollback_cand)
  )
  out_dir <- file.path(root, "qepm", "memory", "axioms", "review_log")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out <- file.path(out_dir, sprintf("weekly_report_%s.json", format(Sys.Date(), "%Y%m%d")))
  write_json(report, out, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[weekly_report] active=%d pending=%d flagged=%d recent=%d enforce_wait=%d rollback_cand=%d → %s\n",
    length(files), length(pending), length(flagged), length(recent), length(enforce_wait), length(rollback_cand),
    basename(out)))

  if (isTRUE(send_telegram)) {
    tg <- file.path(root, "02_Infrastructure", "telegram", "tg_agent_brief.R")
    if (file.exists(tg)) {
      tryCatch({
        source(tg, local = TRUE)
        if (exists("tg_agent_brief", mode = "function")) {
          secs <- list(
            list(type = "kv", emoji = "\U0001F4CA", heading = "Axiom 주간",
                 kv = list(active = length(files), pending = length(pending),
                           `검토요망` = length(flagged), `롤백후보` = length(rollback_cand))),
            list(type = "bullet", emoji = "\U0001F6A9", heading = "검토 요망(proxy/global)",
                 items = head(flagged, 8)))
          tg_agent_brief(agent = "AxiomEngine", title = "Axiom 주간 점검 리포트", sections = secs)
        }
      }, error = function(e) cat("[weekly_report][TG] 발송 실패:", conditionMessage(e), "\n"))
    }
  }
  invisible(report)
}

if (!interactive() && length(commandArgs(trailingOnly = TRUE)) >= 0) {
  invisible(axiom_weekly_report(send_telegram = "--telegram" %in% commandArgs(trailingOnly = TRUE)))
}
cat("[axiom_weekly_report] Loaded. axiom_weekly_report(send_telegram=FALSE)\n")
