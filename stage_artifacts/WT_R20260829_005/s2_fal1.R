# S2 — FAL-1 음(-)상관 전제 검정 (팩터 수준 · 포트폴리오 envelope 미적용)
#  기계/경제 분해: (a) contemporaneous ME  vs  (b) price-lagged ME (t-14)
#  절단면 병기 의무: 전 구간 단일 수치 금지 -> 연도별 + 분위 양끝 국소
#  판정: |rho_b| < 0.5*|rho_a| -> 구성 아티팩트 / rho_b >= 0 -> 전제 완전 기각
#  (문턱 0.5 는 설계 승계값 — 사후 이동 금지)
suppressWarnings(suppressMessages({library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
P <- readRDS(file.path(OUT, "panel.rds"))
MOM <- P$MOM; V01 <- P$V01; BM <- P$BM; mem <- P$mem; fwd <- P$fwd; ME <- P$ME
R <- fwd$returns_dt; LIQ <- fwd$liq_dt; bench <- fwd$bench_dt

LIQ_THRESHOLD <- 2e8
liq_ok <- LIQ[is.finite(adv) & adv >= LIQ_THRESHOLD, .(Date, Ticker)]
E <- merge(mem, MOM, by = c("Date","Ticker"))
E <- merge(E, BM[, .(Date, Ticker, bm_a, bm_b)], by = c("Date","Ticker"))
E <- merge(E, V01, by = c("Date","Ticker"), all.x = TRUE)
E <- merge(E, liq_ok, by = c("Date","Ticker"))
E <- E[is.finite(mom61) & is.finite(bm_a)]
cat(sprintf("[S2] domain: %d rows | %d months | median names %.0f | bm_b %.1f%% | v01 %.1f%%\n",
            nrow(E), uniqueN(E$Date), median(E[, .N, by = Date]$N),
            100*mean(is.finite(E$bm_b)), 100*mean(is.finite(E$v01))))

## parity: 자체계산 bm_a vs 권위경로 V01_BM
par <- E[is.finite(v01) & is.finite(bm_a),
         .(rho = suppressWarnings(cor(rank(bm_a), rank(v01))), n = .N), by = Date]
cat(sprintf("[S2][PARITY] self bm_a vs V01_BM rank-cor: median=%.4f mean=%.4f p10=%.4f months=%d\n",
            median(par$rho, na.rm = TRUE), mean(par$rho, na.rm = TRUE),
            quantile(par$rho, .10, na.rm = TRUE), nrow(par)))

## (1) 신호 수준 단면 순위상관
xs <- function(dt, vcol, mcol) {
  dt[is.finite(get(vcol)) & is.finite(get(mcol)),
     .(rho = suppressWarnings(cor(rank(get(vcol)), rank(get(mcol)))), n = .N), by = Date][n >= 30L]
}
specs <- list(a_contemp_mom61  = c("bm_a", "mom61"),  b_lagged_mom61  = c("bm_b", "mom61"),
              a_contemp_mom121 = c("bm_a", "mom121"), b_lagged_mom121 = c("bm_b", "mom121"),
              v01_mom61        = c("v01",  "mom61"))
sig_rho <- lapply(specs, function(cc) xs(E, cc[1], cc[2]))
sig_sum <- lapply(names(sig_rho), function(nm) { d <- sig_rho[[nm]]
  list(spec = nm, n_months = nrow(d), rho_mean = mean(d$rho), rho_median = median(d$rho),
       rho_sd = sd(d$rho), frac_negative = mean(d$rho < 0),
       t_mean = { m <- lm(d$rho ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) }) })
names(sig_sum) <- names(sig_rho)

yr <- rbindlist(lapply(names(sig_rho), function(nm) {
  d <- copy(sig_rho[[nm]])[, y := as.integer(format(Date, "%Y"))]
  d[, .(spec = nm, rho_mean = mean(rho), n = .N), by = y] }))

## 분위 양끝 국소 상관
tails <- E[is.finite(bm_a) & is.finite(bm_b) & is.finite(mom61)]
tails[, dv := as.integer(cut(frank(bm_a),  quantile(frank(bm_a),  seq(0,1,.1)), labels = FALSE, include.lowest = TRUE)), by = Date]
tails[, dm := as.integer(cut(frank(mom61), quantile(frank(mom61), seq(0,1,.1)), labels = FALSE, include.lowest = TRUE)), by = Date]
tail_loc <- function(idx, lab) {
  d <- tails[idx, .(rho_a = suppressWarnings(cor(rank(bm_a), rank(mom61))),
                    rho_b = suppressWarnings(cor(rank(bm_b), rank(mom61))), n = .N), by = Date][n >= 15L]
  list(cut = lab, n_months = nrow(d), rho_a_mean = mean(d$rho_a, na.rm = TRUE),
       rho_b_mean = mean(d$rho_b, na.rm = TRUE)) }
cuts <- list(tail_loc(tails$dv == 1L, "value_D1_lowest_BM_expensive"),
             tail_loc(tails$dv == 10L, "value_D10_highest_BM_cheap"),
             tail_loc(tails$dm == 1L, "mom_D1_losers"),
             tail_loc(tails$dm == 10L, "mom_D10_winners"),
             tail_loc(tails$dv %in% c(1L, 10L), "value_both_ends"),
             tail_loc(tails$dv %in% 4:7, "value_middle_D4_D7"))

## (2) 논문 basis: 랭크가중 zero-cost 팩터 수익 상관 (식 (1), Table I 마지막 행)
fac_ret <- function(dt, scol) {
  d <- dt[is.finite(get(scol))]
  W <- d[, { r <- frank(get(scol), ties.method = "average"); dev <- r - mean(r)
             .(Ticker = Ticker, w = (2/sum(abs(dev))) * dev) }, by = Date]
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  WR[, .(fr = sum(w * Ret_1m)), by = Date] }
FR <- Reduce(function(a, b) merge(a, b, by = "Date"),
  list(fac_ret(E, "bm_a")[, .(Date, f_val_a = fr)],
       fac_ret(E[is.finite(bm_b)], "bm_b")[, .(Date, f_val_b = fr)],
       fac_ret(E, "mom61")[, .(Date, f_mom61 = fr)],
       fac_ret(E[is.finite(mom121)], "mom121")[, .(Date, f_mom121 = fr)],
       fac_ret(E[is.finite(v01)], "v01")[, .(Date, f_v01 = fr)]))
cor_pairs <- list(
  list(lab = "value_contemporaneousME_vs_mom61",  rho = cor(FR$f_val_a, FR$f_mom61)),
  list(lab = "value_pricelaggedME_vs_mom61",      rho = cor(FR$f_val_b, FR$f_mom61)),
  list(lab = "value_contemporaneousME_vs_mom121", rho = cor(FR$f_val_a, FR$f_mom121)),
  list(lab = "value_pricelaggedME_vs_mom121",     rho = cor(FR$f_val_b, FR$f_mom121)),
  list(lab = "V01_BM_dbpath_vs_mom61",            rho = cor(FR$f_v01,   FR$f_mom61)))
FR[, y := as.integer(format(Date, "%Y"))]
cor_year <- FR[, .(rho_a = cor(f_val_a, f_mom61), rho_b = cor(f_val_b, f_mom61), n = .N), by = y][n >= 8L]
fac_perf <- data.table(
  leg = c("value_contempME","value_laggedME","mom61","mom121","V01_BM_dbpath"),
  mean_ann = 12*c(mean(FR$f_val_a), mean(FR$f_val_b), mean(FR$f_mom61), mean(FR$f_mom121), mean(FR$f_v01)),
  sr_ann = sqrt(12)*c(mean(FR$f_val_a)/sd(FR$f_val_a), mean(FR$f_val_b)/sd(FR$f_val_b),
                      mean(FR$f_mom61)/sd(FR$f_mom61), mean(FR$f_mom121)/sd(FR$f_mom121),
                      mean(FR$f_v01)/sd(FR$f_v01)))

ra_sig <- sig_sum$a_contemp_mom61$rho_mean; rb_sig <- sig_sum$b_lagged_mom61$rho_mean
ra_ret <- cor_pairs[[1]]$rho;               rb_ret <- cor_pairs[[2]]$rho
vd <- function(ra, rb) {
  if (!is.finite(ra) || !is.finite(rb)) return("UNDETERMINED")
  if (rb >= 0) return("PREMISE_FULLY_REJECTED_rho_b_nonnegative")
  if (abs(rb) < 0.5*abs(ra)) return("CONSTRUCTION_ARTIFACT")
  "PREMISE_SUPPORTED_economic" }

res <- list(
  meta = list(wt_id = "WT-R20260829_005", test = "FAL-1 negative-correlation premise",
    envelope = "portfolio envelope MI-JEOG-YONG (factor signal/return level statistic) - design premise_test_exemption",
    threshold_source = "alpha_hypothesis.json FAL-1 reject_if (inherited 0.5, no post-hoc move)",
    paper_root = "AMP2013 p.936 verbatim: 'When using more recent prices in the value measure, the negative correlation between value and momentum is more negative and the value premium is slightly reduced, but our conclusions are not materially affected.' (original PDF re-read)",
    price_lag_spec = "ME lagged 14 months (shares no price observation with 12-1 formation window t-2..t-13)",
    n_months = uniqueN(E$Date), median_names = median(E[, .N, by = Date]$N)),
  self_bm_vs_dbpath_parity = list(rank_cor_median = median(par$rho, na.rm = TRUE),
    rank_cor_mean = mean(par$rho, na.rm = TRUE), months = nrow(par)),
  signal_level = list(summary = sig_sum, by_year = yr, tail_cuts = cuts),
  return_level_paper_basis = list(pairs = cor_pairs, by_year = cor_year, leg_performance = fac_perf,
    paper_reference = list(japan_P3_P1 = -0.60, japan_factor = -0.64, global_stocks_factor = -0.60,
                           us_factor = -0.65, source = "AMP2013 Table I last row")),
  verdict = list(signal_level = vd(ra_sig, rb_sig), return_level = vd(ra_ret, rb_ret),
    rho_a_signal = ra_sig, rho_b_signal = rb_sig, rho_a_return = ra_ret, rho_b_return = rb_ret,
    ratio_signal = abs(rb_sig)/abs(ra_sig), ratio_return = abs(rb_ret)/abs(ra_ret)))
write_json(res, file.path(OUT, "s2_fal1.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(E = E, FR = FR), file.path(OUT, "s2_objects.rds"))

cat("\n===== FAL-1 signal level =====\n")
for (nm in names(sig_sum)) { s <- sig_sum[[nm]]
  cat(sprintf("%-18s n=%3d rho_mean=%+.4f median=%+.4f sd=%.3f neg%%=%.1f t=%+.2f\n",
      nm, s$n_months, s$rho_mean, s$rho_median, s$rho_sd, 100*s$frac_negative, s$t_mean)) }
cat("\n===== FAL-1 tail cuts (rho_a / rho_b) =====\n")
for (c1 in cuts) cat(sprintf("%-30s n=%3d rho_a=%+.4f rho_b=%+.4f\n", c1$cut, c1$n_months, c1$rho_a_mean, c1$rho_b_mean))
cat("\n===== FAL-1 return level (paper basis) =====\n")
for (p in cor_pairs) cat(sprintf("%-36s rho=%+.4f\n", p$lab, p$rho))
cat("\n===== leg performance (rank-weighted zero-cost, gross) =====\n"); print(fac_perf)
cat("\n===== by year (return level) =====\n"); print(cor_year)
cat(sprintf("\n[VERDICT] signal=%s | return=%s\n", res$verdict$signal_level, res$verdict$return_level))
