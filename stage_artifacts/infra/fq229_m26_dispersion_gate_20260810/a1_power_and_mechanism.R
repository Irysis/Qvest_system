## =============================================================================
## FQ-229 (A) — 검정력 선판정 → 기전 분해(스케일 vs 기술) → 차등 loading
## 사전등록: PREREG.md §2 §5 §7 (실행 전 고정)
## metric_type: canonical_screen_diag. 자본 주장 없음.
## ★분할 금지 — 연속 회귀. lag1 만 사용(동시점 disp 는 소비 불가).
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT   <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
SRC   <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
FQ223 <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[a1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260810L)
source("02_Infrastructure/contracts/required_effect_size.R")
T_THRESH <- 2.0; NWLAG <- 3L; BURN <- 24L
FACS <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "M26_Revenue_Mom")
TARGET <- "M26_Revenue_Mom"

nw_t <- function(x, lag = NWLAG) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}
ols_nw <- function(y, X, lag = NWLAG) {
  X <- cbind(`(Intercept)` = 1, as.matrix(X)); ok <- is.finite(y) & apply(is.finite(X), 1, all)
  y <- y[ok]; X <- X[ok, , drop = FALSE]; n <- length(y)
  XtXi <- tryCatch(solve(crossprod(X)), error = function(e) NULL); if (is.null(XtXi)) return(NULL)
  b <- as.numeric(XtXi %*% crossprod(X, y)); e <- as.numeric(y - X %*% b)
  S <- crossprod(X * e) / n
  for (l in 1:lag) { w <- 1 - l/(lag + 1)
    G <- crossprod((X*e)[(l+1):n, , drop = FALSE], (X*e)[1:(n-l), , drop = FALSE]) / n
    S <- S + w * (G + t(G)) }
  V <- XtXi %*% (n * S) %*% XtXi; se <- sqrt(pmax(diag(V), 0))
  data.table(term = colnames(X), est = b, se = se, t = b/se, n = n,
             r2 = 1 - sum(e^2)/sum((y - mean(y))^2))
}
fmb_coefs <- function(dat, xs, ycol = "Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse = " + ")))
  dat[, { fit <- tryCatch(lm(f, data = .SD), error = function(e) NULL)
    if (is.null(fit)) .(term = character(0), est = numeric(0))
    else { cf <- coef(fit); .(term = names(cf), est = as.numeric(cf)) } },
    by = signal_ym, .SDcols = c(ycol, xs)]
}

## ============================================================ [0] 입력 · parity
say("================ [0] 입력 실측 · parity ================")
D <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet"))); D[, Date := as.Date(Date)]
say("★입력 실측: %d행 · 관측단위 (signal_ym x Ticker) · %d개월 %s~%s · Ticker %d",
    nrow(D), uniqueN(D$signal_ym), min(D$signal_ym), max(D$signal_ym), uniqueN(D$Ticker))
CF <- fmb_coefs(D, FACS)
CW <- dcast(CF, signal_ym ~ term, value.var = "est"); setnames(CW, "(Intercept)", "intercept")
setorder(CW, signal_ym)
t_par <- nw_t(CW[[TARGET]])
say("z(M26) FMB NW(3) t = %+.4f (n=%d) · 08-08 기록 +2.5553/283", t_par, nrow(CW))
if (abs(t_par - 2.5552525842524) > 1e-3 || nrow(CW) != 283L) stop("[a1] parity FAIL — 정지")
say("parity PASS")

## M01 대조 arm (FQ-223 캐시 재사용 — factor_db 재빌드 금지)
m01f <- file.path(FQ223, "a1_m01_panel.rds")
if (!file.exists(m01f)) stop("[a1] M01 캐시 부재 — 0은 정지 신호")
M01 <- as.data.table(readRDS(m01f)); M01[, Date := as.Date(Date)]
DM <- merge(D[, .(signal_ym, Date, Ticker, C01_SUE, C02_EPS_Chg_1m, C04_ESBR, Ret_1m)], M01,
            by = c("Date", "Ticker"))
DM <- DM[complete.cases(DM[, .(C01_SUE, C02_EPS_Chg_1m, C04_ESBR, M01, Ret_1m)])]
DM <- DM[signal_ym %in% DM[, .N, by = signal_ym][N >= 30L, signal_ym]]
CFM <- fmb_coefs(DM, c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "M01"))
say("M01 arm: %d행 · %d개월", nrow(DM), uniqueN(DM$signal_ym))
t_m01 <- nw_t(dcast(CFM[term == "M01"], signal_ym ~ term, value.var = "est")$M01)
say("M01 arm t = %+.6f · FQ-223 기록 +1.951092 · |Δ| %.2e ⇒ %s", t_m01, abs(t_m01 - 1.95109208373868),
    if (abs(t_m01 - 1.95109208373868) < 1e-6) "parity PASS" else "★parity FAIL")
if (abs(t_m01 - 1.95109208373868) >= 1e-6) stop("[a1] M01 캐시 parity FAIL — 대조 무효. 정지")

## ============================================================ [1] 월별 성분
say("================ [1] 월별 성분 (disp · sd_z · 표준화 기울기) ================")
MV <- D[, .(N_t = .N, disp_t = sd(Ret_1m),
            sdz_C01_SUE = sd(C01_SUE), sdz_C02_EPS_Chg_1m = sd(C02_EPS_Chg_1m),
            sdz_C04_ESBR = sd(C04_ESBR), sdz_M26_Revenue_Mom = sd(M26_Revenue_Mom)),
        by = signal_ym][order(signal_ym)]
MVm <- DM[, .(disp_m01_t = sd(Ret_1m), sdz_M01 = sd(M01)), by = signal_ym]
DT <- merge(CW, MV, by = "signal_ym")
DT <- merge(DT, merge(dcast(CFM[term == "M01"], signal_ym ~ term, value.var = "est"), MVm,
                      by = "signal_ym"), by = "signal_ym", all.x = TRUE)
setorder(DT, signal_ym)
DT[, disp_lag1 := shift(disp_t, 1L)]

## 표준화 부분기울기 std_slope = b * sd(z) / disp  (항등식 b = std_slope * disp / sd_z)
for (f in FACS) DT[, (paste0("ss_", f)) := get(f) * get(paste0("sdz_", f)) / disp_t]
DT[, ss_M01 := M01 * sdz_M01 / disp_m01_t]
say("std_slope 중앙값: %s", paste(sprintf("%s %.4f", c(FACS, "M01"),
    sapply(c(paste0("ss_", FACS), "ss_M01"), function(cc) median(DT[[cc]], na.rm = TRUE))), collapse = " · "))
## 항등식 무결성 (재구성 오차 0 이어야 함)
recon_err <- max(abs(DT[["ss_M26_Revenue_Mom"]] * DT$disp_t / DT$sdz_M26_Revenue_Mom - DT[[TARGET]]), na.rm = TRUE)
say("★항등식 재구성 최대오차 %.3e ⇒ %s", recon_err, if (recon_err < 1e-12) "항등식 성립" else "★불일치 — 정지")
if (!(recon_err < 1e-12)) stop("[a1] 항등식 재구성 FAIL")

## 확장창 게이트 재료 (PIT-safe) — 판정용 g 는 회귀에서 affine 불변이므로 raw lag 사용
DT[, g_exp := { v <- rep(NA_real_, .N)
  for (i in seq_len(.N)) if (i > BURN) { h <- disp_lag1[1:i]; h <- h[is.finite(h)]
    if (length(h) >= BURN) v[i] <- (disp_lag1[i] - mean(h)) / sd(h) }
  v }]
say("확장창 g 유효 %d개월 (burn-in %d) · 범위 %.3f ~ %.3f",
    sum(is.finite(DT$g_exp)), BURN, min(DT$g_exp, na.rm = TRUE), max(DT$g_exp, na.rm = TRUE))
say("※ OLS 기울기 t 는 회귀변수의 affine 변환에 불변이므로 S1~S3 는 raw disp_lag1 로 적합한다(동일 t).")

## ============================================================ [2] 외부 기준 바 재료
say("================ [2] 동시점 disp 계수 (외부 기준 바 재료) ================")
r_con <- ols_nw(DT[[TARGET]], DT[, .(disp_t)])
c_con <- r_con[term == "disp_t", est]; t_con <- r_con[term == "disp_t", t]
say("동시점: b_t ~ disp_t ⇒ 계수 %+.6f (t %+.3f · R2 %.4f) [FQ-225 nested t +3.63/+4.14 계열]", c_con, t_con, r_con$r2[1])
AC1 <- cor(DT$disp_t, DT$disp_lag1, use = "complete.obs")
ext_expected <- c_con * AC1
say("★외부 기준 효과 = 동시점 계수 x lag1 자기상관 %.4f = %+.6f", AC1, ext_expected)
say("   (해석: lag1 이 동시점과 같은 기전을 담았다면 관측되어야 할 기울기)")

## ============================================================ [3] (C) 검정력 선판정
say("================ [3] (C) 검정력 선판정 — 착수 게이트 ================")
pc_row <- function(yname, y, x, lab, design = "full", frac = NA_real_) {
  ok <- is.finite(y) & is.finite(x); y <- y[ok]; x <- x[ok]; n <- length(y)
  r <- ols_nw(y, data.table(x = x)); c_obs <- r[term == "x", est]; se_obs <- r[term == "x", se]
  ## 기울기 단위로 스케일 맞춤: se_c ~ sd(y)/(sd(x) sqrt(n)) x nw_inflation
  sdm <- sd(y) / sd(x)
  req <- if (design == "full") required_effect(n = n, t_threshold = T_THRESH, sd_monthly = sdm, design = "full")
         else required_effect(n = n, t_threshold = T_THRESH, sd_monthly = sdm, design = "interaction", regime_frac = frac)
  vp <- verdict_with_power(observed_t = abs(r[term == "x", t]), observed_monthly = abs(c_obs),
                           n = n, t_threshold = T_THRESH, sd_monthly = sdm,
                           design = if (design == "full") "full" else "interaction", regime_frac = if (is.na(frac)) 0.35 else frac)
  data.table(spec = lab, y = yname, n = n, design = design,
             c_obs = c_obs, se_obs = se_obs, t_obs = r[term == "x", t],
             req_slope_tool = req$required_monthly, req_slope_exact = T_THRESH * se_obs,
             verdict = vp$verdict, implied_t = vp$implied_t_threshold, bar_restates_t = vp$bar_restates_t)
}
PC <- rbindlist(list(
  pc_row("b_M26",  DT[[TARGET]],            DT$disp_lag1, "PC1-S1 연속(전표본)"),
  pc_row("ss_M26", DT[["ss_M26_Revenue_Mom"]], DT$disp_lag1, "PC1-S2 연속(전표본)"),
  pc_row("b_M26",  DT[[TARGET]],            DT$disp_lag1, "PC2 이진 상위30%", "interaction", 0.30),
  pc_row("b_M26",  DT[[TARGET]],            DT$disp_lag1, "PC2 이진 상위50%", "interaction", 0.50)))
for (i in seq_len(nrow(PC))) with(PC[i], say(
  "  %-22s y=%-7s n=%3d · 관측 %+.6f (t %+.3f) · 필요(도구) %.6f · 필요(정확 se) %.6f · %s (implied_t %.2f · 재진술 %s)",
  spec, y, n, c_obs, t_obs, req_slope_tool, req_slope_exact, verdict, implied_t, bar_restates_t))

req_full <- PC[spec == "PC1-S1 연속(전표본)", req_slope_exact]
GO <- abs(ext_expected) >= req_full
say("★★착수 게이트: 외부 기준 효과 %+.6f vs 연속설계 필요 기울기(정확 se) %.6f ⇒ %s",
    ext_expected, req_full,
    if (GO) "착수 — lag1 이 동시점 기전을 담았다면 이 표본으로 검출 가능" else "폐기 — 원리적으로 판정 불가")
say("   여유 %.1f%% (배수 %.3f)", (abs(ext_expected)/req_full - 1)*100, abs(ext_expected)/req_full)
req_bin30 <- PC[spec == "PC2 이진 상위30%", req_slope_tool]
say("   이진 상위30%% 게이트: 유효 n = %.1f · 필요 기울기 %.6f ⇒ %s",
    283*0.30*0.70, req_bin30, if (abs(ext_expected) >= req_bin30) "검출 가능" else "★판정 불가 라벨 (연속 arm 만 판정)")

## ============================================================ [4] (B) 기전 분해 S1/S2/S3
say("================ [4] (B) 기전 분해 — S1 스케일 · S2 기술 · S3 차등 ================")
chan <- function(ycol, lab, dat = DT) {
  r <- ols_nw(dat[[ycol]], dat[, .(disp_lag1)])
  data.table(series = lab, y = ycol, c = r[term=="disp_lag1", est], se = r[term=="disp_lag1", se],
             t = r[term=="disp_lag1", t], r2 = r$r2[1], n = r$n[1])
}
S1 <- rbindlist(lapply(c(FACS, "M01"), function(f) chan(f, paste0("S1 b_", f))))
S2 <- rbindlist(lapply(c(paste0("ss_", FACS), "ss_M01"), function(f) chan(f, paste0("S2 ", f))))
## S3 차등: M26 표준화기울기 − 나머지 3종 평균
DT[, ss_others := rowMeans(.SD, na.rm = TRUE), .SDcols = paste0("ss_", setdiff(FACS, TARGET))]
DT[, ss_diff := ss_M26_Revenue_Mom - ss_others]
S3 <- chan("ss_diff", "S3 차등(M26 − 타3종 평균)")
say("--- S1 스케일 채널 (b_t ~ disp_{t-1}) ---")
for (i in seq_len(nrow(S1))) with(S1[i], say("  %-24s c %+.6f (t %+.3f · R2 %.4f · n %d)", series, c, t, r2, n))
say("--- S2 기술 채널 (표준화 기울기 ~ disp_{t-1}) ---")
for (i in seq_len(nrow(S2))) with(S2[i], say("  %-24s c %+.6f (t %+.3f · R2 %.4f · n %d)", series, c, t, r2, n))
with(S3, say("--- S3 차등 --- c %+.6f (t %+.3f · R2 %.4f · n %d)", c, t, r2, n))

s1_m26 <- S1[y == TARGET]; s2_m26 <- S2[y == paste0("ss_", TARGET)]
s1_sig <- abs(s1_m26$t) >= T_THRESH; s2_sig <- abs(s2_m26$t) >= T_THRESH; s3_sig <- abs(S3$t) >= T_THRESH
MECH <- if (s1_sig && !s2_sig) "순수 스케일 — 분산 의존은 기계적 항등식의 재진술. 위험조정 소비 근거 없음" else
        if (s2_sig) "기술 조건부 — 고분산 달에 상관 자체가 상승. 소비 후보 성립" else
        if (!s1_sig) "lag1 의존 자체가 미검출 — 동시점 의존이 lag1 로 전이되지 않음" else "혼합"
say("★기전 판정: S1 %s (t %+.3f) · S2 %s (t %+.3f) · S3 %s (t %+.3f) ⇒ %s",
    ifelse(s1_sig,"유의","비유의"), s1_m26$t, ifelse(s2_sig,"유의","비유의"), s2_m26$t,
    ifelse(s3_sig,"유의","비유의"), S3$t, MECH)

## 양성 대조 판별: S1 이 전 팩터 공통이면 S1 은 판별력 없음
s1_all_sig <- all(abs(S1$t) >= T_THRESH)
say("★대조 진단: S1 전 5축 |t| = %s ⇒ %s", paste(sprintf("%.2f", abs(S1$t)), collapse=" / "),
    if (s1_all_sig) "전 팩터 공통 = S1 은 기전 판별력 없음(기계적 스케일 확증)" else "일부만 유의 = S1 에 팩터 고유성 잔존")
s2_sig_which <- S2[abs(t) >= T_THRESH, series]
say("   S2 유의 축: %s", if (length(s2_sig_which)) paste(s2_sig_which, collapse=" / ") else "0건 (대조 유효 — 기술 채널은 어느 축에도 없음)")

## ============================================================ [5] 저장
fwrite(DT, file.path(OUT, "a1_monthly_components.csv"))
fwrite(PC, file.path(OUT, "a1_power_precheck.csv"))
fwrite(rbindlist(list(S1, S2, S3), fill = TRUE), file.path(OUT, "a1_channels.csv"))
saveRDS(list(DT = DT, PC = PC, S1 = S1, S2 = S2, S3 = S3, c_con = c_con, t_con = t_con,
             AC1 = AC1, ext_expected = ext_expected, req_full = req_full, GO = GO,
             MECH = MECH, s1_sig = s1_sig, s2_sig = s2_sig, s3_sig = s3_sig,
             s1_all_sig = s1_all_sig, t_par = t_par, t_m01 = t_m01),
        file.path(OUT, "a1_results.rds"))
say("저장 완료 -> %s", OUT)
say("★★[A 요약] 착수게이트 %s · 기전 %s · S1 t %+.3f / S2 t %+.3f / S3 t %+.3f",
    if (GO) "착수" else "폐기", MECH, s1_m26$t, s2_m26$t, S3$t)
