## =============================================================================
## P3b — ★결정적: C18_Earnings_CAR_3d 의 정체
##
## 코드 독해가 세운 가설: 빌더의 "발표일 프록시" 는
##   ann_src <- sue_hist[Date <= sig_d-3 & Date >= sig_d-400]; ann_date = Date[1]  (최신 우선 정렬)
## 인데 sue 는 **매 영업일 관측**된다(P0d/P0e 실측: 고유 Date 6140개, 간격 중앙 1일).
## ⇒ Date[1] = sig_d-3 근방으로 고정되고, CAR 창 [ad-3, ad+3] = [sig_d-6, sig_d] =
##    **신호월 마지막 ~6일의 시장조정 수익** 이 된다. 즉 이벤트-CAR 가 아니라 **단기 반전 대용품**.
## 관측된 부호(t -2.551, 음) · lag1 유지율 -0.15 가 이 해석과 정합한다.
## ★추론으로 끝내지 않는다 — ①프록시 날짜 분포를 직접 재고 ②반전 통제 하 증분이 죽는지 잰다.
##   (사전등록된 자격 전제조건: "모멘텀/반전 배제 미통과 시 t 무관 자격 불인정")
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
say <- function(fmt,...) { cat(sprintf(paste0("[p3b] ",fmt,"\n"),...)); flush.console() }
set.seed(20260809L)
source("02_Infrastructure/config.R")

nw_t <- function(x, lag=3L){ x <- x[is.finite(x)]; n <- length(x); if (n<20L) return(NA_real_)
  m <- mean(x); e <- x-m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }

## =============================================================================
## [1] 발표일 프록시 분포 실측 — sig_d 로부터 며칠 전인가
## =============================================================================
say("================ [1] '발표일 프록시' 실측 ================")
CD <- file.path(CACHE_DIR,"consensus")
sue <- as.data.table(read_parquet(file.path(CD,"sue.parquet"))); sue[, Date := as.Date(Date)]
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet"))); setnames(A, "signal_date", "Date"); A[, Date := as.Date(Date)]
say("★입력 실측: alpha_scores %d행 · %d개월 (%s~%s) · sue 원천 %d행 · Date %d개",
    nrow(A), uniqueN(A$Date), min(A$signal_ym), max(A$signal_ym), nrow(sue), uniqueN(sue$Date))

sds <- sort(unique(A$Date)); sds <- sds[seq(1, length(sds), length.out=min(10L,length(sds)))]
L1 <- rbindlist(lapply(sds, function(sig_d) {
  src <- sue[Date <= (sig_d-3L) & Date >= (sig_d-400L) & is.finite(sue)]
  if (!nrow(src)) return(NULL)
  setorderv(src, c("Ticker","Date"), c(1L,-1L))
  ad <- src[, .(ann_date = Date[1L]), by=Ticker]
  ad[, lagdays := as.numeric(sig_d - ann_date)]
  data.table(ym=format(sig_d,"%Y-%m"), n=nrow(ad),
             lag_med=median(ad$lagdays), lag_min=min(ad$lagdays), lag_max=max(ad$lagdays),
             frac_le5 = mean(ad$lagdays <= 5), frac_le10 = mean(ad$lagdays <= 10),
             n_distinct_ad = uniqueN(ad$ann_date))
}))
for (i in seq_len(nrow(L1))) with(L1[i], say(
  "  %s n=%4d · sig_d − ann_date: 중앙 %.0f일 (최소 %.0f · 최대 %.0f) · <=5일 %.4f · <=10일 %.4f · 고유 ann_date %d개",
  ym, n, lag_med, lag_min, lag_max, frac_le5, frac_le10, n_distinct_ad))
say("★해석: 중앙 시차가 며칠이고 고유 ann_date 가 소수면 '발표일'이 아니라 **월말 고정창**이다.")

## =============================================================================
## [2] 반전 통제 — C18 증분이 단기 반전의 재포장인가
## =============================================================================
say("================ [2] 반전/모멘텀 통제 하 C18 증분 ================")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Ret","BM_Ret")))
RAW[, Date := as.Date(Date)]
say("RAWDATA(수익): %d행 · 고유 Date %d · 범위 %s ~ %s", nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
RAW <- RAW[is.finite(Ret) & is.finite(BM_Ret)]
RAW[, ar := Ret - BM_Ret]                       # 시장조정 (C18 과 동일 정의)

## 신호월 말 기준 trailing 시장조정 누적수익 — C18 창(6일)과 표준 반전창(1M)·모멘텀(12M)
build_trail <- function(sig_d, ndays_lo, ndays_hi) {
  x <- RAW[Date > (sig_d - ndays_hi) & Date <= (sig_d - ndays_lo)]
  x[, .(v = sum(ar)), by=Ticker]
}
TR <- rbindlist(lapply(sort(unique(A$Date)), function(sig_d) {
  a6  <- build_trail(sig_d, 0L,  7L)     # 최근 ~6일 (C18 창과 정렬)
  a1m <- build_trail(sig_d, 0L,  31L)    # 최근 1개월 (표준 단기반전)
  a12 <- build_trail(sig_d, 31L, 366L)   # t-12M ~ t-1M (표준 모멘텀)
  if (!nrow(a6)) return(NULL)
  setnames(a6,"v","trail6d"); setnames(a1m,"v","trail1m"); setnames(a12,"v","trail12m")
  m <- Reduce(function(p,q) merge(p,q,by="Ticker",all=TRUE), list(a6,a1m,a12))
  m[, Date := sig_d]; m
}))
say("trailing 패널: %d행 · %d개월", nrow(TR), uniqueN(TR$Date))

zc <- function(x){ q <- quantile(x,c(.01,.99),na.rm=TRUE); x <- pmin(pmax(x,q[1]),q[2])
  s <- sd(x,na.rm=TRUE); if (!is.finite(s)||s<1e-12) return(rep(NA_real_,length(x))); (x-mean(x,na.rm=TRUE))/s }
for (f in c("trail6d","trail1m","trail12m")) TR[, (f) := zc(get(f)), by=Date]

D <- merge(A, TR, by=c("Date","Ticker"), all.x=TRUE)
INC <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR")
say("병합 후 %d행 · C18 유효 %d · trail6d 유효 %d · trail1m 유효 %d · trail12m 유효 %d",
    nrow(D), sum(is.finite(D$C18_Earnings_CAR_3d)), sum(is.finite(D$trail6d)),
    sum(is.finite(D$trail1m)), sum(is.finite(D$trail12m)))

## ★C18 이 trailing 창과 얼마나 같은가 (재포장 직접 증거)
sp <- D[complete.cases(D[, .(C18_Earnings_CAR_3d, trail6d, trail1m)]),
        .(rho6 = cor(C18_Earnings_CAR_3d, trail6d, method="spearman"),
          rho1m= cor(C18_Earnings_CAR_3d, trail1m, method="spearman"), n=.N), by=signal_ym][n>=30L]
say("★C18 vs trail6d 월별 spearman: 평균 %+.4f (sd %.3f · 5%% %+.3f · 95%% %+.3f · n=%d개월)",
    mean(sp$rho6), sd(sp$rho6), quantile(sp$rho6,.05), quantile(sp$rho6,.95), nrow(sp))
say("★C18 vs trail1m 월별 spearman: 평균 %+.4f (sd %.3f · n=%d개월)", mean(sp$rho1m), sd(sp$rho1m), nrow(sp))

fmb <- function(dat, xs) dat[, {
  fit <- tryCatch(lm(as.formula(paste("Ret_1m ~", paste(xs, collapse="+"))), data=.SD), error=function(e) NULL)
  if (is.null(fit)) .(term=character(0), est=numeric(0)) else { cf <- coef(fit); .(term=names(cf), est=as.numeric(cf)) }
}, by=signal_ym, .SDcols=c("Ret_1m", xs)]

specs <- list(
  base        = c(INC, "C18_Earnings_CAR_3d"),
  plus_1m     = c(INC, "C18_Earnings_CAR_3d", "trail1m"),
  plus_6d     = c(INC, "C18_Earnings_CAR_3d", "trail6d"),
  plus_1m_12m = c(INC, "C18_Earnings_CAR_3d", "trail1m", "trail12m"),
  full        = c(INC, "C18_Earnings_CAR_3d", "trail6d", "trail1m", "trail12m")
)
OUTS <- rbindlist(lapply(names(specs), function(nm) {
  xs <- specs[[nm]]
  dd <- D[complete.cases(D[, ..xs]) & is.finite(Ret_1m)]
  mm <- dd[, .N, by=signal_ym]; dd <- dd[signal_ym %in% mm[N>=30L, signal_ym]]
  if (uniqueN(dd$signal_ym) < 20L) return(NULL)
  cf <- fmb(dd, xs); e <- cf[term=="C18_Earnings_CAR_3d", est]
  data.table(spec=nm, n_months=length(e), med_n=median(mm[N>=30L]$N),
             mean=mean(e), t_nw3=nw_t(e),
             t_trail1m = if ("trail1m" %in% xs) nw_t(cf[term=="trail1m", est]) else NA_real_,
             t_trail6d = if ("trail6d" %in% xs) nw_t(cf[term=="trail6d", est]) else NA_real_,
             t_trail12m= if ("trail12m"%in% xs) nw_t(cf[term=="trail12m",est]) else NA_real_)
}))
for (i in seq_len(nrow(OUTS))) with(OUTS[i], say(
  "  %-12s n=%3d (월중앙 %.0f종) · C18 mean %+.6f · ★C18 t %+.3f | trail1m t %s · trail6d t %s · trail12m t %s",
  spec, n_months, med_n, mean, t_nw3,
  ifelse(is.na(t_trail1m),"—",sprintf("%+.2f",t_trail1m)),
  ifelse(is.na(t_trail6d),"—",sprintf("%+.2f",t_trail6d)),
  ifelse(is.na(t_trail12m),"—",sprintf("%+.2f",t_trail12m))))

b <- OUTS[spec=="base"]$t_nw3
for (nm in setdiff(OUTS$spec,"base")) {
  v <- OUTS[spec==nm]$t_nw3
  say("  ★유지율 [%-12s] |t| %.3f / |base| %.3f = %.2f", nm, abs(v), abs(b), abs(v)/abs(b))
}
say("★사전등록 자격 전제조건: 반전/모멘텀 통제 후에도 증분이 남아야 자격 인정.")
say("  통제 후 |t| 가 2.0 미만으로 떨어지면 **재포장** → t 값과 무관하게 재료 자격 불인정.")

fwrite(L1,   file.path(OUT,"p3b_ann_proxy.csv"))
fwrite(OUTS, file.path(OUT,"p3b_reversal_control.csv"))
fwrite(sp,   file.path(OUT,"p3b_c18_vs_trailing.csv"))
saveRDS(list(L1=L1, OUTS=OUTS, sp=sp), file.path(OUT,"p3b_results.rds"))
say("저장 완료")
