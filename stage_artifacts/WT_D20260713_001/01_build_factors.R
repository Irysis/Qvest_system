#==============================================================================
# WT-D20260713_001 R17 — Step 01: build F-A/F-B/F-C monthly cross-sectional scores
# API=0. Reuse existing assets only. single-thread, arrow io(2).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(stringi) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WT   <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")   # Phase A assets
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260713_001")
source(file.path(ROOT, "stage_artifacts/WT_D20260711_002/metrics_lib.R"))  # FROZEN char_ngram_set + jaccard

ym2date <- function(ym) as.Date(sprintf("%d-%02d-01", ym%/%100L, ym%%100L))
ym_add  <- function(ym, k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }
dt2ym   <- function(d){ d<-as.Date(d); as.integer(format(d,"%Y"))*100L + as.integer(format(d,"%m")) }

# ---- universe + membership (monthly_panel) ----
mp <- readRDS(file.path(WT,"monthly_panel.rds")); me <- mp$me
memb <- me[K200==TRUE | KQ150==TRUE, .(Ticker, ym)]   # per-month K200|KQ150 membership (decision-month grid)
setkey(memb, ym, Ticker)
cat("[01] universe member-months:", nrow(memb), " decision ym range:", paste(range(memb$ym),collapse=".."),"\n")

# helper: expand a per-report signal (Ticker, rcept_ym, raw) into decision-month grid, hold H months,
#         take most-recent active signal per (Ticker, decision_ym). usable_start = rcept_ym+1 (PIT C5).
expand_hold <- function(sig, H){
  # sig: data.table(Ticker, rcept_ym, raw)
  sig <- sig[is.finite(raw)]
  sig[, us := ym_add(rcept_ym, 1L)]     # first usable decision month
  rows <- sig[, {
    dm <- vapply(0:(H-1L), function(k) ym_add(us, k), integer(1))
    .(decision_ym = dm, raw = raw, rcept_ym = rcept_ym)
  }, by=.(Ticker, seq_len(nrow(sig)))]
  rows[, seq_len := NULL]
  setorder(rows, Ticker, decision_ym, -rcept_ym)      # most recent report first
  rows <- rows[, .SD[1L], by=.(Ticker, decision_ym)]  # keep most-recent active signal
  rows[, .(Ticker, ym=decision_ym, raw)]
}

# cross-sectional z per decision month among universe members, then apply sign -> score
make_scores <- function(sig_monthly, sign){
  x <- merge(sig_monthly, memb, by=c("Ticker","ym"))   # restrict to universe members that month
  zc <- function(v){ s<-sd(v,na.rm=TRUE); if(!is.finite(s)||s<=0) return(rep(NA_real_,length(v))); (v-mean(v,na.rm=TRUE))/s }
  x[, z := zc(raw), by=ym]
  x <- x[is.finite(z)]
  x[, .(Date=ym2date(ym), Ticker, score = sign*z, raw)]
}

#===================== F-A: Lazy Prices YoY text similarity =====================
tc <- readRDS(file.path(WT,"text_cache_all.rds"))
tc <- tc[!is.na(section_head) & nchar(section_head) >= 300 & status %in% c("ok","OK")]
setorder(tc, Ticker, fy)
# precompute 5-gram set + count vector per (Ticker,fy)
cat("[01][F-A] computing 5-gram sets for", nrow(tc), "sections...\n")
tc[, ng := lapply(section_head, function(s){
  s2 <- gsub("\\s+","",s); n<-nchar(s2)
  if(n < 5L) return(character(0)); stri_sub(s2, 1:(n-4L), length=5L)
})]
cosine_ng <- function(a,b){
  if(length(a)==0 || length(b)==0) return(NA_real_)
  ta<-table(a); tb<-table(b); k<-union(names(ta),names(tb))
  va<-as.numeric(ta[k]); va[is.na(va)]<-0; vb<-as.numeric(tb[k]); vb[is.na(vb)]<-0
  d<-sqrt(sum(va^2))*sqrt(sum(vb^2)); if(d<=0) return(NA_real_); sum(va*vb)/d
}
fa_list <- tc[, {
  out <- NULL
  if(.N >= 2){
    for(i in 2:.N){
      if(fy[i] - fy[i-1] == 1L){   # consecutive fy only
        a<-ng[[i]]; b<-ng[[i-1]]
        jac <- length(intersect(a,b))/length(union(a,b))
        cos <- cosine_ng(a,b)
        sim <- 0.5*cos + 0.5*jac
        rc  <- as.Date(as.character(rcept_dt[i]),"%Y%m%d")
        out <- rbind(out, data.table(fy=fy[i], sim=sim, rcept_ym=dt2ym(rc)))
      }
    }
  }
  if(is.null(out)) out<-data.table(fy=integer(0),sim=numeric(0),rcept_ym=integer(0)); out
}, by=Ticker]
cat("[01][F-A] consecutive-fy similarity rows:", nrow(fa_list),
    " sim quantiles:", paste(round(quantile(fa_list$sim,c(0,.25,.5,.75,1),na.rm=TRUE),3),collapse=","),"\n")
fa_sig <- expand_hold(fa_list[, .(Ticker, rcept_ym, raw=sim)], H=12L)
scores_FA <- make_scores(fa_sig, sign=+1)   # high similarity = long
write_parquet(scores_FA, file.path(OUT,"scores_FA.parquet"))
cat("[01][F-A] scores rows:", nrow(scores_FA), " months:", uniqueN(scores_FA$Date),"\n")

#===================== F-B: filing delay vs legal deadline (90d) =====================
inv <- as.data.table(read_parquet(file.path(WT,"filings_inventory.parquet")))
inv <- inv[grepl("사업보고서", report_nm)]
inv[, rc := as.Date(as.character(rcept_dt),"%Y%m%d")]
inv[, deadline := as.Date(sprintf("%d-03-31", fy+1L))]   # Dec-FY end +90d ≈ 3/31
inv[, delay_d := as.integer(rc - deadline)]
inv[, rcept_ym := dt2ym(rc)]
fb_list <- inv[is.finite(delay_d), .(Ticker, rcept_ym, raw=as.numeric(delay_d))]
fb_sig <- expand_hold(fb_list, H=12L)
scores_FB <- make_scores(fb_sig, sign=-1)   # delay = short
write_parquet(scores_FB, file.path(OUT,"scores_FB.parquet"))
cat("[01][F-B] scores rows:", nrow(scores_FB), " months:", uniqueN(scores_FB$Date),
    " raw delay q:", paste(quantile(fb_list$raw,c(0,.5,1)),collapse=","),"\n")

#===================== F-C: insider filing count YoY change (quarterly) =====================
ia <- as.data.table(read_parquet(file.path(ROOT,".cache/dart/insider_activity_hist.parquet")))
ia[, q := (ym%%100L - 1L)%/%3L + 1L]; ia[, yq := (ym%/%100L)*10L + q]
qc <- ia[, .(cnt = sum(n_insider, na.rm=TRUE)), by=.(Ticker, yq)]
setorder(qc, Ticker, yq)
qc[, cnt_lag4 := shift(cnt, 4L), by=Ticker]        # 4 quarters ago (YoY)
qc[, yq_ok := yq - shift(yq,4L)==9L | (yq%%10L - shift(yq,4L)%%10L==0L), by=Ticker]  # loose YoY align guard
qc <- qc[!is.na(cnt_lag4)]
qc[, yoy := (cnt - cnt_lag4)/(cnt_lag4 + 1)]
# quarter-end month = last month of quarter; rcept_ym proxy = quarter-end ym (info available next month)
qc[, qend_ym := (yq%/%10L)*100L + (yq%%10L)*3L]
fc_list <- qc[is.finite(yoy), .(Ticker, rcept_ym=qend_ym, raw=yoy)]
fc_sig <- expand_hold(fc_list, H=3L)               # hold one quarter
scores_FC <- make_scores(fc_sig, sign=-1)          # surge = short
write_parquet(scores_FC, file.path(OUT,"scores_FC.parquet"))
cat("[01][F-C] scores rows:", nrow(scores_FC), " months:", uniqueN(scores_FC$Date),
    " raw yoy q:", paste(round(quantile(fc_list$raw,c(0,.5,.9,1),na.rm=TRUE),2),collapse=","),"\n")

# save aligned returns/bench/size/liq (13b convention) for step 02
ret_at_t  <- me[, .(Ticker, ym=ym_add(ym,-1L), Ret_1m=mret)]
bench_at_t<- mp$bench_m[, .(ym=ym_add(ym,-1L), BM_Ret=bench_mret)]
saveRDS(list(
  returns_all = ret_at_t[, .(Date=ym2date(ym), Ticker, Ret_1m)],
  bench_all   = bench_at_t[, .(Date=ym2date(ym), BM_Ret)],
  size_all    = me[, .(Date=ym2date(ym), Ticker, Size)],
  liq_all     = me[, .(Date=ym2date(ym), Ticker, adv=adv20)]
), file.path(OUT,"panels.rds"))
cat("[01] DONE — panels.rds saved\n")
