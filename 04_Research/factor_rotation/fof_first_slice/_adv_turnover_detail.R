suppressMessages({ library(data.table); library(arrow) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
DIR <- "04_Research/factor_rotation/fof_first_slice"
rp <- function(f) as.data.table(read_parquet(file.path(DIR, f)))

detail <- function(univ) {
  sc  <- rp(sprintf("kns_scores_L2_%s.parquet", univ))
  ret <- rp(sprintf("kns_ret_%s.parquet", univ))[is.finite(Ret_1m)]
  liq <- rp(sprintf("kns_liq_%s.parquet", univ))
  sc  <- sc[Date <= max(ret$Date)]
  S <- merge(sc, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv) | adv >= 2e8]
  setorder(S, Date, -score)
  W <- S[, {n<-min(25L,.N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n,n))}, by=Date]
  dts <- sort(unique(W$Date))
  ov <- numeric(0); trd <- numeric(0); nheld <- integer(0)
  prev <- character(0)
  for (i in seq_along(dts)) {
    cur <- W[Date==dts[i]]
    curT <- cur$Ticker
    nheld <- c(nheld, length(curT))
    if (i>1) {
      ov <- c(ov, length(intersect(curT, prev))/length(curT))
      m <- merge(cur[,.(Ticker,w)], data.table(Ticker=prev, wp=1/length(prev)),
                 by="Ticker", all=TRUE)
      m[is.na(w),w:=0]; m[is.na(wp),wp:=0]
      trd <- c(trd, sum(abs(m$w-m$wp)))
    }
    prev <- curT
  }
  # median adv of held names (KRW)
  heldadv <- merge(W, liq[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)$adv
  cat(sprintf("[%s] n_months=%d  mean_names_held=%.1f\n", univ, length(dts), mean(nheld)))
  cat(sprintf("  monthly name-overlap: mean=%.3f median=%.3f (fraction of 25 retained)\n", mean(ov), median(ov)))
  cat(sprintf("  monthly traded (sum|dw|): mean=%.3f median=%.3f -> annual %.2fx\n", mean(trd), median(trd), mean(trd)*12))
  cat(sprintf("  median names replaced/month = %.1f of 25\n", (1-median(ov))*25))
  cat(sprintf("  held-name adv (KRW): median=%.3e p25=%.3e p10=%.3e min=%.3e\n",
      median(heldadv,na.rm=TRUE), quantile(heldadv,.25,na.rm=TRUE),
      quantile(heldadv,.10,na.rm=TRUE), min(heldadv,na.rm=TRUE)))
  # Fraction of held-name adv that is "small" (< 1e9 = 1bn KRW ~ thin)
  cat(sprintf("  held names with adv<5e8: %.1f%%   adv<1e9: %.1f%%\n",
      100*mean(heldadv<5e8,na.rm=TRUE), 100*mean(heldadv<1e9,na.rm=TRUE)))
}
detail("allliq"); detail("allclean")
cat("TURN_DETAIL_DONE\n")
