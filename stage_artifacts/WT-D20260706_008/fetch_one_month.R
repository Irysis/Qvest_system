# fetch ONE month's stock futures snapshot. arg = basDd (yyyymmdd). Writes RDS to temp.
suppressPackageStartupMessages({library(data.table); library(httr); library(jsonlite)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/data/krx_data_collector.R")
KRX_API_BASE <- "https://data-dbg.krx.co.kr/svc/apis"
.num <- function(x) suppressWarnings(as.numeric(gsub(",","",x)))
SNAPDIR <- "C:/Users/99922/AppData/Local/Temp/claude/wt008_snap"; if(!dir.exists(SNAPDIR)) dir.create(SNAPDIR, recursive=TRUE)
args <- commandArgs(trailingOnly=TRUE)
d <- args[1]; me_date <- args[2]
fetch_ep <- function(endpoint, date_str, max_retry=2) {
  url <- paste0(KRX_API_BASE, endpoint)
  for (att in 1:max_retry) {
    resp <- tryCatch(POST(url, body=toJSON(list(basDd=date_str),auto_unbox=TRUE),
      add_headers(`AUTH_KEY`=trimws(KRX_API_KEY),`Content-Type`="application/json",`Accept`="application/json"),
      encode="raw", content_type_json(), timeout(30)), error=function(e) NULL)
    if (!is.null(resp) && status_code(resp)==200) {
      parsed <- tryCatch(fromJSON(content(resp,"text",encoding="UTF-8")), error=function(e) NULL)
      if (!is.null(parsed$OutBlock_1)) return(as.data.table(parsed$OutBlock_1))
    }
    Sys.sleep(1)
  }
  NULL
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
  front <- dt[, .SD[which.min(expiry)], by=underlying]
  front[, fut_use := fifelse(!is.na(clsprc)&clsprc>0, clsprc, setl)]
  front <- front[!is.na(fut_use) & fut_use>0]
  front[, basis_pct := (fut_use - spot)/spot*100]
  agg <- dt[, .(tot_oi=sum(oi,na.rm=TRUE), tot_vol=sum(vol,na.rm=TRUE), tot_val=sum(val,na.rm=TRUE)), by=underlying]
  merge(front[, .(underlying, mkt=mkt, spot, fut_use, basis_pct, front_oi=oi, front_vol=vol, front_val=val, expiry)],
        agg, by="underlying")
}
fk <- fetch_ep("/drv/eqsfu_stk_bydd_trd", d); fq <- fetch_ep("/drv/eqkfu_ksq_bydd_trd", d)
sk <- parse_snapshot(fk,"KOSPI"); sq <- parse_snapshot(fq,"KOSDAQ")
snap <- rbindlist(list(sk,sq),use.names=TRUE,fill=TRUE)
if (!is.null(snap) && nrow(snap)>0) { snap[, me_date := as.Date(me_date)]; saveRDS(snap, file.path(SNAPDIR, sprintf("snap_%s.rds", d))); cat(d,"->",nrow(snap),"names\n") } else cat(d,"-> EMPTY\n")
