## R28 charts — look-ahead inflation + C06 counterfactual
suppressPackageStartupMessages({library(data.table)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_004"); CH <- file.path(WT,"charts"); dir.create(CH,showWarnings=FALSE)
source(file.path(QM,"02_Infrastructure/telegram/tg_chart_pack.R"))
R <- readRDS(file.path(WT,"screen_results.rds"))
IS_END <- as.Date("2024-06-30")
pr <- function(cc) as.data.table(R[[cc]]$pr)[order(date)]
wl <- function(r) cumprod(1+ifelse(is.na(r),0,r))

## Chart 1: equity curves — clean 7F vs clean 6F vs lookahead 7F vs BM (log cum)
p0_7<-pr("0_stored_S7"); p0_6<-pr("0_stored_S6"); p1_7<-pr("1_stored_S7")
png(file.path(CH,"01_equity_lookahead_c06.png"),width=1100,height=600,res=110); par(mar=c(4,4,3,1))
plot(p1_7$date, log(wl(p1_7$ret_net)), type="l", col="red", lwd=2, xlab="", ylab="log cumulative net",
     main="R28: book alpha equity — same-month(look-ahead) vs T-1(PIT-clean) · 7F vs 6F(-C06)")
lines(p0_7$date, log(wl(p0_7$ret_net)), col="black", lwd=2)
lines(p0_6$date, log(wl(p0_6$ret_net)), col="blue", lwd=2, lty=2)
lines(p0_7$date, log(wl(p0_7$benchmark_ret)), col="gray50", lwd=1.5, lty=3)
abline(v=IS_END, col="orange", lty=3)
legend("topleft", c("7F same-month (look-ahead, PORT_t 6.38)","7F T-1 (PIT-clean, 3.06)","6F(-C06) T-1 (PIT-clean, 3.50)","KOSPI200 cap-w","IS|HO split"),
       col=c("red","black","blue","gray50","orange"), lwd=c(2,2,2,1.5,1), lty=c(1,1,2,3,3), bty="n", cex=0.85)
dev.off()

## Chart 2: PORT_t sweep across 8 cells + stored (hline 2.95)
cells <- c("0_stored_S7","0_stored_S6","0_ic_S7","0_ic_S6","1_stored_S7","1_stored_S6","1_ic_S7","1_ic_S6","score_stored")
labs <- c("T1·stored·7F","T1·stored·6F","T1·ic·7F","T1·ic·6F","SM·stored·7F(LA)","SM·stored·6F(LA)","SM·ic·7F(LA)","SM·ic·6F(LA)","stored panel")
vals <- sapply(cells, function(c) R[[c]]$res$portfolio_alpha_t_nw_lag3)
tg_chart_sweep(labs, as.numeric(vals), out_dir=CH, title="R28 cap-w PORT_t: T-1(PIT-clean) vs SM(same-month look-ahead)",
               hline=2.95, hline_label="HARD 2.95", value_label="PORT_t", filename="02_porttsweep.png")

## Chart 3: paired t IS/HO for 4 cells (positive=removing C06 helps), hline 2.0
paired <- as.data.table(arrow::read_parquet(file.path(WT,"paired_results.parquet")))
lab3 <- c(paste0(paired$cell," IS"), paste0(paired$cell," HO"))
val3 <- c(paired$paired_t_is, paired$paired_t_ho)
tg_chart_sweep(lab3, ifelse(is.finite(val3),val3,0), out_dir=CH, title="R28 paired NW-t (6F minus 7F; +=C06 removal helps)",
               hline=2.0, hline_label="sig 2.0", value_label="paired NW-t", filename="03_pairedt.png")

## Chart 4: cumulative paired diff (6F-7F) — clean vs lookahead
d0 <- merge(pr("0_stored_S7")[,.(date,a7=ret_net-benchmark_ret)], pr("0_stored_S6")[,.(date,a6=ret_net-benchmark_ret)],by="date")
d0[,diff:=a6-a7]
d1 <- merge(pr("1_stored_S7")[,.(date,a7=ret_net-benchmark_ret)], pr("1_stored_S6")[,.(date,a6=ret_net-benchmark_ret)],by="date")
d1[,diff:=a6-a7]
png(file.path(CH,"04_cum_c06_effect.png"),width=1100,height=600,res=110); par(mar=c(4,4,3,1))
plot(d1$date, cumsum(d1$diff), type="l", col="red", lwd=2, xlab="", ylab="cumulative (6F-7F) net-active",
     main="R28: cumulative C06-removal effect — same-month(LA) vs T-1(clean)")
lines(d0$date, cumsum(d0$diff), col="black", lwd=2)
abline(h=0,col="gray70"); abline(v=IS_END,col="orange",lty=3)
legend("topleft", c("same-month (look-ahead basis)","T-1 (PIT-clean basis)","IS|HO split"),
       col=c("red","black","orange"), lwd=c(2,2,1), lty=c(1,1,3), bty="n", cex=0.85)
dev.off()
cat("CHARTS_DONE:", paste(list.files(CH,pattern="png$"),collapse=", "), "\n")
