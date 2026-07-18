# WT-D20260718_005 — Factor-level timing: per-stock family z panel + return grid
# PIT: score at month-end t from factor_db_{ym(t)} (load_month_factors, IC-aligned expanding).
#      forward Ret_1m realized over (start_d, end_d]. benchmark cap-w KOSPI200 (pinned).
# Vintage pin: RAWDATA_pin20260703 + benchmark_pin20260703 (reproducibility; recorded).
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(QM_ROOT=root); setwd(root)
source("02_Infrastructure/factor_db/factor_db_connector.R")

OUT <- "04_Research/method_frontier/wt005_factor_timing"
RAW_PIN   <- ".cache/RAWDATA_pin20260703.parquet"
BENCH_PIN <- ".cache/benchmark_pin20260703.parquet"
PIN_TAG   <- "RAWDATA_pin20260703+benchmark_pin20260703"

FAMILIES <- list(
  value    = c("V01_BM","V02_EP","V03_CFP","V20_SP","V14_EBIT_EV"),
  quality  = c("Q02_ROE","Q03_ROA","Q17_ROIC","GR05_ROE_Growth"),
  momentum = c("M01_Mom_12_1","M02_Mom_6_1","M03_Mom_3_1"),
  low_vol  = c("D01_IdioVol","D02_Beta","D03_RealVol","D04_Downside_Beta"),
  size     = c("S01_Size"),
  dividend = c("V06_fDY","V11_Shareholder_Yield","V17_Payout_Ratio")
)
all_prox <- unlist(FAMILIES, use.names=FALSE)

cat("[1] load raw pin ...\n")
raw <- as.data.table(read_parquet(RAW_PIN, col_select=c("Date","Ticker","K200","KQ150","Size","Ret","Close","Vol")))
raw[, Date := as.Date(Date)]
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)

# month-end trading days
raw[, ym := format(Date, "%Y-%m")]
me <- raw[, .(Date=max(Date)), by=ym]
sig_dates <- sort(me$Date)
# factor_db availability caps: build family z only where factor_db_{ym} exists (>=2005)
sig_dates <- sig_dates[sig_dates >= as.Date("2005-01-01")]
cat("   n sig_dates:", length(sig_dates), " range", as.character(min(sig_dates)), as.character(max(sig_dates)), "\n")

# universe membership + size at each sig_date
univ <- raw[Date %in% sig_dates & (K200==1 | KQ150==1), .(Date, Ticker, Size, K200, KQ150)]
cat("   univ rows:", nrow(univ), " avg names/mo:", round(nrow(univ)/length(sig_dates)), "\n")

cat("[2] build family z panel per sig_date ...\n")
zscore <- function(x){ s<-sd(x,na.rm=TRUE); if(!is.finite(s)||s<=0) return(rep(0,length(x))); (x-mean(x,na.rm=TRUE))/s }
fam_list <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  sd_i <- sig_dates[i]
  mf <- tryCatch(load_month_factors(sd_i, factor_names=all_prox), error=function(e) NULL)
  if (is.null(mf) || nrow(mf)==0) next
  u <- univ[Date==sd_i]
  if (nrow(u)==0) next
  mf <- mf[Ticker %in% u$Ticker]
  W <- dcast(mf, Ticker ~ Factor_Name, value.var="Z_Score_Aligned", fun.aggregate=function(x) mean(x,na.rm=TRUE))
  # family composite = EW mean of aligned z over present proxies
  fam_dt <- data.table(Ticker=W$Ticker)
  for (fk in names(FAMILIES)) {
    px <- intersect(FAMILIES[[fk]], names(W))
    if (length(px)==0) { fam_dt[[fk]] <- NA_real_; next }
    m <- as.matrix(W[, ..px])
    comp <- rowMeans(m, na.rm=TRUE)
    fam_dt[[fk]] <- comp
  }
  # re-standardize each family cross-sectionally within universe (equal scale for compositing)
  for (fk in names(FAMILIES)) fam_dt[[fk]] <- zscore(fam_dt[[fk]])
  fam_dt <- merge(fam_dt, u[, .(Ticker, Size, K200, KQ150)], by="Ticker", all.x=TRUE)
  fam_dt[, Date := sd_i]
  fam_list[[i]] <- fam_dt
  if (i %% 40 == 0) cat("   ", i, "/", length(sig_dates), as.character(sd_i), "\n")
}
FAM <- rbindlist(fam_list, use.names=TRUE, fill=TRUE)
setcolorder(FAM, c("Date","Ticker"))
cat("   FAM rows:", nrow(FAM), " dates:", uniqueN(FAM$Date), "\n")
write_parquet(FAM, file.path(OUT, "family_z_panel.parquet"))

cat("[3] precompute forward return / BM / liquidity grid ...\n")
b <- as.data.table(read_parquet(BENCH_PIN, col_select=c("Date","BM_Ret")))
b[, Date := as.Date(Date)]; bm_daily <- b[!is.na(BM_Ret)]
bm_month <- function(start_d, end_d){ seg <- bm_daily[Date>start_d & Date<=end_d, BM_Ret]; if(length(seg)==0) return(0); prod(1+seg)-1 }
grid_sig <- sort(unique(FAM$Date))
R_list <- vector("list", length(grid_sig)-1L); bm_list <- vector("list", length(grid_sig)-1L); liq_list <- vector("list", length(grid_sig))
for (i in seq_along(grid_sig)) {
  sig <- grid_sig[i]
  start_d <- min(raw[Date>=sig]$Date); if(length(start_d)==0||is.na(start_d)) next
  ld <- raw[Date>=(start_d-30L) & Date<start_d, .(adv=mean(TradingAmt,na.rm=TRUE)), by=Ticker]
  ld[, Date:=sig]; liq_list[[i]] <- ld[, .(Date,Ticker,adv)]
  if (i < length(grid_sig)) {
    nxt <- grid_sig[i+1L]
    end_d <- { z<-min(raw[Date>=nxt]$Date); if(length(z)==0||is.na(z)) max(raw$Date) else z }
    pd <- raw[Date>start_d & Date<=end_d, .(ret_fwd=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    pd[, Date:=sig]; R_list[[i]] <- pd[, .(Date,Ticker,Ret_1m=ret_fwd)]
    bm_list[[i]] <- data.table(Date=sig, BM_Ret=bm_month(start_d,end_d))
  }
}
Rg  <- rbindlist(R_list); BMg <- rbindlist(bm_list); LQg <- rbindlist(liq_list)
write_parquet(Rg,  file.path(OUT,"grid_returns.parquet"))
write_parquet(BMg, file.path(OUT,"grid_bench.parquet"))
write_parquet(LQg, file.path(OUT,"grid_liq.parquet"))
cat("   grid R rows:", nrow(Rg), " BM rows:", nrow(BMg), " LQ rows:", nrow(LQg), "\n")
cat("[done] pin=", PIN_TAG, "\n")
