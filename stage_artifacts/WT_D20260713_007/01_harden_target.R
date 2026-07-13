# R23 WT-D20260713_007 Step 01 — PIT label hardening + severity-restricted forward-12m target
# Reuse R22 events + F3 panel. Cross designation dates from disc_ck. API=0.
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
R22 <- "stage_artifacts/WT_D20260713_006"
OUT <- "stage_artifacts/WT_D20260713_007"
ym_add <- function(ym, k){ y<-ym%/%100; m<-ym%%100; t<-(y*12+(m-1))+k; (t%/%12)*100 + (t%%12)+1 }
d2ym   <- function(d){ (d%/%10000L)*100L + (d%/%100L)%%100L }   # integer yyyymmdd -> yyyymm

events <- readRDS(file.path(R22,"events.rds"))
events[, sc := sub("^A","",Ticker)]
P  <- readRDS(file.path(R22,"panels.rds")); F3 <- P$F3
ym_cut <- P$ym_cut

# ---------- (A) disc_ck designation dates ----------
dir <- "stage_artifacts/WT-D20260710_005/disc_ck"
fs  <- list.files(dir, pattern="[.]csv$", full.names=TRUE)
DISC <- rbindlist(lapply(fs, function(f) tryCatch(
  fread(f, colClasses=list(character=c("stock_code","rcept_no")), select=c("stock_code","report_nm","rcept_dt")),
  error=function(e) NULL)), fill=TRUE)
DISC[, stock_code := sprintf("%06d", as.integer(stock_code))]
DISC[, rnt := trimws(report_nm)]
DISC[, dym := d2ym(as.integer(rcept_dt))]
disc_codes <- unique(DISC$stock_code)
cat("[01] disc_ck rows:", nrow(DISC), " stocks:", length(disc_codes),
    " dym range:", paste(range(DISC$dym,na.rm=TRUE),collapse=".."),"\n")

# designation subsets (actual designation, exclude release/concern/pre-announce/non-designation)
admin_des <- DISC[grepl("관리종목지정", rnt) & !grepl("해제|우려|예고|미지정|일부", rnt),
                  .(sc=stock_code, dym, kind="AdminStock")]
unf_des   <- DISC[grepl("불성실공시법인지정", rnt) & !grepl("예고|미지정", rnt),
                  .(sc=stock_code, dym, kind="UnfaithfulDisc")]
desig <- unique(rbindlist(list(admin_des, unf_des)))
cat("[01] designation rows: Admin", nrow(admin_des), " Unfaithful", nrow(unf_des),
    " distinct sc(admin):", uniqueN(admin_des$sc), " sc(unf):", uniqueN(unf_des$sc),"\n")

# ---------- (B) harden AdminStock/UnfaithfulDisc onsets ----------
# For each flag onset (from RAWDATA), if ticker covered by disc_ck, snap to nearest designation of same kind within +-12 months.
au <- events[type %in% c("AdminStock","UnfaithfulDisc")]
au[, covered := sc %in% disc_codes]
au[, hardened_ym := ev_ym]          # default = flag onset
au[, gap_m := NA_real_]             # flag_onset - designation (months); +ve = flag LAGS designation (safe); -ve = flag LEADS (look-ahead risk)
au[, match_type := "flag_retained"]

mdiff <- function(a,b){ (a%/%100)*12 + (a%%100) - ((b%/%100)*12 + (b%%100)) }

for(i in which(au$covered)){
  k <- au$type[i]; s <- au$sc[i]; m <- au$ev_ym[i]
  cand <- desig[sc==s & kind==k]
  if(nrow(cand)==0) next
  g <- mdiff(m, cand$dym)            # flag_onset - designation
  j <- which.min(abs(g))
  if(abs(g[j]) <= 12){
    au$hardened_ym[i] <- cand$dym[j]
    au$gap_m[i]       <- g[j]
    au$match_type[i]  <- "hardened"
  }
}
cat("\n[01] hardening summary (AdminStock/UnfaithfulDisc onsets):\n")
print(au[, .N, by=.(type, match_type)][order(type, match_type)])
cat("[01] covered ticker-events:", sum(au$covered), "/", nrow(au),
    " hardened(matched<=12m):", sum(au$match_type=="hardened"),"\n")
cat("[01] gap_m (flag_onset - designation, months) distribution among hardened:\n")
gm <- au[match_type=="hardened", gap_m]
if(length(gm)>0){
  print(summary(gm)); cat("   quantiles:", paste(round(quantile(gm, c(0,.1,.25,.5,.75,.9,1)),2),collapse=","),"\n")
  cat("   share flag LEADS designation (gap<0, look-ahead risk):", round(mean(gm< 0),3),
      " | gap==0 (same month):", round(mean(gm==0),3),
      " | flag LAGS (gap>0, safe):", round(mean(gm>0),3),"\n")
}

# ---------- (C) build severity event sets: PURE-FLAG and HARDENED ----------
del <- events[type=="Delisting", .(sc, ev_ym, type)]
# pure-flag severity onsets
sev_flag <- rbindlist(list(
  au[, .(sc, ev_ym, type)],
  del
), use.names=TRUE)
# hardened severity onsets (admin/unf use hardened_ym)
sev_hard <- rbindlist(list(
  au[, .(sc, ev_ym=hardened_ym, type)],
  del
), use.names=TRUE)
sev_flag <- unique(sev_flag); sev_hard <- unique(sev_hard)
cat("\n[01] severity onset rows: pure-flag", nrow(sev_flag), " hardened", nrow(sev_hard),"\n")

# ---------- (D) forward-12m target attach onto F3 panel ----------
F3[, sc := sub("^A","",Ticker)]
attach_target <- function(fp, sev){
  fp <- copy(fp)
  fp[, lo := ym_add(ym,1)]; fp[, hi := ym_add(ym,12)]
  evset <- unique(sev[, .(sc, ev_ym)]); setkey(evset, sc)
  j <- evset[fp, on="sc", allow.cartesian=TRUE, nomatch=NULL]
  hit <- j[ev_ym>=lo & ev_ym<=hi, .(E=1L), by=.(sc,ym)]
  fp <- merge(fp, hit, by=c("sc","ym"), all.x=TRUE)
  fp[is.na(E), E:=0L]; fp[, c("lo","hi"):=NULL]
  fp
}
# F3 panel already has old E (union). drop it, recompute severity E.
F3base <- copy(F3); F3base[, E := NULL]
Fhard <- attach_target(F3base, sev_hard)
Fflag <- attach_target(F3base, sev_flag)

cat("\n[01] target base rates on F3 panel:\n")
cat("   hardened : base_rate=", round(mean(Fhard$E),5), " total E=", sum(Fhard$E),
    " | worst-decile n=", Fhard[pred==1,.N], " worst-decile E=", Fhard[pred==1,sum(E)], "\n")
cat("   pure-flag: base_rate=", round(mean(Fflag$E),5), " total E=", sum(Fflag$E),
    " | worst-decile n=", Fflag[pred==1,.N], " worst-decile E=", Fflag[pred==1,sum(E)], "\n")

saveRDS(list(Fhard=Fhard, Fflag=Fflag, au=au, sev_hard=sev_hard, sev_flag=sev_flag,
             ym_cut=ym_cut, disc_codes=disc_codes, desig=desig),
        file.path(OUT,"target.rds"))
cat("[01] DONE — target.rds saved\n")
