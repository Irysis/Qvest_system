## =============================================================================
## WT-D20260808_002 — M26_Revenue_Mom 증분 판정 (원 사전등록 C14 라운드의 재료 정정판)
##
## 주판정량: fwd_ret ~ z(C01_SUE)+z(C02_EPS_Chg_1m)+z(C04_ESBR)+z(M26_Revenue_Mom)
##           의 z(M26) 계수 Fama-MacBeth NW(lag3) t.  pooled OLS 금지.
## 설계: 전표본 횡단면 (국면·하위군 분할 금지).
## 문턱: |t| >= 2.0 = 재료 자격 (자본 게이트 아님).
## metric_type: canonical_screen_diag (계약 백테 미경유 횡단면 진단 — 성과 주장 아님)
##
## ★규약: 측정 첫 출력 = 입력 실측(행수·관측단위·범위). 월간 아니면 착수 전 중단.
## ★C15: factor DB 는 load_month_factors() 경유만.
## ★신호↔수익 병합은 align_signal_return_ym(off=0, signal_anchor) 표준 경유.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)
say <- function(fmt,...) { cat(sprintf(paste0("[m26] ",fmt,"\n"),...)); flush.console() }
set.seed(20260808L)

source("02_Infrastructure/config.R")                      # CACHE_DIR (커넥터 self-dir 우회)
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")      # build_monthly_forward_returns
source("02_Infrastructure/contracts/align_signal_return_ym.R")
source("02_Infrastructure/contracts/required_effect_size.R")

## Newey-West t (lag 3) — 계열 평균의 t
nw_t <- function(x, lag=3L){
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}
nw_se <- function(x, lag=3L){
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  sqrt(s/n)
}

FACS <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M26_Revenue_Mom")
TARGET <- "M26_Revenue_Mom"

## =============================================================================
## [0] ★입력 실측 — 행수 · 관측단위 · 범위
## =============================================================================
say("================ [0] 입력 실측 ================")
fp <- sort(Sys.glob(".cache/factor_db/factor_db_*.parquet"))
say("factor_db: 월 파일 %d개 · %.2f GB · %s ~ %s",
    length(fp), sum(file.size(fp))/1e9, basename(fp[1]), basename(fp[length(fp)]))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
n_date <- uniqueN(RAW$Date); n_ym <- uniqueN(format(RAW$Date,"%Y-%m"))
unit <- if (n_date > n_ym*1.5) "일간(daily)" else "월간(monthly)"
say("RAWDATA: %d행 · 고유 Date %d · 고유 년월 %d ⇒ ★관측단위 = %s · 범위 %s ~ %s",
    nrow(RAW), n_date, n_ym, unit, min(RAW$Date), max(RAW$Date))
if (unit != "일간(daily)") stop("[m26] 입력 관측단위 가정 위반 — 착수 중단")
say("⇒ 일간이므로 forward 수익은 계약함수 build_monthly_forward_returns() 로만 파생한다")

## 월말 거래일 → 계약함수로 1M forward 수익 (관측단위 월간으로 변환)
ME <- sort(RAW[, .(Date=max(Date)), by=.(ym=format(Date,"%Y-%m"))]$Date)
RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
say("forward 수익 패널: %d행 · %d개월 · 관측단위 = (월말 anchor Date × Ticker) · %s ~ %s",
    nrow(ret), uniqueN(ret$Date), min(ret$Date), max(ret$Date))
say("  ★dating = signal_anchor (Date=신호월말, Ret_1m=익월 실현) ⇒ 병합 off=0")
say("  Ret_1m 요약: 중앙 %+.4f · sd %.4f · 방화벽 격리 %d",
    median(ret$Ret_1m), sd(ret$Ret_1m), fwd$ret_firewall_dropped)

## =============================================================================
## [1] 팩터 패널 — C15 커넥터 경유 (Z_Score_Aligned = 방향정렬 횡단면 z, 원형 그대로)
## =============================================================================
say("================ [1] 팩터 패널 (load_month_factors 경유) ================")
sig_dates <- ME[ME <= max(ret$Date)]           # forward 수익이 존재하는 월만
t0 <- Sys.time(); panels <- vector("list", length(sig_dates)); asof <- character(0)
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  z <- tryCatch(load_month_factors(d, factor_names=FACS), error=function(e) NULL)
  if (is.null(z) || !nrow(z)) next
  a <- attr(z,"factor_db_asof_date")
  asof <- c(asof, sprintf("%s|%s", format(d,"%Y-%m"), as.character(a)))
  w <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  w[, Date := d]
  panels[[i]] <- w
  if (i %% 60 == 0) say("  ... %d/%d (%.0fs)", i, length(sig_dates),
                        as.numeric(difftime(Sys.time(), t0, units="secs")))
}
P <- rbindlist(panels, fill=TRUE)
say("팩터 패널 로드 완료 %.0fs · %d행 · %d개월", as.numeric(difftime(Sys.time(),t0,units="secs")),
    nrow(P), uniqueN(P$Date))
for (f in FACS) {
  if (!f %in% names(P)) { say("  ★%s 패널 부재 — 중단", f); stop("factor missing") }
  sub <- P[is.finite(get(f))]
  say("  %-18s 유효월 %3d (%s ~ %s) · 종목-월 %7d · 월중앙 종목수 %5.0f",
      f, uniqueN(sub$Date), format(min(sub$Date),"%Y-%m"), format(max(sub$Date),"%Y-%m"),
      nrow(sub), median(sub[, .N, by=Date]$N))
}
## ★as-of 검증: 팩터 vintage 가 신호월과 같은 달인지 (동월/미래 vintage 차단)
ao <- data.table(k=asof)[, tstrsplit(k,"|",fixed=TRUE)]
setnames(ao, c("sig_ym","asof_date"))
ao[, asof_ym := substr(asof_date,1,7)]
say("  as-of 정합: 신호월==vintage월 %d/%d · 불일치 %d",
    sum(ao$sig_ym==ao$asof_ym, na.rm=TRUE), nrow(ao), sum(ao$sig_ym!=ao$asof_ym, na.rm=TRUE))
if (any(ao$sig_ym != ao$asof_ym, na.rm=TRUE))
  say("  ★불일치 샘플: %s", paste(head(ao[sig_ym!=asof_ym, paste0(sig_ym,"->",asof_ym)],5), collapse=" "))

## =============================================================================
## [2] 신호↔수익 병합 (표준 헬퍼, off=0 signal_anchor)
## =============================================================================
say("================ [2] 병합 (align_signal_return_ym) ================")
S <- copy(P); setnames(S, "Date", "signal_date")
M <- align_signal_return_ym(S, ret, signal_date_col="signal_date", return_date_col="Date",
                            id_col="Ticker", off=0L, return_dating="signal_anchor",
                            coverage_min=0.90, vintage_label="factor_db_monthend_v1")
say("병합 결과 %d행 · 월 coverage %.3f · 행 coverage %.3f", nrow(M),
    attr(M,"align_coverage_month"), attr(M,"align_coverage_row"))

D <- M[is.finite(Ret_1m)]
cc <- complete.cases(D[, ..FACS])
D4 <- D[cc]
say("★4종 동시 가용(complete-case) %d 종목-월 · %d개월 (%s ~ %s)",
    nrow(D4), uniqueN(D4$signal_ym), min(D4$signal_ym), max(D4$signal_ym))
mm <- D4[, .N, by=signal_ym][order(signal_ym)]
say("  월별 종목수: 중앙 %.0f · 최소 %d · 최대 %d", median(mm$N), min(mm$N), max(mm$N))
say("  breadth(Grinold IR ∝ IC×√N): √N 중앙 %.1f", sqrt(median(mm$N)))
MINN <- 30L
keep_ym <- mm[N >= MINN, signal_ym]
D4 <- D4[signal_ym %in% keep_ym]
say("  n>=%d 월만 유지 ⇒ %d개월 · %d 종목-월", MINN, uniqueN(D4$signal_ym), nrow(D4))

## =============================================================================
## [3] 주판정 — Fama-MacBeth 증분 회귀 (pooled OLS 금지)
## =============================================================================
say("================ [3] 주판정: FMB 증분 회귀 ================")
fmb_coefs <- function(dat, xs, ycol="Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse=" + ")))
  res <- dat[, {
    fit <- tryCatch(lm(f, data=.SD), error=function(e) NULL)
    if (is.null(fit)) .(term=character(0), est=numeric(0))
    else { cf <- coef(fit); .(term=names(cf), est=as.numeric(cf)) }
  }, by=signal_ym, .SDcols=c(ycol, xs)]
  res
}
CF <- fmb_coefs(D4, FACS)
tab <- CF[term != "(Intercept)", .(
  n_months = .N,
  mean_coef = mean(est),
  sd_coef   = sd(est),
  t_simple  = mean(est)/sd(est)*sqrt(.N),
  t_nw3     = nw_t(est),
  se_nw3    = nw_se(est),
  pos_rate  = mean(est > 0)
), by=term]
say("--- 4-팩터 동시 FMB (종속=Ret_1m, 설명=Z_Score_Aligned 원형) ---")
for (i in seq_len(nrow(tab))) with(tab[i], say(
  "  %-18s n=%3d  mean %+.5f  sd %.5f  t_simple %+.2f  ★t_NW3 %+.2f  (SE_NW %.5f)  부호>0 %.1f%%",
  term, n_months, mean_coef, sd_coef, t_simple, t_nw3, se_nw3, pos_rate*100))
TT <- tab[term == TARGET]
say("★★주판정량 z(M26) FMB NW(lag3) t = %+.3f  (문턱 |t|>=2.0)", TT$t_nw3)

## 대조 (진단, 판정 아님): M26 단독 회귀
CF1 <- fmb_coefs(D4, TARGET)
t1 <- CF1[term==TARGET, .(mean=mean(est), t_nw3=nw_t(est), n=.N)]
say("  [대조] M26 단독 FMB: mean %+.5f · t_NW3 %+.2f · n=%d ⇒ 증분/단독 t 비 %.2f",
    t1$mean, t1$t_nw3, t1$n, TT$t_nw3/t1$t_nw3)

## =============================================================================
## [4] 보조 — 단독 rank IC / spearman 대조 / 부호 일치율
## =============================================================================
say("================ [4] 보조 진단 ================")
ic <- D4[, .(ic = suppressWarnings(cor(get(TARGET), Ret_1m, method="spearman", use="complete.obs")),
             n=.N), by=signal_ym][is.finite(ic)]
say("M26 단독 rank IC: 평균 %+.4f · sd %.4f · t_NW3 %+.2f · ICIR %.3f · IC>0 %.1f%% · %d개월",
    mean(ic$ic), sd(ic$ic), nw_t(ic$ic), mean(ic$ic)/sd(ic$ic), mean(ic$ic>0)*100, nrow(ic))
## 전 유효월(4종 교집합 밖 포함) 단독 IC — breadth 손실 진단
Dall <- D[is.finite(get(TARGET))]
ica <- Dall[, .(ic=suppressWarnings(cor(get(TARGET), Ret_1m, method="spearman", use="complete.obs")), n=.N),
            by=signal_ym][n>=MINN & is.finite(ic)]
say("  [교집합 밖 포함 M26 전표본] %d개월 · 평균 IC %+.4f · t_NW3 %+.2f (교집합 제한의 breadth 손실 진단)",
    nrow(ica), mean(ica$ic), nw_t(ica$ic))

say("--- 횡단면 spearman (M26 vs 기존 3종, 월별 → 시계열 평균) ---")
sp <- rbindlist(lapply(setdiff(FACS, TARGET), function(f) {
  s <- D4[, .(rho = suppressWarnings(cor(get(TARGET), get(f), method="spearman", use="complete.obs"))),
          by=signal_ym][is.finite(rho)]
  data.table(other=f, mean_rho=mean(s$rho), sd_rho=sd(s$rho),
             p05=quantile(s$rho,.05), p95=quantile(s$rho,.95), max_rho=max(s$rho), n=nrow(s))
}))
for (i in seq_len(nrow(sp))) with(sp[i], say(
  "  M26 vs %-18s  평균 rho %+.4f (sd %.4f · 5%% %+.3f · 95%% %+.3f · 월최대 %+.3f)",
  other, mean_rho, sd_rho, p05, p95, max_rho))
say("  ★REDUNDANT 분기 판정용 최대 평균 rho = %.4f (문턱 0.9)", max(sp$mean_rho))

## 부호 일치율 (이익 서프라이즈 vs 매출 개정) — 기전 시험 가능성 확인
sg <- D4[, .(agree = mean(sign(C01_SUE) == sign(get(TARGET)), na.rm=TRUE), n=.N), by=signal_ym]
say("SUE↔M26 부호 일치율: 평균 %.1f%% (불일치 %.1f%%) · 월 최소 %.1f%% / 최대 %.1f%%",
    mean(sg$agree)*100, (1-mean(sg$agree))*100, min(sg$agree)*100, max(sg$agree)*100)

## =============================================================================
## [5] 반증 관측 (alpha_hypothesis 승계) — M26 → 후속 eps_chg_1m 전파
## =============================================================================
say("================ [5] 반증 관측: 매출 개정 → 이익 개정 전파 ================")
PP <- P[, .(Date, Ticker, M26=get(TARGET), C02=C02_EPS_Chg_1m)]
PP[, ym := format(Date, "%Y-%m")]
yms <- sort(unique(PP$ym))
prop <- rbindlist(lapply(1:3, function(k) {
  a <- PP[is.finite(M26), .(ym, Ticker, M26)]
  b <- PP[is.finite(C02), .(ym_f=ym, Ticker, C02f=C02)]
  a[, ym_f := ym_shift(ym, k)]
  j <- merge(a, b, by=c("ym_f","Ticker"))
  s <- j[, .(rho=suppressWarnings(cor(M26, C02f, method="spearman", use="complete.obs")), n=.N),
         by=ym][n>=MINN & is.finite(rho)]
  data.table(k=k, n_months=nrow(s), mean_rho=mean(s$rho), t_nw3=nw_t(s$rho), pos=mean(s$rho>0))
}))
for (i in seq_len(nrow(prop))) with(prop[i], say(
  "  M26(t) → C02_EPS_Chg_1m(t+%d): %d개월 · 평균 rho %+.4f · t_NW3 %+.2f · rho>0 %.1f%%",
  k, n_months, mean_rho, t_nw3, pos*100))

## =============================================================================
## [6] 검정력 — 계열 고유 sd 기반 (도구 기본 sd 는 바스켓쌍 프레임이라 참고치)
## =============================================================================
say("================ [6] 검정력 ================")
nM <- TT$n_months
own <- required_effect(n=nM, t_threshold=2.0, sd_monthly=TT$sd_coef, design="full")
say("계열 고유 sd(%.5f) 기반: n=%d · 필요 월평균 계수 %.5f (연 %.2f%%) · 관측 %+.5f (연 %+.2f%%)",
    TT$sd_coef, nM, own$required_monthly, own$required_annual*100, TT$mean_coef, TT$mean_coef*12*100)
vp <- verdict_with_power(observed_t=abs(TT$t_nw3), observed_monthly=abs(TT$mean_coef),
                         n=nM, t_threshold=2.0, sd_monthly=TT$sd_coef, design="full")
say("★검정력 라벨: %s", vp$verdict); say("   %s", vp$note)
ref <- required_effect(n=nM, design="full")
say("  [참고치] 도구 기본 sd(0.0394, top-25 EW 바스켓쌍 프레임): 필요 연 %.2f%% — 본 라운드 판정량과 프레임 다름",
    ref$required_annual*100)

## =============================================================================
## [7] Placebo (월내 신호 셔플) + lag1 스트레스
## =============================================================================
say("================ [7] Placebo + lag1 스트레스 ================")
NPL <- 200L
pl <- numeric(NPL)
Dp <- copy(D4)
for (b in seq_len(NPL)) {
  Dp[, PL := sample(get(TARGET)), by=signal_ym]
  cfp <- fmb_coefs(Dp, c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","PL"))
  pl[b] <- nw_t(cfp[term=="PL", est])
}
p_two <- mean(abs(pl) >= abs(TT$t_nw3), na.rm=TRUE)
say("placebo(월내 셔플 %d회): |t| 분포 중앙 %.2f · 95%% %.2f · ★관측 |t| %.2f 의 p = %.4f",
    NPL, median(abs(pl),na.rm=TRUE), quantile(abs(pl),.95,na.rm=TRUE), abs(TT$t_nw3), p_two)

## lag1 스트레스: 신호를 한 달 더 묵혀서(t-1 신호 → t..t+1 수익) 재측정
S1 <- copy(P); S1[, Date := NULL]
S1 <- P[, c("Date","Ticker",FACS), with=FALSE]
S1[, signal_ym_orig := format(Date,"%Y-%m")]
S1[, signal_ym := ym_shift(signal_ym_orig, 1L)]      # t-1 신호를 t 월 신호로 사용
L <- merge(S1[, c("signal_ym","Ticker",FACS), with=FALSE],
           D4[, .(signal_ym, Ticker, Ret_1m)], by=c("signal_ym","Ticker"))
L <- L[complete.cases(L[, ..FACS])]
mmL <- L[, .N, by=signal_ym]; L <- L[signal_ym %in% mmL[N>=MINN, signal_ym]]
CFL <- fmb_coefs(L, FACS)
tl <- CFL[term==TARGET, .(n=.N, mean=mean(est), t_nw3=nw_t(est))]
say("lag1 스트레스(t-1 신호): n=%d · mean %+.5f · t_NW3 %+.2f (기준 %+.2f) ⇒ 유지율 %.2f",
    tl$n, tl$mean, tl$t_nw3, TT$t_nw3, tl$t_nw3/TT$t_nw3)

## =============================================================================
## [8] 부기간 안정성 (진단 — 판정 분할 아님)
## =============================================================================
say("================ [8] 부기간 (advisory 진단) ================")
CFt <- CF[term==TARGET][order(signal_ym)]
CFt[, era := fifelse(signal_ym < "2010-01", "2003-2009",
              fifelse(signal_ym < "2017-01", "2010-2016", "2017-2026"))]
es <- CFt[, .(n=.N, mean=mean(est), t_nw3=nw_t(est)), by=era][order(era)]
for (i in seq_len(nrow(es))) with(es[i], say("  %-10s n=%3d · mean %+.5f · t_NW3 %+.2f", era, n, mean, t_nw3))

## =============================================================================
## [9] 산출 저장
## =============================================================================
fwrite(CF, file.path(OUT,"m26_fmb_coefs_monthly.csv"))
fwrite(tab, file.path(OUT,"m26_fmb_summary.csv"))
fwrite(sp,  file.path(OUT,"m26_spearman_vs_incumbent.csv"))
fwrite(ic,  file.path(OUT,"m26_rank_ic_monthly.csv"))
fwrite(prop,file.path(OUT,"m26_falsification_propagation.csv"))
fwrite(es,  file.path(OUT,"m26_subperiod.csv"))
write_parquet(D4[, .(signal_ym, Date=signal_date, Ticker, C01_SUE, C02_EPS_Chg_1m, C04_ESBR,
                     M26_Revenue_Mom, Ret_1m)], file.path(OUT,"alpha_scores.parquet"))
saveRDS(list(tab=tab, sp=sp, ic=ic, prop=prop, power=vp, placebo_p=p_two, placebo=pl,
             lag1=tl, era=es, sign_agree=mean(sg$agree), n_months=nM,
             months=mm, single=t1, ic_all=ica),
        file.path(OUT,"m26_results.rds"))
say("저장 완료 → %s", OUT)
say("★★최종: z(M26) FMB NW(lag3) t = %+.3f · 최대 spearman %.4f · 검정력 %s · placebo p %.4f",
    TT$t_nw3, max(sp$mean_rho), vp$verdict, p_two)
