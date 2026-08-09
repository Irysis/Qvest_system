# probe_sector_pit.R — ③ 에 쓴 섹터 라벨이 시점-정합(PIT)인가.
#   정적 스냅샷을 전 역사에 소급 적용한 것이면 섹터-중립화에 미약한 미래참조가 섞인다.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(f,...) cat(sprintf(paste0("[secpit] ",f,"\n"),...))
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Sector")))
R[, Date := as.Date(Date)][, ym := format(Date,"%Y-%m")]
ME <- R[, .(d=max(Date)), by=ym]$d
X <- R[Date %in% ME & !is.na(Sector)]
v <- X[, .(n_uniq = uniqueN(Sector), n_month = .N), by = Ticker]
say("월말 관측 종목 %d", nrow(v))
say("섹터가 시간에 따라 변한 종목 %d (%.3f%%)", sum(v$n_uniq>1), 100*mean(v$n_uniq>1))
long <- v[n_month >= 60]
say("60개월 이상 관측 종목 %d 중 변화 %d (%.3f%%)", nrow(long), sum(long$n_uniq>1),
    100*mean(long$n_uniq>1))
say("⇒ %s", if (mean(long$n_uniq>1) < 0.02)
  "★섹터 라벨은 사실상 정적 — 현시점 분류의 소급 적용으로 보이며 섹터-중립화에 미약한 미래참조 성분이 있다(진단용이라 판정 영향은 없으나 라벨 의무)"
  else "섹터 라벨은 시변 — PIT 성 양호")
