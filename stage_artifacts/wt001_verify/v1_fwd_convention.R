suppressPackageStartupMessages({library(data.table); library(arrow)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001")
say <- function(...) cat(sprintf(...), "\n")

fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
r <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date), Ticker, Ret_1m)]
b <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date), BM_Ret)]
say("[SHAPE] returns_dt nrow=%d  n_date=%d  %s ~ %s", nrow(r), uniqueN(r$Date),
    as.character(min(r$Date)), as.character(max(r$Date)))
say("[SHAPE] bench_dt   nrow=%d  n_date=%d", nrow(b), uniqueN(b$Date))
dd <- sort(unique(r$Date))
say("[SHAPE] date spacing days: median=%.1f min=%d max=%d (관측단위 실측)",
    median(as.numeric(diff(dd))), min(as.numeric(diff(dd))), max(as.numeric(diff(dd))))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close")))[, Date:=as.Date(Date)]
say("[SHAPE] RAWDATA nrow=%d DAILY n_day=%d %s ~ %s", nrow(RAW), uniqueN(RAW$Date),
    as.character(min(RAW$Date)), as.character(max(RAW$Date)))
CL <- RAW[Date %in% dd]; rm(RAW); gc(verbose=FALSE)
setkey(CL, Ticker, Date)

# --- 정렬 규약 실측: Ret_1m(d) 이 FORWARD(d -> d+1) 인가 BACKWARD(d-1 -> d) 인가
idx <- setNames(seq_along(dd), as.character(dd))
r[, i := idx[as.character(Date)]]
smp <- r[i %in% seq(60, length(dd)-2, by=7)]
smp <- smp[sample(.N, min(40000, .N))]
smp[, d_next := dd[i+1L]][, d_prev := dd[i-1L]]
m <- merge(smp, CL[, .(Ticker, Date, C0=Close)], by.x=c("Ticker","Date"), by.y=c("Ticker","Date"))
m <- merge(m, CL[, .(Ticker, Date, C1=Close)], by.x=c("Ticker","d_next"), by.y=c("Ticker","Date"))
m <- merge(m, CL[, .(Ticker, Date, Cm1=Close)], by.x=c("Ticker","d_prev"), by.y=c("Ticker","Date"))
m <- m[is.finite(C0)&is.finite(C1)&is.finite(Cm1)&C0>0&Cm1>0]
m[, fwd_calc := C1/C0 - 1][, bwd_calc := C0/Cm1 - 1]
say("[CONV] n=%d  max|Ret_1m - FORWARD(d->d+1)| = %.3e   max|Ret_1m - BACKWARD(d-1->d)| = %.3e",
    nrow(m), max(abs(m$Ret_1m - m$fwd_calc)), max(abs(m$Ret_1m - m$bwd_calc)))
say("[CONV] cor(Ret_1m, forward)=%.6f   cor(Ret_1m, backward)=%.6f",
    cor(m$Ret_1m, m$fwd_calc), cor(m$Ret_1m, m$bwd_calc))
