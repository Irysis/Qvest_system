suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))

T4 <- as.data.table(read_parquet(".cache/fundamental_xlsx_ttm.parquet"))
say("TTM 파일 컬럼: %s | 행 %d", paste(names(T4),collapse=","), nrow(T4))
say("TTM non-NA 비율: %.3f", mean(!is.na(T4$TTM_Value)))

D <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
## 소스-인지 교정: XLSX/xlsx_derived 행에 TTM_Value 결합, DART 행은 Value 자체가 TTM
key <- c("Ticker","Period","Item")
D2 <- merge(D, unique(T4[, .(Ticker, Period, Item, TTM_Value)]), by=key, all.x=TRUE)
D2[, val_fix := fifelse(Source=="DART", Value, TTM_Value)]
say("교정값 결측률: 전체 %.3f · XLSX계 %.3f · DART %.3f",
    mean(is.na(D2$val_fix)), mean(is.na(D2[Source!="DART"]$val_fix)), mean(is.na(D2[Source=="DART"]$val_fix)))

R <- as.data.table(read_parquet(".cache/rawdata.parquet"))
R[, inuniv := (!is.na(K200) & K200==1) | (!is.na(KQ150) & KQ150==1)]

top25 <- function(sig, itm, usefix) {
  f <- D2[Item==itm & Factor_Date <= sig]
  if (!nrow(f)) return(character(0))
  setorder(f, Ticker, Factor_Date); f <- f[, .SD[.N], by=Ticker]
  f[, v := if (usefix) val_fix else Value]
  p <- R[Date <= sig & inuniv==TRUE][, .SD[.N], by=Ticker][, .(Ticker, Sz=Size)]
  z <- merge(f[, .(Ticker, v)], p, by="Ticker")[Sz>0 & is.finite(v)]
  z[, sc := v/Sz]; setorder(z, -sc); head(z$Ticker, 25)
}
jac <- function(a,b) if(!length(a)&&!length(b)) NA_real_ else length(intersect(a,b))/length(union(a,b))

say("=== top-25 선별: 현행(raw Value) vs 교정(소스-인지 TTM) ===")
dates <- as.Date(paste0(2016:2025, "-06-30"))
for (itm in c("OperatingProfit","Revenue","OperatingCF")) {
  js <- sapply(dates, function(sd) jac(top25(sd,itm,FALSE), top25(sd,itm,TRUE)))
  say("  %-16s 자카드 중앙값 %.3f · 최소 %.3f · <0.8 비율 %.2f",
      itm, median(js,na.rm=TRUE), min(js,na.rm=TRUE), mean(js<0.8,na.rm=TRUE))
}
