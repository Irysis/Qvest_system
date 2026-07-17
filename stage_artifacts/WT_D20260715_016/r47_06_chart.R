#==============================================================================
# R47 STEP 06: 무결성 수리 차트 (구멍 채움 전/후 + parity) — 텔레그램 v7 첨부
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WT <- file.path(ROOT, "stage_artifacts", "WT_D20260715_016")
NEW <- file.path(ROOT, ".cache", "RAWDATA.parquet")
BAK <- file.path(ROOT, ".cache", "rawdata_pre_r47_backup_20260715.parquet")

# sample ticker: A005935 삼성전자우 (preferred, non-universe, 채워진 seam)
rd <- function(f, tk) {
  d <- as.data.table(read_parquet(f, col_select=c("Date","Ticker","Close")))
  d[Ticker==tk][, Date:=as.Date(Date)][Date>=as.Date("2026-04-15") & Date<=as.Date("2026-07-05")][order(Date)]
}
tk <- "A005935"
before <- rd(BAK, tk); after <- rd(NEW, tk)

png(file.path(WT, "r47_chart_integrity.png"), width=1280, height=900, res=110)
par(mfrow=c(2,2), mar=c(4,4.5,3.5,1.2), family="sans")
col_fill <- "#2e7d32"; col_before <- "#c62828"; col_grid <- "#e0e0e0"

# Panel A: source-seam holes before/after
barA <- c(245, 218, 29, 2)
names(barA) <- c("total\nBEFORE","seam\nBEFORE","total\nAFTER","seam\nAFTER")
bp <- barplot(barA, col=c(col_before,col_before,col_fill,col_fill), border=NA,
        main="A. Close 연속성 구멍: 채움 전 → 후", ylab="구멍 수 (hole records)", ylim=c(0,270))
text(bp, barA+10, labels=barA, font=2)
legend("topright", bty="n", legend=c("채움 전","채움 후"), fill=c(col_before,col_fill), border=NA)

# Panel B: fill rows by date
fr <- as.data.table(read_parquet(file.path(WT,"r47_fill_rows.parquet"), col_select=c("Date")))
fr[, Date:=as.Date(Date)]
byd <- fr[, .N, by=Date][order(Date)]
plot(byd$Date, byd$N, type="h", lwd=3, col=col_fill, main="B. 백필된 행수 (일별, 04-30~07-01)",
     xlab="", ylab="채운 종목 수 / 일", ylim=c(0,max(byd$N)*1.15))
abline(h=216, lty=3, col="grey60"); text(min(byd$Date), 216, "216 종목", pos=3, cex=0.8, col="grey40")

# Panel C: sample ticker Close before/after (gap 시각화)
plot(after$Date, after$Close, type="o", pch=16, cex=0.6, col=col_fill, lwd=1.6,
     main=sprintf("C. 예시 %s 삼성전자우: Close 시계열", tk), xlab="", ylab="Close (KRW)")
points(before$Date, before$Close, type="o", pch=1, cex=1.1, col=col_before, lwd=1.8)
legend("topleft", bty="n", legend=c("채움 후 (KRX 백필)","채움 전 (구멍=05·06월 결측)"),
       col=c(col_fill,col_before), pch=c(16,1), lwd=c(1.6,1.8))

# Panel D: parity summary (all 0 / PASS)
plot.new(); title(main="D. Parity 검증 (NEW vs 백업)")
lines_txt <- c(
  "P1 기존 데이터 무변경   : max|ΔRet|=0  max|ΔClose|=0   PASS",
  "P2 seam parity 회복      : source-seam 218→2  07-02  216/216  PASS",
  "P3 유니버스 월패널 무변경: 2,370,544행 불변  max|ΔRet|=0   PASS",
  "P4 현 북 14보유 무변경   : 71,125행 불변  max|ΔRet|=0     PASS",
  "가드 5종                 : 행수 정확(+8,856)·유니버스보호·collision0  PASS",
  "라이브 영향              : 없음 (fill 전량 non-universe microcap)")
for (i in seq_along(lines_txt))
  text(0.02, 0.92-(i-1)*0.15, lines_txt[i], adj=0, cex=0.92, family="mono",
       col=ifelse(grepl("PASS|없음", lines_txt[i]), col_fill, "black"))
dev.off()
cat("[done] chart:", file.path(WT,"r47_chart_integrity.png"), "\n")
