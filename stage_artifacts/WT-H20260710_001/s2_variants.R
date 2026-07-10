# WT-H20260710_001 Stage 2 — Block B (M08 formation) + Block C (C04/C06) variant panels.
# PIT: at each sig_date, only Date<=sig_date daily data. a-priori sign (+). cross-sec z per sig_date.
suppressMessages({library(arrow); library(data.table)})
options(scipen=999); setDTthreads(1L); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-H20260710_001")
inp <- readRDS(file.path(SA,"inputs.rds")); scope <- inp$scope; dts <- inp$dts
zc <- function(x){ s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) return(x*0); (x-mean(x,na.rm=TRUE))/s }

# ============ Block B: M08 residual-momentum variants ============
cat("[B] loading rawdata daily ...\n")
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),
        col_select=c("Date","Ticker","Ret","BM_Ret")))
raw[, Date := as.Date(Date)]; raw <- raw[!is.na(Ret) & !is.na(BM_Ret)]
setkey(raw, Ticker, Date)
bm_daily <- unique(raw[, .(Date, BM_Ret)]); setkey(bm_daily, Date)

# variant defs (skip in trading days, lookback in trading days)
Bvar <- list(
  B0_inc_252_21_capm = list(lb=252L, sk=21L, resid="capm"),
  B1_126_21_capm     = list(lb=126L, sk=21L, resid="capm"),
  B2_378_21_capm     = list(lb=378L, sk=21L, resid="capm"),
  B3_252_0_capm      = list(lb=252L, sk=0L,  resid="capm"),
  B4_252_21_raw      = list(lb=252L, sk=21L, resid="raw")
)
maxback <- 420L
m08_out <- vector("list", length(dts))
for (i in seq_along(dts)) {
  SD <- dts[i]
  wlo <- SD - 620  # calendar days ~ covers 420 trading days
  W <- raw[Date <= SD & Date >= wlo]
  if (nrow(W)==0) next
  res <- W[, {
    n <- .N
    out <- as.list(rep(NA_real_, length(Bvar))); names(out) <- names(Bvar)
    if (n >= 30L) {
      r <- Ret; b <- BM_Ret
      # CAPM residuals over full available window (beta from window) — matches compute_momentum pattern per-window
      for (vn in names(Bvar)) {
        vv <- Bvar[[vn]]; lb <- vv$lb; sk <- vv$sk
        if (n >= (lb)) {
          idx_end <- n - sk
          idx_start <- max(1L, n - lb + 1L)
          if (idx_end > idx_start) {
            if (vv$resid=="capm") {
              # fit CAPM on the summation window slice
              sl <- idx_start:idx_end
              fit <- tryCatch(.lm.fit(cbind(1, b[sl]), r[sl]), error=function(e) NULL)
              if (!is.null(fit)) out[[vn]] <- sum(fit$residuals)
            } else { # raw momentum: cumulative simple return over slice
              sl <- idx_start:idx_end
              out[[vn]] <- prod(1 + r[sl]) - 1
            }
          }
        }
      }
    }
    out
  }, by=Ticker]
  res[, Date := SD]; m08_out[[i]] <- res
  if (i %% 40 == 0) cat("  B sig",i,"/",length(dts),"\n")
}
m08_panel <- rbindlist(m08_out, use.names=TRUE, fill=TRUE)
# restrict to book scope, cross-sec z per Date (a-priori sign +), rename to M08_<variant>
m08_panel <- merge(scope, m08_panel, by=c("Date","Ticker"))
for (vn in names(Bvar)) m08_panel[, (paste0("z_",vn)) := zc(get(vn)), by=Date]
cov_b <- m08_panel[, lapply(.SD, function(x) round(mean(!is.na(x)),3)), .SDcols=names(Bvar)]
cat("[B coverage]\n"); print(t(cov_b))
# sanity: cor of B0 recompute vs stored defense M08 aligned-Z
dpm <- inp$def_panel[, .(Date, Ticker, M08_stored=M08_Residual_Mom)]
chk <- merge(m08_panel[, .(Date,Ticker, z_B0_inc_252_21_capm)], dpm, by=c("Date","Ticker"))
cat(sprintf("[B0 recompute vs stored M08 aligned-Z] cross-sec cor mean=%.4f\n",
    chk[!is.na(M08_stored), .(c=cor(z_B0_inc_252_21_capm, M08_stored)), by=Date][, mean(c,na.rm=TRUE)]))
saveRDS(m08_panel, file.path(SA,"m08_variants.rds"))

# ============ Block C: C04 ESBR agg + C06 TP smoothing ============
cat("\n[C] loading consensus + close ...\n")
esbr <- as.data.table(read_parquet(file.path(ROOT,".cache/consensus/esbr.parquet")))
esbr[, Date := as.Date(Date)]; esbr <- esbr[!is.na(esbr)]; setkey(esbr, Ticker, Date)
tp <- as.data.table(read_parquet(file.path(ROOT,".cache/consensus/target_price.parquet")))
tp[, Date := as.Date(Date)]; tp <- tp[!is.na(target_price) & target_price>0]; setkey(tp, Ticker, Date)
cl <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"), col_select=c("Date","Ticker","Close")))
cl[, Date := as.Date(Date)]; cl <- cl[!is.na(Close) & Close>0]; setkey(cl, Ticker, Date)

c_out <- vector("list", length(dts))
for (i in seq_along(dts)) {
  SD <- dts[i]
  # ESBR aggregations
  e <- esbr[Date <= SD & Date >= (SD-200)]
  eagg <- e[, {
    .(esbr_1 = .SD[.N, esbr],
      esbr_3 = mean(.SD[Date > (SD-95), esbr]),
      esbr_6 = mean(.SD[Date > (SD-190), esbr]))
  }, by=Ticker]
  # TP smoothing + close
  t <- tp[Date <= SD & Date >= (SD-40)]
  tagg <- t[, .(tp_1 = .SD[.N, target_price],
                tp_5 = median(tail(target_price, 5)),
                tp_21= median(tail(target_price, 21))), by=Ticker]
  cc <- cl[Date <= SD & Date >= (SD-15)]
  clast <- cc[, .(Close=.SD[.N, Close]), by=Ticker]
  m <- merge(tagg, clast, by="Ticker")
  m[, `:=`(tpgap_1=(tp_1-Close)/Close, tpgap_5=(tp_5-Close)/Close, tpgap_21=(tp_21-Close)/Close)]
  cc2 <- merge(eagg, m[, .(Ticker, tpgap_1, tpgap_5, tpgap_21)], by="Ticker", all=TRUE)
  cc2[, Date := SD]; c_out[[i]] <- cc2
  if (i %% 40 == 0) cat("  C sig",i,"/",length(dts),"\n")
}
c_panel <- rbindlist(c_out, use.names=TRUE, fill=TRUE)
c_panel <- merge(scope, c_panel, by=c("Date","Ticker"))
for (v in c("esbr_1","esbr_3","esbr_6","tpgap_1","tpgap_5","tpgap_21"))
  c_panel[, (paste0("z_",v)) := zc(get(v)), by=Date]
cov_c <- c_panel[, lapply(.SD, function(x) round(mean(!is.na(x)),3)),
                 .SDcols=c("esbr_1","esbr_3","esbr_6","tpgap_1","tpgap_5","tpgap_21")]
cat("[C coverage]\n"); print(t(cov_c))
# sanity vs core_panel incumbent C04/C06 aligned-Z
cpm <- inp$core_panel[, .(Date,Ticker, C04_stored=C04_ESBR, C06_stored=C06_TP_Gap)]
chkc <- merge(c_panel[, .(Date,Ticker,z_esbr_1,z_tpgap_1)], cpm, by=c("Date","Ticker"))
cat(sprintf("[C recompute vs stored aligned-Z] C04(esbr_1) cor=%.4f  C06(tpgap_1) cor=%.4f\n",
    chkc[!is.na(C04_stored), .(c=cor(z_esbr_1,C04_stored)), by=Date][, mean(c,na.rm=TRUE)],
    chkc[!is.na(C06_stored), .(c=cor(z_tpgap_1,C06_stored)), by=Date][, mean(c,na.rm=TRUE)]))
saveRDS(c_panel, file.path(SA,"c_variants.rds"))
cat("\n[saved] m08_variants.rds + c_variants.rds\n")
