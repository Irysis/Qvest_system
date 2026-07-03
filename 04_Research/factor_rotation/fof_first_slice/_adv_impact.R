suppressMessages({ library(data.table); library(arrow) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
DIR <- "04_Research/factor_rotation/fof_first_slice"
rp <- function(f) as.data.table(read_parquet(file.path(DIR, f)))

# Realistic cost = spread/2 + impact. KR small caps: half-spread ~15-40bps + impact.
# Impact model (square-root, standard): impact_bps = k * sqrt(participation) where
#   participation = trade_notional_per_name / daily_adv, k~=10 (10bps at 100% ADV, conservative-mild).
# We size trade per name = (book_AUM/25) * (fraction traded that name).
# For a given monthly traded weight dw on a name, trade_notional = book_AUM * dw.
# We report: for book AUM levels, the realized round-trip cost the strategy pays,
# then translate to breakeven port_t.

univ <- "allliq"
sc  <- rp(sprintf("kns_scores_L2_%s.parquet", univ))
ret <- rp(sprintf("kns_ret_%s.parquet", univ))[is.finite(Ret_1m)]
liq <- rp(sprintf("kns_liq_%s.parquet", univ))
sc  <- sc[Date <= max(ret$Date)]
S <- merge(sc, liq[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
S <- S[is.na(adv)|adv>=2e8]
setorder(S, Date, -score)
W <- S[, {n<-min(25L,.N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n,n))}, by=Date]
W <- merge(W, liq[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)

dts <- sort(unique(W$Date))
# per-month per-name dw
prev <- data.table(Ticker=character(0), wp=numeric(0))
allrows <- list()
for (i in seq_along(dts)) {
  cur <- W[Date==dts[i], .(Ticker,w,adv)]
  m <- merge(cur, prev, by="Ticker", all=TRUE)
  m[is.na(w),w:=0]; m[is.na(wp),wp:=0]
  m[, dw := abs(w-wp)]
  m <- merge(m[,.(Ticker,dw)], cur[,.(Ticker,adv)], by="Ticker", all.x=TRUE)
  m[, Date := dts[i]]
  allrows[[i]] <- m[dw>0]
  prev <- cur[,.(Ticker,wp=w)]
}
D <- rbindlist(allrows, fill=TRUE)
D <- D[!is.na(adv)]  # need adv to size impact

# For book AUM, compute cost_bps paid per month (weighted by dw), avg over months.
# trade_notional_name = AUM * dw ; participation = trade_notional / (adv * exec_days)
# assume execution spread over 3 trading days (TWAP) to be generous.
exec_days <- 3
k_impact <- 10        # sqrt-impact coefficient (bps at 100% of daily ADV) - mild/standard
half_spread_bps <- 20 # KR small-cap half-spread, one-way (conservative-moderate)

realized_cost_bps <- function(AUM) {
  d <- copy(D)
  d[, trade_notional := AUM * dw]
  d[, part := trade_notional / (adv * exec_days)]
  d[, impact := k_impact * sqrt(part)]
  d[, cost_name := half_spread_bps + impact]     # one-way bps
  # portfolio one-way cost this month = sum(dw*cost_name)/sum(dw) weighted, but total cost
  # in return terms = sum(dw * cost_name/1e4). Report as effective one-way bps = sum(dw*cost)/sum(dw)
  mo <- d[, .(eff_bps = sum(dw*cost_name)/sum(dw), maxpart=max(part), medpart=median(part)), by=Date]
  list(mean_eff_oneway_bps = mean(mo$eff_bps),
       median_eff_oneway_bps = median(mo$eff_bps),
       mean_maxpart = mean(mo$maxpart), mean_medpart = mean(mo$medpart))
}

for (AUM in c(1e9, 5e9, 1e10, 3e10, 5e10)) {
  r <- realized_cost_bps(AUM)
  cat(sprintf("AUM=%.0e KRW: eff one-way cost mean=%.1fbps median=%.1fbps | mean max-name participation=%.2f (of 3-day ADV) med-name=%.3f\n",
      AUM, r$mean_eff_oneway_bps, r$median_eff_oneway_bps, r$mean_maxpart, r$mean_medpart))
}
cat("(half_spread=20bps one-way + sqrt-impact k=10bps@100%ADV, TWAP 3 days)\n")
cat("IMPACT_DONE\n")
