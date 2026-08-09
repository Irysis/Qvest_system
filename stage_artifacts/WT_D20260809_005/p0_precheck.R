## =============================================================================
## FQ-198 / WT-D20260809_005 — P0 사전 확인 (착수 전 의무)
##
## 목적: 해금 4종(C10/C13/C15/C18)이 측정할 가치가 있는가를 착수 *전에* 판정.
##   ①유효월·커버리지 실측 (300개월 산출 ≠ 유효 관측)
##   ②spearman 사전 확인 — C01/C02/C04 + M26 대비. 평균 rho >= 0.9 면 재탕 처분
##   ③required_effect() 로 필요 연효과 기록 — 비현실적이면 착수 전 폐기
##
## ★규약: 측정 첫 출력 = 입력 실측(행수·관측단위·범위). (2026-08-08)
## ★C15: factor DB 는 load_month_factors() 경유만.
## metric_type: diagnostic_precheck (성과 주장 아님)
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_005")
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)
say <- function(fmt,...) { cat(sprintf(paste0("[p0] ",fmt,"\n"),...)); flush.console() }
set.seed(20260809L)

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/align_signal_return_ym.R")
source("02_Infrastructure/contracts/required_effect_size.R")

nw_t <- function(x, lag=3L){
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}

INCUMBENT <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR")
NEW4      <- c("C10_SUE_Persistence","C13_Revision_Breadth_3m",
               "C15_Forecast_Error_Trend","C18_Earnings_CAR_3d")
REF       <- "M26_Revenue_Mom"                 # 선례(재료 자격 t 2.555) — 재탕 대조축
FACS      <- c(INCUMBENT, NEW4, REF)

## =============================================================================
## [0] 입력 실측 — 행수 · 관측단위 · 범위
## =============================================================================
say("================ [0] 입력 실측 ================")
fp <- sort(Sys.glob(".cache/factor_db/factor_db_*.parquet"))
say("factor_db 월 파일 %d개 · %.2f GB · %s ~ %s",
    length(fp), sum(file.size(fp))/1e9, basename(fp[1]), basename(fp[length(fp)]))
bh <- Sys.glob(".cache/factor_db/*build_hash*")
say("build_hash 마커: %s", if (length(bh)) paste(basename(bh), collapse=",") else "(파일 없음 — 재빌드 기록은 FQ-163 verdict)")

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
n_date <- uniqueN(RAW$Date); n_ym <- uniqueN(format(RAW$Date,"%Y-%m"))
unit <- if (n_date > n_ym*1.5) "일간(daily)" else "월간(monthly)"
say("RAWDATA: %d행 · 고유 Date %d · 고유 년월 %d ⇒ ★관측단위 = %s · 범위 %s ~ %s",
    nrow(RAW), n_date, n_ym, unit, min(RAW$Date), max(RAW$Date))
if (unit != "일간(daily)") stop("[p0] 입력 관측단위 가정 위반 — 착수 중단")

ME <- sort(RAW[, .(Date=max(Date)), by=.(ym=format(Date,"%Y-%m"))]$Date)
RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
say("forward 수익 패널: %d행 · %d개월 · 관측단위 = (월말 anchor Date × Ticker) · %s ~ %s",
    nrow(ret), uniqueN(ret$Date), min(ret$Date), max(ret$Date))
say("  dating = signal_anchor (Date=신호월말, Ret_1m=익월 실현) ⇒ 병합 off=0")

## =============================================================================
## [1] 팩터 패널 로드 (C15 커넥터 경유)
## =============================================================================
say("================ [1] 팩터 패널 (load_month_factors 경유, %d종) ================", length(FACS))
sig_dates <- ME[ME <= max(ret$Date)]
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
say("로드 완료 %.0fs · %d행 · %d개월", as.numeric(difftime(Sys.time(),t0,units="secs")),
    nrow(P), uniqueN(P$Date))
missing <- setdiff(FACS, names(P))
if (length(missing)) say("★패널 부재 팩터: %s", paste(missing, collapse=", "))

ao <- data.table(k=asof)[, tstrsplit(k,"|",fixed=TRUE)]
setnames(ao, c("sig_ym","asof_date")); ao[, asof_ym := substr(asof_date,1,7)]
say("as-of 정합: 신호월==vintage월 %d/%d · 불일치 %d",
    sum(ao$sig_ym==ao$asof_ym, na.rm=TRUE), nrow(ao), sum(ao$sig_ym!=ao$asof_ym, na.rm=TRUE))

## =============================================================================
## [2] ①유효월 · 커버리지 실측
## =============================================================================
say("================ [2] ① 유효월 · 커버리지 (팩터 단독) ================")
cov1 <- rbindlist(lapply(intersect(FACS, names(P)), function(f) {
  sub <- P[is.finite(get(f))]
  if (!nrow(sub)) return(data.table(factor=f, n_months=0L))
  mm <- sub[, .N, by=Date]
  data.table(factor=f, n_months=uniqueN(sub$Date),
             first=format(min(sub$Date),"%Y-%m"), last=format(max(sub$Date),"%Y-%m"),
             stock_months=nrow(sub), med_n=median(mm$N), min_n=min(mm$N), max_n=max(mm$N))
}), fill=TRUE)
for (i in seq_len(nrow(cov1))) with(cov1[i], say(
  "  %-26s 유효월 %3d (%s ~ %s) · 종목-월 %7d · 월중앙 종목수 %4.0f (최소 %d / 최대 %d)",
  factor, n_months, first, last, stock_months, med_n, min_n, max_n))

## 병합 → 교집합 커버리지
S <- copy(P); setnames(S, "Date", "signal_date")
M <- align_signal_return_ym(S, ret, signal_date_col="signal_date", return_date_col="Date",
                            id_col="Ticker", off=0L, return_dating="signal_anchor",
                            coverage_min=0.90, vintage_label="factor_db_monthend_v1")
say("병합 %d행 · 월 coverage %.3f · 행 coverage %.3f", nrow(M),
    attr(M,"align_coverage_month"), attr(M,"align_coverage_row"))
D <- M[is.finite(Ret_1m)]
MINN <- 30L

say("--- ★교집합 커버리지: incumbent 3종 + 신규 1종 동시 가용 (실제 판정 표본) ---")
cov2 <- rbindlist(lapply(NEW4, function(f) {
  cols <- c(INCUMBENT, f)
  dd <- D[complete.cases(D[, ..cols])]
  if (!nrow(dd)) return(data.table(factor=f, n_months=0L))
  mm <- dd[, .N, by=signal_ym]
  keep <- mm[N>=MINN, signal_ym]
  dk <- dd[signal_ym %in% keep]
  mk <- dk[, .N, by=signal_ym]
  data.table(factor=f, n_months=uniqueN(dk$signal_ym),
             first=min(dk$signal_ym), last=max(dk$signal_ym),
             stock_months=nrow(dk), med_n=median(mk$N), min_n=min(mk$N),
             sqrtN=sqrt(median(mk$N)),
             solo_months=cov1[factor==f]$n_months,
             retention=uniqueN(dk$signal_ym)/max(cov1[factor==f]$n_months,1))
}), fill=TRUE)
for (i in seq_len(nrow(cov2))) with(cov2[i], say(
  "  %-26s 판정월 %3d (%s ~ %s) · 종목-월 %6d · 월중앙 %4.0f (√N %.1f) · 단독 %d개월 대비 유지 %.2f",
  factor, n_months, first, last, stock_months, med_n, sqrtN, solo_months, retention))

## =============================================================================
## [3] ② spearman 사전 확인 — 0.9 이상이면 재탕 처분
## =============================================================================
say("================ [3] ② 횡단면 spearman (월별 → 시계열 평균) ================")
others <- c(INCUMBENT, REF)
sp <- rbindlist(lapply(NEW4, function(f) {
  cols <- c(INCUMBENT, f); dd <- D[complete.cases(D[, ..cols])]
  rbindlist(lapply(others, function(o) {
    if (!o %in% names(dd)) return(NULL)
    s <- dd[, .(rho = suppressWarnings(cor(get(f), get(o), method="spearman", use="complete.obs")),
                n=.N), by=signal_ym][n>=MINN & is.finite(rho)]
    if (!nrow(s)) return(NULL)
    data.table(new=f, other=o, mean_rho=mean(s$rho), sd_rho=sd(s$rho),
               p05=quantile(s$rho,.05), p95=quantile(s$rho,.95),
               max_month=max(s$rho), n_months=nrow(s))
  }))
}))
for (i in seq_len(nrow(sp))) with(sp[i], say(
  "  %-26s vs %-18s  평균 rho %+.4f (sd %.3f · 5%% %+.3f · 95%% %+.3f · 월최대 %+.3f · n=%d)",
  new, other, mean_rho, sd_rho, p05, p95, max_month, n_months))
redun <- sp[, .(max_abs_rho = max(abs(mean_rho)),
                worst = other[which.max(abs(mean_rho))]), by=new]
redun[, verdict := fifelse(max_abs_rho >= 0.9, "REDUNDANT_재탕처분", "DISTINCT_측정진행")]
say("--- ★재탕 판정 (문턱 |평균 rho| >= 0.90) ---")
for (i in seq_len(nrow(redun))) with(redun[i], say(
  "  %-26s 최대 |평균 rho| %.4f (vs %s) ⇒ %s", new, max_abs_rho, worst, verdict))

## 신규 4종 상호 상관 (한 회귀 동시 투입 금지 근거 + 서로 재탕인지)
say("--- 신규 4종 상호 spearman (참고) ---")
pairs <- combn(NEW4, 2, simplify=FALSE)
spx <- rbindlist(lapply(pairs, function(pp) {
  dd <- D[complete.cases(D[, ..pp])]
  s <- dd[, .(rho=suppressWarnings(cor(get(pp[1]), get(pp[2]), method="spearman", use="complete.obs")), n=.N),
          by=signal_ym][n>=MINN & is.finite(rho)]
  if (!nrow(s)) return(NULL)
  data.table(a=pp[1], b=pp[2], mean_rho=mean(s$rho), n=nrow(s))
}))
for (i in seq_len(nrow(spx))) with(spx[i], say("  %-26s vs %-26s  %+.4f (n=%d)", a, b, mean_rho, n))

## =============================================================================
## [4] ③ required_effect — 필요 연효과 (계열 고유 sd 로 재산출)
## =============================================================================
say("================ [4] ③ 검정력 — 필요 효과크기 ================")
fmb_coefs <- function(dat, xs, ycol="Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse=" + ")))
  dat[, { fit <- tryCatch(lm(f, data=.SD), error=function(e) NULL)
          if (is.null(fit)) .(term=character(0), est=numeric(0))
          else { cf <- coef(fit); .(term=names(cf), est=as.numeric(cf)) } },
      by=signal_ym, .SDcols=c(ycol, xs)]
}
pw <- rbindlist(lapply(NEW4, function(f) {
  cols <- c(INCUMBENT, f); dd <- D[complete.cases(D[, ..cols])]
  mm <- dd[, .N, by=signal_ym]; dd <- dd[signal_ym %in% mm[N>=MINN, signal_ym]]
  if (uniqueN(dd$signal_ym) < 20L) return(data.table(factor=f, n_months=uniqueN(dd$signal_ym)))
  cf <- fmb_coefs(dd, c(INCUMBENT, f))
  e  <- cf[term==f, est]
  n  <- length(e); sdc <- sd(e)
  req <- required_effect(n=n, t_threshold=2.0, sd_monthly=sdc, design="full")
  data.table(factor=f, n_months=n, sd_coef=sdc,
             required_monthly=req$required_monthly, required_annual_pct=req$required_annual*100,
             observed_monthly=mean(e), observed_annual_pct=mean(e)*12*100,
             t_nw3=nw_t(e))
}), fill=TRUE)
for (i in seq_len(nrow(pw))) with(pw[i], say(
  "  %-26s n=%3d · 계열 sd %.5f · 필요 월 %.5f (연 %.2f%%) · 관측 월 %+.5f (연 %+.2f%%) · t_NW3 %+.3f",
  factor, n_months, sd_coef, required_monthly, required_annual_pct,
  observed_monthly, observed_annual_pct, t_nw3))
## 바가 무엇을 재는지 — implied_t_threshold 확인 (계열 고유 sd 는 t 검정 재진술 위험)
for (i in seq_len(nrow(pw))) {
  r <- pw[i]
  vp <- verdict_with_power(observed_t=abs(r$t_nw3), observed_monthly=abs(r$observed_monthly),
                           n=r$n_months, t_threshold=2.0, sd_monthly=r$sd_coef, design="full")
  say("  %-26s 검정력 라벨: %-32s (implied_t %.2f)", r$factor, vp$verdict,
      if (!is.null(vp$implied_t_threshold)) vp$implied_t_threshold else NA_real_)
}
## 외부 기준 바 (top-25 EW 바스켓쌍 실측 sd) — 계열 고유 바가 재진술일 때의 대체 기준
say("--- 외부 기준(도구 기본 sd 0.0394, top-25 EW 바스켓쌍) ---")
for (i in seq_len(nrow(pw))) {
  r <- pw[i]; ref <- required_effect(n=r$n_months, design="full")
  say("  %-26s n=%d ⇒ 필요 연 %.2f%% (프레임 상이 — 참고치)", r$factor, r$n_months, ref$required_annual*100)
}

## =============================================================================
## [5] 착수/폐기 판정 + 저장
## =============================================================================
say("================ [5] 착수 판정 ================")
dec <- merge(merge(cov2[, .(factor, n_months, med_n, retention)],
                   redun[, .(factor=new, max_abs_rho, verdict_redundancy=verdict)], by="factor"),
             pw[, .(factor, t_nw3, required_annual_pct, observed_annual_pct)], by="factor")
dec[, decision := fifelse(n_months < 60L, "ABORT_표본부족",
                   fifelse(max_abs_rho >= 0.9, "ABORT_재탕", "PROCEED"))]
for (i in seq_len(nrow(dec))) with(dec[i], say(
  "  %-26s 월 %3d · 최대rho %.3f · 예비 t %+.3f ⇒ ★%s", factor, n_months, max_abs_rho, t_nw3, decision))
say("★착수 대상 %d/4: %s", sum(dec$decision=="PROCEED"),
    paste(dec[decision=="PROCEED", factor], collapse=", "))

fwrite(cov1, file.path(OUT,"p0_coverage_solo.csv"))
fwrite(cov2, file.path(OUT,"p0_coverage_intersect.csv"))
fwrite(sp,   file.path(OUT,"p0_spearman_vs_incumbent.csv"))
fwrite(spx,  file.path(OUT,"p0_spearman_new_pairs.csv"))
fwrite(pw,   file.path(OUT,"p0_power.csv"))
fwrite(dec,  file.path(OUT,"p0_decision.csv"))
saveRDS(list(P=P, D=D, MINN=MINN, cov1=cov1, cov2=cov2, sp=sp, spx=spx, pw=pw, dec=dec,
             INCUMBENT=INCUMBENT, NEW4=NEW4, REF=REF),
        file.path(OUT,"p0_panel.rds"))
say("저장 완료 → %s", OUT)
