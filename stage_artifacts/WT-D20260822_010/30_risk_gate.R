## WT-D20260822_010 — risk 층 착수 전 크기 관문 (NP4 규약 risk 번역)  [v2]
## 사전등록: stage_artifacts/WT-D20260822_010/30_risk_PREREG.json (실행 전 봉인 완료)
## ★처치(augmented) 위험모델을 추정하지 않는다 — 예측자-측 진단 + 순열 잡음 + 선행 실측 인용만.
## v2 수리 2건 (v1 자가적발):
##   (1) frollmean(n=60) 이 완전창을 요구해 '최소 24개월' 의도가 무효 → hist_n 이 전부 정확히 60,
##       패널 54%/208월로 절단되고 장수-티커 편중. adaptive 창(min 18, max 60)으로 교체.
##   (2) M0 가 정규근사라 꼬리 수준을 ~2배 과대예측 → '이미 채우는 몫' 비교가 수준 오차에 오염.
##       PIT-확장창 표준화잔차 경험분포로 캘리브레이션.
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
say  <- function(f, ...) cat(sprintf(paste0("[gate2] ", f, "\n"), ...))
set.seed(20260822)
J <- list(script_version = "v2", fixes = c("adaptive_rolling_window_min18", "PIT_expanding_empirical_calibration"))

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
MDE80 <- function(sd_monthly, n) 2.802 * sd_monthly / sqrt(n)

## ── A. 입력 ────────────────────────────────────────────────────────────────
O   <- readRDS(file.path(OUT, "10_measure_objects.rds"))
SMx <- as.data.table(O$SMx); Wb <- as.data.table(O$Wb)
SI  <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
FR  <- as.data.table(SI$fwd_ret)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
BM  <- as.data.table(SI$bench)[, .(Date = as.Date(Date), BM_Ret)]
NP  <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/alpha_scores.parquet"))
NP[, Date := as.Date(Date)]; SMx[, Date := as.Date(Date)]; Wb[, Date := as.Date(Date)]
SMx <- merge(SMx, NP[, .(Date, Ticker, win_vol)], by = c("Date","Ticker"), all.x = TRUE)

## ── B. 기저 위험모델 M0 ────────────────────────────────────────────────────
## B-1 특이변동성 sd0: adaptive rolling (창 = min(경과월, 60), 최소 18), 당월 제외
R <- copy(FR); setorder(R, Ticker, Date)
R[, idx := seq_len(.N), by = Ticker]
R[, win := pmin(idx, 60L)]
R[, m1 := frollmean(Ret_1m, n = win, adaptive = TRUE, na.rm = TRUE), by = Ticker]
R[, m2 := frollmean(Ret_1m^2, n = win, adaptive = TRUE, na.rm = TRUE), by = Ticker]
R[, `:=`(m1 = shift(m1, 1L), m2 = shift(m2, 1L), nhist = shift(idx, 1L)), by = Ticker]
R[, sd0 := sqrt(pmax(m2 - m1^2, 0))]
R[is.na(nhist) | nhist < 18L | !is.finite(sd0) | sd0 <= 0, sd0 := NA_real_]
P <- merge(SMx, R[, .(Date, Ticker, Ret_1m, sd0, nhist)], by = c("Date","Ticker"))
P <- P[is.finite(Ret_1m)]
cov_rows <- mean(is.finite(P$sd0))
P <- P[is.finite(sd0)]
P[, grp := ifelse(excluded, "lo", "hi")]
say("패널: %d행 / %d월 (%s~%s) | sd0 커버리지 %.1f%% | lo %.1f%% | nhist 중앙 %d",
    nrow(P), uniqueN(P$Date), as.character(min(P$Date)), as.character(max(P$Date)),
    100 * cov_rows, 100 * mean(P$grp == "lo"), as.integer(median(P$nhist)))

## B-2 캘리브레이션: PIT-확장창 표준화잔차 z = r/sd0 의 경험분포 (t 이전 달만)
setorder(P, Date)
dts <- sort(unique(P$Date))
P[, z := Ret_1m / sd0]
zlist <- split(P$z, P$Date)
pastz <- numeric(0); z05 <- rep(NA_real_, length(dts)); names(z05) <- as.character(dts)
p_fix <- vector("list", length(dts))
for (i in seq_along(dts)) {
  if (length(pastz) >= 2000L) {
    sp <- sort(pastz)
    z05[i] <- sp[max(1L, floor(0.05 * length(sp)))]
    sub <- P[Date == dts[i]]
    # M0 가 고정문턱 -20% 에 부여하는 꼬리확률 = 과거 z 분포의 ECDF( -0.20/sd0 )
    p_fix[[i]] <- data.table(Date = dts[i], Ticker = sub$Ticker,
                             p0 = findInterval(-0.20 / sub$sd0, sp) / length(sp))
  }
  pastz <- c(pastz, zlist[[as.character(dts[i])]])
}
PF <- rbindlist(p_fix)
P <- merge(P, PF, by = c("Date","Ticker"))
P[, z05p := z05[as.character(Date)]]
P <- P[is.finite(z05p)]
P[, q0_5 := z05p * sd0]
say("캘리브레이션 후 패널: %d행 / %d월 (%s~) | z05 중앙 %.3f",
    nrow(P), uniqueN(P$Date), as.character(min(P$Date)), median(P$z05p))

## ── C. 예측자-측 진단 (결과 미사용) ────────────────────────────────────────
cs <- P[, .(r_vol = if (.N > 20) cor(score_orth, log(sd0), method = "spearman") else NA_real_,
            r_wv  = if (.N > 20 && sum(is.finite(win_vol)) > 20)
                      cor(score_orth, win_vol, method = "spearman", use = "complete.obs") else NA_real_),
        by = Date]
J$predictor_side <- list(
  spearman_orth_vs_logsd0_mean = mean(cs$r_vol, na.rm = TRUE),
  spearman_orth_vs_logsd0_nw_t = nw_t(cs$r_vol),
  spearman_orth_vs_winvol_mean = mean(cs$r_wv, na.rm = TRUE),
  mean_sd0_lo = P[grp == "lo", mean(sd0)], mean_sd0_hi = P[grp == "hi", mean(sd0)],
  n_months = nrow(cs))
say("예측자-측: cor(orth, log sd0) %.4f (t %.2f) | cor(orth, win_vol) %.4f | sd0 lo %.4f vs hi %.4f",
    J$predictor_side$spearman_orth_vs_logsd0_mean, J$predictor_side$spearman_orth_vs_logsd0_nw_t,
    J$predictor_side$spearman_orth_vs_winvol_mean, J$predictor_side$mean_sd0_lo, J$predictor_side$mean_sd0_hi)

## C-2 "그 자리를 채우는 것" — M0 가 고정문턱 -20% 에 이미 부여하는 군간 꼬리확률 격차
pf2 <- P[, .(p_lo = mean(p0[grp == "lo"]), p_hi = mean(p0[grp == "hi"]),
             p_all = mean(p0)), by = Date]
pf2[, gap := p_lo - p_hi]
J$m0_already_fills <- list(
  predicted_level = mean(pf2$p_all),
  predicted_tail_prob_lo = mean(pf2$p_lo), predicted_tail_prob_hi = mean(pf2$p_hi),
  predicted_gap = mean(pf2$gap), predicted_gap_nw_t = nw_t(pf2$gap))
say("M0 예측(캘리브): 수준 %.5f | lo %.5f / hi %.5f / 격차 %.5f (t %.2f)",
    mean(pf2$p_all), mean(pf2$p_lo), mean(pf2$p_hi), mean(pf2$gap), J$m0_already_fills$predicted_gap_nw_t)

## C-3 표본 정렬 — 선행 실측(268월 전체 패널)과 본 risk 패널의 raw 격차가 같은 양인가
##   ★이것은 처치 측정이 아니라 **선행 결과의 표본 정렬**이다(NP2/WT-010 이 이미 확립한 기술통계).
PC <- fromJSON(file.path(OUT, "00_precheck.json"))
align <- P[, .(lo = mean(Ret_1m[grp == "lo"] <= -0.20), hi = mean(Ret_1m[grp == "hi"] <= -0.20)), by = Date]
align_gap <- mean(align$lo - align$hi); align_level <- P[, mean(Ret_1m <= -0.20)]
J$sample_alignment <- list(
  published_gap_268m = PC$tail_realization$lo - PC$tail_realization$hi,
  published_level_268m = PC$tail_realization$all,
  risk_panel_gap = align_gap, risk_panel_level = align_level,
  ratio = align_gap / (PC$tail_realization$lo - PC$tail_realization$hi),
  note = "선행 결과의 표본 정렬(기술통계 재표현). 처치 M1 은 추정하지 않았다. 두 표본의 raw 격차가 크게 다르면 '비슷한 크기의 다른 양' 혼동 위험 — 명시 대조.")
say("표본 정렬: 발행본 격차 %.5f(수준 %.5f) vs risk 패널 %.5f(수준 %.5f) — 비 %.3f",
    J$sample_alignment$published_gap_268m, J$sample_alignment$published_level_268m,
    align_gap, align_level, J$sample_alignment$ratio)

## ── D. 기전-함의 개선폭 ────────────────────────────────────────────────────
incr_gap <- align_gap - J$m0_already_fills$predicted_gap        # ★공제
scale_to_5pct <- 0.05 / align_level
R1_effect <- incr_gap * scale_to_5pct
say("기전-함의: raw %.5f − M0 예측 %.5f = 증분 %.5f → 5%% 단위 %.5f",
    align_gap, J$m0_already_fills$predicted_gap, incr_gap, R1_effect)

sd_pool <- P[, sd(Ret_1m)]; f_q05 <- dnorm(qnorm(0.05)) / sd_pool
p_lo_share <- mean(P$grp == "lo")
dp_lo <- R1_effect * (1 - p_lo_share); dp_hi <- -R1_effect * p_lo_share
R1b_effect <- 0.5 * (p_lo_share * dp_lo^2 + (1 - p_lo_share) * dp_hi^2) / f_q05
delta_lo <- dp_lo / f_q05; delta_hi <- dp_hi / f_q05

## ── E. MDE80 — 순열(귀무) 잡음 ─────────────────────────────────────────────
P[, brc := as.integer(Ret_1m <= q0_5)]
n_m <- uniqueN(P$Date)
perm_stat <- function(B, FUN) mean(replicate(B, FUN()))
sd_R1 <- perm_stat(40L, function() {
  Pp <- P[, .(brc, g = sample(grp)), by = Date]
  sd(Pp[, .(d = mean(brc[g == "lo"]) - mean(brc[g == "hi"])), by = Date]$d, na.rm = TRUE) })
mde_R1 <- MDE80(sd_R1, n_m)

pinball <- function(r, q, tau = 0.05) (tau - as.numeric(r < q)) * (r - q)
sd_R1b <- perm_stat(40L, function() {
  Pp <- P[, .(Ret_1m, q0_5, g = sample(grp)), by = Date]
  Pp[, q1 := q0_5 + ifelse(g == "lo", -abs(delta_lo), abs(delta_hi))]
  sd(Pp[, .(d = mean(pinball(Ret_1m, q0_5)) - mean(pinball(Ret_1m, q1))), by = Date]$d, na.rm = TRUE) })
mde_R1b <- MDE80(sd_R1b, n_m)
say("R1 순열 sd %.5f → MDE80 %.5f | R1b 순열 sd %.3e → MDE80 %.3e", sd_R1, mde_R1, sd_R1b, mde_R1b)

## E-3 포트폴리오
BK <- merge(Wb, SMx[, .(Date, Ticker, excluded)], by = c("Date","Ticker"), all.x = TRUE)
BK[is.na(excluded), excluded := FALSE]
tilt <- BK[, .(w_lo = sum(w[excluded]), n_lo = sum(excluded), n = .N), by = Date]
J$book_tilt <- list(mean_w_lo = mean(tilt$w_lo), sd_w_lo = sd(tilt$w_lo),
                    min_w_lo = min(tilt$w_lo), max_w_lo = max(tilt$w_lo),
                    universe_lo_share = p_lo_share, n_months = nrow(tilt))
BKr <- merge(BK, FR, by = c("Date","Ticker"))
PR <- BKr[, .(r_p = sum(w * Ret_1m) / sum(w)), by = Date]
PR <- merge(PR, BM, by = "Date"); PR[, r_act := r_p - BM_Ret]
sd_rp <- sd(PR$r_p); f_port <- dnorm(qnorm(0.05)) / sd_rp
d_port_var <- J$book_tilt$sd_w_lo * abs(delta_lo)
R1c_effect <- 0.5 * f_port * d_port_var^2
sd_R1c <- perm_stat(200L, function() {
  q0p <- qnorm(0.05) * sd_rp; sh <- sample(c(-1, 1), nrow(PR), TRUE) * d_port_var
  sd(pinball(PR$r_p, q0p) - pinball(PR$r_p, q0p + sh)) })
mde_R1c <- MDE80(sd_R1c, nrow(PR))
say("book 틸트 w_lo 평균 %.4f sd %.4f | R1c 효과 %.3e / MDE80 %.3e",
    J$book_tilt$mean_w_lo, J$book_tilt$sd_w_lo, R1c_effect, mde_R1c)

## E-4 R2 crowding
sd_act <- sd(PR$r_act); sd_C <- J$book_tilt$sd_w_lo
mde_R2 <- 2.802 * sd_act / (sd_C * sqrt(nrow(PR)))
R2_effect <- abs(PC$conditional_on_top25$table$mean_ret[2] - PC$conditional_on_top25$table$mean_ret[1])

## E-5 R3 Sigma — 순수-스케일 대안가설
z_lo <- qnorm(PC$tail_realization$lo); z_hi <- qnorm(PC$tail_realization$hi)
R3_dlogvar <- 2 * log((0.20 / abs(z_lo)) / (0.20 / abs(z_hi)))
dlv_lo <- R3_dlogvar * (1 - p_lo_share); dlv_hi <- -R3_dlogvar * p_lo_share
R3_effect <- 0.5 * (p_lo_share * dlv_lo^2 + (1 - p_lo_share) * dlv_hi^2)
qlike <- function(r, s2) log(s2) + r^2 / s2
k <- exp(R3_dlogvar / 2)
sd_R3 <- perm_stat(30L, function() {
  Pp <- P[, .(Ret_1m, sd0, g = sample(grp)), by = Date]
  Pp[, s1 := ifelse(g == "lo", sd0 * k, sd0 / k^(p_lo_share / (1 - p_lo_share)))]
  sd(Pp[, .(d = mean(qlike(Ret_1m, sd0^2)) - mean(qlike(Ret_1m, s1^2))), by = Date]$d, na.rm = TRUE) })
mde_R3 <- MDE80(sd_R3, n_m)
say("R2: MDE80(beta) %.5f vs 기전 %.5f | R3: dlogvar %.4f, 효과 %.5f, MDE80 %.5f",
    mde_R2, R2_effect, R3_dlogvar, R3_effect, mde_R3)

## ── F. 관문 판정 ───────────────────────────────────────────────────────────
mk <- function(id, eff, mde, unit, note) list(id = id, effect = eff, mde80 = mde,
  ratio = abs(eff) / mde, threshold = 0.10, pass = isTRUE(abs(eff) / mde >= 0.10),
  sign = sign(eff), unit = unit, note = note)
J$gate <- list(
  R1  = mk("R1",  R1_effect,  mde_R1,  "월별 위반율 격차(5% VaR)", "raw 격차에서 M0 가 이미 예측하는 격차를 공제한 증분"),
  R1b = mk("R1b", R1b_effect, mde_R1b, "월평균 pinball 손실 차",   "proper score 2차항"),
  R1c = mk("R1c", R1c_effect, mde_R1c, "월평균 포트 pinball 손실 차", "25종 집계 희석 + 틸트 변동"),
  R2  = mk("R2",  R2_effect,  mde_R2,  "회귀계수 beta",             "crowding 이 후속 active 수익을 예측하는 크기"),
  R3  = mk("R3",  R3_effect,  mde_R3,  "월평균 QLIKE 차",           "순수-스케일 대안가설이 함의하는 상한"))
J$gate$summary <- list(
  pass_ids = names(J$gate)[sapply(names(J$gate), function(x) isTRUE(J$gate[[x]]$pass))],
  fail_ids = names(J$gate)[sapply(names(J$gate), function(x) identical(J$gate[[x]]$pass, FALSE))])
J$inputs <- list(align_gap = align_gap, align_level = align_level, incr_gap = incr_gap,
  scale_to_5pct = scale_to_5pct, sd_pool = sd_pool, f_q05 = f_q05, p_lo_share = p_lo_share,
  delta_lo = delta_lo, delta_hi = delta_hi, n_months = n_m, n_rows = nrow(P),
  sd_port = sd_rp, sd_active = sd_act)
J$metric_type <- "estimation_quality__gate_arithmetic"
write_json(J, file.path(OUT, "30_risk_gate.json"), pretty = TRUE, auto_unbox = TRUE, digits = 12)
saveRDS(list(P = P, PR = PR, tilt = tilt, BK = BK, z05 = z05), file.path(OUT, "30_risk_gate_objects.rds"))
say("완료 — 통과 [%s] / 미달 [%s]", paste(J$gate$summary$pass_ids, collapse = ","),
    paste(J$gate$summary$fail_ids, collapse = ","))
