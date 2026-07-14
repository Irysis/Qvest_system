## ============================================================================
## R31 (FQ-047, WT-D20260714_007) — value definition spectrum: build sub-axis panels
##   Sub-axes: BM(V01) EP(V02) CFP(V03) FCF(V10) SP(V20) SHY(V11) + EBIT_EV control(V14+V07)
##   Vintage: off0 = T-1 clean (factor_db month M = AS_OF-1), aligned z (C13). Same as R29.
##   READ-ONLY 05_Production/outputs. book_state unchanged. DART API not used. factor_db only.
## ============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table); library(lubridate)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_007")
source(file.path(QM,"02_Infrastructure/config.R"))
source(file.path(QM,"02_Infrastructure/factor_db/factor_db_connector.R"))
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}

## sub-axis -> factor(s). single-factor except control.
SUBAX <- list(
  BM  = "V01_BM",
  EP  = "V02_EP",
  CFP = "V03_CFP",
  FCF = "V10_FCF_Yield",
  SP  = "V20_SP",
  SHY = "V11_Shareholder_Yield"
)
ALL_FACS <- unique(unlist(SUBAX))
reg <- .load_registry()

## base panel (R28 clean) — dates + membership
PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet")))
PAN[,Date:=as.Date(Date)]
d0s <- sort(unique(PAN$Date))
cat(sprintf("recon dates: %d (%s..%s)\n", length(d0s), as.character(min(d0s)), as.character(max(d0s))))

## extractor: aligned z of each factor, per-month z, restricted to base membership
build_subax_fdb <- function(fdp, AS_OF, keep_tickers){
  if(!file.exists(fdp)) return(NULL)
  f <- as.data.table(read_parquet(fdp, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  f <- f[Factor_Name %in% ALL_FACS & Coverage==TRUE & is.finite(Z_Score),.(Ticker,Factor_Name,Z_Score)]
  if(nrow(f)==0) return(NULL)
  f[,sig_date:=AS_OF]
  fa <- align_factor_direction(f, reg, sig_date=AS_OF, min_ic_months=12L)
  if("Z_Score_Aligned" %in% names(fa)) fa[,Z_Score:=Z_Score_Aligned]
  fw <- dcast(fa, Ticker~Factor_Name, value.var="Z_Score", fill=NA_real_)
  fw <- fw[Ticker %in% keep_tickers]
  if(nrow(fw) < 10) return(NULL)
  out <- data.table(Ticker=fw$Ticker)
  for(sx in names(SUBAX)){
    facs <- SUBAX[[sx]]
    if(!all(facs %in% names(fw))){ out[,(sx):=NA_real_]; next }
    if(length(facs)==1){
      v <- fw[[facs]]
    } else {
      # blend: z each then sum then z (matches R29 control style, not used for singles)
      mm <- as.matrix(fw[, ..facs]); mm <- apply(mm,2,zc); v <- rowSums(mm)
    }
    out[, (sx) := zc(v)]   # per-month cross-sectional z (within base membership)
  }
  out
}

rows <- vector("list", length(d0s)); t0 <- Sys.time()
for(i in seq_along(d0s)){
  d0 <- d0s[i]
  AS_OF <- as.Date(paste0(format(d0 %m+% months(1),"%Y-%m"),"-01"))            # score-label month = M+1
  keep <- PAN[Date==d0 & (is.finite(`0_stored_S7`)|is.finite(`0_ic_S7`)), Ticker]
  fdp0 <- file.path(QM, sprintf(".cache/factor_db/factor_db_%s.parquet", format(AS_OF-1,"%Y%m")))  # T-1 clean
  v0 <- tryCatch(build_subax_fdb(fdp0, AS_OF, keep), error=function(e) NULL)
  acc <- data.table(Date=d0, Ticker=keep)
  if(!is.null(v0)) acc <- merge(acc, v0, by="Ticker", all.x=TRUE)
  rows[[i]] <- acc
  if(i %% 40 == 0) cat(sprintf("  ...%d/%d (%s) %.1fs\n", i, length(d0s), as.character(d0), as.numeric(Sys.time()-t0,units="secs")))
}
SP7 <- rbindlist(rows, fill=TRUE)
for(sx in names(SUBAX)) if(!sx %in% names(SP7)) SP7[,(sx):=NA_real_]

## attach EBIT_EV control (R30 vz_off0) for parity
VP <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_005/value_panels.parquet"))); VP[,Date:=as.Date(Date)]
SP7 <- merge(SP7, VP[,.(Date,Ticker,EBIT_EV=vz_off0)], by=c("Date","Ticker"), all.x=TRUE)

cat("\n=== sub-axis panel coverage (finite, within base membership) ===\n")
for(sx in c(names(SUBAX),"EBIT_EV")) cat(sprintf("  %-8s finite=%d\n", sx, sum(is.finite(SP7[[sx]]))))
cat(sprintf("panel rows=%d months=%d\n", nrow(SP7), uniqueN(SP7$Date)))
save_safe(SP7, file.path(WT,"subaxis_panels.parquet"), function(o,p) write_parquet(o,p))

## sub-axis pairwise cross-sectional corr (concern #1) — median over months, base membership
AX <- c(names(SUBAX),"EBIT_EV")
cormat <- matrix(NA_real_, length(AX), length(AX), dimnames=list(AX,AX))
for(a in AX) for(b in AX){
  per <- SP7[is.finite(get(a))&is.finite(get(b)), .(c=if(.N>=10 && sd(get(a))>0 && sd(get(b))>0) cor(get(a),get(b)) else NA_real_), by=Date]
  cormat[a,b] <- median(per$c, na.rm=TRUE)
}
cat("\n=== sub-axis median cross-sectional corr (base membership) ===\n")
print(round(cormat,2))
saveRDS(cormat, file.path(WT,"subaxis_corr.rds"))
cat("BUILD_PANELS_DONE\n")
