## R35 charts — SP EW-basis perf + pre/post-2024 subperiod + overlay marginal (mandate: telegram-chart)
suppressPackageStartupMessages({library(arrow);library(data.table)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT<-file.path(QM,"stage_artifacts/WT_D20260715_004"); CH<-file.path(WT,"charts")
source(file.path(QM,"02_Infrastructure/telegram/tg_chart_pack.R"))
RES<-readRDS(file.path(WT,"r35_results.rds"))

## chart 1: SP EW-basis performance (net vs EW-universe bench, cumulative active)
ew<-as.data.table(read_parquet(file.path(WT,"sp_ew_series.parquet")))  # date, ret_net, ew_bench_ret, active_ew
setorder(ew,date)
p1<-tg_chart_pack(ew[,.(date,ret_net,benchmark_ret=ew_bench_ret)], CH,
   title="R35 SP(sales-yield) EW-basis vs EW-universe",
   bm_label="EW-universe", prefix="sp_ewbasis",
   metrics_note=sprintf("EW-uni PORT_t %.2f · oos_v2 %.2f · cap-w PORT_t %.2f (<2.95) · capacity %.1f억 (canonical_screen)",
     RES$part1$ewuni_pt, RES$part1$oos_ew, RES$part1$capw_pt, RES$part1$capacity_bil))

## chart 2: pre/post-2024 subperiod SP EW-active NW-t bars
sp<-RES$part3$subperiod  # period, n, nwt, meanbp, sr
p2<-tg_chart_sweep(labels=c("2008-14","2015-19","2020-23","2024+"),
   values=sp$nwt, out_dir=CH, value_label="NW-t (EW-active)",
   title="R35 SP EW-active NW-t by regime (pre-2024 dominant)",
   hline=2.0, hline_label="paired 2.0", highlight="2024+", filename="sp_subperiod.png")

## chart 3: SP overlay marginal (pre vs post-2024) on base + incumbent
ovl_lab<-c("base full","base post24","incumbent full","incumbent post24")
ovl_val<-c(RES$part2$ovl_base_paired, RES$part2$ovl_base_post,
           RES$part2$ovl_bk_paired, RES$part2$ovl_bk_post)
p3<-tg_chart_sweep(labels=ovl_lab, values=ovl_val, out_dir=CH, value_label="paired NW-t (marginal)",
   title="R35 SP overlay marginal paired-t (pre-2024 only, post24 ~0)",
   hline=2.0, hline_label="paired 2.0", highlight="base full", filename="sp_overlay.png")

cat("charts:\n"); cat(paste(c(p1,p2,p3),collapse="\n"),"\n")
cat("R35_CHARTS_DONE\n")
