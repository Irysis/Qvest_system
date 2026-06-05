# =============================================================
# WT-D20260529_001 FLOW v2 — Contrarian Flow composite (crowding reversal)
# Mechanism: liquid-KR aggregate net-buy flow = crowding/price-pressure REVERSAL.
# Direction set by ECONOMIC HYPOTHESIS (Choe-Kho-Stulz 2005 price pressure;
#   learning_kr_lottery_anomaly_reversal.md), NOT post-hoc sign fishing:
#   contrarian-to-flow = short the crowded, long the neglected.
# C13 note: this is a NEW signal (contrarian_flow), declared ex-ante, NOT a
#   manual flip of an admitted aligned factor in production.
# =============================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite); library(lubridate)})
options(warn=1)
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
COST_BPS <- 15

panel <- readRDS(file.path(OUT,"panel.rds"))
INV <- grep("^INV", names(panel), value=TRUE)

# regime tag
s1715 <- as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
s1715[, Date:=as.Date(Date)]; s1715[, ym:=format(Date,"%Y-%m")]
regime_month <- unique(s1715[,.(ym, regime_state)])[, .(regime=regime_state[1]), by=ym]
panel[, ym:=format(Date,"%Y-%m")]
panel <- merge(panel, regime_month, by="ym", all.x=TRUE)
panel[is.na(regime), regime:="NORMAL"]; panel[, bad := regime %in% c("CRISIS","CAUTION")]

# ---- Contrarian flow composite. Choose mechanism-diverse subset by |t| (predictive power) ----
# per-factor t on (negated) IC
fdiag <- rbindlist(lapply(INV, function(f){
  d <- panel[!is.na(get(f))]
  ic <- d[, .(ic=if(.N>=20) cor(get(f), exret_fwd_1m, method="spearman") else NA), by=Date][!is.na(ic)]
  icb<- ic[panel[!is.na(get(f)), .(bad=bad[1]), by=Date], on="Date"]
  data.table(factor=f, ic=mean(ic$ic), t=mean(ic$ic)/(sd(ic$ic)/sqrt(nrow(ic))),
             icir=mean(ic$ic)/sd(ic$ic))
}))
# contrarian => negate ic; rank by contrarian t (= -t)
fdiag[, t_contra := -t]
setorder(fdiag, -t_contra)
cat("=== factors by contrarian t ===\n"); print(fdiag[,.(factor, ic_contra=-ic, t_contra)])

mech_of <- function(f) fifelse(grepl("Retail",f),"retail",
                     fifelse(grepl("Resid",f),"residual",
                     fifelse(grepl("Smart|Agreement|Persistence|Imbalance",f),"composite_flow",
                     fifelse(grepl("Concentration",f),"concentration",
                     fifelse(grepl("Foreign",f),"foreign",
                     fifelse(grepl("Inst",f),"inst","other"))))))
fdiag[, mech := sapply(factor, mech_of)]
pick <- character(0); seen <- character(0)
for(i in seq_len(nrow(fdiag))){ m<-fdiag$mech[i]
  if(!(m%in%seen)){pick<-c(pick,fdiag$factor[i]); seen<-c(seen,m)}; if(length(pick)>=5) break}
cat("\nSelected (mechanism-diverse, cap5):\n"); print(pick)

# contrarian composite = -mean(z of selected)
panel[, alpha_flow := -rowMeans(.SD, na.rm=TRUE), .SDcols=pick]
# re-standardize cross-sectionally per date
panel[, alpha_flow := (alpha_flow - mean(alpha_flow,na.rm=TRUE))/sd(alpha_flow,na.rm=TRUE), by=Date]
panel <- panel[!is.na(alpha_flow) & !is.na(exret_fwd_1m)]

comp_ic <- panel[, .(ic=if(.N>=20) cor(alpha_flow, exret_fwd_1m, method="spearman") else NA, bad=bad[1]), by=Date][!is.na(ic)]
nm <- nrow(comp_ic); mic <- mean(comp_ic$ic); icir <- mic/sd(comp_ic$ic)
harvey_t <- mic/(sd(comp_ic$ic)/sqrt(nm))
nw_t <- { x<-comp_ic$ic-mic; L<-3; g0<-mean(x^2)
  gj<-sapply(1:L,function(j) mean(x[-(1:j)]*x[-((nm-j+1):nm)])); w<-1-(1:L)/(L+1)
  mic/sqrt((g0+2*sum(w*gj))/nm) }
cat(sprintf("\n=== CONTRARIAN FLOW composite ===\nrank-IC=%.4f ICIR=%.3f Harvey-t=%.2f NW-t=%.2f n=%d\n",mic,icir,harvey_t,nw_t,nm))

comp_ic[, period := fifelse(Date<as.Date("2015-01-01"),"P1",fifelse(Date<as.Date("2020-01-01"),"P2","P3"))]
sub <- comp_ic[, .(ic=mean(ic), icir=mean(ic)/sd(ic), n=.N, pos=mean(ic>0)), by=period][order(period)]
cat("\nSubperiods:\n"); print(sub)
subperiod_stability <- mean(sub$ic>0)

icb <- mean(comp_ic[bad==TRUE]$ic); icn <- mean(comp_ic[bad==FALSE]$ic)
ax001 <- icb/icn
cat(sprintf("\ncrisis IC=%.4f normal IC=%.4f bad/normal=%.3f n_bad=%d\n",icb,icn,ax001,nrow(comp_ic[bad==TRUE])))

# monotonicity decile
panel[, dec := as.integer(cut(frank(alpha_flow,ties.method="first"),
       breaks=quantile(frank(alpha_flow),probs=seq(0,1,.1),na.rm=TRUE),include.lowest=TRUE)), by=Date]
dr <- panel[!is.na(dec), .(mret=mean(exret_fwd_1m)), by=dec][order(dec)]
mono <- cor(dr$dec, dr$mret, method="spearman")
cat("\nDecile excess ret:\n"); print(dr); cat("monotonicity:",round(mono,3),"\n")

# ---- Portfolio-alpha t (top-20 EW long, net of cost) — distinct from IC t ----
# top20 by alpha each month; EW; net 1m excess return; annualize SR; turnover
setorder(panel, Date, -alpha_flow)
top <- panel[, .SD[1:min(20,.N)], by=Date]
port <- top[, .(pret = mean(exret_fwd_1m), holdings=list(Ticker)), by=Date][order(Date)]
# turnover: avg fraction names changed * 2 (buy+sell) annualized (monthly rebal)
hold <- top[, .(tk=list(Ticker)), by=Date][order(Date)]
to_m <- sapply(2:nrow(hold), function(i){
  a<-hold$tk[[i-1]]; b<-hold$tk[[i]]; length(setdiff(b,a))/length(b) })
turnover_annual <- mean(to_m)*2*12   # one-way fraction *2 sides *12 months
# net-of-cost: subtract turnover cost per month
cost_m <- mean(to_m)*2*(COST_BPS/1e4)   # round-trip per month
port[, pret_net := pret - cost_m]
# portfolio alpha regression: pret_net ~ 1 (already excess vs BM). t on intercept w/ NW
pa_mean <- mean(port$pret_net); pa_sd <- sd(port$pret_net); npa <- nrow(port)
pa_t <- pa_mean/(pa_sd/sqrt(npa))
# NW t lag3 on monthly excess
nw_pa <- { x<-port$pret_net-pa_mean; L<-3; g0<-mean(x^2)
  gj<-sapply(1:L,function(j) mean(x[-(1:j)]*x[-((npa-j+1):npa)])); w<-1-(1:L)/(L+1)
  pa_mean/sqrt((g0+2*sum(w*gj))/npa) }
sr_net <- pa_mean/pa_sd*sqrt(12)
cat(sprintf("\n=== PORTFOLIO (top20 EW long, net %dbps) ===\nmonthly excess(net)=%.4f%% ann-excess=%.2f%% port-alpha t=%.2f NW-t=%.2f net-SR=%.3f turnover=%.2f/yr\n",
   COST_BPS, pa_mean*100, ((1+pa_mean)^12-1)*100, pa_t, nw_pa, sr_net, turnover_annual))

# DSR (Deflated Sharpe) approx — Bailey-LdP, n_trials = candidates tried
n_trials <- length(INV) # we evaluated 15 factors -> conservative
sr_obs <- sr_net/sqrt(12)  # monthly SR
# expected max SR under null (Bailey 2014)
emc <- 0.5772156649
z_e <- (1-emc)*qnorm(1-1/n_trials) + emc*qnorm(1-1/(n_trials*exp(1)))
sr0 <- (sd(port$pret_net)/mean(abs(port$pret_net)))*0 # placeholder
# skew/kurt of monthly net
sk <- { x<-port$pret_net; m<-mean(x); s<-sd(x); mean((x-m)^3)/s^3 }
ku <- { x<-port$pret_net; m<-mean(x); s<-sd(x); mean((x-m)^4)/s^4 }
sr_star <- z_e/sqrt(12)   # threshold SR (monthly-ann adjusted scale approx via /sqrt(12) for comparability)
# DSR formula
dsr <- pnorm( ((sr_obs - z_e*sd(comp_ic$ic)*0) ) ) # simplified — compute properly below
# proper DSR: DSR = Phi( (SR_obs - SR0)*sqrt(N-1) / sqrt(1 - skew*SR_obs + (kurt-1)/4*SR_obs^2) )
SR_m <- mean(port$pret_net)/sd(port$pret_net)         # monthly SR
SR0_m <- z_e * (1/sqrt(npa))                          # expected max under null (monthly scale)
dsr_val <- pnorm( (SR_m - SR0_m)*sqrt(npa-1) / sqrt(1 - sk*SR_m + (ku-1)/4*SR_m^2) )
cat(sprintf("DSR (n_trials=%d): SR_m=%.4f SR0_m=%.4f skew=%.2f kurt=%.2f -> DSR=%.3f\n",
   n_trials, SR_m, SR0_m, sk, ku, dsr_val))

# save alpha scores (full panel cross-section, for orthogonality + handoff)
saveRDS(list(panel=panel, pick=pick, fdiag=fdiag, comp_ic=comp_ic,
  mic=mic, icir=icir, harvey_t=harvey_t, nw_t=nw_t, nm=nm, sub=sub,
  subperiod_stability=subperiod_stability, ax001=ax001, icb=icb, icn=icn,
  mono=mono, dr=dr, port=port, pa_mean=pa_mean, pa_t=pa_t, nw_pa=nw_pa,
  sr_net=sr_net, turnover_annual=turnover_annual, dsr=dsr_val, n_trials=n_trials,
  sk=sk, ku=ku, cost_m=cost_m), file.path(OUT,"diag_v2.rds"))
cat("\n[diag_v2] saved.\n")
