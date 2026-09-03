# RK8 — 꼬리위험(EVT) · 요인 스트레스 · 회전 스트레스 · 유동성 용량 · crowding
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite); library(evir)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT<-getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R")); source(file.path(ROOT,"02_Infrastructure/backtest_harness.R"))
source(file.path(ROOT,"02_Infrastructure/factor_db/crowding_score_per_factor.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o3<-readRDS(file.path(OUT,"rk3_objects.rds")); o4<-readRDS(file.path(OUT,"rk4_objects.rds"))
o6<-readRDS(file.path(OUT,"rk6_objects.rds")); o7<-readRDS(file.path(OUT,"rk7_objects.rds"))
X<-o3$X; STY<-o3$STY; B<-o4$B; Om<-o4$Om_lw; asof<-o4$asof; wf<-o6$wf; Sig<-o6$Sig
PR <- fread(file.path(OUT,"period_returns_production.csv")); PR[,signal_date:=as.Date(signal_date)]
day <- fread(file.path(OUT,"rk_book_daily.csv")); day[,Date:=as.Date(Date)]
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
pn <- readRDS(file.path(OUT,"panel.rds")); LIQ <- as.data.table(pn$fwd$liq_dt)

## ================= 1. 꼬리위험 =================
rm_ <- PR$ret_net; rd_ <- day$ret_d
emp <- function(x,q) c(VaR=-as.numeric(quantile(x,q)), ES=-mean(x[x<=quantile(x,q)]))
tail_emp <- list(monthly_net=list(q05=emp(rm_,.05), q01=emp(rm_,.01)),
                 daily_gross=list(q05=emp(rd_,.05), q01=emp(rd_,.01)))
cf_var <- function(x,q){ m<-mean(x); s<-sd(x); S<-mean((x-m)^3)/s^3; K<-mean((x-m)^4)/s^4-3
  z<-qnorm(q); zcf<-z+(z^2-1)*S/6+(z^3-3*z)*K/24-(2*z^3-5*z)*S^2/36; -(m+zcf*s) }
gpdfit <- function(x, thr_q=0.90){
  L <- -x; u <- as.numeric(quantile(L, thr_q))
  f <- tryCatch(evir::gpd(L, threshold=u), error=function(e) NULL); if(is.null(f)) return(NULL)
  xi<-f$par.ests["xi"]; bt<-f$par.ests["beta"]; nu<-f$n.exceed; n<-length(L)
  vq <- function(q){ as.numeric(u + bt/xi*(((n/nu)*(1-q))^(-xi)-1)) }
  esq<- function(q){ v<-vq(q); as.numeric((v + bt - xi*u)/(1-xi)) }
  list(xi=as.numeric(xi), beta=as.numeric(bt), threshold=u, n_exceed=as.integer(nu), n=as.integer(n),
       VaR95=vq(.95), ES95=esq(.95), VaR99=vq(.99), ES99=esq(.99)) }
g_m <- gpdfit(rm_, .90); g_d <- gpdfit(rd_, .95)
hill <- function(x,k=NULL){ L<-sort(-x[x<0],decreasing=TRUE); if(length(L)<30) return(NA_real_)
  if(is.null(k)) k<-max(15,floor(0.10*length(L))); k<-min(k,length(L)-1)
  1/mean(log(L[1:k])-log(L[k+1])) }
hill_m <- hill(rm_); hill_d <- hill(rd_)
nav <- cumprod(1+rm_); ddv <- nav/cummax(nav)-1
cdar05 <- -mean(ddv[ddv<=quantile(ddv,.05)])
navd <- cumprod(1+rd_); dd_d <- navd/cummax(navd)-1
u1<-rank(day$ret_d)/(nrow(day)+1); u2<-rank(day$BM_Ret)/(nrow(day)+1)
tdc <- sapply(c(.05,.10), function(q) mean(u1<=q & u2<=q)/q)
cat(sprintf("[RK8] 월간 net VaR95 %.2f%% ES95 %.2f%% | EVT VaR95 %.2f%% ES95 %.2f%% ES99 %.2f%% xi %.3f\n",
  100*tail_emp$monthly_net$q05["VaR"],100*tail_emp$monthly_net$q05["ES"],100*g_m$VaR95,100*g_m$ES95,100*g_m$ES99,g_m$xi))
cat(sprintf("[RK8] 일간 VaR95 %.2f%% | EVT ES99 %.2f%% xi %.3f · Hill alpha 월 %.2f 일 %.2f\n",
  100*tail_emp$daily_gross$q05["VaR"],100*g_d$ES99,g_d$xi,hill_m,hill_d))
cat(sprintf("[RK8] MDD(mon,net) %.2f%% · MDD(day,gross) %.2f%% · CDaR5 %.2f%% · TDC(5) %.3f (10) %.3f\n",
  100*min(ddv),100*min(dd_d),100*cdar05,tdc[1],tdc[2]))

## ================= 2. 요인 스트레스(상관 전파) =================
Bw <- as.numeric(t(B)%*%wf); names(Bw)<-colnames(B)
d_cap <- wf-o6$w_cap; Bd <- as.numeric(t(B)%*%d_cap); names(Bd)<-colnames(B)
sd_f <- sqrt(diag(Om))
shock_factor <- function(k, nsig){ s <- nsig*sd_f[k]; as.numeric(Om[,k]/Om[k,k]*s) }
mkstress <- function(k, nsig){ f <- shock_factor(k,nsig); c(total=sum(Bw*f), active=sum(Bd*f)) }
mkt_move <- function(target){ f <- as.numeric(Om[,"MKT"]/Om["MKT","MKT"]*target); c(total=sum(Bw*f), active=sum(Bd*f)) }
ST <- list(
  market_down_5   = mkt_move(-0.05),
  market_down_10  = mkt_move(-0.10),
  momentum_reversal_2sd = mkstress("MOM",-2),
  signal_crash_2sd      = mkstress("SIGNAL",-2),
  liquidity_shock_2sd   = mkstress("LIQ",-2),
  vol_shock_2sd         = mkstress("VOL",-2),
  size_shock_2sd        = mkstress("SIZE",-2),
  reversal_shock_2sd    = mkstress("REV",-2))
print(round(100*do.call(rbind,ST),3))

## ================= 3. 회전 스트레스 =================
tn <- PR$traded_notional
to_2way_ann <- mean(tn)*12; to_1way_ann <- to_2way_ann/2
grid <- c(5,10,15,20,25,30,40.7,50,60,80)/1e4
bm_cagr <- prod(1+PR$benchmark_ret)^(12/nrow(PR))-1
tstress <- rbindlist(lapply(grid, function(c1){
  rn <- PR$ret_gross - tn*c1
  ann <- prod(1+rn)^(12/length(rn))-1
  data.table(cost_oneway_bps=c1*1e4, cagr_net=ann, active_ann=ann-bm_cagr,
             sr=mean(rn)/sd(rn)*sqrt(12), cost_drag_ann=mean(tn*c1)*12)}))
print(tstress)
be_exact <- uniroot(function(c1){ rn <- PR$ret_gross - tn*c1
  prod(1+rn)^(12/length(rn)) - (1+bm_cagr) }, c(0,0.05))$root
cat(sprintf("[RK8] TO two-way %.0f%%/yr · one-way %.0f%%/yr · breakeven one-way %.1fbps · vs 15bps %.2fx\n",
  100*to_2way_ann,100*to_1way_ann,be_exact*1e4,be_exact/0.0015))
turn_names <- rbindlist(lapply(2:nrow(PR), function(i){
  h0 <- A[Date==PR$signal_date[i-1] & in_top25==TRUE,Ticker]; h1 <- A[Date==PR$signal_date[i] & in_top25==TRUE,Ticker]
  data.table(signal_date=PR$signal_date[i], n_new=length(setdiff(h1,h0)), n_keep=length(intersect(h0,h1)))}))
cat(sprintf("[RK8] mean new names %.1f/25 (replace %.1f%%) · max %d\n",
  mean(turn_names$n_new), 100*mean(turn_names$n_new)/25, max(turn_names$n_new)))

## ================= 4. 유동성 용량 =================
hold <- A[in_top25==TRUE,.(Date,Ticker)]
HL <- merge(hold, LIQ, by=c("Date","Ticker"), all.x=TRUE)
cat(sprintf("[RK8] ADV20 missing %d/%d\n", sum(is.na(HL$adv)), nrow(HL)))
HL[, adv := as.numeric(adv)]
capa <- HL[is.finite(adv), .(min_adv=min(adv), med_adv=median(adv), p10=quantile(adv,.10)), by=Date]
capa <- merge(capa, PR[,.(Date=signal_date,tn=traded_notional)], by="Date")
capa[, aum_cap_10pct := 0.10*min_adv/(tn/2/25)]
cat(sprintf("[RK8] AUM cap (10pct ADV, 1-day) median %.1f eok · p10 %.1f eok · last12M median %.1f eok\n",
  median(capa$aum_cap_10pct)/1e8, quantile(capa$aum_cap_10pct,.10)/1e8,
  median(tail(capa$aum_cap_10pct,12))/1e8))
asof_liq <- LIQ[Date==asof & Ticker %in% o6$top]
if(nrow(asof_liq)>0) cat(sprintf("[RK8] as_of top25 ADV20: median %.1f eok · min %.1f eok · n=%d\n",
  median(asof_liq$adv)/1e8, min(asof_liq$adv)/1e8, nrow(asof_liq)))

## ================= 5. crowding =================
rl <- load_rawdata(use_cache=TRUE); RAW <- as.data.table(rl$RAWDATA); rm(rl); gc(verbose=FALSE)
RAW[,Date:=as.Date(Date)]
fe_at <- function(d){ xd <- X[Date==d]
  rbindlist(lapply(c("SIGNAL","MOM","VOL","LIQ","SIZE"), function(k)
    data.table(Ticker=xd$Ticker, factor_name=paste0("WT007_",k), exposure=xd[[k]]))) }
bmk <- unique(RAW[Date==asof & (K200==TRUE|KQ150==TRUE), Ticker])
dates_c <- sort(unique(X$Date)); d3 <- dates_c[length(dates_c)-3]
cw_now <- crowding_score_per_factor(fe_at(asof), asof, RAW, benchmark_tickers=bmk, top_n=25L)
cw_3m  <- crowding_score_per_factor(fe_at(d3), d3, RAW, benchmark_tickers=bmk, top_n=25L)
cw <- merge(cw_now, cw_3m[,.(factor_name,crowding_score_3m_ago=crowding_score)], by="factor_name")
cw[, delta_3m := crowding_score - crowding_score_3m_ago]
print(cw)
saveRDS(list(tail_emp=tail_emp,g_m=g_m,g_d=g_d,hill_m=hill_m,hill_d=hill_d,cdar05=cdar05,
  mdd_m=min(ddv),mdd_d=min(dd_d),tdc=tdc,ST=ST,tstress=tstress,be_exact=be_exact,
  to_2way_ann=to_2way_ann,to_1way_ann=to_1way_ann,turn_names=turn_names,capa=capa,
  asof_liq=asof_liq,cw=cw,cf95=cf_var(rm_,.05),cf99=cf_var(rm_,.01),Bw=Bw,Bd=Bd,
  bm_cagr=bm_cagr,d3=d3), file.path(OUT,"rk8_objects.rds"))
cat("[RK8] done\n")
