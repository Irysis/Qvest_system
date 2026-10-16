#==============================================================================
# RP_AUTO_CLEAN_2202_10721 — engine.R
#
# Paper: "Risk Parity Portfolios with Skewness Risk: An Application to Factor
#         Investing and Alternative Risk Premia" (arXiv:2202.10721)
#
# Paper's object (§2-§3): asset returns are a 2-component Gaussian mixture
#   R ~ (1-pi) N(mu, Sigma) + pi N(mu + mu~, Sigma + Sigma~)          (eq.14)
# so skewness == jump risk. Risk = expected shortfall at alpha under that
# mixture (eq.4); risk contributions have the closed form (eq.5); the risk
# budgeting portfolio solves RC_i(x) = b_i ES_alpha(x) via the log-barrier
# program  min ES_alpha(y) - sum b_i ln y_i  (then x = y / sum y), long-only
# and fully invested.
#
# Backtest protocol (§4.3 + Appendix A.9): pi, mu~ and Sigma~ are held fixed
# while the NORMAL-REGIME covariance Sigma_t is re-estimated at every date by
# the paper's FILTERING algorithm — posterior jump probabilities pi^_{t-s} are
# computed for every date of the one-year rolling window from (mu^_{t-1},
# Sigma^_{t-1}), and (mu^_t, Sigma^_t) are then formed from the window dates
# that DO NOT correspond to a jump (1{pi^ <= pi*}, pi* = 30%). Monthly
# rebalancing, weekly returns. Per section 4.1 (Table 9 bonds row) an asset
# whose estimated expected jump is POSITIVE carries no jump component at all.
#
# Paper's §5.1 application = "building a diversified portfolio using the more
# relevant long-only equity risk factors (size, value, momentum, low beta and
# quality)". That is what this engine allocates over, in the Korean
# measurement-axis universe: five long-only factor sleeves, allocated across by
# the paper's skewness-aware ERC (b_i = 1/n). The paper's own three-asset mix
# (US bonds / S&P 500 / short-volatility carry) is not reproducible here —
# those panels do not exist in this repository.
#
# Declaration of fidelity, every deviation, every constant, every window:
#   FIDELITY.json  (this header is NOT the declaration channel)
#
# Output: PORTFOLIO(Date, Ticker, Weight, Leg) -> portfolio_spec engine_direct
#         (the sleeve weights ARE the paper's output; they are not equal-weight)
#==============================================================================

suppressPackageStartupMessages(library(data.table))

#------------------------------------------------------------------------------
# 0. Constants  (every one of these is declared in FIDELITY.json::constants)
#------------------------------------------------------------------------------
# -- paper --
.PI_JUMP          <- 0.005     # §4.1 weekly model: jump probability pi = 0.5%
.ES_ALPHA         <- 0.99      # §4.2: expected shortfall confidence alpha = 99%
.N_WIN_NORMAL     <- 52L       # §4.3: one-year rolling window, weekly returns
.PI_STAR          <- 0.30      # §4.3 / A.9: jump threshold pi* = 30%
.MU_NORMAL        <- 0         # §4.2: "the expected returns mu_i are equal to zero"
.DT               <- 1         # Remark 1: "we set dt equal to one in the sequel"

# -- supplement (paper silent; see FIDELITY.json::constants note for each) --
.TOP_N_SLEEVE      <- 5L       # 25-name axis cap / 5 sleeves
.MIN_SLEEVE_NAMES  <- 3L       # minimum ranked candidates for a sleeve to exist
.FDB_COVERAGE_MIN  <- 0.05     # load_month_factors() default, passed explicitly
.WEEK_ANCHOR       <- 4L       # 1970-01-05 (a Monday) = ISO week grouping anchor
.WEEK_LEN          <- 7L       # days per ISO week block (calendar, not a parameter)
.ASOF_LAG_DAYS     <- 1L       # composition as-of = month-end STRICTLY before a week
.RET_LAG_DAYS      <- 1L       # daily return lag when RAWDATA carries no Ret column
.COV_RIDGE         <- 1e-8     # relative diagonal ridge on filtered covariances
.EM_RIDGE          <- 1e-6     # relative diagonal ridge inside EM (component cov)
.EM_MAX_ITER       <- 200L     # paper states no iteration cap
.EM_TOL            <- 1e-8     # paper states no convergence criterion
.EM_MIN_JUMP_MASS  <- 1.0      # min effective posterior mass to accept an M-step
.VAR_BRACKET_MULT  <- 20       # VaR root bracket = |mu| + mult * sd
.VAR_BRACKET_TRIES <- 10L      # bracket widening attempts
.VAR_BRACKET_GROWTH <- 2       # bracket widening growth factor
.VAR_TOL           <- 1e-10    # uniroot tolerance for the mixture VaR
.OPT_MAXIT         <- 500L     # BFGS iteration cap on the log-barrier program
.OPT_RELTOL        <- 1e-12    # BFGS relative tolerance
.OPT_PENALTY       <- 1e10     # objective value returned on an infeasible step
.OPT_RESTARTS      <- 2L       # number of starting points tried
.RC_TOL            <- 0.02     # max |RC_i/ES - b_i| accepted as solved
.NUM_FLOOR         <- 1e-10    # variance / denominator floor
.VARPI_FLOOR       <- 1e-12    # floor on varpi_1 + varpi_2 (eq.5 denominator)

# -- factor sleeves: paper §5.1 five long-only equity risk factors --
.FACTOR_IDS <- c(size     = "S01_Size",
                 value    = "V01_BM",
                 momentum = "M01_Mom_12_1",
                 lowbeta  = "D02_Beta",
                 quality  = "Q01_GPA")
.N_SLEEVE    <- length(.FACTOR_IDS)                  # 5
.RISK_BUDGET <- rep(1 / .N_SLEEVE, .N_SLEEVE)        # paper §5: ERC, b_i = 1/n
.N_MIN_JUMP  <- as.integer(ceiling(1 / .PI_JUMP))    # 200 weeks: pi*T >= 1
.EM_INIT_JUMP_OBS <- .N_SLEEVE + 1L                  # 6: EM init slice floor
.MIN_OBS_COV      <- .N_SLEEVE + 1L                  # 6: non-singular n x n cov

#------------------------------------------------------------------------------
# 1. Inputs
#------------------------------------------------------------------------------
if (!exists(".RP_START_DATE", inherits = TRUE))
  stop("[2202.10721] .RP_START_DATE not in environment - measurement-axis start required")
.SIG_FROM <- as.Date(.RP_START_DATE)

if (!exists("RAWDATA", inherits = TRUE) || !is.data.table(RAWDATA))
  stop("[2202.10721] RAWDATA (data.table) required")
if (!all(c("K200", "KQ150") %in% names(RAWDATA)))
  stop("[2202.10721] RAWDATA must carry the measurement-axis K200/KQ150 membership flags")

.QM_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(.QM_ROOT)) .QM_ROOT <- getwd()
if (!exists("load_month_factors", mode = "function"))   # C15: sole factor-DB gateway
  source(file.path(.QM_ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"))

#------------------------------------------------------------------------------
# 2. Gaussian-mixture expected shortfall and risk contributions (eq.4, eq.5)
#------------------------------------------------------------------------------
# Portfolio return x'R of the mixture is itself a univariate 2-component
# mixture: (1-pi) N(m1, s1^2) + pi N(m2, s2^2) with m_j = x'mu_j, s_j^2 =
# x'Sigma_j x.  VaR solves (1-pi) Phi(-h1) + pi Phi(-h2) = 1-alpha, and
# ES / dES/dx are written exactly as the paper writes them (eq.4 and the
# varpi / delta / dVaR auxiliaries of eq.5 + Appendix A.5).

.sk_moments <- function(w, mu1v, mu2v, S1, S2) {
  list(m1 = drop(crossprod(w, mu1v)),
       m2 = drop(crossprod(w, mu2v)),
       s1 = sqrt(max(drop(crossprod(w, S1 %*% w)), .NUM_FLOOR)),
       s2 = sqrt(max(drop(crossprod(w, S2 %*% w)), .NUM_FLOOR)),
       d1 = drop(S1 %*% w),
       d2 = drop(S2 %*% w))
}

# (1-lambda) Phi((VaR+mu_1)/sigma_1) + lambda Phi((VaR+mu_2)/sigma_2) = alpha
.sk_var <- function(p, alpha, pij) {
  tail_fn <- function(v)
    (1 - pij) * pnorm(-(v + p$m1) / p$s1) +
          pij  * pnorm(-(v + p$m2) / p$s2) - (1 - alpha)
  sc <- max(abs(p$m1), abs(p$m2)) + .VAR_BRACKET_MULT * max(p$s1, p$s2)
  if (!is.finite(sc) || sc <= 0) return(NA_real_)
  lo <- -sc; hi <- sc
  g <- sc
  for (i in seq_len(.VAR_BRACKET_TRIES)) {
    if (tail_fn(lo) >= 0) break
    lo <- lo - g; g <- g * .VAR_BRACKET_GROWTH
  }
  g <- sc
  for (i in seq_len(.VAR_BRACKET_TRIES)) {
    if (tail_fn(hi) <= 0) break
    hi <- hi + g; g <- g * .VAR_BRACKET_GROWTH
  }
  if (tail_fn(lo) < 0 || tail_fn(hi) > 0) return(NA_real_)
  tryCatch(uniroot(tail_fn, c(lo, hi), tol = .VAR_TOL)$root, error = function(e) NA_real_)
}

.sk_risk <- function(w, mu1v, mu2v, S1, S2, alpha, pij, want_mr = FALSE) {
  p <- .sk_moments(w, mu1v, mu2v, S1, S2)
  v <- .sk_var(p, alpha, pij)
  if (!is.finite(v)) return(NULL)
  h1 <- (v + p$m1) / p$s1
  h2 <- (v + p$m2) / p$s2
  q  <- 1 - alpha
  # eq.4 with varphi(a,b,c) = (c/(1-alpha)) phi((a+b)/c) - (b/(1-alpha)) Phi(-(a+b)/c)
  es <- ((1 - pij) * (p$s1 * dnorm(h1) - p$m1 * pnorm(-h1)) +
               pij  * (p$s2 * dnorm(h2) - p$m2 * pnorm(-h2))) / q
  if (!is.finite(es)) return(NULL)
  if (!want_mr) return(list(es = es, var = v))
  # varpi_i(x) = pi_i phi(h_i(x)) / sigma_i(x)
  vp1 <- (1 - pij) * dnorm(h1) / p$s1
  vp2 <-       pij * dnorm(h2) / p$s2
  vps <- vp1 + vp2
  if (!is.finite(vps) || vps < .VARPI_FLOOR) return(NULL)
  # A.5 gradient of the value-at-risk
  dvar <- (vp1 * (h1 / p$s1 * p$d1 - mu1v) +
           vp2 * (h2 / p$s2 * p$d2 - mu2v)) / vps
  # A.5 delta_1, delta_2
  dl1 <- (1 + h1 / p$s1 * v) * p$d1 - v * (dvar + mu1v)
  dl2 <- (1 + h2 / p$s2 * v) * p$d2 - v * (dvar + mu2v)
  # eq.5 marginal risk (RC = x o MR)
  mr <- (vp1 * dl1 + vp2 * dl2 -
           ((1 - pij) * mu1v * pnorm(-h1) + pij * mu2v * pnorm(-h2))) / q
  if (!all(is.finite(mr))) return(NULL)
  list(es = es, var = v, mr = mr)
}

#------------------------------------------------------------------------------
# 3. Risk budgeting program  (§3.3.2: min ES(y) - sum b_i ln y_i, x = y/sum y)
#------------------------------------------------------------------------------
# Solved in log coordinates y = exp(z): the gradient of g(z) = ES(exp z) -
# sum b_i z_i is exactly RC(exp z) - b, so the first order conditions ARE the
# risk budgeting equations (6). y >= 0 holds by construction. ES is homogeneous
# of degree 1, so the stationary point satisfies ES(y*) = sum b_i = 1 (used to
# scale the starting point).

.sk_solve <- function(mu1v, mu2v, S1, S2, alpha, pij, b) {
  n <- length(b)
  fn <- function(z) {
    r <- .sk_risk(exp(z), mu1v, mu2v, S1, S2, alpha, pij)
    if (is.null(r) || !is.finite(r$es) || r$es <= 0) return(.OPT_PENALTY)
    r$es - sum(b * z)
  }
  gr <- function(z) {
    y <- exp(z)
    r <- .sk_risk(y, mu1v, mu2v, S1, S2, alpha, pij, want_mr = TRUE)
    # no silent zero gradient: an unevaluable point aborts this attempt
    if (is.null(r)) stop("[2202.10721] ES gradient not evaluable")
    y * r$mr - b
  }
  starts <- list(b / sqrt(pmax(diag(S1), .NUM_FLOOR)),   # inverse-vol start
                 rep(1 / n, n))                          # equal-weight start
  for (k in seq_len(min(.OPT_RESTARTS, length(starts)))) {
    y0 <- starts[[k]]
    if (!all(is.finite(y0)) || any(y0 <= 0)) next
    y0 <- y0 / sum(y0)
    e0 <- .sk_risk(y0, mu1v, mu2v, S1, S2, alpha, pij)
    if (is.null(e0) || !is.finite(e0$es) || e0$es <= 0) next
    op <- tryCatch(optim(log(y0 / e0$es), fn, gr, method = "BFGS",
                         control = list(maxit = .OPT_MAXIT, reltol = .OPT_RELTOL)),
                   error = function(e) NULL)
    if (is.null(op) || !all(is.finite(op$par))) next
    y <- exp(op$par)
    r <- tryCatch(.sk_risk(y, mu1v, mu2v, S1, S2, alpha, pij, want_mr = TRUE),
                  error = function(e) NULL)
    if (is.null(r) || !is.finite(r$es) || r$es <= 0) next
    rc <- y * r$mr / r$es                           # relative risk contributions
    if (!all(is.finite(rc)) || max(abs(rc - b)) > .RC_TOL) next
    x <- y / sum(y)
    if (!all(is.finite(x)) || any(x < 0)) next
    return(x)
  }
  NULL
}

#------------------------------------------------------------------------------
# 4. Linear algebra helpers and multivariate normal log-density
#------------------------------------------------------------------------------
.sk_ridge <- function(S, eps) S + diag(eps * max(mean(diag(S)), .NUM_FLOOR), nrow(S))

.sk_psd <- function(S) {                             # project onto the PSD cone
  S  <- (S + t(S)) / 2
  ev <- eigen(S, symmetric = TRUE)
  ev$vectors %*% (pmax(ev$values, 0) * t(ev$vectors))
}

.sk_mlcov <- function(X, mu) {                       # ML divisor (A.9: 1/n_t)
  Z <- sweep(X, 2L, mu, "-")
  crossprod(Z) / nrow(X)
}

.sk_wcov <- function(Y, wt, mu) {                    # eq.18 weighted covariance
  sw <- sum(wt)
  if (!is.finite(sw) || sw <= 0) return(NULL)
  Z <- sweep(Y, 2L, mu, "-")
  crossprod(Z * wt, Z) / sw
}

.sk_ldmvn <- function(Y, mu, S) {
  ch <- tryCatch(chol(S), error = function(e) NULL)
  if (is.null(ch)) return(NULL)
  Z <- backsolve(ch, t(sweep(Y, 2L, mu, "-")), transpose = TRUE)
  -0.5 * colSums(Z^2) - sum(log(diag(ch))) - 0.5 * ncol(Y) * log(2 * pi)
}

# posterior jump probability (A.9 step 2 / §4.3 filtering formula)
#   pi^_{t-s} = pi phi_n(y; mu^_{t-1} dt + mu~, Sigma^_{t-1} dt + Sigma~) /
#               [(1-pi) phi_n(y; mu^_{t-1} dt, Sigma^_{t-1} dt) + pi phi_n(...)]
.sk_post_jump <- function(Y, mu, S, jp, pij) {
  S1 <- S * .DT
  S2 <- .sk_ridge(S1 + jp$Sigma_tilde, .COV_RIDGE)
  l1 <- .sk_ldmvn(Y, mu * .DT, S1)
  l2 <- .sk_ldmvn(Y, mu * .DT + jp$mu_tilde, S2)
  if (is.null(l1) || is.null(l2)) return(NULL)
  a1 <- log(1 - pij) + l1
  a2 <- log(pij) + l2
  mx <- pmax(a1, a2)
  p  <- exp(a2 - mx) / (exp(a1 - mx) + exp(a2 - mx))
  if (!all(is.finite(p))) return(NULL)
  p
}

#------------------------------------------------------------------------------
# 5. Jump component mu~, Sigma~  (§2.4 EM + §4.1 zero-jump constraint)
#------------------------------------------------------------------------------
# pi is NOT estimated (§4.1 calibrates it by matching the expected drawdown and
# then holds it). The EM runs under the paper's parametrisation (14): component
# 2 = N(mu_1 + mu~, Sigma_1 + Sigma~) with Sigma~ a covariance matrix, so the
# estimated object is a jump model and not a two-volatility-regime model.
# §4.1 then imposes that an asset whose expected jump is POSITIVE has no jump
# component at all (Table 9 / Table 21: bonds mu~ = 0, sigma~ = 0, rho~ = 0).
# mu~ and Sigma~ come from an EXPANDING window ending at the signal date rather
# than the paper's full sample (PIT C1).

.sk_zero_jump <- function(mt, St, idx) {
  if (length(idx)) {
    mt[idx]  <- 0
    St[idx, ] <- 0
    St[, idx] <- 0
  }
  list(mu_tilde = mt, Sigma_tilde = St)
}

.sk_em <- function(Y, pij, zero_idx = integer(0)) {
  Tn <- nrow(Y)
  k2 <- max(.EM_INIT_JUMP_OBS, as.integer(floor(pij * Tn)))
  if (Tn < k2 + .MIN_OBS_COV) return(NULL)
  # deterministic initialisation (no RNG): the k2 worst equal-weight weeks seed
  # the jump component, everything else seeds the normal regime.
  tau <- rep(0, Tn)
  tau[order(rowMeans(Y))[seq_len(k2)]] <- 1
  out <- NULL
  for (it in seq_len(.EM_MAX_ITER)) {
    w2 <- tau; w1 <- 1 - tau
    if (sum(w2) < .EM_MIN_JUMP_MASS || sum(w1) < .MIN_OBS_COV) break  # keep last valid
    mu1 <- colSums(Y * w1) / sum(w1)
    mu2 <- colSums(Y * w2) / sum(w2)
    S1  <- .sk_wcov(Y, w1, mu1); S2 <- .sk_wcov(Y, w2, mu2)
    if (is.null(S1) || is.null(S2)) break
    S1 <- .sk_ridge(S1, .EM_RIDGE)
    jp <- .sk_zero_jump(mu2 - mu1, .sk_psd(S2 - S1), zero_idx)
    out <- jp
    l1 <- .sk_ldmvn(Y, mu1, S1)
    l2 <- .sk_ldmvn(Y, mu1 + jp$mu_tilde, .sk_ridge(S1 + jp$Sigma_tilde, .EM_RIDGE))
    if (is.null(l1) || is.null(l2)) break
    a1 <- log(1 - pij) + l1; a2 <- log(pij) + l2
    mx <- pmax(a1, a2)
    tn <- exp(a2 - mx) / (exp(a1 - mx) + exp(a2 - mx))
    if (!all(is.finite(tn))) break
    d <- max(abs(tn - tau)); tau <- tn
    if (d < .EM_TOL) break
  }
  if (is.null(out) || !all(is.finite(out$mu_tilde)) ||
      !all(is.finite(out$Sigma_tilde))) return(NULL)
  out
}

.sk_jump_params <- function(Y, pij) {
  p1 <- .sk_em(Y, pij)
  if (is.null(p1)) return(NULL)
  idx <- which(p1$mu_tilde > 0)          # §4.1: expected jump positive -> no jump
  if (!length(idx)) return(p1)
  p2 <- .sk_em(Y, pij, zero_idx = idx)   # re-estimate under the constraint
  if (is.null(p2)) p2 <- .sk_zero_jump(p1$mu_tilde, p1$Sigma_tilde, idx)
  idx2 <- which(p2$mu_tilde > 0)         # final enforcement, no re-estimation
  if (length(idx2)) p2 <- .sk_zero_jump(p2$mu_tilde, p2$Sigma_tilde, idx2)
  p2
}

#------------------------------------------------------------------------------
# 6. Signal dates and the five long-only factor sleeves
#------------------------------------------------------------------------------
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

.all_d <- sort(unique(RAWDATA[Date >= .SIG_FROM, Date]))
if (!length(.all_d)) stop("[2202.10721] no RAWDATA dates at or after .RP_START_DATE")
.ME <- data.table(Date = .all_d)[, .(me = max(Date)), by = .(ym = format(Date, "%Y-%m"))][order(me), me]

# Axis membership at the month-end grid, materialised in one pass (K200 carries
# the injected hygiene membership; the engine adds no universe rule of its own).
.UNI <- RAWDATA[as.integer(Date) %in% as.integer(.ME) &
                  ((!is.na(K200)  & K200  > 0) |
                   (!is.na(KQ150) & KQ150 > 0)), .(Date, Ticker)]
setkey(.UNI, Date)
.sk_universe <- function(d) unique(.UNI[.(d), Ticker, nomatch = 0L])

.sk_sleeves_at <- function(d) {
  uni <- .sk_universe(d)
  if (length(uni) < .MIN_SLEEVE_NAMES) return(NULL)
  fz <- tryCatch(load_month_factors(d, coverage_min = .FDB_COVERAGE_MIN,
                                    factor_names = unname(.FACTOR_IDS),
                                    dedup = FALSE),
                 error = function(e) NULL)
  if (is.null(fz) || !nrow(fz)) return(NULL)
  asof <- attr(fz, "factor_db_asof_date")            # PIT: panel must be as-of <= d
  if (is.null(asof) || length(asof) != 1L || is.na(asof) || as.Date(asof) > d) return(NULL)
  fz <- fz[Ticker %in% uni & is.finite(Z_Score_Aligned)]
  if (!nrow(fz)) return(NULL)
  res <- vector("list", .N_SLEEVE)
  for (k in seq_len(.N_SLEEVE)) {
    s <- fz[Factor_Name == unname(.FACTOR_IDS)[k]]
    if (nrow(s) < .MIN_SLEEVE_NAMES) return(NULL)    # sleeve missing -> skip month
    s <- s[order(-Z_Score_Aligned, Ticker)][seq_len(min(.TOP_N_SLEEVE, nrow(s)))]
    res[[k]] <- data.table(Date = d, Sleeve = k, Ticker = s$Ticker)
  }
  rbindlist(res)
}

# iterate by index so the Date class survives into .sk_sleeves_at / load_month_factors
.SLV <- rbindlist(lapply(seq_along(.ME), function(j) .sk_sleeves_at(.ME[j])),
                  use.names = TRUE)
if (!nrow(.SLV)) stop("[2202.10721] no month could form all five factor sleeves")
.ME_OK <- sort(unique(.SLV$Date))

#------------------------------------------------------------------------------
# 7. Weekly sleeve return panel (the model's estimation input)
#------------------------------------------------------------------------------
# Composition in force during ISO week w = the sleeves formed at the latest
# month-end STRICTLY BEFORE w's first trading day (so no week is priced with a
# composition chosen during or after it). Sleeve weekly return = equal-weight
# mean of its members' compounded weekly returns.

.RD <- if ("Ret" %in% names(RAWDATA)) {
  RAWDATA[Ticker %in% unique(.SLV$Ticker) & Date >= .SIG_FROM, .(Date, Ticker, Ret)]
} else {
  z <- RAWDATA[Ticker %in% unique(.SLV$Ticker) & Date >= .SIG_FROM, .(Date, Ticker, Close)]
  setorder(z, Ticker, Date)
  z[, Ret := Close / shift(Close, .RET_LAG_DAYS) - 1, by = Ticker]
  z[, .(Date, Ticker, Ret)]
}
.RD <- .RD[is.finite(Ret)]
.RD[, wkid := (as.integer(Date) - .WEEK_ANCHOR) %/% .WEEK_LEN]

.WKT <- .RD[, .(wret = prod(1 + Ret) - 1), by = .(Ticker, wkid)]
.WKD <- .RD[, .(wstart = min(Date), wend = max(Date)), by = wkid][order(wkid)]

.ix <- findInterval(as.integer(.WKD$wstart) - .ASOF_LAG_DAYS, as.integer(.ME_OK))
.WKD[, asof := as.Date(NA)]
.WKD[.ix > 0L, asof := .ME_OK[.ix[.ix > 0L]]]
.WKD <- .WKD[!is.na(asof)]

.PN <- merge(.WKT, .WKD[, .(wkid, wend, asof)], by = "wkid")
.PN <- merge(.PN, .SLV, by.x = c("asof", "Ticker"), by.y = c("Date", "Ticker"),
             allow.cartesian = TRUE)
.PN <- .PN[, .(sret = mean(wret, na.rm = TRUE)), by = .(wkid, wend, Sleeve)]

.W5 <- dcast(.PN, wkid + wend ~ Sleeve, value.var = "sret")
.SCOLS <- intersect(as.character(seq_len(.N_SLEEVE)), names(.W5))
if (length(.SCOLS) != .N_SLEEVE) stop("[2202.10721] weekly sleeve panel incomplete")
.W5 <- .W5[complete.cases(.W5[, .SCOLS, with = FALSE])][order(wend)]
.WEND <- .W5$wend
.YM   <- as.matrix(.W5[, .SCOLS, with = FALSE])
.T_WK <- nrow(.YM)

#------------------------------------------------------------------------------
# 8. A.9 filtering recursion + monthly rebalancing
#------------------------------------------------------------------------------
# Weeks are walked forward once. A.9 step 1 initialises at t = n_rw + 1 from the
# Gaussian estimates of the first rolling window ("we consider that there is no
# jump in the first rolling window"). At every later week, steps 2-3 recompute
# the posterior jump probabilities of the window from (mu^_{t-1}, Sigma^_{t-1})
# and re-form (mu^_t, Sigma^_t) from the non-jump dates only. Step 4 iterates.
# At a month-end signal date the allocation uses Sigma^_t of the last week that
# closed at or before that date; mu~ and Sigma~ are refreshed (expanding-window
# EM) AFTER that week's filter update, so no estimate consumes its own output.

.m1v <- rep(.MU_NORMAL, .N_SLEEVE)                   # §4.2: mu = 0 in the allocation

# signal date -> index of the last weekly observation known at that date
.IX_ME <- findInterval(as.integer(.ME_OK), as.integer(.WEND))

.mu_f  <- NULL      # mu^_t   (filtered normal-regime mean, used by the filter only)
.Sig_f <- NULL      # Sigma^_t (filtered normal-regime covariance)
.jp    <- NULL      # list(mu_tilde, Sigma_tilde), held fixed between refreshes
.OUT   <- vector("list", length(.ME_OK))

for (t in seq_len(.T_WK)) {
  if (t < .N_WIN_NORMAL) next

  if (t == .N_WIN_NORMAL) {
    W <- .YM[seq_len(.N_WIN_NORMAL), , drop = FALSE]  # A.9 step 1 initialisation
    .mu_f  <- colMeans(W)
    .Sig_f <- .sk_ridge(.sk_mlcov(W, .mu_f), .COV_RIDGE)
  } else {
    W    <- .YM[(t - .N_WIN_NORMAL + 1L):t, , drop = FALSE]
    keep <- rep(TRUE, nrow(W))
    if (!is.null(.jp)) {
      pj <- .sk_post_jump(W, .mu_f, .Sig_f, .jp, .PI_JUMP)   # A.9 step 2
      if (!is.null(pj)) keep <- (pj <= .PI_STAR)             # 1{pi^_{t-s} <= pi*}
    }
    if (sum(keep) >= .MIN_OBS_COV) {                         # A.9 step 3
      Wk     <- W[keep, , drop = FALSE]
      mu_new <- colMeans(Wk)
      .Sig_f <- .sk_ridge(.sk_mlcov(Wk, mu_new), .COV_RIDGE)
      .mu_f  <- mu_new
    }                                 # else: carry (mu^_{t-1}, Sigma^_{t-1})
  }

  srv <- which(.IX_ME == t)        # signal dates whose last known week is t
  if (!length(srv)) next                                     # not a rebalancing week

  if (t >= .N_MIN_JUMP) {
    jpn <- .sk_jump_params(.YM[seq_len(t), , drop = FALSE], .PI_JUMP)
    if (!is.null(jpn)) .jp <- jpn
  }
  if (is.null(.jp) || is.null(.Sig_f)) next                  # warm-up

  S1 <- .Sig_f                                               # normal regime
  S2 <- .sk_ridge(S1 + .jp$Sigma_tilde, .COV_RIDGE)          # jump regime
  x  <- .sk_solve(.m1v, .jp$mu_tilde, S1, S2, .ES_ALPHA, .PI_JUMP, .RISK_BUDGET)
  if (is.null(x)) next

  for (j in srv) {
    d   <- .ME_OK[j]
    mem <- .SLV[Date == d]
    if (!nrow(mem)) next
    mem[, nmem := .N, by = Sleeve]
    mem[, w := x[Sleeve] / nmem]
    pf <- mem[, .(Weight = sum(w)), by = Ticker]
    pf <- pf[is.finite(Weight) & Weight > 0]
    if (!nrow(pf)) next
    pf[, Weight := Weight / sum(Weight)]
    .OUT[[j]] <- data.table(Date = d, Ticker = pf$Ticker,
                            Weight = pf$Weight, Leg = "LONG")
  }
}

PORTFOLIO <- rbindlist(.OUT, use.names = TRUE)
if (!nrow(PORTFOLIO)) stop("[2202.10721] PORTFOLIO empty - no month cleared warm-up")
setorder(PORTFOLIO, Date, Ticker)

cat(sprintf("[2202.10721] PORTFOLIO %d rows | %s ~ %s | %d month-ends | max %d names\n",
            nrow(PORTFOLIO), min(PORTFOLIO$Date), max(PORTFOLIO$Date),
            uniqueN(PORTFOLIO$Date), max(PORTFOLIO[, .N, by = Date]$N)))
