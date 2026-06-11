# v24_fee_ab_test.R — cost model v2.4 (delta-based) 검증 하니스 (2026-06-11)
# metric_type=diagnostic (합성 산술 검증 — 전략 리서치 아님, 레지스트리 미등재)
#
# 검증 항목:
#   [R1] 회귀 no-op: 패치 후 기본값(v2.3_flat)이 b0_ab_reverted.json과 동일
#        (total_ret -0.025194 양쪽, nav_end 원단위 동일)
#   [R2] 명시 "v2.3_flat" / alias "v2.3_kr_retail_15bps" = 기본값과 비트 동일
#   [D1] v2.4_delta 합성 산술: SYN_low(명목회전 0%) ~= 최초 매수 15bps 1회,
#        SYN_high(100%) ~= 최초 15bps + 이후 리밸마다 (매도15+매수15)bps
#   [D2] SYN_mid(name-turnover 50%) 신설 — v2.4 비용의 회전율 단조성
#   [J1] judge_oos_helper 기본값 회귀 (v24_judge_prepatch_baseline.json 대비 비트 동일)
#   [J2] judge_oos_helper v2.4_delta 합성 산술 (정적 weight = drift 외 실거래 0)
#
# 분석적 기대값 (선도출, diagnostic — 합성 산술 비용검증의 기대값 계산, B0 선례):
#   c = 0.0015, 17 리밸, 가격고정(Close=10000, Ret=0) -> NAV 감소 = 순수 비용
#   v2.3_flat (전 케이스):  (1-c)^17 - 1            (회전율 무관 flat)
#   v2.4 SYN_low:           -c                       (최초 전액 매수레그 1회 + 미세 재양자화)
#   v2.4 SYN_mid:           (1-c)^17 - 1             (최초 c + 이후 16리밸 x |D|=1.0xNAV -> c)
#   v2.4 SYN_high:          (1-c)*(1-2c)^16 - 1      (최초 c + 이후 16리밸 x (매도c+매수c))
#   judge v2.3:             (1-c)*(1-2c)^16 - 1      (전량매도c + 전량매수c, 매 리밸)
#   judge v2.4 (정적 w):    ~= -c                    (최초 매수만, drift=0)
#   허용오차: 정수 shares floor 양자화 + fee-drift 재조정 -> abs tol 5e-4 (judge v2.4는 1e-4)

Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))

OUT_JSON <- file.path(ROOT, "04_Research/pg2_forensics/v24_ab_results.json")
B0_BASELINE    <- file.path(ROOT, "04_Research/pg2_forensics/b0_ab_reverted.json")
JUDGE_BASELINE <- file.path(ROOT, "04_Research/pg2_forensics/v24_judge_prepatch_baseline.json")

cc <- 0.0015

# ════════════════ 합성 데이터 (b0_fee_ab_test.R 과 동일 구성) ════════════════
syn_dates <- seq(as.Date("2020-01-01"), as.Date("2021-06-30"), by = "day")
syn_dates <- syn_dates[as.integer(format(syn_dates, "%u")) <= 5]
tk_all <- sprintf("T%02d", 1:10)

SYN_RAW <- CJ(Ticker = tk_all, Date = syn_dates)
SYN_RAW[, `:=`(Close = 10000, Ret = 0, Name = Ticker, Sector = "SYN")]
SYN_BM <- data.table(Date = syn_dates, BM_Ret = 0)

syn_me  <- SYN_RAW[, .(d = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
syn_sig <- sort(syn_me$d)

# SYN_low: 매월 동일 5종목 (name turnover 0%) — b0 동일
f_low <- rbindlist(lapply(syn_sig, function(d)
  data.table(Date = d, Ticker = tk_all[1:5], Score = 5:1)))
# SYN_high: 매월 5종목 전체 교체 (name turnover 100%) — b0 동일
f_high <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  set_i <- if (i %% 2 == 1) tk_all[1:5] else tk_all[6:10]
  data.table(Date = syn_sig[i], Ticker = set_i, Score = 5:1)
}))
# SYN_mid (신설): n_hold=4, 10종목 링에서 매월 2칸 슬라이드 -> 매 리밸 2/4 교체 = 50%
f_mid <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  start <- ((i - 1L) * 2L) %% 10L
  idx   <- ((start + 0:3) %% 10L) + 1L
  data.table(Date = syn_sig[i], Ticker = tk_all[idx], Score = 4:1)
}))

run_case <- function(FACTORS, n_hold, label, ...) {
  sim <- run_monthly_simulation(copy(SYN_RAW), copy(SYN_BM), FACTORS,
                                n_holdings  = n_hold,
                                commission  = cc,
                                initial_cap = 1e8,
                                weight_method = "equal", ...)
  nav <- sim$DAILY_NAV_DT
  list(label     = label,
       n_rebal   = nrow(sim$PORTFOLIO_LOG),
       nav_end   = tail(nav$NAV, 1),
       total_ret = tail(nav$NAV, 1) / 1e8 - 1)
}

cat("\n==== [R1/R2] regression: default = v2.3_flat (bit-identical) ====\n")
reg_low   <- run_case(f_low,  5, "SYN_low_default")                                  # 기본값 (인자 미전달)
reg_high  <- run_case(f_high, 5, "SYN_high_default")
reg_mid   <- run_case(f_mid,  4, "SYN_mid_default")                                  # flat 무감도 3점째
expl_low  <- run_case(f_low,  5, "SYN_low_explicit_flat",
                      cost_model_version = "v2.3_flat")
alias_low <- run_case(f_low,  5, "SYN_low_alias_v23kr",
                      cost_model_version = "v2.3_kr_retail_15bps")

b0 <- jsonlite::fromJSON(B0_BASELINE)
r1_low_nav  <- identical(as.numeric(reg_low$nav_end),  as.numeric(b0$syn_low$nav_end))
r1_high_nav <- identical(as.numeric(reg_high$nav_end), as.numeric(b0$syn_high$nav_end))
r1_low_ret  <- isTRUE(all.equal(round(reg_low$total_ret, 6),  b0$syn_low$total_ret,  tolerance = 1e-12))
r1_high_ret <- isTRUE(all.equal(round(reg_high$total_ret, 6), b0$syn_high$total_ret, tolerance = 1e-12))
r2_expl  <- identical(as.numeric(expl_low$nav_end),  as.numeric(reg_low$nav_end))
r2_alias <- identical(as.numeric(alias_low$nav_end), as.numeric(reg_low$nav_end))
r1_pass <- r1_low_nav && r1_high_nav && r1_low_ret && r1_high_ret
r2_pass <- r2_expl && r2_alias
cat(sprintf("  R1 nav_end identical: low=%s high=%s | total_ret match: low=%s high=%s -> %s\n",
            r1_low_nav, r1_high_nav, r1_low_ret, r1_high_ret, ifelse(r1_pass, "PASS", "FAIL")))
cat(sprintf("  R2 explicit/alias identical to default: %s/%s -> %s\n",
            r2_expl, r2_alias, ifelse(r2_pass, "PASS", "FAIL")))

cat("\n==== [D1/D2] v2.4_delta synthetic arithmetic ====\n")
v24_low  <- run_case(f_low,  5, "SYN_low_v24",  cost_model_version = "v2.4_delta")
v24_mid  <- run_case(f_mid,  4, "SYN_mid_v24",  cost_model_version = "v2.4_delta")
v24_high <- run_case(f_high, 5, "SYN_high_v24", cost_model_version = "v2.4_delta")

n_reb <- reg_low$n_rebal   # 17
exp_v23      <- (1 - cc)^n_reb - 1
exp_v24_low  <- -cc
exp_v24_mid  <- (1 - cc)^n_reb - 1
exp_v24_high <- (1 - cc) * (1 - 2 * cc)^(n_reb - 1) - 1
TOL <- 5e-4

chk <- function(meas, expd, tol = TOL) abs(meas - expd) <= tol
d_rows <- list(
  list(case = "SYN_low  (0%)",   model = "v2.4_delta", measured = v24_low$total_ret,
       expected = exp_v24_low,  tol = TOL, pass = chk(v24_low$total_ret,  exp_v24_low)),
  list(case = "SYN_mid  (50%)",  model = "v2.4_delta", measured = v24_mid$total_ret,
       expected = exp_v24_mid,  tol = TOL, pass = chk(v24_mid$total_ret,  exp_v24_mid)),
  list(case = "SYN_high (100%)", model = "v2.4_delta", measured = v24_high$total_ret,
       expected = exp_v24_high, tol = TOL, pass = chk(v24_high$total_ret, exp_v24_high)),
  list(case = "SYN_mid  (50%)",  model = "v2.3_flat",  measured = reg_mid$total_ret,
       expected = exp_v23,      tol = TOL, pass = chk(reg_mid$total_ret,  exp_v23))
)
for (r in d_rows)
  cat(sprintf("  %-16s %-10s measured=%+.6f expected=%+.6f |diff|=%.2e %s\n",
              r$case, r$model, r$measured, r$expected, abs(r$measured - r$expected),
              ifelse(r$pass, "PASS", "FAIL")))

mono_v24  <- (v24_low$total_ret > v24_mid$total_ret) && (v24_mid$total_ret > v24_high$total_ret)
flat_v23  <- (abs(reg_low$total_ret - reg_mid$total_ret) < 1e-5) &&
             (abs(reg_mid$total_ret - reg_high$total_ret) < 1e-5)
cat(sprintf("  monotonicity v2.4 (low > mid > high cost): %s | v2.3 flat-insensitive: %s\n",
            ifelse(mono_v24, "PASS", "FAIL"), ifelse(flat_v23, "PASS", "FAIL")))
d_pass <- all(sapply(d_rows, `[[`, "pass")) && mono_v24 && flat_v23

cat("\n==== [J1/J2] judge_oos_helper.R ====\n")
source(file.path(ROOT, "02_Infrastructure/validation/judge_oos_helper.R"))
wdt <- data.table(Ticker = tk_all[1:5], Weight = rep(0.2, 5))
jsim_def <- .joh_run_static_weight_sim(copy(SYN_RAW), copy(wdt),
                                       start_date = as.Date("2020-01-01"),
                                       end_date   = as.Date("2021-06-30"),
                                       commission = cc, initial_cap = 1e8)
jsim_v24 <- .joh_run_static_weight_sim(copy(SYN_RAW), copy(wdt),
                                       start_date = as.Date("2020-01-01"),
                                       end_date   = as.Date("2021-06-30"),
                                       commission = cc, initial_cap = 1e8,
                                       cost_model_version = "v2.4_delta")
j_def_nav <- tail(jsim_def$daily_nav$NAV, 1); j_def_ret <- j_def_nav / 1e8 - 1
j_v24_nav <- tail(jsim_v24$daily_nav$NAV, 1); j_v24_ret <- j_v24_nav / 1e8 - 1

jb <- jsonlite::fromJSON(JUDGE_BASELINE)
j1_pass <- isTRUE(all.equal(j_def_nav, jb$nav_end, tolerance = 1e-9)) # 패치 전 실측과 동일 (digits=12 직렬화)
exp_j_v23 <- (1 - cc) * (1 - 2 * cc)^(jsim_def$n_rebalances - 1) - 1
exp_j_v24 <- -cc
j2_pass <- chk(j_v24_ret, exp_j_v24, tol = 1e-4)
cat(sprintf("  J1 default vs prepatch baseline: nav %.4f vs %.4f -> %s\n",
            j_def_nav, jb$nav_end, ifelse(j1_pass, "PASS (bit-identical)", "FAIL")))
cat(sprintf("  J1 (참고) v2.3 closed-form (1-c)(1-2c)^16-1=%.6f vs measured %.6f (floor 없는 분수주식 — diff=%.2e)\n",
            exp_j_v23, j_def_ret, abs(exp_j_v23 - j_def_ret)))
cat(sprintf("  J2 v2.4 static-w: measured=%+.6f expected~%+.6f |diff|=%.2e %s\n",
            j_v24_ret, exp_j_v24, abs(j_v24_ret - exp_j_v24), ifelse(j2_pass, "PASS", "FAIL")))

# ════════════════ JSON 산출 ════════════════
res <- list(
  meta = list(
    date = as.character(Sys.Date()),
    metric_type = "diagnostic",
    purpose = "cost model v2.4 (delta-based) patch verification: default no-op regression + delta arithmetic",
    patched_files = c("02_Infrastructure/backtest_harness.R (run_monthly_simulation)",
                      "02_Infrastructure/validation/judge_oos_helper.R (.joh_run_static_weight_sim)"),
    default_model = "v2.3_flat (NOT flipped — flip = Q-Lead after book remeasure)",
    commission = cc, n_rebal = n_reb
  ),
  harness_regression = list(
    baseline_file = "b0_ab_reverted.json",
    baseline = list(syn_low = b0$syn_low[c("nav_end", "total_ret")],
                    syn_high = b0$syn_high[c("nav_end", "total_ret")]),
    patched_default = list(syn_low = reg_low[c("nav_end", "total_ret")],
                           syn_high = reg_high[c("nav_end", "total_ret")]),
    nav_end_identical = list(syn_low = r1_low_nav, syn_high = r1_high_nav),
    total_ret_match   = list(syn_low = r1_low_ret, syn_high = r1_high_ret),
    explicit_flat_identical_to_default = r2_expl,
    alias_v23kr_identical_to_default   = r2_alias,
    verdict = ifelse(r1_pass && r2_pass, "PASS", "FAIL")
  ),
  v24_delta_verification = list(
    closed_form = list(
      v23_flat_any   = "(1-c)^17 - 1",
      v24_syn_low    = "-c (initial full-buy leg only)",
      v24_syn_mid    = "(1-c)^17 - 1 (initial c, then 16 x sum|dW|=1.0 x c)",
      v24_syn_high   = "(1-c)*(1-2c)^16 - 1 (initial c, then 16 x (sell c + buy c))"
    ),
    table = d_rows,
    v23_flat_all_three = list(syn_low = reg_low$total_ret, syn_mid = reg_mid$total_ret,
                              syn_high = reg_high$total_ret, insensitive = flat_v23),
    v24_monotonic_in_turnover = mono_v24,
    tolerance_abs = TOL,
    tolerance_rationale = "integer-share floor quantization + fee-induced re-target drift",
    verdict = ifelse(d_pass, "PASS", "FAIL")
  ),
  judge_oos_helper = list(
    baseline_file = "v24_judge_prepatch_baseline.json (captured pre-patch this session)",
    prepatch = list(nav_end = jb$nav_end, total_ret = jb$total_ret),
    patched_default = list(nav_end = j_def_nav, total_ret = j_def_ret),
    default_identical = j1_pass,
    v24_delta = list(nav_end = j_v24_nav, total_ret = j_v24_ret,
                     expected = exp_j_v24, tol = 1e-4, pass = j2_pass),
    note = "v2.3 helper = full-sell c + full-buy c per rebal (~30bps flat); v2.4 static-w cost = initial buy leg only",
    verdict = ifelse(j1_pass && j2_pass, "PASS", "FAIL")
  ),
  overall = ifelse(r1_pass && r2_pass && d_pass && j1_pass && j2_pass, "PASS", "FAIL")
)
jsonlite::write_json(res, OUT_JSON, auto_unbox = TRUE, digits = 12, pretty = TRUE)
cat(sprintf("\n[OVERALL] %s -> %s\n", res$overall, OUT_JSON))
