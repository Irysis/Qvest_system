## =============================================================================
## FQ-198 / WT-D20260809_005 — 주판정: 컨센서스 신규 재료 증분 회귀
##
## ★사전등록 (실행 전 확정, 이 헤더가 사전등록 원본):
##   primary(1)      : C18_Earnings_CAR_3d          — 원안 4종 중 유일 생존
##   exploratory(3)  : C10s / C13s / C15s (스텝-보정판) — P0 사전 확인 중 발견, 원안 아님
##   dead(3)         : C10_SUE_Persistence ≡ C01 · C13_Revision_Breadth_3m ≡ C04 (재탕, spearman 1.000000)
##                     C15_Forecast_Error_Trend = 미산출(인접 영업일 차분이 항등 0)
##
##   주판정량 : fwd_ret ~ z(C01_SUE)+z(C02_EPS_Chg_1m)+z(C04_ESBR)+z(신규) 의 신규 계수
##              Fama-MacBeth NW(lag3) t.  pooled OLS 금지.  4종을 한 회귀에 동시 투입 금지.
##   문턱     : |t| >= 2.0 = 재료 자격 (자본 게이트 아님)
##   다중검정 : 보고 arm 4개 → Bonferroni |t| >= 2.50 (양측 alpha .05/4) 병기
##   설계     : 전표본 횡단면. 국면 분할 없음(구조적 저검정력 회피).
##   metric_type: canonical_screen_diag (계약 백테 미경유 횡단면 진단 — 성과 주장 아님)
##   ★재료 자격까지만 — 자본 주장 금지 (선례 M26: 재료 t 2.555 획득, 전이 미달)
##
## ★규약: 측정 첫 출력 = 입력 실측(행수·관측단위·범위).
## ★C15 규칙: factor DB 는 load_month_factors() 경유만. 스텝-보정판은 factor DB 에 없는
##   신규 프로토타입이라 consensus **원천**에서 파생한다(팩터 DB 우회 아님).
## ★C13 규칙: NEGATE/FLIP 금지. 스텝-보정판 부호는 **사전 지정**(전부 양의 방향 = 값이 클수록 좋음),
##   IC 로 사후 정렬하지 않는다.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_005")
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)
say <- function(fmt,...) { cat(sprintf(paste0("[p1] ",fmt,"\n"),...)); flush.console() }
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
nw_se <- function(x, lag=3L){
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  sqrt(s/n)
}
INCUMBENT <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR")
DBFACS    <- c(INCUMBENT, "C18_Earnings_CAR_3d")
STEPFACS  <- c("C10s_SUE_Persist_step","C13s_RevBreadth_step","C15s_SUE_Trend_step")
ARMS      <- c("C18_Earnings_CAR_3d", STEPFACS)
BONF_T    <- 2.50   # 양측 alpha .05 / 4 arm
MINN      <- 30L

## =============================================================================
## [0] 입력 실측
## =============================================================================
say("================ [0] 입력 실측 ================")
fp <- sort(Sys.glob(".cache/factor_db/factor_db_*.parquet"))
bh <- tryCatch(readLines(".cache/factor_db/build_hash.txt", warn=FALSE)[1], error=function(e) NA_character_)
say("factor_db 월 파일 %d개 · %.2f GB · build_hash = %s", length(fp), sum(file.size(fp))/1e9, bh)

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
n_date <- uniqueN(RAW$Date); n_ym <- uniqueN(format(RAW$Date,"%Y-%m"))
unit <- if (n_date > n_ym*1.5) "일간(daily)" else "월간(monthly)"
say("RAWDATA: %d행 · 고유 Date %d · 고유 년월 %d ⇒ ★관측단위 = %s · 범위 %s ~ %s",
    nrow(RAW), n_date, n_ym, unit, min(RAW$Date), max(RAW$Date))
if (unit != "일간(daily)") stop("[p1] 입력 관측단위 가정 위반 — 착수 중단")

ME <- sort(RAW[, .(Date=max(Date)), by=.(ym=format(Date,"%Y-%m"))]$Date)
SIZE <- RAW[Date %in% ME, .(Date, Ticker, Size, K200, KQ150)]      # cap-tier 분해용
RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
say("forward 수익 패널: %d행 · %d개월 · 관측단위 = (월말 anchor Date × Ticker) · %s ~ %s",
    nrow(ret), uniqueN(ret$Date), min(ret$Date), max(ret$Date))
say("  dating = signal_anchor (Date=신호월말, Ret_1m=익월 실현) ⇒ 병합 off=0 · 방화벽 격리 %d",
    fwd$ret_firewall_dropped)

## =============================================================================
## [1] factor DB 패널 (커넥터 경유)
## =============================================================================
say("================ [1] factor DB 패널 (load_month_factors 경유) ================")
sig_dates <- ME[ME <= max(ret$Date)]
t0 <- Sys.time(); panels <- vector("list", length(sig_dates)); asof <- character(0)
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  z <- tryCatch(load_month_factors(d, factor_names=DBFACS), error=function(e) NULL)
  if (is.null(z) || !nrow(z)) next
  asof <- c(asof, sprintf("%s|%s", format(d,"%Y-%m"), as.character(attr(z,"factor_db_asof_date"))))
  w <- dcast(as.data.table(z), Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  w[, Date := d]; panels[[i]] <- w
  if (i %% 80 == 0) say("  ... %d/%d (%.0fs)", i, length(sig_dates), as.numeric(difftime(Sys.time(),t0,units="secs")))
}
P <- rbindlist(panels, fill=TRUE)
say("로드 완료 %.0fs · %d행 · %d개월", as.numeric(difftime(Sys.time(),t0,units="secs")), nrow(P), uniqueN(P$Date))
ao <- data.table(k=asof)[, tstrsplit(k,"|",fixed=TRUE)]; setnames(ao, c("sig_ym","asof_date"))
ao[, asof_ym := substr(asof_date,1,7)]
say("as-of 정합: 신호월==vintage월 %d/%d · 불일치 %d", sum(ao$sig_ym==ao$asof_ym), nrow(ao), sum(ao$sig_ym!=ao$asof_ym))

## =============================================================================
## [2] 스텝-보정 프로토타입 3종 (consensus 원천 파생, PIT: Date <= sig_date)
## =============================================================================
say("================ [2] 스텝-보정 프로토타입 (exploratory) ================")
CD <- file.path(CACHE_DIR, "consensus")
sue  <- as.data.table(read_parquet(file.path(CD,"sue.parquet")));  sue[,  Date := as.Date(Date)]
esbr <- as.data.table(read_parquet(file.path(CD,"esbr.parquet"))); esbr[, Date := as.Date(Date)]
say("원천 실측 — sue: %d행 · Date %d개 (%s~%s) · Ticker %d | esbr: %d행 · Date %d개 · Ticker %d",
    nrow(sue), uniqueN(sue$Date), min(sue$Date), max(sue$Date), uniqueN(sue$Ticker),
    nrow(esbr), uniqueN(esbr$Date), uniqueN(esbr$Ticker))

## 스텝 압축: 값이 **바뀐 시점**만 남긴다 (Ticker별 시간순). 전역 1회 → PIT 는 step_date <= sig_date 로 적용.
compress_steps <- function(dt, vcol) {
  x <- dt[is.finite(get(vcol)), c("Date","Ticker",vcol), with=FALSE]
  setorderv(x, c("Ticker","Date"))
  x[, keep := c(TRUE, get(vcol)[-1] != get(vcol)[-.N]), by=Ticker]
  s <- x[keep == TRUE, c("Ticker","Date",vcol), with=FALSE]
  setnames(s, vcol, "v"); setorderv(s, c("Ticker","Date")); s[]
}
S_sue  <- compress_steps(sue,  "sue")
S_esbr <- compress_steps(esbr, "esbr")
say("스텝 압축: sue %d행 → %d 스텝 (%.4f) · esbr %d행 → %d 스텝 (%.4f)",
    nrow(sue), nrow(S_sue), nrow(S_sue)/nrow(sue), nrow(esbr), nrow(S_esbr), nrow(S_esbr)/nrow(esbr))
say("  Ticker당 총 스텝 수: sue 중앙 %.0f · esbr 중앙 %.0f",
    median(S_sue[, .N, by=Ticker]$N), median(S_esbr[, .N, by=Ticker]$N))

## sig_date 별로 최근 k 스텝을 뽑아 프로토타입 계산 (PIT: Date <= sig_date)
step_features <- function(S, sig_d) {
  h <- S[Date <= sig_d]
  if (!nrow(h)) return(NULL)
  setorderv(h, c("Ticker","Date"), c(1L,-1L))
  h[, rn := seq_len(.N), by=Ticker]
  h[rn <= 4L, .(n_step = .N,
                avg4   = mean(v[rn <= 4L]),
                avg3   = mean(v[rn <= 3L]),
                d1     = if (.N >= 2L) v[1L] - v[2L] else NA_real_), by=Ticker]
}
t0 <- Sys.time(); protos <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  a <- step_features(S_sue,  d); b <- step_features(S_esbr, d)
  if (is.null(a) && is.null(b)) next
  x <- if (is.null(a)) data.table(Ticker=character()) else
        a[, .(Ticker, C10s_SUE_Persist_step = avg4, C15s_SUE_Trend_step = d1)]
  y <- if (is.null(b)) NULL else b[, .(Ticker, C13s_RevBreadth_step = avg3)]
  m <- if (is.null(y)) x else merge(x, y, by="Ticker", all=TRUE)
  m[, Date := d]; protos[[i]] <- m
  if (i %% 80 == 0) say("  ... 프로토타입 %d/%d (%.0fs)", i, length(sig_dates), as.numeric(difftime(Sys.time(),t0,units="secs")))
}
PR <- rbindlist(protos, fill=TRUE)
say("프로토타입 패널 %.0fs · %d행 · %d개월", as.numeric(difftime(Sys.time(),t0,units="secs")), nrow(PR), uniqueN(PR$Date))

## 횡단면 z (★부호 사전 지정: 3종 모두 양의 방향. IC 사후 정렬 안 함 — C13 규칙)
zc <- function(x) { q <- quantile(x, c(.01,.99), na.rm=TRUE); x <- pmin(pmax(x,q[1]),q[2])
                    s <- sd(x, na.rm=TRUE); if (!is.finite(s) || s < 1e-12) return(rep(NA_real_, length(x)))
                    (x - mean(x, na.rm=TRUE))/s }
for (f in STEPFACS) PR[, (f) := zc(get(f)), by=Date]
for (f in STEPFACS) {
  sub <- PR[is.finite(get(f))]
  say("  %-26s 유효월 %3d (%s ~ %s) · 종목-월 %6d · 월중앙 %4.0f",
      f, uniqueN(sub$Date), format(min(sub$Date),"%Y-%m"), format(max(sub$Date),"%Y-%m"),
      nrow(sub), median(sub[, .N, by=Date]$N))
}

## =============================================================================
## [3] 병합
## =============================================================================
say("================ [3] 병합 (align_signal_return_ym, off=0) ================")
ALL <- merge(P, PR, by=c("Date","Ticker"), all=TRUE)
S <- copy(ALL); setnames(S, "Date", "signal_date")
M <- align_signal_return_ym(S, ret, signal_date_col="signal_date", return_date_col="Date",
                            id_col="Ticker", off=0L, return_dating="signal_anchor",
                            coverage_min=0.90, vintage_label="factor_db_monthend_v1")
D <- M[is.finite(Ret_1m)]
say("병합 %d행 · 월 coverage %.3f · 행 coverage %.3f", nrow(M),
    attr(M,"align_coverage_month"), attr(M,"align_coverage_row"))
SIZE[, signal_ym := format(Date,"%Y-%m")]
D <- merge(D, SIZE[, .(signal_ym, Ticker, Size, K200, KQ150)], by=c("signal_ym","Ticker"), all.x=TRUE)

## =============================================================================
## [4] 주판정 — arm 별 증분 FMB (각각 별도 회귀)
## =============================================================================
say("================ [4] 주판정: arm 별 증분 FMB NW(lag3) ================")
fmb_coefs <- function(dat, xs, ycol="Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse=" + ")))
  dat[, { fit <- tryCatch(lm(f, data=.SD), error=function(e) NULL)
          if (is.null(fit)) .(term=character(0), est=numeric(0))
          else { cf <- coef(fit); .(term=names(cf), est=as.numeric(cf)) } },
      by=signal_ym, .SDcols=c(ycol, xs)]
}
## VIF (증분 회귀 공선성) — 월별 계산 후 중앙값
vif_med <- function(dat, xs) {
  v <- dat[, {
    ok <- complete.cases(.SD); sd_ <- .SD[ok]
    if (sum(ok) < 40L) .(term=character(0), vif=numeric(0)) else {
      out <- sapply(xs, function(tg) {
        oth <- setdiff(xs, tg)
        r2 <- suppressWarnings(summary(lm(as.formula(paste(tg,"~",paste(oth,collapse="+"))), data=sd_))$r.squared)
        if (!is.finite(r2) || r2 >= 1) NA_real_ else 1/(1-r2) })
      .(term=xs, vif=as.numeric(out)) }
  }, by=signal_ym, .SDcols=xs]
  v[, .(vif_med=median(vif, na.rm=TRUE), vif_max=max(vif, na.rm=TRUE)), by=term]
}

RES <- list(); COEFS <- list()
for (arm in ARMS) {
  cols <- c(INCUMBENT, arm)
  dd <- D[complete.cases(D[, ..cols])]
  mm <- dd[, .N, by=signal_ym]; dd <- dd[signal_ym %in% mm[N>=MINN, signal_ym]]
  nmo <- uniqueN(dd$signal_ym)
  if (nmo < 20L) { say("  %-26s 판정월 %d < 20 ⇒ 측정 불가", arm, nmo); next }
  cf <- fmb_coefs(dd, cols); COEFS[[arm]] <- cf
  e  <- cf[term==arm, est]
  ## 단독 대조
  cf1 <- fmb_coefs(dd, arm); e1 <- cf1[term==arm, est]
  ## rank IC (단독)
  ic <- dd[, .(ic=suppressWarnings(cor(get(arm), Ret_1m, method="spearman", use="complete.obs"))),
           by=signal_ym][is.finite(ic)]
  vf <- vif_med(dd, cols)
  RES[[arm]] <- data.table(
    arm=arm, kind=if (arm=="C18_Earnings_CAR_3d") "primary_preregistered" else "exploratory_precheck_discovered",
    n_months=length(e), med_n=median(mm[N>=MINN]$N),
    first=min(dd$signal_ym), last=max(dd$signal_ym),
    mean_coef=mean(e), sd_coef=sd(e), se_nw3=nw_se(e), t_nw3=nw_t(e),
    t_simple=mean(e)/sd(e)*sqrt(length(e)), pos_rate=mean(e>0),
    solo_t_nw3=nw_t(e1), solo_mean=mean(e1),
    rank_ic=mean(ic$ic), rank_ic_t=nw_t(ic$ic), icir=mean(ic$ic)/sd(ic$ic), n_ic=nrow(ic),
    vif_med=vf[term==arm]$vif_med, vif_max=vf[term==arm]$vif_max)
  r <- RES[[arm]]
  say("  %-26s [%s]", arm, r$kind)
  say("     판정월 %3d (%s~%s · 월중앙 %.0f종) · mean %+.6f · SE_NW %.6f · ★t_NW3 %+.3f · t_simple %+.2f · 부호>0 %.1f%%",
      r$n_months, r$first, r$last, r$med_n, r$mean_coef, r$se_nw3, r$t_nw3, r$t_simple, r$pos_rate*100)
  say("     단독 t %+.3f (증분/단독 %.2f) · rank-IC %+.4f (t %+.2f · ICIR %.3f) · VIF 중앙 %.2f (최대 %.2f)",
      r$solo_t_nw3, r$t_nw3/r$solo_t_nw3, r$rank_ic, r$rank_ic_t, r$icir, r$vif_med, r$vif_max)
}
RT <- rbindlist(RES)

## =============================================================================
## [5] spearman — 신규 vs incumbent (재탕 재확인)
## =============================================================================
say("================ [5] spearman vs incumbent ================")
SP <- rbindlist(lapply(ARMS, function(arm) {
  cols <- c(INCUMBENT, arm); dd <- D[complete.cases(D[, ..cols])]
  rbindlist(lapply(INCUMBENT, function(o) {
    s <- dd[, .(rho=suppressWarnings(cor(get(arm), get(o), method="spearman", use="complete.obs")), n=.N),
            by=signal_ym][n>=MINN & is.finite(rho)]
    if (!nrow(s)) return(NULL)
    data.table(arm=arm, other=o, mean_rho=mean(s$rho), sd_rho=sd(s$rho), max_month=max(abs(s$rho)), n=nrow(s))
  }))
}))
for (i in seq_len(nrow(SP))) with(SP[i], say("  %-26s vs %-16s 평균 rho %+.4f (sd %.3f · 월최대|rho| %.3f · n=%d)",
                                             arm, other, mean_rho, sd_rho, max_month, n))
RD <- SP[, .(max_abs_rho=max(abs(mean_rho)), worst=other[which.max(abs(mean_rho))]), by=arm]
RD[, redundancy := fifelse(max_abs_rho>=0.9,"REDUNDANT_재탕","DISTINCT")]
for (i in seq_len(nrow(RD))) with(RD[i], say("  ★%-26s 최대|평균rho| %.4f (vs %s) ⇒ %s", arm, max_abs_rho, worst, redundancy))

## =============================================================================
## [6] Placebo (월내 셔플) + lag1 스트레스
## =============================================================================
say("================ [6] Placebo + lag1 ================")
NPL <- 200L
## ★변수명 a_ : 파라미터를 `arm` 으로 두면 data.table `[` 안에서 동명 컬럼과 충돌해
##   RT[arm==get("arm")] 이 전 행 TRUE 가 된다(무음 오답). 이름을 분리한다.
PLB <- rbindlist(lapply(ARMS, function(a_) {
  if (!a_ %in% names(COEFS)) return(NULL)
  cols <- c(INCUMBENT, a_); dd <- D[complete.cases(D[, ..cols])]
  mm <- dd[, .N, by=signal_ym]; dd <- dd[signal_ym %in% mm[N>=MINN, signal_ym]]
  obs <- RT[arm == a_]$t_nw3
  pl <- numeric(NPL); Dp <- copy(dd)
  for (b in seq_len(NPL)) {
    Dp[, PL := sample(get(a_)), by=signal_ym]
    cfp <- fmb_coefs(Dp, c(INCUMBENT,"PL"))
    pl[b] <- nw_t(cfp[term=="PL", est])
  }
  data.table(arm=a_, obs_t=obs, pl_med=median(abs(pl),na.rm=TRUE), pl_p95=quantile(abs(pl),.95,na.rm=TRUE),
             p_two=mean(abs(pl)>=abs(obs), na.rm=TRUE))
}))
for (i in seq_len(nrow(PLB))) with(PLB[i], say(
  "  %-26s placebo |t| 중앙 %.2f · 95%% %.2f · 관측 |t| %.2f ⇒ p = %.4f", arm, pl_med, pl_p95, abs(obs_t), p_two))

LAG <- rbindlist(lapply(ARMS, function(a_) {
  cols <- c(INCUMBENT, a_)
  if (!all(cols %in% names(ALL))) return(NULL)
  S1 <- ALL[, c("Date","Ticker", cols), with=FALSE]
  S1[, signal_ym := ym_shift(format(Date,"%Y-%m"), 1L)]          # t-1 신호를 t 월 신호로
  L <- merge(S1[, c("signal_ym","Ticker",cols), with=FALSE],
             D[, .(signal_ym, Ticker, Ret_1m)], by=c("signal_ym","Ticker"))
  L <- L[complete.cases(L[, ..cols])]
  mmL <- L[, .N, by=signal_ym]; L <- L[signal_ym %in% mmL[N>=MINN, signal_ym]]
  if (uniqueN(L$signal_ym) < 20L) return(NULL)
  cfl <- fmb_coefs(L, cols); e <- cfl[term==a_, est]
  base <- RT[arm == a_]$t_nw3
  data.table(arm=a_, n=length(e), mean=mean(e), t_nw3=nw_t(e), base_t=base, retention=nw_t(e)/base)
}))
for (i in seq_len(nrow(LAG))) with(LAG[i], say(
  "  %-26s lag1(t-1 신호): n=%d · mean %+.6f · t %+.3f (기준 %+.3f) ⇒ 유지율 %.2f", arm, n, mean, t_nw3, base_t, retention))

## =============================================================================
## [7] 검정력 + 부기간 (advisory)
## =============================================================================
say("================ [7] 검정력 ================")
PW <- rbindlist(lapply(ARMS, function(a_) {
  r <- RT[arm == a_]; if (!nrow(r)) return(NULL)
  req <- required_effect(n=r$n_months, t_threshold=2.0, sd_monthly=r$sd_coef, design="full")
  vp  <- verdict_with_power(observed_t=abs(r$t_nw3), observed_monthly=abs(r$mean_coef),
                            n=r$n_months, t_threshold=2.0, sd_monthly=r$sd_coef, design="full")
  data.table(arm=a_, n_months=r$n_months, required_annual_pct=req$required_annual*100,
             observed_annual_pct=r$mean_coef*12*100, verdict=vp$verdict,
             implied_t=if (!is.null(vp$implied_t_threshold)) vp$implied_t_threshold else NA_real_)
}))
for (i in seq_len(nrow(PW))) with(PW[i], say(
  "  %-26s n=%3d · 필요 연 %.2f%% · 관측 연 %+.2f%% · %s (implied_t %.2f)",
  arm, n_months, required_annual_pct, observed_annual_pct, verdict, implied_t))

say("================ [8] 부기간 (advisory 진단, 판정 분할 아님) ================")
ERA <- rbindlist(lapply(ARMS, function(a_) {
  if (!a_ %in% names(COEFS)) return(NULL)
  x <- COEFS[[a_]][term == a_][order(signal_ym)]
  x[, era := fifelse(signal_ym<"2010-01","2001-2009", fifelse(signal_ym<"2017-01","2010-2016","2017-2026"))]
  x[, .(arm=a_, n=.N, mean=mean(est), t_nw3=nw_t(est)), by=era]
}))
for (i in seq_len(nrow(ERA))) with(ERA[i], say("  %-26s %-10s n=%3d · mean %+.6f · t %+.2f", arm, era, n, mean, t_nw3))

## =============================================================================
## [9] 사전등록 판정 + 저장
## =============================================================================
say("================ [9] 판정 ================")
PLB2 <- PLB[, .(arm, placebo_p = p_two)]
V <- merge(merge(RT[, .(arm, kind, n_months, t_nw3, rank_ic, icir, vif_med)],
                 RD[, .(arm, max_abs_rho, redundancy)], by="arm"),
           PLB2, by="arm")
V <- merge(V, LAG[, .(arm, lag1_retention=retention)], by="arm", all.x=TRUE)
V[, material_qualified := (abs(t_nw3) >= 2.0) & (redundancy=="DISTINCT") & (placebo_p < 0.05)]
V[, bonferroni_pass    := abs(t_nw3) >= BONF_T]
for (i in seq_len(nrow(V))) with(V[i], say(
  "  ★%-26s t %+.3f · |rho|max %.3f · placebo p %.4f · lag1 유지 %.2f ⇒ 재료자격 %s / Bonferroni(%.2f) %s",
  arm, t_nw3, max_abs_rho, placebo_p, lag1_retention, material_qualified, BONF_T, bonferroni_pass))

fwrite(RT,  file.path(OUT,"p1_fmb_summary.csv"))
fwrite(SP,  file.path(OUT,"p1_spearman.csv"))
fwrite(PLB, file.path(OUT,"p1_placebo.csv"))
fwrite(LAG, file.path(OUT,"p1_lag1.csv"))
fwrite(PW,  file.path(OUT,"p1_power.csv"))
fwrite(ERA, file.path(OUT,"p1_subperiod.csv"))
fwrite(V,   file.path(OUT,"p1_verdict.csv"))
fwrite(rbindlist(lapply(names(COEFS), function(a) COEFS[[a]][term==a][, arm:=a])),
       file.path(OUT,"p1_fmb_coefs_monthly.csv"))
keep <- c("signal_ym","signal_date","Ticker", INCUMBENT, ARMS, "Ret_1m","Size","K200","KQ150")
write_parquet(D[, intersect(keep, names(D)), with=FALSE], file.path(OUT,"alpha_scores.parquet"))
saveRDS(list(RT=RT, SP=SP, PLB=PLB, LAG=LAG, PW=PW, ERA=ERA, V=V, COEFS=COEFS,
             build_hash=bh, ARMS=ARMS, INCUMBENT=INCUMBENT, BONF_T=BONF_T),
        file.path(OUT,"p1_results.rds"))
say("저장 완료 → %s", OUT)
