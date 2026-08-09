## =============================================================================
## FQ-226 (C) — ①순열검정 보정(음성 대조가 0.077 로 부풀었음) ②기전 최종 구별
##
## b1 이 남긴 두 숙제:
##  (1) 음성 대조 오탐률 0.0767 (명목 0.05, n=300 ⇒ 95%CI [0.049,0.111]) — 경계.
##      n 을 키워 실측하고, **경험적으로 보정한 문턱**으로 p 를 다시 읽는다.
##  (2) 4월 초과가 M26 고유인가, 모멘텀-계열 공통(M01)의 누출인가.
##      ⇒ M01 계수를 통제한 뒤에도 M26 의 4월 더미가 살아남는가 (결정적 구별).
##      ⇒ 롤오버-수리 arm 의 잔여 4월 초과가 순열 문턱을 넘는가.
## metric_type: canonical_screen_diag. 자본 주장 없음.
## =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810")
FQ223 <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[c1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260811L)
MONS <- sprintf("%02d", 1:12); B <- 20000L; NC <- 3000L

DT <- fread(file.path(OUT, "a1_monthly_coefs_and_covariates.csv"))
DT[, mon := sprintf("%02d", as.integer(substr(signal_ym, 6, 7)))]
DT[, yr := as.integer(substr(signal_ym, 1, 4))]; setorder(DT, signal_ym)
YRS <- sort(unique(DT$yr))
to_mat <- function(v) { M <- matrix(NA_real_, length(YRS), 12, dimnames = list(YRS, MONS))
  M[cbind(match(DT$yr, YRS), match(DT$mon, MONS))] <- v; M }
cmn <- function(M) colMeans(M, na.rm = TRUE)
perm_rows <- function(M) { for (i in seq_len(nrow(M))) { o <- which(!is.na(M[i, ]))
  if (length(o) > 1L) M[i, o] <- M[i, sample(o)] }; M }
say("입력 %d개월 · %d연 · 관측 패턴 보존 순열", nrow(DT), length(YRS))

## =============================================================================
## [1] 순열 분포 pool + 경험적 보정
## =============================================================================
say("================ [1] pool + 경험적 1종 오류 보정 ================")
M26 <- to_mat(DT$M26_Revenue_Mom)
pool <- t(vapply(seq_len(B), function(b) { cm <- cmn(perm_rows(M26))
  c(mx = max(cm), apr = cm[["04"]], nb = cm[["04"]] - mean(c(cm[["03"]], cm[["05"]]))) }, numeric(3)))
pval <- function(stat, col) (1 + sum(pool[, col] >= stat))/(B + 1)
obs <- cmn(M26)
o_mx <- max(obs); o_apr <- obs[["04"]]; o_nb <- obs[["04"]] - mean(c(obs[["03"]], obs[["05"]]))
p_mx <- pval(o_mx, "mx"); p_apr <- pval(o_apr, "apr"); p_nb <- pval(o_nb, "nb")
say("관측: max %+.6f (p %.4f) · 4월 %+.6f (p %.4f) · 이웃차 %+.6f (p %.4f)", o_mx, p_mx, o_apr, p_apr, o_nb, p_nb)

## 음성 대조 — 독립 가짜 계열 NC 개의 p 분포
fk <- t(vapply(seq_len(NC), function(i) { cm <- cmn(perm_rows(M26))
  c(pval(max(cm), "mx"), pval(cm[["04"]], "apr"),
    pval(cm[["04"]] - mean(c(cm[["03"]], cm[["05"]])), "nb")) }, numeric(3)))
colnames(fk) <- c("mx","apr","nb")
say("--- 음성 대조 (가짜 계열 %d개) ---", NC)
for (cc in colnames(fk)) {
  r05 <- mean(fk[, cc] < 0.05); r10 <- mean(fk[, cc] < 0.10)
  se <- sqrt(0.05*0.95/NC)
  say("  %-4s 오탐률 <0.05 = %.4f (명목 0.05 · ±%.4f) · <0.10 = %.4f · ★보정 문턱(경험 5%%분위) = %.4f",
      cc, r05, 1.96*se, r10, quantile(fk[, cc], 0.05, names = FALSE))
}
cal <- vapply(colnames(fk), function(cc) quantile(fk[, cc], 0.05, names = FALSE), 0)
say("★보정 후 재판정: max p %.4f vs 보정문턱 %.4f ⇒ %s", p_mx, cal[["mx"]],
    if (p_mx < cal[["mx"]]) "유의" else "비유의")
say("★보정 후 재판정: 4월 p %.4f vs 보정문턱 %.4f ⇒ %s", p_apr, cal[["apr"]],
    if (p_apr < cal[["apr"]]) "유의 (사전지정 단일가설)" else "비유의")
say("★보정 후 재판정: 이웃차 p %.4f vs 보정문턱 %.4f ⇒ %s", p_nb, cal[["nb"]],
    if (p_nb < cal[["nb"]]) "유의" else "비유의")

## =============================================================================
## [2] 표준화 4월 초과 — 계열 간 크기 비교 (스케일 제거)
## =============================================================================
say("================ [2] 표준화 4월 초과 (계열 간 비교) ================")
SER <- c("M26_Revenue_Mom","C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M01","intercept")
FAM <- c(M26_Revenue_Mom = "모멘텀(전망 개정)", C01_SUE = "서프라이즈(수준)",
         C02_EPS_Chg_1m = "모멘텀(전망 개정)", C04_ESBR = "서프라이즈(수준)",
         M01 = "모멘텀(가격)", intercept = "수준(시장)")
STD <- rbindlist(lapply(SER, function(s) {
  v <- DT[[s]]; a <- mean(v[DT$mon == "04"]); o <- mean(v[DT$mon != "04"])
  data.table(series = s, family = FAM[[s]], apr = a, oth = o, excess = a - o,
             sd_series = sd(v), std_excess = (a - o)/sd(v))
}))[order(-std_excess)]
for (i in seq_len(nrow(STD))) with(STD[i], say("  %-16s [%-16s] 4월초과 %+.6f · 계열 sd %.6f · ★표준화 %+.4f",
                                               series, family, excess, sd_series, std_excess))
say("★가족별 표준화 초과 평균: 모멘텀 %+.4f · 서프라이즈 %+.4f · 수준 %+.4f",
    STD[family %like% "모멘텀", mean(std_excess)], STD[family %like% "서프라이즈", mean(std_excess)],
    STD[family %like% "수준", mean(std_excess)])

## =============================================================================
## [3] ★결정적 구별 — M01 통제 후 M26 의 4월이 남는가
## =============================================================================
say("================ [3] M01 통제 후 4월 더미 (결정적 구별) ================")
nw_ols <- function(y, X, lag = 3L) {
  X <- cbind(`(Intercept)` = 1, as.matrix(X)); ok <- is.finite(y) & apply(is.finite(X), 1, all)
  y <- y[ok]; X <- X[ok, , drop = FALSE]; n <- length(y)
  XtXi <- solve(crossprod(X)); b <- as.numeric(XtXi %*% crossprod(X, y)); e <- as.numeric(y - X %*% b)
  S <- crossprod(X * e)/n
  for (l in 1:lag) { w <- 1 - l/(lag + 1)
    G <- crossprod((X*e)[(l+1):n, , drop=FALSE], (X*e)[1:(n-l), , drop=FALSE])/n; S <- S + w*(G + t(G)) }
  V <- XtXi %*% (n*S) %*% XtXi; se <- sqrt(pmax(diag(V), 0))
  data.table(term = colnames(X), est = b, se = se, t = b/se)
}
DT[, apr := as.integer(mon == "04")]
m_a <- nw_ols(DT$M26_Revenue_Mom, DT[, .(apr)])
m_b <- nw_ols(DT$M26_Revenue_Mom, DT[, .(apr, M01)])
m_c <- nw_ols(DT$M26_Revenue_Mom, DT[, .(apr, M01, C02_EPS_Chg_1m, C01_SUE, C04_ESBR)])
show <- function(r, lab) say("  %-24s 4월더미 %+.6f (t %+.3f)%s", lab, r[term=="apr", est], r[term=="apr", t],
  if (nrow(r) > 2) sprintf(" · 통제 [%s]", paste(sprintf("%s t=%+.2f", r[!term %in% c("(Intercept)","apr"), term],
                                                          r[!term %in% c("(Intercept)","apr"), t]), collapse=" · ")) else "")
show(m_a, "M26 ~ 4월"); show(m_b, "M26 ~ 4월 + M01"); show(m_c, "M26 ~ 4월 + 전 계열")
ret_b <- m_b[term=="apr", est]/m_a[term=="apr", est]
say("★M01 통제 후 4월 더미 잔존율 %.3f (t %+.3f → %+.3f) ⇒ %s", ret_b, m_a[term=="apr", t], m_b[term=="apr", t],
    if (abs(m_b[term=="apr", t]) >= 2.0 && ret_b >= 0.5) "M26 고유 4월 효과 존재 (모멘텀 공통으로 환원 안 됨)"
    else "모멘텀 공통 성분으로 상당 부분 흡수")
## 역방향 — M26 통제 후 M01 의 4월이 남는가 (대칭 확인)
m_d <- nw_ols(DT$M01, DT[, .(apr)]); m_e <- nw_ols(DT$M01, DT[, .(apr, M26_Revenue_Mom)])
say("  역방향: M01~4월 더미 %+.6f (t %+.3f) → M26 통제 후 %+.6f (t %+.3f · 잔존율 %.3f)",
    m_d[term=="apr", est], m_d[term=="apr", t], m_e[term=="apr", est], m_e[term=="apr", t],
    m_e[term=="apr", est]/m_d[term=="apr", est])

## =============================================================================
## [4] 롤오버-수리 잔여 4월이 순열 문턱을 넘는가
## =============================================================================
say("================ [4] 수리 arm 잔여 4월 ================")
ARM <- fread(file.path(FQ223, "b3_coefs_by_arm.csv"))
ARM[, mon := sprintf("%02d", as.integer(substr(signal_ym, 6, 7)))]
ARM[, yr := as.integer(substr(signal_ym, 1, 4))]
perm_arm <- function(a, Bn = 8000L) {
  d <- ARM[arm == a][order(signal_ym)]
  ys <- sort(unique(d$yr)); M <- matrix(NA_real_, length(ys), 12, dimnames = list(ys, MONS))
  M[cbind(match(d$yr, ys), match(d$mon, MONS))] <- d$est
  ob <- colMeans(M, na.rm = TRUE)
  st <- ob[["04"]] - mean(ob[MONS != "04"], na.rm = TRUE)
  pp <- vapply(seq_len(Bn), function(b) { cm <- colMeans(perm_rows(M), na.rm = TRUE)
    cm[["04"]] - mean(cm[MONS != "04"], na.rm = TRUE) }, 0)
  data.table(arm = a, apr_excess = st, p_apr = (1 + sum(pp >= st))/(Bn + 1))
}
AR <- rbindlist(lapply(unique(ARM$arm), perm_arm))
for (i in seq_len(nrow(AR))) with(AR[i], say("  %-16s 4월 초과 %+.6f · 순열 p %.4f", arm, apr_excess, p_apr))
e_p <- AR[arm == "plain(재구성)", apr_excess]; e_r <- AR[arm == "RA_4월탐지", apr_excess]
say("★수리 후 잔여 4월: 초과 %+.6f (plain 대비 %.3f) · p %.4f ⇒ %s",
    e_r, e_r/e_p, AR[arm == "RA_4월탐지", p_apr],
    if (AR[arm == "RA_4월탐지", p_apr] < 0.05) "롤오버 제거 후에도 4월 잔존 — 롤오버 단독 기전 기각"
    else "롤오버 제거 후 4월 소멸 — 롤오버가 4월의 주된 원인")
say("  가짜 basis 통제: FAKE_10/1 %+.6f (p %.4f) · FAKE_7/1 %+.6f (p %.4f) — 수리 형식만으로는 4월이 안 죽어야 함",
    AR[arm %like% "10/1", apr_excess], AR[arm %like% "10/1", p_apr],
    AR[arm %like% "7/1", apr_excess], AR[arm %like% "7/1", p_apr])

## =============================================================================
## [5] 저장
## =============================================================================
fwrite(STD, file.path(OUT, "c1_standardized_april_excess.csv"))
fwrite(AR,  file.path(OUT, "c1_arm_april_permutation.csv"))
fwrite(data.table(stat = c("max","apr","nb"), p_raw = c(p_mx, p_apr, p_nb),
                  emp_fp_05 = c(mean(fk[,"mx"]<0.05), mean(fk[,"apr"]<0.05), mean(fk[,"nb"]<0.05)),
                  calibrated_cutoff = as.numeric(cal)),
       file.path(OUT, "c1_permutation_calibration.csv"))
saveRDS(list(p_mx=p_mx, p_apr=p_apr, p_nb=p_nb, cal=cal, fk_rate=colMeans(fk<0.05),
             STD=STD, dummy_a=m_a, dummy_b=m_b, dummy_c=m_c, ret_b=ret_b, AR=AR),
        file.path(OUT, "c1_results.rds"))
say("저장 완료 → %s", OUT)
say("★★[C 요약] 보정 오탐률 %.4f/%.4f/%.4f · 4월 p %.4f(보정문턱 %.4f) · M01통제 잔존율 %.3f(t %+.3f) · 수리후 4월 p %.4f",
    mean(fk[,"mx"]<0.05), mean(fk[,"apr"]<0.05), mean(fk[,"nb"]<0.05), p_apr, cal[["apr"]], ret_b,
    m_b[term=="apr", t], AR[arm=="RA_4월탐지", p_apr])
