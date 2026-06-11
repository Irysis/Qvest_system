# =============================================================================
# _vfy_trackv.R - Track V ADVERSARIAL VERIFICATION (independent, diagnostic only)
#   A. cost identity + metric arithmetic on ALL 38 stored series
#   B. base reproduction: re-run B1_BASE via engine, compare stored series tol 1e-6
#   C. best-improvement reproduction: re-run B1_V4_band_1p5N + B3_V3_topN25, tol 1e-6
#   D. independent (non-Return.portfolio) drift/net reimplementation for
#      B1_V4 (monthly band) + B2_V3 (quarterly drift) - cross-engine check
#   E. engine-fix losslessness: me_panel NA r_idx rows all have NA ret_fwd
#   F. PIT alignment: synthetic case through tv_run_portfolio (weights@t -> ret t+1)
#   G. smoothing lag check: tv_smooth_scores numeric spot-check (t,t-1,t-2 only)
# NOTE: all numbers here are verification diagnostics, not strategy results.
# =============================================================================
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/cycle1b_trackV/s2_common.R")
suppressMessages(library(jsonlite))
PASS <- function(lbl, ok, detail = "") cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), lbl, detail))
files <- c(B1 = "b1_str1715_vanilla", B2 = "b2_str1715v2", B3 = "b3_valmom_amp", B4 = "b4_c19_lo25")

# ---------- A. cost identity + metric arithmetic (all stored series) ----------
cat("=== A. cost identity / metric arithmetic (all 38 runs) ===\n")
mx_cost <- 0; mx_net <- 0; mx_to <- 0; mx_cap <- 0; n_ser <- 0
for (bk in names(files)) {
  ser <- readRDS(file.path(RESD, paste0(files[[bk]], "_series.rds")))
  res <- fromJSON(file.path(RESD, paste0(files[[bk]], "_results.json")), simplifyVector = FALSE)
  for (rn in names(ser)) {
    s <- as.data.table(ser[[rn]]); n_ser <- n_ser + 1
    mx_cost <- max(mx_cost, s[, max(abs(cost - traded * 0.0015))])
    mx_net  <- max(mx_net,  s[, max(abs(net - (gross - cost)))])
    w <- res$runs[[rn]]$windows$FULL
    mx_to  <- max(mx_to,  abs(mean(s$traded / 2) * 12 - as.numeric(w$to_oneway_ann)))
    mx_cap <- max(mx_cap, abs(mean(s$cost) * 12 * 100 - as.numeric(w$cost_ann_pct)))
  }
}
cat(sprintf("series checked: %d\n", n_ser))
PASS("A1 cost == traded*0.0015 (all rows, all runs)", mx_cost < 1e-12, sprintf("max|diff|=%.3e", mx_cost))
PASS("A2 net == gross - cost (all rows, all runs)",   mx_net  < 1e-12, sprintf("max|diff|=%.3e", mx_net))
PASS("A3 to_oneway_ann == mean(traded/2)*12 (vs JSON, rounding tol 5e-5)", mx_to < 5e-5, sprintf("max|diff|=%.3e", mx_to))
PASS("A4 cost_ann_pct == mean(cost)*12*100 == 15bps x traded (vs JSON)",   mx_cap < 5e-5, sprintf("max|diff|=%.3e", mx_cap))

# ---------- B+C. engine re-runs: B1_BASE, B1_V4, B3_V3 ----------
cat("=== B/C. engine re-runs vs stored series (tol 1e-6) ===\n")
pan <- as.data.table(read_parquet(file.path(PROJ, "04_Research/pg2_forensics/intermediate/factor_panel_7f.parquet")))
pan[, Date := as.Date(Date)]
last_d <- max(pan$Date)
udates <- sort(unique(pan$Date))
umap <- data.table(Date = udates,
                   w_idx = as.Date(vapply(udates, function(d) as.character(month_end_cal(as.Date(d))), character(1))),
                   r_idx = as.Date(vapply(udates, function(d) as.character(month_end_cal(seq(as.Date(d), by = "1 month", length.out = 2)[2])), character(1))))
pan <- merge(pan, umap, by = "Date")
ADV[, ym := format(Date, "%Y-%m")]
adv_ym <- ADV[, .(ym, Ticker, adv)]
S1_all <- pan[!is.na(score_eff) & Date < last_d,
              .(Date = w_idx, Ticker, score = score_eff, ret_ok = is.finite(Ret_1m))]
S1_all[, ym := format(Date, "%Y-%m")]
S1_all <- merge(S1_all, adv_ym, by = c("ym", "Ticker"), all.x = TRUE)
S1_all[, ym := NULL]
RET_B1 <- pan[, .(Date = w_idx, Ticker, ret_fwd = Ret_1m, r_idx)]
S1 <- S1_all[Date >= START_DATE]

cmp_series <- function(lbl, mine, stored, tol = 1e-6) {
  a <- as.data.table(mine); b <- as.data.table(stored)
  ok_n <- nrow(a) == nrow(b) && all(a$Date == b$Date)
  if (!ok_n) { PASS(lbl, FALSE, "row/date mismatch"); return(invisible()) }
  d <- max(abs(a$gross - b$gross), abs(a$traded - b$traded), abs(a$net - b$net))
  PASS(lbl, d < tol, sprintf("n=%d max|diff(gross,traded,net)|=%.3e", nrow(a), d))
}

ser1 <- readRDS(file.path(RESD, "b1_str1715_vanilla_series.rds"))
r_base <- tv_run_variant("VFY_B1_BASE", S1, RET_B1, BMM, list(n_fixed = 20L))
cmp_series("B. B1_BASE re-run == stored series", r_base$series, ser1$B1_BASE)
res1 <- fromJSON(file.path(RESD, "b1_str1715_vanilla_results.json"), simplifyVector = FALSE)
j <- res1$runs$B1_BASE$windows$FULL
cat(sprintf("   B1_BASE FULL rerun: SRnet=%.4f (json %.4f) MDD=%.5f (json %.5f) TO1w=%.4f (json %.4f) PORT_t=%.4f (json %.4f)\n",
            r_base$windows$FULL$sr_net, as.numeric(j$sr_net), r_base$windows$FULL$mdd_net, as.numeric(j$mdd_net),
            r_base$windows$FULL$to_oneway_ann, as.numeric(j$to_oneway_ann), r_base$windows$FULL$port_t_nw, as.numeric(j$port_t_nw)))
r_v4 <- tv_run_variant("VFY_B1_V4", S1, RET_B1, BMM, list(n_fixed = 20L, band = 30L))
cmp_series("C1. B1_V4_band_1p5N re-run == stored series", r_v4$series, ser1$B1_V4_band_1p5N)
j4 <- res1$runs$B1_V4_band_1p5N$windows
cat(sprintf("   B1_V4 rerun: FULL SR=%.4f (json %.4f) IS SR=%.4f (json %.4f) OOS SR=%.4f (json %.4f)\n",
            r_v4$windows$FULL$sr_net, as.numeric(j4$FULL$sr_net), r_v4$windows$IS$sr_net, as.numeric(j4$IS$sr_net),
            r_v4$windows$OOS$sr_net, as.numeric(j4$OOS$sr_net)))

S3_raw <- as.data.table(read_parquet(file.path(INP, "b3_scores.parquet")))
S3_raw[, Date := as.Date(Date)]
S3_raw <- S3_raw[, .(Date, Ticker, score = Score, N)]
S3_raw <- merge(S3_raw, RETOK, by = c("Date", "Ticker"), all.x = TRUE)
S3_raw[is.na(ret_ok), ret_ok := FALSE]
S3_raw <- merge(S3_raw, ADV[, .(Date, Ticker, adv)], by = c("Date", "Ticker"), all.x = TRUE)
S3 <- S3_raw[Date >= START_DATE]
ser3 <- readRDS(file.path(RESD, "b3_valmom_amp_series.rds"))
r_b3v3 <- tv_run_variant("VFY_B3_V3", S3, RET_ME, BMM, list(n_fixed = 25L))
cmp_series("C2. B3_V3_topN25 re-run == stored series", r_b3v3$series, ser3$B3_V3_topN25)
res3 <- fromJSON(file.path(RESD, "b3_valmom_amp_results.json"), simplifyVector = FALSE)
j3 <- res3$runs$B3_V3_topN25$windows
cat(sprintf("   B3_V3 rerun: FULL SR=%.4f (json %.4f) IS SR=%.4f (json %.4f) OOS SR=%.4f (json %.4f)\n",
            r_b3v3$windows$FULL$sr_net, as.numeric(j3$FULL$sr_net), r_b3v3$windows$IS$sr_net, as.numeric(j3$IS$sr_net),
            r_b3v3$windows$OOS$sr_net, as.numeric(j3$OOS$sr_net)))

# ---------- D. independent drift/net reimplementation ----------
cat("=== D. independent (non-Return.portfolio) reimplementation ===\n")
ind_net <- function(H, RET) {
  tks <- sort(unique(H$Ticker)); rb <- sort(unique(H$Date))
  grid <- sort(unique(RET$Date)); grid <- grid[grid >= min(rb)]
  R <- RET[Ticker %in% tks & Date %in% grid, .(Date, Ticker, ret_fwd, r_idx)]
  R <- R[!is.na(r_idx)]
  Rw <- dcast(R, r_idx ~ Ticker, value.var = "ret_fwd")
  for (tk in setdiff(tks, names(Rw))) Rw[, (tk) := NA_real_]
  setcolorder(Rw, c("r_idx", tks))
  rmat <- as.matrix(Rw[, -1, with = FALSE]); rmat[is.na(rmat)] <- 0
  ridx <- Rw$r_idx
  Wt <- dcast(H, Date ~ Ticker, value.var = "w", fill = 0)
  for (tk in setdiff(tks, names(Wt))) Wt[, (tk) := 0]
  setcolorder(Wt, c("Date", tks))
  wmat <- as.matrix(Wt[, -1, with = FALSE]); wdates <- Wt$Date
  n <- length(ridx); eop <- rep(0, ncol(rmat)); gross <- numeric(n); traded <- numeric(n)
  for (m in seq_len(n)) {
    cand <- which(wdates < ridx[m])
    j <- cand[length(cand)]
    wd <- wdates[j]
    reb <- (m == 1L) || (wd >= ridx[m - 1L])   # new target since previous return row
    bop <- if (reb) wmat[j, ] else eop
    traded[m] <- if (m == 1L) sum(abs(bop)) else sum(abs(bop - eop))
    r <- rmat[m, ]; g <- sum(bop * r); gross[m] <- g
    eop <- bop * (1 + r) / (1 + g)
  }
  data.table(Date = ridx, gross = gross, traded = traded, net = gross - traded * 0.0015)
}
H_v4 <- tv_build_holdings(S1, list(n_fixed = 20L, band = 30L))
ind4 <- ind_net(H_v4, RET_B1)
st4 <- as.data.table(ser1$B1_V4_band_1p5N)
m4 <- merge(ind4, st4[, .(Date, g2 = gross, t2 = traded, n2 = net)], by = "Date")
d4 <- m4[, max(abs(gross - g2), abs(traded - t2), abs(net - n2))]
PASS("D1. B1_V4 independent drift impl == engine series", nrow(m4) == nrow(st4) && d4 < 1e-8,
     sprintf("n=%d max|diff|=%.3e", nrow(m4), d4))

S2_raw <- as.data.table(read_parquet(file.path(INP, "b2_scores.parquet")))
S2_raw[, Date := as.Date(Date)]
S2_raw <- S2_raw[, .(Date, Ticker, score = Score, N)]
S2_raw <- merge(S2_raw, RETOK, by = c("Date", "Ticker"), all.x = TRUE)
S2_raw[is.na(ret_ok), ret_ok := FALSE]
S2_raw <- merge(S2_raw, ADV[, .(Date, Ticker, adv)], by = c("Date", "Ticker"), all.x = TRUE)
S2 <- S2_raw[Date >= START_DATE]
H_q <- tv_build_holdings(S2, list(quarterly = TRUE))
indq <- ind_net(H_q, RET_ME)
ser2 <- readRDS(file.path(RESD, "b2_str1715v2_series.rds"))
stq <- as.data.table(ser2$B2_V3_rebal_quarterly)
mq <- merge(indq, stq[, .(Date, g2 = gross, t2 = traded, n2 = net)], by = "Date")
dq <- mq[, max(abs(gross - g2), abs(traded - t2), abs(net - n2))]
PASS("D2. B2_V3 quarterly independent drift impl == engine series", nrow(mq) == nrow(stq) && dq < 1e-8,
     sprintf("n=%d max|diff|=%.3e", nrow(mq), dq))

# ---------- E. engine-fix losslessness (NA r_idx rows) ----------
cat("=== E. engine fix (NA r_idx drop) losslessness ===\n")
na_ridx <- MEP[is.na(ret_date), .N]
na_both <- MEP[is.na(ret_date) & !is.finite(ret_fwd), .N]
PASS("E1. all NA-ret_date rows also have NA ret_fwd (lossless drop)", na_ridx == na_both,
     sprintf("NA ret_date rows=%d, of which NA ret_fwd=%d", na_ridx, na_both))

# ---------- F. PIT alignment synthetic test through tv_run_portfolio ----------
cat("=== F. PIT weight-timing synthetic test (engine path) ===\n")
# signal at Jan-31 selects A,B; A returns +10% in Feb (row Feb-28), C +50% in Feb.
# If weights leak to same-month or use future info, gross(Feb) != 5% (=EW(10%,0%)).
sd1 <- as.Date("2026-01-31"); sd2 <- as.Date("2026-02-28"); sd3 <- as.Date("2026-03-31")
H_syn <- data.table(Date = c(sd1, sd1, sd2, sd2),
                    Ticker = c("A", "B", "B", "C"), w = 0.5)
RET_syn <- data.table(Date   = rep(c(sd1, sd2), each = 3),
                      Ticker = rep(c("A", "B", "C"), 2),
                      ret_fwd = c(0.10, 0.00, 0.50,   # month Feb returns (signal Jan)
                                  0.02, -0.04, 0.06), # month Mar returns (signal Feb)
                      r_idx  = rep(c(sd2, sd3), each = 3))
pr_syn <- tv_run_portfolio(H_syn, RET_syn)
g_feb <- pr_syn$series[Date == sd2, gross]
g_mar <- pr_syn$series[Date == sd3, gross]
PASS("F1. gross(Feb) == EW ret of Jan-selected {A,B} = 0.05 (no same-month/future leak)",
     abs(g_feb - 0.05) < 1e-12, sprintf("gross_feb=%.6f", g_feb))
PASS("F2. gross(Mar) == EW ret of Feb-selected {B,C} = 0.01",
     abs(g_mar - 0.01) < 1e-12, sprintf("gross_mar=%.6f", g_mar))
# banding state check: band keeps incumbents using CURRENT score rank only
S_band <- data.table(Date = rep(c(sd1, sd2), each = 4),
                     Ticker = rep(c("A", "B", "C", "D"), 2),
                     score = c(4, 3, 2, 1,   # Jan ranks: A,B top2
                               1, 4, 3, 2),  # Feb ranks: B(1) C(2) D(3) A(4)
                     ret_ok = TRUE)
H_band <- tv_build_holdings(S_band, list(n_fixed = 2L, band = 3L))
feb_hold <- sort(H_band[Date == sd2, Ticker])
# incumbents A(rank4>band3 -> out), B(rank1 keep); refill best non-held = C
PASS("F3. band rule: incumbent out when rank>band, refill by current rank (A out, keep B, add C)",
     identical(feb_hold, c("B", "C")), paste("feb holdings:", paste(feb_hold, collapse = ",")))

# ---------- G. smoothing lag check ----------
cat("=== G. smoothing uses only t, t-1, t-2 ===\n")
d5 <- as.Date(c("2025-01-31", "2025-02-28", "2025-03-31", "2025-04-30", "2025-05-31"))
S_sm <- data.table(Date = rep(d5, each = 1), Ticker = "X", score = c(1, 2, 6, 10, 20))
sm <- tv_smooth_scores(S_sm)
exp_t3 <- mean(c(1, 2, 6)); exp_t5 <- mean(c(6, 10, 20)); exp_t2 <- mean(c(1, 2))
ok_g <- isTRUE(all.equal(sm[Date == d5[3], score_s], exp_t3)) &&
        isTRUE(all.equal(sm[Date == d5[5], score_s], exp_t5)) &&
        isTRUE(all.equal(sm[Date == d5[2], score_s], exp_t2))
PASS("G1. score_s(t) = mean(score(t), t-1, t-2) (lags only, min 2 non-NA)", ok_g,
     sprintf("t3=%.4f(exp %.4f) t5=%.4f(exp %.4f) t2=%.4f(exp %.4f)",
             sm[Date == d5[3], score_s], exp_t3, sm[Date == d5[5], score_s], exp_t5, sm[Date == d5[2], score_s], exp_t2))

cat("VFY DONE\n")
