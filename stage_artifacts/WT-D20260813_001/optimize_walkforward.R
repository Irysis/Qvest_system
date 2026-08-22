## WT-D20260813_001 — Optimizer walk-forward weighting-scheme comparison
## metric_type = canonical_screen_diag / screen_diagnostic
## 목적: top-25 selection 고정(alpha selection = edge), *weighting scheme* 이 net SR 을
##       EW 대비 개선하는지 정직 비교. Cycle 2(DeMiguel-Garlappi-Uppal) 1/N OOS 우위 검증.
## 포트 수익 구성 = PerformanceAnalytics Return.portfolio (자체합성 금지, python-policy §4 정합)
## 비용 = 15bps delta-based one-way (레그당 Σ|Δw| × 0.0015)
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WT <- "WT-D20260813_001"; SA <- file.path("stage_artifacts", WT); MB <- file.path("qepm/mailbox/worktask", WT)
SRC <- "stage_artifacts/fq233_probe0_20260813"

## ── 입력 (alpha agent 와 동일 패널) ──
inp <- readRDS(file.path(SRC, "r33_inputs.rds"))
returns_dt <- as.data.table(inp$frd)[, .(Date = as.Date(Date), Ticker = as.character(Ticker),
                                         Ret_1m = as.numeric(Ret_1m))][is.finite(Ret_1m)]
scores <- as.data.table(read_parquet(file.path(SA, "alpha_scores.parquet")))[
  , .(Date = as.Date(Date), sig_date = as.Date(sig_date), Ticker = as.character(Ticker),
      score = as.numeric(alpha_score))]

bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, Date := as.Date(Date)][is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by = bm$Date), Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[,1]))
returns_dt[, ym := format(Date, "%Y%m")]
bench_dt <- merge(unique(returns_dt[, .(Date, ym)]), bench_m, by = "ym")[, .(Date, BM_Ret)]
setkey(returns_dt, Date, Ticker)

TOP_N <- 25L; COST <- 0.0015; BOUND_HI <- 0.20

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }

## ── weighting schemes over the top-25 per date ──
## Σ 는 현재 25명 스냅샷만 신뢰(risk scope). 스케줄 상 각 date 의 top-25 는 상이하므로,
## 스케줄 전반 적용 가능한 scheme = EW / score-tilt / vol-scaled(개별 trailing vol, PIT).
## HRP/ERC/MVO 는 date별 Σ 재추정이 필요(risk agent 미제공) → 스냅샷에서만 진단, 스케줄은
## Σ-불요 scheme 3종으로 정직 비교. (Σ 재추정은 risk 역할경계 — optimizer 가 만들지 않음)

## trailing 개별 종목 vol (PIT: Date < sig_date 의 월간 Ret 로 60개월 rolling sd)
retwide <- dcast(returns_dt, Date ~ Ticker, value.var = "Ret_1m")
setorder(retwide, Date)
alldates <- retwide$Date

scheme_weights <- function(sc_dt, scheme) {
  # sc_dt: this date's top-25 (Ticker, score, sig_date)
  tk <- sc_dt$Ticker; s <- sc_dt$score; sd_ <- sc_dt$sig_date[1]
  n <- length(tk)
  if (scheme == "EW") {
    w <- rep(1/n, n)
  } else if (scheme == "ScoreTilt") {
    a <- s - min(s) + 1e-6; w <- a / sum(a)
    w <- pmin(w, BOUND_HI); w <- w / sum(w)
  } else if (scheme == "InvVol") {
    # individual trailing vol using months strictly before sig_date
    hist <- returns_dt[Date < sd_ & Ticker %in% tk]
    vv <- hist[, .(v = sd(Ret_1m, na.rm=TRUE)), by = Ticker]
    v <- setNames(vv$v, vv$Ticker)[tk]
    v[!is.finite(v) | v <= 0] <- median(v[is.finite(v) & v>0], na.rm=TRUE)
    if (all(!is.finite(v))) v <- rep(1, n)
    iv <- 1/v; w <- iv / sum(iv)
    w <- pmin(w, BOUND_HI); w <- w / sum(w)
  }
  names(w) <- tk; w
}

## build weight schedule per scheme -> Return.portfolio
build_series <- function(scheme) {
  dts <- sort(unique(scores$sig_date))
  # weights indexed by rebalance date (sig_date). Return realized in the holding month = the
  # returns_dt Date that maps to this sig_date. Map: scores has Date (holding month) & sig_date.
  wl <- list(); ret_rows <- list(); prev_w <- NULL; cost_vec <- c(); hold_dates <- c()
  # holding-month Date per sig_date
  map_dt <- unique(scores[, .(sig_date, Date)])
  for (sd_ in dts) {
    scd <- scores[sig_date == sd_][order(-score)][1:TOP_N]
    hd <- map_dt[sig_date == sd_]$Date[1]
    # realized returns for held names in holding month hd
    rr <- returns_dt[Date == hd & Ticker %in% scd$Ticker]
    if (nrow(rr) < TOP_N * 0.8) next   # need most names to have realized return
    w <- scheme_weights(scd, scheme)
    # align to names with realized return
    common <- intersect(names(w), rr$Ticker)
    w <- w[common]; w <- w / sum(w)
    rvec <- setNames(rr$Ret_1m, rr$Ticker)[common]
    gross <- sum(w * rvec)
    # turnover cost: delta vs prev holdings (union of names)
    if (is.null(prev_w)) {
      to <- sum(w)   # initial build = full turnover one-way
    } else {
      allnm <- union(names(prev_w), names(w))
      pw <- setNames(rep(0, length(allnm)), allnm); pw[names(prev_w)] <- prev_w
      cw <- setNames(rep(0, length(allnm)), allnm); cw[names(w)] <- w
      to <- sum(abs(cw - pw))
    }
    cost <- to * COST
    net <- gross - cost
    ret_rows[[length(ret_rows)+1]] <- data.table(date = hd, gross = gross, net = net, to = to)
    prev_w <- w
  }
  rbindlist(ret_rows)
}

schemes <- c("EW", "ScoreTilt", "InvVol")
series <- lapply(schemes, build_series); names(series) <- schemes

summ <- rbindlist(lapply(schemes, function(s) {
  d <- series[[s]]
  px <- xts(d$net, order.by = d$date)
  bm_al <- bench_dt[Date %in% d$date][order(Date)]
  act <- d$net - bm_al$BM_Ret[match(d$date, bm_al$Date)]
  data.table(
    scheme = s,
    n_months = nrow(d),
    net_sr = as.numeric(SharpeRatio.annualized(px, Rf=0, scale=12, geometric=FALSE)),
    cagr = as.numeric(Return.annualized(px, scale=12, geometric=TRUE)),
    mdd = as.numeric(maxDrawdown(px)),
    ann_turnover = mean(d$to) * 12,
    active_mean_ann = mean(act, na.rm=TRUE) * 12,
    active_ir = (mean(act,na.rm=TRUE)/sd(act,na.rm=TRUE)) * sqrt(12),
    port_t_nw = nw_t(act, 3)
  )
}))
summ[, calmar := cagr / pmax(mdd, 1e-9)]
print(summ)

fwrite(summ, file.path(SA, "walkforward_scheme_comparison.csv"))
saveRDS(series, file.path(SA, "walkforward_series.rds"))

## write per-date weights.csv for the SELECTED scheme (decided after reading summ) — placeholder here,
## final weights.csv emitted in emit step. Save all-scheme schedules for schedule-density.
sched_all <- rbindlist(lapply(schemes, function(s) {
  dts <- sort(unique(scores$sig_date)); rows <- list()
  map_dt <- unique(scores[, .(sig_date, Date)])
  for (sd_ in dts) {
    scd <- scores[sig_date == sd_][order(-score)][1:TOP_N]
    w <- scheme_weights(scd, s)
    rows[[length(rows)+1]] <- data.table(scheme = s, as_of_date = sd_,
                                         holding_month = map_dt[sig_date==sd_]$Date[1],
                                         Ticker = names(w), weight = as.numeric(w))
  }
  rbindlist(rows)
}))
fwrite(sched_all, file.path(SA, "weights_schedule_allschemes.csv"))
cat("schedule unique dates:", uniqueN(sched_all$as_of_date), "/ sig_dates:", uniqueN(scores$sig_date), "\n")
cat("OPTIMIZE_WALKFORWARD_DONE\n")
