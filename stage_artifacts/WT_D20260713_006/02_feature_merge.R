# Step 02 — feature monthly panels + per-month worst decile + forward-12m target + controls
suppressMessages({library(arrow); library(data.table)})
arrow::set_io_thread_count(2); setDTthreads(1)
OUT <- "stage_artifacts/WT_D20260713_006"
ym_add <- function(ym, k){ y<-ym%/%100; m<-ym%%100; t<-(y*12+(m-1))+k; (t%/%12)*100 + (t%%12)+1 }
events <- readRDS(file.path(OUT,"events.rds"))
attr_m <- readRDS(file.path(OUT,"attr_m.rds"))
meta   <- readRDS(file.path(OUT,"meta.rds"))
ym_max <- meta$ym_max
# max decision month with full 12m forward window observable
ym_cut <- ym_add(ym_max, -12)
cat("ym_max:", ym_max, " decision-month censor cut (<=):", ym_cut, "\n")

evset <- unique(events[, .(Ticker, ev_ym)])
setkey(evset, Ticker)

# forward-12m target for a feature panel with cols (Ticker, ym)
attach_target <- function(fp){
  fp <- copy(fp)
  fp[, lo := ym_add(ym,1)]; fp[, hi := ym_add(ym,12)]
  # join events by ticker, filter window
  j <- evset[fp, on="Ticker", allow.cartesian=TRUE, nomatch=NULL]
  hit <- j[ev_ym>=lo & ev_ym<=hi, .(E=1L), by=.(Ticker,ym)]
  fp <- merge(fp, hit, by=c("Ticker","ym"), all.x=TRUE)
  fp[is.na(E), E:=0L]
  fp[, c("lo","hi"):=NULL]
  fp
}
per_month_decile <- function(fp, suspcol){
  fp <- copy(fp)
  fp[, dec := {
      n <- .N
      if(n<20L) rep(NA_integer_, n) else pmin(10L, pmax(1L, as.integer(ceiling(frank(get(suspcol), ties.method="min")/n*10))))
    }, by=ym]
  fp[, pred := as.integer(dec==10L)]   # top decile of suspect = worst
  fp
}

# ---- F1 Benford ----
b <- as.data.table(read_parquet("stage_artifacts/WT_D20260713_002/alpha_scores.parquet"))
b <- b[factor=="F-B_Benford_FSD"]
b[, ym := as.integer(format(as.Date(Date),"%Y%m"))]
b[, susp := -score]
F1 <- b[ym<=ym_cut, .(Ticker, ym, susp)]
F1 <- per_month_decile(F1, "susp"); F1 <- attach_target(F1)

# ---- F2 m1 ----
sp <- as.data.table(readRDS("stage_artifacts/WT_D20260711_002/signal_panel.rds"))
sp[, susp := m1]
F2 <- sp[ym<=ym_cut & is.finite(m1), .(Ticker, ym, susp)]
F2 <- per_month_decile(F2, "susp"); F2 <- attach_target(F2)

# ---- F3 delay ----
d <- as.data.table(read_parquet("stage_artifacts/WT_D20260713_001/alpha_scores.parquet"))
d <- d[factor=="F-B"]
d[, ym := as.integer(format(as.Date(Date),"%Y%m"))]
d[, susp := -score]
F3 <- d[ym<=ym_cut, .(Ticker, ym, susp)]
F3 <- per_month_decile(F3, "susp"); F3 <- attach_target(F3)

# ---- STACK: >=2 of D10 flags over common (Ticker,ym) ----
allf <- rbindlist(list(F1[,.(Ticker,ym,pred1=pred)], F2[,.(Ticker,ym,pred2=pred)], F3[,.(Ticker,ym,pred3=pred)]), fill=TRUE)
# merge into one row per (Ticker,ym) present in ALL three
m12 <- merge(F1[,.(Ticker,ym,p1=pred)], F2[,.(Ticker,ym,p2=pred)], by=c("Ticker","ym"))
m123 <- merge(m12, F3[,.(Ticker,ym,p3=pred)], by=c("Ticker","ym"))
m123[, nflag := rowSums(.SD, na.rm=TRUE), .SDcols=c("p1","p2","p3")]
m123[, pred := as.integer(nflag>=2)]
ST <- attach_target(m123[,.(Ticker,ym,pred)])
# continuous suspect for stack AUC = nflag (0..3)
ST <- merge(ST, m123[,.(Ticker,ym,susp=nflag)], by=c("Ticker","ym"))

# ---- attach controls ----
add_ctrl <- function(fp){
  fp <- merge(fp, attr_m, by=c("Ticker","ym"), all.x=TRUE)
  fp[, log_size := log(pmax(Size,1))]
  fp[, liq_z := as.numeric(scale(log(pmax(adv,1)))) , by=ym]
  fp[, size_z := as.numeric(scale(log_size)), by=ym]
  fp
}
F1 <- add_ctrl(F1); F2 <- add_ctrl(F2); F3 <- add_ctrl(F3); ST <- add_ctrl(ST)

saveRDS(list(F1=F1,F2=F2,F3=F3,ST=ST, ym_cut=ym_cut), file.path(OUT,"panels.rds"))
for(nm in c("F1","F2","F3","ST")){
  fp <- get(nm)
  cat(sprintf("[%s] rows=%d  months=%d  tickers=%d  base_rate=%.4f  pred1_n=%d  pred1_evrate=%.4f\n",
    nm, nrow(fp), uniqueN(fp$ym), uniqueN(fp$Ticker), mean(fp$E),
    fp[pred==1,.N], fp[pred==1, mean(E)]))
}
