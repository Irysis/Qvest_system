## =============================================================================
## FQ-223 (B) v3 최종 — 방법 B + 대안배제 통제 (위반 주입의 역방향)
##
## b2 가 남긴 3개 결함을 정정한다:
##  (1) ★창-정합: plain 283달 vs 수리 282달을 나란히 비교했다 → 전 arm **공통 월집합** 강제.
##  (2) 설계확인 오설정: "04/05 외 달은 불변" 은 틀린 기대였다. 희소 커버리지 종목은
##      6월(6.0%)·1월(0.3%) 등에서도 d_lag < basis 라 **같은 기전으로 오염**돼 있다.
##      ⇒ 기대를 "변화가 04/05 에 집중" 으로 바꾸고 집중도를 정량화한다.
##  (3) ★대안배제 통제 누락: 롤오버-인지 수리는 **창을 짧게 만든다**(4월 63→29일).
##      t 상승이 '롤오버 제거' 때문인지 '창이 짧아져서' 인지 구별되지 않는다.
##      ⇒ **가짜 basis 통제**: 롤오버가 없는 날짜(10/1, 7/1)를 basis 로 삼아 동일 수리를 가한다.
##        가짜에서도 t 가 같이 오르면 효과 = 창 단축 부수효과이지 롤오버 제거가 아니다.
##
## arm: plain / RA(4월탐지) / RA(원탐지기) / RA(04·05 국한) / FAKE(10/1) / FAKE(7/1)
## metric_type: canonical_screen_diag. 자본 주장 없음.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
SRC  <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
CD   <- file.path(ROOT, ".cache/consensus")
say <- function(fmt, ...) { cat(sprintf(paste0("[b3] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260810L)
TOL <- 1e-12; LAG <- 63L; T_DB <- 2.5552525842524; MINN <- 30L

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}
fmb_coefs <- function(dat, xs, ycol = "Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse = " + ")))
  dat[, { fit <- tryCatch(lm(f, data = .SD), error = function(e) NULL)
    if (is.null(fit)) .(term=character(0), est=numeric(0))
    else { cf <- coef(fit); .(term = names(cf), est = as.numeric(cf)) } },
    by = signal_ym, .SDcols = c(ycol, xs)]
}
z_fdb <- function(x) {
  ok <- is.finite(x); if (sum(ok) < 20L) return(rep(NA_real_, length(x)))
  q <- quantile(x[ok], c(0.01,0.99), na.rm=TRUE, names=FALSE)
  w <- pmin(pmax(x, q[1]), q[2]); mu <- mean(w, na.rm=TRUE); s <- sd(w, na.rm=TRUE)
  if (!is.finite(s) || s < 1e-12) return(rep(NA_real_, length(x)))
  z <- pmin(pmax((w-mu)/s, -3), 3); s2 <- sd(z, na.rm=TRUE)
  if (is.finite(s2) && s2 > 1e-12) z/s2 else z
}

## ---------------------------------------------------------------- [0] 입력
say("================ [0] 입력 ================")
D4 <- as.data.table(read_parquet(file.path(SRC,"alpha_scores.parquet"))); D4[, Date := as.Date(Date)]
sigs <- sort(unique(D4$Date)); K <- length(sigs)
say("판정 패널 %d행 · %d개월 · %s ~ %s", nrow(D4), K, min(sigs), max(sigs))
E <- as.data.table(read_parquet(file.path(CD,"revenue_fy1.parquet")))
E[, Date := as.Date(Date)]; E <- E[!is.na(revenue_fy1), .(Ticker, Date, value = revenue_fy1)]
setorderv(E, c("Ticker","Date"))
E[, prev_v := shift(value), by = Ticker]; E[, chg := !is.na(prev_v) & abs(value-prev_v) > TOL]
lv <- E[, .(n_live=.N), by=Date]; cg <- E[chg==TRUE, .(n_chg=.N), by=Date]
bd <- merge(lv,cg,by="Date",all.x=TRUE)[is.na(n_chg), n_chg:=0L][, frac := n_chg/n_live]
ROLL_raw <- sort(bd[frac>=0.50 & n_live>=50L, Date]); ROLL_apr <- ROLL_raw[format(ROLL_raw,"%m")=="04"]
if (!length(ROLL_apr)) stop("[b3] 4월 동시변경일 0건 — 정지 신호")
say("동시변경일 %d (4월 %d)", length(ROLL_raw), length(ROLL_apr))

E[, obs_date := Date]; setkeyv(E, c("Ticker","Date")); TK <- unique(E$Ticker)
mkQ <- function(d) { q <- CJ(Ticker=TK, k=seq_len(K), sorted=FALSE); q[, Date := d[k]]
  setkeyv(q, c("Ticker","Date")); q[] }
pb <- function(d) { r <- E[mkQ(d), roll=TRUE,  on=.(Ticker,Date)]; r[!is.na(value), .(Ticker,k,v=value,dd=obs_date)] }
pf <- function(d) { r <- E[mkQ(d), roll=-Inf, on=.(Ticker,Date)]; r[!is.na(value), .(Ticker,k,v=value,dd=obs_date)] }
NOW <- pb(sigs); setnames(NOW, c("v","dd"), c("v_now","d_now"))
LG  <- pb(sigs-LAG); setnames(LG, c("v","dd"), c("v_lag","d_lag"))
KMAP <- data.table(k=seq_len(K), Date=sigs)
JP <- merge(D4[, .(Date,Ticker,signal_ym)], merge(KMAP, merge(NOW,LG,by=c("Ticker","k")), by="k"),
            by=c("Date","Ticker"))
JP[, mon := format(Date,"%m")]
say("판정 패널 재구성 %d / %d", nrow(JP), nrow(D4))

## ------------------------------------------------- [1] arm 별 raw 구성
say("================ [1] arm 구성 ================")
## 임의 basis 벡터(연도별 기준일)를 받아 외과적 수리 raw 를 만든다
make_raw <- function(basis_dates, restrict_mon = NULL, lab) {
  bas <- as.Date(vapply(sigs, function(s){ kk <- basis_dates[basis_dates <= s]
    if(!length(kk)) NA_real_ else as.numeric(max(kk)) },0), origin="1970-01-01")
  X <- copy(JP); X[, b := bas[k]]
  X[, contam := !is.na(b) & d_now >= b & d_lag < b]
  if (!is.null(restrict_mon)) X[!(mon %in% restrict_mon), contam := FALSE]
  FW <- pf(bas); setnames(FW, c("v","dd"), c("v_fix","d_fix"))
  X <- merge(X, FW, by=c("Ticker","k"), all.x=TRUE)
  X[, fixable := contam & !is.na(v_fix) & abs(v_fix) > 1e-6 & !is.na(d_fix) & d_fix <= Date]
  X[, v_use := v_lag][fixable==TRUE, v_use := v_fix]
  X[, d_use := d_lag][fixable==TRUE, d_use := d_fix]
  X[, raw := fifelse(abs(v_use) > 1e-6, (v_now - v_use)/abs(v_use), NA_real_)]
  list(lab=lab, X=X, n_contam=sum(X$contam), n_fix=sum(X$fixable),
       frac_contam=mean(X$contam), by_mon=X[, .(n=.N, contam=mean(contam)), by=mon][order(mon)])
}
X_plain <- copy(JP)[, raw := fifelse(abs(v_lag)>1e-6, (v_now-v_lag)/abs(v_lag), NA_real_)]
yrs <- sort(unique(as.integer(format(sigs,"%Y"))))
FAKE_OCT <- as.Date(sprintf("%d-10-01", c(yrs[1]-1L, yrs)))
FAKE_JUL <- as.Date(sprintf("%d-07-01", c(yrs[1]-1L, yrs)))
A_apr  <- make_raw(ROLL_apr, NULL, "RA_4월탐지")
A_raw  <- make_raw(ROLL_raw, NULL, "RA_원탐지기")
A_0405 <- make_raw(ROLL_apr, c("04","05"), "RA_04·05국한")
A_foct <- make_raw(FAKE_OCT, NULL, "FAKE_10/1(통제)")
A_fjul <- make_raw(FAKE_JUL, NULL, "FAKE_7/1(통제)")
for (a in list(A_apr, A_raw, A_0405, A_foct, A_fjul))
  say("  %-16s 오염 %6d (%.4f) · 수리 %6d · 04/05 집중도 %.3f",
      a$lab, a$n_contam, a$frac_contam, a$n_fix,
      a$X[mon %in% c("04","05"), sum(contam)] / max(1L, a$n_contam))

## ------------------------------------------------- [2] 공통 월집합 + 적합
say("================ [2] 공통 월집합 강제 후 적합 ================")
SGNsrc <- merge(D4[, .(Date,Ticker,zdb=M26_Revenue_Mom)], X_plain[, .(Date,Ticker,raw)], by=c("Date","Ticker"))
sg <- SGNsrc[is.finite(raw), .(rho=suppressWarnings(cor(raw,zdb,method="spearman",use="complete.obs"))), by=Date]
say("G1: 월별 |rho| 중앙 %.4f · 최소 %.4f · 음부호 %d달", median(abs(sg$rho)), min(abs(sg$rho)), sum(sg$rho<0))
if (median(abs(sg$rho)) < 0.95) stop("[b3] G1 FAIL")
SGN <- sg[, .(Date, sgn=sign(rho))]
base_cols <- D4[, .(Date,Ticker,signal_ym,C01_SUE,C02_EPS_Chg_1m,C04_ESBR,Ret_1m)]

prep <- function(X) {
  A <- X[is.finite(raw), .(Date,Ticker,raw)]
  A <- merge(A, SGN, by="Date")[, zm := z_fdb(raw)*sgn[1], by=Date]
  DD <- merge(base_cols, A[, .(Date,Ticker,zm)], by=c("Date","Ticker"))
  DD <- DD[complete.cases(DD[, .(C01_SUE,C02_EPS_Chg_1m,C04_ESBR,zm,Ret_1m)])]
  mm <- DD[, .N, by=signal_ym]
  list(DD=DD, ok_ym=mm[N>=MINN, signal_ym])
}
ARMS <- list(list("plain(재구성)", X_plain), list(A_apr$lab, A_apr$X), list(A_raw$lab, A_raw$X),
             list(A_0405$lab, A_0405$X), list(A_foct$lab, A_foct$X), list(A_fjul$lab, A_fjul$X))
PREP <- lapply(ARMS, function(z) prep(z[[2]]))
common_ym <- Reduce(intersect, lapply(PREP, function(p) p$ok_ym))
say("★공통 월집합 %d개월 (arm 별 %s) — 전 arm 동일 창에서만 비교",
    length(common_ym), paste(vapply(PREP, function(p) length(p$ok_ym), 0L), collapse="/"))

fit_one <- function(p, lab) {
  DD <- p$DD[signal_ym %in% common_ym]
  s <- fmb_coefs(DD, c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","zm"))[term=="zm"][order(signal_ym)]
  s[, mon := substr(signal_ym,6,7)]
  list(lab=lab, n=nrow(s), n_obs=nrow(DD), t=nw_t(s$est), mean=mean(s$est), sd=sd(s$est),
       apr=mean(s[mon=="04",est]), may=mean(s[mon=="05",est]),
       oth=mean(s[!(mon %in% c("04","05")),est]), series=s)
}
FITS <- mapply(function(p, a) fit_one(p, a[[1]]), PREP, ARMS, SIMPLIFY=FALSE)
t_plain <- FITS[[1]]$t
tab <- rbindlist(lapply(FITS, function(r) data.table(arm=r$lab, n_months=r$n, n_obs=r$n_obs,
  t_nw3=r$t, mean=r$mean, sd=r$sd, apr=r$apr, may=r$may, oth=r$oth)))
tab[, delta_t := t_nw3 - t_plain][, t_on_db := T_DB + delta_t]
say("--- 공통 %d개월 기준 z(M26) FMB NW(3) t ---", length(common_ym))
for (i in seq_len(nrow(tab))) with(tab[i], say(
  "  %-16s %6d obs · ★t %+.4f (Δ %+.4f · DB이식 %+.4f) · 4월 %+.6f · 5월 %+.6f · 평월 %+.6f",
  arm, n_obs, t_nw3, delta_t, t_on_db, apr, may, oth))

## ------------------------------------------------- [3] 대안배제 판정
say("================ [3] 대안배제 통제 판정 ================")
d_apr  <- tab[arm==A_apr$lab,  delta_t]; d_raw <- tab[arm==A_raw$lab, delta_t]
d_0405 <- tab[arm==A_0405$lab, delta_t]
d_oct  <- tab[arm==A_foct$lab, delta_t]; d_jul <- tab[arm==A_fjul$lab, delta_t]
say("진짜 basis Δt: 4월탐지 %+.4f · 원탐지기 %+.4f · 04·05국한 %+.4f", d_apr, d_raw, d_0405)
say("가짜 basis Δt: 10/1 %+.4f · 7/1 %+.4f  (창 단축 부수효과의 크기)", d_oct, d_jul)
fake_max <- max(abs(c(d_oct, d_jul)))
say("★판정: |진짜 Δt| %.4f vs |가짜 최대| %.4f ⇒ %s", abs(d_apr), fake_max,
    if (abs(d_apr) > 2*fake_max) "롤오버 고유 효과 (가짜의 2배 초과)"
    else if (abs(d_apr) > fake_max) "롤오버 고유 우세하나 여유 작음 — 신중"
    else "★창-단축 부수효과와 구별 불가 — 롤오버 귀속 불가")

## 월별 변화 집중도 — 04/05 에 집중되는가
chg <- merge(FITS[[1]]$series[, .(signal_ym, mon, e_p=est)],
             FITS[[2]]$series[, .(signal_ym, e_f=est)], by="signal_ym")
chg[, d := e_f - e_p]
conc <- chg[, .(n=.N, mean_abs_d=mean(abs(d)), sum_abs_d=sum(abs(d))), by=mon][order(mon)]
conc[, share_of_total := sum_abs_d/sum(conc$sum_abs_d)]
say("--- 계수 변화량의 월별 집중도 (RA_4월탐지 − plain) ---")
for (i in seq_len(nrow(conc))) with(conc[i], say("  %s월 n=%2d · 평균|Δ| %.6f · 총|Δ| 비중 %.3f", mon, n, mean_abs_d, share_of_total))
say("★04·05 두 달이 총 변화량의 %.3f 차지 (월수 비중 %.3f)",
    conc[mon %in% c("04","05"), sum(share_of_total)], conc[mon %in% c("04","05"), sum(n)]/sum(conc$n))

## ------------------------------------------------- [4] 저장
fwrite(tab,  file.path(OUT, "b3_arm_summary_common_window.csv"))
fwrite(conc, file.path(OUT, "b3_change_concentration.csv"))
fwrite(rbindlist(lapply(FITS, function(r) r$series[, arm := r$lab])), file.path(OUT, "b3_coefs_by_arm.csv"))
fwrite(rbindlist(lapply(list(A_apr,A_raw,A_0405,A_foct,A_fjul), function(a) a$by_mon[, lab := a$lab])),
       file.path(OUT, "b3_contam_by_month.csv"))
saveRDS(list(tab=tab, conc=conc, common_ym=common_ym, d_apr=d_apr, d_raw=d_raw, d_0405=d_0405,
             d_oct=d_oct, d_jul=d_jul, sg=sg), file.path(OUT, "b3_results.rds"))
say("저장 완료 → %s", OUT)
say("★★[B 최종] 공통 %d개월 · t_plain %+.4f → RA %+.4f (Δ %+.4f) · 가짜통제 최대 |Δ| %.4f · DB이식 t_B %+.4f",
    length(common_ym), t_plain, tab[arm==A_apr$lab, t_nw3], d_apr, fake_max, T_DB + d_apr)
