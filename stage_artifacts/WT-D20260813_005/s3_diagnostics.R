## WT-D20260813_005 · S3 — 반증축 ② + advisory 진단 배터리 + 라이브 alpha_vector
##
## 판정 축은 S2 에서 끝났다(primary paired NW3 t). 여기는 **기록 의무** 산출:
##   · 반증축 ②(왜도 프로파일 분기) — 승계 falsification 의 마지막 축
##   · advisory 배터리 (rank_ic / icir / harvey_t / monotonicity / subperiod / post-neutral IC / DSR)
##   · 국면 분해 (advisory — 승계 regime_scope 가 '판정 축 아님' 으로 라벨한 축)
##   · 라이브 alpha_vector / confidence_vector (as_of 2026-08 홀딩월)
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/s3_diagnostics.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/validation/statistical_defense.R")
SRC <- "stage_artifacts/fq233_probe0_20260813"
OUT <- "stage_artifacts/WT-D20260813_005"

S1 <- readRDS(file.path(OUT, "s1_factor_month_stats.rds"))
S2 <- readRDS(file.path(OUT, "s2_walkforward_result.rds"))
SC <- readRDS(file.path(OUT, "s2_scores_all_arms.rds"))
FS <- S1$FS; FACS <- S1$FACS; sel <- S2$sel; RES <- S2$RES; PR <- S2$PR
W <- S2$W; K <- S2$K
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
anchors <- S1$anchors
hold <- S2$hold_anchors
DG <- list()

cat("=== A) 반증축 ② — 왜도 프로파일 분기 ===\n")
## 예측 방향(승계): S_rank-단독 채택 팩터군의 분위 왜도기울기가 S_mean-단독 군보다 **더 음**.
##   (R32 기전: 왜도기울기 음 ↔ 중앙값−평균 gap 양)
## PIT: 각 홀딩월의 trailing W 창 평균 왜도기울기만 사용(선별과 같은 정보집합).
M_ss <- dcast(FS, anchor ~ fac, value.var = "skewslope")
a_ss <- M_ss$anchor; M_ss[, anchor := NULL]; M_ss <- as.matrix(M_ss)[, FACS, drop = FALSE]
rownames(M_ss) <- as.character(a_ss)
idx <- match(as.character(hold), rownames(M_ss))
rows <- lapply(seq_along(hold), function(k) (idx[k]-W):(idx[k]-1))
ss_grp <- rbindlist(lapply(seq_along(hold), function(k) {
  nm <- as.character(hold[k])
  sr <- setdiff(sel$OBJ_RANK[[nm]], sel$OBJ_MEAN[[nm]])   # rank-단독
  sm <- setdiff(sel$OBJ_MEAN[[nm]], sel$OBJ_RANK[[nm]])   # mean-단독
  if (!length(sr) || !length(sm)) return(NULL)
  sub <- M_ss[rows[[k]], , drop = FALSE]
  data.table(anchor = hold[k],
             ss_rank_only = mean(colMeans(sub[, sr, drop=FALSE], na.rm=TRUE), na.rm=TRUE),
             ss_mean_only = mean(colMeans(sub[, sm, drop=FALSE], na.rm=TRUE), na.rm=TRUE))
}))
ss_grp[, diff := ss_rank_only - ss_mean_only]
t_ss <- .nw_t_mean(ss_grp$diff[is.finite(ss_grp$diff)], lag = 3L)
cat(sprintf("  n=%d개월 · 평균 왜도기울기: rank-단독 %+.5f · mean-단독 %+.5f · 차이 %+.5f\n",
            nrow(ss_grp), mean(ss_grp$ss_rank_only, na.rm=TRUE), mean(ss_grp$ss_mean_only, na.rm=TRUE),
            mean(ss_grp$diff, na.rm=TRUE)))
ax2_dir_ok <- is.finite(t_ss) && mean(ss_grp$diff, na.rm=TRUE) < 0
ax2_sig    <- is.finite(t_ss) && t_ss <= -2
cat(sprintf("  NW3 t(차이) = %+.4f · 예측 방향(음) %s · |t|>=2 %s\n", t_ss,
            if (ax2_dir_ok) "일치" else "★불일치", if (ax2_sig) "충족" else "미충족"))
cat(sprintf("  ⇒ 반증축 ② : %s\n", if (!ax2_dir_ok || !ax2_sig)
      "★발화(방향 불일치 또는 구분 불가) — 기전의 왜도-드라이버 서사 기각" else "통과"))
DG$falsification_2 <- list(n_months = nrow(ss_grp), mean_rank_only = mean(ss_grp$ss_rank_only, na.rm=TRUE),
                           mean_mean_only = mean(ss_grp$ss_mean_only, na.rm=TRUE),
                           mean_diff = mean(ss_grp$diff, na.rm=TRUE), nw3_t = t_ss,
                           direction_ok = ax2_dir_ok, significant = ax2_sig,
                           fired = (!ax2_dir_ok || !ax2_sig))

cat("\n=== B) advisory 진단 배터리 (선택 권위 아님 — measurement-graduation §3) ===\n")
fwd <- pan[anchor %in% anchors, .(Date = anchor, Ticker = as.character(Ticker), fwd = fwd_ret_1m)][is.finite(fwd)]
size_dt <- pan[anchor %in% anchors, .(Date = anchor, Ticker = as.character(Ticker),
                                      sz = S01_Size, bt = D02_Beta)]
diag_arm <- function(a) {
  j <- merge(SC[[a]], fwd, by = c("Date","Ticker"))
  ic <- j[, .(ic = if (.N >= 30 && sd(score) > 0) cor(rank(score), rank(fwd)) else NA_real_), by = Date]
  rank_ic <- mean(ic$ic, na.rm = TRUE); icir <- rank_ic / sd(ic$ic, na.rm = TRUE)
  harvey_t <- .nw_t_mean(ic$ic[is.finite(ic$ic)], lag = 3L)
  ## monotonicity — 분위(5) 평균 forward 의 분위지수 대비 Spearman (월별 → 평균)
  mono <- j[, { q <- pmin(5L, as.integer(ceiling(rank(score, ties.method="average")/.N*5)))
                mr <- tapply(fwd, q, mean)
                if (length(mr) < 5) NA_real_ else cor(as.numeric(names(mr)), mr, method="spearman") },
            by = Date]
  monotonicity <- mean(mono$V1, na.rm = TRUE)
  ## subperiod stability — 3구간 rank-IC 부호/크기 안정성 = min/max (음수면 0)
  ic[, sp := ifelse(Date < as.Date("2015-01-01"), 1L, ifelse(Date < as.Date("2020-01-01"), 2L, 3L))]
  spi <- ic[, .(m = mean(ic, na.rm=TRUE)), by = sp][order(sp)]
  stab <- if (min(spi$m) <= 0) 0 else min(spi$m)/max(spi$m)
  ## post-neutralization IC — 월별 횡단면에서 size(S01_Size)+beta(D02_Beta) 잔차화 후 IC
  jn <- merge(j, size_dt, by = c("Date","Ticker"))
  pn <- jn[, { ok <- is.finite(score) & is.finite(sz) & is.finite(bt) & is.finite(fwd)
               if (sum(ok) < 30) NA_real_ else {
                 r <- residuals(lm(score[ok] ~ sz[ok] + bt[ok]))
                 if (sd(r) <= 0) NA_real_ else cor(rank(r), rank(fwd[ok])) } }, by = Date]
  post_ic <- mean(pn$V1, na.rm = TRUE)
  list(rank_ic = rank_ic, icir = icir, harvey_t = harvey_t, monotonicity = monotonicity,
       subperiod = list(sp1 = spi$m[1], sp2 = spi$m[2], sp3 = spi$m[3], stability = stab),
       post_neutralization_ic = post_ic, ic_series = ic)
}
D <- lapply(setNames(c("OBJ_RANK","OBJ_MEAN","OBJ_MED"), c("OBJ_RANK","OBJ_MEAN","OBJ_MED")), diag_arm)
for (a in names(D)) cat(sprintf("  %-9s rank_ic %+.5f · ICIR %+.4f · harvey_t %+.3f · mono %+.3f · subper(%.4f/%.4f/%.4f, stab %.3f) · postNeutIC %+.5f\n",
    a, D[[a]]$rank_ic, D[[a]]$icir, D[[a]]$harvey_t, D[[a]]$monotonicity,
    D[[a]]$subperiod$sp1, D[[a]]$subperiod$sp2, D[[a]]$subperiod$sp3, D[[a]]$subperiod$stability,
    D[[a]]$post_neutralization_ic))
DG$advisory <- lapply(D, function(x) x[setdiff(names(x), "ic_series")])

cat("\n=== C) DSR (selection_type=chain → advisory·진단 산출) ===\n")
for (a in c("OBJ_RANK","OBJ_MEAN")) {
  p <- as.data.table(RES[[a]]$period_returns); act <- p$ret_net - p$benchmark_ret
  sr_m <- mean(act)/sd(act)                       # 월간 active SR (연율화 전)
  d1 <- compute_dsr(observed_sr = sr_m, n_obs = length(act), n_trials = 1)
  d3 <- compute_dsr(observed_sr = sr_m, n_obs = length(act), n_trials = 3)
  cat(sprintf("  %-9s active SR(월) %+.4f n=%d → DSR(n_trials=1) %.4f · DSR(n_trials=3) %.4f\n",
              a, sr_m, length(act), d1$dsr, d3$dsr))
  DG$dsr[[a]] <- list(active_sr_monthly = sr_m, n_obs = length(act),
                      dsr_trials1 = d1$dsr, dsr_trials3 = d3$dsr,
                      note = "chain → 게이트 아님(measurement-graduation §3). n_trials=3 은 arm 3종을 보수적으로 센 경우")
}

cat("\n=== D) 국면 분해 (advisory — 승계 regime_scope 가 '판정 축 아님' 라벨) ===\n")
msm <- as.data.table(read_parquet(".cache/msm_daily_latest.parquet"))[, .(Date = as.Date(Date), Crisis_Prob)]
## PIT: 홀딩월 시작 **전** 마지막 관측만 (C5 — 홀딩월 정보로 그 달을 라벨하지 않는다)
lab <- rbindlist(lapply(hold, function(a) {
  v <- msm[Date < a][.N, Crisis_Prob]
  data.table(date = a, crisis_prob = if (length(v)) v else NA_real_)
}))
lab[, crisis := is.finite(crisis_prob) & crisis_prob >= 0.5]
cat(sprintf("  crisis 라벨 %d/%d개월 (%.1f%%) · 라벨 원천 msm_daily_latest, 홀딩월 시작 전 최종관측\n",
            sum(lab$crisis), nrow(lab), 100*mean(lab$crisis)))
dpair <- data.table(date = PR$OBJ_MEAN$date, d = PR$OBJ_MEAN$d)
dpair <- merge(dpair, lab[, .(date, crisis)], by = "date")
for (g in c(FALSE, TRUE)) {
  x <- dpair[crisis == g, d]
  cat(sprintf("  %-9s n=%3d · 월평균차 %+.5f · NW3 t %+.4f\n",
              if (g) "crisis" else "non-crisis", length(x), mean(x), .nw_t_mean(x, lag=3L)))
}
DG$regime_advisory <- list(
  source = ".cache/msm_daily_latest.parquet (Crisis_Prob >= 0.5, 홀딩월 시작 전 최종관측)",
  n_crisis = sum(lab$crisis), n_total = nrow(lab),
  noncrisis = list(n = dpair[crisis==FALSE, .N], mean = dpair[crisis==FALSE, mean(d)],
                   nw3_t = .nw_t_mean(dpair[crisis==FALSE, d], lag=3L)),
  crisis = list(n = dpair[crisis==TRUE, .N], mean = dpair[crisis==TRUE, mean(d)],
                nw3_t = .nw_t_mean(dpair[crisis==TRUE, d], lag=3L)),
  caveat = "에피소드 수 병목 — 승계 preregistration 이 '판정 축 아님' 으로 사전 라벨. 검정력 낮음.")

cat("\n=== E) 선별 팩터 family 구성 (AX-001 v2 scope 판정 입력) ===\n")
fam <- function(f) sub("[0-9].*", "", f)
comp <- rbindlist(lapply(c("OBJ_RANK","OBJ_MEAN","OBJ_MED"), function(a) {
  tb <- table(fam(unlist(sel[[a]])))
  data.table(arm = a, family = names(tb), n = as.integer(tb))[order(-n)][1:6] }))
print(comp)
top_fam <- comp[arm == "OBJ_MEAN"][1]
DG$family_composition <- comp
cat(sprintf("  OBJ_MEAN 최빈 family = %s (%d/%d 선별슬롯, %.1f%%)\n", top_fam$family, top_fam$n,
            length(unlist(sel$OBJ_MEAN)), 100*top_fam$n/length(unlist(sel$OBJ_MEAN))))
cat("  ※ D-접두 = 변동성/베타(방어 계열). 방어 지배 시 AX-001 v2 조건부 축 기록 의무 —\n")
cat("     본 산출물은 standalone 전략 승격 주장이 아니라 **선별층 실험**이므로 자본 판정 축 아님.\n")

cat("\n=== F) AX-001 v2 조건부 축 (방어 계열 지배 시 기록) ===\n")
p_mean <- as.data.table(RES$OBJ_MEAN$period_returns); p_rank <- as.data.table(RES$OBJ_RANK$period_returns)
pm <- merge(p_mean[, .(date, act_mean = ret_net - benchmark_ret)],
            lab[, .(date, crisis)], by = "date")
pr2 <- merge(p_rank[, .(date, act_rank = ret_net - benchmark_ret)], lab[, .(date, crisis)], by = "date")
ca_mean <- pm[crisis == TRUE, mean(act_mean)]; ca_rank <- pr2[crisis == TRUE, mean(act_rank)]
ic_bad <- merge(D$OBJ_MEAN$ic_series[, .(date = Date, ic)], lab[, .(date, crisis)], by = "date")
r_badnorm <- ic_bad[crisis==TRUE, mean(ic, na.rm=TRUE)] / ic_bad[crisis==FALSE, mean(ic, na.rm=TRUE)]
cat(sprintf("  crisis_alpha(월평균 active): OBJ_MEAN %+.5f · OBJ_RANK %+.5f\n", ca_mean, ca_rank))
cat(sprintf("  bad/normal rank-IC 비율(OBJ_MEAN): %+.4f\n", r_badnorm))
DG$ax001_v2 <- list(applicable_note = "선별층 실험 — standalone 방어형 팩터 승격 주장 아님. 조건부 축은 기록 목적.",
                    crisis_alpha_mean_arm = ca_mean, crisis_alpha_rank_arm = ca_rank,
                    bad_normal_ic_ratio = r_badnorm)

cat("\n=== G) 라이브 alpha_vector / confidence_vector (as_of 홀딩월 2026-08) ===\n")
## 선별창 = 2026-07 까지의 완결 통계 36개월(전부 실현). 스코어 = 2026-08-01 anchor 의 z.
M_ms <- dcast(FS, anchor ~ fac, value.var = "meanspread")
a_ms <- M_ms$anchor; M_ms[, anchor := NULL]; M_ms <- as.matrix(M_ms)[, FACS, drop=FALSE]
rownames(M_ms) <- as.character(a_ms)
nlast <- nrow(M_ms)
tv <- apply(M_ms[(nlast-W+1):nlast, , drop=FALSE], 2L, function(x){ x<-x[is.finite(x)]
  if (length(x) < 30L) return(NA_real_); .nw_t_mean(x, lag=3L) })
live_sel <- names(sort(tv[is.finite(tv)], decreasing = TRUE))[seq_len(K)]
cat(sprintf("  선별창 %s ~ %s → 선별 K=%d: %s\n", rownames(M_ms)[nlast-W+1], rownames(M_ms)[nlast],
            K, paste(live_sel, collapse=", ")))
LIVE_ANCHOR <- as.Date("2026-08-01")
pl <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pl[, anchor := as.Date(anchor)]; pl <- pl[anchor == LIVE_ANCHOR]
Z <- as.matrix(pl[, ..live_sel])
sc <- rowMeans(Z, na.rm = TRUE); nv <- rowSums(is.finite(Z))
live <- data.table(Ticker = as.character(pl$Ticker), score = sc, n_valid = nv)[nv >= 1L & is.finite(score)]
## α̂ 스케일 — trailing 창의 Fama-MacBeth 형 횡단면 기울기 평균(수익/스코어 1단위), PIT-safe
jj <- merge(SC$OBJ_MEAN, fwd, by = c("Date","Ticker"))
slope <- jj[Date > max(Date) - 3650, { ok <- is.finite(score) & is.finite(fwd)
             if (sum(ok) < 30) NA_real_ else unname(coef(lm(fwd[ok] ~ score[ok]))[2]) }, by = Date]
b <- mean(slope$V1, na.rm = TRUE)
live[, alpha_hat := b * score]
## confidence — 유효 팩터 수 + 스코어 횡단면 안정성(스코어 절대크기 백분위) 결합, [0,1]
live[, conf := pmin(1, pmax(0, 0.5 * (n_valid / K) + 0.5 * (rank(abs(score))/.N)))]
cat(sprintf("  라이브 종목 %d · α̂ 평균 %+.4f%% · 스케일 b = %+.5f (trailing 10y FM 기울기 평균)\n",
            nrow(live), 100*mean(live$alpha_hat), b))
cat(sprintf("  상위 5: %s\n", paste(head(live[order(-alpha_hat), Ticker], 5), collapse=", ")))
DG$live <- list(as_of_holding_month = as.character(LIVE_ANCHOR), selected_factors = live_sel,
                n_names = nrow(live), fm_slope = b,
                alpha_mean = mean(live$alpha_hat), alpha_sd = sd(live$alpha_hat))

cat("\n=== H) dual-basis 진단 (v8.3 M2 — cap-w 판정 불변, 병기 전용) ===\n")
for (a in c("OBJ_RANK","OBJ_MEAN")) {
  ew <- RES[[a]]$diag_ew_universe
  cat(sprintf("  %-9s cap-w PORT_t %+.4f | EW-유니버스 대비 PORT_t %s (n=%s)\n", a,
              RES[[a]]$portfolio_alpha_t_nw_lag3,
              if (!is.null(ew$portfolio_alpha_t_nw_lag3)) sprintf("%+.4f", ew$portfolio_alpha_t_nw_lag3) else "NA",
              if (!is.null(ew$n_months)) ew$n_months else "NA"))
  DG$dual_basis[[a]] <- list(capw_port_t = RES[[a]]$portfolio_alpha_t_nw_lag3,
                             ew_universe_port_t = ew$portfolio_alpha_t_nw_lag3,
                             ew_n_months = ew$n_months)
}

saveRDS(list(DG = DG, live = live, ss_grp = ss_grp, ic_series = lapply(D, `[[`, "ic_series")),
        file.path(OUT, "s3_diagnostics.rds"))
write_parquet(live[, .(Ticker, score, n_valid, alpha_hat, confidence = conf)],
              file.path(OUT, "alpha_vector_live_202608.parquet"))
cat(sprintf("\n저장: s3_diagnostics.rds · alpha_vector_live_202608.parquet\n"))
