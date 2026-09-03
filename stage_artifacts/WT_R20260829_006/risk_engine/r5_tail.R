## RISK Stage 5 — tail risk (empirical/CF/EVT-GPD/Hill) + stress + crowding
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
S <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
O <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/risk006"
## tail_risk_engine.R 는 fExtremes 미설치로 로드 불가 -> GPD/Hill/CF 자체 구현(아래) 사용.
tre_available <- requireNamespace("fExtremes", quietly=TRUE)
cat("[infra] tail_risk_engine(fExtremes) available =", tre_available, "-> self-implemented GPD/Hill/CF\n")
R1<-readRDS(file.path(O,"r1_reg.rds")); R3<-readRDS(file.path(O,"r3_sigma.rds")); R4<-readRDS(file.path(O,"r4_diag.rds"))
mk<-readRDS(file.path(S,"p1s_market.rds"))
U<-R3$U; B<-R3$B; OM<-R3$OM; SIGMA<-R3$SIGMA; FACN<-R3$FACN; bk<-R4$bk; xp<-R4$xp

PR <- fread("stage_artifacts/WT_R20260829_006/period_returns_production.csv")
PR[, holding_start := as.Date(paste0(holding_ym,"-01"))]
setorder(PR, holding_start)
r  <- PR$ret_net; a <- PR$active
cat("[ret] n",length(r)," mean",round(mean(r),5)," sd",round(sd(r),5),
    " skew", round(mean((r-mean(r))^3)/sd(r)^3,3), " kurt", round(mean((r-mean(r))^4)/sd(r)^4,3),"\n")
## 상류 자기신고 WT006-17: 2025-01 이후 BM 변동성 이상 -> 절단 병기
r_pre <- PR[holding_start < as.Date("2025-01-01")]$ret_net
a_pre <- PR[holding_start < as.Date("2025-01-01")]$active
cat("[ret] pre-2025 subset n",length(r_pre)," sd",round(sd(r_pre),5),
    " 2025+ n",length(r)-length(r_pre)," sd",round(sd(r[(length(r_pre)+1):length(r)]),5),"\n")

emp <- function(x,p){ q<-as.numeric(quantile(x,p)); list(var=-q, es=-mean(x[x<=q])) }
hill <- function(x,k=25L){ L<-sort(-x,decreasing=TRUE); L<-L[L>0]; k<-min(k,length(L)-1L)
  if(k<5) return(NA_real_); 1/mean(log(L[1:k])-log(L[k+1])) }
gpd_fit <- function(x, uq=0.90){ L <- -x; u <- as.numeric(quantile(L,uq)); y <- L[L>u]-u
  nu<-length(y); if(nu<15) return(NULL)
  nll<-function(p){ xi<-p[1]; be<-exp(p[2]); if(be<=0) return(1e10)
    z<-1+xi*y/be; if(any(z<=0)) return(1e10)
    nu*log(be)+(1+1/xi)*sum(log(z)) }
  nll0<-function(p){ be<-exp(p[1]); nu*log(be)+sum(y)/be }
  o<-tryCatch(optim(c(0.1,log(sd(y))),nll,method="Nelder-Mead"),error=function(e)NULL)
  if(is.null(o)) return(NULL)
  xi<-o$par[1]; be<-exp(o$par[2]); ru<-nu/length(L)
  vq<-function(p){ if(abs(xi)<1e-6) u+be*log(ru/(1-p)) else u+be/xi*((ru/(1-p))^xi-1) }
  esq<-function(p){ v<-vq(p); if(xi>=1) return(NA_real_); (v+be-xi*u)/(1-xi) }
  list(u=u,n_exc=nu,xi=xi,beta=be, var95=vq(0.95), es95=esq(0.95), var99=vq(0.99), es99=esq(0.99)) }

TAIL <- list()
for (nm in c("full","pre2025")) {
  x <- if (nm=="full") r else r_pre
  e5<-emp(x,0.05); e1<-emp(x,0.01)
  g <- gpd_fit(x, 0.90)
  sk <- mean((x-mean(x))^3)/sd(x)^3; ku <- mean((x-mean(x))^4)/sd(x)^4 - 3
  z<-qnorm(0.05); zcf <- z + (z^2-1)*sk/6 + (z^3-3*z)*ku/24 - (2*z^3-5*z)*sk^2/36
  cf5 <- -(mean(x)+zcf*sd(x))
  TAIL[[nm]] <- list(n=length(x),
    emp_var_5=round(e5$var,4), emp_es_5=round(e5$es,4),
    emp_var_1=round(e1$var,4), emp_es_1=round(e1$es,4),
    cf_var_5=round(cf5,4), hill_alpha=round(hill(x),3),
    gpd_threshold_q=0.90, gpd_n_exceed=if(is.null(g)) NA else g$n_exc,
    gpd_xi=if(is.null(g)) NA else round(g$xi,4),
    gpd_var_95=if(is.null(g)) NA else round(g$var95,4),
    gpd_es_95=if(is.null(g)) NA else round(g$es95,4),
    gpd_var_99=if(is.null(g)) NA else round(g$var99,4),
    gpd_es_99=if(is.null(g)) NA else round(g$es99,4))
  cat("[tail:",nm,"] ", paste(names(TAIL[[nm]]),unlist(TAIL[[nm]]),sep="=",collapse=" "),"\n")
}
## active leg
ea5<-emp(a,0.05); ea1<-emp(a,0.01)
cat(sprintf("[tail:active] VaR5 %.4f ES5 %.4f VaR1 %.4f ES1 %.4f hill %.3f\n",
    ea5$var, ea5$es, ea1$var, ea1$es, hill(a)))
## MDD (monthly)
nav <- cumprod(1+r); ddv <- nav/cummax(nav)-1
MDDv <- min(ddv); CDaR95 <- -mean(ddv[ddv<=quantile(ddv,0.05)])
cat(sprintf("[tail] monthly MDD %.4f  CDaR95 %.4f\n", MDDv, CDaR95))

## Sigma-implied parametric (as_of book, 진단 기준 EW top-25)
idx <- match(bk, rownames(SIGMA)); w <- rep(1/length(bk), length(bk))
sig_m <- sqrt(as.numeric(t(w)%*%SIGMA[idx,idx]%*%w))
nu <- 5
tq <- function(p,nu) qt(p,nu)*sqrt((nu-2)/nu)
cat(sprintf("[tail:Sigma] book monthly sd %.4f (ann %.2f pct) | normal VaR5 %.4f VaR1 %.4f | t5 VaR5 %.4f VaR1 %.4f | t5 ES5 %.4f\n",
    sig_m, sig_m*sqrt(12)*100, -qnorm(0.05)*sig_m, -qnorm(0.01)*sig_m,
    -tq(0.05,nu)*sig_m, -tq(0.01,nu)*sig_m,
    sig_m*(dt(tq(0.05,nu),nu)/0.05)*((nu+tq(0.05,nu)^2)/(nu-1))*sqrt((nu-2)/nu)))

## ── STRESS 1: 실현 구간 ──────────────────────────────────────────────────────
SP <- list(list(name="Terror_9_11",start="2001-09-01",end="2001-12-31"),
           list(name="GFC",start="2007-10-01",end="2009-03-31"),
           list(name="Euro_Debt",start="2011-07-01",end="2011-12-31"),
           list(name="China_Shock",start="2015-06-01",end="2016-02-29"),
           list(name="US_China_Trade",start="2018-03-01",end="2018-12-31"),
           list(name="COVID",start="2020-01-01",end="2020-06-30"),
           list(name="Rate_Hike",start="2022-01-01",end="2022-12-31"),
           list(name="Iran_War",start="2026-02-01",end="2026-04-30"))
RETP <- mk$RET_DT
rows <- list()
for (sp in SP) {
  s<-as.Date(sp$start); e<-as.Date(sp$end)
  d <- PR[holding_start>=s & holding_start<=e]
  nm_ct <- RETP[Date>=s & Date<=e & Ticker %in% bk, uniqueN(Ticker)]
  cov_book <- nm_ct/length(bk)
  if (nrow(d)<2) { rows[[sp$name]] <- data.table(period=sp$name,start=s,end=e,n_months=nrow(d),
      strat=NA_real_,bench=NA_real_,alpha=NA_real_,mdd=NA_real_,book_coverage=round(cov_book,3),
      reliability="UNRELIABLE_NO_RETURN_COVERAGE"); next }
  cs<-prod(1+d$ret_net)-1; cb<-prod(1+d$benchmark_ret)-1
  nv<-cumprod(1+d$ret_net); md<-min(nv/cummax(nv)-1)
  rel <- if (cov_book < 0.85) "UNRELIABLE_BOOK_COVERAGE_LT_85" else "OK"
  if (sp$name=="Iran_War") rel <- paste0(rel,"; BM_INTEGRITY_SUSPECT(WT006-17)")
  rows[[sp$name]] <- data.table(period=sp$name,start=s,end=e,n_months=nrow(d),
      strat=round(cs,4),bench=round(cb,4),alpha=round(cs-cb,4),mdd=round(md,4),
      book_coverage=round(cov_book,3), reliability=rel)
}
STR <- rbindlist(rows); print(STR)
## KR bear (BM 12m<0 구간 집계)
ben <- mk$BENCH_DT; setorder(ben,Date); ben[, bm12 := frollsum(log(1+BM_Ret),12)]
bd <- ben[bm12<0 & !is.na(bm12)]$Date
PRb <- PR[as.Date(signal_date) %in% bd]
cat(sprintf("[stress] KR_Bear months=%d  mean strat %.4f  mean bench %.4f  mean active %.4f\n",
    nrow(PRb), mean(PRb$ret_net), mean(PRb$benchmark_ret), mean(PRb$active)))

## ── STRESS 2: 팩터 조건부 충격 (Omega 조건부 기댓값) ────────────────────────
cond_shock <- function(fac, shock) {
  j <- match(fac, FACN); ef <- OM[,j]/OM[j,j]*shock
  as.numeric(t(xp) %*% ef) }
SC <- data.table(
  scenario=c("market_down_5","market_down_10","momentum_reversal_2sd","size_reversal_2sd",
             "liquidity_crunch_2sd","value_crash_2sd","defense_shock_2sd","regime_shock_2sd"),
  factor  =c("Intercept","Intercept","x_f_momentum","x_f_size","x_f_liquidity","x_f_value",
             "x_f_defense","x_f_regime"),
  shock_raw=c(-0.05,-0.10,NA,NA,NA,NA,NA,NA))
SC[is.na(shock_raw), shock_raw := -2*sqrt(diag(OM)[factor])]
SC[, book_ret := mapply(cond_shock, factor, shock_raw)]
SC[, shock_pct := round(shock_raw*100,2)][, book_pct := round(book_ret*100,2)]
print(SC[, .(scenario, factor, shock_pct, book_pct)])

## ── STRESS 3: 회전율/비용 ───────────────────────────────────────────────────
TO <- R4$TO
to2 <- mean(TO$to)*12*2
cat(sprintf("[stress:turnover] two-way ann turnover %.2f x | cost drag 15bps %.2f pct | 30bps %.2f pct | 45bps %.2f pct\n",
    to2, to2*0.0015*100, to2*0.0030*100, to2*0.0045*100))
cat(sprintf("[stress:turnover] traded-leg edge: mean gap %.4f/mo (t %.2f) | trade-timing risk %.2f pct ann\n",
    mean(TO$gap,na.rm=TRUE), mean(TO$gap,na.rm=TRUE)/(sd(TO$gap,na.rm=TRUE)/sqrt(sum(!is.na(TO$gap)))),
    sd(TO$to*TO$gap,na.rm=TRUE)*sqrt(12)*100))
## 유동성: book 소화기간 (일 거래대금 10% 참여, book 100억 가정 진단)
liq <- R3$ADV[Ticker %in% bk]
cat(sprintf("[liquidity] book adv20 median %.3e KRW  min %.3e  names<5e8: %d\n",
    median(liq$adv), min(liq$adv), sum(liq$adv<5e8)))
DTT <- list()
for (aum in c(1e10,5e10,1e11)) {
  dtt <- (aum/length(bk))/(0.10*liq$adv)
  DTT[[as.character(aum)]] <- list(aum=aum, median_days=median(dtt), max_days=max(dtt), n_gt5=sum(dtt>5))
  cat(sprintf("   AUM %.0f eok: median days-to-trade %.2f  max %.2f  names>5d: %d\n",
      aum/1e8, median(dtt), max(dtt), sum(dtt>5)))
}

## ── CROWDING (Acadian 2026) ────────────────────────────────────────────────
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date:=as.Date(Date)]
FAMS <- R1$FAMS
FE <- melt(U[, c("Ticker", paste0("x_f_",FAMS)), with=FALSE], id.vars="Ticker",
           variable.name="factor_name", value.name="exposure")
FE[, factor_name := sub("^x_f_","",as.character(factor_name))]
bmk <- RAW[Date==as.Date("2026-08-28") & (K200==1|KQ150==1)]$Ticker
CR <- as.data.table(crowding_score_per_factor(FE, "2026-08-28", RAW, benchmark_tickers=bmk, top_n=25L))
print(CR[order(-crowding_score)])
CR3 <- NULL
FZp <- as.data.table(read_parquet(file.path(S,"p1s_family_z_panel.parquet")))
d3 <- as.Date("2026-05-30")
d3 <- max(FZp$Date[FZp$Date <= as.Date("2026-05-31")])
FE3 <- FZp[Date==d3, .(Ticker, factor_name=family, exposure=z_fam)]
CR3 <- as.data.table(crowding_score_per_factor(FE3, as.character(d3), RAW, benchmark_tickers=bmk, top_n=25L))
CMP <- merge(CR[,.(factor_name, cs_now=crowding_score)], CR3[,.(factor_name, cs_3m=crowding_score)], by="factor_name")
CMP[, delta_3m := round(cs_now-cs_3m,4)]
print(CMP[order(-delta_3m)])

saveRDS(list(TAIL=TAIL, STR=STR, SC=SC, CR=CR, CMP=CMP, sig_m=sig_m, DTT=DTT,
             mdd=MDDv, cdar95=CDaR95,
             bear=list(n=nrow(PRb), strat=mean(PRb$ret_net), bench=mean(PRb$benchmark_ret),
             active=mean(PRb$active)), liq=liq, to2=to2, ea5=ea5, ea1=ea1,
             act_hill=hill(a)), file.path(O,"r5_tail.rds"))
cat("[done]\n")
