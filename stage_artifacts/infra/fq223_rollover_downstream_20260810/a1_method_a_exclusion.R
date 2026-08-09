## =============================================================================
## FQ-223 (A) — 방법 A: 4·5월 제외 재적합 + 검정력 구별 + 직접 오염 분해
##
## 사전등록: PREREG.md (본 디렉터리). 문턱은 실행 전 고정됨.
## 주판정량: fwd_ret ~ z(C01_SUE)+z(C02_EPS_Chg_1m)+z(C04_ESBR)+z(M26) 의 z(M26) FMB NW(3) t
## metric_type: canonical_screen_diag (횡단면 진단 — 성과·자본 주장 아님)
##
## ★규약: 측정 첫 출력 = 입력 실측(행수·관측단위·범위). 08-08 t 재현 실패 시 중단.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
SRC  <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
say <- function(fmt, ...) { cat(sprintf(paste0("[a1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260810L)

source("02_Infrastructure/contracts/required_effect_size.R")

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}
nw_se <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  sqrt(s/n)
}

FACS   <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "M26_Revenue_Mom")
TARGET <- "M26_Revenue_Mom"
T_THRESH <- 2.0

## =============================================================================
## [0] 입력 실측 — 08-08 패널 그대로 소비 (재현 검증)
## =============================================================================
say("================ [0] 입력 실측 ================")
pq <- file.path(SRC, "alpha_scores.parquet")
if (!file.exists(pq)) stop("[a1] 08-08 패널 부재 — 중단")
D4 <- as.data.table(read_parquet(pq))
say("패널 %d행 · 컬럼: %s", nrow(D4), paste(names(D4), collapse = ","))
say("고유 signal_ym %d · 고유 Ticker %d · 범위 %s ~ %s",
    uniqueN(D4$signal_ym), uniqueN(D4$Ticker), min(D4$signal_ym), max(D4$signal_ym))
n_ym <- uniqueN(D4$signal_ym)
unit_ok <- nrow(D4) > n_ym * 5      # 월 × 종목 패널이어야 함
say("★관측단위 = (signal_ym × Ticker) 월간 패널 · 월당 평균 %.0f종목 ⇒ %s",
    nrow(D4)/n_ym, if (unit_ok) "가정 충족" else "가정 위반")
if (!unit_ok) stop("[a1] 입력 관측단위 가정 위반 — 착수 중단")
say("Ret_1m: 중앙 %+.5f · sd %.5f · 유한 %d/%d",
    median(D4$Ret_1m), sd(D4$Ret_1m), sum(is.finite(D4$Ret_1m)), nrow(D4))

## =============================================================================
## [1] 08-08 baseline 재현 (parity gate)
## =============================================================================
say("================ [1] 08-08 baseline 재현 ================")
fmb_coefs <- function(dat, xs, ycol = "Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse = " + ")))
  dat[, {
    fit <- tryCatch(lm(f, data = .SD), error = function(e) NULL)
    if (is.null(fit)) .(term = character(0), est = numeric(0))
    else { cf <- coef(fit); .(term = names(cf), est = as.numeric(cf)) }
  }, by = signal_ym, .SDcols = c(ycol, xs)]
}
CF <- fmb_coefs(D4, FACS)
CFt <- CF[term == TARGET][order(signal_ym)]
t_full <- nw_t(CFt$est); n_full <- nrow(CFt); mean_full <- mean(CFt$est); sd_full <- sd(CFt$est)
say("재현: z(M26) FMB NW(3) t = %+.4f (n=%d · mean %+.6f · sd %.6f)", t_full, n_full, mean_full, sd_full)
ref_t <- 2.5552525842524; ref_n <- 283L
parity <- abs(t_full - ref_t) < 0.001 && n_full == ref_n
say("08-08 기록값 t=%+.4f n=%d ⇒ parity %s (|Δt| = %.2e)", ref_t, ref_n,
    if (parity) "PASS" else "FAIL", abs(t_full - ref_t))
if (!parity) stop("[a1] baseline 재현 실패 — 재검 무의미. 중단")

## =============================================================================
## [2] 방법 A — 4·5월 제외 재적합
## =============================================================================
say("================ [2] 방법 A: 4·5월 제외 ================")
CFt[, mon := substr(signal_ym, 6, 7)]
AM <- c("04", "05")
CF_A  <- CFt[!(mon %in% AM)]
CF_AM <- CFt[mon %in% AM]
n_A <- nrow(CF_A); n_AM <- nrow(CF_AM)
t_A <- nw_t(CF_A$est); mean_A <- mean(CF_A$est); sd_A <- sd(CF_A$est)
mean_AM <- mean(CF_AM$est); sd_AM <- sd(CF_AM$est)
say("제외 대상 4·5월 %d개월 / 잔여 %d개월 (월수 share %.4f)", n_AM, n_A, n_AM/n_full)
say("★t_A (4·5월 제외) = %+.4f  (n=%d · mean %+.6f · sd %.6f)", t_A, n_A, mean_A, sd_A)
say("  4·5월 부분계열: mean %+.6f · sd %.6f · NW(3) t %+.3f (n=%d)",
    mean_AM, sd_AM, nw_t(CF_AM$est), n_AM)

## 오염 없을 때의 기대 t (표본손실만의 효과)
t_A_expected <- t_full * sqrt(n_A / n_full)
say("★검정력 기준선: 4·5월이 평월과 같은 분포일 때 기대 t_A = t_full×√(n_A/n_full) = %+.4f", t_A_expected)
say("  관측 t_A − 기대 t_A = %+.4f (사전등록 허용 마진 −0.30)", t_A - t_A_expected)

## required effect size (사전등록 규약)
req_A <- required_effect(n = n_A, t_threshold = T_THRESH, sd_monthly = sd_A, design = "full")
vp_A  <- verdict_with_power(observed_t = abs(t_A), observed_monthly = abs(mean_A),
                            n = n_A, t_threshold = T_THRESH, sd_monthly = sd_A, design = "full")
say("required_effect(n=%d, sd=%.6f): 필요 월평균 %.6f (연 %.3f%%) · 관측 %+.6f (연 %+.3f%%)",
    n_A, sd_A, req_A$required_monthly, req_A$required_annual*100, mean_A, mean_A*12*100)
say("검정력 라벨: %s", vp_A$verdict)
say("   %s", vp_A$note)
if (!is.null(vp_A$implied_t_threshold))
  say("   implied_t_threshold = %.3f (문턱 %.1f 대비 — 근방이면 바 = t검정 재진술)",
      vp_A$implied_t_threshold, T_THRESH)

## =============================================================================
## [3] 직접 오염 분해 (t_A 와 독립) — 4·5월 vs 평월 계수 비교
## =============================================================================
say("================ [3] 직접 분해: 4·5월 vs 평월 계수 ================")
wt <- t.test(CF_AM$est, CF_A$est, var.equal = FALSE)
say("Welch t (4·5월 mean vs 평월 mean): diff %+.6f · t %+.3f · p %.4f · 95%%CI [%+.6f, %+.6f]",
    mean_AM - mean_A, wt$statistic, wt$p.value, wt$conf.int[1], wt$conf.int[2])
contrib_share <- (n_AM * mean_AM) / (n_full * mean_full)
say("★기여 share = n_AM×mean_AM / (n_full×mean_full) = %.4f  (월수 share %.4f · 문턱 0.30)",
    contrib_share, n_AM/n_full)

## 월별(1~12) 계수 분해 — 4·5월이 고립 봉우리인지, 넓은 고원의 일부인지
mo <- CFt[, .(n = .N, mean = mean(est), sd = sd(est), t_nw3 = nw_t(est), pos = mean(est > 0)), by = mon][order(mon)]
say("--- 월별 z(M26) 계수 (달력 분해) ---")
for (i in seq_len(nrow(mo))) with(mo[i], say("  %s월  n=%2d  mean %+.6f  sd %.6f  t_NW3 %s  부호>0 %.0f%%",
    mon, n, mean, sd, if (is.na(t_nw3)) "  n/a" else sprintf("%+.2f", t_nw3), pos*100))
say("  ★4·5월 mean 순위 = %d, %d 위 (12개월 중, 큰 것부터)",
    which(order(-mo$mean) == which(mo$mon=="04")), which(order(-mo$mean) == which(mo$mon=="05")))

## =============================================================================
## [4] 양성 대조 1 — 같은 회귀의 C01/C02/C04 에 동일 제외
## =============================================================================
say("================ [4] 양성 대조: 동반 팩터 3종 동일 제외 ================")
ctl <- rbindlist(lapply(setdiff(FACS, TARGET), function(f) {
  s <- CF[term == f][order(signal_ym)]; s[, mon := substr(signal_ym, 6, 7)]
  sA <- s[!(mon %in% AM)]; sAM <- s[mon %in% AM]
  data.table(term = f, n_full = nrow(s), t_full = nw_t(s$est), n_A = nrow(sA), t_A = nw_t(sA$est),
             t_A_expected = nw_t(s$est) * sqrt(nrow(sA)/nrow(s)),
             mean_AM = mean(sAM$est), mean_oth = mean(sA$est),
             welch_p = t.test(sAM$est, sA$est, var.equal = FALSE)$p.value)
}))
ctl <- rbind(data.table(term = TARGET, n_full = n_full, t_full = t_full, n_A = n_A, t_A = t_A,
                        t_A_expected = t_A_expected, mean_AM = mean_AM, mean_oth = mean_A,
                        welch_p = wt$p.value), ctl)
ctl[, t_A_minus_expected := t_A - t_A_expected]
for (i in seq_len(nrow(ctl))) with(ctl[i], say(
  "  %-18s t_full %+.3f → t_A %+.3f (기대 %+.3f · Δ %+.3f) · 4·5월 mean %+.6f vs 평월 %+.6f · Welch p %.4f",
  term, t_full, t_A, t_A_expected, t_A_minus_expected, mean_AM, mean_oth, welch_p))

## =============================================================================
## [5] 양성 대조 2 — M01_Mom_12_1 (컨센서스 무관 가격 모멘텀)
## =============================================================================
say("================ [5] 양성 대조: M01_Mom_12_1 대체 arm ================")
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
sig_dates <- sort(unique(as.Date(D4$Date)))
say("M01 로드: %d개 sig_date (%s ~ %s)", length(sig_dates), min(sig_dates), max(sig_dates))
cache_m01 <- file.path(OUT, "a1_m01_panel.rds")
if (file.exists(cache_m01)) {
  M01 <- readRDS(cache_m01); say("  캐시 재사용 %d행", nrow(M01))
} else {
  t0 <- Sys.time(); pl <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    z <- tryCatch(load_month_factors(sig_dates[i], factor_names = "M01_Mom_12_1"), error = function(e) NULL)
    if (is.null(z) || !nrow(z)) next
    pl[[i]] <- data.table(Date = sig_dates[i], Ticker = z$Ticker, M01 = z$Z_Score_Aligned)
    if (i %% 60 == 0) say("  ... %d/%d (%.0fs)", i, length(sig_dates), as.numeric(difftime(Sys.time(), t0, units="secs")))
  }
  M01 <- rbindlist(pl, fill = TRUE); saveRDS(M01, cache_m01)
  say("  로드 완료 %.0fs · %d행 · %d개월", as.numeric(difftime(Sys.time(), t0, units="secs")), nrow(M01), uniqueN(M01$Date))
}
if (!nrow(M01)) stop("[a1] M01 패널 0행 — 0은 결론이 아니라 정지 신호. 계측 확인 필요")
DM <- merge(D4[, .(signal_ym, Date = as.Date(Date), Ticker, C01_SUE, C02_EPS_Chg_1m, C04_ESBR, Ret_1m)],
            M01, by = c("Date", "Ticker"))
DM <- DM[complete.cases(DM[, .(C01_SUE, C02_EPS_Chg_1m, C04_ESBR, M01, Ret_1m)])]
mmM <- DM[, .N, by = signal_ym]; DM <- DM[signal_ym %in% mmM[N >= 30L, signal_ym]]
say("M01 arm 패널: %d행 · %d개월 (M26 arm %d개월 대비 %+d)", nrow(DM), uniqueN(DM$signal_ym), n_full,
    uniqueN(DM$signal_ym) - n_full)
CFM <- fmb_coefs(DM, c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M01"))
sM <- CFM[term == "M01"][order(signal_ym)]; sM[, mon := substr(signal_ym, 6, 7)]
sMA <- sM[!(mon %in% AM)]; sMAM <- sM[mon %in% AM]
m01_row <- data.table(term = "M01_Mom_12_1(대조)", n_full = nrow(sM), t_full = nw_t(sM$est),
                      n_A = nrow(sMA), t_A = nw_t(sMA$est),
                      t_A_expected = nw_t(sM$est)*sqrt(nrow(sMA)/nrow(sM)),
                      mean_AM = mean(sMAM$est), mean_oth = mean(sMA$est),
                      welch_p = t.test(sMAM$est, sMA$est, var.equal = FALSE)$p.value)
m01_row[, t_A_minus_expected := t_A - t_A_expected]
with(m01_row, say("  ★M01 대조: t_full %+.3f → t_A %+.3f (기대 %+.3f · Δ %+.3f) · Welch p %.4f ⇒ %s",
    t_full, t_A, t_A_expected, t_A_minus_expected, welch_p,
    if (abs(t_A_minus_expected) < 0.30 && welch_p > 0.05) "불변(대조 유효)" else "★변동 — 달력효과 의심"))
ctl <- rbind(ctl, m01_row)

## =============================================================================
## [6] 저장
## =============================================================================
fwrite(CFt, file.path(OUT, "a1_m26_coefs_monthly.csv"))
fwrite(mo,  file.path(OUT, "a1_month_of_year_decomp.csv"))
fwrite(ctl, file.path(OUT, "a1_exclusion_and_controls.csv"))
res <- list(t_full = t_full, n_full = n_full, mean_full = mean_full, sd_full = sd_full,
            t_A = t_A, n_A = n_A, mean_A = mean_A, sd_A = sd_A,
            t_A_expected = t_A_expected, n_AM = n_AM, mean_AM = mean_AM, sd_AM = sd_AM,
            welch_p = wt$p.value, welch_diff = mean_AM - mean_A, contrib_share = contrib_share,
            req_A = req_A, vp_A = vp_A, month_decomp = mo, controls = ctl, parity = parity)
saveRDS(res, file.path(OUT, "a1_results.rds"))
say("저장 완료 → %s", OUT)
say("★★[A 요약] t_full %+.4f → t_A %+.4f (기대 %+.4f) · 4·5월 기여 share %.4f · Welch p %.4f",
    t_full, t_A, t_A_expected, contrib_share, wt$p.value)
