## WT-R20260829_005 Optimizer — Step A: baseline reconciliation
## 목적: alpha 단계의 EW top-25 구성/비용 규약을 정확히 재현하는지 실증.
##       재현되지 않으면 아래 모든 method 비교의 basis 가 alpha 와 어긋난다.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})

A <- as.data.table(read_parquet("stage_artifacts/WT_R20260829_005/alpha_scores.parquet"))
P <- readRDS("stage_artifacts/WT_R20260829_005/panel.rds")
RET <- as.data.table(P$fwd$returns_dt)   # Date(=signal month-end t) x Ticker x Ret_1m (holding month t+1)
BM  <- as.data.table(P$fwd$bench_dt)
PRD <- fread("stage_artifacts/WT_R20260829_005/period_returns_production.csv")
PRD[, signal_date := as.Date(signal_date)]

setkey(RET, Date, Ticker)
dates <- sort(unique(A$Date))
cat("dates:", length(dates), "\n")

## --- top-25 selection by alpha score (alpha 소유 랭킹 — 재해석 없음) ---
sel <- A[order(Date, -score, Ticker), .(Ticker, score, alpha_hat, alpha_lb, confidence, adv20_t1), by = Date][
        , head(.SD, 25L), by = Date]
cat("names per date: min", min(sel[, .N, by=Date]$N), " max", max(sel[, .N, by=Date]$N), "\n")

## --- EW weights ---
ew <- sel[, .(Date, Ticker, w = 1/.N), by = Date][, .(Date, Ticker, w)]

## --- generic evaluator ---
eval_sched <- function(W, cost_bps = 15) {
  ## W: Date, Ticker, w  (Σw=1 per Date)
  setkey(W, Date, Ticker)
  W2 <- merge(W, RET, by = c("Date","Ticker"), all.x = TRUE)
  W2[is.na(Ret_1m), Ret_1m := 0]   # 결측 수익 = 0 (alpha 단계 동일 규약 여부는 아래 recon 으로 판정)
  ds <- sort(unique(W2$Date))
  prev <- data.table(Ticker = character(), wd = numeric())
  out <- vector("list", length(ds))
  for (i in seq_along(ds)) {
    d <- ds[i]
    cur <- W2[Date == d, .(Ticker, w, Ret_1m)]
    m <- merge(cur[, .(Ticker, w)], prev, by = "Ticker", all = TRUE)
    m[is.na(w), w := 0]; m[is.na(wd), wd := 0]
    to_ow <- sum(abs(m$w - m$wd))                     # one-way turnover
    gross <- sum(cur$w * cur$Ret_1m)
    cost  <- (cost_bps/1e4) * to_ow
    out[[i]] <- data.table(Date = d, gross = gross, cost = cost, net = gross - cost,
                           to_ow = to_ow, n = nrow(cur), hhi = sum(cur$w^2), wmax = max(cur$w))
    prev <- cur[, .(Ticker, wd = w*(1+Ret_1m)/sum(w*(1+Ret_1m)))]
  }
  rbindlist(out)
}

R_ew <- eval_sched(ew)
cmp <- merge(R_ew[, .(Date, net_mine = net, to = to_ow)], PRD[, .(Date = signal_date, ret_net, benchmark_ret, active_net)], by = "Date")
cmp[, d := net_mine - ret_net]
cat("\n=== RECONCILIATION vs period_returns_production.csv ===\n")
cat("n matched:", nrow(cmp), "\n")
cat("max |diff|:", max(abs(cmp$d)), "  mean |diff|:", mean(abs(cmp$d)), "\n")
cat("cor:", cor(cmp$net_mine, cmp$ret_net), "\n")
print(head(cmp[order(-abs(d))], 8))
cat("\nturnover annual (mean one-way x12):", mean(R_ew$to_ow)*12, "  (alpha reported 8.8198)\n")
cat("turnover ex-first:", mean(R_ew$to_ow[-1])*12, "\n")
saveRDS(list(A=A, RET=RET, BM=BM, PRD=PRD, sel=sel, ew=ew, R_ew=R_ew), "stage_artifacts/WT_R20260829_005/opt_r5.rds")
