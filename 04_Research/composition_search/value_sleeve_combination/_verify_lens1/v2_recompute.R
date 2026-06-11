# Lens1 Step2: independent recomputation (adversarial, BEFORE reading run_blend.R)
# Standard functions only: Return.portfolio / Return.annualized / SharpeRatio.annualized /
# maxDrawdown / CalmarRatio / StdDev.annualized / InformationRatio / apply.monthly+Return.cumulative
suppressMessages({ library(PerformanceAnalytics); library(xts); library(zoo); library(arrow); library(data.table) })

al <- readRDS("../aligned_series.rds")
stopifnot(nrow(al) == 248)
dts <- as.Date(as.yearmon(al$realized_ym), frac = 1)  # month-end
R <- xts(cbind(book = al$book_ret, value = al$value_ret), order.by = dts)
bench_col <- xts(al$bench_ret, order.by = dts)

cat("== period:", al$realized_ym[1], "..", al$realized_ym[nrow(al)], "n =", nrow(al), "\n")

# --- independent benchmark from .cache/benchmark.parquet (daily BM_Ret -> monthly compound) ---
bm <- as.data.table(read_parquet("../../../../.cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]
bm_x <- xts(bm$BM_Ret, order.by = bm$Date)
bm_m <- apply.monthly(bm_x, Return.cumulative)           # standard function compounding
idx_ym <- format(index(bm_m), "%Y-%m")
bm_m_al <- as.numeric(bm_m[match(al$realized_ym, idx_ym)])
stopifnot(!any(is.na(bm_m_al)))
bench_ind <- xts(bm_m_al, order.by = dts)
cat("== bench check: max|bench_rds - bench_parquet| =",
    format(max(abs(al$bench_ret - bm_m_al)), digits = 6), "\n")

# --- correlation ---
cat("== cor(value, book) =", round(cor(al$value_ret, al$book_ret), 4), "\n")

# --- metric helper (standard functions only) ---
metr <- function(r, b) {
  cagr  <- as.numeric(Return.annualized(r, scale = 12, geometric = TRUE))
  sr_g  <- as.numeric(SharpeRatio.annualized(r, Rf = 0, scale = 12, geometric = TRUE))
  sr_a  <- as.numeric(SharpeRatio.annualized(r, Rf = 0, scale = 12, geometric = FALSE))
  mdd   <- as.numeric(maxDrawdown(r))
  cal   <- as.numeric(CalmarRatio(r, scale = 12))
  act   <- r - b
  te    <- as.numeric(StdDev.annualized(act, scale = 12))
  ir_pa <- as.numeric(InformationRatio(r, b, scale = 12))           # ActivePremium(geom)/TE
  act_ann_arith <- mean(act) * 12
  ir_ar <- act_ann_arith / te                                        # arithmetic active/TE
  # PORT_t NW lag-3 (sandwich)
  pt <- NA_real_
  ok <- requireNamespace("sandwich", quietly = TRUE)
  if (ok) {
    fit <- lm(as.numeric(act) ~ 1)
    se  <- sqrt(diag(sandwich::NeweyWest(fit, lag = 3, prewhite = FALSE, adjust = TRUE)))
    pt  <- coef(fit)[1] / se
  }
  c(CAGR = cagr, SR_geom = sr_g, SR_arith = sr_a, MDD = mdd, Calmar = cal,
    TE = te, IR_pa = ir_pa, IR_arith = ir_ar, PORT_t_NW3 = pt)
}

fmt <- function(v) paste(names(v), round(v, 4), sep = "=", collapse = "  ")

cat("\n== BOOK-ONLY (vs parquet bench) ==\n", fmt(metr(R[, "book"], bench_ind)), "\n")
cat("== BOOK-ONLY (vs rds bench_ret col) ==\n", fmt(metr(R[, "book"], bench_col)), "\n")

# --- grid blends via Return.portfolio rebalance_on='months' ---
grid <- c(0.05, 0.10, 0.15, 0.20, 0.30)
res <- list()
for (w in grid) {
  rp <- Return.portfolio(R, weights = c(1 - w, w), rebalance_on = "months",
                         geometric = TRUE, verbose = TRUE)
  gross <- rp$returns
  # turnover at each monthly rebalance: target vs drifted EOP of prior period (both sleeves)
  eopw <- rp$EOP.Weight
  n <- nrow(eopw)
  tgt <- matrix(rep(c(1 - w, w), each = n), ncol = 2)
  drift_prior <- rbind(c(1 - w, w), coredata(eopw)[-n, , drop = FALSE])
  to_m <- rowSums(abs(tgt - drift_prior))            # per-month two-sleeve turnover
  to_ann <- mean(to_m) * 12
  netc <- gross - to_m * 0.0015                       # preregistered blend rebal cost 15bps one-way
  mg <- metr(gross, bench_ind); mn <- metr(netc, bench_ind)
  res[[as.character(w)]] <- list(gross = mg, net = mn, to_ann = to_ann)
  cat("\n== w_value =", w, "| blend_TO_annual =", round(to_ann, 4), "==\n")
  cat("  GROSS:", fmt(mg), "\n")
  cat("  NETC :", fmt(mn), "\n")
}

# --- deltas vs book-only (gross-bench=parquet, net-cost version) ---
mb <- metr(R[, "book"], bench_ind)
cat("\n== deltas (net-cost blend minus book-only) ==\n")
for (w in names(res)) {
  mn <- res[[w]]$net
  cat(sprintf("w=%s dSR_geom=%+.4f dMDD=%+.4f dCalmar=%+.4f dIR_arith=%+.4f dIR_pa=%+.4f\n",
              w, mn["SR_geom"] - mb["SR_geom"], mn["MDD"] - mb["MDD"],
              mn["Calmar"] - mb["Calmar"], mn["IR_arith"] - mb["IR_arith"],
              mn["IR_pa"] - mb["IR_pa"]))
}
