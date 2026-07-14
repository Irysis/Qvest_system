suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
data.table::setDTthreads(1); arrow::set_io_thread_count(2)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
PIN <- file.path(QM, ".cache/pin/rawdata_r9_pin_20260715.parquet")
cols <- c("Date","Ticker","Close","Ret","K200","KQ150","source")
raw <- as.data.table(read_parquet(PIN, col_select=tidyselect::all_of(cols)))
raw[, Date:=as.Date(Date)]

cat("=== A004415 (max Δ) 2026-04 ~ 07 일자 시퀀스 (구멍 실증) ===\n")
print(raw[Ticker=="A004415" & Date>=as.Date("2026-04-25") & Date<=as.Date("2026-07-08"),
   .(Date, Close, Ret=round(Ret,4), source)][order(Date)])

cat("\n=== 유니버스 종목 삼성전자 A005930 동기간 연속성 (구멍 없음 기대) ===\n")
ss <- raw[Ticker=="A005930" & Date>=as.Date("2026-04-27") & Date<=as.Date("2026-07-08"),
   .(Date, Close, Ret=round(Ret,4), source)][order(Date)]
print(ss)
cat(sprintf(" 삼성전자 거래일수 04-27~07-08 = %d (연속=구멍없음)\n", nrow(ss)))

# 현 북 14보유 종목의 동기간 gap 점검
BOOK <- c("A005930","A000660","A319660","A034730","A095610","A011070","A007340",
          "A023530","A004170","A402340","A222800","A003030","A290650","A189300")
cat("\n=== 현 북 14보유 2026-04~07 gap 점검 (max gapdays) ===\n")
setorder(raw, Ticker, Date)
bk <- raw[Ticker %in% BOOK & Date>=as.Date("2026-04-01") & Date<=as.Date("2026-07-10")]
bk[, gd := as.integer(Date - shift(Date)), by=Ticker]
print(bk[, .(n_days=.N, max_gapdays=max(gd,na.rm=TRUE), any_gap_gt3=any(gd>3,na.rm=TRUE)), by=Ticker])

# 유니버스 전체 04-29→07-02 구멍 있는 종목 수 (in-universe 데이터 완결성)
cat("\n=== K200∪KQ150 유니버스 종목 중 2026-04-30~07-01 구간 데이터 보유일 분포 ===\n")
uni_tk <- raw[(K200==1|KQ150==1) & Date==as.Date("2026-07-02"), unique(Ticker)]
seg <- raw[Ticker %in% uni_tk & Date>=as.Date("2026-04-30") & Date<=as.Date("2026-07-01"),
   .(n=.N), by=Ticker]
cat(sprintf(" 유니버스 07-02 활성종목 %d개, 04-30~07-01 구간 보유일 요약:\n", length(uni_tk)))
print(summary(seg$n))
cat(sprintf(" 보유일<30 (구멍 의심) 유니버스 종목: %d\n", seg[n<30,.N]))
