# r8_bench_check.R — 벤치 집중도 실측 대조 (Size 정의 sanity + 시계열)
suppressPackageStartupMessages({library(data.table);library(arrow)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[r8] ",fmt,"\n"),...))
r <- as.data.table(read_parquet(".cache/rawdata.parquet",
      col_select=c("Date","Ticker","Name","Close","Size","Float","K200","KQ150")))
r[, Date := as.Date(Date)]
x <- r[Date==as.Date("2026-06-30") & Ticker %in% c("A005930","A000660","A005380")]
say("Size 정의 확인 (2026-06-30):"); print(x[, .(Ticker,Name,Close,Size,Float,shares_implied=round(Size/Close,0))])
u <- r[Date==as.Date("2026-06-30") & (K200==TRUE|KQ150==TRUE)]
say("유니버스 %d종 | 총 Size %s", nrow(u), format(sum(u$Size), big.mark=","))
say("삼성전자 %.4f | SK하이닉스 %.4f",
    x[Ticker=="A005930"]$Size/sum(u$Size), x[Ticker=="A000660"]$Size/sum(u$Size))
say("── 벤치 집중도 시계열 (연 1회 + 최근) ──")
out <- list()
for (d in seq(as.Date("2010-06-30"), as.Date("2026-06-30"), by="6 months")) {
  d <- as.Date(d)
  dd <- max(r$Date[r$Date <= d]); uu <- r[Date==dd & (K200==TRUE|KQ150==TRUE)]
  if (!nrow(uu)) next
  w <- uu$Size/sum(uu$Size); o <- order(-w)
  out[[length(out)+1]] <- data.table(Date=dd, n=nrow(uu), top1_nm=uu$Name[o[1]], top1=round(w[o[1]],4),
    top2_nm=uu$Name[o[2]], top2=round(w[o[2]],4), hhi=round(sum(w^2),4), n_eff=round(1/sum(w^2),1),
    over20 = sum(w>0.20), uncappable = round(sum(pmax(0,w-0.20)),4))
}
O <- rbindlist(out); print(O[seq(1, .N, by=2)]); print(tail(O, 6))
saveRDS(O, "stage_artifacts/WT_D20260808_001/risk/r8_bench.rds")
