## ============================================================================
## R29 (FQ-044, WT-D20260714_005) — Z6 value blend PIT-clean re-measurement
## Stage 1: build value blend (V14_EBIT_EV + V07_EV_EBITDA) panels at
##   value-vintage {off0 = T-1 (factor_db_M, PIT-clean) / off1 = same-month (factor_db_M+1, look-ahead)}
##   from factor_db (aligned z) — vintage-consistent with R28 recon base.
##   Also reproduce R27's pure_factor_scores value (ym-aligned) for parity/vintage check.
## READ-ONLY vs 05_Production. book_state 무변경. DART API 미사용.
## ============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table); library(dplyr); library(lubridate); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_005")
source(file.path(QM,"02_Infrastructure/config.R"))
source(file.path(QM,"02_Infrastructure/factor_db/factor_db_connector.R"))
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}

VAL_FACS <- c("V14_EBIT_EV","V07_EV_EBITDA")
reg <- .load_registry()

## recon base panel (R28) — dates + membership
PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet")))
PAN[,Date:=as.Date(Date)]
d0s <- sort(unique(PAN$Date))
cat(sprintf("recon dates: %d (%s..%s)\n", length(d0s), as.character(min(d0s)), as.character(max(d0s))))

## ---- factor_db value extractor: aligned z of V14+V07, blended -> vz (per month) ----
## returns data.table(Ticker, vz) for one factor_db file + AS_OF (align sig_date)
build_value_fdb <- function(fdp, AS_OF, keep_tickers){
  if(!file.exists(fdp)) return(NULL)
  f <- as.data.table(read_parquet(fdp, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  f <- f[Factor_Name %in% VAL_FACS & Coverage==TRUE & is.finite(Z_Score),.(Ticker,Factor_Name,Z_Score)]
  if(length(setdiff(VAL_FACS, unique(f$Factor_Name)))) return(NULL)
  f[,sig_date:=AS_OF]
  fa <- align_factor_direction(f, reg, sig_date=AS_OF, min_ic_months=12L)
  if("Z_Score_Aligned" %in% names(fa)) fa[,Z_Score:=Z_Score_Aligned]
  fw <- dcast(fa, Ticker~Factor_Name, value.var="Z_Score", fill=NA_real_)
  ## restrict to base-panel membership (same set the base score lives on), then per-month z
  fw <- fw[Ticker %in% keep_tickers]
  fw <- fw[is.finite(V14_EBIT_EV) & is.finite(V07_EV_EBITDA)]
  if(nrow(fw) < 10) return(NULL)
  fw[,v14z:=zc(V14_EBIT_EV)]; fw[,v07z:=zc(V07_EV_EBITDA)]
  fw[,raw:=v14z+v07z]; fw[,vz:=zc(raw)]
  fw[,.(Ticker, vz)]
}

## ---- pure_factor_scores value (R27 source), ym-aligned, for parity/vintage check ----
ds <- open_dataset("outputs/ramp/pure_factor_scores.parquet")
getz <- function(fid){d<-as.data.table(ds|>filter(factor_id==fid)|>select(signal_date,security_id,z)|>collect())
  d[,.(ym=format(as.Date(signal_date),"%Y-%m"), Ticker=security_id, z=z)]}
pV14 <- getz("V14_EBIT_EV"); pV07 <- getz("V07_EV_EBITDA")
pvb <- merge(pV14[,.(ym,Ticker,v14=z)], pV07[,.(ym,Ticker,v07=z)], by=c("ym","Ticker"))
pvb[,v14z:=zc(v14),by=ym]; pvb[,v07z:=zc(v07),by=ym]; pvb[,raw:=v14z+v07z]; pvb[,vz_pfs:=zc(raw),by=ym]
PFS <- pvb[,.(ym,Ticker,vz_pfs)]

## ---- main loop over recon dates ----
rows <- vector("list", length(d0s))
t0 <- Sys.time()
for(i in seq_along(d0s)){
  d0 <- d0s[i]
  AS_OF <- as.Date(paste0(format(d0 %m+% months(1),"%Y-%m"),"-01"))     # score-label month = M+1
  keep <- PAN[Date==d0 & (is.finite(`0_stored_S7`)|is.finite(`0_ic_S7`)|is.finite(`1_stored_S7`)|is.finite(`1_ic_S7`)), Ticker]
  fdp0 <- file.path(QM, sprintf(".cache/factor_db/factor_db_%s.parquet", format(AS_OF-1,"%Y%m")))                              # T-1 (month M) = clean
  fdp1 <- file.path(QM, sprintf(".cache/factor_db/factor_db_%s.parquet", format(as.Date(paste0(format(AS_OF,"%Y-%m"),"-01")),"%Y%m")))  # same-month (M+1) = look-ahead
  v0 <- tryCatch(build_value_fdb(fdp0, AS_OF, keep), error=function(e) NULL)
  v1 <- tryCatch(build_value_fdb(fdp1, AS_OF, keep), error=function(e) NULL)
  acc <- data.table(Date=d0, Ticker=keep)
  if(!is.null(v0)) acc <- merge(acc, v0[,.(Ticker, vz_off0=vz)], by="Ticker", all.x=TRUE)
  if(!is.null(v1)) acc <- merge(acc, v1[,.(Ticker, vz_off1=vz)], by="Ticker", all.x=TRUE)
  rows[[i]] <- acc
  if(i %% 40 == 0) cat(sprintf("  ...%d/%d (%s) %.1fs\n", i, length(d0s), as.character(d0), as.numeric(Sys.time()-t0,units="secs")))
}
VP <- rbindlist(rows, fill=TRUE)
## attach pure_factor_scores value by ym
VP[,ym:=format(Date,"%Y-%m")]
VP <- merge(VP, PFS, by=c("ym","Ticker"), all.x=TRUE)
VP[,ym:=NULL]
for(cc in c("vz_off0","vz_off1","vz_pfs")) if(!cc %in% names(VP)) VP[,(cc):=NA_real_]
cat(sprintf("\nvalue panel: %d rows, %d months. finite: off0=%d off1=%d pfs=%d\n",
  nrow(VP), uniqueN(VP$Date), sum(is.finite(VP$vz_off0)), sum(is.finite(VP$vz_off1)), sum(is.finite(VP$vz_pfs))))
save_safe(VP, file.path(WT,"value_panels.parquet"), function(o,p) write_parquet(o,p))

## ---- vintage parity: does pure_factor_scores value match off0 (clean) or off1 (look-ahead)? ----
par <- VP[is.finite(vz_pfs)]
per_off0 <- par[is.finite(vz_off0), .(c=if(.N>=10 && sd(vz_off0)>0 && sd(vz_pfs)>0) cor(vz_off0,vz_pfs) else NA_real_), by=Date]
per_off1 <- par[is.finite(vz_off1), .(c=if(.N>=10 && sd(vz_off1)>0 && sd(vz_pfs)>0) cor(vz_off1,vz_pfs) else NA_real_), by=Date]
cat(sprintf("\n=== VALUE VINTAGE PARITY (pure_factor_scores vs factor_db) ===\n"))
cat(sprintf("  median cor(vz_pfs, vz_off0[T-1 clean])  = %.4f  (n=%d)\n", median(per_off0$c,na.rm=TRUE), sum(!is.na(per_off0$c))))
cat(sprintf("  median cor(vz_pfs, vz_off1[same-month LA]) = %.4f  (n=%d)\n", median(per_off1$c,na.rm=TRUE), sum(!is.na(per_off1$c))))
## also off0 vs off1 (how different are the two value vintages?)
per_v <- VP[is.finite(vz_off0)&is.finite(vz_off1),.(c=if(.N>=10&&sd(vz_off0)>0&&sd(vz_off1)>0) cor(vz_off0,vz_off1) else NA_real_),by=Date]
cat(sprintf("  median cor(vz_off0, vz_off1)              = %.4f  (value vintage self-seam)\n", median(per_v$c,na.rm=TRUE)))
saveRDS(list(par_off0=median(per_off0$c,na.rm=TRUE), par_off1=median(per_off1$c,na.rm=TRUE),
             self_seam=median(per_v$c,na.rm=TRUE)), file.path(WT,"value_vintage_parity.rds"))
cat("BUILD_VALUE_DONE\n")
