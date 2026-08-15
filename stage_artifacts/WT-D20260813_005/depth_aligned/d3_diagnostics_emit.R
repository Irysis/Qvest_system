## WT-D20260813_005 후속 · D3 — 진단 배터리 + 산출물 발행
##
## 판정 축은 D2 에서 끝났다(primary paired NW3 t = +1.5706 < 문턱 +2.0 → NOT_SUPPORTED).
## 여기는 **기록 의무** + 자기비판이 요구한 견고성 진단:
##   · 깊이 효과의 견고성 (부기간 · 양수월 비중 · 영향월 제거 · 국면)
##   · advisory 배터리 (rank_ic/ICIR/harvey_t/mono/subperiod/post-neutral IC) · DSR(진단)
##   · dual-basis (cap-w 판정 불변, EW-유니버스 병기) · family 구성 · AX-001 v2 조건부 축
##   · 라이브 alpha_vector / confidence_vector (계약 형태 유지)
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/depth_aligned/d3_diagnostics_emit.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/validation/statistical_defense.R")
SRC  <- "stage_artifacts/fq233_probe0_20260813"
OUT  <- "stage_artifacts/WT-D20260813_005"
DOUT <- file.path(OUT, "depth_aligned")

S1 <- readRDS(file.path(OUT, "s1_factor_month_stats.rds"))
D1 <- readRDS(file.path(DOUT, "d1_depth_stats.rds"))
D2 <- readRDS(file.path(DOUT, "d2_result.rds"))
SC <- readRDS(file.path(DOUT, "d2_scores_all_arms.rds"))
FS <- S1$FS; FACS <- S1$FACS; anchors <- S1$anchors
sel <- D2$sel; RES <- D2$RES; PR <- D2$PR; W <- D2$W; K <- D2$K
hold <- D2$hold_anchors
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
DG <- list()

cat("=== A) 깊이 효과의 견고성 (자기비판 주도 — 판정 변경 아님, 견고성 기록) ===\n")
d  <- PR$OBJ_MEAN_DEPTH$d; dt_ <- PR$OBJ_MEAN_DEPTH$date
dq <- PR$OBJ_MEAN_Q5$d
pos <- mean(d > 0)
cat(sprintf("  양수월 비중 %.1f%% (n=%d) · 월평균차 %+.5f · 중앙값 %+.5f\n",
            100*pos, length(d), mean(d), median(d)))
## 부기간 3분할 (사전등록된 subperiod 규약과 같은 절단)
spg <- ifelse(dt_ < as.Date("2015-01-01"), 1L, ifelse(dt_ < as.Date("2020-01-01"), 2L, 3L))
sp <- rbindlist(lapply(1:3, function(g) data.table(sp = g, n = sum(spg==g),
        mean = mean(d[spg==g]), t = .nw_t_mean(d[spg==g], lag=3L))))
print(sp)
## 영향월 진단 — 상위 |차이| 월을 빼면 t 가 남는가 (꼬리 구동 기전이므로 '남지 않음' 도 정보)
infl <- rbindlist(lapply(c(0L,1L,3L,5L), function(kk) {
  keep <- if (kk == 0L) rep(TRUE, length(d)) else !(seq_along(d) %in% head(order(-abs(d)), kk))
  data.table(dropped = kk, n = sum(keep), mean = mean(d[keep]), t = .nw_t_mean(d[keep], lag=3L))
}))
print(infl)
top3_share <- sum(sort(d, decreasing = TRUE)[1:3]) / sum(d)
cat(sprintf("  상위 3개월이 누적차의 %.1f%% 를 설명 (꼬리 집중도)\n", 100*top3_share))
DG$robustness <- list(pos_share = pos, mean = mean(d), median = median(d),
                      subperiod = sp, influence = infl, top3_share_of_sum = top3_share)

cat("\n=== B) 국면 분해 (advisory — 승계 regime_scope 가 '판정 축 아님' 라벨) ===\n")
msm <- as.data.table(read_parquet(".cache/msm_daily_latest.parquet"))[, .(Date = as.Date(Date), Crisis_Prob)]
lab <- rbindlist(lapply(hold, function(a) { v <- msm[Date < a][.N, Crisis_Prob]   # C5: 홀딩월 시작 전 최종관측
  data.table(date = a, crisis_prob = if (length(v)) v else NA_real_) }))
lab[, crisis := is.finite(crisis_prob) & crisis_prob >= 0.5]
dp <- merge(data.table(date = dt_, d = d, dq = dq), lab[, .(date, crisis)], by = "date")
for (g in c(FALSE, TRUE)) {
  x <- dp[crisis == g, d]; xq <- dp[crisis == g, dq]
  cat(sprintf("  %-10s n=%3d · DEPTH %+.5f (t %+.4f) · Q5 %+.5f (t %+.4f)\n",
              if (g) "crisis" else "non-crisis", length(x), mean(x), .nw_t_mean(x, lag=3L),
              mean(xq), .nw_t_mean(xq, lag=3L)))
}
DG$regime_advisory <- list(source = ".cache/msm_daily_latest.parquet (Crisis_Prob>=0.5, 홀딩월 시작 전 최종관측)",
  n_crisis = sum(lab$crisis), n_total = nrow(lab),
  noncrisis = list(n = dp[crisis==FALSE,.N], mean = dp[crisis==FALSE, mean(d)],
                   nw3_t = .nw_t_mean(dp[crisis==FALSE, d], lag=3L)),
  crisis = list(n = dp[crisis==TRUE,.N], mean = dp[crisis==TRUE, mean(d)],
                nw3_t = .nw_t_mean(dp[crisis==TRUE, d], lag=3L)),
  caveat = "에피소드 수 병목 — 판정 축 아님(사전 라벨). 검정력 낮음.")

cat("\n=== C) advisory 배터리 (선택 권위 아님 — measurement-graduation §3) ===\n")
fwd <- pan[anchor %in% anchors, .(Date = anchor, Ticker = as.character(Ticker), fwd = fwd_ret_1m)][is.finite(fwd)]
size_dt <- pan[anchor %in% anchors, .(Date = anchor, Ticker = as.character(Ticker), sz = S01_Size, bt = D02_Beta)]
diag_arm <- function(a) {
  j <- merge(SC[[a]], fwd, by = c("Date","Ticker"))
  ic <- j[, .(ic = if (.N >= 30 && sd(score) > 0) cor(rank(score), rank(fwd)) else NA_real_), by = Date]
  rank_ic <- mean(ic$ic, na.rm=TRUE); icir <- rank_ic / sd(ic$ic, na.rm=TRUE)
  harvey_t <- .nw_t_mean(ic$ic[is.finite(ic$ic)], lag = 3L)
  mono <- j[, { q <- pmin(5L, as.integer(ceiling(rank(score, ties.method="average")/.N*5)))
                mr <- tapply(fwd, q, mean)
                if (length(mr) < 5) NA_real_ else cor(as.numeric(names(mr)), mr, method="spearman") }, by = Date]
  ic[, sp := ifelse(Date < as.Date("2015-01-01"), 1L, ifelse(Date < as.Date("2020-01-01"), 2L, 3L))]
  spi <- ic[, .(m = mean(ic, na.rm=TRUE)), by = sp][order(sp)]
  stab <- if (min(spi$m) <= 0) 0 else min(spi$m)/max(spi$m)
  jn <- merge(j, size_dt, by = c("Date","Ticker"))
  pn <- jn[, { ok <- is.finite(score) & is.finite(sz) & is.finite(bt) & is.finite(fwd)
               if (sum(ok) < 30) NA_real_ else { r <- residuals(lm(score[ok] ~ sz[ok] + bt[ok]))
                 if (sd(r) <= 0) NA_real_ else cor(rank(r), rank(fwd[ok])) } }, by = Date]
  list(rank_ic = rank_ic, icir = icir, harvey_t = harvey_t, monotonicity = mean(mono$V1, na.rm=TRUE),
       subperiod = list(sp1=spi$m[1], sp2=spi$m[2], sp3=spi$m[3], stability=stab),
       post_neutralization_ic = mean(pn$V1, na.rm=TRUE), ic_series = ic)
}
AN <- c("OBJ_RANK","OBJ_MEAN_DEPTH","OBJ_MEAN_Q5","OBJ_MED_DEPTH")
D <- lapply(setNames(AN, AN), diag_arm)
for (a in AN) cat(sprintf("  %-16s rank_ic %+.5f · ICIR %+.4f · harvey_t %+.3f · mono %+.3f · subper(%.4f/%.4f/%.4f, stab %.3f) · postNeutIC %+.5f\n",
    a, D[[a]]$rank_ic, D[[a]]$icir, D[[a]]$harvey_t, D[[a]]$monotonicity,
    D[[a]]$subperiod$sp1, D[[a]]$subperiod$sp2, D[[a]]$subperiod$sp3, D[[a]]$subperiod$stability,
    D[[a]]$post_neutralization_ic))
DG$advisory <- lapply(D, function(x) x[setdiff(names(x), "ic_series")])

cat("\n=== D) DSR (selection_type=chain → 게이트 아님, 진단 산출) ===\n")
for (a in c("OBJ_RANK","OBJ_MEAN_DEPTH","OBJ_MEAN_Q5")) {
  p <- as.data.table(RES[[a]]$period_returns); ac <- p$ret_net - p$benchmark_ret
  sr_m <- mean(ac)/sd(ac)
  d1 <- compute_dsr(observed_sr = sr_m, n_obs = length(ac), n_trials = 1)
  d4 <- compute_dsr(observed_sr = sr_m, n_obs = length(ac), n_trials = 4)
  cat(sprintf("  %-16s active SR(월) %+.4f n=%d → DSR(1) %.4f · DSR(4) %.4f\n", a, sr_m, length(ac), d1$dsr, d4$dsr))
  DG$dsr[[a]] <- list(active_sr_monthly = sr_m, n_obs = length(ac), dsr_trials1 = d1$dsr, dsr_trials4 = d4$dsr,
    note = "chain → 게이트 아님(measurement-graduation §3). n_trials=4 는 판정 후보 arm 4종을 보수적으로 센 경우(주입/LAG1 대조군 제외)")
}

cat("\n=== E) dual-basis (cap-w 판정 불변 · EW-유니버스 병기, v8.3 M2) ===\n")
for (a in AN) {
  ew <- RES[[a]]$diag_ew_universe
  cat(sprintf("  %-16s cap-w PORT_t %+.4f | EW-유니버스 PORT_t %s (n=%s)\n", a,
              RES[[a]]$portfolio_alpha_t_nw_lag3,
              if (!is.null(ew$portfolio_alpha_t_nw_lag3)) sprintf("%+.4f", ew$portfolio_alpha_t_nw_lag3) else "NA",
              if (!is.null(ew$n_months)) ew$n_months else "NA"))
  DG$dual_basis[[a]] <- list(capw_port_t = RES[[a]]$portfolio_alpha_t_nw_lag3,
                             ew_universe_port_t = ew$portfolio_alpha_t_nw_lag3, ew_n_months = ew$n_months)
}

cat("\n=== F) 선별 family 구성 + AX-001 v2 조건부 축 ===\n")
fam <- function(f) sub("[0-9].*", "", f)
comp <- rbindlist(lapply(AN, function(a) { tb <- sort(table(fam(unlist(sel[[a]]))), decreasing=TRUE)
  data.table(arm = a, family = names(tb), n = as.integer(tb))[1:5] }))
print(comp)
DG$family_composition <- comp
p_dep <- as.data.table(RES$OBJ_MEAN_DEPTH$period_returns); p_rnk <- as.data.table(RES$OBJ_RANK$period_returns)
pm <- merge(p_dep[, .(date, a = ret_net - benchmark_ret)], lab[, .(date, crisis)], by="date")
pr2 <- merge(p_rnk[, .(date, a = ret_net - benchmark_ret)], lab[, .(date, crisis)], by="date")
icb <- merge(D$OBJ_MEAN_DEPTH$ic_series[, .(date = Date, ic)], lab[, .(date, crisis)], by="date")
DG$ax001_v2 <- list(applicable_note = "선별층 실험 — standalone 방어형 팩터 승격 주장 아님. 조건부 축은 기록 목적.",
  crisis_alpha_depth_arm = pm[crisis==TRUE, mean(a)], crisis_alpha_rank_arm = pr2[crisis==TRUE, mean(a)],
  bad_normal_ic_ratio = icb[crisis==TRUE, mean(ic, na.rm=TRUE)] / icb[crisis==FALSE, mean(ic, na.rm=TRUE)])
cat(sprintf("  crisis_alpha: DEPTH %+.5f · RANK %+.5f · bad/normal IC ratio %+.4f\n",
            DG$ax001_v2$crisis_alpha_depth_arm, DG$ax001_v2$crisis_alpha_rank_arm, DG$ax001_v2$bad_normal_ic_ratio))

cat("\n=== G) 라이브 alpha_vector / confidence_vector (as_of 홀딩월 2026-08) ===\n")
M_dp <- dcast(D1$DS, anchor ~ fac, value.var = "meandepth")
a_dp <- M_dp$anchor; M_dp[, anchor := NULL]; M_dp <- as.matrix(M_dp)[, FACS, drop=FALSE]
rownames(M_dp) <- as.character(a_dp)
nl <- nrow(M_dp)
tv <- apply(M_dp[(nl-W+1):nl, , drop=FALSE], 2L, function(x){ x <- x[is.finite(x)]
  if (length(x) < 30L) return(NA_real_); .nw_t_mean(x, lag=3L) })
live_sel <- names(sort(tv[is.finite(tv)], decreasing=TRUE))[seq_len(K)]
cat(sprintf("  선별창 %s ~ %s → K=%d: %s\n", rownames(M_dp)[nl-W+1], rownames(M_dp)[nl], K,
            paste(live_sel, collapse=", ")))
LIVE <- as.Date("2026-08-01")
pl <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pl[, anchor := as.Date(anchor)]; pl <- pl[anchor == LIVE]
Z <- as.matrix(pl[, ..live_sel]); sc <- rowMeans(Z, na.rm=TRUE); nv <- rowSums(is.finite(Z))
live <- data.table(Ticker = as.character(pl$Ticker), score = sc, n_valid = nv)[nv >= 1L & is.finite(score)]
## α̂ 스케일 — 전기간 Fama-MacBeth 형 횡단면 기울기 평균 (창 선택을 자유 파라미터로 두지 않는다)
jj <- merge(SC$OBJ_MEAN_DEPTH, fwd, by = c("Date","Ticker"))
slope <- jj[, { ok <- is.finite(score) & is.finite(fwd)
  if (sum(ok) < 30) NA_real_ else unname(coef(lm(fwd[ok] ~ score[ok]))[2]) }, by = Date]
b_all <- mean(slope$V1, na.rm=TRUE)
b10 <- mean(slope[Date > max(Date) - 3650, V1], na.rm=TRUE); b5 <- mean(slope[Date > max(Date) - 1825, V1], na.rm=TRUE)
live[, alpha_hat := b_all * score]
live[, conf := pmin(1, pmax(0, 0.5*(n_valid/K) + 0.5*(rank(abs(score))/.N)))]
cat(sprintf("  라이브 %d종목 · α̂ 평균 %+.4f%% · 스케일 b(전기간) %+.6f (10y %+.6f · 5y %+.6f — 창 민감)\n",
            nrow(live), 100*mean(live$alpha_hat), b_all, b10, b5))
DG$live <- list(as_of_holding_month = as.character(LIVE), selected_factors = live_sel, n_names = nrow(live),
                fm_slope_full = b_all, fm_slope_10y = b10, fm_slope_5y = b5,
                alpha_mean = mean(live$alpha_hat), alpha_sd = sd(live$alpha_hat),
                caveat = "배포 근거 아님 — 본 라운드 primary 는 NOT_SUPPORTED, cap-w PORT_t 1.78 << 2.95")

saveRDS(list(DG = DG, live = live, ic_series = lapply(D, `[[`, "ic_series")),
        file.path(DOUT, "d3_diagnostics.rds"))
write_parquet(live[, .(Ticker, score, n_valid, alpha_hat, confidence = conf)],
              file.path(DOUT, "alpha_vector_live_202608_depth.parquet"))
cat(sprintf("\n저장: %s/d3_diagnostics.rds · alpha_vector_live_202608_depth.parquet\n", DOUT))
