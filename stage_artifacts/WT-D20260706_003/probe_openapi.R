suppressPackageStartupMessages({ library(httr); library(jsonlite) })
PR <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
KEY <- Sys.getenv("KRX_API_KEY")
if(KEY==""){ el<-readLines(file.path(PR,".env"),warn=FALSE); kl<-grep("^KRX_API_KEY=",el,value=TRUE); if(length(kl))KEY<-sub("^KRX_API_KEY=","",kl[1]) }
tryp <- function(base, ep, params, hdr=NULL) {
  url <- paste0(base, ep)
  hd <- add_headers(`AUTH_KEY`=trimws(KEY), `Content-Type`="application/json", `Accept`="application/json")
  r <- tryCatch(POST(url, body=toJSON(params,auto_unbox=TRUE), hd, encode="raw", content_type_json(), timeout(20)),
    error=function(e){cat("[ERR]",conditionMessage(e),"\n");NULL})
  if(is.null(r)) return()
  txt <- content(r,"text",encoding="UTF-8")
  cat(sprintf("%-45s HTTP %d  head=%s\n", ep, status_code(r), substr(gsub("\n"," ",txt),1,90)))
}
# data-dbg host: does the srt (short) service group exist at all under any name?
cat("--- data-dbg.krx.co.kr /svc/apis ---\n")
B1 <- "https://data-dbg.krx.co.kr/svc/apis"
for(ep in c("/srt/sslt_bydd_trd","/srt/ssts_bydd_trd","/srt/sbst_bydd_trd",
            "/sto/ksq_bydd_trd")) tryp(B1, ep, list(basDd="20260630"))
