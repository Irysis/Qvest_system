#==============================================================================
# RP_AUTO_CLEAN_2202_10721 — engine.R
#
# Paper: "Risk Parity Portfolios with Skewness Risk: An Application to Factor
#         Investing and Alternative Risk Premia" (arXiv:2202.10721)
#
# Paper's object (§2-§3): asset returns are a 2-component Gaussian mixture
#   R ~ (1-pi) N(mu, Sigma) + pi N(mu + mu~, Sigma + Sigma~)
# so skewness == jump risk. Risk is measured by expected shortfall at level
# alpha UNDER that mixture (eq. 4), risk contributions have a closed form
# (eq. 5), and the risk budgeting portfolio solves RC_i(x) = b_i * ES_alpha(x)
# via the log-barrier program  min ES_alpha(y) - sum b_i ln y_i  (then
# x = y / sum(y)), long-only, fully invested.
#
# Paper's §5.1 application = "a diversified portfolio using the more relevant
# long-only equity risk factors (size, value, momentum, low beta and quality)".
# That is what this engine builds, in the Korean measurement-axis universe:
# five long-only equity factor sleeves, allocated across by the paper's
# skewness-aware ERC (b_i = 1/n). The paper's own three-asset mix (US bonds /
# S&P 500 / short-volatility carry) is not reproducible here — those panels do
# not exist in this repository.
#
# Declaration of fidelity, every deviation, every constant, every window:
#   FIDELITY.json  (this header is NOT the declaration channel)
#
# Output: PORTFOLIO(Date, Ticker, Weight, Leg)  -> portfolio_spec engine_direct
#         (the sleeve weights ARE the paper's output; they are not equal-weight)
#==============================================================================

suppressPackageStartupMessages(library(data.table))

#------------------------------------------------------------------------------
# 0. Constants  (every one of these is declared in FIDELITY.json::constants)
#------------------------------------------------------------------------------
# -- paper --
.PI_JUMP          <- 0.005     # paper §4.1 weekly model: jump probability pi = 0.5%
.ES_ALPHA         <- 0.99      # paper §4: expected shortfall confidence alpha = 99%
.N_WIN_NORMAL     <- 52L       # paper §4.3: one-year rolling window, weekly returns
.MU_NORMAL        <- 0         # paper: "the expected returns mu_i are equal to zero"

# -- supplement (paper silent; see FIDELITY.json::constants note for each) --
.TOP_N_SLEEVE     <- 5L        # 25-name axis cap / 5 sleeves
.MIN_SLEEVE_NAMES <- 3L        # minimum ranked candidates for a sleeve to exist
.FDB_COVERAGE_MIN <- 0.05      # load_month_factors() default, passed explicitly
.WEEK_ANCHOR      <- 4L        # 1970-01-05 (a Monday) = ISO week grouping anchor
.COV_RIDGE        <- 1e-8      # relative diagonal ridge on Sigma_t
.EM_RIDGE         <- 1e-6      # relative diagonal ridge inside EM (component cov)
.EM_MAX_ITER      <- 200L      # paper states no iteration cap
.EM_TOL           <- 1e-8      # paper states no convergence criterion
.EM_MIN_JUMP_MASS <- 1.0       # min effective posterior mass to accept an M-step
.VAR_BRACKET_MULT <- 20        # VaR root bracket = |mu| + mult * sd
.VAR_BRACKET_TRIES <- 10L      # bracket widening attempts
.VAR_TOL          <- 1e-10     # uniroot tolerance for the mixture VaR
.OPT_MAXIT         <- 500L     # BFGS iteration cap on the log-barrier program
.OPT_RELTOL        <- 1e-12    # BFGS relative tolerance
.OPT_PENALTY       <- 1e10     # objective value returned on an infeasible step
.RC_TOL            <- 0.02     # max |RC_i/ES - b_i| accepted as solved
.NUM_FLOOR         <- 1e-10    # variance / denominator floor

# -- factor sleeves: paper §5.1 five long-only equity risk factors --
.FACTOR_IDS <- c(size     = "S01_Size",
                 value    = "V01_BM",
                 momentum = "M01_Mom_12_1",
                 lowbeta  = "D02_Beta",
                 quality  = "Q01_GPA")
.N_SLEEVE    <- length(.FACTOR_IDS)                  # 5
.RISK_BUDGET <- rep(1 / .N_SLEEVE, .N_SLEEVE)        # paper §5: ERC, b_i = 1/n
.N_MIN_JUMP  <- as.integer(ceiling(1 / .PI_JUMP))    # 200 weeks: pi*T >= 1
.EM_INIT_JUMP_OBS <- .N_SLEEVE + 1L                  # 6: n+1 obs -> non-singular cov

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
# 2. Gaussian-mixture expected shortfall  (paper eq. 2-5)
#------------------------------------------------------------------------------
# Portfolio return x'R of the mixture is itself a univariate 2-component
# mixture: (1-pi) N(m1, s1^2) + pi N(m2, s2^2) with
#   m_j = x'mu_j,  s_j^2 = x'Sigma_j x.
# VaR_alpha solves  (1-pi) Phi(-h1) + pi Phi(-h2) = 1-alpha,  h_j = (VaR+m_j)/s_j
# ES_alpha        = [ (1-pi)(s1 phi(h1) - m1 Phi(-h1))
#                     +   pi (s2 phi(h2) - m2 Phi(-h2)) ] / (1-alpha)
# d ES/dx         = [ (1-pi)( phi(h1)/s1 * Sigma1 x - Phi(-h1) mu1 )
#                     +   pi ( phi(h2)/s2 * Sigma2 x - Phi(-h2) mu2 ) ] / (1-alpha)
# (the dVaR/dx terms cancel because sum_j pi_j phi(h_j) dh_j/dx = 0 is exactly
#  the derivative of the VaR defining equation; Euler check: x' dES/dx = ES)

.sk_pf <- function(w, m1v, m2v, S1, S2) {
  list(m1 = drop(crossprod(w, m1v)),
       m2 = drop(crossprod(w, m2v)),
       s1 = sqrt(max(drop(crossprod(w, S1 %*% w)), .NUM_FLOOR)),
       s2 = sqrt(max(drop(crossprod(w, S2 %*% w)), .NUM_FLOOR)),
       d1 = drop(S1 %*% w),
       d2 = drop(S2 %*% w))
}

.sk_var <- function(p, alpha, pij) {
  tail_fn <- function(v)
    (1 - pij) * pnorm(-(v + p$m1) / p$s1) +
          pij  * pnorm(-(v + p$m2) / p$s2) - (1 - alpha)
  sc <- max(abs(p$m1), abs(p$m2)) + .VAR_BRACKET_MULT * max(p$s1, p$s2)
  if (!is.finite(sc) || sc <= 0) return(NA_real_)
  lo <- -sc; hi <- sc
  for (i in seq_len(.VAR_BRACKET_TRIES)) { if (tail_fn(lo) >= 0) break; lo <- lo - sc }
  for (i in seq_len(.VAR_BRACKET_TRIES)) { if (tail_fn(hi) <= 0) break; hi <- hi + sc }
  if (tail_fn(lo) < 0 || tail_fn(hi) > 0) return(NA_real_)
  r <- tryCatch(uniroot(tail_fn, c(lo, hi), tol = .VAR_TOL)$root, error = function(e) NA_real_)
  r
}

.sk_es <- function(w, m1v, m2v, S1, S2, alpha, pij, want_grad = FALSE) {
  p <- .sk_pf(w, m1v, m2v, S1, S2)
  v <- .sk_var(p, alpha, pij)
  if (!is.finite(v)) return(NULL)
  h1 <- (v + p$m1) / p$s1
  h2 <- (v + p$m2) / p$s2
  q  <- 1 - alpha
  es <- ((1 - pij) * (p$s1 * dnorm(h1) - p$m1 * pnorm(-h1)) +
               pij  * (p$s2 * dnorm(h2) - p$m2 * pnorm(-h2))) / q
  if (!is.finite(es)) return(NULL)
  if (!want_grad) return(list(es = es, var = v))
  g <- ((1 - pij) * (dnorm(h1) / p$s1 * p$d1 - pnorm(-h1) * m1v) +
              pij  * (dnorm(h2) / p$s2 * p$d2 - pnorm(-h2) * m2v)) / q
  list(es = es, var = v, grad = g)
}

#------------------------------------------------------------------------------
# 3. Risk budgeting program  (paper §3: min ES(y) - sum b_i ln y_i, x = y/sum y)
#------------------------------------------------------------------------------
# Solved in log coordinates y = exp(z): the gradient of
#   g(z) = ES(exp(z)) - sum b_i z_i
# is exactly RC(exp(z)) - b, so first order conditions ARE the risk budgeting
# equations. y >= 0 holds by construction. ES is homogeneous of degree 1, so
# the stationary point satisfies ES(y*) = sum b_i = 1 (used for the initial scale).

.sk_rb <- function(m1v, m2v, S1, S2, alpha, pij, b) {
  n <- length(b)
  y0 <- b / sqrt(pmax(diag(S1), .NUM_FLOOR))        # inverse-vol start
  y0 <- y0 / sum(y0)
  e0 <- .sk_es(y0, m1v, m2v, S1, S2, alpha, pij)
  if (is.null(e0) || !is.finite(e0$es) || e0$es <= 0) return(NULL)
  z0 <- log(y0 / e0$es)                             # rescale so ES(y0) = 1

  fn <- function(z) {
    r <- .sk_es(exp(z), m1v, m2v, S1, S2, alpha, pij)
    if (is.null(r) || !is.finite(r$es) || r$es <= 0) return(.OPT_PENALTY)
    r$es - sum(b * z)
  }
  gr <- function(z) {
    y <- exp(z)
    r <- .sk_es(y, m1v, m2v, S1, S2, alpha, pij, want_grad = TRUE)
    if (is.null(r) || !all(is.finite(r$grad))) return(rep(0, n))
    y * r$grad - b
  }
  op <- tryCatch(optim(z0, fn, gr, method = "BFGS",
                       control = list(maxit = .OPT_MAXIT, reltol = .OPT_RELTOL)),
                 error = function(e) NULL)
  if (is.null(op) || !all(is.finite(op$par))) return(NULL)

  y <- exp(op$par)
  r <- .sk_es(y, m1v, m2v, S1, S2, alpha, pij, want_grad = TRUE)
  if (is.null(r) || !is.finite(r$es) || r$es <= 0) return(NULL)
  rc <- y * r$grad / r$es                           # relative risk contributions
  if (!all(is.finite(rc)) || max(abs(rc - b)) > .RC_TOL) return(NULL)
  x <- y / sum(y)
  if (!all(is.finite(x)) || any(x < 0)) return(NULL)
  x
}

#------------------------------------------------------------------------------
# 4. EM estimation of the jump component  (paper §4.1 / §4.3)
#------------------------------------------------------------------------------
# pi is NOT estimated (paper calibrates it by matching expected drawdown and
# then holds it); mu~ and Sigma~ are the jump INCREMENTS, which §4.3 holds fixed
# while Sigma_t is re-estimated. Here they come from an EXPANDING window ending
# at the signal date instead of the paper's full sample (PIT C1).

.sk_ridge <- function(S, eps) S + diag(eps * max(mean(diag(S)), .NUM_FLOOR), nrow(S))

.sk_wcov <- function(Y, wt, mu) {
  sw <- sum(wt)
  if (!is.finite(sw) || sw <= 0) return(NULL)
  Z <- sweep(Y, 2L, mu, "-")
  crossprod(Z * wt, Z) / sw
}

.sk_psd <- function(S) {                             # project onto PSD cone
  S  <- (S + t(S)) / 2
  ev <- eigen(S, symmetric = TRUE)
  ev$vectors %*% (pmax(ev$values, 0) * t(ev$vectors))
}

.sk_ldmvn <- function(Y, mu, S) {
  ch <- tryCatch(chol(S), error = function(e) NULL)
  if (is.null(ch)) return(NULL)
  Z <- backsolve(ch, t(sweep(Y, 2L, mu, "-")), transpose = TRUE)
  -0.5 * colSums(Z^2) - sum(log(diag(ch))) - 0.5 * ncol(Y) * log(2 * pi)
}

.sk_em <- function(Y, pij) {
  n <- ncol(Y); Tn <- nrow(Y)
  k2 <- max(.EM_INIT_JUMP_OBS, as.integer(floor(pij * Tn)))
  if (Tn < k2 + n + 1L) return(NULL)
  # deterministic initialisation (no RNG): the k2 worst equal-weight weeks seed
  # the jump component, everything else seeds the normal regime.
  tau <- rep(0, Tn)
  tau[order(rowMeans(Y))[seq_len(k2)]] <- 1
  out <- NULL
  for (it in seq_len(.EM_MAX_ITER)) {
    w2 <- tau; w1 <- 1 - tau
    if (sum(w2) < .EM_MIN_JUMP_MASS || sum(w1) < n + 1L) break   # keep last valid
    mu1 <- colSums(Y * w1) / sum(w1)
    mu2 <- colSums(Y * w2) / sum(w2)
    S1  <- .sk_wcov(Y, w1, mu1); S2 <- .sk_wcov(Y, w2, mu2)
    if (is.null(S1) || is.null(S2)) break
    S1 <- .sk_ridge(S1, .EM_RIDGE); S2 <- .sk_ridge(S2, .EM_RIDGE)
    out <- list(mu_tilde = mu2 - mu1, Sigma_tilde = .sk_psd(S2 - S1))
    l1 <- .sk_ldmvn(Y, mu1, S1); l2 <- .sk_ldmvn(Y, mu2, S2)
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

#------------------------------------------------------------------------------
# 5. Signal dates and the five long-only factor sleeves
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
# 6. Weekly sleeve return panel (the model's estimation input)
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
  z[, Ret := Close / shift(Close, 1L) - 1, by = Ticker]
  z[, .(Date, Ticker, Ret)]
}
.RD <- .RD[is.finite(Ret)]
.RD[, wkid := (as.integer(Date) - .WEEK_ANCHOR) %/% 7L]

.WKT <- .RD[, .(wret = prod(1 + Ret) - 1), by = .(Ticker, wkid)]
.WKD <- .RD[, .(wstart = min(Date), wend = max(Date)), by = wkid][order(wkid)]

.ix <- findInterval(as.integer(.WKD$wstart) - 1L, as.integer(.ME_OK))
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

#------------------------------------------------------------------------------
# 7. Month-end loop: estimate, solve the risk budgeting program, emit weights
#------------------------------------------------------------------------------
.m1v <- rep(.MU_NORMAL, .N_SLEEVE)                   # paper: mu = 0
.OUT <- vector("list", length(.ME_OK))

for (i in seq_along(.ME_OK)) {
  d  <- .ME_OK[i]
  nk <- sum(.WEND <= d)                              # complete weeks known at d
  if (nk < .N_MIN_JUMP) next                          # warm-up
  Y <- .YM[seq_len(nk), , drop = FALSE]

  jm <- .sk_em(Y, .PI_JUMP)                           # mu~, Sigma~ (expanding, <= d)
  if (is.null(jm)) next

  Yn <- Y[(nk - .N_WIN_NORMAL + 1L):nk, , drop = FALSE]   # one-year rolling window
  S1 <- .sk_ridge(cov(Yn), .COV_RIDGE)
  if (!all(is.finite(S1))) next
  S2 <- S1 + jm$Sigma_tilde

  x <- .sk_rb(.m1v, jm$mu_tilde, S1, S2, .ES_ALPHA, .PI_JUMP, .RISK_BUDGET)
  if (is.null(x)) {                                   # fallback: inverse volatility
    iv <- 1 / sqrt(pmax(diag(S1), .NUM_FLOOR))
    x  <- iv / sum(iv)
  }

  mem <- .SLV[Date == d]
  mem[, nmem := .N, by = Sleeve]
  mem[, w := x[Sleeve] / nmem]
  pf <- mem[, .(Weight = sum(w)), by = Ticker]
  pf <- pf[is.finite(Weight) & Weight > 0]
  if (!nrow(pf)) next
  pf[, Weight := Weight / sum(Weight)]
  .OUT[[i]] <- data.table(Date = d, Ticker = pf$Ticker, Weight = pf$Weight, Leg = "LONG")
}

PORTFOLIO <- rbindlist(.OUT, use.names = TRUE)
if (!nrow(PORTFOLIO)) stop("[2202.10721] PORTFOLIO empty - no month cleared warm-up")
setorder(PORTFOLIO, Date, Ticker)

cat(sprintf("[2202.10721] PORTFOLIO %d rows | %s ~ %s | %d month-ends | max %d names\n",
            nrow(PORTFOLIO), min(PORTFOLIO$Date), max(PORTFOLIO$Date),
            uniqueN(PORTFOLIO$Date), max(PORTFOLIO[, .N, by = Date]$N)))
