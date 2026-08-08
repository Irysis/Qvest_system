suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
D <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
R <- as.data.table(read_parquet(".cache/rawdata.parquet"))
setnames(R, old=intersect(names(R),"Size"), new="Sz", skip_absent=TRUE)

## compute_value.R 와 동일 절차: Factor_Date<=sig 최신 Ticker×Item, use_val=Value (TTM_Value 부재)
snap_factor <- function(sig, itm="OperatingProfit") {
  f <- D[Item==itm & Factor_Date <= sig]
  if (!nrow(f)) return(NULL)
  setorder(f, Ticker, Factor_Date); f <- f[, .SD[.N], by=Ticker]
  p <- R[Date <= sig][, .SD[.N], by=Ticker][, .(Ticker, Sz)]
  z <- merge(f[, .(Ticker, val=Value, Source, Period)], p, by="Ticker")[Sz>0 & is.finite(val)]
  z[, ep := val/Sz]
  z[, rk := frank(ep)/.N]
  z
}
say("=== 유량기반 팩터(OperatingProfit/Size) 의 소스별 평균 백분위 서열 ===")
say("   (오염 없으면 두 군 모두 ~0.5 부근)")
out <- rbindlist(lapply(as.Date(c("2017-06-30","2019-06-30","2021-06-30","2023-06-30","2025-06-30")), function(sd){
  z <- snap_factor(sd); if (is.null(z)||!nrow(z)) return(NULL)
  a <- z[Source=="DART"]; b <- z[Source!="DART"]
  data.table(sig=sd, n=nrow(z), DART군=nrow(a), DART평균서열=round(mean(a$rk),3),
             XLSX평균서열=round(mean(b$rk),3), 서열격차=round(mean(a$rk)-mean(b$rk),3))
}))
print(out)
say("=== 상위 25 종목 중 DART 소스 비중 (전체 비중과 비교) ===")
for (sd in as.Date(c("2019-06-30","2023-06-30"))) {
  z <- snap_factor(sd); setorder(z, -ep)
  say("  %s : 전체 DART비중 %.3f → 상위25 중 DART %d/25 (%.2f)",
      sd, mean(z$Source=="DART"), sum(head(z,25)$Source=="DART"), mean(head(z,25)$Source=="DART"))
}
