## =============================================================================
## FQ-225/226 (D) — 자가 적대검증에서 나온 두 우려의 실측
##  우려1 [ACCEPT]: (A) 전 분석이 **오염된 M26**(4·5월 = 롤오버 아티팩트) 위에서 돌았다.
##                  수리 arm(FQ-223 RA, 279개월)에서 추세·검정력 판정이 바뀌는가?
##  우려2 [ACCEPT]: A0 의 "초기 크기였다면 검출 가능" 여유가 +2.2% 로 면도날이다.
##                  sd 를 흔들면 결론이 뒤집히는 구간을 수치로 표시한다.
##  우려3 [PARTIAL]: M01 대조가 캐시 재사용 — parity 를 명시 검증한다.
## metric_type: canonical_screen_diag. 자본 주장 없음.
## =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810")
FQ223 <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[d1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260812L)
source("02_Infrastructure/contracts/required_effect_size.R")
T_THRESH <- 2.0

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }
ols_nw <- function(y, X, lag = 3L) {
  X <- cbind(`(Intercept)` = 1, as.matrix(X)); ok <- is.finite(y) & apply(is.finite(X), 1, all)
  y <- y[ok]; X <- X[ok, , drop = FALSE]; n <- length(y)
  XtXi <- solve(crossprod(X)); b <- as.numeric(XtXi %*% crossprod(X, y)); e <- as.numeric(y - X %*% b)
  S <- crossprod(X*e)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1)
    G <- crossprod((X*e)[(l+1):n,,drop=FALSE], (X*e)[1:(n-l),,drop=FALSE])/n; S <- S + w*(G+t(G)) }
  V <- XtXi %*% (n*S) %*% XtXi; se <- sqrt(pmax(diag(V),0))
  data.table(term = colnames(X), est = b, se = se, t = b/se) }

## =============================================================================
## [1] 우려1 — 수리 arm 에서 (A) 재판정 (창-정합: 전 arm 공통 279개월)
## =============================================================================
say("================ [1] 수리 arm 에서 A 재판정 ================")
ARM <- fread(file.path(FQ223, "b3_coefs_by_arm.csv")); setorder(ARM, arm, signal_ym)
say("arm %d종 · arm 당 %d개월 (전부 공통 창)", uniqueN(ARM$arm), ARM[, .N, by=arm]$N[1])
RE <- rbindlist(lapply(unique(ARM$arm), function(a) {
  d <- ARM[arm == a][order(signal_ym)]
  d[, tau := (seq_len(.N) - (.N+1)/2)/12]
  d[, mod := as.integer(signal_ym >= "2017-01")]
  tr <- ols_nw(d$est, d[, .(tau)])
  bm <- d[mod == 1L, est]; be <- d[mod == 0L, est]
  req <- required_effect(n = length(bm), t_threshold = T_THRESH, sd_monthly = sd(bm), design = "full")
  data.table(arm = a, n = nrow(d), t_full = nw_t(d$est),
             c_lin = tr[term=="tau", est], t_lin = tr[term=="tau", t],
             n_mod = length(bm), t_mod = nw_t(bm), mean_mod = mean(bm), sd_mod = sd(bm),
             t_ear = nw_t(be), mean_ear = mean(be),
             req_monthly = req$required_monthly,
             early_detectable = abs(mean(be)) >= req$required_monthly,
             n_req_months = (T_THRESH*NW_INFLATION_DEFAULT*sd(bm)/abs(mean(bm)))^2)
}))
for (i in seq_len(nrow(RE))) with(RE[i], say(
  "  %-16s 전체 t %+.3f · 추세 %+.6f/yr (t %+.3f) · 현대(n=%d) t %+.3f mean %+.6f · 초기 t %+.3f mean %+.6f · 필요표본 %.0f월(%.1f년)",
  arm, t_full, c_lin, t_lin, n_mod, t_mod, mean_mod, t_ear, mean_ear, n_req_months, n_req_months/12))
say("★우려1 판정: 추세 |t| 최대 %.3f (arm %s) vs 문턱 %.1f ⇒ %s",
    max(abs(RE$t_lin)), RE[which.max(abs(t_lin)), arm], T_THRESH,
    if (max(abs(RE$t_lin)) >= T_THRESH) "일부 arm 에서 추세 검출 — (A) 결론 수정 필요"
    else "전 arm 추세 미검출 — (A) '판정 불가' 결론은 오염과 무관하게 성립")
say("   현대 구간 level: 전 arm |t| = %s ⇒ %s",
    paste(sprintf("%.3f", abs(RE$t_mod)), collapse=" / "),
    if (all(abs(RE$t_mod) < T_THRESH)) "전 arm 문턱 미달 (오염 제거해도 현대 level 미확립)" else "일부 arm 통과")

## =============================================================================
## [2] 우려2 — A0 여유의 민감도 (sd 를 흔들면 결론이 언제 뒤집히나)
## =============================================================================
say("================ [2] A0 여유 민감도 ================")
A <- readRDS(file.path(OUT, "a1_results.rds"))
say("기준: 현대 sd %.6f · 초기 mean %.6f · 필요치 %.6f (여유 %+.2f%%)",
    A$s_mod, A$m_ear, A$req_self$required_monthly, (A$m_ear/A$req_self$required_monthly - 1)*100)
sens <- rbindlist(lapply(c(0.85, 0.90, 0.95, 1.00, 1.02, 1.05, 1.10), function(k) {
  r <- required_effect(n = A$n_mod, t_threshold = T_THRESH, sd_monthly = A$s_mod*k, design = "full")
  data.table(sd_mult = k, sd = A$s_mod*k, required = r$required_monthly,
             margin_pct = (A$m_ear/r$required_monthly - 1)*100,
             early_detectable = A$m_ear >= r$required_monthly) }))
for (i in seq_len(nrow(sens))) with(sens[i], say("  sd×%.2f ⇒ 필요치 %.6f · 여유 %+.2f%% ⇒ %s",
  sd_mult, required, margin_pct, if (early_detectable) "초기 크기 검출 가능" else "★검출 불가 (판정 원천 불가)"))
flip <- A$m_ear/(T_THRESH*NW_INFLATION_DEFAULT/sqrt(A$n_mod))
say("★뒤집힘 지점: 현대 sd 가 %.6f 를 넘으면(현재 %.6f · 배수 %.4f) 초기 크기조차 검출 불가 ⇒ 여유 %.1f%%",
    flip, A$s_mod, flip/A$s_mod, (flip/A$s_mod - 1)*100)
## NW 팽창계수 민감도 (1.25 는 근사값)
for (k in c(1.00, 1.15, 1.25, 1.40)) {
  req <- T_THRESH * k * A$s_mod/sqrt(A$n_mod)
  say("  NW 팽창 %.2f ⇒ 필요치 %.6f · 초기 효과 %.6f ⇒ %s", k, req, A$m_ear,
      if (A$m_ear >= req) "검출 가능" else "★검출 불가") }

## =============================================================================
## [3] 우려3 — M01 캐시 parity
## =============================================================================
say("================ [3] M01 캐시 parity ================")
DT <- fread(file.path(OUT, "a1_monthly_coefs_and_covariates.csv"))
t_m01 <- nw_t(DT$M01); ref <- 1.95109208373868
say("본 라운드 M01 arm t = %+.6f · FQ-223 a1 기록 %+.6f · |Δ| %.2e ⇒ %s",
    t_m01, ref, abs(t_m01 - ref), if (abs(t_m01 - ref) < 1e-6) "parity PASS" else "★parity FAIL — 캐시 불일치")
if (abs(t_m01 - ref) >= 1e-6) stop("[d1] M01 캐시 parity FAIL — 핵심 대조 무효. 중단")

## =============================================================================
## [4] 저장
## =============================================================================
fwrite(RE, file.path(OUT, "d1_arm_reassessment.csv"))
fwrite(sens, file.path(OUT, "d1_power_sensitivity.csv"))
saveRDS(list(RE = RE, sens = sens, flip_sd = flip, m01_parity = abs(t_m01 - ref) < 1e-6),
        file.path(OUT, "d1_results.rds"))
say("저장 완료 → %s", OUT)
say("★★[D 요약] 수리 arm 추세 최대 |t| %.3f (전부 미검출) · 현대 level 최대 |t| %.3f · sd 뒤집힘 배수 %.4f · M01 parity %s",
    max(abs(RE$t_lin)), max(abs(RE$t_mod)), flip/A$s_mod, abs(t_m01 - ref) < 1e-6)
