# =============================================================================
# run_fq122_prod.R — FQ-122 Part 2
#   (1) §7b production 실코드 base arm (W3 tilt20 parity-gated · W4 EW20)
#   (2) 가드: 항등식 · 플라시보 · lag1 · 검정력 라벨 · 국면 상호작용
#   (3) 반증 관측 F2(주체=개인 순매수) · F3(β-drag)
#   (4) parity: W1 base vs WT-009 저장 M01_PATHQ canonical
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/run_fq122_prod.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest); library(lubridate)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[fq122p] ", fmt, "\n"), ...))
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]), error=function(e) NA_real_) }
nw_ci <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(c(NA,NA))
  fit <- lm(x ~ 1); se <- tryCatch(sqrt(sandwich::NeweyWest(fit, lag=lag, prewhite=FALSE)[1,1]),
    error=function(e) NA_real_); mean(x) + c(-1.96,1.96)*se }
ir_v <- function(a) mean(a)/sd(a)*sqrt(12)
source("02_Infrastructure/contracts/required_effect_size.R")

P1RDS <- readRDS(file.path(OUT, "fq122_part1.rds"))

# =============================================================================
# 0. 입력 (production 실코드 경로 — WT-022 검증 코드 재사용)
# =============================================================================
IN <- c(alpha = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
        raw   = ".cache/rawdata.parquet",
        bench = ".cache/benchmark.parquet",
        prod_pr = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
        tuned = "stage_artifacts/WT_D20260802_009/tuned_panel.parquet")
say("입력 vintage:"); for (n in names(IN)) say("  %-8s %s | mtime %s", n, IN[n], as.character(file.mtime(IN[n])))

alpha_scores <- as.data.table(read_parquet(IN["alpha"])); alpha_scores[, Date := as.Date(Date)]
raw <- as.data.table(read_parquet(IN["raw"], col_select=c("Date","Ticker","Close","Vol","Ret","Size")))
raw[, Date := as.Date(Date)]; raw[, TradingAmt := Close*Vol]; setkey(raw, Date, Ticker)
bm <- as.data.table(read_parquet(IN["bench"])); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
prod_pr <- fread(IN["prod_pr"]); prod_pr[, date := as.Date(date)]; setorder(prod_pr, date)
TUNED <- as.data.table(read_parquet(IN["tuned"])); TUNED[, Date := as.Date(Date)]
say("INPUT prod alpha rows=%d MONTHLY %d월 | prod_pr %d행 %s~%s",
    nrow(alpha_scores), uniqueN(alpha_scores$Date), nrow(prod_pr),
    as.character(min(prod_pr$date)), as.character(max(prod_pr$date)))

# ── Iter31 §5 VERBATIM 헬퍼 ──────────────────────────────────────────────────
normalize_long_only <- function(w, lb=0, ub=0.20, target_sum=1, max_iter=50) {
  w[!is.finite(w)] <- 0; w[w<lb] <- lb; w[w>ub] <- ub
  s <- sum(w); if (s <= 1e-12) return(rep(target_sum/length(w), length(w)))
  w <- w*(target_sum/s)
  for (k in seq_len(max_iter)) { over <- w > ub+1e-12; if(!any(over)) break
    excess <- sum(w[over]-ub); w[over] <- ub; free <- which(!over & w > lb+1e-12)
    if(!length(free)) { w <- w*(target_sum/sum(w)); break }
    w[free] <- w[free] + excess*(w[free]/sum(w[free])) }
  w/sum(w)*target_sum }
linear_tilt_qd <- function(a, lambda=1.0, lb=0, ub=0.20) {
  N <- length(a); if (N<=1) return(rep(1,N))
  r <- rank(a, ties.method="average"); centered <- (r-mean(r))/(N-1)
  wr <- pmax(1+lambda*2*centered, 1e-6); normalize_long_only(wr/sum(wr), lb, ub, 1) }
linear_tilt_to_penalty_qd <- function(a, lambda=1.5, w_prev=NULL, phi=3.0, lb=0, ub=0.20) {
  wt <- linear_tilt_qd(a, lambda, lb, ub); names(wt) <- names(a)
  if (is.null(w_prev) || phi<=0) return(wt)
  wp <- setNames(numeric(length(wt)), names(wt)); cm <- intersect(names(wt), names(w_prev))
  wp[cm] <- w_prev[cm]; dropped <- 1-sum(wp); if (dropped>0) wp <- wp + dropped*wt
  if (sum(wp)>0) wp <- wp/sum(wp); bl <- phi/(1+phi)
  normalize_long_only(bl*wp + (1-bl)*wt, lb, ub, 1) }
LIQ <- 2e8; CBPS <- 15; MAXN <- 20L; MINN <- 15L; UB <- 0.20; LAM <- 1.5; PHI <- 3

sig_dates <- sort(unique(alpha_scores[!is.na(score_eff), Date]))
raw_dates <- sort(unique(raw$Date)); n_iter <- length(sig_dates)-1L
cache <- vector("list", n_iter)
for (i in seq_len(n_iter)) {
  sl <- sig_dates[i]; nx <- sig_dates[i+1L]
  is_ <- findInterval(sl-1, raw_dates)+1L; if (is_ > length(raw_dates)) next
  sd_ <- raw_dates[is_]; ie <- findInterval(nx-1, raw_dates)+1L
  ed <- if (ie > length(raw_dates)) max(raw_dates) else raw_dates[ie]
  pt <- alpha_scores[Date==sl & !is.na(score_eff)]; if (!nrow(pt)) next
  liq <- raw[Date >= sd_-30L & Date < sd_, .(A=mean(TradingAmt,na.rm=TRUE)), by=Ticker][A>=LIQ, Ticker]
  sr <- raw[Date > sd_ & Date <= ed, .(stock_ret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
  cache[[i]] <- list(sig_label=sl, start_d=sd_, end_d=ed, panel_t=pt, liquid=liq, stock_rets=sr)
}
say("월별 캐시 %d/%d", sum(!sapply(cache,is.null)), n_iter)

# ── 신호일 매핑: tuned 월말 d0 → prod sig_label 월 = month(d0)+1 (C5) ────────
TW <- dcast(TUNED[Factor_Name %in% c("D03_EWMA","Q01_EB")], Date+Ticker ~ Factor_Name, value.var="score")
TW[, sig_ym := format(as.Date(format(Date, "%Y-%m-01")) %m+% months(1), "%Y-%m")]
TW[, sig_ym_lag1 := format(as.Date(format(Date, "%Y-%m-01")) %m+% months(2), "%Y-%m")]
say("매핑 확인: tuned 월 %d → sig_ym 고유 %d (중복 0 여부 %s) | prod sig 월 %d · 교집합 %d",
    uniqueN(TW$Date), uniqueN(TW$sig_ym), uniqueN(TW$Date)==uniqueN(TW$sig_ym),
    length(sig_dates), length(intersect(unique(TW$sig_ym), format(sig_dates, "%Y-%m"))))

build_excl <- function(fac, q=0.20, lag1=FALSE) {
  yc <- if (lag1) "sig_ym_lag1" else "sig_ym"
  e <- new.env(parent=emptyenv())
  for (i in seq_len(n_iter)) { cc <- cache[[i]]; if (is.null(cc)) next
    ym <- format(cc$sig_label, "%Y-%m")
    f5 <- TW[get(yc)==ym & is.finite(get(fac)), .(Ticker, v=get(fac))]
    if (!nrow(f5)) next
    cand <- merge(cc$panel_t[, .(Ticker)], f5, by="Ticker", all.x=TRUE)
    v <- cand$v[is.finite(cand$v)]; if (length(v) < 30L) next
    thr <- quantile(v, q, type=7, names=FALSE)
    ex <- cand[is.finite(v) & v <= thr, Ticker]
    if (length(ex)) assign(as.character(cc$sig_label), ex, envir=e) }
  e }

run_prod <- function(excl=NULL, ew=FALSE) {
  rows <- vector("list", n_iter); wprev <- NULL
  for (i in seq_len(n_iter)) {
    cc <- cache[[i]]; if (is.null(cc)) next
    pt <- copy(cc$panel_t); reg <- pt$regime_state[1L]; fired <- FALSE
    if (!is.null(excl)) { k <- as.character(cc$sig_label)
      if (exists(k, envir=excl, inherits=FALSE)) { n0 <- nrow(pt)
        pt <- pt[!Ticker %in% get(k, envir=excl)]; fired <- nrow(pt) < n0 } }
    setorder(pt, -score_eff); ne <- nrow(pt); nt <- min(MAXN, ne)
    if (nt < MINN && ne >= MINN) nt <- MINN
    if (nt < 5L) next
    pk <- pt[seq_len(nt)]; a <- setNames(pk$score_eff, pk$Ticker)
    tl <- intersect(names(a), cc$liquid); if (length(tl) < 5L) tl <- names(a)
    a <- a[tl]; if (length(a) < 5L) next
    ubu <- if (identical(reg,"CRISIS")) min(UB,0.10) else UB
    if (ew) w <- setNames(rep(1/length(a), length(a)), names(a))
    else { w <- tryCatch(linear_tilt_to_penalty_qd(a, LAM, wprev, PHI, 0, ubu),
             error=function(e) linear_tilt_qd(a, LAM, 0, ubu))
           names(w) <- names(a); w <- normalize_long_only(w, 0, ubu, 1) }
    if (is.null(cc$stock_rets) || !nrow(cc$stock_rets)) next
    mr <- merge(data.table(ticker=names(w), wv=as.numeric(w)), cc$stock_rets,
                by.x="ticker", by.y="Ticker", all.x=TRUE)
    mr[is.na(stock_ret), stock_ret := 0]
    gross <- sum(mr$wv*mr$stock_ret)
    to <- if (is.null(wprev) || !length(wprev)) 1.0 else {
      an <- union(names(w), names(wprev)); w1 <- setNames(rep(0,length(an)),an); w0 <- w1
      w1[names(w)] <- w; w0[names(wprev)] <- wprev; sum(abs(w1-w0))/2 }
    rows[[i]] <- data.table(period_start=cc$start_d, period_end=cc$end_d,
      ret_net=gross-(CBPS/1e4)*to*2, ret_gross=gross, turnover=to,
      regime=reg, fired=fired, n_held=nrow(mr))
    wprev <- setNames(as.numeric(w), names(w))
  }
  out <- rbindlist(rows[!sapply(rows,is.null)]); setorder(out, period_end); out
}

# ── PARITY GATE A ────────────────────────────────────────────────────────────
say("── W3 PARITY GATE A (production 03_period_returns 재현) ──")
w3_base <- run_prod(NULL, ew=FALSE)
pp <- merge(w3_base[, .(date=period_end, mine=ret_net, to_mine=turnover)],
            prod_pr[, .(date, ret_net, turnover)], by="date", all=TRUE)
dv <- pp[, max(abs(mine-ret_net), na.rm=TRUE)]
say("  n %d vs %d | max|Δret_net| %.3e | max|ΔTO| %.3e",
    nrow(w3_base), nrow(prod_pr), dv, pp[, max(abs(to_mine-turnover), na.rm=TRUE)])
gateA <- (nrow(w3_base)==nrow(prod_pr)) && is.finite(dv) && dv <= 1e-8
if (!gateA) { print(head(pp[abs(mine-ret_net) > 1e-8], 8))
  stop("[fq122p] PARITY GATE A FAIL — production 재현 불일치 (사전등록 STOP)") }
say("  GATE A PASS — production_parity_verified")

# 벤치 월윈도우
bmx <- bm[, .(Date, BM_Ret)]
mk_bmw <- function(anchors) {
  out <- rep(NA_real_, length(anchors))
  for (i in 2:length(anchors)) {
    seg <- bmx[Date > anchors[i-1] & Date <= anchors[i], BM_Ret]
    if (length(seg)) out[i] <- prod(1+seg)-1 }
  data.table(period_end=anchors, bmw=out) }
BW <- mk_bmw(w3_base$period_end)

paired_prod <- function(b, f, label) {
  D <- merge(merge(b[, .(period_end, rb=ret_net, tob=turnover)],
                   f[, .(period_end, rf=ret_net, tof=turnover)], by="period_end"),
             BW, by="period_end")[is.finite(bmw)]
  ab <- D$rb-D$bmw; af <- D$rf-D$bmw; d <- af-ab; ci <- nw_ci(d)
  data.table(arm=label, n=nrow(D), base_port_t=nw_t(ab), filt_port_t=nw_t(af),
    base_ir=ir_v(ab), filt_ir=ir_v(af), delta_ir=ir_v(af)-ir_v(ab),
    d_ann_pct=100*12*mean(d), paired_t=nw_t(d),
    ci_lo_ann_pct=100*12*ci[1], ci_hi_ann_pct=100*12*ci[2], sd_d=sd(d),
    base_to_ann=100*mean(D$tob)*12, filt_to_ann=100*mean(D$tof)*12) }

say("── W3/W4 production 실코드 arm (q=0.20 고정) ──")
prod_rows <- list()
for (fac in c("D03_EWMA","Q01_EB")) {
  e <- build_excl(fac, 0.20)
  say("  %s 배제맵 %d개월", fac, length(ls(e)))
  prod_rows[[paste0("W3_",fac)]] <- paired_prod(w3_base, run_prod(e, FALSE), paste0("W3_prod_tilt20_", fac))
}
w4_base <- run_prod(NULL, ew=TRUE)
for (fac in c("D03_EWMA","Q01_EB")) {
  e <- build_excl(fac, 0.20)
  prod_rows[[paste0("W4_",fac)]] <- paired_prod(w4_base, run_prod(e, TRUE), paste0("W4_prod_ew20_", fac))
}
# lag1 스트레스 (W3)
for (fac in c("D03_EWMA","Q01_EB")) {
  e <- build_excl(fac, 0.20, lag1=TRUE)
  prod_rows[[paste0("W3lag1_",fac)]] <- paired_prod(w3_base, run_prod(e, FALSE), paste0("W3_lag1_", fac))
}
PROD <- rbindlist(prod_rows)
PROD[, sign_agree := sign(delta_ir)==sign(paired_t)]
say("── production 실코드 결과 ──")
print(PROD[, .(arm, n, delta_ir=round(delta_ir,4), d_ann_pct=round(d_ann_pct,3),
               paired_t=round(paired_t,3), sign_agree,
               ci=sprintf("[%+.2f, %+.2f]", ci_lo_ann_pct, ci_hi_ann_pct),
               base_to=round(base_to_ann), filt_to=round(filt_to_ann))])

# =============================================================================
# 2. 검정력 라벨 (모든 셀)
# =============================================================================
RECON <- P1RDS$RECON
lab <- function(t, m, n, sdv) verdict_with_power(observed_t=t, observed_monthly=m,
                                                 n=n, sd_monthly=sdv, design="full")$verdict
RECON[, power_verdict := mapply(lab, paired_t, d_ann_pct/1200, n, sd_d)]
PROD[,  power_verdict := mapply(lab, paired_t, d_ann_pct/1200, n, sd_d)]
say("검정력 라벨(재구성):"); print(RECON[, .(weighting, factor, q, d_ann_pct=round(d_ann_pct,2), paired_t=round(paired_t,2), power_verdict)])
say("검정력 라벨(production):"); print(PROD[, .(arm, d_ann_pct=round(d_ann_pct,2), paired_t=round(paired_t,2), power_verdict)])

# =============================================================================
# 3. 플라시보 (production W3, 무작위 제외 동월 동개수 8 seed)
# =============================================================================
say("── 플라시보 (W3, 무작위 제외 8 seed) ──")
set.seed(20260808L); plc <- list()
for (fac in c("D03_EWMA","Q01_EB")) {
  e <- build_excl(fac, 0.20)
  kmap <- sapply(ls(e), function(k) length(get(k, envir=e)))
  reals <- PROD[arm==paste0("W3_prod_tilt20_", fac), d_ann_pct]
  ds <- numeric(0)
  for (s in 1:8) {
    er <- new.env(parent=emptyenv())
    for (i in seq_len(n_iter)) { cc <- cache[[i]]; if (is.null(cc)) next
      k <- as.character(cc$sig_label); kk <- kmap[k]
      if (is.na(kk) || kk < 1) next
      pool <- cc$panel_t$Ticker
      if (length(pool) > kk) assign(k, sample(pool, kk), envir=er) }
    pr_ <- paired_prod(w3_base, run_prod(er, FALSE), "placebo")
    ds <- c(ds, pr_$d_ann_pct)
  }
  plc[[fac]] <- data.table(factor=fac, real_d_ann_pct=reals,
    placebo_mean=mean(ds), placebo_sd=sd(ds), placebo_min=min(ds), placebo_max=max(ds),
    outside_range = reals < min(ds) | reals > max(ds))
}
PLC <- rbindlist(plc); print(PLC)

# =============================================================================
# 4. F2 주체 (개인 순매수) · F3 β-drag
# =============================================================================
say("── F2 주체: 개인 순매수 집중 (연속 조건화 회귀) ──")
F2 <- tryCatch({
  IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet"))
  say("  investor_individual cols=[%s] rows=%d", paste(head(names(IND),10),collapse=","), nrow(IND))
  dcol <- names(IND)[tolower(names(IND)) %in% c("date")][1]
  tcol <- names(IND)[tolower(names(IND)) %in% c("ticker","code")][1]
  ncol <- names(IND)[grepl("net|netbuy|net_buy|value|amt", tolower(names(IND)))][1]
  say("  사용 컬럼: date=%s ticker=%s net=%s", dcol, tcol, ncol)
  IND <- IND[, .(Date=as.Date(get(dcol)), Ticker=get(tcol), nb=as.numeric(get(ncol)))]
  IND[, ym := format(Date, "%Y-%m")]
  M <- IND[, .(nb_m=sum(nb, na.rm=TRUE)), by=.(ym, Ticker)]
  EL <- P1RDS$RECON  # placeholder (실제 패널은 아래 재구성)
  TW2 <- dcast(TUNED[Factor_Name %in% c("D03_EWMA","Q01_EB")], Date+Ticker ~ Factor_Name, value.var="score")
  TW2[, ym := format(Date, "%Y-%m")]
  SZ <- raw[, .(Date, Ticker, Size)]
  SZm <- SZ[, .SD[which.max(Date)], by=.(ym=format(Date,"%Y-%m"), Ticker), .SDcols=c("Size")]
  J <- merge(TW2, M, by=c("ym","Ticker"))
  J <- merge(J, SZm[, .(ym, Ticker, Size)], by=c("ym","Ticker"))
  J <- J[is.finite(Size) & Size > 0][, nbs := nb_m/Size]
  out <- list()
  for (f in c("D03_EWMA","Q01_EB")) {
    D <- J[is.finite(get(f)) & is.finite(nbs)]
    D[, `:=`(xz={s<-sd(get(f)); if(!is.finite(s)||s<=0) NA_real_ else (get(f)-mean(get(f)))/s},
             yz={s<-sd(nbs); if(!is.finite(s)||s<=0) NA_real_ else (nbs-mean(nbs))/s}), by=ym]
    sl <- D[is.finite(xz)&is.finite(yz), {if(.N<20L) .(b=NA_real_) else .(b=as.numeric(coef(lm(yz~xz))[2]))}, by=ym]
    b <- sl$b[is.finite(sl$b)]
    out[[f]] <- data.table(factor=f, n_months=length(b), slope=mean(b), t_nw=nw_t(b),
      interpretation=sprintf("필터 z 1sd 상승 시 개인 순매수(시총정규화) z %+.4f", mean(b)))
  }
  rbindlist(out)
}, error=function(e) { say("  F2 실패: %s", conditionMessage(e)); NULL })
if (!is.null(F2)) print(F2)

say("── F3 β-drag: 분위별 trailing-60m β ──")
MR <- raw[, .(mret = prod(1+Ret, na.rm=TRUE)-1), by=.(ym=format(Date,"%Y-%m"), Ticker)]
BMm <- bm[, .(bmret = prod(1+BM_Ret)-1), by=.(ym=format(Date,"%Y-%m"))]
MR <- merge(MR, BMm, by="ym"); setorder(MR, Ticker, ym)
MR[, idx := .GRP, by=ym]
F3 <- tryCatch({
  TW3 <- dcast(TUNED[Factor_Name %in% c("D03_EWMA","Q01_EB")], Date+Ticker ~ Factor_Name, value.var="score")
  TW3[, ym := format(Date, "%Y-%m")]
  # trailing 60m β (신호월 포함 과거만 — PIT)
  setkey(MR, Ticker, idx)
  bcalc <- MR[, {
    n <- .N; bb <- rep(NA_real_, n)
    if (n >= 24L) for (j in 24:n) {
      lo <- max(1L, j-59L); x <- bmret[lo:j]; y <- mret[lo:j]
      ok <- is.finite(x)&is.finite(y)
      if (sum(ok) >= 24L && sd(x[ok])>0) bb[j] <- cov(x[ok],y[ok])/var(x[ok]) }
    .(ym=ym, beta60=bb) }, by=Ticker]
  J3 <- merge(TW3, bcalc, by=c("ym","Ticker"))
  out <- list()
  for (f in c("D03_EWMA","Q01_EB")) {
    D <- J3[is.finite(get(f)) & is.finite(beta60)]
    D[, qq := cut(frank(get(f))/.N, breaks=seq(0,1,0.2), labels=paste0("Q",1:5), include.lowest=TRUE), by=ym]
    s <- D[, .(beta_med=median(beta60), n=.N), by=qq][order(qq)]
    s[, `:=`(factor=f, univ_median=D[, median(beta60)])]
    out[[f]] <- s }
  rbindlist(out)
}, error=function(e) { say("  F3 실패: %s", conditionMessage(e)); NULL })
if (!is.null(F3)) print(F3)

# =============================================================================
# 5. 국면 상호작용 (연속 — advisory)
# =============================================================================
say("── 국면 상호작용 (연속, advisory) ──")
REG <- tryCatch({
  bmm <- bm[, .(bmret = prod(1+BM_Ret)-1), by=.(ym=format(Date,"%Y-%m"))]
  setorder(bmm, ym); bmm[, trail12 := frollapply(bmret, 12, function(z) prod(1+z)-1, align="right")]
  bmm[, trail12_lag := shift(trail12, 1)]
  out <- list()
  for (fac in c("D03_EWMA","Q01_EB")) {
    e <- build_excl(fac, 0.20)
    f <- run_prod(e, FALSE)
    D <- merge(merge(w3_base[, .(period_end, rb=ret_net)], f[, .(period_end, rf=ret_net)], by="period_end"),
               BW, by="period_end")[is.finite(bmw)]
    D[, ym := format(period_end %m-% months(1), "%Y-%m")]
    D <- merge(D, bmm[, .(ym, trail12_lag)], by="ym")
    D <- D[is.finite(trail12_lag)]
    D[, d := (rf-bmw)-(rb-bmw)]
    fit <- lm(d ~ trail12_lag, data=D)
    ct <- lmtest::coeftest(fit, vcov.=sandwich::NeweyWest(fit, lag=3, prewhite=FALSE))
    out[[fac]] <- data.table(factor=fac, n=nrow(D),
      interact_coef=ct[2,1], interact_t=ct[2,3],
      note="paired d ~ 벤치 trailing 12m (연속 조건화, 분할 아님). ADVISORY")
  }
  rbindlist(out)
}, error=function(e) { say("  국면 실패: %s", conditionMessage(e)); NULL })
if (!is.null(REG)) print(REG)

saveRDS(list(PROD=PROD, PLC=PLC, F2=F2, F3=F3, REG=REG, RECON=RECON, P1=P1RDS$P1,
             gateA_max_dev=dv),
        file.path(OUT, "fq122_part2.rds"))
say("저장: fq122_part2.rds — 완료")
