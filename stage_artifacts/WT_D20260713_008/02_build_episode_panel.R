# R24 Step 02 — build EPISODE-LEVEL panel (frozen prereg e13d4251...). API=0.
# One row per (Ticker, fy) filing episode. Controls @ rcept_ym. Hardened severity outcome in [rcept_ym+1, rcept_ym+12].
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260713_008")
DISCDIR <- file.path(ROOT,"stage_artifacts/WT-D20260710_005/disc_ck")
d2ym  <- function(d){ (as.integer(d)%/%10000L)*100L + (as.integer(d)%/%100L)%%100L }
ym_add<- function(ym,k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }
mdiff <- function(a,b){ (a%/%100L)*12L + (a%%100L) - ((b%/%100L)*12L + (b%%100L)) }

S <- readRDS(file.path(OUT,"census.rds"))
events <- S$events; attr_m <- S$attr_m; inv <- S$inv; measurable <- S$measurable
data_end_ym <- S$meta$ym_max
cat("[02] data_end_ym:", data_end_ym, "\n")

## (A) per-ticker Market (KOSPI/KOSDAQ) from rawdata — light read ------------
# NOTE: Market column labels only "KOSPI" (non-NA); KOSDAQ rows are NA. So KOSPI iff KOSPI-rows >= NA-rows.
mk <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Ticker","Market")))
mkmap <- mk[, .(n_kospi=sum(Market=="KOSPI",na.rm=TRUE), n_na=sum(is.na(Market))), by=Ticker]
mkmap[, KOSPI := as.integer(n_kospi >= n_na)]
cat("[02] Market map tickers:", nrow(mkmap), " KOSPI:", sum(mkmap$KOSPI), " KOSDAQ:", sum(mkmap$KOSPI==0),"\n")
mkmap <- mkmap[, .(Ticker, KOSPI)]
rm(mk); gc()

## (B) disc_ck designation dates (reuse R23 hardening) ----------------------
fs  <- list.files(DISCDIR, pattern="[.]csv$", full.names=TRUE)
DISC <- rbindlist(lapply(fs, function(f) tryCatch(
  fread(f, colClasses=list(character=c("stock_code","rcept_no")), select=c("stock_code","report_nm","rcept_dt")),
  error=function(e) NULL)), fill=TRUE)
DISC[, stock_code := sprintf("%06d", as.integer(stock_code))]
DISC[, rnt := trimws(report_nm)]; DISC[, dym := d2ym(rcept_dt)]
disc_codes <- unique(DISC$stock_code)
admin_des <- DISC[grepl("관리종목지정", rnt) & !grepl("해제|우려|예고|미지정|일부", rnt), .(sc=stock_code, dym, kind="AdminStock")]
unf_des   <- DISC[grepl("불성실공시법인지정", rnt) & !grepl("예고|미지정", rnt), .(sc=stock_code, dym, kind="UnfaithfulDisc")]
desig <- unique(rbindlist(list(admin_des, unf_des)))
cat("[02] designation rows: Admin", nrow(admin_des), " Unf", nrow(unf_des), "\n")

## (C) harden Admin/Unf onsets; build severity onset sets -------------------
au <- events[type %in% c("AdminStock","UnfaithfulDisc")]
au[, covered := sc %in% disc_codes]; au[, hardened_ym := ev_ym]; au[, gap_m := NA_real_]; au[, match_type := "flag_retained"]
for(i in which(au$covered)){
  k<-au$type[i]; s<-au$sc[i]; m<-au$ev_ym[i]; cand<-desig[sc==s & kind==k]
  if(nrow(cand)==0) next
  g<-mdiff(m, cand$dym); j<-which.min(abs(g))
  if(abs(g[j])<=12){ au$hardened_ym[i]<-cand$dym[j]; au$gap_m[i]<-g[j]; au$match_type[i]<-"hardened" }
}
del <- events[type=="Delisting", .(sc, ev_ym, type)]
sev_flag <- unique(rbindlist(list(au[, .(sc, ev_ym, type)], del), use.names=TRUE))
sev_hard <- unique(rbindlist(list(au[, .(sc, ev_ym=hardened_ym, type)], del), use.names=TRUE))
cat("[02] severity onsets: pure-flag", nrow(sev_flag), " hardened", nrow(sev_hard),
    " | hardened matched:", sum(au$match_type=="hardened"), "/", nrow(au), "\n")

## (D) episode panel from inv (measurable universe) -------------------------
E0 <- inv[Ticker %in% paste0("A",measurable)]
E0[, sc := sub("^A","",Ticker)]
E0 <- E0[, .(Ticker, sc, fy, rcept_ym, delay_d)]
# FROZEN PRIMARY treatment: per-fy p90 quantile AND delay>0 (prereg e13d4251)
E0[, thr90 := quantile(delay_d, 0.90, type=7, na.rm=TRUE), by=fy]
E0[, worst_decile_late := as.integer(delay_d >= thr90 & delay_d > 0)]
# DIAGNOSTIC (non-authoritative): strict per-fy top-decile by rank (frank-ceiling; matches census 299 & R23 extreme-tail intent)
E0[, dec_rank := {r<-frank(delay_d,ties.method="average"); ceiling(r/.N*10)}, by=fy]; E0[dec_rank>10, dec_rank:=10L]
E0[, wd_strict := as.integer(dec_rank==10 & delay_d>0)]
# DIAGNOSTIC (non-authoritative): extreme cut delay>=30 calendar days late
E0[, late30 := as.integer(delay_d>=30)]
cat("[02] episodes:", nrow(E0),
    " | FROZEN worst_decile_late=1:", sum(E0$worst_decile_late), "(firms", uniqueN(E0[worst_decile_late==1,sc]),")",
    " | wd_strict=1:", sum(E0$wd_strict), "(firms", uniqueN(E0[wd_strict==1,sc]),")",
    " | late30=1:", sum(E0$late30), "(firms", uniqueN(E0[late30==1,sc]),")\n")

## (E) controls @ rcept_ym from attr_m --------------------------------------
attr_m[, sc := sub("^A","",Ticker)]
ctrl <- attr_m[, .(sc, ym, Size, adv, K200, KQ150)]
E0 <- merge(E0, ctrl, by.x=c("sc","rcept_ym"), by.y=c("sc","ym"), all.x=TRUE)
# fallback: if no attr at exact rcept_ym, use nearest prior month within 3m
miss <- which(is.na(E0$Size))
if(length(miss)>0){
  setkey(attr_m, sc, ym)
  for(i in miss){
    cand <- attr_m[sc==E0$sc[i] & ym<=E0$rcept_ym[i] & ym>=ym_add(E0$rcept_ym[i],-3L)]
    if(nrow(cand)>0){ r<-cand[which.max(ym)]; E0$Size[i]<-r$Size; E0$adv[i]<-r$adv; E0$K200[i]<-r$K200; E0$KQ150[i]<-r$KQ150 }
  }
}
E0 <- merge(E0, mkmap, by="Ticker", all.x=TRUE)
E0[, log_size := log(pmax(Size,1))]
E0[, log_adv  := log(pmax(adv,1))]
E0[, size_z := as.numeric(scale(log_size)), by=fy]
E0[, adv_z  := as.numeric(scale(log_adv)),  by=fy]
E0[is.na(size_z), size_z:=0]; E0[is.na(adv_z), adv_z:=0]; E0[is.na(KOSPI), KOSPI:=0]

## (F) attach forward-12m severity outcome (hardened + pure-flag) -----------
attach_E <- function(sev){
  ev <- unique(sev[, .(sc, ev_ym)]); setkey(ev, sc)
  ep <- copy(E0); ep[, lo:=ym_add(rcept_ym,1L)]; ep[, hi:=ym_add(rcept_ym,12L)]
  j <- ev[ep, on="sc", allow.cartesian=TRUE, nomatch=NULL]
  hit <- j[ev_ym>=lo & ev_ym<=hi, .(E=1L), by=.(sc,fy)]
  ep <- merge(ep, hit, by=c("sc","fy"), all.x=TRUE); ep[is.na(E),E:=0L]
  ep[, c("lo","hi"):=NULL]; ep
}
Ehard <- attach_E(sev_hard); Eflag <- attach_E(sev_flag)

## (G) censor: forward window fully observable ------------------------------
cens <- function(ep){ ep[ ym_add(rcept_ym,12L) <= data_end_ym ] }
Ehard_c <- cens(Ehard); Eflag_c <- cens(Eflag)
cat("\n[02] AFTER CENSOR (forward 12m observable):\n")
cat("   hardened: n=", nrow(Ehard_c), " base=", round(mean(Ehard_c$E),5),
    " wd_late n=", Ehard_c[worst_decile_late==1,.N], " wd_late E=", Ehard_c[worst_decile_late==1,sum(E)],
    " distinct wd firms(in-window)=", uniqueN(Ehard_c[worst_decile_late==1,sc]),"\n")
cat("   pureflag: n=", nrow(Eflag_c), " base=", round(mean(Eflag_c$E),5),
    " wd_late n=", Eflag_c[worst_decile_late==1,.N], " wd_late E=", Eflag_c[worst_decile_late==1,sum(E)],"\n")
cat("   VALIDITY GATE: distinct worst-decile-late firms in-window =",
    uniqueN(Ehard_c[worst_decile_late==1,sc]), " (>=30 required)\n")

saveRDS(list(Ehard=Ehard_c, Eflag=Eflag_c, au=au, sev_hard=sev_hard, sev_flag=sev_flag,
             data_end_ym=data_end_ym, disc_codes=disc_codes),
        file.path(OUT,"episode_panel.rds"))
cat("[02] DONE — episode_panel.rds saved\n")
