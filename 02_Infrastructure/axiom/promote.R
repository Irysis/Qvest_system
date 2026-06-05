# promote.R — 5-Axis Promoter (v8.0: 원전 r7 복원 + 2-tier + INV-1/4/6/7)
#
# 원전 00_Lawbook/Axiom_아키텍처/r7_axiom_design.md 5축 boolean-AND 복원:
#   Independence(construction 다양성) / Rigor(metric_type 게이트) / Falsification(적극 반증)
#   / External(OOS) / Mechanism. 현 구현의 열화(weighted-sum / strategy_id 착시 /
#   negative auto-bonus)를 교정한다.
#
# INV-4: 5축 각 min-hurdle 동시 충족(boolean AND)이 통과 — weighted는 랭킹용.
# INV-1: 본 함수는 mode-local 승격(AX-<MODE>-NNN). global은 promote_global.R(backtested+essence_score §3).
# INV-7: negative = provisional(epistemic_status) + 비대칭 burden(construction 상향) + expiry.
# INV-6: 초안 statement(`[초안]...확정 필요`)는 needs_refinement 표기.
# INV-2: 자동 승격 = enforcement_mode=documented / enforcement="" (hook block은 주간 confirm).
#
# Usage: Rscript promote.R qepm/memory/axioms/candidates/CAND_XXX.json
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

.px_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
             Sys.getenv("QVEST_PROJECT_DIR", ""), Sys.getenv("PROJECT_ROOT", ""), getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

.MODE_PREFIX <- c(alpha_search = "AS", alpha_research = "AR", qepm_legacy = "QPM",
                  judge_gate = "JG", governor_admission = "GV",
                  factor_rotation = "FR", regime_research = "RR")

.HURDLE <- list(
  indep_min_constructions = 2L, indep_min_constructions_neg = 3L,  # INV-7 negative 상향
  indep_min_direction = 0.8,
  rigor_backtested_port_t = 2.95, rigor_neg_frac_fail = 0.8,
  fals_min_attempts = 1L, fals_min_retained = 0.5,
  ext_min_oos_months = 3, ext_min_oos_vs_is = 0.5
)

.lc_get <- function(corpus, lc, field, default = NULL) {
  idx <- which(vapply(corpus$lcodes, function(x) x$l_code == lc, logical(1)))
  if (length(idx)) corpus$lcodes[[idx[1]]][[field]] %||% default else default
}

# ── 축 1: Independence (r7 — construction 다양성, strategy_id 착시 폐기) ──
.axis_independence <- function(candidate, corpus) {
  sup <- candidate$supporting_l_codes %||% character(0)
  polarity <- candidate$polarity %||% "unknown"
  constructions <- vapply(sup, function(lc) .lc_get(corpus, lc, "construction_type", "unknown"), character(1))
  grades <- vapply(sup, function(lc) .lc_get(corpus, lc, "grade", "?"), character(1))
  n_constr <- length(unique(constructions))
  consistency <- if (length(grades)) max(table(grades)) / length(grades) else 0
  min_c <- if (polarity == "negative") .HURDLE$indep_min_constructions_neg else .HURDLE$indep_min_constructions
  score <- min(1.0, (n_constr / max(min_c, 1)) * 0.6 + (if (consistency >= 0.8) 0.4 else consistency * 0.4))
  list(score = round(score, 3),
       hurdle_pass = (n_constr >= min_c && consistency >= .HURDLE$indep_min_direction),
       n_constructions = n_constr, direction_consistency = round(consistency, 3),
       reason = sprintf("%d distinct constructions (min %d), direction_consistency=%.2f", n_constr, min_c, consistency))
}

# ── 축 2: Rigor (r7 — metric_type 게이트; INV-1) ──
.axis_rigor <- function(candidate, corpus, tier) {
  sup <- candidate$supporting_l_codes %||% character(0)
  polarity <- candidate$polarity %||% "unknown"
  metrics <- vapply(sup, function(lc) .lc_get(corpus, lc, "metric_type", "estimated"), character(1))
  grades  <- vapply(sup, function(lc) .lc_get(corpus, lc, "grade", "?"), character(1))
  n_bt <- sum(metrics == "backtested")
  if (polarity == "negative") {
    bt_idx <- metrics == "backtested"
    frac_bt  <- if (any(bt_idx)) sum(grades[bt_idx] %in% c("F", "C")) / sum(bt_idx) else 0
    frac_all <- if (length(grades)) sum(grades %in% c("F", "C")) / length(grades) else 0
    if (tier == "global") { sc <- frac_bt; hp <- (n_bt >= 1 && frac_bt >= .HURDLE$rigor_neg_frac_fail) }
    else { sc <- frac_all; hp <- frac_all >= .HURDLE$rigor_neg_frac_fail }
    return(list(score = round(sc, 3), hurdle_pass = hp, n_backtested = n_bt,
                reason = sprintf("negative frac_fail[%s]=%.2f (n_backtested=%d)", tier, sc, n_bt)))
  }
  pts <- suppressWarnings(as.numeric(vapply(sup, function(lc) {
    v <- .lc_get(corpus, lc, "portfolio_alpha_t", NA); if (is.null(v)) NA_real_ else as.numeric(v) }, numeric(1))))
  pts <- pts[!is.na(pts)]
  if (tier == "global") {
    weakest <- if (length(pts)) min(pts) else NA_real_
    sc <- if (!is.na(weakest)) min(1.0, weakest / .HURDLE$rigor_backtested_port_t) else 0
    hp <- (!is.na(weakest) && weakest >= .HURDLE$rigor_backtested_port_t && n_bt == length(sup))
  } else {
    sc <- if (length(pts)) min(1.0, mean(pts) / 1.5) else 0.4
    hp <- TRUE  # mode-local: rigor 관대(Independence/Mechanism으로 게이트)
  }
  list(score = round(sc, 3), hurdle_pass = hp, n_backtested = n_bt,
       reason = sprintf("positive port_t n=%d[%s] n_backtested=%d", length(pts), tier, n_bt))
}

# ── 축 3: Falsification (r7 — 적극 반증; negative auto +0.5 폐기) ──
.axis_falsification <- function(candidate) {
  attempts <- candidate$falsification_draft$attempts %||% list()
  n <- length(attempts)
  retained_ok <- if (n) all(vapply(attempts, function(a)
    (a$result %||% "") != "survived" || (suppressWarnings(as.numeric(a$effect_retained %||% 0)) >= .HURDLE$fals_min_retained),
    logical(1))) else TRUE
  none_falsified <- !any(vapply(attempts, function(a) identical(a$result %||% "", "falsified"), logical(1)))
  score <- min(1.0, (if (n >= 1) 0.5 else 0) + (if (n >= 3) 0.3 else 0) + (if (retained_ok && n >= 1) 0.2 else 0))
  list(score = round(score, 3),
       hurdle_pass = (n >= .HURDLE$fals_min_attempts && none_falsified && retained_ok),
       n_attempts = n,
       reason = sprintf("active attempts=%d none_falsified=%s retained_ok=%s", n, none_falsified, retained_ok))
}

# ── 축 4: External (OOS) ──
.axis_external <- function(candidate) {
  o <- candidate$oos_validation_draft %||% list()
  m <- suppressWarnings(as.numeric(o$oos_months %||% NA))
  v <- suppressWarnings(as.numeric(o$oos_effect_vs_is %||% NA))
  score <- min(1.0, (if (!is.na(m) && m >= 3) 0.5 else 0) + (if (!is.na(v) && v >= 0.5) 0.5 else 0))
  list(score = round(score, 3),
       hurdle_pass = (!is.na(m) && m >= .HURDLE$ext_min_oos_months && !is.na(v) && v >= .HURDLE$ext_min_oos_vs_is),
       oos_months = m, oos_vs_is = v,
       reason = sprintf("OOS months=%s vs_is=%s", if (is.na(m)) "NA" else m, if (is.na(v)) "NA" else v))
}

# ── 축 5: Mechanism ──
.axis_mechanism <- function(candidate) {
  m <- candidate$mechanism_draft %||% list()
  expl <- m$economic_explanation %||% NA
  mtype <- m$mechanism_type %||% "unknown"
  caus <- m$causal_plausibility %||% NA
  has_expl <- !is.na(expl) && nzchar(as.character(expl)) && tolower(as.character(expl)) != "null"
  score <- min(1.0, (if (has_expl) 0.4 else 0) + (if (!is.na(mtype) && mtype != "unknown") 0.3 else 0) +
               (if (!is.na(caus) && caus %in% c("moderate", "moderate_to_high", "high")) 0.3 else 0))
  list(score = round(score, 3), hurdle_pass = (has_expl && mtype != "unknown"),
       mechanism_type = mtype, reason = sprintf("expl=%s type=%s", if (has_expl) "present" else "MISSING", mtype))
}

.weights <- function(type) {
  if (type == "methodological") c(I = 0.15, R = 0.20, F = 0.30, E = 0.15, M = 0.20)
  else c(I = 0.25, R = 0.25, F = 0.20, E = 0.20, M = 0.10)
}

# ── 메인: mode-local 승격 (INV-1/4) ──
promote_to_axiom <- function(candidate_path, threshold = 0.80, auto_inject = NULL) {
  if (!file.exists(candidate_path)) stop("candidate not found: ", candidate_path)
  candidate <- fromJSON(candidate_path, simplifyVector = FALSE)
  root <- .px_root()
  cp <- file.path(root, ".cache", "lcode_corpus.json")
  if (!file.exists(cp)) stop("lcode_corpus.json 없음 — harvester 먼저 실행")
  corpus <- fromJSON(cp, simplifyVector = FALSE)

  mode <- candidate$research_mode %||% "qepm_legacy"
  cand_metric <- candidate$metric_type %||% "estimated"
  tier <- "mode_local"
  type <- candidate$type %||% "empirical"
  polarity <- candidate$polarity %||% "unknown"

  I <- .axis_independence(candidate, corpus)
  R <- .axis_rigor(candidate, corpus, tier)
  Fx <- .axis_falsification(candidate)
  E <- .axis_external(candidate)
  M <- .axis_mechanism(candidate)

  w <- .weights(type)
  weighted <- round(as.numeric(w["I"] * I$score + w["R"] * R$score + w["F"] * Fx$score + w["E"] * E$score + w["M"] * M$score), 3)
  hurdles <- c(I$hurdle_pass, R$hurdle_pass, Fx$hurdle_pass, E$hurdle_pass, M$hurdle_pass)
  all_hurdles <- all(hurdles)
  passed <- all_hurdles && weighted >= threshold  # INV-4

  report <- list(candidate_id = candidate$candidate_id, mode = mode, tier = tier, metric_type = cand_metric,
    type = type, polarity = polarity,
    axes = list(independence = I, rigor = R, falsification = Fx, external = E, mechanism = M),
    hurdle_pass = list(independence = I$hurdle_pass, rigor = R$hurdle_pass, falsification = Fx$hurdle_pass,
                       external = E$hurdle_pass, mechanism = M$hurdle_pass),
    weights = as.list(w), weighted_score = weighted, threshold = threshold,
    all_hurdles_pass = all_hurdles, passed = passed, checked_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

  cat(sprintf("[promote] %s (%s/%s mode=%s metric=%s) weighted=%.3f hurdles=%s → %s\n",
    candidate$candidate_id, type, polarity, mode, cand_metric, weighted,
    paste(ifelse(hurdles, "P", "F"), collapse = ""), if (passed) "PASS" else "FAIL"))
  for (an in names(report$axes)) { ax <- report$axes[[an]]
    cat(sprintf("  %-13s %.2f hurdle=%-5s %s\n", an, ax$score, ax$hurdle_pass, ax$reason)) }

  if (passed) {
    ap <- .promote_to_active(candidate, report, mode)
    report$active_path <- ap
    .update_lcode_back_links(candidate, basename(ap))
    do_inject <- if (is.null(auto_inject)) as.integer(Sys.getenv("QVEST_AXIOM_AUTO_INJECT", "0")) == 1 else isTRUE(auto_inject)
    if (do_inject) {
      inj <- file.path(root, "02_Infrastructure", "axiom", "inject.R")
      if (file.exists(inj)) { source(inj, local = TRUE); if (exists("inject_axiom", mode = "function")) try(inject_axiom(ap)) }
    } else cat("[promote] dry-run (QVEST_AXIOM_AUTO_INJECT != 1) — inject 생략\n")
  } else {
    report$review_log_path <- .log_partial(candidate, report)
  }
  report
}

.next_axiom_id <- function(active_dir, mode = NULL) {
  if (is.null(mode)) {
    files <- list.files(active_dir, pattern = "^AX-\\d+\\.json$")
    nums <- as.integer(sub("AX-(\\d+)\\.json", "\\1", files)); nums <- nums[!is.na(nums)]
    return(if (!length(nums)) "AX-003" else sprintf("AX-%03d", max(nums) + 1L))
  }
  prefix <- .MODE_PREFIX[[mode]] %||% "GEN"
  md <- file.path(active_dir, "modes", mode)
  files <- if (dir.exists(md)) list.files(md, pattern = sprintf("^AX-%s-\\d+\\.json$", prefix)) else character(0)
  nums <- as.integer(sub(sprintf("AX-%s-(\\d+)\\.json", prefix), "\\1", files)); nums <- nums[!is.na(nums)]
  sprintf("AX-%s-%03d", prefix, if (length(nums)) max(nums) + 1L else 1L)
}

.promote_to_active <- function(candidate, report, mode) {
  root <- .px_root()
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  out_dir <- file.path(active_dir, "modes", mode)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ax_id <- .next_axiom_id(active_dir, mode)
  polarity <- candidate$polarity %||% "unknown"
  epistemic <- if (polarity == "negative") "provisional" else "law"  # INV-7
  stmt <- candidate$statement_draft %||% ""

  axiom <- list(
    axiom_id = ax_id, memory_id = ax_id, id = ax_id,
    research_mode = mode, tier = "mode_local",
    metric_type = candidate$metric_type %||% "estimated",
    epistemic_status = epistemic,
    type = candidate$type, polarity = polarity,
    statement = stmt, canonical_statement = stmt, text = stmt,
    supporting_l_codes = candidate$supporting_l_codes,
    scope = candidate$scope_draft %||% list(),
    evidence = candidate$evidence_draft %||% list(),
    falsification = candidate$falsification_draft %||% list(),
    mechanism = candidate$mechanism_draft %||% list(),
    oos_validation = candidate$oos_validation_draft %||% list(),
    promotion = list(source_candidate = candidate$candidate_id, weighted_score = report$weighted_score,
      threshold = report$threshold, all_hurdles_pass = report$all_hurdles_pass,
      axis_scores = lapply(report$axes, function(a) a$score),
      promoted_at = format(Sys.Date()), next_review = format(Sys.Date() + 90)),
    enforcement = "", enforcement_mode = "documented",  # INV-2
    status = "active", version = 1L
  )
  if (epistemic == "provisional") {
    axiom$expiry <- format(Sys.Date() + 180)            # INV-7 만료
    axiom$retry_trigger <- "새 construction/ML/regime L-code 출현 시 kr-inverse-pattern-miner 재도전"
  }
  if (grepl("\\[.*초안.*\\]|확정 필요", stmt)) {           # INV-6
    cat(sprintf("[promote][INV-6] %s statement가 cluster 초안 — needs_refinement=TRUE 표기\n", ax_id))
    axiom$needs_refinement <- TRUE
  }
  nrm <- file.path(root, "02_Infrastructure/memory/memory_metadata_normalize.R")
  if (file.exists(nrm)) { source(nrm, local = TRUE)
    if (exists("normalize_axiom_metadata", mode = "function"))
      axiom <- normalize_axiom_metadata(axiom = axiom, axiom_class = candidate$type %||% "methodological",
        memory_kind = "axiom_active", authority = "high", review_policy = "quarterly",
        enforcement_mode = "documented", write = FALSE) }
  out_path <- file.path(out_dir, paste0(ax_id, ".json"))
  write_json(axiom, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[promote] 승격(mode-local) → %s [%s, %s]\n", out_path, epistemic, axiom$metric_type))
  .update_sot_map(ax_id, mode, axiom)  # atomic 정합(INV-5 전제)
  out_path
}

.update_sot_map <- function(ax_id, mode, axiom) {
  root <- .px_root()
  sp <- file.path(root, "qepm", "memory", "axioms", "axiom_sot_map.json")
  if (!file.exists(sp)) return(invisible())
  sot <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(sot) || is.null(sot$axioms)) return(invisible())
  # 이미 있으면 skip
  ids <- vapply(sot$axioms, function(a) a$axiom_id %||% "", character(1))
  if (ax_id %in% ids) return(invisible())
  sot$axioms[[length(sot$axioms) + 1]] <- list(axiom_id = ax_id, name = ax_id,
    documented_active = FALSE,
    active_json_path = sprintf("qepm/memory/axioms/active/modes/%s/%s.json", mode, ax_id),
    namespace = .MODE_PREFIX[[mode]] %||% "GEN", axiom_class = axiom$axiom_class %||% "methodological",
    authority = "high", review_policy = "quarterly", enforcement_mode = "documented",
    sync_status = "MODE_LOCAL", cache_core_present = FALSE)
  write_json(sot, sp, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[promote] sot_map += %s (namespace=%s)\n", ax_id, .MODE_PREFIX[[mode]] %||% "GEN"))
}

.update_lcode_back_links <- function(candidate, ax_filename) {
  root <- .px_root(); ax_id <- sub("\\.json$", "", ax_filename)
  for (lc in (candidate$supporting_l_codes %||% character(0))) {
    files <- list.files(file.path(root, "stage_artifacts"), pattern = "^l_code_.*\\.json$",
                        full.names = TRUE, recursive = TRUE)
    for (f in files) { d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(d)) next
      if (identical(d$l_code, lc)) { d$promoted_to_axiom <- ax_id; d$promoted_at <- format(Sys.Date())
        write_json(d, f, pretty = TRUE, auto_unbox = TRUE, null = "null"); break } }
  }
}

.log_partial <- function(candidate, report) {
  root <- .px_root(); ld <- file.path(root, "qepm", "memory", "axioms", "review_log")
  dir.create(ld, recursive = TRUE, showWarnings = FALSE)
  ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
  op <- file.path(ld, sprintf("AX-PENDING_%s_%s.json", candidate$candidate_id, ts))
  failing <- names(report$hurdle_pass)[!unlist(report$hurdle_pass)]
  write_json(list(candidate_id = candidate$candidate_id, mode = report$mode,
    weighted_score = report$weighted_score, threshold = report$threshold,
    all_hurdles_pass = report$all_hurdles_pass, failing_hurdles = failing, axes = report$axes,
    logged_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    note = "INV-4: 5축 min-hurdle 동시 충족 필요. 실패 축 보강 후 재시도."),
    op, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[promote] 부분통과(hurdle 미달: %s) → %s\n", paste(failing, collapse = ","), op)); op
}

if (!interactive() && Sys.getenv("PROMOTE_SOURCED") != "1" && length(commandArgs(trailingOnly = TRUE)) > 0) {
  invisible(promote_to_axiom(commandArgs(trailingOnly = TRUE)[1]))
}
cat("[promote] Loaded (v8.0 r7-복원 + 2-tier). promote_to_axiom(candidate_path, threshold=0.80)\n")
