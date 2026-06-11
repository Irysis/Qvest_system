# v24_flip_verify.R - cost model v2.4 DEFAULT FLIP regression verification (2026-06-11)
# Independent verifier re-run (does not trust Q-Lead implementer outputs).
# metric_type = diagnostic (synthetic-arithmetic cost verification, no strategy research).
# Output: 04_Research/pg2_forensics/v24_flip_verify.json
#
# Battery (maps to task items 1-7):
#  [T1] parse("02_Infrastructure/backtest_harness.R") succeeds
#  [T2] legacy reproducibility: explicit "v2.3_flat" + alias "v2.3_kr_retail_15bps"
#       -> SYN_low / SYN_high nav_end + total_ret won-level identical to b0_ab_reverted.json
#  [T3] new default (arg omitted) == v2.4_delta closed forms:
#       low ~ -c | high ~ (1-c)(1-2c)^16 - 1 | mid strictly between | monotone low > mid > high
#  [T4] alias "v2.4_kr_retail_15bps" == "v2.4_delta" (won-level identical navs)
#  [T5] liquidation-month bug fix: f_liq scenario (v24_adv_verify_d.R repro) completes
#       WITHOUT crash in BOTH modes + PORTFOLIO_LOG contains the liquidation row
#       (N_stocks == 0, N_sells/N_buys/Turnover_Pct NA allowed)
#  [T6] constraint_defaults.json parses + label matches schema.json pattern
#       + judge_oos_helper grepl('^v2\\.4', .) maps label -> v2.4_delta
#       (functional confirm: static-weight sim under mapped model ~ -c)
#  [T7] unknown label guard: "v9.9_bogus" -> stop() in harness AND judge helper

Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

OUT_JSON <- file.path(ROOT, "04_Research/pg2_forensics/v24_flip_verify.json")

# ---- [T1] parse check (before sourcing, so a syntax error is caught here) ----
t1_err <- tryCatch({
  invisible(parse(file.path(ROOT, "02_Infrastructure/backtest_harness.R")))
  NA_character_
}, error = function(e) conditionMessage(e))
T1_pass <- is.na(t1_err)
cat(sprintf("[T1] parse backtest_harness.R: %s\n", ifelse(T1_pass, "PASS", paste("FAIL:", t1_err))))

source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))

B0_BASE <- jsonlite::fromJSON(file.path(ROOT, "04_Research/pg2_forensics/b0_ab_reverted.json"))

cc <- 0.0015

# ---- synthetic fixtures (identical construction to b0_fee_ab_test.R / v24_adv_verify.R) ----
syn_dates <- seq(as.Date("2020-01-01"), as.Date("2021-06-30"), by = "day")
syn_dates <- syn_dates[as.integer(format(syn_dates, "%u")) <= 5]
tk_all <- sprintf("T%02d", 1:10)
SYN_RAW <- CJ(Ticker = tk_all, Date = syn_dates)
SYN_RAW[, `:=`(Close = 10000, Ret = 0, Name = Ticker, Sector = "SYN")]
SYN_BM  <- data.table(Date = syn_dates, BM_Ret = 0)
syn_me  <- SYN_RAW[, .(d = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
syn_sig <- sort(syn_me$d)

f_low <- rbindlist(lapply(syn_sig, function(d)
  data.table(Date = d, Ticker = tk_all[1:5], Score = 5:1)))
f_high <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  set_i <- if (i %% 2 == 1) tk_all[1:5] else tk_all[6:10]
  data.table(Date = syn_sig[i], Ticker = set_i, Score = 5:1)
}))
# mid: 4 holdings, slide 2 per month on 10-ticker ring -> 50% name turnover
f_mid <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  start <- ((i - 1L) * 2L) %% 10L
  idx   <- ((start + 0:3) %% 10L) + 1L
  data.table(Date = syn_sig[i], Ticker = tk_all[idx], Score = 4:1)
}))
# liquidation cycle (v24_adv_verify_d.R repro): month 6 all-NA score -> liquidate path
f_liq <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  if (i == 6L) data.table(Date = syn_sig[i], Ticker = "T01", Score = NA_real_)
  else         data.table(Date = syn_sig[i], Ticker = tk_all[1:5], Score = 5:1)
}))

run_case <- function(RAW, FACTORS, n_hold, label, ...) {
  sim <- run_monthly_simulation(copy(RAW), copy(SYN_BM), copy(FACTORS),
                                n_holdings = n_hold, commission = cc,
                                initial_cap = 1e8, weight_method = "equal", ...)
  nav <- sim$DAILY_NAV_DT
  list(label = label, n_rebal = nrow(sim$PORTFOLIO_LOG),
       nav_end = tail(nav$NAV, 1), total_ret = tail(nav$NAV, 1) / 1e8 - 1,
       plog = sim$PORTFOLIO_LOG)
}
strip <- function(x) x[setdiff(names(x), "plog")]

# ---- [T2] legacy reproducibility: explicit v2.3_flat + alias, won-level vs b0_ab_reverted ----
cat("\n[T2] legacy v2.3_flat reproducibility vs b0_ab_reverted.json\n")
l_low_ex  <- run_case(SYN_RAW, f_low,  5, "low_v23_explicit",  cost_model_version = "v2.3_flat")
l_high_ex <- run_case(SYN_RAW, f_high, 5, "high_v23_explicit", cost_model_version = "v2.3_flat")
l_low_al  <- run_case(SYN_RAW, f_low,  5, "low_v23_alias",  cost_model_version = "v2.3_kr_retail_15bps")
l_high_al <- run_case(SYN_RAW, f_high, 5, "high_v23_alias", cost_model_version = "v2.3_kr_retail_15bps")

base_low_nav  <- as.numeric(B0_BASE$syn_low$nav_end)
base_high_nav <- as.numeric(B0_BASE$syn_high$nav_end)
T2_low_nav_ex  <- identical(as.numeric(l_low_ex$nav_end),  base_low_nav)
T2_high_nav_ex <- identical(as.numeric(l_high_ex$nav_end), base_high_nav)
T2_low_ret_ex  <- identical(round(l_low_ex$total_ret, 6),  as.numeric(B0_BASE$syn_low$total_ret))
T2_high_ret_ex <- identical(round(l_high_ex$total_ret, 6), as.numeric(B0_BASE$syn_high$total_ret))
T2_low_nav_al  <- identical(as.numeric(l_low_al$nav_end),  base_low_nav)
T2_high_nav_al <- identical(as.numeric(l_high_al$nav_end), base_high_nav)
T2_alias_eq    <- identical(as.numeric(l_low_al$nav_end), as.numeric(l_low_ex$nav_end)) &&
                  identical(as.numeric(l_high_al$nav_end), as.numeric(l_high_ex$nav_end))
T2_nreb <- (l_low_ex$n_rebal == B0_BASE$syn_low$n_rebal) &&
           (l_high_ex$n_rebal == B0_BASE$syn_high$n_rebal)
T2_pass <- T2_low_nav_ex && T2_high_nav_ex && T2_low_ret_ex && T2_high_ret_ex &&
           T2_low_nav_al && T2_high_nav_al && T2_alias_eq && T2_nreb
cat(sprintf("  explicit nav: low=%s high=%s | ret: low=%s high=%s\n",
            T2_low_nav_ex, T2_high_nav_ex, T2_low_ret_ex, T2_high_ret_ex))
cat(sprintf("  alias nav:    low=%s high=%s | alias==explicit=%s | n_rebal=%s -> %s\n",
            T2_low_nav_al, T2_high_nav_al, T2_alias_eq, T2_nreb, ifelse(T2_pass, "PASS", "FAIL")))
cat(sprintf("  measured low nav_end=%.4f (base %.4f) high nav_end=%.4f (base %.4f)\n",
            l_low_ex$nav_end, base_low_nav, l_high_ex$nav_end, base_high_nav))

# ---- [T3] new DEFAULT (arg omitted) == v2.4 delta closed forms ----
cat("\n[T3] default (cost_model_version omitted) == v2.4_delta closed forms\n")
d_low  <- run_case(SYN_RAW, f_low,  5, "low_default")
d_mid  <- run_case(SYN_RAW, f_mid,  4, "mid_default")
d_high <- run_case(SYN_RAW, f_high, 5, "high_default")
n_reb  <- d_low$n_rebal
e_low  <- -cc                                   # initial buy only
e_mid  <- (1 - cc)^n_reb - 1                    # 50% names: 0.5 sell + 0.5 buy = 1c per rebal
e_high <- (1 - cc) * (1 - 2 * cc)^(n_reb - 1) - 1  # 100% names: 2c per rebal after first
TOL <- 5e-4
chk <- function(m, e, tol = TOL) abs(m - e) <= tol
T3_rows <- list(
  list(case = "default_low",  measured = d_low$total_ret,  expected = e_low,
       pass = chk(d_low$total_ret,  e_low)),
  list(case = "default_mid",  measured = d_mid$total_ret,  expected = e_mid,
       pass = chk(d_mid$total_ret,  e_mid)),
  list(case = "default_high", measured = d_high$total_ret, expected = e_high,
       pass = chk(d_high$total_ret, e_high))
)
for (r in T3_rows) cat(sprintf("  %-12s measured=%+.7f expected=%+.7f diff=%.2e %s\n",
                               r$case, r$measured, r$expected, abs(r$measured - r$expected),
                               ifelse(r$pass, "PASS", "FAIL")))
T3_mono    <- (d_low$total_ret > d_mid$total_ret) && (d_mid$total_ret > d_high$total_ret)
T3_between <- (d_mid$total_ret < d_low$total_ret) && (d_mid$total_ret > d_high$total_ret)
# default must NOT reproduce legacy flat anymore (flip actually took effect)
T3_not_flat <- !identical(as.numeric(d_low$nav_end), base_low_nav) &&
               !identical(as.numeric(d_high$nav_end), base_high_nav)
T3_pass <- all(sapply(T3_rows, `[[`, "pass")) && T3_mono && T3_between && T3_not_flat
cat(sprintf("  monotone low>mid>high: %s | mid between: %s | default != legacy flat nav: %s -> %s\n",
            T3_mono, T3_between, T3_not_flat, ifelse(T3_pass, "PASS", "FAIL")))

# ---- [T4] alias "v2.4_kr_retail_15bps" == "v2.4_delta" (won-level) ----
cat("\n[T4] alias v2.4_kr_retail_15bps == v2.4_delta\n")
a4_low_d  <- run_case(SYN_RAW, f_low,  5, "low_v24_delta",  cost_model_version = "v2.4_delta")
a4_low_a  <- run_case(SYN_RAW, f_low,  5, "low_v24_alias",  cost_model_version = "v2.4_kr_retail_15bps")
a4_high_d <- run_case(SYN_RAW, f_high, 5, "high_v24_delta", cost_model_version = "v2.4_delta")
a4_high_a <- run_case(SYN_RAW, f_high, 5, "high_v24_alias", cost_model_version = "v2.4_kr_retail_15bps")
a4_mid_d  <- run_case(SYN_RAW, f_mid,  4, "mid_v24_delta",  cost_model_version = "v2.4_delta")
a4_mid_a  <- run_case(SYN_RAW, f_mid,  4, "mid_v24_alias",  cost_model_version = "v2.4_kr_retail_15bps")
T4_low  <- identical(as.numeric(a4_low_a$nav_end),  as.numeric(a4_low_d$nav_end))
T4_mid  <- identical(as.numeric(a4_mid_a$nav_end),  as.numeric(a4_mid_d$nav_end))
T4_high <- identical(as.numeric(a4_high_a$nav_end), as.numeric(a4_high_d$nav_end))
# alias must also equal the new default (same engine path)
T4_def  <- identical(as.numeric(a4_low_d$nav_end), as.numeric(d_low$nav_end)) &&
           identical(as.numeric(a4_high_d$nav_end), as.numeric(d_high$nav_end))
T4_pass <- T4_low && T4_mid && T4_high && T4_def
cat(sprintf("  alias==delta nav: low=%s mid=%s high=%s | delta==default=%s -> %s\n",
            T4_low, T4_mid, T4_high, T4_def, ifelse(T4_pass, "PASS", "FAIL")))

# ---- [T5] liquidation-month crash fix (v24_adv_verify_d.R scenario, both modes) ----
cat("\n[T5] liquidation-month scenario: no crash + liq row present (both modes)\n")
t5_run <- function(mode_label, ...) {
  r <- tryCatch(run_case(SYN_RAW, f_liq, 5, mode_label, ...),
                error = function(e) list(error = conditionMessage(e)))
  if (!is.null(r$error)) {
    list(mode = mode_label, crashed = TRUE, error = r$error,
         n_rows = NA_integer_, liq_row_present = FALSE, liq_na_cols_ok = FALSE,
         nav_end = NA_real_)
  } else {
    pl <- r$plog
    liq <- pl[N_stocks == 0L]
    has_to_cols <- all(c("N_sells", "N_buys", "Turnover_Pct") %in% names(pl))
    liq_na_ok <- nrow(liq) >= 1L && has_to_cols &&
                 all(is.na(liq$N_sells)) && all(is.na(liq$N_buys)) && all(is.na(liq$Turnover_Pct))
    list(mode = mode_label, crashed = FALSE, error = NA_character_,
         n_rows = nrow(pl), liq_row_present = nrow(liq) >= 1L,
         liq_na_cols_ok = liq_na_ok, nav_end = r$nav_end)
  }
}
t5_flat <- t5_run("liq_v23_flat", cost_model_version = "v2.3_flat")
t5_v24  <- t5_run("liq_v24_delta", cost_model_version = "v2.4_delta")
T5_pass <- !t5_flat$crashed && !t5_v24$crashed &&
           t5_flat$liq_row_present && t5_v24$liq_row_present &&
           t5_flat$liq_na_cols_ok && t5_v24$liq_na_cols_ok &&
           is.finite(t5_flat$nav_end) && is.finite(t5_v24$nav_end)
for (z in list(t5_flat, t5_v24))
  cat(sprintf("  %-13s crashed=%s rows=%s liq_row=%s na_cols_ok=%s nav_end=%s\n",
              z$mode, z$crashed, z$n_rows, z$liq_row_present, z$liq_na_cols_ok,
              format(z$nav_end, nsmall = 2)))
cat(sprintf("  -> %s\n", ifelse(T5_pass, "PASS", "FAIL")))

# ---- [T6] constraint_defaults.json + schema pattern + judge helper mapping ----
cat("\n[T6] constraint_defaults.json label + schema pattern + judge helper delta mapping\n")
t6_cfg_err <- tryCatch({
  CFG <- jsonlite::fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"),
                            simplifyVector = FALSE)
  NA_character_
}, error = function(e) conditionMessage(e))
T6_json_ok <- is.na(t6_cfg_err)
cmv <- if (T6_json_ok) CFG$tier_soft_deployment$cost_model_version else NA_character_
SCHEMA <- jsonlite::fromJSON(file.path(ROOT, "02_Infrastructure/worktask/schema.json"),
                             simplifyVector = FALSE)
pat <- SCHEMA$properties$constraints$properties$cost_model_version$pattern
if (is.null(pat)) {
  # locate pattern robustly anywhere in schema
  find_pat <- function(o) {
    if (is.list(o)) {
      if (!is.null(o$cost_model_version$pattern)) return(o$cost_model_version$pattern)
      for (el in o) { r <- find_pat(el); if (!is.null(r)) return(r) }
    }
    NULL
  }
  pat <- find_pat(SCHEMA)
}
T6_label_ok   <- identical(cmv, "v2.4_kr_retail_15bps")
T6_pattern_ok <- !is.null(pat) && grepl(pat, cmv, perl = TRUE)
# judge helper mapping: same expression as judge_oos_helper.R L377
source(file.path(ROOT, "02_Infrastructure/validation/judge_oos_helper.R"))
mapped_model <- if (grepl("^v2\\.4", cmv)) "v2.4_delta" else "v2.3_flat"
T6_map_delta <- identical(mapped_model, "v2.4_delta")
# the mapping line must actually exist in the helper source (guard against drift)
joh_src <- readLines(file.path(ROOT, "02_Infrastructure/validation/judge_oos_helper.R"),
                     warn = FALSE)
T6_map_line  <- any(grepl('grepl("^v2\\\\.4", cv)', joh_src, fixed = TRUE))
# functional: static-weight sim under mapped model behaves as delta (~ -c, price-frozen)
wdt <- data.table(Ticker = tk_all[1:5], Weight = rep(0.2, 5))
j_v24 <- .joh_run_static_weight_sim(copy(SYN_RAW), copy(wdt),
                                    start_date = as.Date("2020-01-01"),
                                    end_date   = as.Date("2021-06-30"),
                                    commission = cc, initial_cap = 1e8,
                                    cost_model_version = mapped_model)
j_v24_ret <- tail(j_v24$daily_nav$NAV, 1) / 1e8 - 1
T6_func_delta <- chk(j_v24_ret, -cc, tol = 1e-4)
T6_pass <- T6_json_ok && T6_label_ok && T6_pattern_ok && T6_map_delta && T6_map_line && T6_func_delta
cat(sprintf("  json parse=%s | label='%s' ok=%s | pattern '%s' match=%s\n",
            T6_json_ok, cmv, T6_label_ok, pat, T6_pattern_ok))
cat(sprintf("  mapping -> '%s' (delta=%s, source line present=%s) | functional static-w ret=%+.6f ~ -c: %s -> %s\n",
            mapped_model, T6_map_delta, T6_map_line, j_v24_ret, T6_func_delta,
            ifelse(T6_pass, "PASS", "FAIL")))

# ---- [T7] unknown label stop() guard ----
cat("\n[T7] unknown cost_model_version must stop()\n")
t7_harness_err <- tryCatch({
  run_monthly_simulation(copy(SYN_RAW), copy(SYN_BM), copy(f_low), n_holdings = 5,
                         commission = cc, initial_cap = 1e8, weight_method = "equal",
                         cost_model_version = "v9.9_bogus")
  NA_character_
}, error = function(e) conditionMessage(e))
t7_judge_err <- tryCatch({
  .joh_run_static_weight_sim(copy(SYN_RAW), copy(wdt),
                             start_date = as.Date("2020-01-01"),
                             end_date   = as.Date("2021-06-30"),
                             commission = cc, initial_cap = 1e8,
                             cost_model_version = "v9.9_bogus")
  NA_character_
}, error = function(e) conditionMessage(e))
T7_harness <- !is.na(t7_harness_err) && grepl("unknown cost_model_version", t7_harness_err)
T7_judge   <- !is.na(t7_judge_err)   && grepl("unknown cost_model_version", t7_judge_err)
T7_pass <- T7_harness && T7_judge
cat(sprintf("  harness stop: %s ('%s')\n  judge stop:   %s ('%s') -> %s\n",
            T7_harness, t7_harness_err, T7_judge, t7_judge_err,
            ifelse(T7_pass, "PASS", "FAIL")))

# ---- assemble JSON ----
overall <- T1_pass && T2_pass && T3_pass && T4_pass && T5_pass && T6_pass && T7_pass
res <- list(
  meta = list(date = as.character(Sys.Date()), metric_type = "diagnostic",
              verifier = "independent post-flip regression (v24_flip_verify.R)",
              scope = "default flip to v2.4_delta + v2.4 alias + liquidation rbindlist fix + constraint_defaults label",
              commission = cc, n_rebal = n_reb,
              baseline = "b0_ab_reverted.json (v2.3 flat won-level reference)"),
  T1_parse = list(error = t1_err, pass = T1_pass),
  T2_legacy_repro = list(
    explicit = list(low = strip(l_low_ex), high = strip(l_high_ex)),
    alias    = list(low = strip(l_low_al), high = strip(l_high_al)),
    baseline = list(low_nav = base_low_nav, high_nav = base_high_nav,
                    low_ret = as.numeric(B0_BASE$syn_low$total_ret),
                    high_ret = as.numeric(B0_BASE$syn_high$total_ret)),
    nav_identical_won = list(low_explicit = T2_low_nav_ex, high_explicit = T2_high_nav_ex,
                             low_alias = T2_low_nav_al, high_alias = T2_high_nav_al),
    ret_identical = list(low = T2_low_ret_ex, high = T2_high_ret_ex),
    alias_equals_explicit = T2_alias_eq, n_rebal_match = T2_nreb, pass = T2_pass),
  T3_new_default = list(rows = T3_rows, monotonic = T3_mono, mid_between = T3_between,
                        default_differs_from_legacy_flat = T3_not_flat, tol = TOL, pass = T3_pass),
  T4_v24_alias = list(low = T4_low, mid = T4_mid, high = T4_high,
                      delta_equals_default = T4_def,
                      navs = list(low_delta = a4_low_d$nav_end, low_alias = a4_low_a$nav_end,
                                  mid_delta = a4_mid_d$nav_end, mid_alias = a4_mid_a$nav_end,
                                  high_delta = a4_high_d$nav_end, high_alias = a4_high_a$nav_end),
                      pass = T4_pass),
  T5_liquidation_fix = list(flat = t5_flat, v24 = t5_v24,
                            prefix_behavior = "pre-patch harness crashed: 'Item 6 has 4 columns, inconsistent with item 1 which has 7 columns' (v24_adv_verify_d.json)",
                            pass = T5_pass),
  T6_constraint_defaults = list(json_parse_ok = T6_json_ok, label = cmv,
                                label_expected_ok = T6_label_ok,
                                schema_pattern = pat, pattern_match = T6_pattern_ok,
                                judge_mapped_model = mapped_model, map_is_delta = T6_map_delta,
                                map_source_line_present = T6_map_line,
                                judge_static_w_ret = j_v24_ret,
                                judge_functional_delta = T6_func_delta, pass = T6_pass),
  T7_unknown_label_guard = list(harness_error = t7_harness_err, judge_error = t7_judge_err,
                                pass = T7_pass),
  observations = list(
    "judge_oos_helper .joh_run_static_weight_sim default remains v2.3_flat and only aliases the v2.3 label; raw label 'v2.4_kr_retail_15bps' passed directly to it would stop(). Request path is safe (L371-377 maps via grepl before dispatch), but direct callers must pass 'v2.4_delta'.",
    "judge_oos_helper request fallback (req$cost_model_version missing) is still 'v2.3_kr_retail_15bps' -> flat. Intentional for legacy requests; new requests inherit v2.4 label from constraint_defaults.json."
  ),
  overall = ifelse(overall, "PASS", "FAIL")
)
jsonlite::write_json(res, OUT_JSON, auto_unbox = TRUE, digits = 12, pretty = TRUE)
cat(sprintf("\n[FLIP-VERIFY OVERALL] %s -> %s\n", res$overall, OUT_JSON))
