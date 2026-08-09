## =============================================================================
## FQ-226 (B) — 달력 계절성: 슬라이딩 창 우선 → 다중검정 보정 순열 → 기전 구별
## 사전등록: PREREG.md §2 (실행 전 고정). metric_type: canonical_screen_diag.
## ★버킷 경계가 봉우리를 만든다 — 월 버킷 주장 전에 원형 슬라이딩 창 + 하모닉.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810")
FQ223 <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[b1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260810L)
source("02_Infrastructure/contracts/required_effect_size.R")
T_THRESH <- 2.0; B <- 20000L; MONS <- sprintf("%02d", 1:12)

## =============================================================================
## [0] 입력 — a1 이 저장한 월별 계수 + 공변량
## =============================================================================
say("================ [0] 입력 실측 ================")
f <- file.path(OUT, "a1_monthly_coefs_and_covariates.csv")
if (!file.exists(f)) stop("[b1] a1 산출 부재 — 0은 정지 신호")
DT <- fread(f); DT[, mon := sprintf("%02d", as.integer(substr(signal_ym, 6, 7)))]
DT[, yr := as.integer(substr(signal_ym, 1, 4))]
setorder(DT, signal_ym)
say("월별 계수 %d행 · %s ~ %s · 연도 %d개", nrow(DT), min(DT$signal_ym), max(DT$signal_ym), uniqueN(DT$yr))
SER <- c("M26_Revenue_Mom","C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M01","intercept")
for (s in SER) say("  %-16s 유한 %d/%d · mean %+.6f · sd %.6f", s, sum(is.finite(DT[[s]])), nrow(DT),
                   mean(DT[[s]], na.rm=TRUE), sd(DT[[s]], na.rm=TRUE))

## 연×월 행렬 (연내 순열의 기반) — 2026 은 7개월만 관측 ⇒ 관측 패턴은 조건부로 보존
to_mat <- function(v) {
  M <- matrix(NA_real_, nrow = uniqueN(DT$yr), ncol = 12,
              dimnames = list(sort(unique(DT$yr)), MONS))
  idx <- cbind(match(DT$yr, as.integer(rownames(M))), match(DT$mon, MONS))
  M[idx] <- v; M
}
colmeans_na <- function(M) colMeans(M, na.rm = TRUE)

## 연내 순열: 각 연도의 관측된 값들을 그 연도의 관측된 월 자리끼리 재배정
perm_rows <- function(M) {
  for (i in seq_len(nrow(M))) {
    o <- which(!is.na(M[i, ])); if (length(o) > 1L) M[i, o] <- M[i, sample(o)]
  }
  M
}

## =============================================================================
## [1] B0 검정력 선판정 (착수 게이트) — 월별 표
## =============================================================================
say("================ [1] B0 검정력 선판정 ================")
mo_tab <- function(v, lab) {
  d <- data.table(mon = DT$mon, est = v)[is.finite(est)]
  r <- d[, .(n = .N, mean = mean(est), sd = sd(est)), by = mon][order(mon)]
  r[, t_plain := mean/(sd/sqrt(n))]
  r[, excess := mean - mean(d$est)]
  r[, series := lab][]
}
MO <- rbindlist(lapply(SER, function(s) mo_tab(DT[[s]], s)))
M26mo <- MO[series == "M26_Revenue_Mom"][order(-mean)]
say("--- M26 월별 (평균 내림차순) ---")
for (i in seq_len(nrow(M26mo))) with(M26mo[i], say("  %s월 n=%2d mean %+.6f (연 %+.3f%%) sd %.6f t_plain %+.3f 초과 %+.6f",
                                                   mon, n, mean, mean*1200, sd, t_plain, excess))
top_mon <- M26mo$mon[1]; top_mean <- M26mo$mean[1]; top_sd <- M26mo$sd[1]; top_n <- M26mo$n[1]
req_top <- required_effect(n = top_n, t_threshold = T_THRESH, sd_monthly = top_sd, design = "full")
B0_pass <- abs(top_mean) >= req_top$required_monthly
say("★B0: 최대월 %s · 관측 %.6f (연 %.3f%%) vs n=%d 필요치 %.6f (연 %.3f%%) · 여유 %+.1f%% ⇒ %s",
    top_mon, top_mean, top_mean*1200, top_n, req_top$required_monthly, req_top$required_annual*100,
    (abs(top_mean)/req_top$required_monthly - 1)*100,
    if (B0_pass) "단일-달 검출 가능 범위 — 착수" else "★필요치 미달 — 측정 전 폐기가 정답")
if (!B0_pass) say("   (착수 게이트 미통과 시에도 B1 순열은 '어떤 달도 특별하지 않다'를 확인하는 용도로만 수행)")
say("   ⚠ 12개 달 동시 관찰 ⇒ 단일-달 문턱은 다중검정 미보정. 주판정 = B1 순열.")

## =============================================================================
## [2] B2 슬라이딩 창 (주장 전 선행) + 하모닉
## =============================================================================
say("================ [2] B2 원형 슬라이딩 창 ================")
slide <- function(v, lab) {
  d <- data.table(mon = DT$mon, est = v)[is.finite(est)]
  gm <- mean(d$est)
  out <- rbindlist(lapply(c(1L, 3L, 5L), function(w) {
    half <- (w - 1L) %/% 2L
    rbindlist(lapply(1:12, function(m) {
      wm <- sprintf("%02d", ((m - 1L + (-half):half) %% 12L) + 1L)
      s <- d[mon %in% wm]
      data.table(series = lab, w = w, center = MONS[m], n = nrow(s),
                 win_mean = mean(s$est), excess = mean(s$est) - gm)
    }))
  }))
  out
}
SL <- rbindlist(lapply(SER, function(s) slide(DT[[s]], s)))
sl26 <- SL[series == "M26_Revenue_Mom"]
for (wsel in c(1L, 3L, 5L)) {
  z <- sl26[w == wsel][order(-excess)]
  say("  w=%d 최대 %s월 초과 %+.6f · 2위 %s월 %+.6f · 최소 %s월 %+.6f",
      wsel, z$center[1], z$excess[1], z$center[2], z$excess[2], z$center[12], z$excess[12])
}
e1 <- sl26[w == 1L & center == top_mon, excess]
e3 <- sl26[w == 3L & center == top_mon, excess]
e5 <- sl26[w == 5L & center == top_mon, excess]
r3 <- e3/e1; r5 <- e5/e1
say("★희석 프로파일 (%s월 중심): w1 %+.6f → w3 %+.6f (비 %.3f) → w5 %+.6f (비 %.3f)", top_mon, e1, e3, r3, e5, r5)
say("   순수 고립 스파이크의 이론 희석비 = 1/3 = 0.333 (w3) · 1/5 = 0.200 (w5)")
iso_label <- if (r3 <= 0.7 * 1.0 && r3 <= 0.55) "고립 봉우리 (창 확대 시 희석)" else if (r3 >= 0.8) "넓은 고원 (창 확대에도 초과 유지)" else "중간 — 인접 1개월과 부분 공유"
say("★B2 판정: %s", iso_label)
sl26_rank <- sl26[w == 3L][order(-excess)]
say("   w=3 최대 창 중심 = %s월 (w=1 최대월 %s와 %s)", sl26_rank$center[1], top_mon,
    if (sl26_rank$center[1] == top_mon) "일치" else "불일치 — 경계 효과 의심")

## 하모닉 회귀 (버킷 경계 없는 사양)
say("--- 하모닉 분해 (버킷 경계 없음) ---")
mnum <- as.integer(DT$mon)
harm <- function(v, K) {
  X <- do.call(cbind, lapply(1:K, function(k) cbind(sin(2*pi*k*mnum/12), cos(2*pi*k*mnum/12))))
  fit <- lm(v ~ X); c(r2 = summary(fit)$r.squared, p = anova(fit)[["Pr(>F)"]][1])
}
hh <- rbindlist(lapply(1:5, function(K) { z <- harm(DT[["M26_Revenue_Mom"]], K)
  data.table(K = K, r2 = z[["r2"]], p_F = z[["p"]]) }))
for (i in seq_len(nrow(hh))) with(hh[i], say("  K=%d 하모닉 R2 %.4f · F p %.4f", K, r2, p_F))
say("   ⇒ 고립 스파이크면 R2 가 K 증가에 따라 계속 오른다 · 고원이면 K=1 에서 대부분 설명")

## =============================================================================
## [3] B1 순열검정 (주판정) + B3 이웃 구별 + B6 대조
## =============================================================================
say("================ [3] B1 순열검정 (다중검정 보정) ================")
run_perm <- function(v, Bn = B, lab = "") {
  M <- to_mat(v); obs <- colmeans_na(M)
  s_max <- max(obs); s_apr <- obs[["04"]]
  s_nb  <- obs[["04"]] - mean(c(obs[["03"]], obs[["05"]]))
  pm <- numeric(Bn); pa <- numeric(Bn); pn <- numeric(Bn)
  for (b in seq_len(Bn)) {
    cm <- colmeans_na(perm_rows(M))
    pm[b] <- max(cm); pa[b] <- cm[["04"]]; pn[b] <- cm[["04"]] - mean(c(cm[["03"]], cm[["05"]]))
  }
  list(obs = obs, s_max = s_max, s_apr = s_apr, s_nb = s_nb,
       p_max = (1 + sum(pm >= s_max))/(Bn + 1),
       p_apr = (1 + sum(pa >= s_apr))/(Bn + 1),
       p_nb  = (1 + sum(pn >= s_nb))/(Bn + 1),
       pool_max = pm, pool_apr = pa, pool_nb = pn, lab = lab)
}
t0 <- Sys.time()
P26 <- run_perm(DT[["M26_Revenue_Mom"]], B, "M26")
say("순열 %d회 소요 %.0fs", B, as.numeric(difftime(Sys.time(), t0, units = "secs")))
say("★B1 주판정 (M26): max-month 통계 %+.6f (최대월 %s) · p_max %.4f ⇒ %s",
    P26$s_max, names(which.max(P26$obs)), P26$p_max,
    if (P26$p_max < 0.05) "어떤 달이 특별하다 — 계절성 확립" else "다중검정 보정 후 계절성 미확립")
say("   4월 사전지정 단일검정: 통계 %+.6f · p_apr %.4f (보정 없음 라벨)", P26$s_apr, P26$p_apr)
say("★B3 이웃 구별: 4월 − (3월,5월)/2 = %+.6f · p_nb %.4f ⇒ %s",
    P26$s_nb, P26$p_nb, if (P26$p_nb < 0.05) "이웃과 구별됨" else "이웃과 구별 안 됨")

## B6-1 위반 주입 (양성 대조) — 검정이 실제 신호를 잡는가
say("--- B6-1 위반 주입 (양성 대조) ---")
inj <- DT[["M26_Revenue_Mom"]] + req_top$required_monthly * (DT$mon == "04")
PIN <- run_perm(inj, 5000L, "injected")
say("  주입 크기 %.6f (= B0 필요치) · 주입 후 p_max %.4f · p_apr %.4f ⇒ %s",
    req_top$required_monthly, PIN$p_max, PIN$p_apr,
    if (PIN$p_max < 0.05) "검정 살아있음 (검출)" else "★검정 사망 — 중단 신호")
if (PIN$p_max >= 0.05) stop("[b1] 위반 주입 미검출 — 검정 사망. 중단")

## B6-2 음성 대조 — 순열 null 에서 명목 5% 오탐률 재현
say("--- B6-2 음성 대조 (경험적 1종 오류) ---")
M26M <- to_mat(DT[["M26_Revenue_Mom"]]); NC <- 300L
pfake <- vapply(seq_len(NC), function(i) {
  cm <- colmeans_na(perm_rows(M26M))
  (1 + sum(P26$pool_max >= max(cm)))/(B + 1)
}, 0)
say("  가짜(순열) 계열 %d개의 p_max: <0.05 비율 %.4f · <0.10 비율 %.4f (명목 0.05 / 0.10)",
    NC, mean(pfake < 0.05), mean(pfake < 0.10))

## =============================================================================
## [4] B5 기전 구별 관측
## =============================================================================
say("================ [4] B5 기전 구별 관측 ================")
## (a) 팩터 전반 폭 — 4월 초과가 M26 고유인가 전 팩터 공통인가
say("--- (a) 전 계열 4월 초과 + 순열 p (폭 축) ---")
BR <- rbindlist(lapply(SER, function(s) {
  P <- run_perm(DT[[s]], 4000L, s)
  data.table(series = s, apr_mean = P$s_apr, apr_excess = P$s_apr - mean(DT[[s]], na.rm=TRUE),
             top_mon = names(which.max(P$obs)), p_max = P$p_max, p_apr = P$p_apr, p_nb = P$p_nb)
}))
for (i in seq_len(nrow(BR))) with(BR[i], say(
  "  %-16s 4월 %+.6f (초과 %+.6f · 연 %+.3f%%) · 최대월 %s · p_max %.4f · p_apr %.4f · p_nb %.4f",
  series, apr_mean, apr_excess, apr_excess*1200, top_mon, p_max, p_apr, p_nb))
n_apr_sig <- sum(BR$p_apr < 0.05); n_slope <- sum(BR$series != "intercept")
say("★폭: 기울기 계열 %d개 중 4월 p_apr<0.05 = %d개 · 절편 p_apr %.4f",
    n_slope, sum(BR[series != "intercept", p_apr] < 0.05), BR[series == "intercept", p_apr])

## (b) 횡단면 분산 채널 — 4월 disp 가 높은가 · 정규화하면 초과가 사라지는가
say("--- (b) 횡단면 수익 분산 채널 ---")
dsp <- DT[, .(n = .N, disp = mean(disp_t), N_t = mean(N_t)), by = mon][order(mon)]
gd <- mean(DT$disp_t)
for (i in seq_len(nrow(dsp))) with(dsp[i], say("  %s월 disp %.5f (전체 %.5f · 비 %.3f) · 평균 종목수 %.0f", mon, disp, gd, disp/gd, N_t))
dsp_apr_p <- (1 + sum(replicate(4000L, { cm <- colmeans_na(perm_rows(to_mat(DT$disp_t))); cm[["04"]] }) >= dsp[mon=="04", disp]))/4001
say("  4월 disp 순열 p = %.4f ⇒ %s", dsp_apr_p, if (dsp_apr_p < 0.05) "4월 분산 유의하게 높음" else "4월 분산 특이 아님")
norm26 <- DT[["M26_Revenue_Mom"]]/DT$disp_t
PN <- run_perm(norm26, 8000L, "M26/disp")
say("  ★분산 정규화 후: 4월 초과 %+.6f · p_apr %.4f · p_max %.4f ⇒ %s",
    PN$s_apr - mean(norm26, na.rm=TRUE), PN$p_apr, PN$p_max,
    if (PN$p_apr >= 0.05) "정규화로 소멸 — 분산 채널이 설명" else "정규화 후에도 유지 — 분산 채널로 설명 안 됨")

## (c) 롤오버 수리 arm — 수리가 4월 초과를 없애는가
say("--- (c) 롤오버-수리 arm (FQ-223 b3, 공통 279개월) ---")
ARM <- fread(file.path(FQ223, "b3_coefs_by_arm.csv"))
ARM[, mon := sprintf("%02d", as.integer(substr(signal_ym, 6, 7)))]
am <- ARM[, .(apr = mean(est[mon == "04"]), oth = mean(est[!mon %in% c("04")]),
              n_apr = sum(mon == "04"), t_apr = { x <- est[mon == "04"]; mean(x)/(sd(x)/sqrt(length(x))) }),
          by = arm]
am[, excess := apr - oth]
for (i in seq_len(nrow(am))) with(am[i], say("  %-16s 4월 %+.6f · 평월 %+.6f · 초과 %+.6f · 4월 t_plain %+.3f (n=%d)", arm, apr, oth, excess, t_apr, n_apr))
e_plain <- am[arm == "plain(재구성)", excess]; e_ra <- am[arm == "RA_4월탐지", excess]
say("★수리 효과: plain 초과 %+.6f → RA 초과 %+.6f (잔존율 %.3f) ⇒ %s",
    e_plain, e_ra, e_ra/e_plain,
    if (e_ra/e_plain < 0.5) "수리가 4월 초과의 절반 이상 제거 — 롤오버 기여 지지" else "수리 후에도 4월 초과 유지 — 롤오버만으로 설명 안 됨")

## (d) 시대 재현 (기술 — 판정 아님)
say("--- (d) 시대 재현 (기술통계, 저검정력) ---")
for (s in c("M26_Revenue_Mom","M01")) {
  h1 <- DT[yr <= 2014 & mon == "04", get(s)]; h2 <- DT[yr >= 2015 & mon == "04", get(s)]
  o1 <- DT[yr <= 2014 & mon != "04", get(s)]; o2 <- DT[yr >= 2015 & mon != "04", get(s)]
  say("  %-16s 전반 4월 %+.6f(n=%d, 초과 %+.6f) · 후반 4월 %+.6f(n=%d, 초과 %+.6f)",
      s, mean(h1), length(h1), mean(h1)-mean(o1), mean(h2), length(h2), mean(h2)-mean(o2))
}

## =============================================================================
## [5] 저장
## =============================================================================
fwrite(MO, file.path(OUT, "b1_month_of_year_all_series.csv"))
fwrite(SL, file.path(OUT, "b1_sliding_windows.csv"))
fwrite(BR, file.path(OUT, "b1_breadth_across_series.csv"))
fwrite(dsp, file.path(OUT, "b1_dispersion_by_month.csv"))
fwrite(am, file.path(OUT, "b1_rollover_arm_april.csv"))
fwrite(hh, file.path(OUT, "b1_harmonics.csv"))
saveRDS(list(B0_pass = B0_pass, req_top = req_top, top_mon = top_mon, top_mean = top_mean,
             p_max = P26$p_max, p_apr = P26$p_apr, p_nb = P26$p_nb, obs = P26$obs,
             e1 = e1, e3 = e3, e5 = e5, r3 = r3, r5 = r5, iso_label = iso_label,
             harm = hh, breadth = BR, disp = dsp, disp_apr_p = dsp_apr_p,
             norm_p_apr = PN$p_apr, arm_april = am,
             inj_p = PIN$p_max, fp_rate_05 = mean(pfake < 0.05), fp_rate_10 = mean(pfake < 0.10)),
        file.path(OUT, "b1_results.rds"))
say("저장 완료 → %s", OUT)
say("★★[B 요약] 최대월 %s · p_max %.4f · p_apr %.4f · p_nb %.4f · 희석비 w3 %.3f ⇒ %s · 주입검출 p %.4f · 오탐률 %.3f",
    top_mon, P26$p_max, P26$p_apr, P26$p_nb, r3, iso_label, PIN$p_max, mean(pfake < 0.05))
