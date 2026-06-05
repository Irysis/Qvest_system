#!/usr/bin/env Rscript
# ──────────────────────────────────────────────────────────────────────────────
# harness_perf_eval.R — v8.0 WS8-1 추론성능 측정 루프
# ──────────────────────────────────────────────────────────────────────────────
# 목적: 아키텍처(WS3~7) 변경의 before/after를 "리서치 추론성능"으로 정량 입증.
#       "perf 향상"이 unmeasured면 도훈 thesis 자체가 검증불가 → v8.0 게이트.
#
# 2-tier:
#   Tier A (artifact 기반, 안정): WT mailbox 패키지에서 연구품질(IC/ICIR/DSR/AX001/
#           turnover) + Codex 결과(stance/veto/rationalization) 추출.
#   Tier B (logger): agent_perf_runs.jsonl 에 per-agent token/latency/codex_stance
#           기록(완료 통계는 자동 영속 안 됨 → Q-Lead/agent가 log_agent_run()로 적립).
#
# 사용:
#   source("02_Infrastructure/eval/harness_perf_eval.R")
#   perf_baseline("WT-D20260528_003", "before_v8")          # baseline 스냅샷
#   log_agent_run("WT-D20260528_003","alpha",159597,1163748,"REJECT")  # Tier B 적립
#   perf_compare("...before_v8.json","...after_v8.json")     # diff
# 또는 CLI: Rscript harness_perf_eval.R baseline WT-D20260528_003 before_v8
# ──────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(jsonlite)
})

.PE_ROOT <- tryCatch(
  dirname(dirname(dirname(normalizePath(sub("--file=", "",
    grep("--file=", commandArgs(FALSE), value = TRUE)[1])))) ),
  error = function(e) getwd())
if (is.na(.PE_ROOT) || !dir.exists(file.path(.PE_ROOT, "qepm")))
  .PE_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))

.PE_MAILBOX  <- file.path(.PE_ROOT, "qepm/mailbox/worktask")
.PE_OUTDIR   <- file.path(.PE_ROOT, "qepm/observability/perf_eval")
.PE_RUNLOG   <- file.path(.PE_ROOT, "qepm/observability/agent_perf_runs.jsonl")
dir.create(.PE_OUTDIR, showWarnings = FALSE, recursive = TRUE)

# 연구품질 metric 키 패턴 (소문자 부분일치)
.PE_METRIC_PAT <- c("ic_raw_mean", "ic_smth_mean", "rank_ic_mean", "icir",
                    "icir_raw", "harvey", "t_hac", "dsr_proper", "dsr_z",
                    "dsr_pass", "ax001_v2_ratio", "ax001_v2_pass",
                    "turnover_yr", "turnover_pass", "sr_net", "net_sr",
                    "sharpe", "hit_rate")

# ── Tier A: WT 패키지에서 연구품질 + Codex 결과 추출 ──────────────────────────
.pe_flatten <- function(x, prefix = "") {
  out <- list()
  if (is.list(x)) {
    for (nm in names(x)) {
      v <- x[[nm]]
      key <- if (nchar(prefix)) paste0(prefix, ".", nm) else nm
      if (is.list(v)) out <- c(out, .pe_flatten(v, key))
      else if (length(v) == 1 && (is.numeric(v) || is.logical(v))) out[[key]] <- v
    }
  }
  out
}

.pe_extract_metrics <- function(pkg_path) {
  d <- tryCatch(fromJSON(pkg_path, simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(d)) return(list())
  flat <- .pe_flatten(d)
  keep <- flat[vapply(names(flat), function(k)
    any(grepl(paste(.PE_METRIC_PAT, collapse = "|"), tolower(k))), logical(1))]
  keep
}

.pe_codex_outcome <- function(codex_path) {
  d <- tryCatch(fromJSON(codex_path, simplifyVector = TRUE),
                error = function(e) NULL)
  if (is.null(d)) return(NULL)
  nflags <- tryCatch(length(d$rationalization_red_flags), error = function(e) NA)
  list(stance = d$stance %||% NA, veto_flag = d$veto_flag %||% NA,
       n_rationalization_flags = nflags)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

extract_wt_quality <- function(wt_id) {
  wt_dir <- file.path(.PE_MAILBOX, wt_id)
  if (!dir.exists(wt_dir)) stop(sprintf("WT dir 없음: %s", wt_dir))
  roles <- c("alpha", "risk", "optimization", "forge", "judge", "governor")
  res <- list()
  for (role in roles) {
    # final 패키지 우선순위: {role}_package_PROD.json > {role}_package.json
    pkgs <- list.files(wt_dir, pattern = sprintf("^%s_package.*\\.json$", role),
                       full.names = TRUE)
    pkgs <- pkgs[!grepl("_draft", pkgs)]
    if (!length(pkgs)) next
    pkg <- if (any(grepl("_PROD", pkgs))) grep("_PROD", pkgs, value = TRUE)[1] else pkgs[1]
    crole <- if (role == "optimization") "optimizer" else role  # role↔codex 파일명 alias (audit_pipeline #2)
    codex <- list.files(wt_dir,
      pattern = sprintf("codex_critic_response_%s.*\\.json$", crole), full.names = TRUE)
    codex <- if (length(codex)) {
      if (any(grepl("_PROD", codex))) grep("_PROD", codex, value = TRUE)[1] else codex[1]
    } else NA
    res[[role]] <- list(
      package = basename(pkg),
      metrics = .pe_extract_metrics(pkg),
      codex   = if (!is.na(codex)) .pe_codex_outcome(codex) else NULL)
  }
  res
}

# ── Tier B: per-agent perf logger (token/latency/codex stance) ────────────────
log_agent_run <- function(wt_id, role, tokens = NA, duration_ms = NA,
                          codex_stance = NA, tool_uses = NA, ts = NA) {
  rec <- list(wt_id = wt_id, role = role, tokens = tokens,
              duration_ms = duration_ms, codex_stance = codex_stance,
              tool_uses = tool_uses, ts = if (is.na(ts)) as.character(Sys.time()) else ts)
  cat(toJSON(rec, auto_unbox = TRUE), "\n", file = .PE_RUNLOG, append = TRUE)
  invisible(rec)
}

.pe_read_runlog <- function(wt_id = NULL) {
  if (!file.exists(.PE_RUNLOG)) return(list())
  lines <- readLines(.PE_RUNLOG, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  recs <- lapply(lines, function(l) tryCatch(fromJSON(l), error = function(e) NULL))
  recs <- Filter(Negate(is.null), recs)
  if (!is.null(wt_id)) recs <- Filter(function(r) isTRUE(r$wt_id == wt_id), recs)
  recs
}

# ── baseline 스냅샷 (Tier A + Tier B 결합) ────────────────────────────────────
perf_baseline <- function(wt_id, label) {
  quality <- extract_wt_quality(wt_id)
  runs    <- .pe_read_runlog(wt_id)
  codex_stances <- unlist(lapply(quality, function(r) r$codex$stance))
  n_codex <- sum(!is.na(codex_stances))
  snap <- list(
    wt_id = wt_id, label = label,
    captured_at = as.character(Sys.time()),
    harness_note = "Tier A = artifact 연구품질+Codex / Tier B = agent_perf_runs.jsonl",
    per_role = quality,
    agent_runs = runs,
    summary = list(
      n_roles_with_package = length(quality),
      n_codex_rounds = n_codex,
      codex_stances = as.list(codex_stances),
      total_tokens = if (length(runs)) sum(unlist(lapply(runs, function(r)
        r$tokens %||% 0)), na.rm = TRUE) else NA,
      total_duration_ms = if (length(runs)) sum(unlist(lapply(runs, function(r)
        r$duration_ms %||% 0)), na.rm = TRUE) else NA))
  out <- file.path(.PE_OUTDIR, sprintf("%s_%s.json", wt_id, label))
  write_json(snap, out, auto_unbox = TRUE, pretty = TRUE, null = "null")
  cat(sprintf("[perf_baseline] %s → %s\n  roles=%d codex_rounds=%d agent_runs=%d total_tokens=%s\n",
              label, out, length(quality), n_codex, length(runs),
              snap$summary$total_tokens))
  invisible(snap)
}

# ── before/after 비교 ─────────────────────────────────────────────────────────
perf_compare <- function(before_path, after_path) {
  b <- fromJSON(before_path, simplifyVector = FALSE)
  a <- fromJSON(after_path,  simplifyVector = FALSE)
  cat(sprintf("\n=== PERF COMPARE: %s vs %s ===\n", b$label, a$label))
  cat(sprintf("tokens:    %s → %s\n", b$summary$total_tokens, a$summary$total_tokens))
  cat(sprintf("duration:  %s → %s ms\n", b$summary$total_duration_ms, a$summary$total_duration_ms))
  cat(sprintf("codex rounds: %s → %s\n", b$summary$n_codex_rounds, a$summary$n_codex_rounds))
  roles <- union(names(b$per_role), names(a$per_role))
  for (role in roles) {
    bm <- b$per_role[[role]]$metrics; am <- a$per_role[[role]]$metrics
    keys <- union(names(bm), names(am))
    for (k in keys) {
      bv <- bm[[k]]; av <- am[[k]]
      if (!identical(bv, av))
        cat(sprintf("  [%s] %s: %s → %s\n", role, k,
                    ifelse(is.null(bv), "—", format(bv)),
                    ifelse(is.null(av), "—", format(av))))
    }
  }
  invisible(list(before = b, after = a))
}

# ── CLI ───────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0) {
  args <- commandArgs(TRUE)
  if (length(args) >= 1 && args[1] == "baseline") {
    perf_baseline(args[2], if (length(args) >= 3) args[3] else "snapshot")
  } else if (length(args) >= 1 && args[1] == "compare") {
    perf_compare(args[2], args[3])
  } else if (length(args) >= 1 && args[1] == "log") {
    log_agent_run(args[2], args[3],
      tokens = as.numeric(args[4]), duration_ms = as.numeric(args[5]),
      codex_stance = if (length(args) >= 6) args[6] else NA)
    cat("[log_agent_run] appended\n")
  } else {
    cat("usage: harness_perf_eval.R baseline <wt_id> <label> | compare <b> <a> | log <wt> <role> <tok> <ms> [stance]\n")
  }
}
