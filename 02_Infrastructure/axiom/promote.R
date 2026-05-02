# Sprint 4 AX-P1: 5-Axis Promoter
# L-code 기반 axiom candidate → active axiom 승격 로직.
# Reference: 00_Lawbook/Axiom_아키텍처/r7_axiom_design.md §승격조건
#
# Usage:
#   source("02_Infrastructure/axiom/promote.R")
#   r <- promote_to_axiom("qepm/memory/axioms/candidates/CAND_XXX.json")
#
# 5축:
#   Independence, Rigor, Falsification, External (OOS), Mechanism
#
# 가중치 (type별):
#   empirical     : I=0.25 R=0.25 F=0.20 E=0.20 M=0.10
#   methodological: I=0.15 R=0.20 F=0.30 E=0.15 M=0.20
# 통과 기준: weighted >= 0.80

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

.px_root <- function() {
  cands <- c(
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    Sys.getenv("QVEST_PROJECT_DIR", ""),
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 ||
                             (length(a) == 1 && is.na(a))) b else a

# ─── 축 1: Independence ─────────────────────────────────────────────
.axis_independence <- function(candidate, corpus) {
  supporting <- candidate$supporting_l_codes %||% character(0)
  if (length(supporting) == 0L) return(list(score = 0, reason = "no supporting L-codes"))

  strategies <- character(0)
  families <- character(0)
  polarities <- character(0)
  for (lc in supporting) {
    idx <- which(vapply(corpus$lcodes, function(x) x$l_code == lc, logical(1)))
    if (length(idx) == 0L) next
    lcd <- corpus$lcodes[[idx[1]]]
    if (!is.null(lcd$strategy_id)) strategies <- c(strategies, lcd$strategy_id)
    if (!is.null(lcd$family)) families <- c(families, lcd$family)
    if (!is.null(lcd$grade)) polarities <- c(polarities, lcd$grade)
  }

  n_strat <- length(unique(strategies))
  n_fam <- length(unique(families))
  consistency <- if (length(polarities) > 0L) {
    # Most common grade ratio (direction consistency)
    max(table(polarities)) / length(polarities)
  } else 0

  score <- 0
  score <- score + min(0.5, n_strat * 0.25)           # 2+ strategies = 0.5
  score <- score + if (n_fam >= 2) 0.3 else n_fam * 0.15
  score <- score + if (consistency >= 0.8) 0.2 else consistency * 0.2

  list(
    score = min(1.0, score),
    n_independent_strategies = n_strat,
    n_families = n_fam,
    direction_consistency = round(consistency, 3),
    reason = sprintf("%d strategies, %d families, consistency=%.2f",
                     n_strat, n_fam, consistency)
  )
}

# ─── 축 2: Rigor ────────────────────────────────────────────────────
.axis_rigor <- function(candidate, corpus) {
  supporting <- candidate$supporting_l_codes %||% character(0)
  polarity <- candidate$polarity %||% "unknown"
  type <- candidate$type %||% "empirical"

  # Grade A catalog 교차검증 (실증 positive/conditional only)
  root <- .px_root()
  ga_path <- file.path(root, "04_Research", "grade_a_catalog.json")
  ga <- if (file.exists(ga_path)) {
    tryCatch(fromJSON(ga_path, simplifyVector = FALSE), error = function(e) list())
  } else list()

  # For negative polarity (실패 규칙): all supporting L-codes should have grade F/C → high rigor
  if (polarity == "negative") {
    grades <- vapply(supporting, function(lc) {
      idx <- which(vapply(corpus$lcodes, function(x) x$l_code == lc, logical(1)))
      if (length(idx)) corpus$lcodes[[idx[1]]]$grade %||% "?" else "?"
    }, character(1))
    frac_fail <- sum(grades %in% c("F", "C")) / max(1L, length(grades))
    score <- frac_fail  # 전부 실패면 1.0
    return(list(score = score,
                 frac_fail = round(frac_fail, 3),
                 grades = grades,
                 reason = sprintf("negative polarity: %d/%d failed",
                                   sum(grades %in% c("F","C")), length(grades))))
  }

  # positive/conditional: grade_a_catalog에서 supporting strategy 매칭
  strategies <- unique(vapply(supporting, function(lc) {
    idx <- which(vapply(corpus$lcodes, function(x) x$l_code == lc, logical(1)))
    if (length(idx)) corpus$lcodes[[idx[1]]]$strategy_id %||% "?" else "?"
  }, character(1)))

  ga_strategies <- vapply(ga$strategies %||% list(), function(s) s$strategy_id %||% "", character(1))
  matches <- sum(vapply(strategies, function(s) any(grepl(s, ga_strategies, fixed = TRUE)),
                         logical(1)))

  sharps <- numeric(0)
  for (s_info in (ga$strategies %||% list())) {
    sid <- s_info$strategy_id %||% ""
    if (any(vapply(strategies, function(x) grepl(x, sid, fixed = TRUE), logical(1)))) {
      sr <- tryCatch(as.numeric(s_info$sharpe), error = function(e) NA)
      if (!is.na(sr)) sharps <- c(sharps, sr)
    }
  }

  weakest <- if (length(sharps)) min(sharps) else NA_real_
  meta <- if (length(sharps)) mean(sharps) else NA_real_

  score <- 0
  if (matches >= 2) score <- score + 0.4 else score <- score + matches * 0.2
  if (!is.na(weakest) && weakest >= 0.8) score <- score + 0.3
  if (!is.na(meta) && meta >= 1.0) score <- score + 0.3

  list(
    score = min(1.0, score),
    n_grade_a_matches = matches,
    weakest_sharpe = round(weakest, 3),
    meta_sharpe = round(meta, 3),
    reason = sprintf("grade_a matches=%d, weakest SR=%s, meta SR=%s",
                     matches,
                     if (is.na(weakest)) "NA" else sprintf("%.2f", weakest),
                     if (is.na(meta)) "NA" else sprintf("%.2f", meta))
  )
}

# ─── 축 3: Falsification ────────────────────────────────────────────
.axis_falsification <- function(candidate, corpus) {
  root <- .px_root()
  supporting <- candidate$supporting_l_codes %||% character(0)
  polarity <- candidate$polarity %||% "unknown"

  attempts <- candidate$falsification_draft$attempts %||% list()
  n_attempts <- length(attempts)

  # role_honesty 스캔: supporting strategies의 role honesty 결과
  rh_dir <- file.path(root, "stage_artifacts")
  rh_files <- list.files(rh_dir, pattern = "^role_honesty_.*\\.json$", full.names = TRUE)
  strategies <- vapply(supporting, function(lc) {
    idx <- which(vapply(corpus$lcodes, function(x) x$l_code == lc, logical(1)))
    if (length(idx)) corpus$lcodes[[idx[1]]]$strategy_id %||% "" else ""
  }, character(1))

  rh_attempts <- 0L
  rh_survived <- 0L
  for (f in rh_files) {
    rh <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(rh)) next
    sid <- rh$strategy_id %||% ""
    if (any(vapply(strategies, function(s) nzchar(s) && grepl(s, sid, fixed = TRUE),
                    logical(1)))) {
      rh_attempts <- rh_attempts + 1L
      if (isTRUE(rh$honest)) rh_survived <- rh_survived + 1L
    }
  }

  total_attempts <- n_attempts + rh_attempts

  # evidence_summary/ 교차검증 시도 (optional)
  ev_dir <- file.path(root, "qepm", "memory", "evidence_summary")
  ev_attempts <- 0L
  if (dir.exists(ev_dir)) {
    ev_files <- list.files(ev_dir, pattern = "\\.json$", full.names = TRUE)
    for (f in ev_files) {
      ev <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(ev)) next
      sid <- ev$strategy_id %||% ""
      if (any(vapply(strategies, function(s) nzchar(s) && grepl(s, sid, fixed = TRUE),
                      logical(1)))) {
        ev_attempts <- ev_attempts + 1L
      }
    }
  }

  total_attempts <- total_attempts + ev_attempts
  score <- 0
  if (total_attempts >= 1) score <- score + 0.3
  if (total_attempts >= 3) score <- score + 0.2
  # For negative polarity, "survived" means failure was reproduced — all members failed → success
  if (polarity == "negative") {
    score <- score + 0.5  # 자체 재현성 = L-codes 여러 건
  } else {
    if (rh_attempts > 0 && rh_survived / max(1, rh_attempts) >= 0.5) score <- score + 0.5
  }

  list(
    score = min(1.0, score),
    total_attempts = total_attempts,
    rh_attempts = rh_attempts,
    rh_survived = rh_survived,
    ev_attempts = ev_attempts,
    reason = sprintf("attempts=%d (rh=%d survived=%d, evidence=%d)",
                     total_attempts, rh_attempts, rh_survived, ev_attempts)
  )
}

# ─── 축 4: External (OOS) ───────────────────────────────────────────
.axis_external <- function(candidate, corpus) {
  oos_draft <- candidate$oos_validation_draft %||% list()
  oos_months <- as.numeric(oos_draft$oos_months %||% NA_real_)
  oos_vs_is <- as.numeric(oos_draft$oos_effect_vs_is %||% NA_real_)

  # 보조: supporting 전략 hurdle_result에서 rolling metrics 확인
  root <- .px_root()
  supporting <- candidate$supporting_l_codes %||% character(0)
  strategies <- vapply(supporting, function(lc) {
    idx <- which(vapply(corpus$lcodes, function(x) x$l_code == lc, logical(1)))
    if (length(idx)) corpus$lcodes[[idx[1]]]$strategy_id %||% "" else ""
  }, character(1))

  hurdle_matches <- 0L
  rolling_ok <- 0L
  for (s in strategies) {
    if (!nzchar(s)) next
    dirs <- list.dirs(file.path(root, "04_Research", "strategies"),
                      recursive = FALSE, full.names = TRUE)
    for (d in dirs) {
      if (grepl(s, basename(d), fixed = TRUE)) {
        hf <- list.files(d, pattern = "^hurdle_result\\.json$",
                          recursive = TRUE, full.names = TRUE)
        if (length(hf) == 0L) next
        hurdle_matches <- hurdle_matches + 1L
        hd <- tryCatch(fromJSON(hf[1], simplifyVector = FALSE), error = function(e) NULL)
        if (!is.null(hd)) {
          rs <- hd$metrics$rolling_sharpe_positive_ratio %||%
                hd$rolling_sharpe_positive_ratio %||% NA_real_
          if (!is.null(rs) && !is.na(rs) && as.numeric(rs) >= 0.5) {
            rolling_ok <- rolling_ok + 1L
          }
        }
      }
    }
  }

  score <- 0
  if (!is.na(oos_months) && oos_months >= 3) score <- score + 0.4
  if (!is.na(oos_vs_is) && oos_vs_is >= 0.5) score <- score + 0.4
  if (hurdle_matches >= 1) score <- score + 0.1
  if (rolling_ok >= 1) score <- score + 0.1

  list(
    score = min(1.0, score),
    oos_months = oos_months,
    oos_effect_vs_is = oos_vs_is,
    hurdle_matches = hurdle_matches,
    rolling_ok = rolling_ok,
    reason = sprintf("OOS=%s/%s, hurdle=%d, rolling_ok=%d",
                     if (is.na(oos_months)) "NA" else as.character(oos_months),
                     if (is.na(oos_vs_is)) "NA" else sprintf("%.2f", oos_vs_is),
                     hurdle_matches, rolling_ok)
  )
}

# ─── 축 5: Mechanism ────────────────────────────────────────────────
.axis_mechanism <- function(candidate) {
  m <- candidate$mechanism_draft %||% list()
  expl <- m$economic_explanation %||% NA_character_
  mtype <- m$mechanism_type %||% "unknown"
  caus <- m$causal_plausibility %||% NA_character_

  score <- 0
  if (!is.na(expl) && nzchar(expl) && expl != "null") score <- score + 0.4
  if (!is.na(mtype) && mtype != "unknown") score <- score + 0.3
  if (caus %in% c("moderate", "moderate_to_high", "high")) score <- score + 0.3

  list(
    score = score,
    economic_explanation_present = !is.na(expl) && nzchar(expl),
    mechanism_type = mtype,
    causal_plausibility = caus,
    reason = sprintf("expl=%s, type=%s, plausibility=%s",
                     if (is.na(expl) || !nzchar(expl)) "MISSING" else "present",
                     mtype, caus %||% "NA")
  )
}

# ─── 가중 합산 ─────────────────────────────────────────────────────
.weights <- function(type) {
  if (type == "methodological") {
    c(I = 0.15, R = 0.20, F = 0.30, E = 0.15, M = 0.20)
  } else {
    c(I = 0.25, R = 0.25, F = 0.20, E = 0.20, M = 0.10)
  }
}

# ─── 메인 함수 ─────────────────────────────────────────────────────
promote_to_axiom <- function(candidate_path, threshold = 0.80, auto_inject = NULL) {
  if (!file.exists(candidate_path)) stop("candidate not found: ", candidate_path)

  candidate <- fromJSON(candidate_path, simplifyVector = FALSE)
  root <- .px_root()
  corpus_path <- file.path(root, ".cache", "lcode_corpus.json")
  if (!file.exists(corpus_path)) stop("lcode_corpus.json 없음. harvester 먼저 실행.")
  corpus <- fromJSON(corpus_path, simplifyVector = FALSE)

  I <- .axis_independence(candidate, corpus)
  R <- .axis_rigor(candidate, corpus)
  F_ax <- .axis_falsification(candidate, corpus)
  E <- .axis_external(candidate, corpus)
  M <- .axis_mechanism(candidate)

  type <- candidate$type %||% "empirical"
  w <- .weights(type)
  weighted <- w["I"] * I$score + w["R"] * R$score + w["F"] * F_ax$score +
              w["E"] * E$score + w["M"] * M$score
  weighted <- round(as.numeric(weighted), 3)

  report <- list(
    candidate_id = candidate$candidate_id,
    type = type,
    polarity = candidate$polarity,
    axes = list(
      independence = I, rigor = R, falsification = F_ax,
      external = E, mechanism = M
    ),
    weights = as.list(w),
    weighted_score = weighted,
    threshold = threshold,
    passed = weighted >= threshold,
    checked_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )

  cat(sprintf("[promote] %s (%s/%s) → weighted=%.3f (threshold=%.2f) %s\n",
              candidate$candidate_id, type, candidate$polarity, weighted, threshold,
              if (report$passed) "PASS" else "FAIL"))
  for (ax_name in c("independence", "rigor", "falsification", "external", "mechanism")) {
    ax <- report$axes[[ax_name]]
    cat(sprintf("  %-14s %.2f  %s\n", ax_name, ax$score, ax$reason))
  }

  if (report$passed) {
    axiom_path <- .promote_to_active(candidate, report)
    .update_lcode_back_links(candidate, basename(axiom_path))
    do_inject <- if (is.null(auto_inject)) {
      as.integer(Sys.getenv("QVEST_AXIOM_AUTO_INJECT", "0")) == 1
    } else isTRUE(auto_inject)
    if (do_inject) {
      inject_src <- file.path(root, "02_Infrastructure", "axiom", "inject.R")
      if (file.exists(inject_src)) {
        source(inject_src, local = TRUE)
        if (exists("inject_axiom", mode = "function")) {
          try(inject_axiom(axiom_path))
        }
      }
    } else {
      cat("[promote] dry-run (QVEST_AXIOM_AUTO_INJECT != 1) — inject 생략\n")
    }
    report$active_path <- axiom_path
  } else {
    log_path <- .log_partial(candidate, report)
    report$review_log_path <- log_path
  }

  report
}

.next_axiom_id <- function(active_dir) {
  files <- list.files(active_dir, pattern = "^AX-\\d+\\.json$", full.names = FALSE)
  nums <- as.integer(sub("AX-(\\d+)\\.json", "\\1", files))
  nums <- nums[!is.na(nums)]
  if (length(nums) == 0L) return("AX-003")  # 000/001/002 reserved
  sprintf("AX-%03d", max(nums) + 1L)
}

.promote_to_active <- function(candidate, report) {
  root <- .px_root()
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  dir.create(active_dir, recursive = TRUE, showWarnings = FALSE)

  ax_id <- .next_axiom_id(active_dir)
  axiom <- list(
    axiom_id = ax_id,
    type = candidate$type,
    polarity = candidate$polarity,
    statement = candidate$statement_draft %||% "",
    supporting_l_codes = candidate$supporting_l_codes,
    scope = candidate$scope_draft %||% list(),
    evidence = candidate$evidence_draft %||% list(),
    falsification = candidate$falsification_draft %||% list(),
    mechanism = candidate$mechanism_draft %||% list(),
    oos_validation = candidate$oos_validation_draft %||% list(),
    promotion = list(
      source_candidate = candidate$candidate_id,
      weighted_score = report$weighted_score,
      threshold = report$threshold,
      axis_scores = list(
        independence = report$axes$independence$score,
        rigor = report$axes$rigor$score,
        falsification = report$axes$falsification$score,
        external = report$axes$external$score,
        mechanism = report$axes$mechanism$score
      ),
      promoted_at = format(Sys.time(), "%Y-%m-%d"),
      next_review = format(Sys.Date() + 90, "%Y-%m-%d")
    ),
    enforcement = "",
    status = "active",
    version = 1L
  )

  out_path <- file.path(active_dir, paste0(ax_id, ".json"))

  # ─── v7.2.1 metadata normalize (객체 dry-run, scoring logic 변경 X) ───
  source(file.path(.px_root(),
                   "02_Infrastructure/memory/memory_metadata_normalize.R"))
  axiom <- normalize_axiom_metadata(
    axiom = axiom,
    axiom_class = candidate$type %||% "methodological",
    memory_kind = "axiom_active",
    authority = "high",
    review_policy = "quarterly",
    enforcement_mode = "documented",
    write = FALSE
  )

  write_json(axiom, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[promote] 승격 → %s\n", out_path))
  out_path
}

.update_lcode_back_links <- function(candidate, ax_filename) {
  root <- .px_root()
  ax_id <- sub("\\.json$", "", ax_filename)
  for (lc in (candidate$supporting_l_codes %||% character(0))) {
    # Find l_code_*.json containing this l_code
    files <- list.files(file.path(root, "stage_artifacts"),
                        pattern = "^l_code_.*\\.json$", full.names = TRUE)
    for (f in files) {
      d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(d)) next
      if (identical(d$l_code, lc)) {
        d$promoted_to_axiom <- ax_id
        d$promoted_at <- format(Sys.time(), "%Y-%m-%d")
        write_json(d, f, pretty = TRUE, auto_unbox = TRUE, null = "null")
        cat(sprintf("[promote] 역링크 기입: %s ← %s\n", basename(f), ax_id))
        break
      }
    }
  }
}

.log_partial <- function(candidate, report) {
  root <- .px_root()
  log_dir <- file.path(root, "qepm", "memory", "axioms", "review_log")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_path <- file.path(log_dir,
    sprintf("AX-PENDING_%s_%s.json", candidate$candidate_id, ts))

  failing <- character(0)
  for (ax_name in names(report$axes)) {
    if (report$axes[[ax_name]]$score < 0.5) failing <- c(failing, ax_name)
  }

  log_obj <- list(
    candidate_id = candidate$candidate_id,
    weighted_score = report$weighted_score,
    threshold = report$threshold,
    failing_axes = failing,
    axes = report$axes,
    logged_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    note = "부분 통과 — 누락 축 보강 후 재시도. 실증 후보는 mechanism/OOS 채움, 방법론 후보는 falsification/mechanism 강화 필요."
  )
  write_json(log_obj, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[promote] 부분 통과 → %s\n", out_path))
  out_path
}

# ── CLI entry point ──
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  .args <- commandArgs(trailingOnly = TRUE)
  .path <- .args[1]
  .r <- promote_to_axiom(.path)
  invisible(.r)
}

cat("[promote] Loaded. Function: promote_to_axiom(candidate_path, threshold=0.80)\n")
