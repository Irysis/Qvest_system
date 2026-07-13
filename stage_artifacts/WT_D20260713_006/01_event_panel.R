# R22 WT-D20260713_006 Step 01 — build composite adverse-event panel
suppressMessages({library(arrow); library(data.table)})
arrow::set_io_thread_count(2); setDTthreads(1)
OUT <- "stage_artifacts/WT_D20260713_006"
ym_add <- function(ym, k){ y<-ym%/%100; m<-ym%%100; t<-(y*12+(m-1))+k; (t%/%12)*100 + (t%%12)+1 }

rd <- as.data.table(read_parquet(".cache/rawdata.parquet",
   col_select=c("Date","Ticker","UnfaithfulDisc","AdminStock","TradingHalt","K200","KQ150","Size","Vol","Close")))
rd[, Date:=as.Date(Date)]
setorder(rd, Ticker, Date)
data_end <- max(rd$Date)
rd[, ym := as.integer(format(Date,"%Y%m"))]

# ---- (1) Long TradingHalt: daily runs >=20 consecutive trading days ----
rd[, th := as.integer(!is.na(TradingHalt) & TradingHalt>0)]
# run id per ticker
rd[, runid := rleid(th), by=Ticker]
haltruns <- rd[th==1, .(len=.N, start=min(Date), start_ym=min(ym)), by=.(Ticker, runid)]
longhalt <- haltruns[len>=20]
# onset month = start month of a qualifying long-halt run
lh_onset <- unique(longhalt[, .(Ticker, ev_ym=start_ym, type="LongHalt")])
cat("[LongHalt] qualifying runs>=20d:", nrow(longhalt), " distinct onset ticker-months:", nrow(lh_onset), "\n")

# ---- (2) UnfaithfulDisc / AdminStock onsets (monthly 0->1) ----
mflag <- rd[, .(ud=as.integer(any(UnfaithfulDisc>0,na.rm=T)),
                ad=as.integer(any(AdminStock>0,na.rm=T))), by=.(Ticker,ym)]
setorder(mflag, Ticker, ym)
mflag[, ud_prev := shift(ud,1), by=Ticker]
mflag[, ad_prev := shift(ad,1), by=Ticker]
ud_onset <- mflag[ud==1 & (is.na(ud_prev)|ud_prev==0), .(Ticker, ev_ym=ym, type="UnfaithfulDisc")]
ad_onset <- mflag[ad==1 & (is.na(ad_prev)|ad_prev==0), .(Ticker, ev_ym=ym, type="AdminStock")]
cat("[UnfaithfulDisc] onsets:", nrow(ud_onset), "  [AdminStock] onsets:", nrow(ad_onset), "\n")

# ---- (3) Delisting: last obs < data_end-180d ----
lo <- rd[, .(last=max(Date), last_ym=max(ym), n=.N), by=Ticker]
lo[, delisted := last < (data_end-180)]
del_onset <- lo[delisted==TRUE, .(Ticker, ev_ym=last_ym, type="Delisting")]
cat("[Delisting] events:", nrow(del_onset), "\n")

# ---- Combine all event onsets ----
events <- rbindlist(list(ud_onset, ad_onset, lh_onset, del_onset), use.names=TRUE)
events <- unique(events)
cat("[ALL] total event onsets (ticker,ym,type):", nrow(events),
    " distinct ticker-months with any event:", uniqueN(events[,.(Ticker,ev_ym)]),"\n")
# per-type
print(events[, .N, by=type][order(-N)])

# ---- Build monthly stock-level attributes (Size, tier, liq) for controls ----
rd[, dollar := Vol*Close]
attr_m <- rd[, .(Size=last(Size), K200=as.integer(any(K200>0,na.rm=T)),
                 KQ150=as.integer(any(KQ150>0,na.rm=T)),
                 adv=mean(dollar,na.rm=T)), by=.(Ticker,ym)]
saveRDS(events, file.path(OUT,"events.rds"))
saveRDS(attr_m, file.path(OUT,"attr_m.rds"))
saveRDS(list(data_end=data_end, ym_max=as.integer(format(data_end,"%Y%m"))), file.path(OUT,"meta.rds"))
cat("[DONE] event panel saved.\n")
