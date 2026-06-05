# promote_global.R — mode-local → global 승격 (v8.0 INV-1/5)
#
# mode-local 공리(들)가 다음을 모두 충족하면 global AX-NNN으로 승격:
#   (1) INV-1: supporting L-code 전부 metric_type=backtested (아니면 blocked: needs backtest)
#   (2) cross-mode 독립성: 출처 모드 ≥ 2 (다른 모드에서도 재확인 — 같은 편향 공유 아님)
#   (3) essence_score §3 HARD: weakest portfolio_alpha_t ≥ 2.95 (measurement-graduation §3)
#   (4) INV-5/AX-008: Forge(essence) + Codex + Architect 중 2-source PASS
# silent-proceed 금지 — 미충족(특히 proxy)은 blocked 반환.
#
# Usage: Rscript promote_global.R <modes/<m>/AX-XX-001.json> [<더 묶을 mode-local> ...]
suppressPackageStartupMessages({ library(jsonlite) })

# promote.R helper(.px_root/.lc_get/.next_axiom_id/.update_sot_map/.MODE_PREFIX) 재사용 — CLI 이중실행 가드
Sys.setenv(PROMOTE_SOURCED = "1")
local({
  pr <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
                  "02_Infrastructure", "axiom", "promote.R")
  if (file.exists(pr)) sys.source(pr, envir = globalenv())
})
Sys.unsetenv("PROMOTE_SOURCED")

promote_to_global <- function(mode_local_paths,
                              verification = list(forge = FALSE, codex = FALSE, architect = FALSE)) {
  root <- .px_root()
  corpus <- fromJSON(file.path(root, ".cache", "lcode_corpus.json"), simplifyVector = FALSE)
  axioms <- lapply(mode_local_paths, function(p) fromJSON(p, simplifyVector = FALSE))
  supporting <- unique(unlist(lapply(axioms, function(a) a$supporting_l_codes %||% character(0))))
  axiom_modes <- unique(vapply(axioms, function(a) a$research_mode %||% "?", character(1)))

  # (1) INV-1: 모든 supporting backtested
  metrics <- vapply(supporting, function(lc) .lc_get(corpus, lc, "metric_type", "estimated"), character(1))
  n_bt <- sum(metrics == "backtested")
  if (n_bt < length(supporting)) {
    cat(sprintf("[promote_global] BLOCKED: needs backtest (%d/%d backtested) — proxy/estimated는 global 불가(INV-1)\n",
                n_bt, length(supporting)))
    return(list(passed = FALSE, blocked = "needs_backtest", n_backtested = n_bt, n_total = length(supporting)))
  }

  # (2) cross-mode 독립성
  lc_modes <- unique(vapply(supporting, function(lc) .lc_get(corpus, lc, "research_mode", "?"), character(1)))
  cross_mode_ok <- (length(axiom_modes) >= 2) || (length(lc_modes) >= 2)

  # (3) essence §3: weakest portfolio_alpha_t ≥ 2.95
  port_ts <- suppressWarnings(as.numeric(vapply(supporting, function(lc) {
    v <- .lc_get(corpus, lc, "portfolio_alpha_t", NA); if (is.null(v)) NA_real_ else as.numeric(v) }, numeric(1))))
  port_ts <- port_ts[!is.na(port_ts)]
  weakest_t <- if (length(port_ts)) min(port_ts) else NA_real_
  essence_ok <- !is.na(weakest_t) && weakest_t >= 2.95

  # (4) INV-5/AX-008: 2/3 verification
  n_verif <- sum(vapply(verification, isTRUE, logical(1)))
  ax008_ok <- n_verif >= 2

  passed <- cross_mode_ok && essence_ok && ax008_ok
  cat(sprintf("[promote_global] cross_mode(%s)=%s essence(weakest_t=%s≥2.95)=%s AX008(%d/3)=%s → %s\n",
    paste(axiom_modes, collapse = "+"), cross_mode_ok,
    if (is.na(weakest_t)) "NA" else round(weakest_t, 2), essence_ok, n_verif, ax008_ok,
    if (passed) "PASS" else "FAIL"))

  if (passed) {
    ap <- .promote_global_active(axioms, supporting, axiom_modes, weakest_t, verification)
    return(list(passed = TRUE, global_path = ap))
  }
  list(passed = FALSE, cross_mode_ok = cross_mode_ok, essence_ok = essence_ok, ax008_ok = ax008_ok)
}

.promote_global_active <- function(axioms, supporting, modes, weakest_t, verification) {
  root <- .px_root()
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  ax_id <- .next_axiom_id(active_dir)  # global AX-NNN (mode=NULL)
  base <- axioms[[1]]
  stmt <- base$statement %||% base$canonical_statement %||% ""
  axiom <- list(axiom_id = ax_id, memory_id = ax_id, id = ax_id, tier = "global",
    metric_type = "backtested", epistemic_status = base$epistemic_status %||% "law",
    type = base$type, polarity = base$polarity,
    statement = stmt, canonical_statement = stmt, text = stmt,
    supporting_l_codes = supporting, scope = base$scope %||% list(),
    promotion = list(promoted_from = vapply(axioms, function(a) a$axiom_id %||% "?", character(1)),
      cross_mode = modes, weakest_portfolio_alpha_t = weakest_t,
      ax008_verification = verification, promoted_at = format(Sys.Date()), next_review = format(Sys.Date() + 90)),
    enforcement = "", enforcement_mode = "documented", status = "active", version = 1L)  # INV-2
  nrm <- file.path(root, "02_Infrastructure/memory/memory_metadata_normalize.R")
  if (file.exists(nrm)) { source(nrm, local = TRUE); if (exists("normalize_axiom_metadata", mode = "function"))
    axiom <- normalize_axiom_metadata(axiom = axiom, axiom_class = base$type %||% "methodological",
      memory_kind = "axiom_active", authority = "high", review_policy = "quarterly",
      enforcement_mode = "documented", write = FALSE) }
  out_path <- file.path(active_dir, paste0(ax_id, ".json"))
  write_json(axiom, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[promote_global] GLOBAL 승격 → %s (cross-mode: %s)\n", out_path, paste(modes, collapse = "+")))
  if (exists(".update_sot_map", mode = "function")) .update_sot_map(ax_id, "global", axiom)
  out_path
}

if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  invisible(promote_to_global(as.list(commandArgs(trailingOnly = TRUE))))
}
cat("[promote_global] Loaded (v8.0 INV-1/5). promote_to_global(mode_local_paths, verification)\n")
