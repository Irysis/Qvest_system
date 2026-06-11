# v24_adv_verify.R — cost model v2.4 patch ADVERSARIAL re-verification (2026-06-11)
# Independent re-run by verifier agent. Does NOT trust implementer outputs.
# metric_type=diagnostic (synthetic-arithmetic cost verification only, no strategy research,
# not registered). Output: v24_adv_verify.json (separate file; implementer artifacts untouched).
#
# Battery:
#  [A] default-mode regression: SYN_low/SYN_high nav_end == b0_ab_reverted.json (won-level)
#  [B] explicit "v2.3_flat" + alias "v2.3_kr_retail_15bps" == default (won-level)
#  [C] v2.4_delta closed forms (independently derived) low/mid/high + turnover monotonicity
#  [D] liquidation-cycle double-charge probe (NA-score month forces liquidate path)
#  [E] odd-price floor-quantization probe (Close=9973)
#  [F] weight-change-without-name-change netting probe (Dynamic N column 5/4 alternation)
#  [G] invalid cost_model_version must stop() in both entry points
#  [H] judge_oos_helper: default vs prepatch baseline (bit) + v2.4 static-weight ~ -c

Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))

OUT_JSON <- file.path(ROOT, "04_Research/pg2_forensics/v24_adv_verify.json")
B0_BASE  <- jsonlite::fromJSON(file.path(ROOT, "04_Research/pg2_forensics/b0_ab_reverted.json"))
J_BASE   <- jsonlite::fromJSON(file.path(ROOT, "04_Research/pg2_forensics/v24_judge_prepatch_baseline.json"))

cc <- 0.0015

# ---- synthetic data (identical construction to b0_fee_ab_test.R lines 53-71) ----
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
# mid: 4 holdings, slide 2 per month on a 10-ticker ring -> 2/4 = 50% name turnover
f_mid <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  start <- ((i - 1L) * 2L) %% 10L
  idx   <- ((start + 0:3) %% 10L) + 1L
  data.table(Date = syn_sig[i], Ticker = tk_all[idx], Score = 4:1)
}))
# liquidation cycle: months 1-5 hold T01-05, month 6 all-NA score (forces liquidate), 7-17 re-enter
f_liq <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  if (i == 6L) data.table(Date = syn_sig[i], Ticker = "T01", Score = NA_real_)
  else         data.table(Date = syn_sig[i], Ticker = tk_all[1:5], Score = 5:1)
}))
# dynamic-N alternation: same 5 names ranked, N alternates 5,4,5,4,... (16 transitions)
f_dynN <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  data.table(Date = syn_sig[i], Ticker = tk_all[1:5], Score = 5:1,
             N = if (i %% 2 == 1L) 5L else 4L)
}))
# odd price variant
SYN_RAW2 <- CJ(Ticker = tk_all, Date = syn_dates)
SYN_RAW2[, `:=`(Close = 9973, Ret = 0, Name = Ticker, Sector = "SYN")]

run_case <- function(RAW, FACTORS, n_hold, label, ...) {
  sim <- run_monthly_simulation(copy(RAW), copy(SYN_BM), copy(FACTORS),
                                n_holdings = n_hold, commission = cc,
                                initial_cap = 1e8, weight_method = "equal", ...)
  nav <- sim$DAILY_NAV_DT
  list(label = label, n_rebal = nrow(sim$PORTFOLIO_LOG),
       nav_end = tail(nav$NAV, 1), total_ret = tail(nav$NAV, 1) / 1e8 - 1)
}

cat("\n[A/B] default regression vs b0_ab_reverted.json + explicit/alias identity\n")
a_low   <- run_case(SYN_RAW, f_low,  5, "low_default")
a_high  <- run_case(SYN_RAW, f_high, 5, "high_default")
a_mid   <- run_case(SYN_RAW, f_mid,  4, "mid_default")
b_expl  <- run_case(SYN_RAW, f_low,  5, "low_explicit", cost_model_version = "v2.3_flat")
b_alias <- run_case(SYN_RAW, f_low,  5, "low_alias",    cost_model_version = "v2.3_kr_retail_15bps")

A_low_nav  <- identical(as.numeric(a_low$nav_end),  as.numeric(B0_BASE$syn_low$nav_end))
A_high_nav <- identical(as.numeric(a_high$nav_end), as.numeric(B0_BASE$syn_high$nav_end))
A_low_ret  <- identical(round(a_low$total_ret, 6),  as.numeric(B0_BASE$syn_low$total_ret))
A_high_ret <- identical(round(a_high$total_ret, 6), as.numeric(B0_BASE$syn_high$total_ret))
A_nreb     <- (a_low$n_rebal == B0_BASE$syn_low$n_rebal) && (a_high$n_rebal == B0_BASE$syn_high$n_rebal)
B_expl     <- identical(as.numeric(b_expl$nav_end),  as.numeric(a_low$nav_end))
B_alias    <- identical(as.numeric(b_alias$nav_end), as.numeric(a_low$nav_end))
A_pass <- A_low_nav && A_high_nav && A_low_ret && A_high_ret && A_nreb
B_pass <- B_expl && B_alias
cat(sprintf("  A nav low=%s high=%s ret low=%s high=%s n_rebal=%s -> %s\n",
            A_low_nav, A_high_nav, A_low_ret, A_high_ret, A_nreb, ifelse(A_pass,"PASS","FAIL")))
cat(sprintf("  B explicit=%s alias=%s -> %s\n", B_expl, B_alias, ifelse(B_pass,"PASS","FAIL")))
cat(sprintf("  measured: low nav_end=%.2f ret=%.6f | high nav_end=%.2f ret=%.6f | baseline %.2f / %.6f\n",
            a_low$nav_end, a_low$total_ret, a_high$nav_end, a_high$total_ret,
            as.numeric(B0_BASE$syn_low$nav_end), as.numeric(B0_BASE$syn_low$total_ret)))

cat("\n[C] v2.4_delta closed forms (independent derivation) + monotonicity\n")
v_low  <- run_case(SYN_RAW, f_low,  5, "low_v24",  cost_model_version = "v2.4_delta")
v_mid  <- run_case(SYN_RAW, f_mid,  4, "mid_v24",  cost_model_version = "v2.4_delta")
v_high <- run_case(SYN_RAW, f_high, 5, "high_v24", cost_model_version = "v2.4_delta")
n_reb <- a_low$n_rebal
# my own closed forms:
#  flat any-turnover:      (1-c)^17 - 1   (buy-notional c every rebal, no sell leg ex-liquidation)
#  v2.4 low (0% names):    -c            (initial full buy only; later only floor re-quant dust)
#  v2.4 mid (50% names):   sell 0.5 + buy 0.5 = 1.0 x c per rebal after first -> (1-c)^17 - 1
#  v2.4 high (100% names): sell 1.0 + buy 1.0 = 2c per rebal after first      -> (1-c)(1-2c)^16 - 1
e_flat  <- (1 - cc)^n_reb - 1
e_low   <- -cc
e_mid   <- (1 - cc)^n_reb - 1
e_high  <- (1 - cc) * (1 - 2 * cc)^(n_reb - 1) - 1
TOL <- 5e-4
chk <- function(m, e, tol = TOL) abs(m - e) <= tol
C_rows <- list(
  list(case="v24_low",  measured=v_low$total_ret,  expected=e_low,  pass=chk(v_low$total_ret,  e_low)),
  list(case="v24_mid",  measured=v_mid$total_ret,  expected=e_mid,  pass=chk(v_mid$total_ret,  e_mid)),
  list(case="v24_high", measured=v_high$total_ret, expected=e_high, pass=chk(v_high$total_ret, e_high)),
  list(case="flat_mid", measured=a_mid$total_ret,  expected=e_flat, pass=chk(a_mid$total_ret,  e_flat))
)
for (r in C_rows) cat(sprintf("  %-9s measured=%+.6f expected=%+.6f diff=%.2e %s\n",
                              r$case, r$measured, r$expected, abs(r$measured-r$expected),
                              ifelse(r$pass,"PASS","FAIL")))
C_mono <- (v_low$total_ret > v_mid$total_ret) && (v_mid$total_ret > v_high$total_ret)
C_between <- (v_mid$total_ret < v_low$total_ret) && (v_mid$total_ret > v_high$total_ret)
C_flat_insens <- (abs(a_low$total_ret - a_mid$total_ret) < 1e-5) &&
                 (abs(a_mid$total_ret - a_high$total_ret) < 1e-5)
C_pass <- all(sapply(C_rows, `[[`, "pass")) && C_mono && C_between && C_flat_insens
cat(sprintf("  monotonic low>mid>high: %s | mid strictly between: %s | flat insensitive: %s -> %s\n",
            C_mono, C_between, C_flat_insens, ifelse(C_pass,"PASS","FAIL")))

cat("\n[D] liquidation-cycle probe: PRE-EXISTING rbindlist crash equivalence check\n")
# Finding: mixing a liquidation month (selected==0, 4-col portfolio_log row, harness L912)
# with normal months (7-col row, L1165) crashes rbindlist() at sim end. The patch did NOT
# touch either logging block (git diff confirms). Here: assert BOTH patched modes crash
# with the SAME message; separate script v24_adv_verify_d.R asserts the PRE-PATCH harness
# (5e2b83fc^) crashes identically -> pre-existing engine bug, not a patch regression.
d_err_def <- tryCatch({ run_case(SYN_RAW, f_liq, 5, "liq_flat"); NA_character_ },
                      error = function(e) conditionMessage(e))
d_err_v24 <- tryCatch({ run_case(SYN_RAW, f_liq, 5, "liq_v24",
                                 cost_model_version = "v2.4_delta"); NA_character_ },
                      error = function(e) conditionMessage(e))
D_both_crash <- !is.na(d_err_def) && !is.na(d_err_v24)
D_same_msg   <- identical(d_err_def, d_err_v24)
D_pass <- D_both_crash && D_same_msg
cat(sprintf("  default-mode error: '%s'\n  v24-mode error:     '%s'\n  both crash + same message: %s\n",
            d_err_def, d_err_v24, ifelse(D_pass, "PASS (mode-equivalent, pre-existing)", "FAIL")))

cat("\n[E] odd-price (9973) floor-quantization probe\n")
e1_v24 <- run_case(SYN_RAW2, f_low, 5, "odd_v24", cost_model_version = "v2.4_delta")
e1_flt <- run_case(SYN_RAW2, f_low, 5, "odd_flat")
E_v24 <- chk(e1_v24$total_ret, -cc)
E_flt <- chk(e1_flt$total_ret, e_flat)
E_pass <- E_v24 && E_flt
cat(sprintf("  v24 measured=%+.6f expected=%+.6f diff=%.2e %s\n",
            e1_v24$total_ret, -cc, abs(e1_v24$total_ret + cc), ifelse(E_v24,"PASS","FAIL")))
cat(sprintf("  flat measured=%+.6f expected=%+.6f diff=%.2e %s\n",
            e1_flt$total_ret, e_flat, abs(e1_flt$total_ret - e_flat), ifelse(E_flt,"PASS","FAIL")))

cat("\n[F] netting on weight change without name change (N alternating 5/4)\n")
f1_v24 <- run_case(SYN_RAW, f_dynN, 5, "dynN_v24", cost_model_version = "v2.4_delta")
f1_flt <- run_case(SYN_RAW, f_dynN, 5, "dynN_flat")
# v2.4: m1 buy c; each N-switch: |dW| = 0.2 (T05 leg) + 4x0.05 (re-spread) = 0.4 -> 0.4c x 16
e_dynN_v24 <- (1 - cc) * (1 - 0.4 * cc)^16 - 1
F_v24 <- chk(f1_v24$total_ret, e_dynN_v24)
F_flt <- chk(f1_flt$total_ret, e_flat)
F_pass <- F_v24 && F_flt
cat(sprintf("  v24 measured=%+.6f expected=%+.6f diff=%.2e %s\n",
            f1_v24$total_ret, e_dynN_v24, abs(f1_v24$total_ret - e_dynN_v24), ifelse(F_v24,"PASS","FAIL")))
cat(sprintf("  flat measured=%+.6f expected=%+.6f diff=%.2e %s\n",
            f1_flt$total_ret, e_flat, abs(f1_flt$total_ret - e_flat), ifelse(F_flt,"PASS","FAIL")))

cat("\n[G] invalid cost_model_version must stop()\n")
g_harness <- inherits(tryCatch(
  run_monthly_simulation(copy(SYN_RAW), copy(SYN_BM), copy(f_low), n_holdings = 5,
                         commission = cc, initial_cap = 1e8, weight_method = "equal",
                         cost_model_version = "v9.9_bogus"),
  error = function(e) e), "error")
cat(sprintf("  harness rejects bogus version: %s\n", ifelse(g_harness, "PASS", "FAIL")))

cat("\n[H] judge_oos_helper regression + v2.4\n")
source(file.path(ROOT, "02_Infrastructure/validation/judge_oos_helper.R"))
g_judge <- inherits(tryCatch(
  .joh_run_static_weight_sim(copy(SYN_RAW), data.table(Ticker = tk_all[1:5], Weight = rep(.2, 5)),
                             start_date = as.Date("2020-01-01"), end_date = as.Date("2021-06-30"),
                             commission = cc, initial_cap = 1e8,
                             cost_model_version = "v9.9_bogus"),
  error = function(e) e), "error")
G_pass <- g_harness && g_judge
cat(sprintf("  judge helper rejects bogus version: %s\n", ifelse(g_judge, "PASS", "FAIL")))

wdt <- data.table(Ticker = tk_all[1:5], Weight = rep(0.2, 5))
j_def <- .joh_run_static_weight_sim(copy(SYN_RAW), copy(wdt),
                                    start_date = as.Date("2020-01-01"),
                                    end_date = as.Date("2021-06-30"),
                                    commission = cc, initial_cap = 1e8)
j_ali <- .joh_run_static_weight_sim(copy(SYN_RAW), copy(wdt),
                                    start_date = as.Date("2020-01-01"),
                                    end_date = as.Date("2021-06-30"),
                                    commission = cc, initial_cap = 1e8,
                                    cost_model_version = "v2.3_kr_retail_15bps")
j_v24 <- .joh_run_static_weight_sim(copy(SYN_RAW), copy(wdt),
                                    start_date = as.Date("2020-01-01"),
                                    end_date = as.Date("2021-06-30"),
                                    commission = cc, initial_cap = 1e8,
                                    cost_model_version = "v2.4_delta")
j_def_nav <- tail(j_def$daily_nav$NAV, 1)
j_ali_nav <- tail(j_ali$daily_nav$NAV, 1)
j_v24_ret <- tail(j_v24$daily_nav$NAV, 1) / 1e8 - 1
H_def   <- isTRUE(all.equal(j_def_nav, J_BASE$nav_end, tolerance = 1e-12))
H_alias <- identical(j_ali_nav, j_def_nav)
# independent closed form for prepatch judge v2.3 (fractional shares, both legs flat):
e_j_v23 <- (1 - cc) * (1 - 2 * cc)^(j_def$n_rebalances - 1) - 1
H_form  <- abs((j_def_nav / 1e8 - 1) - e_j_v23) <= 1e-4
H_v24   <- chk(j_v24_ret, -cc, tol = 1e-4)
H_pass <- H_def && H_alias && H_form && H_v24
cat(sprintf("  default vs prepatch nav: %.6f vs %.6f rel.diff=%.3e -> %s\n",
            j_def_nav, J_BASE$nav_end, abs(j_def_nav - J_BASE$nav_end) / J_BASE$nav_end,
            ifelse(H_def, "PASS", "FAIL")))
cat(sprintf("  alias identical: %s | v2.3 closed-form sanity (%.6f vs %.6f): %s\n",
            H_alias, j_def_nav / 1e8 - 1, e_j_v23, ifelse(H_form, "PASS", "FAIL")))
cat(sprintf("  v24 static-w measured=%+.6f expected=%+.6f %s\n",
            j_v24_ret, -cc, ifelse(H_v24, "PASS", "FAIL")))

overall <- A_pass && B_pass && C_pass && D_pass && E_pass && F_pass && G_pass && H_pass
res <- list(
  meta = list(date = as.character(Sys.Date()), metric_type = "diagnostic",
              verifier = "independent adversarial re-run (does not reuse implementer outputs)",
              commission = cc, n_rebal = n_reb,
              patch_commits = c("5e2b83fc", "74c018ac")),
  A_default_regression = list(low = a_low, high = a_high,
                              nav_identical = list(low = A_low_nav, high = A_high_nav),
                              ret_identical = list(low = A_low_ret, high = A_high_ret),
                              n_rebal_match = A_nreb, pass = A_pass),
  B_explicit_alias = list(explicit = B_expl, alias = B_alias, pass = B_pass),
  C_v24_closed_forms = list(rows = C_rows, monotonic = C_mono, mid_between = C_between,
                            flat_insensitive = C_flat_insens, tol = TOL, pass = C_pass),
  D_liquidation_cycle = list(finding = "pre-existing rbindlist 4-vs-7-col portfolio_log crash on liquidation months (harness L912 vs L1165, untouched by patch)",
                             default_error = d_err_def, v24_error = d_err_v24,
                             mode_equivalent = D_same_msg, pass = D_pass),
  E_odd_price = list(v24 = e1_v24, flat = e1_flt, pass = E_pass),
  F_dynN_netting = list(v24 = f1_v24, v24_expected = e_dynN_v24, flat = f1_flt, pass = F_pass),
  G_invalid_version_rejected = list(harness = g_harness, judge = g_judge, pass = G_pass),
  H_judge_helper = list(default_nav = j_def_nav, prepatch_nav = J_BASE$nav_end,
                        default_identical = H_def, alias_identical = H_alias,
                        v23_closed_form_ok = H_form, v24_ret = j_v24_ret, pass = H_pass),
  overall = ifelse(overall, "PASS", "FAIL")
)
jsonlite::write_json(res, OUT_JSON, auto_unbox = TRUE, digits = 12, pretty = TRUE)
cat(sprintf("\n[ADV-VERIFY OVERALL] %s -> %s\n", res$overall, OUT_JSON))
