# ============================================================================
# C22 Quiet Accumulation (Flow-Price Divergence) — alpha build (WT-D20260621_004)
# QA_t(i) = z_flow_t(i) - beta_t * z_priceresp_t(i)
#   beta_t = expanding no-intercept OLS, LAGGED (INV13 accumulator pattern).
#   flow leg  = frollsum(Foreign+Inst, LB) / Size      (smart-money net-buy; NON-return)
#   price leg = frollsum(Ret, LB)  (SUBTRACTED — structural anti-corr to M01)
# Grid: LB in {21,42,63} x flow in {F+Inst, Foreign-only}, top_n=20, burn-in 60m.
# Anchor = LB42 / F+Inst.
# Real-computation ONLY: canonical_screen_bt(). PIT C1-C15. Single-thread guard.
# Reuses C21 proven data infra (build_c21.R).
# ============================================================================
suppressMessages({ library(arrow); library(data.table); library(dplyr) })
setDTthreads(1L)
options(warn = 1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source("02_Infrastructure/factor_db/factor_z_standard.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260621_004"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

cat("=== STEP 1: load data (single-thread, narrow cols) ===\n")
raw <- open_dataset(".cache/rawdata.parquet") %>%
  select(Date, Ticker, Close, Vol, Size, Ret, K200, KQ150) %>%
  filter(Date >= as.Date("2003-06-01")) %>%   # need 252d (M01) + 63d lookback pre-2005-01
  collect() %>% as.data.table()
setkey(raw, Ticker, Date)
cat("raw rows:", nrow(raw), " date:", as.character(min(raw$Date)), "->", as.character(max(raw$Date)), "\n")

inv <- open_dataset(".cache/investor_stock/investor_wide.parquet") %>%
  select(Date, Ticker, Foreign, Institutional, Individual) %>%
  filter(Date >= as.Date("2003-06-01")) %>%
  collect() %>% as.data.table()
setkey(inv, Ticker, Date)
cat("inv rows:", nrow(inv), "\n")

cat("=== STEP 2: benchmark (real KOSPI200 TR) ===\n")
bench <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bench[, Date := as.Date(Date)]
bench <- bench[!is.na(BM_Ret), .(Date, BM_Ret)]
stopifnot(nrow(bench) > 100, all(!is.na(bench$BM_Ret)))
cat("bench daily rows:", nrow(bench), "\n")

cat("=== STEP 3: universe + monthly sig_dates (2005~) ===\n")
raw[, ym := format(Date, "%Y-%m")]
me <- raw[, .(Date = max(Date)), by = ym][order(Date)]
sig_dates <- me[Date >= as.Date("2005-01-01") & Date <= as.Date("2026-04-30"), Date]
cat("n sig_dates:", length(sig_dates), " (", as.character(min(sig_dates)), "->", as.character(max(sig_dates)), ")\n")

raw[, dv := Close * Vol]
raw[, adv20 := frollmean(dv, 20L, align = "right"), by = Ticker]
raw[, adv20_lag1 := shift(adv20, 1L, type = "lag"), by = Ticker]

cat("=== STEP 4: rolling legs — flow (F+Inst & Foreign-only) + price-response, 3 windows ===\n")
# Investor flow legs (t-1 lag handled by roll_asof last value <= sig_date which is < t since investor settled t-1)
for (lb in c(21L, 42L, 63L)) {
  inv[, paste0("rF", lb)  := frollsum(Foreign, lb, na.rm = TRUE, align = "right"), by = Ticker]
  inv[, paste0("rFI", lb) := frollsum(Foreign + Institutional, lb, na.rm = TRUE, align = "right"), by = Ticker]
}
# price-response leg: rolling sum of Ret over LB (sum of daily simple returns over window)
for (lb in c(21L, 42L, 63L)) {
  raw[, paste0("pr", lb) := frollsum(Ret, lb, na.rm = TRUE, align = "right"), by = Ticker]
}
# M01 12-1 momentum (252d cum ret skip most-recent 21d) for orthogonality
raw[, mom_12_1 := frollsum(Ret, 252L, na.rm = TRUE, align = "right") -
                  frollsum(Ret, 21L,  na.rm = TRUE, align = "right"), by = Ticker]
# size (log mktcap) for ortho #5
# (use Size directly as proxy; z later)

cat("=== STEP 5: per-sig_date cross-section snapshots ===\n")
roll_asof <- function(dt, valcol, sig_d, univ_tickers) {
  empty <- data.table(Ticker = character(0), v = numeric(0)); setnames(empty, "v", valcol)
  sub <- dt[Date < sig_d & Ticker %in% univ_tickers]   # STRICT < sig_d for investor (C2 settle t-1)
  if (nrow(sub) == 0) return(empty)
  sub <- sub[order(Ticker, Date)]
  out <- sub[, .(v = get(valcol)[.N]), by = Ticker]; setnames(out, "v", valcol); out
}
# price legs: pre-sig_date window — use value at last Date <= sig_d (window ends at sig_d close, which is known at t)
roll_asof_le <- function(dt, valcol, sig_d, univ_tickers) {
  empty <- data.table(Ticker = character(0), v = numeric(0)); setnames(empty, "v", valcol)
  sub <- dt[Date <= sig_d & Ticker %in% univ_tickers]
  if (nrow(sub) == 0) return(empty)
  sub <- sub[order(Ticker, Date)]
  out <- sub[, .(v = get(valcol)[.N]), by = Ticker]; setnames(out, "v", valcol); out
}

setkey(inv, Ticker, Date); setkey(raw, Ticker, Date)

# storage: per-cell per-month z_flow, z_priceresp (then expanding beta in STEP 6)
cells <- list(
  list(tag="FI21", flowcol="rFI21", prcol="pr21"),
  list(tag="FI42", flowcol="rFI42", prcol="pr42"),
  list(tag="FI63", flowcol="rFI63", prcol="pr63"),
  list(tag="F21",  flowcol="rF21",  prcol="pr21"),
  list(tag="F42",  flowcol="rF42",  prcol="pr42"),
  list(tag="F63",  flowcol="rF63",  prcol="pr63")
)
# month snapshots: list per cell of data.table(Date,Ticker,z_flow,z_pr)
zsnap <- setNames(vector("list", length(cells)), sapply(cells, `[[`, "tag"))
ortho_list <- vector("list", length(sig_dates))   # M01, INV01, INV02, INV13(z_F-beta*z_Ind 21d), Size
liq_list   <- vector("list", length(sig_dates))

# INV13 accumulator (z_F vs z_Individual, 21d, no-intercept expanding, lagged) — for ortho #3
inv[, rInd21 := frollsum(Individual, 21L, na.rm = TRUE, align = "right"), by = Ticker]
inv13_SxY <- 0; inv13_Sxx <- 0; inv13_n <- 0L

zw <- function(x) z_safe_winsorize(x)

for (k in seq_along(sig_dates)) {
 tryCatch({
  t <- sig_dates[k]
  usnap <- raw[Date == t & !is.na(Close) & ((K200 == 1) | (KQ150 == 1)),
               .(Ticker, Size, adv = adv20_lag1, mom_12_1)]
  usnap <- usnap[!is.na(Size) & Size > 0]
  if (nrow(usnap) < 20) { for(tg in names(zsnap)) {}; next }
  uts <- usnap$Ticker

  # price legs at sig_d (window ends <= t close)
  pr_vals <- list()
  for (lb in c("pr21","pr42","pr63")) pr_vals[[lb]] <- roll_asof_le(raw, lb, t, uts)
  # flow legs (investor Date < sig_d strict)
  fl_vals <- list()
  for (fc in c("rFI21","rFI42","rFI63","rF21","rF42","rF63","rInd21")) fl_vals[[fc]] <- roll_asof(inv, fc, t, uts)

  base <- usnap[, .(Ticker, Size, mom_12_1)]
  for (nm in names(pr_vals)) base <- merge(base, pr_vals[[nm]], by="Ticker", all.x=TRUE)
  for (nm in names(fl_vals)) base <- merge(base, fl_vals[[nm]], by="Ticker", all.x=TRUE)

  # per-cell: flow_raw = flowsum/Size ; z_flow, z_priceresp
  for (cl in cells) {
    fr <- base[[cl$flowcol]] / base$Size
    z_flow <- zw(fr)
    z_pr   <- zw(base[[cl$prcol]])
    dd <- data.table(Date=t, Ticker=base$Ticker, z_flow=z_flow, z_pr=z_pr)
    dd <- dd[is.finite(z_flow) & is.finite(z_pr)]
    if (is.null(zsnap[[cl$tag]])) zsnap[[cl$tag]] <- vector("list", length(sig_dates))
    zsnap[[cl$tag]][[k]] <- dd
  }

  # ortho factors at t
  INV01 <- base$rFI21  # placeholder; recompute below properly
  d_o <- data.table(Date=t, Ticker=base$Ticker)
  d_o[, z_M01  := zw(base$mom_12_1)]
  d_o[, z_INV01 := zw(base$rF21 / base$Size)]   # Foreign 21d / Size  (~INV01 20d)
  d_o[, z_INV02 := zw(base$rF63 / base$Size)]   # Foreign 63d / Size  (~INV02 60d)
  d_o[, z_Size  := zw(base$Size)]
  # INV13 21d (z_F vs z_Individual, beta lagged) for ortho #3
  zF21  <- zw(base$rF21 / base$Size)
  zInd21<- zw(base$rInd21 / base$Size)
  ok13 <- is.finite(zF21) & is.finite(zInd21)
  beta13 <- if (inv13_n >= 60L && inv13_Sxx > 1e-10) inv13_SxY / inv13_Sxx else NA_real_
  resid13 <- zF21 - beta13 * zInd21
  d_o[, z_INV13 := resid13]
  # update INV13 accumulator AFTER (lagged)
  if (sum(ok13) >= 10L) {
    inv13_SxY <- inv13_SxY + sum(zF21[ok13] * zInd21[ok13])
    inv13_Sxx <- inv13_Sxx + sum(zInd21[ok13]^2)
    inv13_n   <- inv13_n + 1L
  }
  ortho_list[[k]] <- d_o

  liq_list[[k]] <- usnap[, .(Date = t, Ticker, adv)]
 }, error = function(e) { cat("ERR k=",k," t=",as.character(sig_dates[k]),": ",conditionMessage(e),"\n"); stop(e) })
}
cat("scored sig_dates (ortho):", sum(!sapply(ortho_list, is.null)), "\n")

cat("=== STEP 6: expanding no-intercept LAGGED beta per cell -> QA residual ===\n")
# For each cell: month loop, beta_lagged = prev SxY/Sxx (if n>=60), residual = z_flow - beta*z_pr, then update.
build_qa <- function(zlist) {
  SxY <- 0; Sxx <- 0; nmo <- 0L
  out <- vector("list", length(zlist))
  for (k in seq_along(zlist)) {
    dd <- zlist[[k]]
    if (is.null(dd) || nrow(dd) < 10L) next
    beta_lag <- if (nmo >= 60L && Sxx > 1e-10) SxY / Sxx else NA_real_
    if (!is.na(beta_lag)) {
      res <- dd$z_flow - beta_lag * dd$z_pr
      out[[k]] <- data.table(Date=dd$Date, Ticker=dd$Ticker, score=res)
    }
    # update accumulator AFTER use (lagged guarantee)
    SxY <- SxY + sum(dd$z_flow * dd$z_pr)
    Sxx <- Sxx + sum(dd$z_pr^2)
    nmo <- nmo + 1L
  }
  list(scores = rbindlist(out), n_months_burnin = nmo)
}
qa_cells <- setNames(vector("list", length(cells)), sapply(cells, `[[`, "tag"))
beta_trace <- list()
for (cl in cells) {
  qa <- build_qa(zsnap[[cl$tag]])
  qa_cells[[cl$tag]] <- qa$scores
  cat(sprintf("  cell %-5s : QA score rows=%d (post burn-in)\n", cl$tag, nrow(qa$scores)))
}

cat("=== STEP 7: forward 1M asset returns + benchmark (compound daily over (t,t+1M]) ===\n")
ret_rows <- list(); bench_rows <- list()
for (k in seq_len(length(sig_dates) - 1L)) {
  t0 <- sig_dates[k]; t1 <- sig_dates[k + 1L]
  win <- raw[Date > t0 & Date <= t1 & !is.na(Ret), .(Ret_1m = prod(1 + Ret) - 1), by = Ticker]
  win[, Date := t0]; ret_rows[[k]] <- win
  bw <- bench[Date > t0 & Date <= t1, BM_Ret]
  bench_rows[[k]] <- data.table(Date = t0, BM_Ret = prod(1 + bw) - 1)
}
returns_dt <- rbindlist(ret_rows)
bench_dt   <- rbindlist(bench_rows)
liq_dt     <- rbindlist(liq_list)
ortho      <- rbindlist(ortho_list)
cat("returns_dt rows:", nrow(returns_dt), " bench_dt rows:", nrow(bench_dt), "\n")

saveRDS(list(qa_cells = qa_cells, ortho = ortho, returns_dt = returns_dt,
             bench_dt = bench_dt, liq_dt = liq_dt, sig_dates = sig_dates),
        file.path(OUT, "qa_intermediate.rds"))
cat("BUILD-PART1-DONE\n")
