# =============================================================================
# run_canonical_pool.R — WT-D20260803_005 (FQ-131) Step B: 풀 전체 canonical 실측
#   각 factor의 전기간 canonical net-active 시계열을 확보한다.
#   창별 PORT_t는 Step C에서 이 시계열에 동일 추정량(.nw_t_mean lag=3)을 적용해 산출 —
#   그 동치성은 아래 WINDOW PARITY 검사로 실증한다(창-직접 canonical 대비).
#
#   parity 3종:
#     P1 TOPK   : top-80 저장 패널 vs 전체 z 패널 canonical (선택 절단 무해 실증)
#     P2 FASTPATH: 자체 재현 선택 vs canonical period_returns (< 1e-8)
#     P3 WINDOW : 창-직접 canonical PORT_t vs 전기간 시계열 슬라이스 PORT_t
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/run_canonical_pool.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005B] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

META  <- readRDS(file.path(OUT, "pool_meta.rds"))
PANEL <- as.data.table(read_parquet(file.path(OUT, "pool_panel.parquet")))
PANEL[, Date := as.Date(Date)]
setkey(PANEL, Factor_Name, Date, Ticker)
POOL <- sort(META$pool)
say("풀 %d factor | 패널 행 %d | 월 %d", length(POOL), nrow(PANEL), uniqueN(PANEL$Date))

# ── 하네스 (WT-004 동일) ────────────────────────────────────────────────────
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(FALSE)
sig_all <- META$sig_all
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
# size 패널 (cap-tier 조건축 + dual-basis diag)
size_dt <- RAWME[Date %in% sig_all & (K200 == TRUE | KQ150 == TRUE) & !is.na(Size),
                 .(Date, Ticker, Size)]
size_dt[, size_pct := frank(Size) / .N, by = Date]
say("returns %d행 / bench %d월 / liq %d행 / size %d행",
    nrow(returns_dt), nrow(bench_dt), nrow(liq_dt), nrow(size_dt))

canon <- function(sc, tag, dual = FALSE) {
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n = 25L,
    cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
    run_id = "WT-D20260803_005", strategy_id = paste0("WT_D20260803_005_", tag),
    diag_dual_basis = dual, size_dt = if (dual) size_dt else NULL)
}
sc_of <- function(f) PANEL[.(f), .(Date, Ticker, score), nomatch = 0L]

# ── P1 TOPK parity: top-80 저장 vs 전체 z 패널 (3 factor 표본) ───────────────
say("P1 TOPK parity 시작 (전체 z 패널 재로드 3 factor)")
p1_f <- c("V01_BM", "M01_Mom_12_1", "D01_IdioVol")
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]; setkey(UNIV, Date, Ticker)
sink(file.path(OUT, "p1_connector.log"))
full_list <- lapply(sig_all, function(d) {
  tk <- UNIV[.(d), Ticker, nomatch = 0L]
  fd <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = p1_f),
                 error = function(e) NULL)
  if (is.null(fd) || !nrow(fd)) return(NULL)
  fd[Ticker %in% tk & is.finite(Z_Score_Aligned),
     .(Date = d, Ticker, Factor_Name, score = Z_Score_Aligned)]
})
sink()
FULLP <- rbindlist(Filter(Negate(is.null), full_list), use.names = TRUE); rm(full_list)
p1 <- rbindlist(lapply(p1_f, function(f) {
  a <- canon(FULLP[Factor_Name == f, .(Date, Ticker, score)], paste0("P1FULL_", f))
  b <- canon(sc_of(f), paste0("P1TOPK_", f))
  m <- merge(as.data.table(a$period_returns)[, .(date, x = ret_net)],
             as.data.table(b$period_returns)[, .(date, y = ret_net)], by = "date")
  data.table(Factor = f, n = nrow(m), max_abs_diff = max(abs(m$x - m$y)),
             port_t_full = a$portfolio_alpha_t_nw_lag3, port_t_topk = b$portfolio_alpha_t_nw_lag3)
}))
print(p1)
stopifnot(all(p1$max_abs_diff < 1e-12))
say("P1 PASS — top-80 절단이 top-25 선택을 바꾸지 않음 (max diff %.1e)", max(p1$max_abs_diff))
rm(FULLP); gc(FALSE)

# ── 본 루프: 풀 전체 canonical ──────────────────────────────────────────────
t0 <- Sys.time()
RES <- vector("list", length(POOL)); names(RES) <- POOL
SUM <- vector("list", length(POOL))
for (i in seq_along(POOL)) {
  f <- POOL[i]
  r <- tryCatch(canon(sc_of(f), f), error = function(e) NULL)
  if (is.null(r) || is.null(r$period_returns)) next
  pr <- as.data.table(r$period_returns)
  RES[[f]] <- pr[, .(date, ret_net, benchmark_ret, active = ret_net - benchmark_ret)]
  SUM[[i]] <- data.table(Factor_Name = f, n_months = r$n_months,
    port_t_full = r$portfolio_alpha_t_nw_lag3, net_sr = r$net_sr,
    ir = r$information_ratio, alpha_ann = r$alpha_annualized,
    turnover_annual = r$turnover_annual, sel_cov = r$selected_ret_coverage,
    mean_active = r$mean_active_net)
  if (i %% 25L == 0L) say("%d/%d (%.0fs)", i, length(POOL),
      as.numeric(difftime(Sys.time(), t0, units = "secs")))
}
SUMM <- rbindlist(Filter(Negate(is.null), SUM), use.names = TRUE)
RES <- RES[!vapply(RES, is.null, logical(1))]
say("canonical 완료 %d factor / %.0fs", nrow(SUMM),
    as.numeric(difftime(Sys.time(), t0, units = "secs")))

# ── cap-tier / 보유 프로파일 (fast path 선택 재현 — P2로 parity 확인) ────────
select_top <- function(sc, top_n = 25L) {
  S <- as.data.table(sc)[!is.na(score)]
  S <- merge(S, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
  S <- S[is.na(adv) | adv >= 2e8][, adv := NULL]
  setorder(S, Date, -score)
  S[, { n <- min(top_n, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
}
port_from_w <- function(W, cost_bps = 15) {
  WR <- merge(W, returns_dt, by = c("Date","Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, ret_net := port_gross - traded * cost_bps / 1e4]
  setorder(port, Date); port
}
setkey(size_dt, Date, Ticker)
CAP <- rbindlist(lapply(POOL, function(f) {
  W <- select_top(sc_of(f))
  m <- merge(W, size_dt, by = c("Date","Ticker"), all.x = TRUE)
  data.table(Factor_Name = f, hold_size_pct = median(m$size_pct, na.rm = TRUE))
}))

# ── P2 FASTPATH parity ──────────────────────────────────────────────────────
p2_f <- c("V01_BM", "Q01_GPA", "L01_Amihud")
p2 <- rbindlist(lapply(p2_f, function(f) {
  fp <- port_from_w(select_top(sc_of(f)))
  cn <- RES[[f]]
  m <- merge(fp[, .(date = Date, mine = ret_net)], cn[, .(date, canon = ret_net)], by = "date")
  data.table(Factor = f, n = nrow(m), max_abs_diff = max(abs(m$mine - m$canon)))
}))
print(p2); stopifnot(all(p2$max_abs_diff < 1e-8))
say("P2 PASS — fast path == canonical (max %.1e)", max(p2$max_abs_diff))

# ── P3 WINDOW parity: 창-직접 canonical vs 전기간 슬라이스 ──────────────────
#   창 직접 실행은 창 첫달 turnover가 100%(직전 보유 없음)로 잡히는 경계효과가 있다.
#   그 차이를 정량화해 Step C 창 t 산출 방식(슬라이스)의 편향을 정직 보고한다.
nw_t <- function(x, lag = 3L) { if (!exists(".nw_t_mean", mode="function")) return(NA_real_); .nw_t_mean(x, lag = lag) }
p3_f <- c("V01_BM", "M01_Mom_12_1", "D01_IdioVol", "Q01_GPA", "L01_Amihud")
dts_all <- sort(unique(RES[[p3_f[1]]]$date))
w_end <- length(dts_all); W60 <- 60L
w_bounds <- list()
while (w_end - W60 + 1L >= 1L) {
  w_bounds[[length(w_bounds)+1L]] <- c(w_end - W60 + 1L, w_end); w_end <- w_end - W60
}
w_bounds <- rev(w_bounds)
p3 <- rbindlist(lapply(p3_f, function(f) {
  sc <- sc_of(f)
  rbindlist(lapply(seq_along(w_bounds), function(k) {
    ix <- w_bounds[[k]]; d0 <- dts_all[ix[1]]; d1 <- dts_all[ix[2]]
    direct <- canon(sc[Date >= d0 & Date <= d1], sprintf("P3_%s_w%d", f, k))
    slice_t <- nw_t(RES[[f]][date >= d0 & date <= d1, active])
    data.table(Factor = f, window = k, from = d0, to = d1,
               t_direct = direct$portfolio_alpha_t_nw_lag3, t_slice = slice_t)
  }))
}))
p3[, dt := t_slice - t_direct]
p3[, sign_same := sign(t_slice) == sign(t_direct)]
print(p3)
say("P3: |Δt| 평균 %.4f / 최대 %.4f | 부호 일치 %d/%d",
    mean(abs(p3$dt)), max(abs(p3$dt)), sum(p3$sign_same), nrow(p3))

saveRDS(list(res = RES, summary = SUMM, cap = CAP,
             parity = list(p1_topk = p1, p2_fastpath = p2, p3_window = p3),
             sig_all = sig_all, generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "canonical_pool.rds"))
say("저장 — canonical_pool.rds")
