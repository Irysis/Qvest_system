## WT-D20260822_002 · P4 — 진단 배터리 완결 + 반증 축 2 + 강건성 + 산출물 발행
##
## 사전등록: PREREG.json. 여기 나오는 R1/R2/R3 는 전부 **비바인딩**(라벨은 P3 primary 로 확정).
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260822_002/p4_diagnostics_emit.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/essence_score.R")
OUT  <- "stage_artifacts/WT-D20260822_002"
SRC  <- "stage_artifacts/fq233_probe0_20260813"
W005 <- "stage_artifacts/WT-D20260813_005"
P2 <- readRDS(file.path(OUT,"p2_arms.rds")); P3 <- readRDS(file.path(OUT,"p3_verdict.rds"))
RES <- P2$RES; SC <- P2$SC; sel <- P2$sel; CP <- P3$CP; GATE <- P2$GATE
PRIM <- c("SEL_RANK","SEL_PEARSON","SEL_MEANDEPTH")
res4 <- list()

cat("=== 1) 성과 계약 지표 (PerformanceAnalytics 표준함수만 — 자체합성 금지) ===\n")
perf <- rbindlist(lapply(P2$ARMS, function(a) {
  pr <- RES[[a]]$period_returns
  x  <- xts(pr$ret_net, order.by = as.Date(pr$date))
  xa <- xts(pr$ret_net - pr$benchmark_ret, order.by = as.Date(pr$date))
  ta <- table.AnnualizedReturns(x, scale = 12); taa <- table.AnnualizedReturns(xa, scale = 12)
  mdd <- as.numeric(maxDrawdown(x)); cagr <- as.numeric(ta[1,1])
  data.table(arm = a, cagr = cagr, total_sr = as.numeric(ta[3,1]), mdd = mdd,
             calmar = if (mdd > 0) cagr/mdd else NA_real_,
             active_ir = as.numeric(taa[3,1]), active_cagr = as.numeric(taa[1,1]),
             port_t_capw = RES[[a]]$portfolio_alpha_t_nw_lag3, turnover = RES[[a]]$turnover_annual)
}))
print(perf); res4$perf <- perf
cat("  ★graduation HARD 3종(PORT_t 2.95 · oos_retention 0.7 · calmar 0.64)은 forge-authoritative 값에만 적용 —\n")
cat("    위 수치는 metric_type='canonical_screen' 스크리닝 실측이며 졸업을 주장하지 않는다.\n")

cat("\n=== 2) co-primary 신뢰구간 (연율, NW lag-3 se) — '미결로 남는 폭' 을 수치로 ===\n")
ci <- rbindlist(lapply(names(CP), function(id) { p <- CP[[id]]
  se_m <- abs(p$mean_m)/abs(p$t_nw3); lo <- (p$mean_m - 1.96*se_m)*12*100; hi <- (p$mean_m + 1.96*se_m)*12*100
  data.table(contrast = id, ann_pct = p$ann_pct, se_ann_pct = se_m*12*100, ci95_lo = lo, ci95_hi = hi,
             mde_ann_pct = GATE[grepl(if (id=="A") "^SEL_PEARSON" else "^SEL_MEANDEPTH", contrast), mde_annual_pct]) }))
print(ci); res4$ci <- ci

cat("\n=== 3) ★3-basis 대조 (mandate: basis 라벨 없는 수치는 게이트 근거가 못 된다) ===\n")
p0 <- readRDS(file.path(OUT, "p0_returns.rds"))
bench_parent <- as.data.table(p0$bench)[, .(Date, BM_Ret)]
bd_iks <- P2$bench_dt
cmp_b <- merge(bd_iks[, .(Date, iks = BM_Ret)], bench_parent[, .(Date, parent = BM_Ret)], by = "Date")
cmp_b <- cmp_b[Date %in% RES$SEL_RANK$period_returns$date]
cat(sprintf("  측정창 %d개월 · IKS200(.cache/benchmark.parquet) 연 %.3f%%  vs  parent K200∪KQ150 cap-w 연 %.3f%%  (격차 %+.3f%%p)\n",
            nrow(cmp_b), (prod(1+cmp_b$iks)^(12/nrow(cmp_b))-1)*100, (prod(1+cmp_b$parent)^(12/nrow(cmp_b))-1)*100,
            ((prod(1+cmp_b$iks)^(12/nrow(cmp_b))-1) - (prod(1+cmp_b$parent)^(12/nrow(cmp_b))-1))*100))
b3 <- rbindlist(lapply(PRIM, function(a) {
  r2 <- canonical_screen_bt(SC[[a]], P2$returns_dt, bench_parent, top_n = P2$TOPN,
                            cost_bps_oneway = P2$COST, strategy_id = paste0("FQ237B_", a),
                            run_id = paste0("FQ237B_", a), diag_dual_basis = FALSE)
  data.table(arm = a, port_t_IKS200 = RES[[a]]$portfolio_alpha_t_nw_lag3,
             port_t_parent_capw = r2$portfolio_alpha_t_nw_lag3,
             port_t_EW_universe = RES[[a]]$diag_ew_universe$portfolio_alpha_t_nw_lag3,
             ir_IKS200 = RES[[a]]$net_sr, ir_parent = r2$net_sr) }))
print(b3); res4$basis3 <- b3
cat("  ★canonical_screen_bt 는 호출자가 넘긴 계열에 라벨 'KOSPI200_total_return' 을 **하드코딩**한다 —\n")
cat("    본 라운드 primary 가 실제로 넘긴 것은 .cache/benchmark.parquet(build_index_cache.py Code-매칭 IKS200).\n")

cat("\n=== 4) R1 강건성 — 유동성 필터 adv20_t1 >= 2e8 적용판 (비바인딩) ===\n")
liq <- as.data.table(p0$liq)[, .(Date, Ticker = as.character(Ticker), adv)]
cat(sprintf("  liq 축 덮개: 측정 %d개월 중 liq 보유 %d개월 · liq_ruler=%s\n",
            uniqueN(SC$SEL_RANK$Date), uniqueN(liq[Date %in% SC$SEL_RANK$Date]$Date),
            paste(attr(p0$liq, "liq_ruler", exact = TRUE), collapse = "/")))
R1 <- setNames(lapply(PRIM, function(a)
  canonical_screen_bt(SC[[a]], P2$returns_dt, bd_iks, top_n = P2$TOPN, cost_bps_oneway = P2$COST,
                      liq_dt = liq, liq_min = 2e8, strategy_id = paste0("FQ237L_", a),
                      run_id = paste0("FQ237L_", a), diag_dual_basis = FALSE)), PRIM)
r1tab <- rbindlist(lapply(PRIM, function(a) data.table(arm = a, n = R1[[a]]$n_months,
  port_t = R1[[a]]$portfolio_alpha_t_nw_lag3, ir = R1[[a]]$net_sr,
  dropped_pct = 100*R1[[a]]$liq_filter$n_dropped/R1[[a]]$liq_filter$n_before)))
print(r1tab); res4$R1 <- r1tab
pl <- function(a, b) { m <- merge(R1[[a]]$period_returns[, .(date, ra = ret_net)],
                                  R1[[b]]$period_returns[, .(date, rb = ret_net)], by = "date")
  d <- m$ra - m$rb; list(n = nrow(m), t = .nw_t_mean(d, lag=3L), ann = 100*mean(d)*12) }
for (p in list(c("SEL_PEARSON","SEL_RANK"), c("SEL_MEANDEPTH","SEL_RANK"))) {
  z <- pl(p[1], p[2]); cat(sprintf("  [R1 paired] %-14s - SEL_RANK  n=%d  t %+.4f  연 %+.3f%%p\n", p[1], z$n, z$t, z$ann)) }

cat("\n=== 5) ★반증 축 2 — (Pearson−Spearman) 격차의 비대칭 기원 ===\n")
S1 <- readRDS(file.path(W005, "s1_factor_month_stats.rds")); P1 <- readRDS(file.path(OUT, "p1_pearson_stats.rds"))
G <- merge(S1$FS[, .(anchor, fac, ic)], P1$PS[, .(anchor, fac, ic_pe)], by = c("anchor","fac"))
G <- G[is.finite(ic) & is.finite(ic_pe)][, .(gap = mean(abs(ic_pe - ic)), n_fac = .N), by = anchor]
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
.skew <- function(x) { n <- length(x); if (n < 8L) return(NA_real_); m <- mean(x)
  s <- sqrt(sum((x-m)^2)/n); if (!is.finite(s) || s <= 0) return(NA_real_); sum((x-m)^3)/(n*s^3) }
SK2a <- pan[is.finite(fwd_ret_1m), .(skew_m = .skew(fwd_ret_1m)), by = anchor]
raw <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
                                  col_select = c("Date","Ticker","Ret","K200","KQ150")))
raw[, Date := as.Date(Date)]
raw <- raw[is.finite(Ret) & ((!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1))]
raw[, ym := as.Date(cut(Date, "month"))]
dm <- raw[, .(r = prod(1 + Ret) - 1, nd = .N), by = .(ym, Ticker)][nd >= 10L]
SK2b <- dm[, .(skew_d = .skew(r)), by = .(anchor = ym)]
AX <- merge(merge(G, SK2a, by = "anchor"), SK2b, by = "anchor")
AX <- AX[is.finite(gap) & is.finite(skew_m) & is.finite(skew_d)]
## HAC 계수 t = sandwich::NeweyWest(lag=3, prewhite=FALSE) + lmtest::coeftest (표준 구현 사용,
##   자체 합성 금지). iid t 도 병기해 팽창분을 보이게 한다.
reg_t <- function(y, x) { f <- stats::lm(y ~ x)
  ct <- lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = 3L, prewhite = FALSE, adjust = TRUE))
  list(b = unname(stats::coef(f)[2]), t_iid = unname(summary(f)$coefficients[2,3]),
       t_nw = unname(ct[2,3]), p_nw = unname(ct[2,4])) }
z2a <- reg_t(AX$gap, AX$skew_m); z2b <- reg_t(AX$gap, AX$skew_d)
cat(sprintf("  n=%d개월 · cor(skew_m, skew_d) = %+.4f (2추정기 독립성 대조)\n", nrow(AX),
            stats::cor(AX$skew_m, AX$skew_d)))
cat(sprintf("  (2a) gap ~ 월간CS 왜도   : b %+.6f  t_iid %+.3f  t_NW3 %+.3f  p %.4f\n", z2a$b, z2a$t_iid, z2a$t_nw, z2a$p_nw))
cat(sprintf("  (2b) gap ~ 일간파생 왜도 : b %+.6f  t_iid %+.3f  t_NW3 %+.3f  p %.4f\n", z2b$b, z2b$t_iid, z2b$t_nw, z2b$p_nw))
ar1 <- function(x) stats::cor(x[-1], x[-length(x)])
cat(sprintf("  ★조건변수 AR(1): skew_m %.4f · skew_d %.4f · gap %.4f  ⇒ phi>0.9 축 %d개 (보강 대상)\n",
            ar1(AX$skew_m), ar1(AX$skew_d), ar1(AX$gap),
            sum(c(ar1(AX$skew_m), ar1(AX$skew_d)) > 0.9)))
res4$axis2 <- list(n = nrow(AX), cor_estimators = stats::cor(AX$skew_m, AX$skew_d),
                   a = z2a, b = z2b, ar1 = list(skew_m = ar1(AX$skew_m), skew_d = ar1(AX$skew_d), gap = ar1(AX$gap)))

cat("\n=== 6) DSR 진단 (chain — HARD 아님) ===\n")
dsrt <- rbindlist(lapply(PRIM, function(a) { pr <- RES[[a]]$period_returns
  ac <- pr$ret_net - pr$benchmark_ret
  data.table(arm = a, active_sr_ann = perf[arm == a, active_ir],
             dsr_trials1 = .essence_dsr(perf[arm==a, active_ir], length(ac), 1),
             dsr_trials3 = .essence_dsr(perf[arm==a, active_ir], length(ac), 3)) }))
print(dsrt); res4$dsr <- dsrt

cat("\n=== 7) 산출물 발행 — alpha_scores.parquet (3 primary arm) + live alpha_vector ===\n")
AS <- rbindlist(lapply(PRIM, function(a) SC[[a]][, .(Date, Ticker, alpha_score = score, arm = a)]))
write_parquet(AS, file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("  alpha_scores.parquet: %d행 · %d개월 · arm %d종\n", nrow(AS), uniqueN(AS$Date), uniqueN(AS$arm)))
## live alpha_vector — 2026-08 홀딩월. 선별창 = anchor <= 2026-07-01 실현 통계만(PIT).
FACS <- S1$FACS; anchors <- S1$anchors
to_mat <- function(dt, col) { m <- dcast(dt, anchor ~ fac, value.var = col); a <- m$anchor
  m[, anchor := NULL]; mm <- as.matrix(m); rownames(mm) <- as.character(a); mm[, FACS, drop = FALSE] }
D1 <- readRDS(file.path(W005, "depth_aligned", "d1_depth_stats.rds"))
Mlist <- list(SEL_RANK = to_mat(S1$FS,"ic"), SEL_PEARSON = to_mat(P1$PS,"ic_pe"),
              SEL_MEANDEPTH = to_mat(D1$DS,"meandepth"))
n <- length(anchors); rw <- (n - P2$W + 1L):n     # 2026-07-01 까지 = 홀딩월 2026-08 의 trailing 창
live_anchor <- as.Date("2026-08-01")
panl <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))[, anchor := as.Date(anchor)]
panl <- panl[anchor == live_anchor]
LIVE <- rbindlist(lapply(PRIM, function(a) {
  tv <- apply(Mlist[[a]][rw, , drop=FALSE], 2L, function(x) { x <- x[is.finite(x)]
    if (length(x) < 30L) return(NA_real_); .nw_t_mean(x, lag=3L) })
  ok <- is.finite(tv); fs <- names(sort(tv[ok], decreasing=TRUE))[seq_len(P2$K)]
  if (!nrow(panl)) return(NULL)
  Z <- as.matrix(panl[, ..fs]); sc <- rowMeans(Z, na.rm=TRUE); nv <- rowSums(is.finite(Z))
  data.table(Date = live_anchor, Ticker = as.character(panl$Ticker), arm = a,
             alpha_score = ifelse(nv >= 1L, sc, NA_real_),
             selected = paste(fs, collapse="|"))[is.finite(alpha_score)] }))
if (nrow(LIVE)) { write_parquet(LIVE, file.path(OUT, "alpha_vector_live_202608.parquet"))
  cat(sprintf("  alpha_vector_live_202608.parquet: %d행 · %d종목/arm\n", nrow(LIVE), nrow(LIVE)/length(PRIM)))
  for (a in PRIM) cat(sprintf("    %-14s 선별: %s\n", a, LIVE[arm==a, selected][1])) } else
  cat("  ★live anchor 2026-08-01 패널 부재 — live vector 미발행(정직 결손)\n")
res4$live_selected <- if (nrow(LIVE)) LIVE[, .(sel = selected[1]), by = arm] else NULL

saveRDS(res4, file.path(OUT, "p4_diagnostics.rds"))
cat("\n[saved] p4_diagnostics.rds\n")
