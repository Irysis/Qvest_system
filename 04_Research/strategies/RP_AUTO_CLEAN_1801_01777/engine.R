#==============================================================================
# RP_AUTO_CLEAN_1801_01777 — engine.R
#
# Abe, M. & Nakayama, H. (2018)
# "Deep Learning for Forecasting Stock Returns in the Cross-Section"
# arXiv:1801.01777
#
# WHAT THE PAPER DOES (faithfully reproduced here)
#   - 25 practitioner factors (Table 1), month-end, for an index universe.
#   - Input for stock i at month T: the factors at 5 time points spaced 3 months
#     apart  v_i,T = {x_i,T, x_i,T-3, x_i,T-6, x_i,T-9, x_i,T-12}   (§3.2)
#   - Preprocessing: cross-sectional ascending rank / max rank  -> (0,1]  (§3.2)
#     applied to every input AND to the output (next month's return).
#   - Target: next month's stock return r_i,T+1, rank-rescaled the same way.
#   - Loss: MSE over the latest N = 120 monthly training sets (eq. 1, §3.3).
#   - Net: fully-connected feedforward, DNN8_3 = 8 layers, hidden 120-120-70-70-
#     20-20, tanh, dropout 50%, Adam, mini-batch = the cross-section at each
#     time point, 100 epochs, biases 0, weights ~ truncated normal(0, 1/sqrt(M))
#     (Table 3 + §3.5).
#   - Portfolio (§3.4, §4.4): net-zero long-short, top quintile bought equally
#     weighted, bottom quintile sold equally weighted, monthly. No cost.
#
# OUTPUT: PORTFOLIO(Date, Ticker, Weight, Leg)  -- signed weights, each leg
#   sum|w| = 1, net 0. portfolio_spec = {"construction":"engine_direct"}.
#
# PIT (C1-C15): every window ends at or before the signal month-end. Factor DB
#   is consumed only through load_month_factors() (C15) and only the
#   Z_Score_Aligned column (C13); that connector infers direction from IC with
#   Usable_Date <= sig_date (C14). The supervised target for training month j is
#   the return of month j+1, and the training window at signal month p ends at
#   target month p -- a return fully realised on the signal date. No statistic is
#   computed across the whole sample: all rescaling is cross-sectional within one
#   month, all training windows are trailing 120 months.
#
# All deviations from the paper are declared in FIDELITY.json (changed /
# paper_steps / windows / factor_mapping / constants).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# C15: the factor DB is reachable only through the PIT-safe connector.
if (!exists("load_month_factors", mode = "function")) {
  .qm_root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
  source(file.path(.qm_root, "02_Infrastructure", "factor_db", "factor_db_connector.R"))
}

#------------------------------------------------------------------------------
# 1. Constants  (every top-level number lives here; see FIDELITY.json::constants)
#------------------------------------------------------------------------------

# -- paper: problem definition (§3.2 / §3.3) ----------------------------------
N_FACTORS_PAPER        <- 25L      # Table 1 factor count
LAG_STEP_MONTHS        <- 3L       # "past five points of time in three month intervals"
N_TIME_POINTS          <- 5L       # "past five points of time"
N_TRAIN_MONTHS         <- 120L     # "the latest 120 sets of training from the past 10 years"
MISSING_KEEP_FRAC      <- 62 / 125 # "stocks with 62 or less missing input values" of 125

# -- paper: network (Table 3 "DNN8_3" + §3.5) ---------------------------------
HIDDEN_UNITS           <- c(120L, 120L, 70L, 70L, 20L, 20L)
DROPOUT_RATE           <- 0.5      # "dropout rate is set uniformly to 50%"
EPOCHS_INIT            <- 100L     # "100 epochs"
TRUNC_NORM_SD_CAP      <- 2.0      # tf.truncated_normal truncates at +-2 sd

# -- paper: portfolio (§3.4 / §4.4) -------------------------------------------
QUANTILE_FRAC          <- 0.2      # quintile portfolios

# -- supplement: Adam hyper-parameters (paper names Adam [14] but no values;
#    these are the TensorFlow defaults the paper's implementation would use) ---
ADAM_LR                <- 0.001
ADAM_B1                <- 0.9
ADAM_B2                <- 0.999
ADAM_EPS               <- 1e-8

# -- supplement: compute budget (paper refits every month from scratch) -------
REFIT_EVERY_MONTHS     <- 12L      # refit cadence (paper: 1)
EPOCHS_REFIT           <- 20L      # epochs per warm-started refit
TRAIN_XS_CAP           <- 336L     # cap on a training month's cross-section
                                   # (value = paper Table 2 "All" monthly avg 336.5)
MIN_TRAIN_MONTHS_USABLE <- 60L     # refuse to fit on fewer usable training months

# -- supplement: numeric guards ----------------------------------------------
COVERAGE_MIN           <- 0        # connector factor-coverage threshold: keep
                                   # every factor and let the paper's own
                                   # missing-value rule (§3.3) decide
MIN_XS_FOR_RANK        <- 10L      # a cross-section this small cannot be ranked
MIN_LEG_SIZE           <- 2L       # below this the month emits nothing
IMPUTE_MID             <- 0.5      # midpoint of the (0,1] rank scale
EPS_DIV                <- 1e-12    # denominator guard

# -- supplement: bookkeeping --------------------------------------------------
SEED                   <- 1801L    # reproducibility (paper states no seed)
MONTH_KEY_MULT         <- 100L     # integer month key = year*100 + month
LOG_EVERY_MONTHS       <- 24L      # progress line cadence

# -- paper Table 1 -> factor DB ids (one id per registry dedup cluster) -------
#    Table 1 No.14 "Investment growth" has no registry counterpart and is
#    omitted; see FIDELITY.json. Order fixes the input column layout.
PAPER_FACTOR_IDS <- c(
  "V01_BM",                    #  1 Book-to-market ratio
  "V02_EP",                    #  2 Earnings-to-price ratio
  "V11_Shareholder_Yield",     #  3 Dividend yield      (Dividends / MarketCap)
  "V20_SP",                    #  4 Sales-to-price ratio
  "V03_CFP",                   #  5 Cash flow-to-price ratio
  "Q02_ROE",                   #  6 Return on equity
  "Q03_ROA",                   #  7 Return on asset
  "Q17_ROIC",                  #  8 Return on invested capital
  "Q05_Accrual",               #  9 Accruals
  "Q12_Asset_Turnover",        # 10 Sales-to-total assets ratio
  "Q14_Current_Ratio",         # 11 Current ratio
  "Q13_Fin_Leverage",          # 12 Equity ratio        (reciprocal: TA / TE)
  "GR03_Asset_Growth",         # 13 Total asset growth
  "IN06_Investment_to_Assets", # 15 Investment-to-assets ratio
  "C02_EPS_Chg_1m",            # 16 EPS Revision (1 month)
  "C03_EPS_Chg_3m",            # 17 EPS Revision (3 months)
  "D02_Beta",                  # 18 Market beta
  "L26_Log_MktCap",            # 19 Market value
  "M04_Mom_1",                 # 20 Past stock return (1 month)
  "M01_Mom_12_1",              # 21 Past stock return (12 months)
  "D03_RealVol",               # 22 Volatility
  "D43_Skewness",              # 23 Skewness
  "D01_IdioVol",               # 24 Idiosyncratic volatility
  "L02_Turnover"               # 25 Trading turnover
)

N_FACTORS_USED <- length(PAPER_FACTOR_IDS)
N_INPUT        <- N_FACTORS_USED * N_TIME_POINTS
MISSING_MAX    <- as.integer(floor(MISSING_KEEP_FRAC * N_INPUT))
LAG_OFFSETS    <- (seq_len(N_TIME_POINTS) - 1L) * LAG_STEP_MONTHS
SPAN_MONTHS    <- max(LAG_OFFSETS)
KEEP_PROB      <- 1 - DROPOUT_RATE
MI_FIRST_PRED  <- N_TRAIN_MONTHS + SPAN_MONTHS + 1L

set.seed(SEED)

#------------------------------------------------------------------------------
# 2. Calendar, universe, monthly returns  (all from RAWDATA)
#------------------------------------------------------------------------------

stopifnot(is.data.table(RAWDATA),
          all(c("Date", "Ticker", "Ret", "K200", "KQ150") %in% names(RAWDATA)))
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

.all_dates <- sort(unique(RAWDATA$Date))

# contract-injected measurement-axis start; signals are emitted from here on
.SIG_FROM <- if (exists(".RP_START_DATE", inherits = TRUE)) {
  as.Date(.RP_START_DATE)
} else {
  min(.all_dates)
}

# month-end trading day grid, indexed 1..M
MEND <- data.table(Date = .all_dates)
MEND[, mk := data.table::year(Date) * MONTH_KEY_MULT + data.table::month(Date)]
MEND <- MEND[, list(Date = max(Date)), by = mk]
setorder(MEND, Date)
MEND[, mi := seq_len(.N)]
.n_months <- nrow(MEND)

# universe membership on each month-end: the contract injects the measurement
# axis membership into the K200 flag (KQ150 is 0 on this axis)
UNI <- unique(RAWDATA[as.integer(Date) %in% as.integer(MEND$Date) &
                        (K200 == 1 | KQ150 == 1), list(Date, Ticker)])
UNI <- merge(UNI, MEND[, list(Date, mi)], by = "Date")
setkey(UNI, mi)

# realised month return per stock = compounded daily Ret inside the month
MRET <- RAWDATA[is.finite(Ret), list(MRet = prod(1 + Ret) - 1),
                by = list(mk = data.table::year(Date) * MONTH_KEY_MULT +
                            data.table::month(Date), Ticker)]
MRET <- merge(MRET, MEND[, list(mk, mi)], by = "mk")
MRET <- MRET[is.finite(MRet), list(mi, Ticker, MRet)]
setkey(MRET, mi)

cat(sprintf("[1801.01777] months=%d (%s ~ %s) | signals from %s | inputs=%d (%d factors x %d time points)\n",
            .n_months, format(min(MEND$Date)), format(max(MEND$Date)),
            format(.SIG_FROM), N_INPUT, N_FACTORS_USED, N_TIME_POINTS))

#------------------------------------------------------------------------------
# 3. Preprocessing (§3.2): cross-sectional ascending rank / max rank
#------------------------------------------------------------------------------

# rank ascending within the cross-section, divide by the maximum rank -> (0,1]
.xs_rank01 <- function(v) {
  r  <- rank(v, na.last = "keep", ties.method = "average")
  mx <- suppressWarnings(max(r, na.rm = TRUE))
  if (!is.finite(mx) || mx <= EPS_DIV) return(rep(NA_real_, length(v)))
  r / mx
}

# month-end factor block: rows = that month's universe, cols = PAPER_FACTOR_IDS,
# values = rank-rescaled Z_Score_Aligned. NULL when the month is unavailable.
.load_block <- function(sig_date, tickers) {
  if (length(tickers) < MIN_XS_FOR_RANK) return(NULL)
  ft <- tryCatch(
    load_month_factors(sig_date, coverage_min = COVERAGE_MIN,
                       factor_names = PAPER_FACTOR_IDS),
    error = function(e) NULL)
  if (is.null(ft) || !nrow(ft)) return(NULL)
  # the connector substitutes the closest earlier month file when the requested
  # month is absent; a stale block would corrupt the 3-month lag structure, so
  # reject it instead of silently repeating a month
  asof <- attr(ft, "factor_db_asof_date")
  if (is.null(asof) || is.na(asof) ||
      data.table::year(asof) != data.table::year(sig_date) ||
      data.table::month(asof) != data.table::month(sig_date)) return(NULL)

  ft <- unique(ft[Ticker %in% tickers & is.finite(Z_Score_Aligned)],
               by = c("Ticker", "Factor_Name"))
  if (!nrow(ft)) return(NULL)
  wd  <- dcast(ft, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  if (nrow(wd) < MIN_XS_FOR_RANK) return(NULL)
  out <- matrix(NA_real_, nrow = nrow(wd), ncol = N_FACTORS_USED,
                dimnames = list(as.character(wd$Ticker), PAPER_FACTOR_IDS))
  hit <- intersect(PAPER_FACTOR_IDS, names(wd))
  if (length(hit)) out[, hit] <- as.matrix(wd[, ..hit])
  for (cc in seq_len(N_FACTORS_USED)) out[, cc] <- .xs_rank01(out[, cc])
  out
}

# cross-sectional rank-rescaled target: month-(mi+1) return of the stocks that
# make up the month-mi training cross-section
.target_vec <- function(mi_feat, tickers) {
  tg <- MRET[J(mi_feat + 1L), nomatch = 0L]
  if (!nrow(tg)) return(rep(NA_real_, length(tickers)))
  v <- tg$MRet[match(tickers, tg$Ticker)]
  if (sum(is.finite(v)) < MIN_XS_FOR_RANK) return(rep(NA_real_, length(tickers)))
  .xs_rank01(v)
}

#------------------------------------------------------------------------------
# 4. Input assembly (§3.2) + missing-value handling (§3.3)
#------------------------------------------------------------------------------

FBLK <- vector("list", .n_months)   # lazily filled month-end factor blocks
FTRY <- logical(.n_months)          # month already attempted

.block <- function(k) {
  if (k < 1L || k > .n_months) return(NULL)
  if (!FTRY[k]) {
    FTRY[k] <<- TRUE
    FBLK[[k]] <<- .load_block(MEND$Date[k], UNI[J(k), Ticker, nomatch = 0L])
  }
  FBLK[[k]]
}

# pull one month's factor block onto a fixed ticker vector (absent = NA)
.gather <- function(mm, tickers) {
  out <- matrix(NA_real_, nrow = length(tickers), ncol = N_FACTORS_USED)
  if (is.null(mm)) return(out)
  idx <- match(tickers, rownames(mm))
  ok  <- !is.na(idx)
  if (any(ok)) out[ok, ] <- mm[idx[ok], , drop = FALSE]
  out
}

# the 125-dim (here 120-dim) input: 5 time points, 3 months apart, ending at mi
.build_inputs <- function(mi, tickers) {
  do.call(cbind, lapply(LAG_OFFSETS, function(o) .gather(.block(mi - o), tickers)))
}

# §3.3: "each missing value is replaced by the median value for the stocks that
# are not missing" -- per input column, inside this one cross-section
.impute_median <- function(X) {
  for (cc in seq_len(ncol(X))) {
    v  <- X[, cc]
    na <- !is.finite(v)
    if (!any(na)) next
    md <- if (all(na)) NA_real_ else median(v[!na])
    X[na, cc] <- if (is.finite(md)) md else IMPUTE_MID
  }
  X
}

#------------------------------------------------------------------------------
# 5. Network (Table 3 DNN8_3, §3.5) -- tanh / 50% dropout / Adam / MSE
#------------------------------------------------------------------------------

# tf.truncated_normal(mean = 0, stddev = 1/sqrt(M)), truncated at +-2 sd
.trunc_norm <- function(n, sdv) {
  v   <- rnorm(n, 0, sdv)
  bad <- abs(v) > TRUNC_NORM_SD_CAP * sdv
  while (any(bad)) {
    v[bad] <- rnorm(sum(bad), 0, sdv)
    bad    <- abs(v) > TRUNC_NORM_SD_CAP * sdv
  }
  v
}

.net_init <- function(d_in) {
  dims <- c(d_in, HIDDEN_UNITS, 1L)
  nl   <- length(dims) - 1L
  W <- vector("list", nl); b <- vector("list", nl)
  for (l in seq_len(nl)) {
    W[[l]] <- matrix(.trunc_norm(dims[l] * dims[l + 1L], 1 / sqrt(dims[l])),
                     nrow = dims[l], ncol = dims[l + 1L])
    b[[l]] <- rep(0, dims[l + 1L])          # "initialize the biases to be 0"
  }
  list(W = W, b = b, nl = nl)
}

.adam_init <- function(par) {
  list(mW = lapply(par$W, function(x) x * 0), vW = lapply(par$W, function(x) x * 0),
       mb = lapply(par$b, function(x) x * 0), vb = lapply(par$b, function(x) x * 0),
       t  = 0L)
}

.add_bias <- function(Z, b) Z + rep(b, each = nrow(Z))

# one epoch = one pass over the monthly mini-batches (batch = a cross-section)
.net_epoch <- function(par, st, blocks) {
  for (bi in sample.int(length(blocks))) {
    X <- blocks[[bi]]$X; y <- blocks[[bi]]$y
    n <- nrow(X); L <- par$nl
    A <- vector("list", L); H <- vector("list", L - 1L); Mk <- vector("list", L - 1L)
    A[[1L]] <- X
    for (l in seq_len(L - 1L)) {
      H[[l]]       <- tanh(.add_bias(A[[l]] %*% par$W[[l]], par$b[[l]]))
      Mk[[l]]      <- runif(length(H[[l]])) < KEEP_PROB   # element-wise mask
      A[[l + 1L]]  <- H[[l]] * Mk[[l]] / KEEP_PROB        # inverted dropout
    }
    yhat <- as.numeric(A[[L]] %*% par$W[[L]]) + par$b[[L]]

    gW <- vector("list", L); gb <- vector("list", L)
    dZ         <- matrix(2 * (yhat - y) / n, ncol = 1L) # d MSE / d output
    gW[[L]]    <- crossprod(A[[L]], dZ)
    gb[[L]]    <- sum(dZ)
    dA         <- dZ %*% t(par$W[[L]])
    for (l in rev(seq_len(L - 1L))) {
      dZ      <- (dA * Mk[[l]] / KEEP_PROB) * (1 - H[[l]]^2)
      gW[[l]] <- crossprod(A[[l]], dZ)
      gb[[l]] <- colSums(dZ)
      if (l > 1L) dA <- dZ %*% t(par$W[[l]])
    }

    st$t <- st$t + 1L
    c1 <- 1 - ADAM_B1^st$t; c2 <- 1 - ADAM_B2^st$t
    for (l in seq_len(L)) {
      st$mW[[l]] <- ADAM_B1 * st$mW[[l]] + (1 - ADAM_B1) * gW[[l]]
      st$vW[[l]] <- ADAM_B2 * st$vW[[l]] + (1 - ADAM_B2) * gW[[l]]^2
      par$W[[l]] <- par$W[[l]] - ADAM_LR * (st$mW[[l]] / c1) /
        (sqrt(st$vW[[l]] / c2) + ADAM_EPS)
      st$mb[[l]] <- ADAM_B1 * st$mb[[l]] + (1 - ADAM_B1) * gb[[l]]
      st$vb[[l]] <- ADAM_B2 * st$vb[[l]] + (1 - ADAM_B2) * gb[[l]]^2
      par$b[[l]] <- par$b[[l]] - ADAM_LR * (st$mb[[l]] / c1) /
        (sqrt(st$vb[[l]] / c2) + ADAM_EPS)
    }
  }
  list(par = par, st = st)
}

# prediction: dropout off (eq. 2)
.net_score <- function(par, X) {
  A <- X
  for (l in seq_len(par$nl - 1L)) A <- tanh(.add_bias(A %*% par$W[[l]], par$b[[l]]))
  as.numeric(A %*% par$W[[par$nl]]) + par$b[[par$nl]]
}

#------------------------------------------------------------------------------
# 6. Training set (eq. 1): the latest 120 monthly (input, target) sets
#------------------------------------------------------------------------------

.training_blocks <- function(mi_pred) {
  feat_months <- seq.int(mi_pred - N_TRAIN_MONTHS, mi_pred - 1L)
  out <- vector("list", length(feat_months))
  k   <- 0L
  for (j in feat_months) {
    if (j - SPAN_MONTHS < 1L) next
    if (is.null(.block(j))) next                       # own month must exist
    tk <- UNI[J(j), Ticker, nomatch = 0L]
    if (length(tk) < MIN_XS_FOR_RANK) next
    y <- .target_vec(j, tk)
    keep <- is.finite(y)
    if (sum(keep) < MIN_XS_FOR_RANK) next
    tk <- tk[keep]; y <- y[keep]
    if (length(tk) > TRAIN_XS_CAP) {
      sel <- sort(sample.int(length(tk), TRAIN_XS_CAP))
      tk  <- tk[sel]; y <- y[sel]
    }
    X <- .impute_median(.build_inputs(j, tk))
    k <- k + 1L
    out[[k]] <- list(X = X, y = y)
  }
  if (k == 0L) return(list())
  out[seq_len(k)]
}

#------------------------------------------------------------------------------
# 7. Walk-forward: fit -> score -> long-short quintile portfolio
#------------------------------------------------------------------------------

.mi_start <- max(MI_FIRST_PRED, min(MEND$mi[MEND$Date >= .SIG_FROM], .n_months + 1L))
PAR <- NULL; ST <- NULL
.pieces <- list(); .np <- 0L
.n_fit <- 0L; .last_fit_p <- NA_integer_

if (.mi_start <= .n_months) {
  for (p in seq.int(.mi_start, .n_months)) {
    sig_date <- MEND$Date[p]

    refit <- is.null(PAR) || (p - .last_fit_p >= REFIT_EVERY_MONTHS)
    if (refit) {
      blocks <- .training_blocks(p)
      if (length(blocks) >= MIN_TRAIN_MONTHS_USABLE) {
        if (is.null(PAR)) {
          PAR <- .net_init(N_INPUT)                    # cold start, 100 epochs
          n_ep <- EPOCHS_INIT
        } else {
          n_ep <- EPOCHS_REFIT                         # warm start, fewer epochs
        }
        ST <- .adam_init(PAR)
        for (e in seq_len(n_ep)) {
          fit <- .net_epoch(PAR, ST, blocks)
          PAR <- fit$par; ST <- fit$st
        }
        .n_fit <- .n_fit + 1L; .last_fit_p <- p
        cat(sprintf("[1801.01777] fit %d @ %s: %d training months, %d epochs\n",
                    .n_fit, format(sig_date), length(blocks), n_ep))
      }
      rm(blocks)
    }
    if (is.null(PAR)) next

    # ---- eq. 2: score the signal month's cross-section --------------------
    if (is.null(.block(p))) next
    tk <- UNI[J(p), Ticker, nomatch = 0L]
    if (length(tk) < MIN_XS_FOR_RANK) next
    Xp   <- .build_inputs(p, tk)
    n_na <- rowSums(!is.finite(Xp))
    ok   <- n_na <= MISSING_MAX                        # §3.3 missing-count rule
    if (sum(ok) < MIN_XS_FOR_RANK) next
    tk <- tk[ok]; Xp <- Xp[ok, , drop = FALSE]
    sc <- .net_score(PAR, .impute_median(Xp))
    good <- is.finite(sc)
    if (sum(good) < MIN_XS_FOR_RANK) next
    tk <- tk[good]; sc <- sc[good]

    # ---- §3.4 / §4.4: net-zero long-short quintile, equal weighted --------
    nq <- as.integer(floor(length(tk) * QUANTILE_FRAC))
    if (nq < MIN_LEG_SIZE) next
    ord  <- order(-sc, tk)                             # ties broken by ticker
    long <- tk[ord[seq_len(nq)]]
    shrt <- tk[ord[seq.int(length(tk) - nq + 1L, length(tk))]]

    .np <- .np + 1L
    .pieces[[.np]] <- data.table(
      Date   = sig_date,
      Ticker = as.character(c(long, shrt)),
      Weight = c(rep(1 / nq, nq), rep(-1 / nq, nq)),
      Leg    = c(rep("long", nq), rep("short", nq)))

    if (.np %% LOG_EVERY_MONTHS == 0L)
      cat(sprintf("[1801.01777] %s: %d scored, %d per leg\n",
                  format(sig_date), length(tk), nq))
  }
}

PORTFOLIO <- if (.np > 0L) rbindlist(.pieces) else
  data.table(Date = as.Date(character()), Ticker = character(),
             Weight = numeric(), Leg = character())
PORTFOLIO <- PORTFOLIO[is.finite(Weight) & Weight != 0]
setorder(PORTFOLIO, Date, Ticker)

cat(sprintf("[1801.01777] PORTFOLIO: %d rows | %d signal months (%s ~ %s) | %d fits\n",
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date),
            if (nrow(PORTFOLIO)) format(min(PORTFOLIO$Date)) else "NA",
            if (nrow(PORTFOLIO)) format(max(PORTFOLIO$Date)) else "NA", .n_fit))
