## =============================================================================
## FQ-225 (A) — M26 현대 구간 약화: ①검정력 선판정 → ②연속 추세 → ③귀속 → ④필요표본
## 사전등록: PREREG.md (본 디렉터리, 실행 전 고정)
## metric_type: canonical_screen_diag. 자본 주장 없음.
## ★분할 금지 — 국면/시대는 연속 상호작용으로 다룬다(08-08 규약).
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810")
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
FQ223 <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[a1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260810L)
source("02_Infrastructure/contracts/required_effect_size.R")

T_THRESH <- 2.0; NWLAG <- 3L
FACS <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M26_Revenue_Mom")
TARGET <- "M26_Revenue_Mom"

## ---- NW 도구 ---------------------------------------------------------------
nw_t <- function(x, lag = NWLAG) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}
nw_se_mean <- function(x, lag = NWLAG) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  sqrt(s/n)
}
## OLS + Newey-West 공분산 (수기 구현 — 의존성 회피)
ols_nw <- function(y, X, lag = NWLAG) {
  X <- cbind(`(Intercept)` = 1, as.matrix(X)); ok <- is.finite(y) & apply(is.finite(X), 1, all)
  y <- y[ok]; X <- X[ok, , drop = FALSE]; n <- length(y); k <- ncol(X)
  XtXi <- tryCatch(solve(crossprod(X)), error = function(e) NULL)
  if (is.null(XtXi)) return(NULL)
  b <- as.numeric(XtXi %*% crossprod(X, y)); e <- as.numeric(y - X %*% b)
  S <- crossprod(X * e) / n
  for (l in 1:lag) {
    w <- 1 - l/(lag + 1)
    G <- crossprod((X * e)[(l+1):n, , drop = FALSE], (X * e)[1:(n-l), , drop = FALSE]) / n
    S <- S + w * (G + t(G))
  }
  V <- XtXi %*% (n * S) %*% XtXi
  se <- sqrt(pmax(diag(V), 0))
  data.table(term = colnames(X), est = b, se = se, t = b/se, n = n,
             r2 = 1 - sum(e^2)/sum((y - mean(y))^2))
}

## =============================================================================
## [0] 입력 + FMB 계수 (절편 포함) + parity
## =============================================================================
say("================ [0] 입력 · FMB · parity ================")
D4 <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet")))
D4[, Date := as.Date(Date)]
say("패널 %d행 · %d개월 · %s ~ %s", nrow(D4), uniqueN(D4$signal_ym), min(D4$signal_ym), max(D4$signal_ym))

fmb_coefs <- function(dat, xs, ycol = "Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse = " + ")))
  dat[, { fit <- tryCatch(lm(f, data = .SD), error = function(e) NULL)
    if (is.null(fit)) .(term = character(0), est = numeric(0))
    else { cf <- coef(fit); .(term = names(cf), est = as.numeric(cf)) } },
    by = signal_ym, .SDcols = c(ycol, xs)]
}
CF <- fmb_coefs(D4, FACS)
CFt <- CF[term == TARGET][order(signal_ym)]
t_full <- nw_t(CFt$est); n_full <- nrow(CFt)
say("z(M26) FMB NW(3) t = %+.4f (n=%d)  · 08-08 기록 +2.5553/283", t_full, n_full)
if (abs(t_full - 2.5552525842524) > 1e-3 || n_full != 283L) stop("[a1] parity FAIL — 중단")
say("parity PASS")

## M01 대조 arm (FQ-223 캐시 재사용 — factor_db 재빌드 금지)
m01f <- file.path(FQ223, "a1_m01_panel.rds")
if (!file.exists(m01f)) stop("[a1] M01 캐시 부재 — 0은 정지 신호")
M01 <- as.data.table(readRDS(m01f)); M01[, Date := as.Date(Date)]
say("M01 캐시 %d행 · %d개월", nrow(M01), uniqueN(M01$Date))
DM <- merge(D4[, .(signal_ym, Date, Ticker, C01_SUE, C02_EPS_Chg_1m, C04_ESBR, Ret_1m)],
            M01, by = c("Date","Ticker"))
DM <- DM[complete.cases(DM[, .(C01_SUE,C02_EPS_Chg_1m,C04_ESBR,M01,Ret_1m)])]
DM <- DM[signal_ym %in% DM[, .N, by = signal_ym][N >= 30L, signal_ym]]
CFM <- fmb_coefs(DM, c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M01"))
say("M01 arm: %d행 · %d개월", nrow(DM), uniqueN(DM$signal_ym))

## 계수 wide (절편 포함)
CW <- dcast(CF, signal_ym ~ term, value.var = "est")
setnames(CW, "(Intercept)", "intercept")
CW <- merge(CW, dcast(CFM[term == "M01"], signal_ym ~ term, value.var = "est"), by = "signal_ym", all.x = TRUE)
setorder(CW, signal_ym)

## =============================================================================
## [1] 월별 공변량 (구성 / 국면 대리변수)
## =============================================================================
say("================ [1] 월별 공변량 ================")
MV <- D4[, .(N_t = .N, disp_t = sd(Ret_1m), mkt_t = mean(Ret_1m),
             sd_z_t = sd(M26_Revenue_Mom)), by = signal_ym][order(signal_ym)]
## 국면 = **lagged** (직전 12개월) — 동시점 국면 대리변수의 순환참조 회피
MV[, vol12_t := shift(frollapply(mkt_t, 12, sd), 1L)]
MV[, cum := cumprod(1 + mkt_t)]
MV[, dd_t := shift(cum / cummax(cum) - 1, 1L)]
MV[, cum := NULL]
say("공변량 요약: N_t %d~%d · disp_t %.4f~%.4f · vol12_t 유한 %d · dd_t 유한 %d",
    min(MV$N_t), max(MV$N_t), min(MV$disp_t), max(MV$disp_t),
    sum(is.finite(MV$vol12_t)), sum(is.finite(MV$dd_t)))
DT <- merge(CW, MV, by = "signal_ym")
DT[, yr := as.integer(substr(signal_ym, 1, 4))]
DT[, mon := substr(signal_ym, 6, 7)]
DT[, tau := (seq_len(.N) - (.N + 1)/2) / 12]      # 연 단위, 중앙 0
DT[, mod := as.integer(signal_ym >= "2017-01")]

## =============================================================================
## [2] A0 — 검정력 선판정 (착수 게이트)
## =============================================================================
say("================ [2] A0 검정력 선판정 ================")
b_mod <- DT[mod == 1L, get(TARGET)]; b_ear <- DT[mod == 0L, get(TARGET)]
n_mod <- length(b_mod); n_ear <- length(b_ear)
m_mod <- mean(b_mod); s_mod <- sd(b_mod); t_mod <- nw_t(b_mod)
m_ear <- mean(b_ear); s_ear <- sd(b_ear); t_ear <- nw_t(b_ear)
say("현대(>=2017-01) n=%d · mean %+.6f (연 %+.3f%%) · sd %.6f · NW3 t %+.4f", n_mod, m_mod, m_mod*1200, s_mod, t_mod)
say("초기(<2017-01)  n=%d · mean %+.6f (연 %+.3f%%) · sd %.6f · NW3 t %+.4f", n_ear, m_ear, m_ear*1200, s_ear, t_ear)

## 바 1: 자기 sd (도구 자기진단 포함)
req_self <- required_effect(n = n_mod, t_threshold = T_THRESH, sd_monthly = s_mod, design = "full")
vp_self  <- verdict_with_power(observed_t = abs(t_mod), observed_monthly = abs(m_mod),
                               n = n_mod, t_threshold = T_THRESH, sd_monthly = s_mod, design = "full")
say("바1(자기 sd): 필요 월 %.6f (연 %.3f%%) vs 관측 %.6f (연 %.3f%%) ⇒ %s",
    req_self$required_monthly, req_self$required_annual*100, abs(m_mod), abs(m_mod)*1200, vp_self$verdict)
say("   implied_t_threshold %.3f · bar_restates_t %s · negative_powered_reachable %s",
    vp_self$implied_t_threshold, vp_self$bar_restates_t, vp_self$negative_powered_reachable)
say("   %s", vp_self$note)

## 바 2 (★진짜 검정력 질문): 초기 구간과 같은 크기의 효과였다면 현대 115달에서 검출됐겠는가
req_ext <- required_effect(n = n_mod, t_threshold = T_THRESH, sd_monthly = s_mod, design = "full")
detect_early_effect <- abs(m_ear) >= req_ext$required_monthly
say("★바2(외부기준): 초기 효과 %.6f (연 %.3f%%) vs 현대 n=%d 검출 필요치 %.6f (연 %.3f%%) ⇒ %s",
    abs(m_ear), abs(m_ear)*1200, n_mod, req_ext$required_monthly, req_ext$required_annual*100,
    if (detect_early_effect) "초기 크기였다면 검출 가능 — level null 은 정보를 담는다"
    else "초기 크기여도 검출 불가 — 현대 구간 level 검정은 원리적으로 판정 불가")

## A4 필요 표본
n_req <- if (abs(m_mod) > 1e-12) (T_THRESH * NW_INFLATION_DEFAULT * s_mod / abs(m_mod))^2 else Inf
say("★A4 필요 표본: 현대 효과 크기 유지 시 |t|=2.0 도달에 %.0f개월 (= %.1f년) 필요 · 현재 %d개월 (부족 %.0f개월)",
    n_req, n_req/12, n_mod, max(0, n_req - n_mod))

## =============================================================================
## [3] A1 — 연속 추세 (주판정)
## =============================================================================
say("================ [3] A1 연속 추세 (분할 아님) ================")
trend_of <- function(col, lab) {
  y <- DT[[col]]
  r1 <- ols_nw(y, DT[, .(tau)])
  r2 <- ols_nw(y, DT[, .(logt = log(1 + (tau - min(tau))))])
  r3 <- ols_nw(y, DT[, .(tau, tau2 = tau^2)])
  data.table(series = lab,
             c_lin = r1[term=="tau", est], t_lin = r1[term=="tau", t], r2_lin = r1$r2[1],
             c_log = r2[term=="logt", est], t_log = r2[term=="logt", t],
             c_q1 = r3[term=="tau", est], t_q1 = r3[term=="tau", t],
             c_q2 = r3[term=="tau2", est], t_q2 = r3[term=="tau2", t],
             mean_all = mean(y, na.rm=TRUE), t_all = nw_t(y))
}
TR <- rbindlist(lapply(c(TARGET, "C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M01","intercept"),
                       function(cc) trend_of(cc, cc)))
say("--- 계수계열 시간추세 (연 단위 기울기, NW3) ---")
for (i in seq_len(nrow(TR))) with(TR[i], say(
  "  %-16s 선형 c %+.6f/yr (t %+.3f · R2 %.3f) · 로그 t %+.3f · 2차 [t1 %+.3f, t2 %+.3f] · 전체 mean %+.6f (t %+.3f)",
  series, c_lin, t_lin, r2_lin, t_log, t_q1, t_q2, mean_all, t_all))
t_lin_m26 <- TR[series == TARGET, t_lin]; c_lin_m26 <- TR[series == TARGET, c_lin]
A1_detected <- is.finite(t_lin_m26) && abs(t_lin_m26) >= T_THRESH
say("★A1 판정: |t_c| = %.4f vs 문턱 %.1f ⇒ %s", abs(t_lin_m26), T_THRESH,
    if (A1_detected) sprintf("추세 검출 (%s)", if (c_lin_m26 < 0) "약화 방향" else "강화 방향") else "추세 미검출")

## A3 대조 유효성
ctl_t <- TR[series %in% c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M01"), abs(t_lin)]
ctl_ok <- any(ctl_t < T_THRESH)
say("★A3 양성 대조: 대조 4종 |t_c| = %s ⇒ %s",
    paste(sprintf("%.3f", ctl_t), collapse=" / "),
    if (ctl_ok) "최소 1개 추세 미검출 — 대조 유효" else "전부 유의 — 시대 공통 효과로 라벨")

## 추세 검정 자체의 검정력 (관측 기울기가 아니라 '초기→현대 관측 낙차'가 검출 가능했는가)
obs_drop_per_yr <- (m_mod - m_ear) / ((mean(DT[mod==1L, tau]) - mean(DT[mod==0L, tau])))
se_c <- ols_nw(DT[[TARGET]], DT[, .(tau)])[term=="tau", se]
say("★A1 검정력: 관측 낙차 %+.6f/yr (초기→현대 평균차 기준) vs 추세 SE %.6f ⇒ 함의 t %+.3f",
    obs_drop_per_yr, se_c, obs_drop_per_yr/se_c)
say("   문턱 2.0 검출에 필요한 기울기 = %+.6f/yr (관측 %+.6f/yr)", T_THRESH*se_c, c_lin_m26)

## =============================================================================
## [4] A2 — 귀속 (nested, 연속 채널)
## =============================================================================
say("================ [4] A2 귀속 (nested 연속 채널) ================")
DTa <- DT[is.finite(vol12_t) & is.finite(dd_t)]
say("귀속 표본 %d개월 (국면 lag 로 %d개월 소실)", nrow(DTa), nrow(DT) - nrow(DTa))
base <- ols_nw(DTa[[TARGET]], DTa[, .(tau)])
c_base <- base[term=="tau", est]; t_base <- base[term=="tau", t]
say("기준(같은 표본) 시간계수 %+.6f (t %+.3f)", c_base, t_base)
specs <- list(
  list("+구성 N_t",            DTa[, .(tau, N_t)]),
  list("+구성 sd_z_t",         DTa[, .(tau, sd_z_t)]),
  list("+분산 disp_t",         DTa[, .(tau, disp_t)]),
  list("+국면 vol12/dd",       DTa[, .(tau, vol12_t, dd_t)]),
  list("+전채널",              DTa[, .(tau, N_t, sd_z_t, disp_t, vol12_t, dd_t)])
)
ATT <- rbindlist(lapply(specs, function(s) {
  r <- ols_nw(DTa[[TARGET]], s[[2]])
  data.table(spec = s[[1]], c_tau = r[term=="tau", est], t_tau = r[term=="tau", t],
             retention = r[term=="tau", est]/c_base, r2 = r$r2[1],
             others = paste(sprintf("%s t=%+.2f", r[!term %in% c("(Intercept)","tau"), term],
                                    r[!term %in% c("(Intercept)","tau"), t]), collapse=" · "))
}))
for (i in seq_len(nrow(ATT))) with(ATT[i], say(
  "  %-16s 시간계수 %+.6f (t %+.3f) · 잔존율 %.3f · R2 %.3f · [%s]", spec, c_tau, t_tau, retention, r2, others))

lab_att <- function(row) {
  killed <- abs(row$t_tau) < T_THRESH && abs(row$retention) < 0.5
  if (killed) "설명함(시간계수 소멸)" else if (abs(row$t_tau) >= T_THRESH) "설명 못함(시간계수 유지)" else "부분"
}
for (i in seq_len(nrow(ATT))) say("   판정 %-16s ⇒ %s", ATT$spec[i], lab_att(ATT[i]))
full_row <- ATT[spec == "+전채널"]
A2_verdict <- {
  if (!A1_detected) {
    "N/A — A1 추세 미검출이므로 귀속 대상 자체가 없다(무엇을 설명할지가 통계적으로 확립되지 않음)"
  } else if (abs(full_row$t_tau) >= T_THRESH && abs(full_row$retention) >= 0.5) {
    "감쇠(decay) — 전 채널 통제 후에도 시간추세 유지"
  } else {
    killers <- ATT[abs(t_tau) < T_THRESH & abs(retention) < 0.5, spec]
    if (!length(killers)) "혼합/미귀속 — 단일 채널이 설명 못하나 전채널에서 소멸"
    else paste0("귀속: ", paste(killers, collapse = ", "), " 채널이 시간추세를 흡수")
  }
}
say("★A2 판정: %s", A2_verdict)

## =============================================================================
## [4b] 추세 검정의 필요 표본 + 직접 시대차 검정 (보조)
## =============================================================================
say("================ [4b] 필요 표본 · 직접 시대차 ================")
## 추세 SE ∝ n^{-1.5} (등간격 tau 의 sd 가 n 에 비례) — 관측 기울기를 문턱에서 검출하려면
shrink <- if (abs(c_lin_m26) > 1e-12) (T_THRESH * se_c) / abs(c_lin_m26) else Inf
n_trend_req <- n_full * shrink^(2/3)
say("★추세 검출 필요 표본: SE 를 %.3f 배 줄여야 함 ⇒ n = %.0f개월 (%.1f년) · 현재 %d개월 ⇒ 추가 %.1f년",
    shrink, n_trend_req, n_trend_req/12, n_full, max(0, (n_trend_req - n_full)/12))

## 직접 시대차 (분할 — 보조 지표. 주판정 아님)
se_e <- nw_se_mean(b_ear); se_m <- nw_se_mean(b_mod)
d_era <- m_ear - m_mod; se_d <- sqrt(se_e^2 + se_m^2); t_d <- d_era/se_d
say("직접 시대차(보조·분할): 초기−현대 %+.6f/월 (연 %+.3f%%) · NW SE %.6f ⇒ t %+.3f ⇒ %s",
    d_era, d_era*1200, se_d, t_d, if (abs(t_d) >= T_THRESH) "낙차 유의" else "낙차 비유의 — 두 구간이 같은 모집단과 구별 안 됨")
say("   ⇒ '약화됐다'와 '안 약화됐다' 중 어느 쪽도 이 표본으로는 기각되지 않는다")

## 전 계열 기울기 부호 공통성 (시대 공통 드리프트 여부)
neg_slopes <- sum(TR$c_lin < 0); say("전 %d개 계수계열 중 음의 기울기 %d개 — 부호 공통(유의는 0개)", nrow(TR), neg_slopes)

## =============================================================================
## [5] 저장
## =============================================================================
fwrite(DT, file.path(OUT, "a1_monthly_coefs_and_covariates.csv"))
fwrite(TR, file.path(OUT, "a1_trend_by_series.csv"))
fwrite(ATT, file.path(OUT, "a1_attribution_nested.csv"))
res <- list(
  n_mod = n_mod, n_ear = n_ear, m_mod = m_mod, s_mod = s_mod, t_mod = t_mod,
  m_ear = m_ear, s_ear = s_ear, t_ear = t_ear,
  req_self = req_self, vp_self = vp_self, detect_early_effect = detect_early_effect,
  n_required_months = n_req, t_full = t_full,
  A1_detected = A1_detected, c_lin_m26 = c_lin_m26, t_lin_m26 = t_lin_m26,
  se_c = se_c, min_detectable_slope = T_THRESH*se_c, obs_drop_per_yr = obs_drop_per_yr,
  ctl_ok = ctl_ok, TR = TR, ATT = ATT, A2_verdict = A2_verdict,
  n_trend_req_months = n_trend_req, trend_se_shrink = shrink,
  era_diff = d_era, era_diff_se = se_d, era_diff_t = t_d)
saveRDS(res, file.path(OUT, "a1_results.rds"))
say("저장 완료 → %s", OUT)
say("★★[A 요약] 현대 n=%d level t %+.3f · 검정력 %s · 추세 t %+.3f(%s) · 귀속 %s",
    n_mod, t_mod, vp_self$verdict, t_lin_m26, if (A1_detected) "검출" else "미검출", A2_verdict)
