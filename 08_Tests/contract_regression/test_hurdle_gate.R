# ============================================================================
# test_hurdle_gate.R - contract regression for run_hurdle_gate()
# Target (read-only): 02_Infrastructure/hurdle_gate.R
# Sandboxed: PROJECT_ROOT / CLAUDE_PROJECT_DIR / cwd all point to tempdir()
# so no repo file (grade_a_catalog, .cache, axioms) is read or written.
# Covered branches:
#   - verdict$screening: screen_pass TRUE -> STANDALONE_TRACK (grade A/B path),
#     screen_pass FALSE -> route NONE
#   - .drawdown_frequency_profile structural-drawdown branches:
#     (a) single deep episode -> tail_review only (NOT hard fail)
#     (b) MDD >= 70% catastrophic -> structural hard fail
#     (c) repeated 45%+ episodes >= 15 -> structural hard fail
#     (d) severe episode >= 252 days underwater -> structural hard fail
#   - D004 E2E: catastrophic crash -> hard_fail TRUE, grade F
#   - D001 insufficient data early return
#   - D000 PIT absolute rejection (SPEC check - see t_check_spec)
# ============================================================================

suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})

.this_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.here <- dirname(normalizePath(.this_file, winslash = "/"))
source(file.path(.here, "helpers.R"))
REAL_ROOT <- t_root()

SB <- t_sandbox("hurdle_gate")
dir.create(file.path(SB, "02_Infrastructure"), showWarnings = FALSE)  # no .cpp -> R fallback
dir.create(file.path(SB, "strategies"), showWarnings = FALSE)
PROJECT_ROOT <- SB
Sys.setenv(CLAUDE_PROJECT_DIR = SB)   # axiom/family lookups resolve to empty sandbox
setwd(SB)                             # relative .cache lookups stay in sandbox
INFRA_DIR <- file.path(REAL_ROOT, "02_Infrastructure")

source(file.path(REAL_ROOT, "02_Infrastructure/hurdle_gate.R"))

# ---------------------------------------------------------------------------
# Fixture builders (deterministic, no RNG)
# ---------------------------------------------------------------------------
weekday_dates <- function(n, start = as.Date("2017-01-02")) {
  d <- seq(start, by = "day", length.out = ceiling(n * 1.5) + 14)
  d <- d[!format(d, "%u") %in% c("6", "7")]
  d[seq_len(n)]
}

mk_sim <- function(r, rb, pit_shift_days = NULL) {
  n <- length(r)
  d <- weekday_dates(n)
  grp <- format(d, "%Y-%m")
  last_idx <- cumsum(rle(grp)$lengths)
  sig_i <- head(last_idx, -1L)               # last weekday of each month
  sig_dates  <- d[sig_i]
  exec_dates <- d[sig_i + 1L]                # first weekday of next month
  factor_dates <- if (is.null(pit_shift_days)) sig_dates else exec_dates + pit_shift_days
  FACTORS <- rbindlist(lapply(factor_dates, function(fd)
    data.table(Date = fd, Ticker = paste0("T", 1:30), Score = as.numeric(1:30))))
  PLOG <- data.table(Signal_Date = sig_dates, Exec_Date = exec_dates,
                     N_stocks = 20L, Turnover_Pct = 60)
  list(sim = list(strategy_xts = xts(r, d), bm_xts = xts(rb, d),
                  DAILY_NAV_DT = data.table(Date = d, NAV = cumprod(1 + r)),
                  PORTFOLIO_LOG = PLOG),
       FACTORS = FACTORS)
}

run_case <- function(name, r, rb, pit_shift_days = NULL) {
  fx <- mk_sim(r, rb, pit_shift_days = pit_shift_days)
  od <- file.path(SB, "strategies", name, "output")
  dir.create(od, recursive = TRUE, showWarnings = FALSE)
  run_hurdle_gate(fx$sim, FACTORS = fx$FACTORS, strategy_name = name,
                  output_dir = od, strict_mode = FALSE)
}

n_days <- 1560L  # ~6.2 years of weekdays

# NOTE on fixture design: run_hurdle_gate D071 calls compute_dsr() with the
# ANNUALIZED Sharpe but daily skew/kurtosis; its sr_se = sqrt(1 - skew*SR +
# (ekurt/4)*SR^2) goes NaN (unguarded "if (sr_se > 1e-08)" crash) whenever
# |skew*SR| or platykurtosis is large (e.g. SR_ann > ~1.4 with two-point
# returns). Fixtures below deliberately keep SR/skew inside the valid region;
# the fragility itself is a target-code robustness issue (reported, not fixed).

# ============================================================================
# H1: strong deterministic uptrend -> screening PASS via standalone track
#     (zig-zag carrier: CAGR ~15%, SR ~1.05, negligible drawdown)
# ============================================================================
zig   <- rep(c(1, -1), n_days / 2)
r_up  <- 0.0006 + 0.0090 * zig
rb_up <- 0.0002 + 0.0050 * zig
res_up <- run_case("TCASE_H1", r_up, rb_up)
scr_up <- res_up$verdict$screening
t_check("hurdle:H1_screening_fields_present",
        is.list(scr_up) && is.logical(scr_up$screen_pass) &&
        is.character(scr_up$screen_route) && nzchar(scr_up$note))
t_check("hurdle:H1_strong_signal_screen_pass",
        isTRUE(scr_up$screen_pass) &&
        identical(scr_up$screen_route, "STANDALONE_TRACK") &&
        res_up$grade %in% c("A", "A_NOVEL", "A_DEF", "B", "B_DEF"))
t_check("hurdle:H1_not_authoritative_label",
        identical(res_up$authoritative, FALSE) &&
        identical(res_up$grade_basis, "proxy_diagnostic_18component"))

# ============================================================================
# H2: flat noise -> screening FAIL, route NONE
# ============================================================================
r_flat  <- 2e-5 * rep(c(1, -1), n_days / 2)
rb_flat <- rep(0, n_days)
res_flat <- run_case("TCASE_H2", r_flat, rb_flat)
t_check("hurdle:H2_no_signal_screen_fail_route_none",
        identical(res_flat$verdict$screening$screen_pass, FALSE) &&
        identical(res_flat$verdict$screening$screen_route, "NONE"))

# ============================================================================
# H3 E2E: catastrophic crash (zig-zag carrier + crash drift; crash segment
#         pair factor (1.004)(0.988)^165 -> dd ~73.6% >= 70%)
#         -> D004 structural drawdown hard fail, grade F
# ============================================================================
r_crash <- c(rep(c(0.0088, -0.0072), 350),   # pre-crash uptrend (700d)
             rep(c(0.0040, -0.0120), 165),   # crash (330d, cum ~-73.6%)
             rep(c(0.0086, -0.0074), 265))   # recovery (530d)
res_crash <- run_case("TCASE_H3", r_crash, rb_up)
t_check("hurdle:H3_catastrophic_dd_hard_fail_grade_F",
        isTRUE(res_crash$verdict$hard_fail) &&
        identical(res_crash$grade, "F") &&
        any(grepl("Structural drawdown", res_crash$verdict$fail_reasons,
                  fixed = TRUE)))
t_check("hurdle:H3_pass_false",
        identical(res_crash$pass, FALSE))

# ============================================================================
# H4 unit: .drawdown_frequency_profile branches (thresholds are code SOT:
#          severe 0.45 / extreme 0.55 / catastrophic 0.70 / counts 15,6 /
#          day frac 0.25 / max underwater 252d)
# ============================================================================
# (a) single ~48.8% episode -> tail_review only
r_tail <- c(rep(0.001, 300), rep(-0.0055, 130), rep(0.001, 600))
p_a <- .drawdown_frequency_profile(xts(r_tail, weekday_dates(length(r_tail))))
t_check("hurdle:H4a_single_deep_episode_tail_review_not_structural",
        isTRUE(p_a$tail_review) && identical(p_a$structural_hard_fail, FALSE) &&
        identical(p_a$severe_count, 1L) && identical(p_a$catastrophic, FALSE) &&
        p_a$mdd > 0.45 && p_a$mdd < 0.55)

# (b) catastrophic depth
p_b <- .drawdown_frequency_profile(xts(r_crash, weekday_dates(length(r_crash))))
t_check("hurdle:H4b_catastrophic_structural",
        isTRUE(p_b$catastrophic) && isTRUE(p_b$structural_hard_fail) &&
        p_b$mdd >= 0.70)

# (c) repeated severe episodes: initial drop below -45%, then 15 cycles
#     oscillating across the -45% line -> 16 distinct severe episodes >= 15
r_rep <- c(rep(-0.008, 78), rep(c(0.037, -0.0355), 15))
p_c <- .drawdown_frequency_profile(xts(r_rep, weekday_dates(length(r_rep))))
nav_c <- cumprod(1 + r_rep); dd_c <- nav_c / cummax(nav_c) - 1
exp_episodes <- sum(rle(dd_c <= -0.45)$values)   # independent episode count
t_check("hurdle:H4c_repeated_severe_episodes_structural",
        identical(p_c$severe_count, as.integer(exp_episodes)) &&
        p_c$severe_count >= 15L && isTRUE(p_c$structural_hard_fail) &&
        identical(p_c$catastrophic, FALSE) && p_c$mdd < 0.55)

# (d) single episode but >= 252 days underwater below -45% -> structural
r_long <- c(rep(-0.008, 78), rep(0, 260), rep(0.002, 1200))
p_d <- .drawdown_frequency_profile(xts(r_long, weekday_dates(length(r_long))))
t_check("hurdle:H4d_long_underwater_structural",
        isTRUE(p_d$structural_hard_fail) && identical(p_d$catastrophic, FALSE) &&
        p_d$severe_max_days >= 252L &&
        p_d$severe_day_frac < p_d$severe_day_hard_frac)

# ============================================================================
# H5: insufficient data early return (< 60 trading days)
# ============================================================================
res_short <- run_case("TCASE_H5", rep(0.001, 40), rep(0.0005, 40))
t_check("hurdle:H5_insufficient_data_hard_fail",
        identical(res_short$pass, FALSE) && res_short$score == 0 &&
        isTRUE(res_short$verdict$hard_fail))

# ============================================================================
# H6 SPEC: PIT absolute rejection (D000). Factor signal dates are set AFTER
# their execution dates (blatant look-ahead). Per spec (pit.md /
# measurement-graduation "PIT only is absolute across tiers" + D000 comment
# "Each factor date should be < its corresponding exec date") this must
# hard-fail with a "PIT violation" reason and screen_pass FALSE.
# NOTE: the detector at hurdle_gate.R:325-331 filters exec_dates > fd and then
# tests min(matched_exec) < fd, which is unsatisfiable by construction - if
# this shows [DEFECT], the detection is dead code (target-code bug, reported
# upstream; NOT fixed by this suite).
# ============================================================================
res_pit <- run_case("TCASE_H6", r_up, rb_up, pit_shift_days = 40L)
t_check_spec("hurdle:H6_pit_violation_absolute_rejection",
             isTRUE(res_pit$verdict$hard_fail) &&
             any(grepl("PIT violation", res_pit$verdict$fail_reasons,
                       fixed = TRUE)) &&
             identical(res_pit$verdict$screening$screen_pass, FALSE),
             note = paste("D000 PIT detector never fires:",
                          "exec_dates[exec_dates > fd] then min(.) < fd is",
                          "always FALSE -> look-ahead signals pass the gate"))

t_summary("test_hurdle_gate")
