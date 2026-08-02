## _channel_012.R — 창-정합 개선(A→A′)의 채널 분리
##   A′ 는 A 와 두 군데가 다르다: ① SAFE flag 확장(on) ② 커버리지 확장(cov → OFF 풀·전이유효 변화).
##   창-정합에서 A′ 가 더 강해 보인 것이 ①(보조축이 실제로 좋은 이름을 더함) 때문인지
##   ②(OFF 기준선 재구성) 때문인지 갈라야 배선 제안을 쓸 수 있다.
##   2×2: {on_A, on_Ap} × {cov_a, cov_Ap}
## 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_012/_channel_012.R", encoding="UTF-8")'
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2L), silent=TRUE)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_012"
logf <- file.path(OUT, "_r43_channel_log.txt"); if (file.exists(logf)) try(file.remove(logf), silent=TRUE)
w  <- function(...){ m<-paste0(...); try({.c<-file(logf,"a",encoding="UTF-8"); writeLines(m,.c); close(.c)}, silent=TRUE); cat(m,"\n") }
wf <- function(...) w(sprintf(...))
ymshift <- function(v,k){y<-v%/%100L;m<-v%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
nw_fit <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(list(mean=NA,t=NA,n=length(x)))
  m<-lm(x~1); ct<-coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))
  list(mean=as.numeric(ct[1,1]), t=as.numeric(ct[1,3]), n=length(x)) }
mk_flag <- function(z,thr) as.integer(!is.na(z) & z>=thr); THR <- 1.0
build_states <- function(DT, on_col, cov_col){
  d <- copy(DT); setorder(d, Ticker, hold_ym)
  d[, .on:=as.integer(get(on_col))]; d[, .cov:=as.logical(get(cov_col))]
  d[, .onp:=shift(.on), by=Ticker]; d[, .covp:=shift(.cov), by=Ticker]; d[, .ymp:=shift(hold_ym), by=Ticker]
  d[, .consec := !is.na(.ymp) & (.ymp==ymshift(hold_ym,-1L))]
  d[, .valid := .cov & !is.na(.covp) & .covp & .consec & !is.na(.onp)]
  d[, .on_p := as.integer(.valid & .onp==1L)]
  d[, state := fifelse(!.valid, NA_character_,
               fifelse(.on==1L & .on_p==0L,"ENTRY", fifelse(.on==1L & .on_p==1L,"SUSTAIN",
               fifelse(.on==0L & .on_p==1L,"EXIT","OFF"))))]
  d[] }
paired <- function(DT, col, tgt, ref, basis="Ret_1m"){
  d <- DT[get(col) %in% c(tgt,ref)]; if(!nrow(d)) return(list(gap_ann=NA,gap_t=NA,n_months=0L,avg=NA))
  g <- d[, .(ms=mean(get(basis)[get(col)==tgt],na.rm=TRUE), mr=mean(get(basis)[get(col)==ref],na.rm=TRUE),
             ns=sum(get(col)==tgt), nr=sum(get(col)==ref)), by=hold_ym][ns>0 & nr>0]
  if(!nrow(g)) return(list(gap_ann=NA,gap_t=NA,n_months=0L,avg=NA))
  f <- nw_fit(g$ms-g$mr); list(gap_ann=f$mean*12, gap_t=f$t, n_months=f$n, avg=mean(g$ns)) }
pr <- function(x) sprintf("gap_ann=%+.4f t=%+.2f (mo=%d, %.1f/mo)", x$gap_ann, x$gap_t, x$n_months, x$avg)

## ── 패널 재구성 (run_r43 과 동일 산식) ────────────────────────────────────────
o36 <- readRDS("stage_artifacts/WT_D20260715_005/_r36_objects.rds"); uni <- copy(as.data.table(o36$uni))
PAN <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_007/insider_axes_panel.parquet"))
cs_z <- function(dt,col){ d<-dt[is.finite(get(col)), .(sig_ym,Ticker,x=get(col))]
  d[, { mu<-mean(x); s<-sd(x); if(!is.finite(s)||s<=0) list(Ticker=Ticker,score=rep(NA_real_,.N)) else {
    xw<-pmin(pmax(x,mu-3*s),mu+3*s); s2<-sd(xw)
    if(!is.finite(s2)||s2<=0) list(Ticker=Ticker,score=rep(NA_real_,.N)) else list(Ticker=Ticker,score=(xw-mean(xw))/s2)}}, by=sig_ym][is.finite(score)] }
MZ <- cs_z(PAN,"INS_MAGQ3"); MZ[, hold_ym := ymshift(as.integer(sig_ym),1L)]
uni <- merge(uni, MZ[, .(hold_ym,Ticker,magq3=score)], by=c("hold_ym","Ticker"), all.x=TRUE)
uni[, cov_a := !is.na(INS02_OffBuyBreadth6m)]; uni[, cov_b := !is.na(magq3)]
uni[, cov_Ap := cov_a | cov_b]
uni[, a := mk_flag(INS02_OffBuyBreadth6m,THR)]; uni[, b := mk_flag(magq3,THR)]
uni[, on_A := a]; uni[, on_Ap := as.integer(a==1L | b==1L)]
A_MONTHS <- uni[a==1L, unique(hold_ym)]

VAR <- list(
  V1_A      = list(on="on_A",  cov="cov_a",  desc="A (현행)"),
  V2_Aflag_Apcov = list(on="on_A", cov="cov_Ap", desc="A flag + A′ 커버리지  ← 채널② 단독(OFF 풀 재구성)"),
  V3_Apflag_Acov = list(on="on_Ap", cov="cov_a", desc="A′ flag + A 커버리지  ← 채널① 단독(보조 flag 확장)"),
  V4_Ap     = list(on="on_Ap", cov="cov_Ap", desc="A′ (사전등록 primary)"))
for (v in names(VAR)) {
  st <- build_states(uni, VAR[[v]]$on, VAR[[v]]$cov)[, .(hold_ym, Ticker, s=state)]
  setnames(st, "s", paste0("st_", v)); uni <- merge(uni, st, by=c("hold_ym","Ticker"), all.x=TRUE)
}
RES <- list()
w("────── 채널 분리: SUSTAIN vs OFF, 창-정합(A 활성 126개월) ──────")
for (sl in c("MID_habitat","REST","ALL")) {
  D <- switch(sl, MID_habitat=uni[sz_tercile=="mid"], REST=uni[megatier=="REST"], ALL=uni)
  Dm <- D[hold_ym %in% A_MONTHS]
  w(sprintf("\n[%s | 창-정합]", sl)); RES[[sl]] <- list()
  for (v in names(VAR)) { x <- paired(Dm, paste0("st_",v), "SUSTAIN","OFF")
    RES[[sl]][[v]] <- list(gap_ann=round(x$gap_ann,5), gap_t=round(x$gap_t,3), n_months=x$n_months, avg=round(x$avg,2))
    wf("   %-16s %-42s %s", v, VAR[[v]]$desc, pr(x)) }
  t1 <- RES[[sl]]$V1_A$gap_t; t2 <- RES[[sl]]$V2_Aflag_Apcov$gap_t
  t3 <- RES[[sl]]$V3_Apflag_Acov$gap_t; t4 <- RES[[sl]]$V4_Ap$gap_t
  wf("   ⇒ 채널②(커버리지만) Δt=%+.2f | 채널①(보조flag만) Δt=%+.2f | 합산 A′ Δt=%+.2f",
     t2-t1, t3-t1, t4-t1)
}
## MAG_ONLY 직접 검정 — A 활성월 한정 (보조축 이름 자체의 안전성)
uni[, grp4 := fifelse(!(cov_a|cov_b), NA_character_,
             fifelse(a==1L&b==1L,"BOTH", fifelse(a==1L&b==0L,"A_ONLY",
             fifelse(a==0L&b==1L,"MAG_ONLY","NEITHER"))))]
w("\n────── MAG_ONLY vs NEITHER — 월집합 분리 ──────")
MOSPLIT <- list()
for (sl in c("MID_habitat","REST","ALL")) {
  D <- switch(sl, MID_habitat=uni[sz_tercile=="mid"], REST=uni[megatier=="REST"], ALL=uni)
  xa <- paired(D[hold_ym %in% A_MONTHS], "grp4","MAG_ONLY","NEITHER")
  xs <- paired(D[!hold_ym %in% A_MONTHS], "grp4","MAG_ONLY","NEITHER")
  MOSPLIT[[sl]] <- list(A_active=list(gap_ann=round(xa$gap_ann,5),gap_t=round(xa$gap_t,3),n_months=xa$n_months,avg=round(xa$avg,2)),
                        A_silent=list(gap_ann=round(xs$gap_ann,5),gap_t=round(xs$gap_t,3),n_months=xs$n_months,avg=round(xs$avg,2)))
  wf("   [%-11s] A활성월 %s | A침묵월 %s", sl, pr(xa), pr(xs))
}
write_json(list(A_active_months=length(A_MONTHS), variants=lapply(VAR, function(x) x$desc),
                channel_decomposition=RES, mag_only_month_split=MOSPLIT),
           file.path(OUT,"r43_channel.json"), auto_unbox=TRUE, pretty=TRUE, digits=6, na="null")
w("\nCHANNEL_DONE"); cat("[SAVED]", file.path(OUT,"r43_channel.json"), "\n")
