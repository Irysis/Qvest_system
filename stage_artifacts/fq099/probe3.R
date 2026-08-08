suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
D <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
D[, mm := substr(as.character(Period), 5, 6)]
say("--- Source x 월(Period 끝2자리) ---"); print(dcast(D[, .N, by=.(Source,mm)], mm~Source, value.var="N", fill=0))

## P/L 항목 하나 골라 스케일 교대를 직접 잰다
pl <- intersect(c("NetIncome","OperatingIncome","Revenue","Sales","NetProfit"), unique(D$Item))
say("P/L 후보 in merged: %s", paste(pl, collapse=", "))
if (!length(pl)) { say("항목명 스캔:"); print(head(sort(unique(D$Item)), 60)) }
for (itm in head(pl,2)) {
  say("=== %s ===", itm)
  S <- D[Item==itm & Value>0]
  S[, yr := as.integer(substr(as.character(Period),1,4))]
  ## 같은 종목-연도에서 Dec(연간 or 분기) vs Sep(분기) 비율
  w <- dcast(S[mm %in% c("09","12")], Ticker+yr ~ mm, value.var=c("Value","Source"), fun.aggregate=function(z) z[1])
  setnames(w, c("Value_09","Value_12","Source_09","Source_12"), c("v09","v12","s09","s12"), skip_absent=TRUE)
  w <- w[!is.na(v09) & !is.na(v12) & v09>0]
  w[, ratio := v12/v09]
  say("  Dec소스별 Dec/Sep 값 비율 중앙값 (분기끼리면 ~1, 연간/분기면 ~4):")
  print(w[, .(n=.N, ratio_med=round(median(ratio),3), q25=round(quantile(ratio,.25),2), q75=round(quantile(ratio,.75),2)), by=.(Dec소스=s12)][order(Dec소스)])
}
