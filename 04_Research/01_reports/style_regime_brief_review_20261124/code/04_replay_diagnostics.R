## 04_replay_diagnostics.R — 현행 국면 판독 규칙을 날마다 '그날까지의 자료'로 다시 내고(as-of 재현) 성질을 잰다.
##   현행 규칙(style_brief_lib.R:132-137 · :205-208 · :234-237): 창 = 완결 11개월 + 진행월 MTD, 월평균 = 합/12,
##     국면 = 창 평균의 부호(SMB<0 대형 · HML<0 성장 · RMW>0 퀄리티 강세), 부활 워치 = SMB>0 ∧ HML>0.
##   재료 = 한국 FF 요인 정본 일간(build_kr_factor_returns.R v1.1 · 현 측정 축) — 월 수익 = 그 달 일간 복리.
##   PIT: d 날짜의 판독은 d 까지의 일간 수익만 쓴다. 평가(앞으로 h 거래일 수익)는 판독 뒤의 실현값 — 판독에는 들어가지 않는다.
##   문턱 없음(부호 규칙 그대로). 대안 판독 비교용 t 문턱 = 등록부 constraint_defaults.json::tier_graduation 의 2.0(PORT_t · 알파 노치와 같은 수).
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE)
SNAP <- a[1]; OUT <- a[2]; QM <- if (length(a) >= 3) a[3] else "G:/OneDrive/Quant_Module_Moltbot"
## 유의 문턱 = 등록부 tier_graduation::grade_b_min_portfolio_alpha_t (B 진입 PORT_t 2.0 · 팩터 알파 노치 C→B 와 같은 수)
TG <- fromJSON(file.path(QM, "02_Infrastructure/worktask/constraint_defaults.json"))$tier_graduation
T_SIG <- as.numeric(TG[["grade_b_min_portfolio_alpha_t"]])
stopifnot(length(T_SIG) == 1L, is.finite(T_SIG))

D <- as.data.table(read_parquet(file.path(SNAP, "kr_factor_returns_daily.parquet")))
D[, Date := as.Date(Date)]; setorder(D, Date)
FAC <- c("MKT", "SMB", "HML", "RMW", "CMA", "WML")
D <- D[, c("Date", FAC), with = FALSE]
D[, ym := format(Date, "%Y-%m")]
first_ok <- D[complete.cases(D[, ..FAC]), min(Date)]
cat(sprintf("일간 %d일 %s~%s · 6요인 모두 있는 첫날 %s\n", nrow(D), min(D$Date), max(D$Date), first_ok))
D <- D[Date >= first_ok]

## 월 수익(그 달 일간 복리) · 진행월 MTD 누적(그날까지)
M <- D[, lapply(.SD, function(r) prod(1 + r) - 1), by = ym, .SDcols = FAC]
for (f in FAC) D[, (paste0("mtd_", f)) := cumprod(1 + get(f)) - 1, by = ym]
yms <- M$ym
D[, mi := match(ym, yms)]                                   # 진행월 위치
## 창 평균(완결 11개월 + MTD)/12 — 완결 11개월 합은 진행월 직전 11개월
for (f in FAC) {
  cs <- c(0, cumsum(M[[f]]))                                 # cs[k+1] = 1..k 월 합
  s11 <- function(k) { o <- rep(NA_real_, length(k)); ok <- k >= 12   # 월 k-11..k-1 합 = cs[k] - cs[k-11]
    o[ok] <- cs[k[ok]] - cs[k[ok] - 11]; o }
  D[, (paste0("w_", f)) := (s11(mi) + get(paste0("mtd_", f))) / 12]
}
D <- D[!is.na(w_SMB)]
lab <- function(x) sign(x)
for (f in c("SMB", "HML", "RMW", "CMA", "WML")) D[, (paste0("L_", f)) := lab(get(paste0("w_", f)))]
D[, revive := as.integer(w_SMB > 0 & w_HML > 0)]
D[, first_of_month := c(TRUE, ym[-1] != ym[-.N])]
cat(sprintf("판독 재현 %d일 %s~%s\n", nrow(D), min(D$Date), max(D$Date)))

## ── (1) 지속 · 뒤집힘 ──────────────────────────────────────────────────────
runs_stats <- function(x, dates, fom) {
  r <- rle(x); n <- length(r$lengths)
  flips <- which(x[-1] != x[-length(x)]) + 1L              # 뒤집힌 날의 위치
  yrs <- as.numeric(diff(range(dates))) / 365.25
  ## 되돌림: 뒤집힌 뒤 21거래일 안에 다시 뒤집힘
  wh <- if (length(flips) > 1) sum(diff(flips) <= 21) else 0L
  data.table(flips_per_year = round(length(flips) / yrs, 2),
             median_run_days = median(r$lengths), p25_run = quantile(r$lengths, .25), p75_run = quantile(r$lengths, .75),
             whipsaw_share = round(if (length(flips)) wh / length(flips) else NA_real_, 3),
             flips_on_month_start_share = round(mean(fom[flips]), 3),
             base_month_start_share = round(mean(fom), 3))
}
RS <- rbindlist(lapply(c("SMB", "HML", "RMW", "CMA", "WML"), function(f)
  cbind(factor = f, runs_stats(D[[paste0("L_", f)]], D$Date, D$first_of_month))))
RS <- rbind(RS, cbind(factor = "부활워치", runs_stats(D$revive, D$Date, D$first_of_month)))
cat("\n[1] 판독 지속 · 뒤집힘 (일간 as-of 재현)\n"); print(RS)

## 월초 뒤집힘의 원인 분해: 그날 MTD 가 아니라 '빠져나간 13개월 전 달'이 부호를 바꿨나
drop_cause <- rbindlist(lapply(c("SMB", "HML", "RMW"), function(f) {
  L <- D[[paste0("L_", f)]]; fl <- which(L[-1] != L[-length(L)]) + 1L
  fl <- fl[D$first_of_month[fl]]
  if (!length(fl)) return(NULL)
  ## 월초 d: 창 = (k-11..k-1) + MTD(d). 전날 창 = (k-12..k-2) + MTD(전날=월 k-1 전체). 빠진 달 = k-12
  k <- D$mi[fl]
  dropped <- M[[f]][pmax(k - 12, 1)]
  w_prev <- D[[paste0("w_", f)]][fl - 1]
  data.table(factor = f, n_month_start_flips = length(fl),
             share_dropped_month_bigger_than_new_day = round(mean(abs(dropped) / 12 > abs(D[[f]][fl]) / 12), 3),
             median_abs_window_before = round(median(abs(w_prev)) * 100, 3))
}))
cat("\n[1b] 월초 뒤집힘 — 13개월 전 달이 빠지는 효과(밑 효과)\n"); print(drop_cause)

## ── (2) 판독 크기 — 부호를 정한 숫자가 잡음 안인가 ──────────────────────────
## 창 평균의 표준오차 근사 = 일간 수익의 직전 252일 표준편차 × sqrt(21) / sqrt(12)  (월 수익 sd / sqrt(12))
for (f in c("SMB", "HML", "RMW")) {
  D[, (paste0("sd_", f)) := frollapply(get(f), 252, sd, align = "right")]
  D[, (paste0("t_", f)) := get(paste0("w_", f)) / (get(paste0("sd_", f)) * sqrt(21) / sqrt(12))]
}
TT <- rbindlist(lapply(c("SMB", "HML", "RMW"), function(f) {
  t <- D[[paste0("t_", f)]]; t <- t[is.finite(t)]
  data.table(factor = f, share_abs_t_lt_1 = round(mean(abs(t) < 1), 3), share_abs_t_lt_tsig = round(mean(abs(t) < T_SIG), 3),
             median_abs_t = round(median(abs(t)), 2))
}))
cat(sprintf("\n[2] 판독 크기(창 평균 / 표준오차) — |t|<1 · |t|<%.1f 비율\n", T_SIG)); print(TT)

## ── (3) 예측력 — 판독 뒤 h 거래일 요인 누적 수익의 부호 적중 · 조건부 평균 ──
fwd <- function(r, h) { n <- length(r); cs <- c(0, cumsum(log1p(r)))
  out <- rep(NA_real_, n); i <- seq_len(n - h); out[i] <- exp(cs[i + h + 1] - cs[i + 1]) - 1; out }
nw_t <- function(y, x, lag) {                                  # 차이(라벨 +1 대 -1) 의 NW t
  ok <- is.finite(y) & is.finite(x); y <- y[ok]; x <- x[ok]
  m <- lm(y ~ x); V <- sandwich::NeweyWest(m, lag = lag, prewhite = FALSE)
  as.numeric(coef(m)[2] / sqrt(V[2, 2]))
}
PR <- rbindlist(lapply(c("SMB", "HML", "RMW", "CMA", "WML"), function(f) rbindlist(lapply(c(21, 63, 126, 252), function(h) {
  y <- fwd(D[[f]], h); L <- D[[paste0("L_", f)]]
  ok <- is.finite(y) & L != 0
  base_up <- mean(y[ok] > 0)
  hit <- mean(sign(y[ok]) == L[ok])
  ## 같은 날 무작위로 부호를 고르는 기준(기저율)의 적중 = p*q + (1-p)*(1-q)
  q <- mean(L[ok] > 0); base_hit <- base_up * q + (1 - base_up) * (1 - q)
  data.table(factor = f, h_days = h, n = sum(ok), hit = round(hit, 3), base_hit = round(base_hit, 3),
             mean_fwd_if_pos = round(mean(y[ok & L > 0]) * 100, 2), mean_fwd_if_neg = round(mean(y[ok & L < 0]) * 100, 2),
             nw_t_diff = round(nw_t(y[ok], as.numeric(L[ok] > 0), lag = h), 2))
}))))
cat("\n[3] 예측력 — 판독(부호) 뒤 h 거래일 요인 수익\n"); print(PR)

## 부활 워치 발화 뒤 SMB · HML
RV <- rbindlist(lapply(c(21, 63, 126, 252), function(h) {
  ys <- fwd(D$SMB, h); yh <- fwd(D$HML, h); ok <- is.finite(ys) & is.finite(yh)
  data.table(h_days = h, n_fire_days = sum(ok & D$revive == 1), share_days_firing = round(mean(D$revive[ok]), 3),
             smb_fwd_fire = round(mean(ys[ok & D$revive == 1]) * 100, 2), smb_fwd_else = round(mean(ys[ok & D$revive == 0]) * 100, 2),
             hml_fwd_fire = round(mean(yh[ok & D$revive == 1]) * 100, 2), hml_fwd_else = round(mean(yh[ok & D$revive == 0]) * 100, 2))
}))
cat("\n[3b] 부활 워치 발화 뒤 SMB · HML 누적 수익(%)\n"); print(RV)
## 발화 구간 목록
D[, rv_run := rleid(revive)]
EP <- D[revive == 1, .(start = min(Date), end = max(Date), days = .N), by = rv_run][order(start)]
cat(sprintf("\n[3c] 부활 워치 발화 구간 %d개 (10거래일 이상만 표시)\n", nrow(EP))); print(EP[days >= 10])

## ── (4) 지연 — 후행 12개월 창 판독이 '사후 중심 창'(그날 ±126거래일) 부호를 몇 거래일 늦게 따라가나 ──
LG <- rbindlist(lapply(c("SMB", "HML", "RMW"), function(f) {
  r <- D[[f]]; n <- length(r); cs <- c(0, cumsum(r))
  cen <- rep(NA_real_, n); i <- 127:(n - 126); cen[i] <- (cs[i + 127] - cs[i - 126]) / 253
  L <- D[[paste0("L_", f)]]
  sh <- seq(0, 252, by = 21)
  ag <- vapply(sh, function(s) { j <- seq_len(n); k <- j - s; ok <- k >= 1 & is.finite(cen[pmax(k, 1)])
    mean(L[ok] == sign(cen[k[ok]])) }, numeric(1))
  data.table(factor = f, best_shift_days = sh[which.max(ag)], agree_at_0 = round(ag[1], 3), agree_at_best = round(max(ag), 3))
}))
cat("\n[4] 지연 — 판독과 사후 중심 창 부호의 일치가 가장 높은 지연(거래일)\n"); print(LG)

fwrite(RS, file.path(OUT, "diag_runs.csv")); fwrite(drop_cause, file.path(OUT, "diag_dropoff.csv"))
fwrite(TT, file.path(OUT, "diag_tstat.csv")); fwrite(PR, file.path(OUT, "diag_predict.csv"))
fwrite(RV, file.path(OUT, "diag_revive.csv")); fwrite(EP, file.path(OUT, "diag_revive_episodes.csv")); fwrite(LG, file.path(OUT, "diag_lag.csv"))
saveRDS(D[, c("Date", "ym", FAC, paste0("w_", FAC), "revive", "t_SMB", "t_HML", "t_RMW"), with = FALSE], file.path(OUT, "replay_daily.rds"))
cat(sprintf("\nT_SIG(등록부) = %s\n", T_SIG))
