## =============================================================================
## FQ-223 (B) — 방법 B: 롤오버-인지 M26 재구성 후 재적합 (표본 불변 = 결정적 반증)
##
## 설계: anchor = max(sig-63, basis_start), basis_start = sig 이하 최근 "동시변경일".
##       04/05 만 값이 바뀌고 나머지 달은 plain 과 동일 ⇒ n=283 불변, 검정력 교락 없음.
##
## ★2중 parity gate (미달 시 중단 — 재구성이 생산 코드를 대표해야만 비교가 성립)
##   G1: raw M26_plain 재구성 vs factor_db Z_Score_Aligned  월별 |Spearman| >= 0.95
##   G2: 내 z(M26_plain) arm 의 FMB t 가 DB arm t(+2.5553) 와 |Δ| <= 0.15
## 그 뒤에야 plain→rollaware 의 Δt 를 오염 제거 효과로 읽는다.
##
## metric_type: canonical_screen_diag. 자본 주장 없음. factor_db 재빌드 없음(읽기만).
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
SRC  <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
CD   <- file.path(ROOT, ".cache/consensus")
say <- function(fmt, ...) { cat(sprintf(paste0("[b1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260810L)
TOL <- 1e-12; LAG <- 63L

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}
fmb_coefs <- function(dat, xs, ycol = "Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse = " + ")))
  dat[, {
    fit <- tryCatch(lm(f, data = .SD), error = function(e) NULL)
    if (is.null(fit)) .(term = character(0), est = numeric(0))
    else { cf <- coef(fit); .(term = names(cf), est = as.numeric(cf)) }
  }, by = signal_ym, .SDcols = c(ycol, xs)]
}
## factor_db_builder.R 의 z 규약 복제: raw 1/99 winsor → z → ±3 clip → sd=1 재표준화
z_fdb <- function(x) {
  ok <- is.finite(x)
  if (sum(ok) < 20L) return(rep(NA_real_, length(x)))
  q <- quantile(x[ok], c(0.01, 0.99), na.rm = TRUE, names = FALSE)
  w <- pmin(pmax(x, q[1]), q[2])
  mu <- mean(w, na.rm = TRUE); s <- sd(w, na.rm = TRUE)
  if (!is.finite(s) || s < 1e-12) return(rep(NA_real_, length(x)))
  z <- (w - mu)/s
  z <- pmin(pmax(z, -3), 3)
  s2 <- sd(z, na.rm = TRUE)
  if (is.finite(s2) && s2 > 1e-12) z/s2 else z
}

## =============================================================================
## [0] 입력 실측
## =============================================================================
say("================ [0] 입력 실측 ================")
D4 <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet")))
D4[, Date := as.Date(Date)]
sigs <- sort(unique(D4$Date))
say("판정 패널: %d행 · %d개월 · sig_date %s ~ %s", nrow(D4), length(sigs), min(sigs), max(sigs))

E <- as.data.table(read_parquet(file.path(CD, "revenue_fy1.parquet")))
E[, Date := as.Date(Date)]
E <- E[!is.na(revenue_fy1), .(Ticker, Date, value = revenue_fy1)]
setorderv(E, c("Ticker", "Date"))
n_date <- uniqueN(E$Date); n_ym <- uniqueN(format(E$Date, "%Y-%m"))
say("revenue_fy1 원계열: %d행 · 고유 Date %d · 고유 년월 %d ⇒ ★관측단위 = %s · %s ~ %s",
    nrow(E), n_date, n_ym, if (n_date > n_ym*1.5) "일간(daily)" else "월간(monthly)",
    min(E$Date), max(E$Date))
if (n_date <= n_ym*1.5) stop("[b1] 원계열 관측단위 가정 위반 — 중단")
say("  고유 Ticker %d · 값 중앙 %.4g", uniqueN(E$Ticker), median(E$value))
if (max(E$Date) < max(sigs))
  say("  ★주의: 원계열 종점(%s) < 판정 sig 종점(%s) — 후반부 월은 재구성 불가할 수 있음",
      max(E$Date), max(sigs))

## =============================================================================
## [1] 동시변경일(롤오버) 탐지 — 2변형 (원 탐지기 / 4월 한정)
## =============================================================================
say("================ [1] 동시변경일 탐지 ================")
E[, prev_v := shift(value), by = Ticker]
E[, chg := !is.na(prev_v) & abs(value - prev_v) > TOL]
lv <- E[, .(n_live = .N), by = Date]
cg <- E[chg == TRUE, .(n_chg = .N), by = Date]
bd <- merge(lv, cg, by = "Date", all.x = TRUE); bd[is.na(n_chg), n_chg := 0L]
bd[, frac := n_chg/n_live]
ROLL_raw <- sort(bd[frac >= 0.50 & n_live >= 50L, Date])
if (!length(ROLL_raw)) stop("[b1] 동시변경일 0건 — 0은 결론이 아니라 정지 신호")
mon_tab <- table(format(ROLL_raw, "%m"))
say("탐지 %d일 · 월 분포: %s", length(ROLL_raw),
    paste(sprintf("%s월=%d", names(mon_tab), as.integer(mon_tab)), collapse = " "))
ROLL_apr <- ROLL_raw[format(ROLL_raw, "%m") == "04"]
say("  4월 %d일 / 4월 외 %d일 (b6 가 보고한 초기 희소구간 오검출)",
    length(ROLL_apr), length(ROLL_raw) - length(ROLL_apr))
fwrite(bd[frac >= 0.50 & n_live >= 50L][order(Date)], file.path(OUT, "b1_rollover_days.csv"))

## =============================================================================
## [2] raw M26 재구성 — plain(생산 복제) / rollaware(수리안) × 탐지기 2변형
## =============================================================================
say("================ [2] raw M26 재구성 ================")
E[, obs_date := Date]                 # roll join 이 query Date 로 덮으므로 원 관측일 보존
setkeyv(E, c("Ticker", "Date"))
TK <- unique(E$Ticker)
mkQ <- function(dates) {
  q <- CJ(Ticker = TK, i = seq_along(sigs))
  q[, Date := dates[i]][, i := NULL]
  q[, sig_i := match(Date, dates)]   # 자리표시 (아래서 재부여)
  q[, sig_i := NULL]
  setkeyv(q, c("Ticker", "Date")); q[]
}
## 인덱스 보존형 질의 (Ticker × sig 순서 고정)
mkQ2 <- function(dates) {
  q <- CJ(Ticker = TK, k = seq_along(sigs), sorted = FALSE)
  q[, Date := dates[k]]
  setkeyv(q, c("Ticker", "Date")); q[]
}
pull <- function(dates) {
  q <- mkQ2(dates)
  r <- E[q, roll = TRUE, on = .(Ticker, Date)]
  r[!is.na(value), .(Ticker, k, v = value, d = obs_date)]
}
pull_fwd <- function(dates) {
  q <- mkQ2(dates)
  r <- E[q, roll = -Inf, on = .(Ticker, Date)]
  r[!is.na(value), .(Ticker, k, v = value, d = obs_date)]
}
NOW <- pull(sigs)
setnames(NOW, c("v","d"), c("v_now","d_now"))
say("현재값 관측 %d (종목×월) · 유효 월 %d", nrow(NOW), uniqueN(NOW$k))

build_arm <- function(anchor_dates, lab) {
  LG <- pull(anchor_dates); setnames(LG, c("v","d"), c("v_lag","d_lag"))
  J <- merge(NOW, LG, by = c("Ticker","k"))
  J <- J[abs(v_lag) > 1e-6]
  J[, raw := (v_now - v_lag)/abs(v_lag)]
  J <- J[is.finite(raw)]
  J[, arm := lab]
  J[]
}
## (a) plain: anchor = sig - 63
A_plain <- build_arm(sigs - LAG, "plain")
say("plain arm: %d 관측 · %d개월", nrow(A_plain), uniqueN(A_plain$k))

## (b) rollaware: anchor = max(sig-63, basis); 후방관측이 basis 이전이면 basis 이후 첫 관측
make_ra <- function(ROLL, lab) {
  basis <- as.Date(vapply(sigs, function(s) { kk <- ROLL[ROLL <= s]
    if (!length(kk)) NA_real_ else as.numeric(max(kk)) }, 0), origin = "1970-01-01")
  n_na <- sum(is.na(basis))
  tgt <- sigs - LAG
  has <- !is.na(basis)
  tgt[has] <- pmax(sigs[has] - LAG, basis[has])
  back <- pull(tgt);     setnames(back, c("v","d"), c("v_lag","d_lag"))
  fwd  <- pull_fwd(tgt); setnames(fwd,  c("v","d"), c("v_f","d_f"))
  bb <- merge(back, fwd, by = c("Ticker","k"), all = TRUE)
  bb[, bas := basis[k]]
  bb[, use_fwd := !is.na(bas) & (is.na(d_lag) | d_lag < bas)]
  bb[use_fwd == TRUE, `:=`(v_lag = v_f, d_lag = d_f)]
  bb <- bb[!is.na(v_lag) & !is.na(d_lag)]
  J <- merge(NOW, bb[, .(Ticker, k, v_lag, d_lag)], by = c("Ticker","k"))
  J <- J[abs(v_lag) > 1e-6]
  J[, raw := (v_now - v_lag)/abs(v_lag)]
  J <- J[is.finite(raw)][, arm := lab]
  list(J = J, n_na_basis = n_na, use_fwd_rate = mean(bb$use_fwd, na.rm = TRUE))
}
RA1 <- make_ra(ROLL_raw, "rollaware_rawdet")
RA2 <- make_ra(ROLL_apr, "rollaware_aprdet")
say("rollaware(원탐지기): %d 관측 · basis 결측월 %d · 전방관측 대체율 %.3f",
    nrow(RA1$J), RA1$n_na_basis, RA1$use_fwd_rate)
say("rollaware(4월한정) : %d 관측 · basis 결측월 %d · 전방관측 대체율 %.3f",
    nrow(RA2$J), RA2$n_na_basis, RA2$use_fwd_rate)

## =============================================================================
## [3] G1 parity — raw M26_plain 재구성 vs factor_db 배출값
## =============================================================================
say("================ [3] G1 parity: 재구성 vs 배출값 ================")
KMAP <- data.table(k = seq_along(sigs), Date = sigs)
P <- merge(A_plain[, .(Ticker, k, raw)], KMAP, by = "k")
G1 <- merge(D4[, .(Date, Ticker, signal_ym, zdb = M26_Revenue_Mom)], P[, .(Date, Ticker, raw)],
            by = c("Date","Ticker"))
say("교집합 %d 관측 · %d개월 (판정패널 %d행 대비 매칭률 %.3f)",
    nrow(G1), uniqueN(G1$Date), nrow(D4), nrow(G1)/nrow(D4))
g1 <- G1[, .(n = .N, rho = suppressWarnings(cor(raw, zdb, method = "spearman", use = "complete.obs"))),
         by = .(Date, signal_ym)][is.finite(rho)]
say("월별 Spearman(raw 재구성, DB Z_Score_Aligned): 중앙 %+.4f · 5%% %+.4f · 최소 %+.4f · |rho|>=0.95 인 달 %d/%d",
    median(g1$rho), quantile(g1$rho, .05), min(g1$rho), sum(abs(g1$rho) >= 0.95), nrow(g1))
say("  부호 분포: 양 %d달 / 음 %d달 (음이면 align_factor_direction 이 방향을 뒤집은 달)",
    sum(g1$rho > 0), sum(g1$rho < 0))
fwrite(g1, file.path(OUT, "b1_g1_parity_monthly.csv"))
G1_PASS <- median(abs(g1$rho)) >= 0.95
say("★G1 = %s (중앙 |rho| %.4f · 문턱 0.95)", if (G1_PASS) "PASS" else "FAIL", median(abs(g1$rho)))
if (!G1_PASS) stop("[b1] G1 미달 — 재구성이 생산 배출값을 대표하지 못함. 비교 무효. 중단")
## 달별 정렬 부호 (DB 가 쓴 방향) — RA arm 에 동일 적용
SGN <- g1[, .(Date, sgn = sign(rho))]

## =============================================================================
## [4] arm 별 z 구성 + FMB 재적합
## =============================================================================
say("================ [4] arm 별 z + FMB ================")
base_cols <- D4[, .(Date, Ticker, signal_ym, C01_SUE, C02_EPS_Chg_1m, C04_ESBR, Ret_1m)]
fit_arm <- function(J, lab) {
  X <- merge(KMAP, J[, .(k, Ticker, raw)], by = "k")[, .(Date, Ticker, raw)]
  X <- merge(X, SGN, by = "Date")
  X[, zm := z_fdb(raw)*sgn[1], by = Date]
  DD <- merge(base_cols, X[, .(Date, Ticker, zm)], by = c("Date","Ticker"))
  DD <- DD[complete.cases(DD[, .(C01_SUE, C02_EPS_Chg_1m, C04_ESBR, zm, Ret_1m)])]
  mm <- DD[, .N, by = signal_ym]; DD <- DD[signal_ym %in% mm[N >= 30L, signal_ym]]
  CFx <- fmb_coefs(DD, c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","zm"))
  s <- CFx[term == "zm"][order(signal_ym)]; s[, mon := substr(signal_ym, 6, 7)]
  list(arm = lab, n_months = nrow(s), n_obs = nrow(DD),
       t_nw3 = nw_t(s$est), mean = mean(s$est), sd = sd(s$est),
       apr_mean = mean(s[mon == "04", est]), may_mean = mean(s[mon == "05", est]),
       oth_mean = mean(s[!(mon %in% c("04","05")), est]),
       t_excl_apr_may = nw_t(s[!(mon %in% c("04","05")), est]), series = s)
}
R_plain <- fit_arm(A_plain, "plain(재구성)")
R_ra1   <- fit_arm(RA1$J,  "rollaware_rawdet")
R_ra2   <- fit_arm(RA2$J,  "rollaware_aprdet")

t_db <- 2.5552525842524
say("--- arm 별 z(M26) FMB NW(3) t ---")
for (r in list(R_plain, R_ra1, R_ra2))
  say("  %-20s n=%3d · %6d obs · ★t %+.4f · mean %+.6f · 4월평균 %+.6f · 5월평균 %+.6f · 평월 %+.6f",
      r$arm, r$n_months, r$n_obs, r$t_nw3, r$mean, r$apr_mean, r$may_mean, r$oth_mean)
say("★G2 parity: 재구성 plain t %+.4f vs DB arm t %+.4f ⇒ |Δ| = %.4f (문턱 0.15)",
    R_plain$t_nw3, t_db, abs(R_plain$t_nw3 - t_db))
G2_PASS <- abs(R_plain$t_nw3 - t_db) <= 0.15
say("★G2 = %s", if (G2_PASS) "PASS" else "FAIL")

## 오염 제거 효과 = plain → rollaware 의 Δt (표본 동일)
d1 <- R_ra1$t_nw3 - R_plain$t_nw3
d2 <- R_ra2$t_nw3 - R_plain$t_nw3
say("★오염 제거 Δt: 원탐지기 %+.4f · 4월한정 %+.4f", d1, d2)
say("★DB baseline 에 이식한 t_B: 원탐지기 %+.4f · 4월한정 %+.4f (문턱 2.0)", t_db + d1, t_db + d2)

## 월 일치 여부 확인 — 04/05 외의 달은 값이 같아야 한다(설계 확인)
chk <- merge(R_plain$series[, .(signal_ym, e_plain = est)],
             R_ra2$series[, .(signal_ym, e_ra = est)], by = "signal_ym")
chk[, mon := substr(signal_ym, 6, 7)]
chk[, same := abs(e_plain - e_ra) < 1e-10]
say("설계 확인: 04/05 외 달의 계수 동일 비율 %.4f (%d/%d) · 04/05 달 동일 비율 %.4f",
    chk[!(mon %in% c("04","05")), mean(same)], chk[!(mon %in% c("04","05")), sum(same)],
    chk[!(mon %in% c("04","05")), .N], chk[mon %in% c("04","05"), mean(same)])

## =============================================================================
## [5] (C) 오염 규모 — raw 값 분포 비교
## =============================================================================
say("================ [5] (C) 오염 규모: raw 값 분포 ================")
mag <- rbindlist(lapply(list(list(A_plain,"plain"), list(RA1$J,"rollaware_rawdet"), list(RA2$J,"rollaware_aprdet")),
  function(z) {
    J <- merge(KMAP, z[[1]][, .(k, Ticker, raw)], by = "k")
    J[, mon := format(Date, "%m")]
    J[, grp := fifelse(mon == "04", "04", fifelse(mon == "05", "05", "other"))]
    J[, .(arm = z[[2]], n = .N, med = median(raw), med_abs = median(abs(raw)),
          q90 = quantile(raw, .90), frac_pos = mean(raw > 0), frac_zero = mean(abs(raw) < TOL),
          sd = sd(raw)), by = grp]
  }))
setorder(mag, arm, grp)
for (i in seq_len(nrow(mag))) with(mag[i], say(
  "  %-20s %-5s n=%7d · 중앙 %+.5f · 중앙|.| %.5f · q90 %+.5f · 양비율 %.3f · 영값 %.3f · sd %.4f",
  arm, grp, n, med, med_abs, q90, frac_pos, frac_zero, sd))
pl <- mag[arm == "plain"]
ratio_apr <- pl[grp=="04", med_abs]/pl[grp=="other", med_abs]
ratio_may <- pl[grp=="05", med_abs]/pl[grp=="other", med_abs]
say("★값 분포 배수(plain, 중앙|raw|): 4월 %.3f배 · 5월 %.3f배 (문턱 2.0)", ratio_apr, ratio_may)

## =============================================================================
## [6] 저장
## =============================================================================
fwrite(mag, file.path(OUT, "b1_raw_magnitude_by_month.csv"))
arm_tab <- rbindlist(lapply(list(R_plain, R_ra1, R_ra2), function(r)
  data.table(arm = r$arm, n_months = r$n_months, n_obs = r$n_obs, t_nw3 = r$t_nw3,
             mean = r$mean, sd = r$sd, apr_mean = r$apr_mean, may_mean = r$may_mean,
             oth_mean = r$oth_mean, t_excl_apr_may = r$t_excl_apr_may)))
arm_tab[, delta_t_vs_plain := t_nw3 - R_plain$t_nw3]
arm_tab[, t_B_on_db_baseline := t_db + delta_t_vs_plain]
fwrite(arm_tab, file.path(OUT, "b1_arm_summary.csv"))
fwrite(rbindlist(list(R_plain$series[, arm := "plain"], R_ra1$series[, arm := "ra_rawdet"],
                      R_ra2$series[, arm := "ra_aprdet"])), file.path(OUT, "b1_coefs_by_arm.csv"))
saveRDS(list(arm_tab = arm_tab, g1 = g1, mag = mag, G1_PASS = G1_PASS, G2_PASS = G2_PASS,
             roll_days = ROLL_raw, t_db = t_db), file.path(OUT, "b1_results.rds"))
say("저장 완료 → %s", OUT)
say("★★[B 요약] G1 %s · G2 %s · t_plain %+.4f → t_RA(4월한정) %+.4f (Δ %+.4f) ⇒ DB이식 t_B %+.4f",
    if (G1_PASS) "PASS" else "FAIL", if (G2_PASS) "PASS" else "FAIL",
    R_plain$t_nw3, R_ra2$t_nw3, d2, t_db + d2)
