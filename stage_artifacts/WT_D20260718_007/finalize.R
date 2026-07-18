#!/usr/bin/env Rscript
# finalize.R — WT-D20260718_007: lineage + status + governance + charts (calmar sweep, crisis-firing timeline)
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
WT <- "WT-D20260718_007"; MB <- file.path("qepm/mailbox/worktask",WT); ST <- "stage_artifacts/WT_D20260718_007"

# ---- 1. lineage (AFTER alpha_package write) ----
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id=WT, package_type="alpha_package",
    method_selected="UNSUPERVISED autoencoder (LSTM seq-AE + point-AE) regime timing overlay, detector-swap vs M4 BOCPD",
    input_file_paths=c(file.path(ST,"ae_regime_signal.parquet"),
                       ".cache/pins/WT-D20260718_007_r1/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet",
                       ".cache/pins/WT-D20260718_007_r1/period_returns_layer5.csv"))
  cat("[lineage] recorded\n")
}, error=function(e) cat("[lineage] skipped:", conditionMessage(e), "\n"))

# ---- 2. status + governance ----
write_json(list(task_id=WT, phase="ALPHA_DONE", verdict="VALIDATED_MIXED_CONDITIONAL_POSITIVE",
                surface="timing_overlay_detector_swap", certificate="NOT_ISSUED",
                handoff="risk-research recommended", as_of="2026-07-18"),
           file.path(MB,"status.json"), pretty=TRUE, auto_unbox=TRUE)
write_json(list(task_id=WT, entries=list(list(stage="alpha", event="detector_swap_ab_complete",
                verdict="VALIDATED_MIXED_CONDITIONAL_POSITIVE",
                note="Unsupervised AE solves WT-004 OOD root-cause (2008 GFC 9/9, crisis-corr 2x M4) + calmar/MDD edge (2.196 vs 2.069, persistent ex-2008) but paired-return insignificant (-1.49). No clean kill. Route to risk-research (ensemble tail-complement).",
                pin_tag="WT-D20260718_007_r1"))),
           file.path(MB,"governance_log.json"), pretty=TRUE, auto_unbox=TRUE)
cat("[status/governance] written\n")

# ---- 3. charts ----
source("02_Infrastructure/telegram/tg_chart_pack.R")
# (a) calmar sweep across arms
c1 <- tg_chart_sweep(
  labels=c("bare(no overlay)","M4 BOCPD(incumbent)","AE-seq(swap)","AE-point(swap)","M4(+)AE ensemble"),
  values=c(1.140, 2.069, 2.196, 1.976, 2.148),
  out_dir=ST, title="WT-007 detector-swap: book Calmar (CAGR/|MDD|)",
  value_label="Calmar", hline=2.069, hline_label="M4", highlight="AE-seq(swap)",
  filename="chart_calmar_sweep.png")
cat("[chart] calmar sweep:", c1, "\n")

# (b) crisis-firing timeline: M4 vs AE-seq fire flags over time + BM-crash months
ae <- as.data.table(read_parquet(file.path(ST,"ae_regime_signal.parquet")))
ae[, decision_date := as.Date(decision_date)]
Lr <- fread(".cache/pins/WT-D20260718_007_r1/period_returns_layer5.csv")
Lr[, ym_a := format(as.Date(anchor_date),"%Y-%m")]
ae[, ym := format(decision_date,"%Y-%m")]
m4 <- Lr[, .(ym_a, m4=as.numeric(m4_weight_lag))]
ae[m4, on=.(ym=ym_a), m4_fire := as.integer(i.m4 < 0.999)]
# BM crash months from benchmark (period monthly ret < -5%)
bm <- as.data.table(read_parquet(".cache/pins/WT-D20260718_007_r1/benchmark.parquet"))
bm[, Date := as.Date(Date)]; bm <- bm[order(Date)]
bm[, ym := format(Date,"%Y-%m")]
bmm <- bm[, .(bmret = prod(1+ifelse(is.na(BM_Ret),0,BM_Ret))-1), by=ym]
ae[bmm, on=.(ym), crash := as.integer(i.bmret < -0.05)]
ae <- ae[!is.na(m4_fire)][order(decision_date)]
f <- file.path(ST,"chart_crisis_firing.png")
grDevices::png(f, width=1100, height=520, res=110)
graphics::par(mar=c(3.6,7.5,3.0,1.2), family="")
plot(NA, xlim=range(ae$decision_date), ylim=c(0.3,3.7), yaxt="n", xaxt="n", xlab="", ylab="",
     main="WT-007 crisis-firing: does the detector de-risk WHEN crashes hit?")
yrs <- seq(as.Date("2008-01-01"), as.Date("2026-01-01"), by="2 years")
axis(1, at=yrs, labels=format(yrs,"%Y"), cex.axis=0.72)
axis(2, at=c(1,2,3), labels=c("BM crash\n(<-5%)","M4 BOCPD\nfire","AE-seq\nfire"), las=1, cex.axis=0.72)
graphics::abline(h=c(1,2,3), col="#eeeeee")
cr <- ae[crash==1]; graphics::rect(cr$decision_date-12, 0.3, cr$decision_date+12, 3.7, col="#fde0e0", border=NA)
graphics::points(cr$decision_date, rep(1,nrow(cr)), pch=15, col="#d62728", cex=0.8)
mm <- ae[m4_fire==1]; graphics::points(mm$decision_date, rep(2,nrow(mm)), pch=15, col="#1f77b4", cex=0.8)
aa <- ae[fire_seq==1]; graphics::points(aa$decision_date, rep(3,nrow(aa)), pch=15, col="#ff7f0e", cex=0.8)
graphics::text(as.Date("2008-11-01"), 3.55, "2008 GFC: AE 9/9, M4 6/9, WT004-transformer 0/9", col="#ff7f0e", cex=0.62, pos=4)
graphics::box()
grDevices::dev.off()
cat("[chart] crisis firing timeline:", f, "\n")
cat("[done] finalize\n")
