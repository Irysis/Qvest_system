## P1 — 팩터×월 선별-통계 원재료 구축 (스트리밍 1패스)
##
## 산출:
##   (1) factor_month_stats.rds : anchor 월별·팩터별 ic_sp / ic_pe / ic_pe_w1 / spr_dec / n
##   (2) 월별 z 패널 캐시 (scratch, parquet) — P2 합성 시 재로드 없이 소비
##
## ★앵커 규약 (WT-D20260821_002 / 2026-08-13 실사고 승계): 팩터 sig_date T = T월 말 관측.
##   build_monthly_forward_returns 앵커 = "sig_date 이하 최종 거래일" 이므로 팩터를 T 로
##   넘기면 forward 가 T월 수익이 되어 팩터가 채점 대상 월을 본다. 수정 = Date 를 T+1개월 스탬프.
##   지문 = M04_Mom_1 평균 Spearman IC (+0.0170 정상 / -0.9423 결함) — p0_probe.R 에서 검증.
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260822_002/p1_build_stats.R")'

suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

OUT <- "stage_artifacts/WT-D20260822_002"
ZDIR <- file.path(OUT, "zcache")
dir.create(ZDIR, showWarnings = FALSE, recursive = TRUE)

p0 <- readRDS(file.path(OUT, "p0_returns.rds"))
sig_dates <- p0$sig_dates
frd <- as.data.table(p0$frd)
setkey(frd, Date, Ticker)

nextm <- function(d) as.Date(cut(as.Date(d) + 40L, "month"))

## 상하위 10% 평균 스프레드 — 분위 경계는 그 달 횡단면 내에서만(PIT 무관, 동시점).
dec_spread <- function(z, r) {
  n <- length(z)
  if (n < 30L) return(NA_real_)
  q <- stats::quantile(z, probs = c(0.10, 0.90), na.rm = TRUE, type = 7)
  lo <- r[z <= q[1]]; hi <- r[z >= q[2]]
  if (length(lo) < 3L || length(hi) < 3L) return(NA_real_)
  mean(hi) - mean(lo)
}
winsor <- function(x, p = 0.01) {
  q <- stats::quantile(x, probs = c(p, 1 - p), na.rm = TRUE, type = 7)
  pmin(pmax(x, q[1]), q[2])
}

res <- vector("list", length(sig_dates))
cov_log <- vector("list", length(sig_dates))
t_start <- Sys.time()
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  a <- nextm(d)
  x <- tryCatch(load_month_factors(d), error = function(e) NULL)
  if (is.null(x) || !nrow(x)) next
  x <- as.data.table(x)[is.finite(Z_Score_Aligned)]
  if (!nrow(x)) next
  setnames(x, "Z_Score_Aligned", "z")
  x[, Ticker := as.character(Ticker)]

  ## z 패널 캐시 (P2 소비용) — anchor 스탬프로 저장
  write_parquet(x[, .(Ticker, Factor_Name = as.character(Factor_Name), z = as.numeric(z))],
                file.path(ZDIR, sprintf("z_%s.parquet", format(a, "%Y%m"))))

  rr <- frd[.(a), .(Ticker, Ret_1m), on = "Date", nomatch = 0L]
  if (!nrow(rr)) { cov_log[[i]] <- data.table(anchor = a, n_ret = 0L); next }
  m <- merge(x[, .(Ticker, Factor_Name, z)], rr, by = "Ticker")
  if (!nrow(m)) next
  m[, r_w1 := winsor(Ret_1m, 0.01), by = Factor_Name]

  st <- m[, {
    n <- .N
    if (n < 30L) .(ic_sp = NA_real_, ic_pe = NA_real_, ic_pe_w1 = NA_real_, spr_dec = NA_real_, n = n)
    else .(
      ic_sp    = suppressWarnings(stats::cor(z, Ret_1m, method = "spearman")),
      ic_pe    = suppressWarnings(stats::cor(z, Ret_1m, method = "pearson")),
      ic_pe_w1 = suppressWarnings(stats::cor(z, r_w1,   method = "pearson")),
      spr_dec  = dec_spread(z, Ret_1m),
      n = n)
  }, by = Factor_Name]
  st[, anchor := a]
  res[[i]] <- st
  cov_log[[i]] <- data.table(anchor = a, n_ret = nrow(rr), n_fac = uniqueN(x$Factor_Name),
                             n_tick = uniqueN(x$Ticker), n_rows = nrow(x))
  if (i %% 20L == 0L)
    cat(sprintf("  [%3d/%3d] %s  fac=%d tick=%d  (%.1f분 경과)\n", i, length(sig_dates),
                format(a), uniqueN(x$Factor_Name), uniqueN(x$Ticker),
                as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
  flush.console()
}
S <- rbindlist(res, fill = TRUE)
CL <- rbindlist(cov_log, fill = TRUE)
saveRDS(list(stats = S, cov = CL), file.path(OUT, "factor_month_stats.rds"))
cat(sprintf("\n[P1 완료] stats %d행 · %d팩터 · %d개월 · %.1f분\n",
            nrow(S), uniqueN(S$Factor_Name), uniqueN(S$anchor),
            as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
print(CL[, .(n_fac_med = as.integer(median(n_fac)), n_tick_med = as.integer(median(n_tick)),
             n_ret_med = as.integer(median(n_ret)))])
