## P0 — 데이터층 실측 (설계 전 관문): 로드 비용 · 팩터 수 · 앵커 지문
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")

avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\d{6}\.parquet$")
yms <- sort(gsub("factor_db_(\d{6})\.parquet", "\1", avail))
yms <- yms[yms >= "200501"]
sd0 <- as.Date(paste0(substr(yms,1,4),"-",substr(yms,5,6),"-01"))
sig_dates <- as.Date(vapply(sd0, function(d) as.character(seq(as.Date(d), by="month", length.out=2)[2]-1), character(1)))
cat(sprintf("sig_dates: %d  %s ~ %s\n", length(sig_dates), min(sig_dates), max(sig_dates)))

t0 <- Sys.time()
x <- load_month_factors(sig_dates[70])
cat(sprintf("1개월 전체팩터 로드: %.2f초 · %d행 · %d팩터 · %d종목\n",
            as.numeric(difftime(Sys.time(), t0, units="secs")),
            nrow(x), uniqueN(x$Factor_Name), uniqueN(x$Ticker)))

## 앵커 지문 검증 — M04_Mom_1 평균 IC (+0.0170 정상 / -0.9423 결함)
FAC <- "M04_Mom_1"
fl <- rbindlist(lapply(sig_dates, function(d) {
  y <- tryCatch(load_month_factors(d, factor_names = FAC), error=function(e) NULL)
  if (is.null(y) || !nrow(y)) return(NULL)
  y <- as.data.table(y)[Factor_Name == FAC & is.finite(Z_Score_Aligned)]
  if (!nrow(y)) return(NULL)
  data.table(sig_date = as.Date(d), Ticker = as.character(y$Ticker), z = as.numeric(y$Z_Score_Aligned))
}), fill = TRUE)
nextm <- function(d) as.Date(cut(as.Date(d) + 40L, "month"))
fl[, anchor := nextm(sig_date)]
raw <- as.data.table(read_parquet(".cache/RAWDATA.parquet")); raw[, Date := as.Date(Date)]
fr <- build_monthly_forward_returns(raw, sort(unique(fl$anchor)))
frd <- as.data.table(fr$returns_dt)
m <- merge(fl[, .(Date=anchor, Ticker, z)], frd[, .(Date, Ticker, Ret_1m)], by=c("Date","Ticker"))
ic_fix <- m[, .(ic = suppressWarnings(cor(z, Ret_1m, method="spearman"))), by=Date][is.finite(ic)]
cat(sprintf("[FIXED frame] M04_Mom_1 평균 Spearman IC = %.4f  (n=%d개월)\n", mean(ic_fix$ic), nrow(ic_fix)))
## 결함 프레임 대조 (팩터 Date 를 sig_date 로 그대로 넘김)
fr2 <- build_monthly_forward_returns(raw, sort(unique(fl$sig_date)))
frd2 <- as.data.table(fr2$returns_dt)
m2 <- merge(fl[, .(Date=sig_date, Ticker, z)], frd2[, .(Date, Ticker, Ret_1m)], by=c("Date","Ticker"))
ic_bad <- m2[, .(ic = suppressWarnings(cor(z, Ret_1m, method="spearman"))), by=Date][is.finite(ic)]
cat(sprintf("[BROKEN frame] M04_Mom_1 평균 Spearman IC = %.4f  (n=%d개월)\n", mean(ic_bad$ic), nrow(ic_bad)))

## 벤치 basis 실측
bd <- as.data.table(fr$bench_dt)
cat(sprintf("bench_dt(build_monthly_forward_returns) rows=%d  mean=%.5f  ann=%.3f%%\n",
            nrow(bd), mean(bd$BM_Ret), (prod(1+bd$BM_Ret)^(12/nrow(bd))-1)*100))
bp <- as.data.table(read_parquet(".cache/benchmark.parquet"))
cat("benchmark.parquet cols:", paste(names(bp), collapse=", "), " rows=", nrow(bp), "\n")
print(utils::head(bp, 3)); print(utils::tail(bp, 3))
saveRDS(list(sig_dates=sig_dates, frd=frd, bench=bd, liq=as.data.table(fr$liq_dt)),
        "stage_artifacts/WT-D20260822_002/p0_returns.rds")
cat("[saved] p0_returns.rds\n")
