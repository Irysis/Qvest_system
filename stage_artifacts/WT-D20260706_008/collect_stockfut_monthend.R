# Collect month-end single-stock futures snapshots (2016-2026) for WT-D20260706_008
# PIT: month-end = t-1 signal date (rebalance at t = next day). Basis/OI observed at close of me_date.
suppressPackageStartupMessages({library(data.table); library(httr); library(jsonlite); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/data/krx_data_collector.R")
KRX_API_BASE <- "https://data-dbg.krx.co.kr/svc/apis"
.num <- function(x) suppressWarnings(as.numeric(gsub(",","",x)))
OUT <- "stage_artifacts/WT-D20260706_008"

fetch_ep <- function(endpoint, date_str, max_retry=2) {
  url <- paste0(KRX_API_BASE, endpoint)
  for (att in 1:max_retry) {
    resp <- tryCatch(POST(url, body=toJSON(list(basDd=date_str),auto_unbox=TRUE),
      add_headers(`AUTH_KEY`=trimws(KRX_API_KEY),`Content-Type`="application/json",`Accept`="application/json"),
      encode="raw", content_type_json(), timeout(30)), error=function(e) NULL)
    if (!is.null(resp) && status_code(resp)==200) {
      parsed <- tryCatch(fromJSON(content(resp,"text",encoding="UTF-8")), error=function(e) NULL)
      if (!is.null(parsed$OutBlock_1)) { Sys.sleep(0.4); return(as.data.table(parsed$OutBlock_1)) }
    }
    Sys.sleep(1)
  }
  return(NULL)
}

parse_snapshot <- function(dt, mkt) {
  if (is.null(dt) || nrow(dt)==0) return(NULL)
  dt[, underlying := trimws(sub("선물$","", PROD_NM))]
  dt <- dt[!grepl("^ETF ", underlying)]
  dt[, `:=`(clsprc=.num(TDD_CLSPRC), spot=.num(SPOT_PRC), setl=.num(SETL_PRC),
            vol=.num(ACC_TRDVOL), val=.num(ACC_TRDVAL), oi=.num(ACC_OPNINT_QTY))]
  dt[, expiry := suppressWarnings(as.integer(sub(".*F ", "", ISU_NM)))]
  dt <- dt[!is.na(expiry) & !is.na(spot) & spot>0]
  if (nrow(dt)==0) return(NULL)
  setorder(dt, underlying, expiry)
  # front-month: nearest expiry per underlying
  front <- dt[, .SD[which.min(expiry)], by=underlying]
  front[, fut_use := fifelse(!is.na(clsprc)&clsprc>0, clsprc, setl)]
  front <- front[!is.na(fut_use) & fut_use>0]
  front[, basis_pct := (fut_use - spot)/spot*100]
  # aggregate OI/vol across ALL maturities per underlying (positioning depth)
  agg <- dt[, .(tot_oi=sum(oi,na.rm=TRUE), tot_vol=sum(vol,na.rm=TRUE), tot_val=sum(val,na.rm=TRUE)), by=underlying]
  out <- merge(front[, .(underlying, mkt=mkt, spot, fut_use, basis_pct, front_oi=oi, front_vol=vol, front_val=val, expiry)],
               agg, by="underlying")
  out
}

me <- fread(file.path(OUT,"monthend_dates.csv"))
res_list <- list()
for (i in seq_len(nrow(me))) {
  d <- me$basDd[i]
  fk <- fetch_ep("/drv/eqsfu_stk_bydd_trd", d)
  fq <- fetch_ep("/drv/eqkfu_ksq_bydd_trd", d)
  sk <- parse_snapshot(fk, "KOSPI")
  sq <- parse_snapshot(fq, "KOSDAQ")
  snap <- rbindlist(list(sk, sq), use.names=TRUE, fill=TRUE)
  if (!is.null(snap) && nrow(snap)>0) { snap[, me_date := me$me_date[i]]; res_list[[d]] <- snap }
  if (i %% 12 == 0) cat(sprintf("  [%d/%d] %s -> %d names\n", i, nrow(me), d, if(!is.null(snap)) nrow(snap) else 0L))
}
allsnap <- rbindlist(res_list, use.names=TRUE, fill=TRUE)
write_parquet(allsnap, file.path(OUT,"stockfut_monthend_raw.parquet"))
cat("DONE. Total rows:", nrow(allsnap), " months:", uniqueN(allsnap$me_date), "\n")
cat("Names per month summary:\n")
print(summary(allsnap[, .N, by=me_date]$N))
