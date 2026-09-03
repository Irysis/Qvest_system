# OP1 — 백테스트 엔진 + M1 재현 검증 (alpha 생산 사양 대조)
suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")

A  <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
pn <- readRDS(file.path(OUT,"panel.rds"))
RT <- as.data.table(pn$fwd$returns_dt); LQ <- as.data.table(pn$fwd$liq_dt); BM <- as.data.table(pn$fwd$bench_dt)
PR <- fread(file.path(OUT,"period_returns_production.csv")); PR[,signal_date:=as.Date(signal_date)]

A <- merge(A, RT, by=c("Date","Ticker"), all.x=TRUE)
A <- merge(A, LQ, by=c("Date","Ticker"), all.x=TRUE)
setorder(A, Date, -fh_lag1d, Ticker)
DTS <- sort(unique(A$Date))                 # 260 (마지막 = as-of 2026-08-28)
DTS_BT <- sort(unique(PR$signal_date))      # 259 실현
COST_BPS <- 0.0015

# ---- 범용 walk-forward 러너 ----
# wfun(dt_slice, prev_names, prev_w_end, t_idx) -> named numeric vector (Σ=1, ≥0, ≤25)
run_wf <- function(wfun, dates=DTS_BT, label="M"){
  prev <- setNames(numeric(0), character(0))
  rows <- list(); wl <- list()
  for(i in seq_along(dates)){
    dd <- dates[i]; x <- A[Date==dd]
    w <- wfun(x, prev, i)
    w <- w[w > 1e-12]; w <- w/sum(w)
    stopifnot(length(w) <= 25, all(w >= 0))
    tick <- names(w)
    r <- x$Ret_1m[match(tick, x$Ticker)]
    if(any(!is.finite(r))) { r[!is.finite(r)] <- 0 }
    pg <- sum(w*r)
    # turnover vs 직전월 말 drift 후 비중
    allt <- union(names(prev), tick)
    a <- setNames(numeric(length(allt)), allt); a[names(prev)] <- prev
    b <- setNames(numeric(length(allt)), allt); b[tick] <- w
    to <- sum(abs(b-a))
    cost <- COST_BPS*to
    bmr <- BM$BM_Ret[match(dd, BM$Date)]
    rows[[i]] <- data.table(signal_date=dd, n=length(w), ret_gross=pg, traded=to, cost=cost,
                            ret_net=pg-cost, bm=bmr, hhi=sum(w^2), maxw=max(w))
    wl[[i]] <- data.table(as_of_date=dd, Ticker=tick, weight=as.numeric(w))
    prev <- setNames(w*(1+r)/(1+pg), tick)
  }
  list(perf=rbindlist(rows), weights=rbindlist(wl), method=label)
}

# ---- M1: EW top-25 (alpha 생산 사양) ----
f_ew <- function(x, prev, i){ tk <- x[order(-fh_lag1d, Ticker)]$Ticker[1:25]; setNames(rep(1/25,25), tk) }
m1 <- run_wf(f_ew, label="EW25_base")

cmp <- merge(m1$perf[,.(signal_date, my_g=ret_gross, my_to=traded, my_n=ret_net)],
             PR[,.(signal_date, pr_g=ret_gross, pr_to=traded_notional, pr_n=ret_net)], by="signal_date")
cat("=== M1 재현 대조 (vs period_returns_production.csv) ===\n")
cat("months:", nrow(cmp), "\n")
cat("max |Δ ret_gross| :", max(abs(cmp$my_g-cmp$pr_g)), "\n")
cat("max |Δ traded|    :", max(abs(cmp$my_to-cmp$pr_to)), "\n")
cat("max |Δ ret_net|   :", max(abs(cmp$my_n-cmp$pr_n)), "\n")
cat("mean traded (two-way, monthly):", mean(cmp$my_to), " -> annual:", mean(cmp$my_to)*12, "\n")
saveRDS(list(A=A, RT=RT, LQ=LQ, BM=BM, PR=PR, DTS=DTS, DTS_BT=DTS_BT, m1=m1), file.path(OUT,"op1_objects.rds"))
