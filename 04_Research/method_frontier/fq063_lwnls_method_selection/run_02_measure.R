# =============================================================================
# FQ-063 run_02: 실측 — 각 셀 canonical PORT_t(NW lag3 net active) + best-vs-baseline
#   paired + dual-basis(cap-w vs EW-uni + cap-tier) + DSR(sweep) + method_shopping_log.
#   포트 수익 = Return.portfolio(verbose=TRUE) only. 비용 15bps one-way delta. 벤치 cap-w fresh.
# Output: fq063_series.parquet + fq063_metrics.json + fq063_shopping_log.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics); library(sandwich); library(lmtest)
})
data.table::setDTthreads(1)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_DIR<-file.path(ROOT,"stage_artifacts/method_frontier")

mr  <-as.data.table(read_parquet(file.path(OUT_DIR,"fq057_monthly_returns.parquet")))
snap<-as.data.table(read_parquet(file.path(OUT_DIR,"fq057_monthly_snapshot.parquet")))
W   <-as.data.table(read_parquet(file.path(OUT_DIR,"fq063_weights.parquet")))
cellreg<-fromJSON(file.path(OUT_DIR,"fq063_cell_registry.json"), simplifyVector=FALSE)

ym2date<-function(ym){ y<-ym%/%100L;m<-ym%%100L
  nx<-ifelse(m==12L,(y+1L)*10000L+101L, y*10000L+(m+1L)*100L+1L)
  as.Date(as.character(nx),format="%Y%m%d")-1L }

reb_yms<-sort(unique(W$ym)); all_yms<-sort(unique(mr$ym))
span_yms<-all_yms[all_yms>=min(reb_yms) & all_yms<=max(all_yms)]
Mw<-dcast(mr[ym%in%span_yms], ym~Ticker, value.var="ret_m")
Rmat<-as.matrix(Mw[,-1,drop=FALSE]); Rdates<-ym2date(Mw$ym)
na_total<-sum(is.na(Rmat)); Rmat[is.na(Rmat)]<-0
R_all<-xts(Rmat, order.by=Rdates)

# ---- 벤치 A: cap-w K200|KQ150 fresh ----------------------------------------
bsnap<-snap[ym%in%reb_yms & member==1L & !is.na(size) & size>0]
bsnap<-bsnap[Ticker%in%colnames(R_all)]; bsnap[,wb:=size/sum(size), by=ym]
Bw<-dcast(bsnap, ym~Ticker, value.var="wb", fill=0)
Bx<-xts(as.matrix(Bw[,-1,drop=FALSE]), order.by=ym2date(Bw$ym))
bench_capw<-Return.portfolio(R_all[,colnames(Bw)[-1],drop=FALSE], weights=Bx, verbose=FALSE)
bench_capw_dt<-data.table(date=index(bench_capw), bench_capw=as.numeric(bench_capw))

# ---- 벤치 B: EW-uni (elig 균등, dual-basis) --------------------------------
esnap<-snap[ym%in%reb_yms & member==1L]; esnap<-esnap[Ticker%in%colnames(R_all)]
esnap[,we:=1/.N, by=ym]
Ew<-dcast(esnap, ym~Ticker, value.var="we", fill=0)
Ex<-xts(as.matrix(Ew[,-1,drop=FALSE]), order.by=ym2date(Ew$ym))
bench_ew<-Return.portfolio(R_all[,colnames(Ew)[-1],drop=FALSE], weights=Ex, verbose=FALSE)
bench_ew_dt<-data.table(date=index(bench_ew), bench_ew=as.numeric(bench_ew))
cat("[bench] capw months:",nrow(bench_capw_dt)," ew months:",nrow(bench_ew_dt),"\n")

# ---- 헬퍼 -------------------------------------------------------------------
nw_t<-function(x,lag=3L){ x<-as.numeric(x); x<-x[!is.na(x)]; if(length(x)<5) return(list(mean_m=NA,t=NA,n=length(x)))
  fit<-lm(x~1); ct<-lmtest::coeftest(fit, vcov.=sandwich::NeweyWest(fit,lag=lag,prewhite=FALSE))
  list(mean_m=unname(ct[1,1]), t=unname(ct[1,3]), n=length(x)) }
ann_sr<-function(x){ x<-as.numeric(x); m<-mean(x); s<-sd(x); if(!is.finite(s)||s<1e-12) return(NA); m/s*sqrt(12) }
oos_v2<-function(x, splits=c(0.55,0.65,0.75)){ x<-as.numeric(x); N<-length(x)
  rr<-sapply(splits, function(f){ n1<-floor(f*N); si<-ann_sr(x[1:n1]); so<-ann_sr(x[(n1+1):N])
    if(!is.finite(si)||abs(si)<1e-9) return(NA_real_); so/si })
  list(splits=as.list(setNames(round(rr,4),paste0("f",splits*100))), median=median(rr,na.rm=TRUE)) }
psr<-function(x, sr0=0){ x<-as.numeric(x); n<-length(x); sr<-mean(x)/sd(x)
  g3<-PerformanceAnalytics::skewness(x,method="moment"); g4<-PerformanceAnalytics::kurtosis(x,method="moment")
  pnorm(((sr-sr0)*sqrt(n-1))/sqrt(1-g3*sr+(g4-1)/4*sr^2)) }

build_port<-function(cell_){
  wsub<-W[cell==cell_]; tks<-sort(unique(wsub$Ticker)); tks<-intersect(tks, colnames(R_all))
  Wmw<-dcast(wsub[Ticker%in%tks], ym~Ticker, value.var="w", fill=0)
  Wx<-xts(as.matrix(Wmw[,-1,drop=FALSE]), order.by=ym2date(Wmw$ym))
  Rx<-R_all[, colnames(Wmw)[-1], drop=FALSE]
  pf<-Return.portfolio(Rx, weights=Wx, verbose=TRUE)
  ret<-pf$returns; bop<-as.matrix(pf$BOP.Weight); eop<-as.matrix(pf$EOP.Weight)
  n<-nrow(bop); eop_lag<-rbind(matrix(0,1,ncol(eop)), eop[-n,,drop=FALSE])
  to<-rowSums(abs(bop-eop_lag)); cost<-0.0015*to; net<-as.numeric(ret)-cost
  data.table(date=index(ret), gross=as.numeric(ret), to_oneway=to, cost=cost, ret_net=net) }

measure_cell<-function(cell_){
  pd<-build_port(cell_)
  m<-merge(pd, bench_capw_dt, by="date", all.x=TRUE)
  m<-merge(m, bench_ew_dt, by="date", all.x=TRUE)
  stopifnot(!anyNA(m$bench_capw))
  m[, active:=ret_net-bench_capw]; m[, active_ew:=ret_net-bench_ew]
  net_x<-xts(m$ret_net, order.by=m$date)
  pt<-nw_t(m$active); pt_ew<-nw_t(m$active_ew)
  cagr<-as.numeric(Return.annualized(net_x, scale=12, geometric=TRUE))
  mdd<-as.numeric(maxDrawdown(net_x))
  m[, yr:=year(date)]; yr_to<-m[,.(to=sum(to_oneway),n=.N),by=yr][n==12]
  list(cell=cell_,
       n_months=nrow(m),
       port_t_capw=round(pt$t,4), mean_active_m=round(pt$mean_m,6),
       port_t_ew=round(pt_ew$t,4),
       active_sr_ann=round(ann_sr(m$active),4), net_sr_ann=round(ann_sr(m$ret_net),4),
       cagr=round(cagr,4), mdd=round(mdd,4), calmar=round(cagr/mdd,4),
       oos_v2_median=round(oos_v2(m$active)$median,4),
       to_oneway_annual=round(mean(yr_to$to),3), to_roundtrip_annual=round(mean(yr_to$to)*2,3),
       avg_cost_bps=round(mean(m$cost)*1e4,2),
       series=m[,.(date,ret_net,bench_capw,bench_ew,active,active_ew,to_oneway,cost)]) }

cells<-sort(unique(W$cell))
res<-list(); series_out<-list()
for(cl in cells){ cm<-measure_cell(cl); series_out[[cl]]<-copy(cm$series)[,cell:=cl]
  res[[cl]]<-cm[setdiff(names(cm),"series")] }
SER<-rbindlist(series_out)
write_parquet(SER, file.path(OUT_DIR,"fq063_series.parquet"))

# ---- method_shopping_log (전 셀) -------------------------------------------
tbl<-rbindlist(lapply(res, function(r) as.data.table(r[c("cell","n_months","port_t_capw","port_t_ew",
   "active_sr_ann","net_sr_ann","cagr","mdd","calmar","oos_v2_median","to_oneway_annual")])))
tbl[, `:=`(mode=sapply(cell, function(c) cellreg[[c]]$mode),
           method=sapply(cell, function(c) cellreg[[c]]$method),
           sigma=sapply(cell, function(c) cellreg[[c]]$sigma),
           variant=sapply(cell, function(c) cellreg[[c]]$variant))]
tbl[, to_ok:=to_oneway_annual<=11.0]
tbl[, grad_hard_pass:=(port_t_capw>=2.95 & oos_v2_median>=0.7 & calmar>=0.64)]
setorder(tbl, -port_t_capw)

# ---- baselines / best-of-sweep ---------------------------------------------
baselines<-c("A_EW","A_LinearTilt"); incumbent_ref<-"A_prodLT20"
sweep_cells<-setdiff(cells, c(baselines, incumbent_ref))
base_pt<-sapply(baselines, function(b) res[[b]]$port_t_capw)
baseline_best<-baselines[which.max(base_pt)]
# best-of-sweep: TO 준수(disqualify TO>11) 셀 중 최고 PORT_t
sweep_dt<-tbl[cell%in%sweep_cells]
sweep_valid<-sweep_dt[to_ok==TRUE]
best_overall<-sweep_valid[which.max(port_t_capw), cell]
best_A<-sweep_valid[startsWith(cell,"A_")][which.max(port_t_capw), cell]
best_B<-sweep_valid[startsWith(cell,"B_")][which.max(port_t_capw), cell]

# paired NW-t: best vs baseline (동일 date)
paired<-function(cA, cB){  # cB - cA (active_capw), rebuilt from SER
  sa<-SER[cell==cA, .(date, active)]; sb<-SER[cell==cB, .(date, active)]
  mm<-merge(sa, sb, by="date"); d<-mm$active.y-mm$active.x; pt<-nw_t(d)
  list(diff_def=paste0(cB," - ",cA," (net active, capw)"), mean_diff_m=round(pt$mean_m,6),
       nw_t_lag3=round(pt$t,4), n=pt$n, ann_diff=round(pt$mean_m*12,4)) }
paired_best_vs_base<-lapply(baselines, function(b) c(list(baseline=b, best=best_overall), paired(b, best_overall)))
names(paired_best_vs_base)<-baselines

# ---- DSR (sweep) ------------------------------------------------------------
sr_cells<-tbl[cell%in%sweep_cells, .(cell, sr=active_sr_ann/sqrt(12))]  # monthly SR of active
srv<-sr_cells$sr; srv<-srv[is.finite(srv)]; Ntr<-length(srv); ge<-0.5772156649
sr_star<-sd(srv)*((1-ge)*qnorm(1-1/Ntr)+ge*qnorm(1-1/(Ntr*exp(1))))
best_active<-SER[cell==best_overall, active]
dsr_best<-psr(best_active, sr0=sr_star)

# ---- dual-basis cap-tier decomposition (best + baselines) -------------------
tier_of<-function(ym_){ s<-snap[ym==ym_ & member==1L & !is.na(size) & size>0]
  s[, rk:=frank(-size, ties.method="first")]
  s[, tier:=fifelse(rk<=30,"MEGA", fifelse(rk<=150,"MID","SMALL"))]
  setNames(s$tier, s$Ticker) }
tier_cache<-list()
captier_share<-function(cell_){
  wsub<-W[cell==cell_]; agg<-list()
  for(y in unique(wsub$ym)){ tm<-tier_cache[[as.character(y)]]; if(is.null(tm)){ tm<-tier_of(y); tier_cache[[as.character(y)]]<<-tm }
    ws<-wsub[ym==y]; tt<-tm[ws$Ticker]; tt[is.na(tt)]<-"SMALL"
    agg[[length(agg)+1L]]<-data.table(MEGA=sum(ws$w[tt=="MEGA"]), MID=sum(ws$w[tt=="MID"]), SMALL=sum(ws$w[tt=="SMALL"])) }
  a<-rbindlist(agg); list(MEGA=round(mean(a$MEGA),4), MID=round(mean(a$MID),4), SMALL=round(mean(a$SMALL),4)) }
dual_basis<-list(
  benchmark_note="PRIMARY=cap-w K200|KQ150; dual=EW-uni(elig). cap-tier=holdings weight share (MEGA<=30/MID 31-150/SMALL>150 by size rank).",
  cells=setNames(lapply(c(baselines, incumbent_ref, best_A, best_B, best_overall), function(c) list(
    cell=c, port_t_capw=res[[c]]$port_t_capw, port_t_ew=res[[c]]$port_t_ew,
    captier=captier_share(c))),
    c(baselines, incumbent_ref, best_A, best_B, best_overall)))

metrics<-list(pin_tag="fq057_20260718_171024", measured_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"),
  metric_type="optimizer_lane_ab_diagnostic",
  na_to_zero_cells=na_total,
  bench="cap-w K200|KQ150 fresh (Size, Return.portfolio) PRIMARY; EW-uni dual",
  n_cells=length(cells), n_months=res[[cells[1]]]$n_months,
  baselines=baselines, incumbent_ref=incumbent_ref,
  baseline_best=baseline_best, baseline_best_port_t=res[[baseline_best]]$port_t_capw,
  best_overall=best_overall, best_A=best_A, best_B=best_B,
  best_overall_port_t=res[[best_overall]]$port_t_capw,
  paired_best_vs_baseline=paired_best_vs_base,
  dsr=list(note="sweep형 argmax -> HARD 적용", n_trials=Ntr, sr_star_monthly=round(sr_star,4),
           dsr_best=round(dsr_best,4), pass=dsr_best>=0.5),
  graduation_gate_best=list(port_t_capw=res[[best_overall]]$port_t_capw,
     oos_v2_median=res[[best_overall]]$oos_v2_median, calmar=res[[best_overall]]$calmar,
     hard_pass=(res[[best_overall]]$port_t_capw>=2.95 & res[[best_overall]]$oos_v2_median>=0.7 & res[[best_overall]]$calmar>=0.64)),
  dual_basis=dual_basis,
  cells=res)
write_json(metrics, file.path(OUT_DIR,"fq063_metrics.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
write_json(list(shopping_log=tbl, note="method x sigma x variant PORT_t 전수 (sweep DSR n_trials=nrow)"),
           file.path(OUT_DIR,"fq063_shopping_log.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)

cat("\n===== FQ-063 RESULT =====\n")
cat(sprintf("baseline_best: %s  PORT_t=%.3f\n", baseline_best, res[[baseline_best]]$port_t_capw))
cat(sprintf("best_overall:  %s  PORT_t=%.3f (mode/method/sigma/var: %s/%s/%s/%s)\n",
    best_overall, res[[best_overall]]$port_t_capw, cellreg[[best_overall]]$mode,
    cellreg[[best_overall]]$method, cellreg[[best_overall]]$sigma, cellreg[[best_overall]]$variant))
cat(sprintf("best_A: %s (%.3f) | best_B: %s (%.3f)\n", best_A, res[[best_A]]$port_t_capw, best_B, res[[best_B]]$port_t_capw))
for(b in baselines){ p<-paired_best_vs_base[[b]]; cat(sprintf("paired best vs %s: nw_t=%.3f ann_diff=%.4f\n", b, p$nw_t_lag3, p$ann_diff)) }
cat(sprintf("DSR best: %.4f (n_trials=%d, sr*=%.4f) pass=%s\n", dsr_best, Ntr, sr_star, dsr_best>=0.5))
cat(sprintf("grad HARD pass(best): %s\n", metrics$graduation_gate_best$hard_pass))
cat("\n--- shopping_log (top by PORT_t) ---\n")
print(tbl[,.(cell, port_t_capw, calmar, oos_v2_median, to_oneway_annual, grad_hard_pass)][1:min(12,.N)])
cat("[done] run_02\n")
