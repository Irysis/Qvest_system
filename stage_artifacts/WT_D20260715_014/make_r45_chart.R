suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
data.table::setDTthreads(1); arrow::set_io_thread_count(2)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- file.path(QM, "stage_artifacts/WT_D20260715_014")
m <- fread(file.path(OUT,"mismatch_census_ALL.csv")); m[,Date:=as.Date(Date)]

# A004415 gap example
PIN <- file.path(QM, ".cache/pin/rawdata_r9_pin_20260715.parquet")
raw <- as.data.table(read_parquet(PIN, col_select=c("Date","Ticker","Close","Ret")))
raw[,Date:=as.Date(Date)]
ex <- raw[Ticker=="A004415" & Date>=as.Date("2026-04-20") & Date<=as.Date("2026-07-10")][order(Date)]

png(file.path(OUT,"chartA_r45_diagnosis.png"), width=1180, height=640, res=110)
par(mfrow=c(1,2), mar=c(4.2,4.4,3.4,1.2), family="sans")

# Panel 1: magnitude buckets, colored by universe (all non-universe)
bk <- c("0.01-0.05","0.05-0.10","0.10-0.30","0.30-1.0",">1.0")
n_all  <- c(m[dAbs>0.01&dAbs<=0.05,.N], m[dAbs>0.05&dAbs<=0.10,.N], m[dAbs>0.10&dAbs<=0.30,.N], m[dAbs>0.30&dAbs<=1.0,.N], m[dAbs>1.0,.N])
n_univ <- c(m[in_univ==TRUE&dAbs>0.01&dAbs<=0.05,.N], m[in_univ==TRUE&dAbs>0.05&dAbs<=0.10,.N], m[in_univ==TRUE&dAbs>0.10&dAbs<=0.30,.N], m[in_univ==TRUE&dAbs>0.30&dAbs<=1.0,.N], m[in_univ==TRUE&dAbs>1.0,.N])
bp <- barplot(n_all, names.arg=bk, col="#c44e52", border=NA, las=2, cex.names=0.82,
   ylab="종목-일 수", main="① 불일치 규모분포 (총 196, |Δ|>0.01)", ylim=c(0,max(n_all)*1.25))
text(bp, n_all, labels=n_all, pos=3, cex=0.85, col="#333")
legend("topright", legend=c("전체(196)","유니버스內(0)"), fill=c("#c44e52","#4c72b0"), border=NA, bty="n", cex=0.85)
mtext("유니버스內 0건 — 전부 비-유니버스 소형/우선주", side=3, line=-1.2, cex=0.72, col="#4c72b0")

# Panel 2: A004415 close series showing hole
plot(ex$Date, ex$Close, type="n", xlab="", ylab="종가(원)",
   main="② 근원: Close 시계열 구멍 (A004415, max Δ)", cex.main=0.98)
# highlight the gap
rect(as.Date("2026-04-30"), par("usr")[3], as.Date("2026-07-01"), par("usr")[4],
   col="#f2dede", border=NA)
lines(ex$Date, ex$Close, type="o", pch=19, col="#c44e52", cex=0.8)
text(as.Date("2026-05-30"), mean(range(ex$Close)), "결측 구간\n04-30~07-01\n(64일 hole)", col="#a94442", cex=0.8)
text(as.Date("2026-04-29"), 1193, "1193", pos=3, cex=0.75)
text(as.Date("2026-07-02"), 7030, "7030\n(stored Ret=+2.9%,\n recompute=+489%)", pos=1, cex=0.7, col="#c44e52")
dev.off()
cat("[chart] chartA_r45_diagnosis.png 저장\n")
