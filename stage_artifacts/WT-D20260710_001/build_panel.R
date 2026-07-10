# WT-D20260710_001 Phase 1 — multi-axis MID-tier panel assembly
# PIT-safe: tier_panel (validated PIT) + factor DB via load_month_factors (cor=1.000 verified).
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR=ROOT, QM_ROOT=ROOT)
source(file.path(ROOT,"02_Infrastructure","config.R"))
source(file.path(ROOT,"02_Infrastructure","factor_db","factor_db_connector.R"))
SA <- file.path(ROOT,"stage_artifacts","WT-D20260710_001"); dir.create(SA, showWarnings=FALSE, recursive=TRUE)

# ---- base panel (PIT-aligned) ----
tp <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts","WT_D20260706_MIDCAP","tier_panel.parquet")))
panel_axes <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
                "M08_Residual_Mom","Q07_Earnings_Stability","Q25_Ohlson_O")
base <- tp[, c("Date","Ticker","Ret_1m","Size","tv20","in_univ","AdminStock","TradingHalt",
               "score_eff", panel_axes), with=FALSE]
# tradeable universe: in K200 union KQ150, not admin/halt
base <- base[in_univ==TRUE & (is.na(AdminStock)|AdminStock==0) & (is.na(TradingHalt)|TradingHalt==0)]
base <- base[!is.na(Size)]
dts <- sort(unique(base$Date))
cat("[base] rows=", nrow(base), " dates=", length(dts), " range=",
    as.character(min(dts)), "..", as.character(max(dts)), "\n")

# ---- augment: extra factor DB axes (distinct families) ----
extra <- c("V02_EP","V12_Composite_Value","Q01_GPA","Q02_ROE",
           "M01_Mom_12_1","M13_VolAdj_Mom","D01_IdioVol","D18_BAB_Rank",
           "L01_Amihud","M11_ST_Reversal")
aug_list <- vector("list", length(dts))
for(i in seq_along(dts)){
  sd <- dts[i]
  fm <- tryCatch(load_month_factors(sd, factor_names=extra), error=function(e) NULL)
  if(is.null(fm)||nrow(fm)==0){ aug_list[[i]] <- NULL; next }
  fm <- as.data.table(fm)
  w <- dcast(fm, Ticker ~ Factor_Name, value.var="Z_Score_Aligned", fun.aggregate=function(x) x[1])
  w[, Date := sd]
  aug_list[[i]] <- w
  if(i %% 40 == 0) cat("  augmented", i, "/", length(dts), "\n")
}
aug <- rbindlist(aug_list, use.names=TRUE, fill=TRUE)
cat("[aug] rows=", nrow(aug), " cols=", paste(setdiff(names(aug),c("Ticker","Date")), collapse=","), "\n")

panel <- merge(base, aug, by=c("Date","Ticker"), all.x=TRUE)

# ---- recompute size_rank + tier within tradeable in_univ per Date (MEGA1-10/MID11-30/OTHER31+) ----
setorder(panel, Date, -Size)
panel[, size_rank := seq_len(.N), by=Date]
panel[, tier := fifelse(size_rank<=10L,"MEGA", fifelse(size_rank<=30L,"MID","OTHER"))]

all_axes <- c(panel_axes, extra)
# ---- cross-sectional z per Date (screening universe), and within-tier z ----
zc <- function(x){ s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) return(x*0); (x-mean(x,na.rm=TRUE))/s }
for(ax in all_axes){
  panel[, paste0("zc_",ax) := zc(get(ax)), by=Date]
  panel[, paste0("zt_",ax) := zc(get(ax)), by=.(Date,tier)]  # within-tier z (size-confound removed)
}
saveRDS(panel, file.path(SA,"panel.rds"))
cat("[saved] panel.rds rows=", nrow(panel), " cols=", ncol(panel), "\n")
# axis coverage report
cov <- panel[, lapply(.SD, function(x) round(mean(!is.na(x)),3)), .SDcols=all_axes]
cat("[axis coverage]\n"); print(t(cov))
