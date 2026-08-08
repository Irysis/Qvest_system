suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
T4 <- as.data.table(read_parquet(".cache/fundamental_xlsx_ttm.parquet"))
D  <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
D2 <- merge(D, unique(T4[, .(Ticker,Period,Item,TTM_Value)]), by=c("Ticker","Period","Item"), all.x=TRUE)
D2[, val_fix := fifelse(Source=="DART", Value, TTM_Value)]
R <- as.data.table(read_parquet(".cache/rawdata.parquet"))
R[, inuniv := (!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]

## ★공통 지지집합 통제: 두 방식 모두 유효값이 있는 종목만 남긴다 (결손≠차이)
pair <- function(sig, itm) {
  f <- D2[Item==itm & Factor_Date <= sig]
  if (!nrow(f)) return(NULL)
  setorder(f, Ticker, Factor_Date); f <- f[, .SD[.N], by=Ticker]
  p <- R[Date <= sig & inuniv==TRUE][, .SD[.N], by=Ticker][, .(Ticker, Sz=Size)]
  z <- merge(f[, .(Ticker, Value, val_fix, Source)], p, by="Ticker")
  z <- z[Sz>0 & is.finite(Value) & is.finite(val_fix)]     # ← 공통 지지
  z
}
jac <- function(a,b) length(intersect(a,b))/length(union(a,b))
dates <- as.Date(paste0(2016:2025,"-06-30"))
say("=== 공통 지지집합 통제 후: 현행 raw vs 소스-인지 TTM ===")
for (itm in c("OperatingProfit","Revenue","OperatingCF")) {
  rows <- rbindlist(lapply(dates, function(sd){
    z <- pair(sd,itm); if (is.null(z)||nrow(z)<30) return(NULL)
    a <- z[order(-Value/Sz)][1:25]$Ticker
    b <- z[order(-val_fix/Sz)][1:25]$Ticker
    data.table(sd=sd, n=nrow(z), dart=mean(z$Source=="DART"), j=jac(a,b),
               스케일불일치=mean(abs(z$val_fix/z$Value - 1) > 0.01))
  }))
  if (!nrow(rows)) { say("  %s: 표본 부족", itm); next }
  say("  %-16s n중앙 %4.0f · DART비중 %.2f · 자카드 중앙 %.3f (최소 %.3f) · 값이바뀐종목 %.2f",
      itm, median(rows$n), median(rows$dart), median(rows$j), min(rows$j), median(rows$스케일불일치))
}
say("=== 참고: 교정이 값을 바꾸는 정도 (XLSX군, TTM/분기값 배수) ===")
z <- D2[Source!="DART" & is.finite(Value) & is.finite(TTM_Value) & Value>0]
say("  중앙값 %.2f · q25 %.2f · q75 %.2f  (분기→TTM 이므로 ~4 기대)",
    median(z$TTM_Value/z$Value), quantile(z$TTM_Value/z$Value,.25), quantile(z$TTM_Value/z$Value,.75))
