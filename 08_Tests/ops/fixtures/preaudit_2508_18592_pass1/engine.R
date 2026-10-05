# =============================================================================
# RP_AUTO_CLEAN_2508_18592 — engine.R
#
# Paper : Cai, He, Zhang (2025) "Combined machine learning for stock selection
#         strategy based on dynamic weighting methods"
#         https://arxiv.org/abs/2508.18592   (arXiv:2508.18592v1, q-fin.ST)
#
# Mechanism transplanted (paper Table 1 / Algorithm 1 / Algorithm 2):
#   (1) 8 first-level style factors, each an Entropy-Weight-Method (EWM)
#       aggregate of its second-level indicators over a trailing 12-month
#       min-max window.
#   (2) LASSO screening of the second-level indicators (paper result (3):
#       "Factor screening substantially enhances the performance").
#   (3) Three models — Ridge / MLP / Random Forest — retrained every month on a
#       rolling 12-month panel, 1-month out-of-sample test (Algorithm 1).
#   (4) Dynamic combination by IC_Mean (Algorithm 2): w_i,t = max(mu_IC_i,0)/S,
#       mu_IC_i = mean of the trailing L=20 monthly Spearman ICs of model i.
#       Combined forecast r_hat = sum_i w_i * r_hat_i  ->  FACTORS$Score.
#   The paper reports IC_Mean + factor screening as its best cell (Table 6);
#   that is the cell implemented here.  The static (evaluation-metric) weighting
#   and the IC_Ratio variant are NOT implemented.
#
# Output : FACTORS(Date, Ticker, Score) — Score = combined predicted monthly
#          return.  The paper says only "Form portfolio based on predicted
#          returns" (Algorithm 1 line 7) and never states a holding count or a
#          weighting scheme, so the portfolio layer is left to the runner via
#          portfolio_spec.  See FIDELITY.json (the single declared channel).
#
# fidelity = adapted.  Every deviation is declared in FIDELITY.json::changed —
#   this header is NOT the declaration channel.
#
# -----------------------------------------------------------------------------
# PIT (C1~C15) — guaranteed by STRUCTURE, not by detector pass
# -----------------------------------------------------------------------------
#  * Factor values come only from load_month_factors(sig_date = month-end) and
#    only as Z_Score_Aligned (C15, C13).  The connector's direction inference is
#    its own expanding Usable_Date <= sig_date path (C14).  No manual sign flip.
#  * Every monthly panel is accepted only if its reported as-of month EQUALS the
#    requested month and its as-of date is <= the requested date.  The connector
#    silently substitutes the closest earlier file when a month is missing; that
#    substitution is rejected here instead of being consumed as a stale panel.
#  * Each month's factor row carries the direction sign that was knowable AT THAT
#    MONTH (one load per month), so a training row never carries a sign inferred
#    from its own future.
#  * Min-max range and entropy weights: trailing 12 month-slots ending at the
#    current month.  No full-sample min/max/mean/sd/cov anywhere.
#  * Labels: y(mi) = compounded return over (month_end[mi], month_end[mi+1]],
#    carrying an explicit realisation date `asof` = month_end[mi+1].  For every
#    decision month k the code asserts max(asof of training rows) <= me[k].
#  * IC log: IC(mi) is appended only at step mi+1 and carries asof = me[mi+1];
#    the weighting step asserts all consumed IC rows have asof <= me[k].
#  * Liquidity floor: adv20 = shift(frollmean(Close*Vol, 20), 1) by ticker, i.e.
#    strictly t-1 (C10).  20 consecutive non-missing observations are required,
#    which also implements the paper's "newly listed within the past month"
#    exclusion.
#  * Universe / status flags are read from the signal-date row only (C6) — the
#    K200/KQ150 membership flag is time-varying in RAWDATA.
#  * No negative shift, no forward join, no manual future indexing: the monthly
#    loop only ever reads month indices < k (training, IC) or == k (features).
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(glmnet)
  library(nnet)
  library(ranger)
})

# ---- paper-stated constants (Algorithm 1 / Algorithm 2 / EWM step 1) --------
PAP_TRAIN_M <- 12L   # Algorithm 1: "Training window size: 12 months"
PAP_EWM_M   <- 12L   # EWM step 1: min-max normalization "over the past 12 months"
PAP_IC_L    <- 20L   # Algorithm 2: "L: Rolling window size (e.g., L=20)"; monthly data
PAP_RF_TREE <- 500L  # paper gives no hyperparameters — see FIDELITY.json::changed
PAP_MLP_H   <- 8L
PAP_MLP_DEC <- 1e-3
PAP_MLP_IT  <- 300L
PAP_CV_FOLD <- 5L
PAP_SEED    <- 20250826L

# ---- fixed axes supplied by the harness (not paper values) ------------------
AX_LIQ_MIN   <- 2e8                      # adv20 floor in KRW, applied at t-1
AX_ADV_WIN   <- 20L
AX_FEAT_FROM <- as.Date("1996-01-01")    # feature/burn-in start; scoring starts later
AX_MIN_TRAIN <- 100L                     # minimum training rows for a monthly fit
AX_MIN_TEST  <- 20L                      # minimum cross-section to score / to compute IC
AX_MIN_ICOBS <- 10L                      # minimum IC observations inside the L=20 window

# ---- paper Table 1: 8 first-level style factors, mapped onto the KR factor DB
#      (the mapping itself is declared in FIDELITY.json::changed)
GROUPS <- list(
  size       = c("S01_Size", "S02_Float_Size", "L26_Log_MktCap"),
  reverse    = c("M04_Mom_1", "M03_Mom_3_1", "M02_Mom_6_1", "M11_ST_Reversal",
                 "M22_Max_Return", "M29_Mom_5d", "L43_Turnover_Change",
                 "L03_Volume_Mom", "L34_Vol_Spike_Ratio", "L35_Reversal_Intensity",
                 "CR09_Money_Flow_Ratio", "D53_Range_Vol"),
  volatility = c("D02_Beta", "D01_IdioVol", "D03_RealVol", "D42_EWMA_Vol"),
  earnings   = c("V02_EP", "V03_CFP", "V10_FCF_Yield", "V11_Shareholder_Yield"),
  growth     = c("GR01_Revenue_Growth", "GR02_Earnings_Growth", "GR04_GPA_Growth",
                 "GR05_ROE_Growth", "GR06_OCF_Growth", "Q07_Earnings_Stability",
                 "Q33_Earnings_Persistence"),
  valuation  = c("V01_BM", "V07_EV_EBITDA", "V08_PSR", "V13_EV_Sales", "V16_Tobins_Q"),
  leverage   = c("R17_Market_Leverage", "R18_Book_Leverage", "Q16_Debt_to_Assets",
                 "Q15_Debt_to_Equity", "Q13_Fin_Leverage", "D60_Leverage"),
  liquidity  = c("L02_Turnover", "L15_Turnover_252d", "L01_Amihud", "L05_Dollar_Volume")
)
GMAP  <- rbindlist(lapply(names(GROUPS),
                          function(g) data.table(grp = g, Factor_Name = GROUPS[[g]])))
if (anyDuplicated(GMAP$Factor_Name))
  stop("[engine] a second-level indicator is assigned to two first-level factors")
ALL_F  <- GMAP$Factor_Name
GRP_NM <- names(GROUPS)
MODELS <- c("ridge", "mlp", "rf")

# ---- factor DB connector (C15 single gate) ---------------------------------
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

# ---- helpers ---------------------------------------------------------------
# status flags arrive as logical / numeric / character depending on vintage;
# anything not affirmatively true counts as not flagged (declared guard).
.truthy <- function(x) {
  if (is.logical(x)) return(!is.na(x) & x)
  if (is.numeric(x))  return(!is.na(x) & x != 0)
  u <- toupper(trimws(as.character(x)))
  !is.na(u) & u %in% c("TRUE", "T", "Y", "YES", "1")
}
# trailing-window reducers over a COMPLETE month grid: slot i covers [i-11, i].
.win_min <- function(v, n) do.call(pmin, c(shift(v, 0:(n - 1L)), list(na.rm = TRUE)))
.win_max <- function(v, n) do.call(pmax, c(shift(v, 0:(n - 1L)), list(na.rm = TRUE)))
.win_sum <- function(v, n) Reduce(`+`, lapply(shift(v, 0:(n - 1L)),
                                              function(u) fifelse(is.na(u), 0, u)))

# =============================================================================
# 1. monthly grid, point-in-time eligibility, labels
# =============================================================================
stopifnot(is.data.table(RAWDATA), is.data.table(BM_DT))
need <- c("Date", "Ticker", "Close", "Vol", "Ret", "K200", "KQ150")
miss <- setdiff(need, names(RAWDATA))
if (length(miss)) stop(sprintf("[engine] RAWDATA lacks %s", paste(miss, collapse = ", ")))

flag_cols <- intersect(c("AdminStock", "TradingHalt", "UnfaithfulDisc"), names(RAWDATA))
memtk <- unique(RAWDATA[(K200 %in% TRUE) | (KQ150 %in% TRUE), Ticker])
RD <- RAWDATA[Ticker %in% memtk, c(need, flag_cols), with = FALSE]   # fresh table; safe to modify
setorder(RD, Ticker, Date)

RD[, tval := as.numeric(Close) * as.numeric(Vol)]
RD[, adv_lag := shift(frollmean(tval, AX_ADV_WIN), 1L), by = Ticker]  # t-1 (C10)
RD[, tval := NULL]

all_dates <- sort(unique(RAWDATA$Date))
mkey <- as.integer(format(all_dates, "%Y")) * 12L + as.integer(format(all_dates, "%m"))
me <- all_dates[!duplicated(mkey, fromLast = TRUE)]                   # last trading day / month
me <- me[me >= AX_FEAT_FROM]
n_me <- length(me)
if (n_me < PAP_EWM_M + PAP_TRAIN_M + 2L) stop("[engine] monthly grid too short")

# holding-period index: hp = i  <=>  me[i] < Date <= me[i+1]
RD[, hp := findInterval(as.numeric(Date), as.numeric(me), left.open = TRUE)]

# label realised at me[mi+1] — the only place a forward return is built, and it
# is tagged with its realisation date so every consumer can be gated on it.
LAB <- RD[hp >= 1L & hp < n_me & is.finite(Ret),
          .(y = prod(1 + Ret) - 1, nd = .N), by = .(mi = hp, Ticker)]
LAB[, asof := me[mi + 1L]]
setkey(LAB, mi)

SIG <- RD[Date %in% me]
SIG[, mi := match(Date, me)]
bad_v <- rep(FALSE, nrow(SIG))
for (fc in flag_cols) bad_v <- bad_v | .truthy(SIG[[fc]])
SIG[, bad := bad_v]
ELIG <- SIG[((K200 %in% TRUE) | (KQ150 %in% TRUE)) & !bad &
              is.finite(adv_lag) & adv_lag >= AX_LIQ_MIN, .(mi, Ticker)]
setkey(ELIG, mi)
rm(SIG); gc(verbose = FALSE)
cat(sprintf("[engine] monthly grid %s ~ %s (%d months) | eligible stock-months %d\n",
            format(me[1]), format(me[n_me]), n_me, nrow(ELIG)))

# =============================================================================
# 2. second-level indicator panel — one load per month, as-of verified
# =============================================================================
FAC <- vector("list", n_me)
n_skip <- 0L
for (k in seq_len(n_me)) {
  ek <- ELIG[.(k), Ticker, nomatch = NULL]
  if (!length(ek)) { n_skip <- n_skip + 1L; next }
  res <- NULL
  invisible(capture.output(suppressWarnings(suppressMessages(
    res <- tryCatch(load_month_factors(me[k], factor_names = ALL_F),
                    error = function(e) NULL)))))
  if (is.null(res) || !nrow(res)) { n_skip <- n_skip + 1L; next }
  a <- attr(res, "factor_db_asof_date")
  # reject a substituted / stale panel: the connector falls back to the closest
  # earlier month file when the requested month is absent.
  if (length(a) != 1L || is.na(a)) { n_skip <- n_skip + 1L; next }
  a <- as.Date(a)
  if (a > me[k] || format(a, "%Y%m") != format(me[k], "%Y%m")) {
    n_skip <- n_skip + 1L; next
  }
  d <- as.data.table(res)[Ticker %in% ek & is.finite(Z_Score_Aligned),
                          .(Ticker, Factor_Name, z = as.numeric(Z_Score_Aligned))]
  if (!nrow(d)) { n_skip <- n_skip + 1L; next }
  d[, mi := k]
  FAC[[k]] <- d
}
FZ <- rbindlist(FAC, use.names = TRUE)
rm(FAC); gc(verbose = FALSE)
if (!nrow(FZ)) stop("[engine] indicator panel empty — factor DB months unavailable")
FZ <- GMAP[FZ, on = "Factor_Name", nomatch = NULL]
cat(sprintf("[engine] indicator panel %d rows | %d indicators | %d months loaded (%d skipped)\n",
            nrow(FZ), uniqueN(FZ$Factor_Name), uniqueN(FZ$mi), n_skip))

# =============================================================================
# 3. EWM — trailing 12-month min-max (step 1) + entropy weights (steps 2-4)
# =============================================================================
f_avail <- unique(FZ$Factor_Name)
grid <- CJ(Factor_Name = f_avail, mi = seq_len(n_me))

MM <- FZ[, .(lo = min(z), hi = max(z)), by = .(Factor_Name, mi)]
MM <- MM[grid, on = .(Factor_Name, mi)]
setorder(MM, Factor_Name, mi)
MM[, `:=`(lo12 = .win_min(lo, PAP_EWM_M), hi12 = .win_max(hi, PAP_EWM_M)), by = Factor_Name]
MM[mi < PAP_EWM_M, `:=`(lo12 = NA_real_, hi12 = NA_real_)]

V <- MM[, .(Factor_Name, mi, lo12, hi12)][FZ, on = .(Factor_Name, mi), nomatch = NULL]
V <- V[is.finite(lo12) & is.finite(hi12)]
V[, rng := hi12 - lo12]
V[, v01 := fifelse(rng > 1e-12, (z - lo12) / rng, 0.5)]   # degenerate range -> midpoint
V[v01 < 0, v01 := 0]; V[v01 > 1, v01 := 1]
V <- V[, .(mi, Ticker, Factor_Name, grp, v01)]

# entropy of indicator j over the trailing window, in decomposable form:
#   p = v01 / S1 ;  sum p log p = (S2 - S1 log S1) / S1 ;  e = -(that) / log(N)
# with 0*log0 := 0.  S1/S2/N are trailing sums of per-month partials.
PART <- V[, .(cnt = .N, s1 = sum(v01),
              s2 = sum(fifelse(v01 > 0, v01 * log(v01), 0))), by = .(Factor_Name, mi)]
PART <- PART[grid, on = .(Factor_Name, mi)]
setorder(PART, Factor_Name, mi)
PART[, `:=`(Rn = .win_sum(cnt, PAP_EWM_M), R1 = .win_sum(s1, PAP_EWM_M),
            R2 = .win_sum(s2, PAP_EWM_M)), by = Factor_Name]
PART[, ent := fifelse(mi >= PAP_EWM_M & Rn > 1 & R1 > 0,
                      -(R2 / R1 - log(R1)) / log(Rn), NA_real_)]
PART[, wraw := fifelse(is.finite(ent), pmax(1 - ent, 0), NA_real_)]

V <- PART[, .(Factor_Name, mi, wraw)][V, on = .(Factor_Name, mi), nomatch = NULL]
V <- V[is.finite(wraw)]
setkey(V, mi)
rm(MM, PART, FZ, grid); gc(verbose = FALSE)
if (!nrow(V)) stop("[engine] EWM panel empty after the 12-month burn-in")
cat(sprintf("[engine] EWM panel %d rows | months %d ~ %d\n",
            nrow(V), min(V$mi), max(V$mi)))

# A first-level factor whose indicators are all absent from the monthly Factor DB
# cannot be built.  That is a data-availability fact about this DB, not a
# performance-based choice, so the feature set is narrowed to the groups that
# actually materialised and the drop is logged (declared in FIDELITY.json).
GRP_USE <- intersect(GRP_NM, unique(V$grp))
if (length(GRP_USE) < 2L)
  stop("[engine] fewer than two first-level factors materialised in the Factor DB")
if (length(GRP_USE) < length(GRP_NM))
  cat(sprintf("[engine] first-level factors dropped (no materialised indicator): %s\n",
              paste(setdiff(GRP_NM, GRP_USE), collapse = ", ")))

# =============================================================================
# 4. monthly loop — screen, fit three models, combine by IC_Mean
# =============================================================================
#  step order inside month k:
#    (a) append IC(mi = k-1) from the previous step's predictions and the label
#        that became known at me[k]  ->  IC log only ever holds asof <= me[k]
#    (b) LASSO screen on the 12-month training panel (labels known at me[k])
#    (c) EWM-aggregate survivors into the 8 first-level factors
#    (d) fit Ridge / MLP / RF on months [k-12, k-1], predict month k
#    (e) weights from the trailing L=20 IC window, combine, emit
mi_lo  <- min(V$mi)
k_from <- max(mi_lo + PAP_TRAIN_M, PAP_EWM_M + PAP_TRAIN_M)
if (k_from > n_me)
  stop(sprintf("[engine] burn-in exceeds the grid (first EWM month %d, grid %d months)",
               mi_lo, n_me))
OUT <- vector("list", n_me)
IC_ROWS <- vector("list", 0L)
PREV <- NULL; PREV_MI <- NA_integer_
n_fit <- 0L; n_emit <- 0L

for (k in k_from:n_me) {
  sd_k <- me[k]

  # ---- (a) IC that became observable at me[k] ------------------------------
  if (!is.null(PREV) && identical(PREV_MI, k - 1L)) {
    lb <- LAB[.(k - 1L), .(Ticker, y, asof), nomatch = NULL]
    if (nrow(lb)) {
      j <- merge(PREV, lb, by = "Ticker")
      j <- j[is.finite(y)]
      if (nrow(j) >= AX_MIN_TEST && max(j$asof) <= sd_k) {
        for (mn in MODELS) {
          pv <- j[[paste0("p_", mn)]]
          icv <- suppressWarnings(stats::cor(pv, j$y, method = "spearman"))
          if (is.finite(icv))
            IC_ROWS[[length(IC_ROWS) + 1L]] <-
              data.table(mi = k - 1L, model = mn, ic = icv, asof = max(j$asof))
        }
      }
    }
  }
  PREV <- NULL; PREV_MI <- NA_integer_

  # ---- (b) LASSO screening on the rolling 12-month panel -------------------
  tr_mi <- (k - PAP_TRAIN_M):(k - 1L)
  TRV <- V[.(tr_mi), nomatch = NULL]
  if (!nrow(TRV)) next
  W2 <- dcast(TRV, mi + Ticker ~ Factor_Name, value.var = "v01")
  W2 <- merge(W2, LAB[mi %in% tr_mi, .(mi, Ticker, y, asof)], by = c("mi", "Ticker"))
  W2 <- W2[is.finite(y)]
  if (nrow(W2) < AX_MIN_TRAIN) next
  # hard structural PIT assertion: no training label may postdate the decision
  if (max(W2$asof) > sd_k)
    stop(sprintf("[engine] PIT: training label asof %s > decision date %s",
                 format(max(W2$asof)), format(sd_k)))
  fcols <- setdiff(names(W2), c("mi", "Ticker", "y", "asof"))
  if (!length(fcols)) next
  # missing indicator -> 0.5, the midpoint of the paper's min-max [0,1] range.
  # Applies to the LASSO design matrix ONLY; the EWM aggregation below instead
  # drops missing indicators and renormalises the entropy weights.
  W2[, (fcols) := lapply(.SD, function(u) fifelse(is.na(u), 0.5, u)), .SDcols = fcols]
  sdv <- vapply(fcols, function(cn) stats::sd(W2[[cn]], na.rm = TRUE), numeric(1))
  xcols <- fcols[is.finite(sdv) & sdv > 1e-10]
  if (length(xcols) < 2L) next
  xl <- as.matrix(W2[, xcols, with = FALSE])
  set.seed(PAP_SEED + k)
  cvl <- tryCatch(glmnet::cv.glmnet(xl, W2$y, alpha = 1, nfolds = PAP_CV_FOLD,
                                    standardize = TRUE),
                  error = function(e) NULL)
  surv <- if (is.null(cvl)) xcols else {
    bb <- as.matrix(stats::coef(cvl, s = "lambda.min"))
    s <- rownames(bb)[-1L][abs(bb[-1L, 1]) > 0]
    if (!length(s)) xcols else s
  }
  rm(W2, xl, TRV)

  # ---- (c) EWM aggregate of the survivors into 8 first-level factors -------
  # screening works at the second level; a first-level factor is never deleted,
  # so a group with no survivor falls back to all of its available indicators.
  keep_f <- unlist(lapply(GRP_USE, function(g) {
    gf <- intersect(GROUPS[[g]], surv)
    if (length(gf)) gf else GROUPS[[g]]
  }), use.names = FALSE)
  PV <- V[.(c(tr_mi, k)), nomatch = NULL][Factor_Name %in% keep_f]
  if (!nrow(PV)) next
  GS <- PV[, .(num = sum(v01 * wraw), den = sum(wraw), mn = mean(v01)),
           by = .(mi, Ticker, grp)]
  GS[, x := fifelse(den > 1e-12, num / den, mn)]      # all-zero entropy -> simple mean
  X <- dcast(GS[is.finite(x)], mi + Ticker ~ grp, value.var = "x")
  gcols <- intersect(GRP_USE, names(X))
  if (length(gcols) < length(GRP_USE)) next           # every available first-level factor required
  X <- X[stats::complete.cases(X[, gcols, with = FALSE])]
  rm(PV, GS)

  XTE <- X[mi == k]
  XTR <- merge(X[mi < k], LAB[mi %in% tr_mi, .(mi, Ticker, y)], by = c("mi", "Ticker"))
  XTR <- XTR[is.finite(y)]
  if (nrow(XTR) < AX_MIN_TRAIN || nrow(XTE) < AX_MIN_TEST) next
  xtr <- as.matrix(XTR[, gcols, with = FALSE])
  xte <- as.matrix(XTE[, gcols, with = FALSE])
  ytr <- XTR$y

  # ---- (d) Ridge / MLP / RF — retrained every month (Algorithm 1) ----------
  set.seed(PAP_SEED + k)
  p_ridge <- tryCatch({
    cvr <- glmnet::cv.glmnet(xtr, ytr, alpha = 0, nfolds = PAP_CV_FOLD, standardize = TRUE)
    as.numeric(stats::predict(cvr, newx = xte, s = "lambda.min"))
  }, error = function(e) NULL)

  ymu <- mean(ytr); ysd <- stats::sd(ytr)
  p_mlp <- if (!is.finite(ysd) || ysd <= 1e-12) NULL else tryCatch({
    set.seed(PAP_SEED + k)
    nn <- nnet::nnet(x = xtr, y = (ytr - ymu) / ysd, size = PAP_MLP_H,
                     decay = PAP_MLP_DEC, maxit = PAP_MLP_IT, linout = TRUE,
                     trace = FALSE, MaxNWts = 4000L)
    as.numeric(stats::predict(nn, xte)) * ysd + ymu    # back to return units
  }, error = function(e) NULL)

  p_rf <- tryCatch({
    set.seed(PAP_SEED + k)
    rf <- ranger::ranger(x = xtr, y = ytr, num.trees = PAP_RF_TREE,
                         mtry = max(1L, floor(sqrt(ncol(xtr)))), min.node.size = 5L,
                         num.threads = 1L, seed = PAP_SEED + k, verbose = FALSE)
    as.numeric(stats::predict(rf, data = xte)$predictions)
  }, error = function(e) NULL)

  if (is.null(p_ridge) || is.null(p_mlp) || is.null(p_rf)) next
  P <- data.table(Ticker = XTE$Ticker, p_ridge = p_ridge, p_mlp = p_mlp, p_rf = p_rf)
  P <- P[is.finite(p_ridge) & is.finite(p_mlp) & is.finite(p_rf)]
  if (nrow(P) < AX_MIN_TEST) next
  PREV <- P; PREV_MI <- k
  n_fit <- n_fit + 1L

  # ---- (e) IC_Mean weights over the trailing L=20 window -------------------
  if (!length(IC_ROWS)) next
  ICL <- rbindlist(IC_ROWS, use.names = TRUE)
  ICL <- ICL[mi >= k - PAP_IC_L & mi <= k - 1L]
  if (!nrow(ICL)) next
  if (max(ICL$asof) > sd_k)
    stop(sprintf("[engine] PIT: IC asof %s > decision date %s",
                 format(max(ICL$asof)), format(sd_k)))
  st <- ICL[, .(mu = mean(ic), n = .N), by = model]
  if (nrow(st) < length(MODELS) || min(st$n) < AX_MIN_ICOBS) next
  st[, pos := pmax(mu, 0)]
  tot <- sum(st$pos)
  if (!is.finite(tot) || tot <= 0) next                # Algorithm 2 line 14: w = 0
  st[, w := pos / tot]
  wv <- setNames(st$w, st$model)
  sc <- wv[["ridge"]] * P$p_ridge + wv[["mlp"]] * P$p_mlp + wv[["rf"]] * P$p_rf
  o <- data.table(Date = sd_k, Ticker = P$Ticker, Score = as.numeric(sc))
  o <- o[is.finite(Score)]
  if (nrow(o) >= AX_MIN_TEST) { OUT[[k]] <- o; n_emit <- n_emit + 1L }
}

# =============================================================================
# 5. FACTORS
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
