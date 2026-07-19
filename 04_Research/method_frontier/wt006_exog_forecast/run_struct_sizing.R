# run_struct_sizing.R — axis structural_multisleeve, sub-branch: ML/uncertainty-aware SIZING
# On the momentum top-25 picks, does non-EW weighting (inverse-vol / conviction / uncertainty
# down-weight) beat EW in cap-w PORT_t or calmar? (project-uncertainty-aware-selection wall +
# EW=sizing ceiling prior — measure at stock layer to close the sub-branch.)
suppressMessages({library(data.table);library(arrow);library(PerformanceAnalytics);library(xts)})
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
OUT <- "04_Research/method_frontier/wt006_exog_forecast"

UNIV <- .FAM[(K200==1 | KQ150==1)][Date %in% .Rg$Date]
# apply liq filter explicitly so weighted picks == canonical universe
LQ <- .LQg[, .(Date,Ticker,adv)]
UNIV <- merge(UNIV, LQ, by=c("Date","Ticker"), all.x=TRUE)
UNIV <- UNIV[is.na(adv) | adv >= 2e8]
UNIV <- UNIV[Date %in% .oos_dates]

# momentum top-25 per date
setorder(UNIV, Date, -momentum)
PICKS <- UNIV[is.finite(momentum), head(.SD, 25), by=Date]

wmeasure <- function(w_dt, label){
  r <- weighted_screen_bt(w_dt, .Rg, .BMg, cost_bps_oneway=15)
  pr <- as.data.table(r$period_returns)
  pr2 <- copy(pr); pr2[, active := ret_net - benchmark_ret]
  cal <- .calmar_of(pr[, .(date, ret_net)])
  oos <- .oos_ret_of(pr2)
  data.table(label=label, n=r$n_months, port_t=round(r$portfolio_alpha_t_nw_lag3,3),
             net_sr=round(r$net_sr,3), calmar=round(cal,3), oos_ret=round(oos,3),
             turnover=round(r$turnover_annual,2))
}

# weighting schemes on the SAME 25 picks
res <- rbindlist(list(
  wmeasure(PICKS[, .(Date,Ticker,w=1)], "EW (reference)"),
  # inverse-vol proxy: higher low_vol z = lower vol => higher weight (softmax on low_vol z)
  wmeasure(PICKS[, .(Date,Ticker,w=exp(pmin(pmax(low_vol,-3),3)))], "invvol_softmax(low_vol z)"),
  # conviction: weight by momentum strength (softmax)
  wmeasure(PICKS[, {z<-momentum; .(Ticker=Ticker, w=exp(pmin(pmax(z-mean(z),-3),3)))}, by=Date], "conviction_softmax(mom)"),
  # uncertainty down-weight: larger cap = more certain => weight ∝ sqrt(Size) (cap-tilt sizing)
  wmeasure(PICKS[, .(Date,Ticker,w=sqrt(pmax(Size,1)))], "cap_sqrt_size"),
  # uncertainty down-weight via low dispersion proxy: weight ∝ 1/(1+|value|+|size|) idiosyncratic — skip; use quality as quality-certainty
  wmeasure(PICKS[, .(Date,Ticker,w=exp(pmin(pmax(quality,-3),3)))], "quality_softmax")
), fill=TRUE)

cat("\n===== SIZING A/B on momentum top-25 (cap-w KOSPI200, 15bps) =====\n")
print(res)
cat(sprintf("\nEW is the reference; sizing 'promising' only if PORT_t or calmar materially > EW.\n"))
fwrite(res, file.path(OUT,"struct_sizing_results.csv"))
saveRDS(res, file.path(OUT,"struct_sizing_results.rds"))
cat("[saved] struct_sizing_results.{csv,rds}\n")
