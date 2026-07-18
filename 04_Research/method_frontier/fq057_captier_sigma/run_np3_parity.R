# =============================================================================
# FQ-057 NP3: lw_nls registration parity + p>n degeneracy guard verification
#
#   A1. runner parity      : env_new$.get_cor_cov(R,"lw_nls")$cov == est_lw_nls(R)
#                            (runner original), bit / rel-frob < 1e-10.
#   A2. known-case parity  : existing methods (sample / ledoit_wolf / gerber_rmt)
#                            on p<n cases -> BIT-IDENTICAL old(HEAD) vs new(edited).
#                            (기존 소비자 무영향 절대 원칙 검증)
#   B.  p>n guard          : ledoit_wolf on p>n emits warning + attr('lw_degenerate'),
#                            VALUES UNCHANGED (no auto-fallback), schema intact;
#                            p<n control emits neither.
#
# estimation-quality / infra-parity only. No SR/IR/alpha (R4 P3 정합).
# Run: Rscript 04_Research/method_frontier/fq057_captier_sigma/run_np3_parity.R
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)

OLD_HRP <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/12ad97b3-ad6e-452f-96f2-2f71c829602e/scratchpad/hrp_core_OLD_HEAD.R"
NEW_HRP <- file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R")
ESTIM   <- file.path(ROOT, "04_Research/method_frontier/fq057_captier_sigma/estimators.R")
OUT_JSON <- file.path(ROOT, "stage_artifacts/method_frontier/np3_registration_report.json")
OUT_LOG  <- file.path(ROOT, "stage_artifacts/method_frontier/np3_parity_log.txt")
TOL <- 1e-10

log_lines <- c()
lg <- function(...) { s <- sprintf(...); log_lines[[length(log_lines) + 1L]] <<- s; cat(s, "\n") }
rel_frob <- function(A, B) { d <- sqrt(sum((A - B)^2)); s <- sqrt(sum(B^2)); if (s == 0) d else d / s }
maxabs   <- function(A, B) max(abs(A - B))

lg("== FQ-057 NP3 parity / guard verification ==")
lg("ROOT=%s  TOL=%.0e", ROOT, TOL)

# --- isolated sourcing (avoid harness-detection cross-talk) -------------------
# OLD/NEW sourced into fresh envs BEFORE estimators.R pollutes globalenv.
src_iso <- function(path) { e <- new.env(parent = globalenv()); sys.source(path, envir = e); e }
env_old <- src_iso(OLD_HRP)
env_new <- src_iso(NEW_HRP)
stopifnot(exists(".get_cor_cov", envir = env_old), exists(".get_cor_cov", envir = env_new),
          exists(".lw_nls_cov", envir = env_new))
source(ESTIM)   # runner: defines est_lw_nls (global); harmless global hrp_core reload
stopifnot(exists("est_lw_nls"))
lg("[src] env_old(HEAD), env_new(edited), runner est_lw_nls loaded")

set.seed(20260718)
mk <- function(n, p, sd = 0.03) { m <- matrix(rnorm(n * p, sd = sd), n, p); colnames(m) <- sprintf("A%03d", seq_len(p)); m }

# =============================================================================
# A2. KNOWN-CASE PARITY (existing methods unaffected — p<n)
# =============================================================================
lg("\n-- A2 known-case parity (sample/ledoit_wolf/gerber_rmt, p<n) --")
kc_cases   <- list(list(n = 120, p = 15), list(n = 252, p = 20), list(n = 60, p = 8))
kc_methods <- c("sample", "ledoit_wolf", "gerber_rmt")
kc_rows <- list(); kc_all_ok <- TRUE
for (cs in kc_cases) {
  R <- mk(cs$n, cs$p)
  for (m in kc_methods) {
    a <- env_old$.get_cor_cov(R, m)
    b <- env_new$.get_cor_cov(R, m)
    id  <- identical(a, b)
    dc  <- maxabs(a$cov, b$cov); dr <- maxabs(a$cor, b$cor)
    attr_absent <- is.null(attr(b, "lw_degenerate"))
    ok <- id && dc <= TOL && dr <= TOL && attr_absent
    kc_all_ok <- kc_all_ok && ok
    kc_rows[[length(kc_rows) + 1L]] <- list(n = cs$n, p = cs$p, method = m,
      identical = id, max_abs_cov = dc, max_abs_cor = dr, attr_absent = attr_absent, pass = ok)
    lg("[A2] n=%3d p=%2d %-12s identical=%-5s max|dcov|=%.2e max|dcor|=%.2e attr_absent=%-5s -> %s",
       cs$n, cs$p, m, id, dc, dr, attr_absent, if (ok) "PASS" else "FAIL")
  }
}
lg("[A2] overall: %s", if (kc_all_ok) "PASS" else "FAIL")

# =============================================================================
# A1. RUNNER PARITY (registered lw_nls == runner est_lw_nls)
# =============================================================================
lg("\n-- A1 runner parity (lw_nls registered vs estimators.R::est_lw_nls) --")
# (i) small p<n case
Rsmall <- mk(480, 10)
reg_s <- env_new$.get_cor_cov(Rsmall, "lw_nls")$cov
run_s <- est_lw_nls(Rsmall)
d_s <- maxabs(reg_s, run_s); rf_s <- rel_frob(reg_s, run_s)
ok_s <- d_s <= TOL && rf_s <= TOL
lg("[A1] small  p<n  n=480 p=10   max_abs=%.3e rel_frob=%.3e -> %s", d_s, rf_s, if (ok_s) "PASS" else "FAIL")

# (ii) real pinned window (p>n), replicate run_02 S4 (win_end=201912, 60m complete)
mr <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/method_frontier/fq057_monthly_returns.parquet")))
sn <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/method_frontier/fq057_monthly_snapshot.parquet")))
yms <- sort(unique(mr$ym)); win_end <- 201912L
win  <- tail(yms[yms <= win_end], 60)
memb <- sn[ym == win_end & member == 1L & !is.na(size), Ticker]
sub  <- mr[ym %in% win & Ticker %in% memb]
cnt  <- sub[, .N, by = Ticker][N == 60, Ticker]
W    <- dcast(sub[Ticker %in% cnt], ym ~ Ticker, value.var = "ret_m")
Rm   <- as.matrix(W[, -1]); rownames(Rm) <- W$ym
reg_b <- env_new$.get_cor_cov(Rm, "lw_nls")$cov
run_b <- est_lw_nls(Rm)
d_b <- maxabs(reg_b, run_b); rf_b <- rel_frob(reg_b, run_b)
ok_b <- d_b <= TOL && rf_b <= TOL
ev_reg <- eigen(reg_b, symmetric = TRUE, only.values = TRUE)$values
cond_reg <- max(ev_reg) / min(ev_reg); minev_reg <- min(ev_reg)
lg("[A1] window p>n  n=%d p=%d  max_abs=%.3e rel_frob=%.3e -> %s", nrow(Rm), ncol(Rm), d_b, rf_b, if (ok_b) "PASS" else "FAIL")
lg("[A1] registered lw_nls@p>n : min_ev=%.3e cond=%.2f (full-rank PSD, non-degenerate)", minev_reg, cond_reg)
a1_all_ok <- ok_s && ok_b
lg("[A1] overall: %s", if (a1_all_ok) "PASS" else "FAIL")

# also confirm registered cor validity (diag==1, symmetric)
cc_b <- env_new$.get_cor_cov(Rm, "lw_nls")
cor_diag_ok <- max(abs(diag(cc_b$cor) - 1)) <= 1e-12
cor_sym_ok  <- max(abs(cc_b$cor - t(cc_b$cor))) <= 1e-10
lg("[A1] registered cor: diag==1 %s, symmetric %s", cor_diag_ok, cor_sym_ok)

# =============================================================================
# B. p>n GUARD (warning + attr flag; values unchanged; no auto-fallback)
# =============================================================================
lg("\n-- B p>n degeneracy guard --")
# p>n : reuse Rm (p>n). capture warning.
w_pn <- NULL
res_pn <- withCallingHandlers(
  env_new$.get_cor_cov(Rm, "ledoit_wolf"),
  warning = function(w) { w_pn <<- conditionMessage(w); invokeRestart("muffleWarning") })
attr_pn <- attr(res_pn, "lw_degenerate")
warn_ok   <- !is.null(w_pn)
attr_ok   <- !is.null(attr_pn) && isTRUE(attr_pn$degenerate) && identical(attr_pn$p, ncol(Rm)) && identical(attr_pn$n_obs, nrow(Rm))
schema_ok <- all(c("cor", "cov") %in% names(res_pn)) && is.matrix(res_pn$cor) && is.matrix(res_pn$cov)
# values unchanged vs pre-guard (OLD has no guard): bit-identical cor & cov
res_pn_old <- env_old$.get_cor_cov(Rm, "ledoit_wolf")
vals_unchanged <- identical(res_pn$cor, res_pn_old$cor) && identical(res_pn$cov, res_pn_old$cov)
ev_pn <- eigen(res_pn$cov, symmetric = TRUE, only.values = TRUE)$values
cond_pn <- max(ev_pn) / min(ev_pn)   # ~1 => mu*I collapse (the KNOWN defect being flagged)
lg("[B] p>n  n=%d p=%d : warning=%s attr=%s schema_intact=%s values_unchanged=%s",
   nrow(Rm), ncol(Rm), warn_ok, attr_ok, schema_ok, vals_unchanged)
lg("[B] p>n  degenerate cond(ledoit_wolf cov)=%.4f (rho=%.6f cap_binding=%s) — defect the guard flags",
   cond_pn, attr_pn$rho, attr_pn$rho_cap_binding)
lg("[B] warning msg: %s", w_pn)

# p<n control : NO warning, NO attr
w_ctrl <- NULL
res_ctrl <- withCallingHandlers(
  env_new$.get_cor_cov(mk(120, 15), "ledoit_wolf"),
  warning = function(w) { w_ctrl <<- conditionMessage(w); invokeRestart("muffleWarning") })
ctrl_no_warn <- is.null(w_ctrl); ctrl_no_attr <- is.null(attr(res_ctrl, "lw_degenerate"))
ctrl_clean <- ctrl_no_warn && ctrl_no_attr
lg("[B] p<n control (n=120 p=15): no_warning=%s no_attr=%s -> %s",
   ctrl_no_warn, ctrl_no_attr, if (ctrl_clean) "clean" else "LEAK")
guard_pass <- warn_ok && attr_ok && schema_ok && vals_unchanged && ctrl_clean
lg("[B] overall: %s", if (guard_pass) "PASS" else "FAIL")

# =============================================================================
# callers_audit (static, from repo grep 2026-07-18)
# =============================================================================
callers_audit <- list(
  scope_note = paste0("hrp_core.R .get_cor_cov (standalone fallback) modified. A SECOND ",
    ".get_cor_cov exists in 02_Infrastructure/backtest_harness.R:414 (uses .ledoit_wolf_shrink, ",
    "a different LW formula that ALSO caps at alpha=1 -> analogous p>n isotropic collapse). ",
    "The harness copy takes precedence when backtest_harness.R is sourced (hrp_core skips its ",
    "own defs); it does NOT receive lw_nls or the p>n guard from this task (out of scope). ",
    "FOLLOW-UP: mirror registration+guard into harness if WT-time Sigma consumption routes ",
    "through the harness rather than a direct source() of hrp_core.R."),
  live_infra_consumers = list(
    list(path = "02_Infrastructure/ops/auto_sigma_weighting_ab.R:84", methods = "sample/ledoit_wolf",
         universe = "book holdings top-N (p<=25)", lookback = "LOOKBACK_DAYS(120+)", p_gt_n = FALSE),
    list(path = "02_Infrastructure/factor_db/covariance_cache.R:71,75", methods = "gerber_rmt ONLY via .get_cor_cov",
         note = "its ledoit_wolf path uses corpcor::cov.shrink, NOT .get_cor_cov; select_cov_method returns ledoit_wolf when D>=N but that bypasses this fn",
         p_gt_n = FALSE),
    list(path = "04_Research/composition_search/cycle1b_trackW/trackw_engine.R:171", methods = "sample/ledoit_wolf/gerber_rmt",
         universe = "top-N tickers", lookback = "n_days=756", p_gt_n = FALSE),
    list(path = "02_Infrastructure/prompts/risk_research_init.md:206", methods = "documents hrp_core .get_cor_cov (Sample/LW/Gerber-RMT)",
         universe = "WT-time top-25 (p<=25)", p_gt_n = FALSE)
  ),
  historical_or_perWT_pattern = list(
    list(path = "qepm/mailbox/worktask/WT-D20260606_001/risk_build.R:263",
         call = ".get_cor_cov(facMat,'ledoit_wolf')", note = "factor covariance; p=#factors can approach/exceed n"),
    list(path = "qepm/mailbox/worktask/WT-D20260508_009|010/challenge_note_risk.md",
         note = "self-caught inline LW isotropic collapse at n_obs(252) < p(348) and n_obs(252) ~ p(241) -> p>=n degeneracy ACTUALLY OCCURRED historically; motivates this guard")
  ),
  conclusion = paste0("No always-on/live infra consumer currently sends p>n to hrp_core inline ",
    "ledoit_wolf (all top-N, p<n). Guard is protective for the recurring factor-level covariance ",
    "usage pattern (historically confirmed to silently degenerate). Matches FQ-057 verdict ",
    "revival condition #4 (audit large-universe .get_cor_cov ledoit_wolf consumers for p>n).")
)

# =============================================================================
# REPORT
# =============================================================================
overall_pass <- kc_all_ok && a1_all_ok && guard_pass && cor_diag_ok && cor_sym_ok
report <- list(
  id = "FQ-057-NP3",
  task = "register analytical NLS (lw_nls) into hrp_core .get_cor_cov + p>n degeneracy guard",
  finalized_at = as.character(Sys.time()),
  tolerance = TOL,
  target_file = "02_Infrastructure/portfolio/hrp_core.R",
  parity_result = list(
    description = "A1 runner parity: registered lw_nls == estimators.R::est_lw_nls",
    small_p_lt_n = list(n = 480L, p = 10L, max_abs = d_s, rel_frob = rf_s, pass = ok_s),
    real_window_p_gt_n = list(window_end = 201912L, p = ncol(Rm), n = nrow(Rm),
      max_abs = d_b, rel_frob = rf_b, registered_cov_min_ev = minev_reg,
      registered_cov_cond = cond_reg, pass = ok_b),
    registered_cor_diag_unit = cor_diag_ok, registered_cor_symmetric = cor_sym_ok,
    overall_pass = a1_all_ok && cor_diag_ok && cor_sym_ok
  ),
  known_case_parity = list(
    description = "A2 existing methods bit-identical old(HEAD) vs new(edited), p<n (기존 소비자 무영향)",
    cases = kc_rows, overall_pass = kc_all_ok
  ),
  guard_test = list(
    description = "B p>n guard: warning + attr('lw_degenerate'); values unchanged; schema intact; p<n control clean",
    p_gt_n = list(p = ncol(Rm), n = nrow(Rm), warning_emitted = warn_ok, warning_msg = w_pn,
      attr_present = !is.null(attr_pn), attr = attr_pn, values_unchanged_vs_pre_guard = vals_unchanged,
      schema_intact = schema_ok, degenerate_cond = cond_pn),
    p_lt_n_control = list(no_warning = ctrl_no_warn, no_attr = ctrl_no_attr, clean = ctrl_clean),
    auto_fallback_applied = FALSE,
    overall_pass = guard_pass
  ),
  callers_audit = callers_audit,
  overall_pass = overall_pass
)
if (!dir.exists(dirname(OUT_JSON))) dir.create(dirname(OUT_JSON), recursive = TRUE)
write_json(report, OUT_JSON, auto_unbox = TRUE, pretty = TRUE, digits = 12, null = "null")
writeLines(unlist(log_lines), OUT_LOG)

lg("\n== NP3 OVERALL: %s ==", if (overall_pass) "PASS" else "FAIL")
lg("report: %s", OUT_JSON)
lg("log   : %s", OUT_LOG)
if (!overall_pass) quit(status = 1L)
