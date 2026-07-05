# run3.R — Attribution: decompose the ANCHOR lift. Is short-side (underweight) additive to anchor,
# or is the anchor(mega-cap tilt) the whole story? Ablations that turn each mechanism on/off.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); arrow::set_cpu_count(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA   <- file.path(ROOT,"stage_artifacts","WT-D20260705_004")
OUT  <- file.path(ROOT,"stage_artifacts","probe_benchmark_relative_construction_20260705")
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","weighted_screen_bt.R"))
set.seed(20260705L); ym2date <- function(y) as.Date(paste0(y,"-01"))
pan <- as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet")))
yms <- sort(unique(pan$ym)); bw <- readRDS(file.path(OUT,"benchmark_weights.rds"))
bm <- as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[, ym := format(as.Date(Date),"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_lr <- bm[, .(lr=sum(log1p(BM_Ret))), by=ym][order(ym)]; bm_lr[, bm_fwd := expm1(shift(lr,type="lead",n=1L))]
benchdt <- bm_lr[!is.na(bm_fwd), .(Date=ym2date(ym), BM_Ret=bm_fwd)]
rets <- pan[, .(Date=ym2date(ym), Ticker, Ret_1m=F1)]
CAP<-0.20; NMAX<-25L; BPS<-15
cap_project <- function(w,cap=CAP){w[w<0]<-0;if(sum(w)<=0)return(w);w<-w/sum(w)
  for(it in 1:100){over<-w>cap+1e-12;if(!any(over))break;ex<-sum(w[over]-cap);w[over]<-cap;un<-!over&w>0;if(!any(un))break;w[un]<-w[un]+ex*w[un]/sum(w[un])};w/sum(w)}
run_bt<-function(wd,tag,sf=NULL){d<-copy(wd);if(!is.null(sf))d<-d[Date>=as.Date(sf)];weighted_screen_bt(d,rets,benchdt,cost_bps_oneway=BPS,run_id=tag,strategy_id=tag)}
PT<-function(r)r$portfolio_alpha_t_nw_lag3

# ABLATION MATRIX — vary (A) anchor on/off, (B) anchor size, (C) fill = alpha vs EW-of-benchmark-largest
# A0: no anchor, EW top-25 alpha = BASE (already 0.97)
# A1: anchor top-2 @ each cap x, fill top-(25-2) by alpha  [= ANCHOR]
# A2: anchor top-1 only @ 20%, fill 24 alpha
# A3: anchor top-3 @ ~13.3% each (0.40 total), fill 22 alpha
# A4: anchor top-2 @ 10% each (0.20 total), fill 23 alpha  (weaker anchor)
# A5: anchor top-2 @ their true b (cap-weight, no over/under) capped 20%, fill 23 alpha
# CONTROL_bench_noAlpha: anchor top-2 + fill next-largest-cap 23 (NO alpha) = pure size portfolio
build <- function(n_anchor, cap_each, n_fill, fill="alpha") {
  out <- vector("list", length(yms))
  for (i in seq_along(yms)) { y<-yms[i]
    bb<-bw[ym==y][order(-Size)]; mm<-pan[ym==y,.(Ticker,mu_hat)]
    if(nrow(bb)<n_anchor+2) next
    anchors<-head(bb$Ticker,n_anchor)
    if(fill=="alpha"){pool<-mm[!Ticker %in% anchors];setorder(pool,-mu_hat);ft<-head(pool$Ticker,n_fill)}
    else if(fill=="size"){pool<-bb[!Ticker %in% anchors];ft<-head(pool$Ticker,n_fill)}
    aw<-rep(cap_each,n_anchor); fw<-rep((1-sum(aw))/n_fill,n_fill)
    dt<-data.table(ym=y,Date=ym2date(y),Ticker=c(anchors,ft),w=cap_project(c(aw,fw)))
    out[[i]]<-dt[w>0]
  }; rbindlist(out)
}
specs <- list(
  A1_anchor2x20_alpha23 = list(2,0.20,23,"alpha"),
  A2_anchor1x20_alpha24 = list(1,0.20,24,"alpha"),
  A3_anchor3x1333_alpha22 = list(3,0.1333,22,"alpha"),
  A4_anchor2x10_alpha23 = list(2,0.10,23,"alpha"),
  CTRL_anchor2x20_SIZEfill23 = list(2,0.20,23,"size")
)
tab <- rbindlist(lapply(names(specs), function(nm){
  s<-specs[[nm]]; wd<-build(s[[1]],s[[2]],s[[3]],s[[4]])
  r<-run_bt(wd[,.(Date,Ticker,w)],nm); rr<-run_bt(wd[,.(Date,Ticker,w)],paste0(nm,"_rec"),sf="2017-01-01")
  data.table(spec=nm, full_PORT_t=PT(r), rec2017_PORT_t=PT(rr), IR=r$information_ratio,
             TO=r$turnover_annual, n=r$n_months, med_max_w=median(wd[,.(m=max(w)),by=ym]$m))
}))
cat("=== ABLATION MATRIX ===\n"); print(tab)

# Direct short-side attribution: for ANCHOR (A1), split active return into contribution buckets.
# Reconstruct monthly active return = sum_i (w_i - b_i)*ret_i ; bucket by role.
a1 <- build(2,0.20,23,"alpha")
setorder(pan, ym, -mu_hat)
attr_rows <- vector("list", length(yms))
for (i in seq_along(yms)) { y<-yms[i]
  bb<-bw[ym==y][order(-Size)]; if(nrow(bb)<3) next
  anchors<-head(bb$Ticker,2)
  held<-a1[ym==y]; if(nrow(held)==0) next
  alln<-merge(bw[ym==y,.(Ticker,b)], pan[ym==y,.(Ticker,mu_hat,F1)], by="Ticker", all=TRUE)
  alln<-merge(alln, held[,.(Ticker,w)], by="Ticker", all=TRUE)
  alln[is.na(b),b:=0]; alln[is.na(w),w:=0]; alln[is.na(F1),F1:=0]
  alln[, act:=w-b]
  alln[, role := fifelse(Ticker %in% anchors, "anchor",
                  fifelse(w>0, "fill_long", "underweight"))]
  ar <- alln[, .(contrib=sum(act*F1)), by=role]
  ar[, ym:=y]; attr_rows[[i]]<-ar
}
ATTR <- rbindlist(attr_rows)
attr_sum <- ATTR[, .(mean_monthly_contrib=mean(contrib), ann_contrib=mean(contrib)*12), by=role][order(-ann_contrib)]
cat("\n=== ANCHOR active-return attribution (mean monthly (w_i-b_i)*ret_i by role) ===\n"); print(attr_sum)
cat("(underweight bucket = short-side harvest of non-held names; anchor = mega-cap tilt vs their b)\n")

saveRDS(list(ablation=tab, attribution=attr_sum, ATTR=ATTR), file.path(OUT,"phase3_attribution.rds"))
fwrite(tab, file.path(OUT,"ablation_matrix.csv"))
fwrite(attr_sum, file.path(OUT,"anchor_attribution.csv"))
cat("SAVED phase3_attribution.rds + csvs\n")
