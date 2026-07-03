#==============================================================================
# Phase 0 검증 battery (1차): #1 sub-period · #2 calmar/MDD · #3 turnover-banding · #6 look-ahead
#   대상: B(predB, score_eff+factors) vs A(score_eff). 적대적 자세.
#==============================================================================
suppressPackageStartupMessages({ library(arrow); library(data.table) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a

sc <- as.data.table(read_parquet(file.path(ROOT,".cache/discovery/phase0_scores.parquet")))
sc[, Date := as.Date(paste0(ym,"-01"))]
returns_dt <- unique(sc[, .(Date, Ticker, Ret_1m = fwd_ret_1m)])
bm <- as.data.table(read_parquet(file.path(ROOT,".cache/benchmark.parquet")))
bmcol <- intersect(c("BM_Ret","Ret","bm_ret"),names(bm))[1]; bm[,Date:=as.Date(Date)]; bm<-bm[!is.na(get(bmcol))]
bm[,ym2:=format(Date,"%Y-%m")]; bmm<-bm[,.(lr=sum(log(1+get(bmcol)))),by=ym2]; setorder(bmm,ym2)
bmm[,mret:=expm1(lr)][,fwd:=shift(mret,-1)]
bench_dt <- bmm[!is.na(fwd),.(Date=as.Date(paste0(ym2,"-01")),BM_Ret=fwd)]
bmap <- setNames(bench_dt$BM_Ret, as.character(bench_dt$Date))

TOPN <- 25L
csbt <- function(sig, d0=NULL, d1=NULL){
  s <- sc[, .(Date,Ticker,score=get(sig))][!is.na(score)]
  if(!is.null(d0)) s <- s[Date>=as.Date(d0) & Date<=as.Date(d1)]
  r <- canonical_screen_bt(s, returns_dt, bench_dt, top_n=TOPN, cost_bps_oneway=15)
  list(PORT_t=r$portfolio_alpha_t_nw_lag3, IR=r$information_ratio, TO=r$turnover_annual, n=r$n_months)
}

# ---- 직접 net ABS 시계열 (calmar/MDD·banding용; cost=sum|dw|*15bps delta) ----
bt_series <- function(sig, band=NULL){
  dates <- sort(unique(sc$Date)); prev <- character(0); out <- list()
  for(d in dates){
    m <- sc[Date==d & !is.na(get(sig))]; if(nrow(m)<TOPN) next
    setorder(m, -score_eff)  # placeholder; reorder by sig below
    m <- m[order(-m[[sig]])]
    rk <- setNames(seq_len(nrow(m)), m$Ticker)
    if(is.null(band)){ sel <- m$Ticker[1:TOPN] } else {
      keep <- prev[prev %in% m$Ticker]; keep <- keep[rk[keep] <= band]
      cand <- setdiff(m$Ticker, keep); add <- cand[order(rk[cand])]
      sel <- head(c(keep, add), TOPN)
    }
    gross <- mean(m[Ticker %in% sel, fwd_ret_1m])
    w <- setNames(rep(1/TOPN,length(sel)),sel); wp <- setNames(rep(1/max(1,length(prev)),length(prev)),prev)
    allt <- union(names(w),names(wp)); to <- sum(abs((w[allt]%||%0)*ifelse(is.na(w[allt]),0,1) - ifelse(is.na(wp[allt]),0,wp[allt])),na.rm=TRUE)
    wv <- sapply(allt,function(t) (if(t %in% names(w)) w[[t]] else 0) - (if(t %in% names(wp)) wp[[t]] else 0))
    to <- sum(abs(wv))
    net <- gross - to*0.0015
    out[[length(out)+1]] <- data.table(Date=d, net=net, bm=bmap[as.character(d)]%||%NA_real_, to=to)
    prev <- sel
  }
  rbindlist(out)
}
mdd <- function(r){ nav<-cumprod(1+r); 1 - min(nav/cummax(nav)) }
stats_abs <- function(ser){
  r<-ser$net; n<-length(r); cagr<-prod(1+r)^(12/n)-1; m<-mdd(r); sr<-mean(r)/sd(r)*sqrt(12)
  act<-ser$net-ser$bm; ir<-mean(act,na.rm=TRUE)/sd(act,na.rm=TRUE)*sqrt(12)
  list(CAGR=cagr, MDD=m, calmar=cagr/m, absSR=sr, IR=ir, TO=mean(ser$to)*12, n=n)
}

cat("================ Phase 0 검증 (top25) ================\n")

cat("\n#1 SUB-PERIOD 안정성 (canonical PORT_t / IR, 3분할)\n")
splits <- list(c("2010-01-01","2015-12-31"),c("2016-01-01","2020-12-31"),c("2021-01-01","2026-12-31"))
for(sp in splits){
  a<-csbt("score_eff",sp[1],sp[2]); b<-csbt("predB",sp[1],sp[2])
  cat(sprintf("  %s~%s (n%d): A PORT_t %.2f IR %.2f | B PORT_t %.2f IR %.2f | ΔPORT_t %+.2f ΔIR %+.2f\n",
              substr(sp[1],1,7),substr(sp[2],1,7),b$n,a$PORT_t,a$IR,b$PORT_t,b$IR,b$PORT_t-a$PORT_t,b$IR-a$IR))
}

cat("\n#2 calmar/MDD (직접 net ABS, 오버레이 無 — bare. HARD calmar>=0.64는 오버레이 後 #4서 본판정)\n")
for(sig in c("score_eff","predB")){ s<-stats_abs(bt_series(sig))
  cat(sprintf("  %-10s absSR %.2f CAGR %.1f%% MDD %.1f%% calmar %.2f IR %.2f TO %.1f\n",
              sig,s$absSR,s$CAGR*100,s$MDD*100,s$calmar,s$IR,s$TO)) }

cat("\n#3 turnover-banding (buffer rule, 회전 억제 후 우위 유지?)\n")
for(bd in c(35L,40L,50L)){ s<-stats_abs(bt_series("predB",band=bd))
  cat(sprintf("  predB band<=%d: TO %.1f (was ~15) | absSR %.2f calmar %.2f IR %.2f\n",bd,s$TO,s$absSR,s$calmar,s$IR)) }

cat("\n#6 look-ahead offset (predB 신호를 -1/0/+1달 이동한 IC; 0=정상, +1=미래(누수면 급등), -1=stale)\n")
icf <- function(off){
  d<-copy(sc); setorder(d,Ticker,Date)
  d[, sig_sh := shift(predB, -off), by=Ticker]   # off=+1 → 미래신호 당겨씀
  ics <- d[!is.na(sig_sh)&!is.na(fwd_ret_1m), .(ic=cor(sig_sh,fwd_ret_1m,method="spearman")), by=ym]
  mean(ics$ic,na.rm=TRUE)
}
cat(sprintf("  offset -1(stale) %.4f | 0(정상) %.4f | +1(미래) %.4f  → 0이 +1 안 넘고 매끈감쇠면 누수無\n",
            icf(-1), icf(0), icf(1)))
cat("\n검증 1차 완료.\n")
