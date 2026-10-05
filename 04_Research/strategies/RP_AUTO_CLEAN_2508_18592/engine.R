# =============================================================================
# RP_AUTO_CLEAN_2508_18592 — engine.R   (re-implementation, r2)
#
# Paper : Cai, He, Zhang (2025) "Combined machine learning for stock selection
#         strategy based on dynamic weighting methods"
#         https://arxiv.org/abs/2508.18592        (read: arxiv.org/html/2508.18592v1)
#
# Mechanism (paper section 2.1 / 2.3 / Algorithm 1 / Algorithm 2):
#   section 2.1  preprocess  : industry-median -> pool-median imputation,
#                              3 x MAD outlier rule, Z-score, then regression
#                              residual centering on industry dummies + market cap
#                              (industry centering only for market-cap factors).
#   section 2.3  EWM         : eq (1) min-max over the pool s in [t-12, t-1],
#                              eq (2)-(3) entropy over that same pool with
#                              normaliser ln(12 N), eq (4) w = (1-e)/sum(1-e),
#                              eq (5) F_it = sum_j w_ijt z_ijt.
#                              LASSO screens the second-level indicators first
#                              (section 2.3 "Factor Selection and Synthesis").
#   Algorithm 1  models      : Ridge / MLP / Random Forest, retrained every month
#                              on tau = t-12 .. t-1, test X_t, advance 1 month.
#   Algorithm 2  combination : IC_i,tau = Spearman(r_hat_i,tau, realised),
#                              mu_IC = mean over tau in [t-L, t-1], L = 20 months,
#                              w_i = max(mu_IC_i, 0) / S ; S = 0 -> w = 0.
#
# Output : FACTORS(Date, Ticker, Score) — Score = combined predicted return.
#          The paper's only statement about portfolio formation is Algorithm 1
#          line 7 "Form portfolio based on predicted returns", so the portfolio
#          layer is left to the runner via FIDELITY.json::portfolio_spec.
#
# fidelity = adapted.  EVERY deviation is declared in FIDELITY.json::changed.
#          This header is NOT the declaration channel.
#
# -----------------------------------------------------------------------------
# Window endpoints — the one thing the previous revision got wrong
# -----------------------------------------------------------------------------
#   eq (1) subscripts are  s in [t-12, t-1],  b in [1, N] : the min/max pool
#   EXCLUDES the decision month t.  Only the numerator x_ijt is the current
#   month.  Hence z_ijt is NOT confined to [0,1] — it is above 1 when the stock
#   broke out above the trailing 12-month cross-sectional range, below 0 when it
#   broke below — and the paper does not clip it.  The entropy pool of eq (2)-(3)
#   is that same t-excluding window, so the weights w_ijt never see month t.
#   Here: window = month slots [k-12, k-1]; decision-month value = slot k; one
#   (lo, hi) pair per (indicator, decision month) shared by the pool and by the
#   decision-month value.  No clip anywhere.
#
# -----------------------------------------------------------------------------
# PIT (C1~C15) — guaranteed by STRUCTURE, not by a detector pass
# -----------------------------------------------------------------------------
#  * Every rolling reducer here is trailing-only: stats::filter(sides = 1) and
#    frollmean/frollsum default to trailing, data.table::shift() is used with
#    positive n only.  There is no shift(-k), no forward/rolling join, no
#    negative index, and no full-sample mean/sd/cov/min/max on any panel.
#  * Month-slot algebra: the decision date for slot k is me[k] (last trading day
#    of that month).  The monthly loop reads slots < k (training, EWM window, IC)
#    and slot k (features) only; it never names an index > k.
#  * Labels: y(k) = compounded return over (me[k], me[k+1]], carrying an explicit
#    realisation date asof = me[k+1].  Every consumer is hard-asserted on asof.
#  * IC(k) is appended only at step k+1, carrying asof = me[k+1]; the weighting
#    step asserts every consumed IC row has asof <= me[k].
#  * Factor DB: load_month_factors() only (C15), Z_Score_Aligned only (C13), and
#    a panel is consumed only if its reported as-of month equals the requested
#    month (the connector otherwise substitutes the closest earlier file).
#  * Liquidity: adv20 = shift(frollmean(Close*Vol, 20), 1) by ticker — t-1 (C10).
#  * Universe / status flags are read from the signal-date row only (C6); the
#    K200/KQ150 membership flag is time-varying in RAWDATA.
#  * The feature set (which first-level groups, which indicators) is decided
#    per decision month from the slots [k-12, k] alone — never from the whole
#    panel, and never from any evaluation-window outcome (C1/C14).
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(glmnet)
  library(nnet)
  library(ranger)
})

# =============================================================================
# 0. constants
# =============================================================================
# ---- stated by the paper ----------------------------------------------------
PAP_EWM_M   <- 12L    # eq (1)-(3): pool s in [t-12, t-1]
PAP_TRAIN_M <- 12L    # Algorithm 1: "Training window size: 12 months"
PAP_IC_L    <- 20L    # Algorithm 2: L = 20; section 3.2.1 "past 20 trading months"
PAP_HL_D    <- 60L    # Table 1: "half-life of 60 trading days"
PAP_MAD_K   <- 3      # section 2.1: "three times Median Absolute Deviation"
PAP_ROE_D   <- c(Roe20 = 20L, Roe60 = 60L, Roe120 = 120L)   # Table 1 names
PAP_VOL_D   <- 250L   # Table 1 Std_g / Dastd: "past 250 trading days"
PAP_IR_D    <- 20L    # Table 1 IR_industry_*: "time window of 20 trading days"
PAP_MON_D   <- 20L    # paper's own month length (Roe20 = "one-month")
PAP_QTR_D   <- 60L    # paper's own quarter length (Roe60 = "three-month")
PAP_YR_D    <- 250L   # paper's own year length (Std_g "past 250 trading days")

# ---- not stated by the paper (all declared in FIDELITY.json::changed) -------
AX_LIQ_MIN   <- 2e8                   # harness axis: adv20 floor in KRW, at t-1
AX_ADV_WIN   <- 20L
AX_FEAT_FROM <- as.Date("1996-01-01") # burn-in start; scoring starts far later
AX_NEWLIST_D <- 20L                   # paper's "newly listed within the past month"
AX_MIN_WCOV  <- 0.5                   # min observed share of a weighted daily window
AX_MIN_TRAIN <- 100L                  # min training rows for a monthly fit
AX_MIN_TEST  <- 20L                   # min cross-section to score / to form an IC
AX_RF_TREE   <- 500L
AX_MLP_H     <- 8L
AX_MLP_DEC   <- 1e-3
AX_MLP_IT    <- 300L
AX_CV_FOLD   <- 5L
AX_SEED      <- 20250826L

# =============================================================================
# 0b. paper Table 1 — 8 first-level factors and their second-level indicators
#     Names are the PAPER's names so every column is traceable to Table 1.
#     Table 1 lists 50 second-level indicators; 31 are built here.  What is NOT
#     available and deliberately NOT proxied is declared in FIDELITY.json::changed
#     (order-size money flows Sm/Md/Lg/Elg, the IR_industry_pb / IR_industry_ps
#     daily-multiple IRs, the 5-year CGR_* / IR_* leverage and growth variants,
#     Basic_eps_yoy, Rtop, Epstop, Pe).
# =============================================================================
GROUPS <- list(
  size       = c("Total_mv", "Total_mv_log", "Total_mv_3", "IR_industry_total_mv"),
  reverse    = c("Roe20", "Roe60", "Roe120", "Pct_chg", "Turnover_rate",
                 "Amplitude", "Vol"),
  volatility = c("Beta", "Std_e", "Std_g", "Dastd"),
  liquidity  = c("Turnover_month", "Turnover_quater", "Turnover_year",
                 "IR_industry_turnover_rate"),
  earnings   = c("Etop", "Cetop"),
  growth     = c("Netprofit_yoy", "Ocf_yoy", "Or_yoy", "Roe_yoy", "IR_eps"),
  valuation  = c("Pb", "Ps"),
  leverage   = c("Mlev", "Dtoa", "Blev")
)
# paper indicator -> KR Factor DB registry factor (the only PIT-safe fundamental
# path).  Each registry factor is used EXACTLY ONCE: no two paper slots share a
# registry factor, so no indicator can be counted twice in an entropy weight.
FDB_MAP <- c(
  Etop          = "V02_EP",                # NetIncome / MarketCap   (paper: net profit / total mv)
  Cetop         = "V03_CFP",                # OperatingCF / MarketCap (paper: operating cash flow / total mv)
  Netprofit_yoy = "GR02_Earnings_Growth",   # YoY net income growth
  Ocf_yoy       = "GR06_OCF_Growth",        # YoY operating cash flow growth
  Or_yoy        = "GR01_Revenue_Growth",    # YoY revenue growth
  Roe_yoy       = "GR05_ROE_Growth",        # 5Y ROE growth  (paper: YoY — declared)
  IR_eps        = "Q07_Earnings_Stability", # 5Y earnings stability (paper: 5Y EPS IR)
  Pb            = "V01_BM",                 # TotalEquity / MarketCap = 1 / Pb
  Ps            = "V08_PSR",                # MarketCap / Revenue     (paper: Ps)
  Mlev          = "R17_Market_Leverage",    # -(TotalDebt / MarketCap)
  Dtoa          = "Q16_Debt_to_Assets",     # TotalDebt / TotalAssets (paper: Dtoa)
  Blev          = "Q13_Fin_Leverage"        # TotalAssets / TotalEquity
)
# section 2.1: "For factors inherently related to market capitalization (e.g.,
# the market capitalization factor itself), only industry centering is performed."
SIZE_IDX <- GROUPS$size

GMAP <- rbindlist(lapply(names(GROUPS),
                         function(g) data.table(grp = g, Factor_Name = GROUPS[[g]])))
if (anyDuplicated(GMAP$Factor_Name))
  stop("[engine] one indicator name is assigned to two first-level factors")
if (anyDuplicated(FDB_MAP))
  stop("[engine] one registry factor is mapped to two paper indicators")
RAW_IDX <- setdiff(GMAP$Factor_Name, names(FDB_MAP))
# the four Table 1 Reverse indicators whose value needs a cross-sectional
# comparison ("less than the market average"), built at the month-end pool
COND_IDX <- c("Pct_chg", "Turnover_rate", "Amplitude", "Vol")
GRP_NM  <- names(GROUPS)
MODELS  <- c("ridge", "mlp", "rf")

# =============================================================================
# 0c. factor DB connector (C15 single gate)
# =============================================================================
.ENG_ENV <- environment()
.ENG_ROOT <- local({
  ok <- function(p) nzchar(p) && dir.exists(p) &&
    file.exists(file.path(p, "02_Infrastructure", "config.R"))
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
    if (ok(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (ok(cur)) return(cur)
    up <- dirname(cur)
    if (identical(up, cur)) break
    cur <- up
  }
  stop("[engine] project root not found (need 02_Infrastructure/config.R)")
})
if (!exists("FUNC_PATH", inherits = TRUE))
  FUNC_PATH <- file.path(.ENG_ROOT, "02_Infrastructure")
invisible(capture.output(suppressWarnings(suppressMessages(
  sys.source(file.path(.ENG_ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"),
             envir = .ENG_ENV)
))))
if (!is.function(get0("load_month_factors", envir = .ENG_ENV, inherits = TRUE)))
  stop("[engine] load_month_factors() unavailable — C15 gate cannot be honoured")

# =============================================================================
# 0d. helpers
# =============================================================================
# status flags arrive as logical / numeric / character depending on vintage;
# anything not affirmatively true counts as not flagged (declared guard).
.truthy <- function(x) {
  if (is.logical(x)) return(!is.na(x) & x)
  if (is.numeric(x))  return(!is.na(x) & x != 0)
  u <- toupper(trimws(as.character(x)))
  !is.na(u) & u %in% c("TRUE", "T", "Y", "YES", "1")
}
# exponential ("index-weighted") trailing weights: w_i = 0.5^(i / half-life),
# i = 0 at the signal day.  Table 1: half-life 60 trading days.
.hlw <- function(n) 0.5 ^ ((0:(n - 1L)) / PAP_HL_D)
# trailing weighted sum  y_t = sum_i f_{i+1} x_{t-i}.  stats::filter(sides = 1)
# is trailing by construction — there is no way for it to read x_{t+j}.
.fsum <- function(x, f) {
  n <- length(x)
  if (n < length(f)) return(rep(NA_real_, n))
  as.numeric(stats::filter(x, f, method = "convolution", sides = 1))
}
# trailing mean / sum over a fixed number of the ticker's own trading rows
.rmean <- function(x, n) if (length(x) < n) rep(NA_real_, length(x)) else
  frollmean(x, n, na.rm = TRUE, hasNA = TRUE)
.rsum  <- function(x, n) if (length(x) < n) rep(NA_real_, length(x)) else
  frollsum(x, n)

# =============================================================================
# 1. daily panel, monthly grid, point-in-time eligibility, labels
# =============================================================================
stopifnot(is.data.table(RAWDATA), is.data.table(BM_DT))
need <- c("Date", "Ticker", "Close", "Vol", "Ret", "Size", "K200", "KQ150")
miss <- setdiff(need, names(RAWDATA))
if (length(miss)) stop(sprintf("[engine] RAWDATA lacks %s", paste(miss, collapse = ", ")))

opt_cols  <- intersect(c("High", "Low", "Sector", "BM_Ret"), names(RAWDATA))
flag_cols <- intersect(c("AdminStock", "TradingHalt", "UnfaithfulDisc"), names(RAWDATA))
memtk <- unique(RAWDATA[(K200 %in% TRUE) | (KQ150 %in% TRUE), Ticker])
if (!length(memtk)) stop("[engine] no K200/KQ150 member ticker in RAWDATA")
RD <- RAWDATA[Ticker %in% memtk, c(need, opt_cols, flag_cols), with = FALSE]
setorder(RD, Ticker, Date)

# industry classification (paper: Shenwan standard; here the RAWDATA Sector
# column).  Absent / NA sector -> "UNKNOWN" bucket; the paper's own fallback
# ("when the industry median is unavailable, the overall median ... is applied")
# is what then fires for imputation.
if (!"Sector" %in% names(RD)) RD[, Sector := NA_character_]
RD[, Sector := as.character(Sector)]
RD[is.na(Sector) | !nzchar(Sector), Sector := "UNKNOWN"]

# benchmark daily return for Beta / Std_e / Dastd (paper: against CSI 300)
if (!"BM_Ret" %in% names(RD)) {
  bm <- as.data.table(BM_DT)
  bcol <- intersect(c("BM_Ret", "Ret", "Return"), names(bm))
  if (length(bcol)) {
    b <- bm[, .(Date, BM_Ret = as.numeric(get(bcol[1])))]
  } else if ("Close" %in% names(bm)) {
    setorder(bm, Date)
    b <- bm[, .(Date, BM_Ret = as.numeric(Close) / shift(as.numeric(Close)) - 1)]
  } else stop("[engine] BM_DT has no usable benchmark return / close column")
  RD <- b[RD, on = "Date"]
}
RD[, BM_Ret := as.numeric(BM_Ret)]
for (cc in c("High", "Low")) if (!cc %in% names(RD)) RD[, (cc) := NA_real_]
RD[, `:=`(Close = as.numeric(Close), Vol = as.numeric(Vol), Ret = as.numeric(Ret),
          Size = as.numeric(Size), High = as.numeric(High), Low = as.numeric(Low))]
setorder(RD, Ticker, Date)

# ---- monthly grid ----------------------------------------------------------
all_dates <- sort(unique(RAWDATA$Date))
mkey <- as.integer(format(all_dates, "%Y")) * 12L + as.integer(format(all_dates, "%m"))
me <- all_dates[!duplicated(mkey, fromLast = TRUE)]        # last trading day / month
me <- me[me >= AX_FEAT_FROM]
n_me <- length(me)
if (n_me < PAP_EWM_M + PAP_TRAIN_M + 4L) stop("[engine] monthly grid too short")

# liquidity at t-1 (C10) + the paper's "newly listed within the past month"
RD[, tval := Close * Vol]
RD[, adv_lag := shift(.rmean(tval, AX_ADV_WIN), 1L), by = Ticker]
RD[, n_prior := shift(seq_len(.N), 1L), by = Ticker]       # rows strictly before today
RD[, tval := NULL]

# holding-period index: hp = i  <=>  me[i] < Date <= me[i+1]
RD[, hp := findInterval(as.numeric(Date), as.numeric(me), left.open = TRUE)]

# label realised at me[k+1] — the only forward return built anywhere, and it is
# tagged with its realisation date so every consumer can be gated on it.
LAB <- RD[hp >= 1L & hp < n_me & is.finite(Ret),
          .(y = prod(1 + Ret) - 1), by = .(mi = hp, Ticker)]
LAB[, asof := me[mi + 1L]]
setkey(LAB, mi)

# =============================================================================
# 2a. second-level indicators built from the paper's OWN definitions
#     (Table 1 size / reverse / volatility / liquidity groups).
#     Every window below is trailing and ends at the signal day.
# =============================================================================
# -- Reverse: Roe20 / Roe60 / Roe120 = exponentially ("index") weighted
#    cumulative daily return, half-life 60 trading days (Table 1).
RD[, r0 := fifelse(is.finite(Ret), Ret, 0)]
for (nm in names(PAP_ROE_D))
  RD[, (nm) := .fsum(r0, .hlw(PAP_ROE_D[[nm]])), by = Ticker]

# -- Reverse conditional block: Table 1 "if the stock <x> is less than the market
#    average, multiply the return by -1".  <x> = return / turnover rate /
#    amplitude / volume.  The paper states no window; its own month is 20 trading
#    days (Roe20 = "one-month"), so the past 20 trading days is used throughout.
RD[, lr := fifelse(is.finite(Ret), log1p(pmax(Ret, -0.99)), 0)]
RD[, ret_m := expm1(.rsum(lr, PAP_MON_D)), by = Ticker]
RD[, turn := fifelse(is.finite(Size) & Size > 0 & is.finite(Close) & Close > 0 &
                       is.finite(Vol), Vol * Close / Size, NA_real_)]
RD[, pc := shift(Close), by = Ticker]
RD[, ampd := fifelse(is.finite(High) & is.finite(Low) & is.finite(pc) & pc > 0,
                     (High - Low) / pc, NA_real_)]
RD[, `:=`(turn_m = .rmean(turn, PAP_MON_D),
          amp_m  = .rmean(ampd, PAP_MON_D),
          vol_m  = .rmean(fifelse(is.finite(Vol), Vol, NA_real_), PAP_MON_D)),
   by = Ticker]

# -- Volatility: Beta / Std_e from a weighted time-series regression of the
#    stock's index-weighted daily returns on the benchmark; Std_g / Dastd are
#    weighted sds, window 250 trading days (Table 1).  Weighted moments are
#    exact trailing sums, so nothing full-sample enters.
W250 <- .hlw(PAP_VOL_D)
RD[, av := as.numeric(is.finite(Ret) & is.finite(BM_Ret))]
RD[, `:=`(ry = fifelse(av > 0, Ret, 0), rx = fifelse(av > 0, BM_Ret, 0))]
RD[, `:=`(Sw  = .fsum(av, W250),
          Sy  = .fsum(av * ry, W250),
          Sx  = .fsum(av * rx, W250),
          Sxx = .fsum(av * rx * rx, W250),
          Sxy = .fsum(av * rx * ry, W250),
          Syy = .fsum(av * ry * ry, W250),
          Se  = .fsum(av * (ry - rx), W250),
          See = .fsum(av * (ry - rx) ^ 2, W250)), by = Ticker]
.wmin <- AX_MIN_WCOV * sum(W250)
RD[, ok_w := is.finite(Sw) & Sw >= .wmin]
RD[, `:=`(vxx = Sxx / Sw - (Sx / Sw) ^ 2,
          vyy = Syy / Sw - (Sy / Sw) ^ 2,
          vxy = Sxy / Sw - (Sx / Sw) * (Sy / Sw),
          vee = See / Sw - (Se / Sw) ^ 2)]
RD[, Beta  := fifelse(ok_w & is.finite(vxx) & vxx > 0, vxy / vxx, NA_real_)]
RD[, Std_g := fifelse(ok_w & is.finite(vyy) & vyy >= 0, sqrt(pmax(vyy, 0)), NA_real_)]
RD[, Dastd := fifelse(ok_w & is.finite(vee) & vee >= 0, sqrt(pmax(vee, 0)), NA_real_)]
RD[, Std_e := fifelse(is.finite(Beta) & is.finite(vyy),
                      sqrt(pmax(vyy - Beta * vxy, 0)), NA_real_)]
RD[, c("av", "ry", "rx", "Sw", "Sy", "Sx", "Sxx", "Sxy", "Syy", "Se", "See",
       "vxx", "vyy", "vxy", "vee", "ok_w", "r0", "lr", "pc", "ampd") := NULL]
gc(verbose = FALSE)

# -- Size: total market value and its log / cube (Table 1).
RD[, Total_mv     := fifelse(is.finite(Size) & Size > 0, Size, NA_real_)]
RD[, Total_mv_log := fifelse(is.finite(Total_mv), log(Total_mv), NA_real_)]
RD[, Total_mv_3   := fifelse(is.finite(Total_mv), Total_mv ^ 3, NA_real_)]

# -- Liquidity: average turnover rate over month / quarter / year (Table 1).
RD[, `:=`(Turnover_month  = .rmean(turn, PAP_MON_D),
          Turnover_quater = .rmean(turn, PAP_QTR_D),
          Turnover_year   = .rmean(turn, PAP_YR_D)), by = Ticker]

# -- "industry excess IR, with a time window of 20 trading days" (Table 1):
#    IR = mean / sd of the stock's daily industry-demeaned series over 20 days.
RD[, ex_mv := Total_mv_log - mean(Total_mv_log, na.rm = TRUE), by = .(Date, Sector)]
RD[, ex_to := turn - mean(turn, na.rm = TRUE),                 by = .(Date, Sector)]
RD[, `:=`(m1 = .rmean(ex_mv, PAP_IR_D), m2 = .rmean(ex_mv ^ 2, PAP_IR_D),
          t1 = .rmean(ex_to, PAP_IR_D), t2 = .rmean(ex_to ^ 2, PAP_IR_D)), by = Ticker]
RD[, IR_industry_total_mv := fifelse(is.finite(m2 - m1 ^ 2) & (m2 - m1 ^ 2) > 0,
                                     m1 / sqrt(m2 - m1 ^ 2), NA_real_)]
RD[, IR_industry_turnover_rate := fifelse(is.finite(t2 - t1 ^ 2) & (t2 - t1 ^ 2) > 0,
                                          t1 / sqrt(t2 - t1 ^ 2), NA_real_)]
RD[, c("ex_mv", "ex_to", "m1", "m2", "t1", "t2", "turn") := NULL]
gc(verbose = FALSE)

# ---- month-end snapshot + eligibility --------------------------------------
SIG <- RD[Date %in% me]
SIG[, mi := match(Date, me)]
bad_v <- rep(FALSE, nrow(SIG))
for (fc in flag_cols) bad_v <- bad_v | .truthy(SIG[[fc]])
SIG[, bad := bad_v]
POOL <- SIG[((K200 %in% TRUE) | (KQ150 %in% TRUE)) &      # harness axis: universe
              !bad &                                       # paper: ST / suspended
              is.finite(n_prior) & n_prior >= AX_NEWLIST_D & # paper: newly listed
              is.finite(adv_lag) & adv_lag >= AX_LIQ_MIN &  # harness axis, t-1
              is.finite(Total_mv_log),                      # mcap regressor needed
            .(mi, Ticker, Sector, m = Total_mv_log)]
setkey(POOL, mi, Ticker)
if (!nrow(POOL)) stop("[engine] eligibility left an empty pool")

# restrict the month-end snapshot to the pool (1:1 join on the pool key)
setkey(SIG, mi, Ticker)
SIGP <- SIG[POOL[, .(mi, Ticker)], nomatch = NULL]
rm(SIG); gc(verbose = FALSE)

# ---- Table 1 Reverse conditional block -------------------------------------
# "If the stock <x> is less than the market average, multiply the return by -1",
# for <x> = return / turnover rate / amplitude / volume.  The comparison is
# cross-sectional within the decision month's pool ("the market average"); the
# VALUE of all four indicators is the stock's own return, sign-conditioned.
# Built here, not as a daily column, because `Vol` is also a RAWDATA column name
# and melting by name would otherwise silently ship raw share volume instead.
CB <- SIGP[, .(mi, Ticker, ret_m, turn_m, amp_m, vol_m)]
CB[, `:=`(a_r = mean(ret_m,  na.rm = TRUE), a_t = mean(turn_m, na.rm = TRUE),
          a_a = mean(amp_m,  na.rm = TRUE), a_v = mean(vol_m,  na.rm = TRUE)), by = mi]
CB[, `:=`(
  Pct_chg       = fifelse(is.finite(ret_m) & is.finite(a_r),
                          ret_m * fifelse(ret_m  < a_r, -1, 1), NA_real_),
  Turnover_rate = fifelse(is.finite(ret_m) & is.finite(turn_m) & is.finite(a_t),
                          ret_m * fifelse(turn_m < a_t, -1, 1), NA_real_),
  Amplitude     = fifelse(is.finite(ret_m) & is.finite(amp_m) & is.finite(a_a),
                          ret_m * fifelse(amp_m  < a_a, -1, 1), NA_real_),
  Vol           = fifelse(is.finite(ret_m) & is.finite(vol_m) & is.finite(a_v),
                          ret_m * fifelse(vol_m  < a_v, -1, 1), NA_real_))]

# ---- long-format panel of the self-built indicators ------------------------
DIRECT_IDX <- setdiff(RAW_IDX, COND_IDX)
rawi <- intersect(DIRECT_IDX, names(SIGP))
if (length(rawi) < length(DIRECT_IDX))
  cat(sprintf("[engine] self-built indicator column(s) absent: %s\n",
              paste(setdiff(DIRECT_IDX, rawi), collapse = ", ")))
if (!length(rawi)) stop("[engine] no self-built indicator materialised")
RX <- rbindlist(list(
  melt(SIGP[, c("mi", "Ticker", rawi), with = FALSE], id.vars = c("mi", "Ticker"),
       variable.name = "Factor_Name", value.name = "x", variable.factor = FALSE),
  melt(CB[, c("mi", "Ticker", COND_IDX), with = FALSE], id.vars = c("mi", "Ticker"),
       variable.name = "Factor_Name", value.name = "x", variable.factor = FALSE)
), use.names = TRUE)
RX <- RX[is.finite(x)]
rm(SIGP, CB, RD); gc(verbose = FALSE)
cat(sprintf("[engine] monthly grid %s ~ %s (%d months) | pool stock-months %d | self-built rows %d\n",
            format(me[1]), format(me[n_me]), n_me, nrow(POOL), nrow(RX)))

# =============================================================================
# 2b. fundamental indicators — Factor DB only (C15 gate, C13 Z_Score_Aligned).
#     dedup = TRUE so the registry's own alias/redundancy declarations collapse
#     before anything reaches an entropy weight.
# =============================================================================
FDB_REQ <- unname(FDB_MAP)
INV_MAP <- setNames(names(FDB_MAP), FDB_MAP)
FL <- vector("list", n_me); n_skip <- 0L
for (k in seq_len(n_me)) {
  ek <- POOL[.(k), Ticker, nomatch = NULL]
  if (!length(ek)) next
  res <- NULL
  invisible(capture.output(suppressWarnings(suppressMessages(
    res <- tryCatch(load_month_factors(me[k], factor_names = FDB_REQ, dedup = TRUE),
                    error = function(e) NULL)))))
  if (is.null(res) || !nrow(res)) { n_skip <- n_skip + 1L; next }
  a <- attr(res, "factor_db_asof_date")
  # reject a substituted / stale panel: the connector falls back to the closest
  # EARLIER month file when the requested month is absent.  Consuming that would
  # silently feed a previous month's cross-section into this month's decision.
  if (length(a) != 1L || is.na(a)) { n_skip <- n_skip + 1L; next }
  a <- as.Date(a)
  if (a > me[k] || format(a, "%Y%m") != format(me[k], "%Y%m")) {
    n_skip <- n_skip + 1L; next
  }
  d <- as.data.table(res)[Ticker %in% ek & is.finite(Z_Score_Aligned),
                          .(Ticker, Factor_Name = INV_MAP[as.character(Factor_Name)],
                            x = as.numeric(Z_Score_Aligned))]
  d <- d[!is.na(Factor_Name)]
  if (!nrow(d)) { n_skip <- n_skip + 1L; next }
  d[, mi := k]
  FL[[k]] <- d[, .(mi, Ticker, Factor_Name, x)]
}
FX <- rbindlist(Filter(Negate(is.null), FL), use.names = TRUE)
rm(FL); gc(verbose = FALSE)
RAWX <- rbindlist(list(RX, FX), use.names = TRUE)
rm(RX, FX); gc(verbose = FALSE)
if (!nrow(RAWX)) stop("[engine] indicator panel empty")
cat(sprintf("[engine] indicator panel %d rows | %d of %d Table-1 indicators | %d FDB months skipped\n",
            nrow(RAWX), uniqueN(RAWX$Factor_Name), nrow(GMAP), n_skip))

# =============================================================================
# 3. section 2.1 preprocessing — all strictly within one month's cross-section
#    (a) missing -> industry median -> overall pool median  (stocks are NEVER
#        dropped for missingness; the paper imputes, it does not delete)
#    (b) 3 x MAD outlier rule
#    (c) Z-score
#    (d) residual centering on industry dummies + market capitalisation;
#        industry centering only for the market-cap factors
# =============================================================================
FMI  <- unique(RAWX[, .(mi, Factor_Name)])
GRID <- FMI[POOL[, .(mi, Ticker)], on = "mi", allow.cartesian = TRUE]
P <- RAWX[GRID, on = .(mi, Ticker, Factor_Name)]
rm(RAWX, GRID, FMI); gc(verbose = FALSE)
P <- POOL[P, on = .(mi, Ticker), nomatch = NULL]

# (a) imputation — paper section 2.1
P[, imed := stats::median(x, na.rm = TRUE), by = .(mi, Factor_Name, Sector)]
P[, pmed := stats::median(x, na.rm = TRUE), by = .(mi, Factor_Name)]
P[!is.finite(x), x := fifelse(is.finite(imed), imed, pmed)]
P[, c("imed", "pmed") := NULL]
P <- P[is.finite(x)]          # drops an INDICATOR-month with no observation at all

# (b) 3 x MAD.  Treatment (delete vs winsorise) is not specified by the paper;
#     winsorising to the boundary is used because the paper's own design never
#     deletes a stock.  MAD = 0 -> the rule would annihilate the whole
#     cross-section, so it is skipped there (declared numerical guard).
P[, med := stats::median(x), by = .(mi, Factor_Name)]
P[, madv := stats::median(abs(x - med)), by = .(mi, Factor_Name)]
P[is.finite(madv) & madv > 0,
  x := pmin(pmax(x, med - PAP_MAD_K * madv), med + PAP_MAD_K * madv)]
P[, c("med", "madv") := NULL]

# (c) Z-score
P[, `:=`(mu = mean(x), sg = stats::sd(x)), by = .(mi, Factor_Name)]
P <- P[is.finite(sg) & sg > 1e-12]
P[, x := (x - mu) / sg]
P[, c("mu", "sg") := NULL]

# (d) residual centering.  Frisch-Waugh: the OLS residual of x on
#     [industry dummies + m] equals the residual of the industry-demeaned x on
#     the industry-demeaned m.  Singleton industries therefore get residual 0 —
#     that is a property of the paper's own formula, not an added guard.
P[, yd := x - mean(x), by = .(mi, Factor_Name, Sector)]
P[, md := m - mean(m), by = .(mi, Factor_Name, Sector)]
P[, b := { s <- sum(md * md)
           if (is.finite(s) && s > 1e-12) sum(yd * md) / s else 0 },
  by = .(mi, Factor_Name)]
P[, x := fifelse(Factor_Name %chin% SIZE_IDX, yd, yd - b * md)]
P <- P[is.finite(x), .(mi, Ticker, Factor_Name, x)]
if (!nrow(P)) stop("[engine] preprocessing left an empty panel")

# ---- structural duplicate defence ------------------------------------------
# Two indicator columns that are numerically identical would each receive their
# own entropy weight, i.e. one signal counted twice (or, with opposite signs,
# cancelled).  FDB_MAP already uses every registry factor exactly once; this
# asserts it on the realised numbers rather than on the intent.
.WD <- dcast(P, mi + Ticker ~ Factor_Name, value.var = "x")
.cl <- setdiff(names(.WD), c("mi", "Ticker"))
.dup <- .cl[duplicated(as.list(.WD[, .cl, with = FALSE]))]
rm(.WD); gc(verbose = FALSE)
if (length(.dup)) {
  cat(sprintf("[engine] bit-identical indicator(s) dropped: %s\n",
              paste(.dup, collapse = ", ")))
  P <- P[!Factor_Name %chin% .dup]
}
setkey(P, mi)
cat(sprintf("[engine] preprocessed panel %d rows | %d indicators | months %d ~ %d\n",
            nrow(P), uniqueN(P$Factor_Name), min(P$mi), max(P$mi)))

# =============================================================================
# 4. EWM — eq (1)-(4) EXACTLY as printed.  Pool = month slots [k-12, k-1];
#    the decision month k contributes ONLY the numerator x_ijk.
#    One (lo, hi) per (indicator, k), shared by the pool and by month k, so
#    z_ijk is free to leave [0,1] (breakout above / below the trailing range).
#    Entropy identity used:  sum p ln p = S2/S1 - ln S1 with S1 = sum z,
#    S2 = sum z ln z over the SAME pool — an algebraic rearrangement of eq (2)
#    and eq (3), not an approximation.
# =============================================================================
EWL <- vector("list", n_me)
for (k in (PAP_EWM_M + 1L):n_me) {
  win <- P[.((k - PAP_EWM_M):(k - 1L)), nomatch = NULL]
  if (!nrow(win)) next
  cur <- P[.(k), nomatch = NULL]
  if (!nrow(cur)) next
  mm <- win[, .(lo = min(x), hi = max(x)), by = Factor_Name]
  mm[, r := hi - lo]
  mm <- mm[is.finite(r) & r > 1e-12]
  if (!nrow(mm)) next
  w2 <- mm[win, on = "Factor_Name", nomatch = NULL]
  w2[, z := (x - lo) / r]                                  # pool: z in [0,1]
  ag <- w2[, .(S1 = sum(z), S2 = sum(fifelse(z > 0, z * log(z), 0)), nn = .N),
           by = Factor_Name]                               # 0 * ln 0 := 0
  ag <- ag[nn > 1L & is.finite(S1) & S1 > 0]
  if (!nrow(ag)) next
  ag[, ent := -(S2 / S1 - log(S1)) / log(nn)]              # eq (3), ln(12 N) -> ln(nn)
  ag <- ag[is.finite(ent)]
  if (!nrow(ag)) next
  ag[, wraw := pmax(1 - ent, 0)]                           # eq (4) numerator
  c2 <- mm[cur, on = "Factor_Name", nomatch = NULL]
  c2[, zk := (x - lo) / r]                                 # eq (1), NOT clipped
  o <- ag[, .(Factor_Name, wraw)][c2, on = "Factor_Name", nomatch = NULL]
  o <- o[is.finite(zk) & is.finite(wraw)]
  if (nrow(o)) EWL[[k]] <- o[, .(mi = k, Ticker, Factor_Name, zk, wraw)]
}
EW <- rbindlist(Filter(Negate(is.null), EWL), use.names = TRUE)
rm(EWL); gc(verbose = FALSE)
if (!nrow(EW)) stop("[engine] EWM panel empty after the 12-month burn-in")
setkey(EW, mi)
cat(sprintf("[engine] EWM panel %d rows | slots %d ~ %d | z range [%.2f, %.2f]\n",
            nrow(EW), min(EW$mi), max(EW$mi), min(EW$zk), max(EW$zk)))

# =============================================================================
# 5. monthly loop — Algorithm 1 + Algorithm 2
#    step order inside decision month k (decision date me[k]):
#      (a) append IC(k-1): the label of slot k-1 became known at me[k], so the
#          IC log can only ever hold asof <= me[k]
#      (b) LASSO screen on the 12-month training panel of section-2.1 adjusted
#          values (section 2.3 selects BEFORE it synthesises)
#      (c) eq (4)-(5) aggregate the survivors into the first-level factors
#      (d) Ridge / MLP / RF on slots [k-12, k-1], predict slot k
#      (e) Algorithm 2 weights from the trailing L = 20 IC window, combine, emit
# =============================================================================
mi_lo  <- min(EW$mi)
k_from <- mi_lo + PAP_TRAIN_M
if (k_from > n_me) stop("[engine] burn-in exceeds the monthly grid")
OUT <- vector("list", n_me)
IC_ROWS <- vector("list", 0L)
PREV <- NULL; PREV_MI <- NA_integer_
n_fit <- 0L; n_emit <- 0L

for (k in k_from:n_me) {
  sd_k  <- me[k]
  tr_mi <- (k - PAP_TRAIN_M):(k - 1L)

  # ---- (a) IC that became observable at me[k] ------------------------------
  if (!is.null(PREV) && identical(PREV_MI, k - 1L)) {
    lb <- LAB[.(k - 1L), .(Ticker, y, asof), nomatch = NULL][is.finite(y)]
    if (nrow(lb)) {
      j <- merge(PREV, lb, by = "Ticker")
      if (nrow(j) >= AX_MIN_TEST && max(j$asof) <= sd_k) {
        for (mn in MODELS) {
          icv <- suppressWarnings(stats::cor(j[[paste0("p_", mn)]], j$y,
                                             method = "spearman"))
          if (is.finite(icv))
            IC_ROWS[[length(IC_ROWS) + 1L]] <-
              data.table(mi = k - 1L, model = mn, ic = icv, asof = max(j$asof))
        }
      }
    }
  }
  PREV <- NULL; PREV_MI <- NA_integer_

  # ---- (b) LASSO screening of the second-level indicators ------------------
  TRX <- P[.(tr_mi), nomatch = NULL]
  if (!nrow(TRX)) next
  LW <- dcast(TRX, mi + Ticker ~ Factor_Name, value.var = "x")
  LW <- merge(LW, LAB[mi %in% tr_mi, .(mi, Ticker, y, asof)], by = c("mi", "Ticker"))
  LW <- LW[is.finite(y)]
  if (nrow(LW) < AX_MIN_TRAIN) next
  # hard structural PIT assertion: no training label may postdate the decision
  if (max(LW$asof) > sd_k)
    stop(sprintf("[engine] PIT: training label asof %s > decision date %s",
                 format(max(LW$asof)), format(sd_k)))
  fc <- setdiff(names(LW), c("mi", "Ticker", "y", "asof"))
  if (!length(fc)) next
  # an indicator absent in some slot of the window -> 0, the cross-sectional mean
  # of a Z-score (declared).  This is the LASSO design matrix only; the eq (5)
  # aggregation below instead renormalises over the indicators actually present.
  LW[, (fc) := lapply(.SD, function(u) fifelse(is.finite(u), u, 0)), .SDcols = fc]
  sdv <- vapply(fc, function(cn) stats::sd(LW[[cn]]), numeric(1))
  xc  <- fc[is.finite(sdv) & sdv > 1e-10]
  if (length(xc) < 2L) next
  set.seed(AX_SEED + k)
  cvl <- tryCatch(glmnet::cv.glmnet(as.matrix(LW[, xc, with = FALSE]), LW$y,
                                    alpha = 1, nfolds = AX_CV_FOLD, standardize = TRUE),
                  error = function(e) NULL)
  surv <- if (is.null(cvl)) xc else {
    bb <- as.matrix(stats::coef(cvl, s = "lambda.min"))
    s <- rownames(bb)[-1L][abs(bb[-1L, 1]) > 0]
    if (!length(s)) xc else s
  }
  rm(TRX, LW)

  # ---- (c) eq (4)-(5): aggregate survivors into first-level factors --------
  # Screening works at the second level and the paper's model always keeps all
  # eight first-level factors, so a group left with no survivor falls back to
  # every indicator it has in this window.
  keep_f <- unlist(lapply(GRP_NM, function(g) {
    gf <- intersect(GROUPS[[g]], surv)
    if (length(gf)) gf else GROUPS[[g]]
  }), use.names = FALSE)
  E <- EW[.(c(tr_mi, k)), nomatch = NULL][Factor_Name %chin% keep_f]
  if (!nrow(E)) next
  E <- GMAP[E, on = "Factor_Name", nomatch = NULL]
  GS <- E[, .(num = sum(zk * wraw), den = sum(wraw), eq = mean(zk)),
          by = .(mi, Ticker, grp)]
  # eq (4) normalises over the indicators actually present for that stock-month;
  # all weights zero (every e = 1, perfectly uniform) -> equal weights.
  GS[, f := fifelse(is.finite(den) & den > 1e-12, num / den, eq)]
  GS <- GS[is.finite(f)]
  if (!nrow(GS)) next
  rm(E)

  # as-of feature set: the groups that materialised in slots [k-12, k] ONLY.
  gset <- intersect(GRP_NM, unique(GS$grp))
  if (length(gset) < 2L) next
  X <- dcast(GS, mi + Ticker ~ grp, value.var = "f")
  gcols <- intersect(gset, names(X))
  # a stock-month missing one group score keeps its row: that group is filled
  # with the slot's cross-sectional median, else 0 (declared).  No stock is ever
  # removed from the panel for missingness.
  for (g in gcols) {
    X[, (g) := fifelse(is.finite(get(g)), get(g),
                       stats::median(get(g), na.rm = TRUE)), by = mi]
    X[, (g) := fifelse(is.finite(get(g)), get(g), 0)]
  }
  XTE <- X[mi == k]
  XTR <- merge(X[mi < k], LAB[mi %in% tr_mi, .(mi, Ticker, y)], by = c("mi", "Ticker"))
  XTR <- XTR[is.finite(y)]
  if (nrow(XTR) < AX_MIN_TRAIN || nrow(XTE) < AX_MIN_TEST) next
  xtr <- as.matrix(XTR[, gcols, with = FALSE])
  xte <- as.matrix(XTE[, gcols, with = FALSE])
  ytr <- XTR$y
  rm(GS, X)

  # ---- (d) Ridge / MLP / RF — retrained every month (Algorithm 1) ----------
  set.seed(AX_SEED + k)
  p_ridge <- tryCatch({
    cvr <- glmnet::cv.glmnet(xtr, ytr, alpha = 0, nfolds = AX_CV_FOLD, standardize = TRUE)
    as.numeric(stats::predict(cvr, newx = xte, s = "lambda.min"))
  }, error = function(e) NULL)

  ymu <- mean(ytr); ysd <- stats::sd(ytr)
  p_mlp <- if (!is.finite(ysd) || ysd <= 1e-12) NULL else tryCatch({
    set.seed(AX_SEED + k)
    nn <- nnet::nnet(x = xtr, y = (ytr - ymu) / ysd, size = AX_MLP_H,
                     decay = AX_MLP_DEC, maxit = AX_MLP_IT, linout = TRUE,
                     trace = FALSE, MaxNWts = 4000L)
    as.numeric(stats::predict(nn, xte)) * ysd + ymu       # back to return units
  }, error = function(e) NULL)

  p_rf <- tryCatch({
    set.seed(AX_SEED + k)
    rf <- ranger::ranger(x = xtr, y = ytr, num.trees = AX_RF_TREE,
                         mtry = max(1L, floor(sqrt(ncol(xtr)))), min.node.size = 5L,
                         num.threads = 1L, seed = AX_SEED + k, verbose = FALSE)
    as.numeric(stats::predict(rf, data = xte)$predictions)
  }, error = function(e) NULL)

  if (is.null(p_ridge) || is.null(p_mlp) || is.null(p_rf)) next
  PR <- data.table(Ticker = XTE$Ticker, p_ridge = p_ridge, p_mlp = p_mlp, p_rf = p_rf)
  PR <- PR[is.finite(p_ridge) & is.finite(p_mlp) & is.finite(p_rf)]
  if (nrow(PR) < AX_MIN_TEST) next
  PREV <- PR; PREV_MI <- k
  n_fit <- n_fit + 1L

  # ---- (e) Algorithm 2 — IC_Mean weights over the trailing L = 20 window ---
  if (!length(IC_ROWS)) next
  ICL <- rbindlist(IC_ROWS, use.names = TRUE)[mi >= k - PAP_IC_L & mi <= k - 1L]
  if (!nrow(ICL)) next
  if (max(ICL$asof) > sd_k)
    stop(sprintf("[engine] PIT: IC asof %s > decision date %s",
                 format(max(ICL$asof)), format(sd_k)))
  st <- ICL[, .(mu = mean(ic)), by = model]
  if (nrow(st) < length(MODELS)) next
  st[, pos := pmax(mu, 0)]
  tot <- sum(st$pos)
  if (!is.finite(tot) || tot <= 0) next          # Algorithm 2: S = 0 -> w = 0
  wv <- setNames(st$pos / tot, st$model)
  sc <- wv[["ridge"]] * PR$p_ridge + wv[["mlp"]] * PR$p_mlp + wv[["rf"]] * PR$p_rf
  o <- data.table(Date = sd_k, Ticker = PR$Ticker, Score = as.numeric(sc))[is.finite(Score)]
  if (nrow(o) >= AX_MIN_TEST) { OUT[[k]] <- o; n_emit <- n_emit + 1L }
}

# =============================================================================
# 6. FACTORS
# =============================================================================
FACTORS <- rbindlist(Filter(Negate(is.null), OUT), use.names = TRUE)
if (!nrow(FACTORS)) stop("[engine] no scored month survived the burn-in")
FACTORS <- FACTORS[is.finite(Score), .(Date, Ticker, Score)]
setorder(FACTORS, Date, Ticker)
if (max(FACTORS$Date) > max(RAWDATA$Date))
  stop("[engine] signal date beyond RAWDATA range")
cat(sprintf("[engine] fitted months %d | scored months %d | %s ~ %s | %d rows (median %d names/month)\n",
            n_fit, n_emit, format(min(FACTORS$Date)), format(max(FACTORS$Date)),
            nrow(FACTORS), as.integer(stats::median(FACTORS[, .N, by = Date]$N))))
