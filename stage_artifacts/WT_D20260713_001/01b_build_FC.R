#==============================================================================
# WT-D20260713_001 R17 — Step 01b: rebuild F-C (ym is "YYYY-MM" string) + save panels
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WT   <- file.path(ROOT, "stage_artifacts/WT_D20260711_002"); OUT <- file.path(ROOT, "stage_artifacts/WT_D20260713_001")
ym2date <- function(ym) as.Date(sprintf("%d-%02d-01", ym%/%100L, ym%%100L))
ym_add  <- function(ym, k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }

mp <- readRDS(file.path(WT,"monthly_panel.rds")); me <- mp$me
memb <- me[K200==TRUE | KQ150==TRUE, .(Ticker, ym)]; setkey(memb, ym, Ticker)
expand_hold <- function(sig, H){
  sig <- sig[is.finite(raw)]; sig[, us := ym_add(rcept_ym, 1L)]
  rows <- sig[, { dm <- vapply(0:(H-1L), function(k) ym_add(us, k), integer(1)); .(decision_ym=dm, raw=raw, rcept_ym=rcept_ym) }, by=.(Ticker, seq_len(nrow(sig)))]
  rows[, seq_len := NULL]; setorder(rows, Ticker, decision_ym, -rcept_ym)
  rows <- rows[, .SD[1L], by=.(Ticker, decision_ym)]; rows[, .(Ticker, ym=decision_ym, raw)]
}
make_scores <- function(sig_monthly, sign){
  x <- merge(sig_monthly, memb, by=c("Ticker","ym"))
  zc <- function(v){ s<-sd(v,na.rm=TRUE); if(!is.finite(s)||s<=0) return(rep(NA_real_,length(v))); (v-mean(v,na.rm=TRUE))/s }
  x[, z := zc(raw), by=ym]; x <- x[is.finite(z)]; x[, .(Date=ym2date(ym), Ticker, score=sign*z, raw)]
}

ia <- as.data.table(read_parquet(file.path(ROOT,".cache/dart/insider_activity_hist.parquet")))
ia[, ymi := as.integer(substr(ym,1,4))*100L + as.integer(substr(ym,6,7))]   # "YYYY-MM" -> YYYYMM
ia[, yq := (ymi%/%100L)*10L + ((ymi%%100L - 1L)%/%3L + 1L)]                   # year*10 + quarter
qc <- ia[, .(cnt=sum(n_insider,na.rm=TRUE)), by=.(Ticker, yq)]
setorder(qc, Ticker, yq)
qc[, yq_idx := (yq%/%10L)*4L + (yq%%10L)]                                     # linear quarter index
qc[, cnt_lag4 := shift(cnt,4L), by=Ticker]; qc[, idx_lag4 := shift(yq_idx,4L), by=Ticker]
qc <- qc[!is.na(cnt_lag4) & (yq_idx - idx_lag4)==4L]                          # strict YoY (4 quarters)
qc[, yoy := (cnt - cnt_lag4)/(cnt_lag4 + 1)]
qc[, qend_ym := (yq%/%10L)*100L + (yq%%10L)*3L]                               # quarter-end month
fc_list <- qc[is.finite(yoy), .(Ticker, rcept_ym=qend_ym, raw=yoy)]
fc_sig <- expand_hold(fc_list, H=3L)
scores_FC <- make_scores(fc_sig, sign=-1)
write_parquet(scores_FC, file.path(OUT,"scores_FC.parquet"))
cat("[01b][F-C] scores rows:", nrow(scores_FC), " months:", uniqueN(scores_FC$Date),
    " corps:", uniqueN(scores_FC$Ticker), " raw yoy q:", paste(round(quantile(fc_list$raw,c(0,.5,.9,1)),2),collapse=","),"\n")

# save panels (13b convention)
ret_at_t  <- me[, .(Ticker, ym=ym_add(ym,-1L), Ret_1m=mret)]
bench_at_t<- mp$bench_m[, .(ym=ym_add(ym,-1L), BM_Ret=bench_mret)]
saveRDS(list(
  returns_all = ret_at_t[, .(Date=ym2date(ym), Ticker, Ret_1m)],
  bench_all   = bench_at_t[, .(Date=ym2date(ym), BM_Ret)],
  size_all    = me[, .(Date=ym2date(ym), Ticker, Size)],
  liq_all     = me[, .(Date=ym2date(ym), Ticker, adv=adv20)]
), file.path(OUT,"panels.rds"))
cat("[01b] DONE — scores_FC + panels.rds saved\n")
