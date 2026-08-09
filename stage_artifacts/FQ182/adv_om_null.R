## FQ-182 적대검증 — STEP 4:
##  D1 2026-07 구간 안정성 (백업 대조) — 데이터 인공물 혐의
##  D2 공통창(2002-01~2026-06) 전 계열 동일조건 재측정 — 창 교락 제거한 교차시장 비교
##  D3 대칭-혁신 GARCH 합성 null — **절차 자체**가 양(+) skew 차이를 만들어내는가
##  D4 부트 분포 기반 정직 p (ratio 대신)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182"); say <- function(fmt, ...) { cat(sprintf(paste0("[nul] ", fmt, "\n"), ...)); flush.console() }
skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
n_epi <- function(on, gap = 60L) { i <- which(on); if (!length(i)) return(0L); sum(diff(i) > gap) + 1L }
set.seed(20260809)

## ================= D1 2026-07 구간 안정성 =================
say("=== D1 최근구간(2026-06-01~) 백업 간 안정성 ===")
cur <- as.data.table(read_parquet(".cache/benchmark.parquet"))[order(Date)]
bks <- c(".cache/benchmark.parquet.bak_20260808_081104_scalebreak",
         ".cache/benchmark.parquet.bak_20260803_corrupt",
         ".cache/benchmark.parquet.bak_naver_patch_20260806_211113",
         ".cache/benchmark.parquet.bak_naver_patch_20260804_090547")
d1 <- list()
for (bk in bks) {
  if (!file.exists(bk)) { say("  %s — 없음", basename(bk)); next }
  b2 <- tryCatch(as.data.table(read_parquet(bk))[order(Date)], error=function(e) NULL)
  if (is.null(b2)) { say("  %s — read 실패", basename(bk)); next }
  M <- merge(cur[, .(Date, cur = BM_Ret)], b2[, .(Date, bak = BM_Ret)], by = "Date")
  Mr <- M[Date >= as.Date("2026-06-01")]
  say("  %-52s 공통 %d · 최근구간 %d · 최근구간 불일치 %d · 최대|Δ| %.4f · 백업 max|ret| %.4f",
      basename(bk), nrow(M), nrow(Mr), Mr[abs(cur-bak) > 1e-8, .N],
      if (nrow(Mr)) Mr[, max(abs(cur-bak))] else NA_real_,
      b2[Date >= as.Date("2026-06-01"), if (.N) max(abs(BM_Ret), na.rm=TRUE) else NA_real_])
  d1[[length(d1)+1L]] <- data.table(backup=basename(bk), n_common=nrow(M), n_recent=nrow(Mr),
    n_mismatch_recent=Mr[abs(cur-bak) > 1e-8, .N],
    max_absdiff_recent=if (nrow(Mr)) Mr[, max(abs(cur-bak))] else NA_real_)
}
say("  ★현행 계열 2026-06-01~ : n %d · sd %.4f (전기간 sd %.4f = %.1f배) · max %+.4f",
    cur[Date>=as.Date("2026-06-01"), .N], cur[Date>=as.Date("2026-06-01"), sd(BM_Ret,na.rm=TRUE)],
    cur[, sd(BM_Ret,na.rm=TRUE)],
    cur[Date>=as.Date("2026-06-01"), sd(BM_Ret,na.rm=TRUE)]/cur[, sd(BM_Ret,na.rm=TRUE)],
    cur[Date>=as.Date("2026-06-01"), max(BM_Ret,na.rm=TRUE)])
if (length(d1)) fwrite(rbindlist(d1), file.path(OUT, "adv_om_recent_integrity.csv"))

## ================= D2 공통창 전 계열 =================
say("=== D2 공통창 2002-01-10 ~ 2026-06-29 · 전 계열 동일조건 ===")
IDX <- as.data.table(read_parquet(".cache/indices.parquet"))[order(Date)]
BD  <- as.data.table(readRDS(file.path(ROOT,"stage_artifacts/alloc_daily/p0.rds"))$BD)[order(Date)]
mkret <- function(dates, lvl) { ok<-is.finite(lvl); d<-dates[ok]; l<-lvl[ok]; o<-order(d)
  data.table(Date=d[o], ret=c(NA_real_, l[o][-1]/l[o][-length(l)] - 1))[is.finite(ret)][abs(ret)<0.5] }
SER <- list(
  KR_BM        = data.table(Date=BD$Date, ret=BD$BM_Ret)[is.finite(ret)][abs(ret)<0.5],
  KOSPI200     = mkret(IDX$Date, IDX$kospi200),
  KOSPI_broad  = mkret(IDX$Date, IDX$kospi),
  KOSDAQ       = mkret(IDX$Date, IDX$kosdaq),
  KOSPI_small  = mkret(IDX$Date, IDX$kospi_small),
  KOSDAQ_small = mkret(IDX$Date, IDX$kosdaq_small),
  KOSPI_mid    = mkret(IDX$Date, IDX$kospi_mid),
  KOSDAQ_large = mkret(IDX$Date, IDX$kosdaq_large),
  all_firms    = mkret(IDX$Date, IDX$all_firms)
)
LO <- as.Date("2002-01-10"); HI <- as.Date("2026-06-29")
bbs <- function(x, on, B=500L, blk=60L) {
  n<-length(x); nb<-ceiling(n/blk); st<-seq_len(max(1,n-blk+1)); o<-rep(NA_real_,B)
  for (b in seq_len(B)) { s<-sample(st,nb,replace=TRUE)
    idx<-as.integer(unlist(lapply(s,function(k) k:min(k+blk-1,n))))[1:n]
    xb<-x[idx]; ob<-on[idx]; if (sum(ob)<30||sum(!ob)<30) next
    o[b]<-skew1(xb[ob])-skew1(xb[!ob]) }
  o[is.finite(o)] }
d2 <- list()
for (nm in names(SER)) {
  D <- SER[[nm]][Date >= LO & Date <= HI]
  if (nrow(D) < 1000) { say("  %-13s n %d — 스킵", nm, nrow(D)); next }
  nav <- cumprod(1+D$ret)
  D[, dd252 := nav/frollapply(nav,252,max,fill=NA,align="right") - 1]
  D[, fwd1 := shift(ret,1L,type="lead")]
  D <- D[is.finite(dd252) & is.finite(fwd1)]
  on <- D$dd252 <= -0.20
  if (sum(on) < 100) { say("  %-13s ON %d — 보류", nm, sum(on)); next }
  a<-skew1(D$fwd1[on]); of<-skew1(D$fwd1[!on]); df<-a-of
  bs<-bbs(D$fwd1,on,500L); se<-sd(bs); p_le0 <- mean(bs <= 0)
  say("  %-13s n %d · ON %4d (에피 %2d) · ON_skew %+.4f · OFF_skew %+.4f · diff %+.4f · se %.4f · ratio %.3f · 부트 P(diff<=0) %.3f · 뒤집힘 %s",
      nm, nrow(D), sum(on), n_epi(on), a, of, df, se, abs(df)/(2*se), p_le0, if (a>0 && of<0) "YES" else "NO")
  d2[[length(d2)+1L]] <- data.table(series=nm, n=nrow(D), n_on=sum(on), n_epi=n_epi(on),
    on_skew=a, off_skew=of, diff=df, se=se, ratio=abs(df)/(2*se), boot_p_le0=p_le0,
    signflip = (a>0 && of<0))
}
D2 <- rbindlist(d2); fwrite(D2, file.path(OUT, "adv_om_common_window.csv"))
say("  ★공통창 요약: 부호뒤집힘 %d/%d · diff>0 %d/%d · ratio>=1 %d/%d",
    D2[signflip==TRUE,.N], nrow(D2), D2[diff>0,.N], nrow(D2), D2[ratio>=1,.N], nrow(D2))
if (nrow(D2) > 1) {
  bt <- binom.test(D2[diff>0,.N], nrow(D2), 0.5)
  say("  ★diff>0 부호검정 (계열 독립 아님 — 상한 해석): p = %.4f", bt$p.value)
}

## ================= D3 대칭-혁신 GARCH 합성 null =================
say("=== D3 대칭 혁신 GARCH(1,1) null — 절차가 스스로 양(+) skew 차이를 만드는가 ===")
r0 <- BD[is.finite(BM_Ret)][abs(BM_Ret)<0.5]$BM_Ret
mu <- mean(r0); s2 <- var(r0); alpha <- 0.10; beta <- 0.88; omega <- s2*(1-alpha-beta)
say("  보정: mu %.6f · 무조건분산 %.6e · (a,b) = (%.2f,%.2f) · nu=5 표준화 t (대칭, 왜도 0)", mu, s2, alpha, beta)
sim1 <- function(n) {
  nu <- 5; e <- rt(n+500, df=nu)/sqrt(nu/(nu-2))
  h <- numeric(n+500); h[1] <- s2; r <- numeric(n+500)
  for (t in seq_len(n+500)) {
    if (t > 1) h[t] <- omega + alpha*(r[t-1]-mu)^2 + beta*h[t-1]
    r[t] <- mu + sqrt(h[t])*e[t]
  }
  r[(501):(500+n)]
}
NSIM <- 400L; n <- length(r0)
out <- matrix(NA_real_, NSIM, 5)
for (i in seq_len(NSIM)) {
  r <- sim1(n); nav <- cumprod(1+r)
  dd <- nav/frollapply(nav,252,max,fill=NA,align="right") - 1
  f1 <- c(r[-1], NA_real_)
  k <- is.finite(dd) & is.finite(f1); dd<-dd[k]; f1<-f1[k]
  on <- dd <= -0.20
  if (sum(on) < 100 || sum(!on) < 100) { out[i,] <- c(sum(on), NA,NA,NA,0); next }
  a<-skew1(f1[on]); of<-skew1(f1[!on])
  out[i,] <- c(sum(on), a, of, a-of, as.numeric(a>0 && of<0))
}
O <- as.data.table(out); setnames(O, c("n_on","on_skew","off_skew","diff","signflip"))
fwrite(O, file.path(OUT, "adv_om_garch_null.csv"))
V <- O[is.finite(diff)]
say("  유효 시뮬 %d/%d · ON일 중앙 %.0f", nrow(V), NSIM, median(V$n_on))
say("  null diff 분포: 평균 %+.4f · sd %.4f · 5%%/50%%/95%% = %+.4f / %+.4f / %+.4f",
    mean(V$diff), sd(V$diff), quantile(V$diff,.05), quantile(V$diff,.5), quantile(V$diff,.95))
say("  ★null 에서 diff >= +0.5808 비율 = %.3f", mean(V$diff >= 0.5808))
say("  ★null 에서 '부호 뒤집힘'(ON>0 & OFF<0) 비율 = %.3f", mean(V$signflip == 1))
say("  ★null ON_skew 평균 %+.4f · OFF_skew 평균 %+.4f (대칭이면 둘 다 0 근처여야 함)", mean(V$on_skew), mean(V$off_skew))

## ================= D4 실측 부트 분포 기반 p =================
say("=== D4 KR_BM 부트 분포 기반 P(diff<=0) — full vs drop-top1 ===")
B <- BD[is.finite(BM_Ret)][abs(BM_Ret)<0.5]
nav <- cumprod(1+B$BM_Ret)
B[, dd252 := nav/frollapply(nav,252,max,fill=NA,align="right") - 1]
B[, fwd1 := shift(BM_Ret,1L,type="lead")]
B <- B[is.finite(dd252) & is.finite(fwd1)]
on <- B$dd252 <= -0.20
imax <- which(on)[which.max(B$fwd1[on])]
for (tag in c("full","drop_top1","cut_2026-07")) {
  keep <- rep(TRUE, nrow(B))
  if (tag=="drop_top1") keep[imax] <- FALSE
  if (tag=="cut_2026-07") keep <- B$Date < as.Date("2026-07-01")
  x <- B$fwd1[keep]; o2 <- on[keep]
  bs <- bbs(x, o2, 800L)
  a<-skew1(x[o2]); of<-skew1(x[!o2]); df<-a-of
  say("  %-12s ON %d · diff %+.4f · 부트 P(diff<=0) %.3f · P(ON_skew<=0)... ratio %.3f",
      tag, sum(o2), df, mean(bs<=0), abs(df)/(2*sd(bs)))
}
say("=== STEP 4 완료 ===")
