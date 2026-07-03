## ============================================================================
## PG2 강화 P1 → book-marginal (forge-authoritative, 실측-only)
## W2 earnings composite(S3_consensus + 보유밴드)를 noLayer4 incumbent book 대비 검증.
##
## 설계(도훈 지시 2026-07-02):
##   1) earnings sleeve = S3_consensus top-25 EW + 보유밴드(Blitz) 선택수익 (P1 band 알고리즘 재현)
##      × 동일 book 오버레이(beta_R05 × m4, 클린 타이밍) − |Δbeta_R05|×15bps.
##      build_bt_result 계약 10-component, annualization=12 (252 버그 회피).
##   2) 직교성: earnings active(−KOSPI200) vs incumbent active 상관 (active-basis, gross 아님).
##   3) book-marginal ΔIR: 50/50 블렌드 + IR-max 블렌드 → new_book_ir − 1.416.
##   4) 2021+ 생존: 블렌드 active 2021+ PORT_t(NW lag3) 양수 유의?
##   5) DSR/holdout 진단: n_trials 기록.
##
## 규율: proxy 손계산 금지. build_bt_result / build_benchmark_compare 계약 경유.
##       PerformanceAnalytics 표준(포트수익 Return.portfolio). PIT: earnings 신호@ym말·fwd 1M.
##       benchmark = incumbent와 동일 pinned KOSPI200(IKS200) — ΔIR 비교 타당성.
##       overlay(beta_R05/m4)는 book-level 스칼라 = incumbent와 동일 series(5-panel) 매칭.
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/pg2_w2_bookmarginal")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015   # 15bps one-way
TOP_N <- 25L; BAND_KEEP <- 0.45

## ─── 1. earnings panel 로드 ──────────────────────────────────────────────
pan <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/pg2_w2_earnings3m/panel_signals.parquet")))
pan[, Date := as.Date(Date)]
pan[, ym := as.character(ym)]
ret_dt <- pan[, .(Date, Ticker, Ret_1m = fwd_ret_1m)]
liq_dt <- pan[, .(Date, Ticker, adv = adv_lag1)]

## ─── 2. S3_consensus + 보유밴드 선택수익 (P1 band 알고리즘 정확 재현) ──────
## earnings ret_net dated EOM(ym=t)는 fwd_ret_1m 사용 → 실현월 = ym=t+1 (panel 정의).
band_select_return <- function(sigcol) {
  s <- pan[!is.na(get(sigcol)), .(Date, Ticker, score = get(sigcol))]
  sl <- merge(s, liq_dt, by = c("Date", "Ticker"), all.x = TRUE)
  sl <- sl[is.na(adv) | adv >= 2e8]
  dts <- sort(unique(sl$Date))
  held <- character(0); rows <- vector("list", length(dts))
  prev_w <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    d <- dts[i]
    cur <- sl[Date == d][order(-score)]
    if (nrow(cur) < TOP_N) next
    cur[, toprank := frank(-score, ties.method = "first")]
    cur[, topfrac := toprank / .N]
    top25 <- cur[toprank <= TOP_N, Ticker]
    keep_pool <- cur[topfrac <= BAND_KEEP, Ticker]
    retain <- intersect(held, keep_pool)
    if (length(retain) > TOP_N) retain <- cur[Ticker %in% retain][order(-score)][1:TOP_N, Ticker]
    slots <- TOP_N - length(retain); fill <- character(0)
    if (slots > 0) {
      cand <- setdiff(top25, retain)
      if (length(cand) > 0) fill <- cur[Ticker %in% cand][order(-score)][seq_len(min(slots, length(cand))), Ticker]
    }
    held <- unique(c(retain, fill))
    w <- data.table(Ticker = held, w = 1 / length(held))
    rr <- merge(w, ret_dt[Date == d, .(Ticker, Ret_1m)], by = "Ticker", all.x = TRUE)
    rr[is.na(Ret_1m), Ret_1m := 0]
    gross <- sum(rr$w * rr$Ret_1m)
    m <- merge(w[, .(Ticker, w_cur = w)], prev_w[, .(Ticker, w_prev = w)], by = "Ticker", all = TRUE)
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded <- sum(abs(m$w_cur - m$w_prev))
    ym_sig <- format(d, "%Y-%m")                     # 신호월 t
    rows[[i]] <- data.table(ym_sig = ym_sig, ret_sel = gross - traded * COST / 1e4, traded = traded)
    prev_w <- w
  }
  rbindlist(rows)
}

earn <- band_select_return("S3_consensus")
## 실현월 realized_ym = 신호월 + 1개월
earn[, realized_ym := format(as.Date(paste0(ym_sig, "-01")) + 32, "%Y-%m")]
earn[, realized_ym := format(as.Date(paste0(realized_ym, "-01")), "%Y-%m")]
cat(sprintf("[earn] S3 band 선택수익 months=%d (%s ~ %s realized)\n",
            nrow(earn), min(earn$realized_ym), max(earn$realized_ym)))

## ─── 3. book overlay (5-panel: beta_R05, m4) 매칭 by realized_ym ─────────────
p5 <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p5[, anchor_date := as.Date(anchor_date)]; setorder(p5, realized_ym)
p5[, realized_ym := as.character(realized_ym)]

mg <- merge(earn[, .(realized_ym, ret_sel, traded)],
            p5[, .(realized_ym, anchor_date, ret_orig, beta_R05, m4, regime)],
            by = "realized_ym", all = FALSE)
setorder(mg, realized_ym)
## clean overlay: earnings 선택수익에 동일 book 스칼라 적용
mg[, dR05 := abs(beta_R05 - shift(beta_R05, 1, fill = 1.0))]
mg[, ret_earn_overlay := beta_R05 * m4 * ret_sel - dR05 * COST]   # overlay β-회전 비용 추가
cat(sprintf("[overlay] earnings×(beta_R05×m4) matched months=%d (%s ~ %s)\n",
            nrow(mg), min(mg$realized_ym), max(mg$realized_ym)))

## ─── 4. benchmark: incumbent와 동일 pinned KOSPI200, anchor 윈도우 누적 ──────
bm <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
bm_x <- xts(bm$BM_Ret, order.by = bm$Date)
a <- mg$anchor_date; bmw <- rep(NA_real_, nrow(mg))
for (i in 2:nrow(mg)) {
  seg <- bm_x[index(bm_x) > a[i - 1] & index(bm_x) <= a[i]]
  if (nrow(seg) > 0) bmw[i] <- as.numeric(Return.cumulative(seg))
}
bmw[1] <- 0
mg[, benchmark_ret := bmw]

## ─── 5. earnings sleeve bt_result (계약, annualization=12) ─────────────────
RID <- "PG2_W2_earn_S3band_overlay"; SID <- RID
pr <- data.table(run_id = RID, strategy_id = SID, date = mg$anchor_date, frequency = "monthly",
                 ret_gross = mg$ret_earn_overlay, ret_net = mg$ret_earn_overlay, risk_free_ret = 0,
                 excess_ret_net = mg$ret_earn_overlay, turnover = mg$traded, cost_ret = 0,
                 cash_weight = NA_real_, leverage = NA_real_, n_holdings = TOP_N)
br <- data.table(benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200", date = mg$anchor_date,
                 benchmark_ret = mg$benchmark_ret, benchmark_nav = cumprod(1 + ifelse(is.na(mg$benchmark_ret), 0, mg$benchmark_ret)),
                 risk_free_ret = 0, benchmark_excess_ret = mg$benchmark_ret, frequency = "monthly")
nav_v <- cumprod(1 + pr$ret_net)
nav_tbl <- data.table(run_id = RID, strategy_id = SID, date = pr$date, frequency = "monthly",
                      nav_gross = nav_v, nav_net = nav_v, drawdown = NA_real_)
hold_tbl <- data.table(matrix(nrow = 0, ncol = length(HOLDINGS_COLS), dimnames = list(NULL, HOLDINGS_COLS)))
metrics <- build_metrics(nav_tbl, pr, hold_tbl, RID, SID, frequency = "monthly", annualization_factor = 12)
bcmp    <- build_benchmark_compare(pr, br, RID, SID, annualization_factor = 12)

gv  <- function(dt, mn) { v <- dt[metric_name == mn]$metric_value; if (length(v)) v[1] else NA_real_ }
gvb <- function(mn, col = "strategy_value") { v <- bcmp[metric_name == mn][[col]]; if (length(v)) v[1] else NA_real_ }
x_earn <- xts(pr$ret_net, order.by = pr$date)
SR_geo  <- as.numeric(table.AnnualizedReturns(x_earn, scale = 12)[3, 1])
CAGR    <- gv(metrics, "CAGR"); MDD <- gv(metrics, "MDD"); CALMAR <- gv(metrics, "Calmar")
PORT_t  <- gvb("Portfolio_Alpha_t_NW_lag3")
IR_earn <- gvb("Information_Ratio", "active_value")
ALPHA   <- gvb("Alpha_Annualized"); BETA <- gvb("Beta_to_Benchmark")

cat("\n===== EARNINGS SLEEVE (S3 band × m4×β_R05 overlay) forge 지표 =====\n")
cat(sprintf("  n_months = %d (%s ~ %s)\n", nrow(pr), min(pr$date), max(pr$date)))
cat(sprintf("  SR(geo table)=%.4f  CAGR=%.4f  MDD=%.4f  Calmar=%.4f\n", SR_geo, CAGR, MDD, CALMAR))
cat(sprintf("  PORT_t(NW lag3)=%.4f  IR(active)=%.4f  alpha_ann=%.4f  beta=%.4f\n", PORT_t, IR_earn, ALPHA, BETA))

## ─── 6. 직교성 (active-basis) vs incumbent ────────────────────────────────
inc <- readRDS(file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds"))
inc_pr <- as.data.frame(inc$period_returns); inc_br <- as.data.frame(inc$benchmark_returns)
inc_dt <- data.table(date = as.Date(inc_pr$date), inc_ret = inc_pr$ret_net, inc_bench = inc_br$benchmark_ret)
inc_dt[, inc_active := inc_ret - inc_bench]

earn_dt <- data.table(date = pr$date, earn_ret = pr$ret_net, earn_bench = br$benchmark_ret)
earn_dt[, earn_active := earn_ret - earn_bench]

J <- merge(inc_dt, earn_dt, by = "date", all = FALSE)
setorder(J, date)
cat(sprintf("\n[join] incumbent∩earnings overlap months = %d (%s ~ %s)\n",
            nrow(J), min(J$date), max(J$date)))
## benchmark 일치성 sanity (동일 pinned KOSPI200)
bench_diff <- max(abs(J$inc_bench - J$earn_bench), na.rm = TRUE)
cat(sprintf("[sanity] max |inc_bench - earn_bench| = %.2e (동일 pinned KOSPI200 이어야 ~0)\n", bench_diff))

active_cor_gross <- cor(J$earn_ret, J$inc_ret)               # gross(총수익) 상관
active_cor       <- cor(J$earn_active, J$inc_active)         # active(−BM) 상관 ★판정
cat(sprintf("\n===== 직교성 =====\n"))
cat(sprintf("  gross return cor (earn vs inc)   = %.4f\n", active_cor_gross))
cat(sprintf("  ACTIVE(−KOSPI200) cor            = %.4f  [<0.30 이어야 sleeve 가치]\n", active_cor))

## ─── 7. book-marginal ΔIR (active-basis IR = mean/sd × sqrt(12)) ──────────
ir_ann <- function(active) (mean(active) / sd(active)) * sqrt(12)
inc_ir_overlap <- ir_ann(J$inc_active)   # overlap 구간 incumbent IR (참고)
inc_ir_full    <- 1.416026               # book_state incumbent (전기간 269m)
cat(sprintf("\n===== book-marginal ΔIR =====\n"))
cat(sprintf("  incumbent IR (full 269m)        = %.4f  [book_state]\n", inc_ir_full))
cat(sprintf("  incumbent IR (overlap %dm)       = %.4f  [동일구간 참고]\n", nrow(J), inc_ir_overlap))

## 50/50 블렌드 (월별 active 단순평균 = 자본 50/50 배분의 active)
J[, blend_50 := 0.5 * inc_active + 0.5 * earn_active]
ir_50 <- ir_ann(J$blend_50)

## IR-max 블렌드: w on earnings, (1-w) incumbent, maximize active IR (grid 0..1, w∈[0,0.5] 상한=sleeve 보조)
grid <- seq(0, 1, by = 0.01)
irs  <- sapply(grid, function(w) ir_ann((1 - w) * J$inc_active + w * J$earn_active))
w_opt <- grid[which.max(irs)]; ir_opt <- max(irs)
## 실무 상한: sleeve는 보조 → w_earn ≤ 0.5 제약본도 산출
grid_cap <- seq(0, 0.5, by = 0.01)
irs_cap  <- sapply(grid_cap, function(w) ir_ann((1 - w) * J$inc_active + w * J$earn_active))
w_opt_cap <- grid_cap[which.max(irs_cap)]; ir_opt_cap <- max(irs_cap)

## ΔIR은 동일구간(overlap) 기준으로 계산해야 타당 (incumbent full 269 ≠ overlap 261)
d_ir_50      <- ir_50      - inc_ir_overlap
d_ir_opt     <- ir_opt     - inc_ir_overlap
d_ir_opt_cap <- ir_opt_cap - inc_ir_overlap
cat(sprintf("  blend 50/50 IR                  = %.4f  (ΔIR vs overlap-inc = %+.4f)\n", ir_50, d_ir_50))
cat(sprintf("  IR-max blend (w_earn=%.2f)       = %.4f  (ΔIR = %+.4f)\n", w_opt, ir_opt, d_ir_opt))
cat(sprintf("  IR-max blend cap w≤0.5 (w=%.2f)   = %.4f  (ΔIR = %+.4f)\n", w_opt_cap, ir_opt_cap, d_ir_opt_cap))
cat(sprintf("  [게이트] ΔIR ≥ 0.05 (measurement-graduation §4)\n"))

## ─── 8. 2021+ 생존 (블렌드 active PORT_t NW lag3) ★결정적 관문 ────────────
nw_t <- function(x, lag = 3L) {
  x <- x[!is.na(x)]; n <- length(x); if (n < 5) return(NA_real_)
  e <- x - mean(x); s <- sum(e * e) / n
  for (l in seq_len(lag)) s <- s + 2 * (1 - l / (lag + 1)) * (sum(e[(l + 1):n] * e[1:(n - l)]) / n)
  mean(x) / sqrt(s / n)
}
J21 <- J[date >= as.Date("2021-01-01")]
t21_inc      <- nw_t(J21$inc_active)
t21_earn     <- nw_t(J21$earn_active)
t21_blend50  <- nw_t(J21$blend_50)
t21_blendopt <- nw_t((1 - w_opt_cap) * J21$inc_active + w_opt_cap * J21$earn_active)
cat(sprintf("\n===== 2021+ 생존 (n=%d) =====\n", nrow(J21)))
cat(sprintf("  incumbent active PORT_t (2021+)  = %.3f  (mean ann %+.4f)\n", t21_inc, mean(J21$inc_active)*12))
cat(sprintf("  earnings  active PORT_t (2021+)   = %.3f  (mean ann %+.4f)\n", t21_earn, mean(J21$earn_active)*12))
cat(sprintf("  blend50   active PORT_t (2021+)   = %.3f\n", t21_blend50))
cat(sprintf("  blend_opt(w=%.2f) PORT_t (2021+)   = %.3f\n", w_opt_cap, t21_blendopt))

## ─── 9. DSR/holdout 진단 (selection_type) ─────────────────────────────────
## P1 신호구성 = chain(n_trials=8, 가설주도). book 블렌드 비중 = sweep 소지(grid 0..1).
n_trials_signal <- 8L
n_trials_blend  <- length(grid)     # IR-max grid = sweep
## DSR 진단(단일 sleeve SR, Bailey-LdP 근사 진단용 — 게이트 아님)
sr_earn_active <- IR_earn
dsr_diag <- {
  T <- nrow(pr); sr <- SR_geo
  skew <- as.numeric(skewness(x_earn)); kurt <- as.numeric(kurtosis(x_earn)) + 3
  sr_std <- sqrt((1 - skew*sr + (kurt-1)/4*sr^2) / (T-1))
  ## SR0 for n_trials (blend grid) via expected max — 진단만
  list(sr = sr, sr_std = sr_std, T = T, skew = skew, kurt = kurt)
}

## ─── 10. 저장 ─────────────────────────────────────────────────────────────
saveRDS(list(manifest = data.table(run_id = RID, strategy_id = SID, frequency = "monthly",
                                    transaction_cost_bps = 15, benchmark_ids = "KOSPI200",
                                    note = "earnings S3 band × m4×β_R05 overlay. monthly ann=12."),
             period_returns = pr, benchmark_returns = br, nav = nav_tbl,
             metrics = metrics, benchmark_compare = bcmp),
        file.path(OUT, "bt_result_earn_sleeve.rds"))

res_tab <- data.table(
  metric = c("earn_n_months","earn_SR_geo","earn_CAGR","earn_MDD","earn_Calmar",
             "earn_PORT_t_NW","earn_IR_active","earn_alpha_ann","earn_beta",
             "overlap_months","gross_cor","ACTIVE_cor",
             "inc_IR_full","inc_IR_overlap","blend50_IR","dIR_blend50",
             "IRmax_w_earn","IRmax_IR","dIR_IRmax","IRmax_cap_w","IRmax_cap_IR","dIR_IRmax_cap",
             "t21_inc","t21_earn","t21_blend50","t21_blend_opt","n21"),
  value = c(nrow(pr), SR_geo, CAGR, MDD, CALMAR,
            PORT_t, IR_earn, ALPHA, BETA,
            nrow(J), active_cor_gross, active_cor,
            inc_ir_full, inc_ir_overlap, ir_50, d_ir_50,
            w_opt, ir_opt, d_ir_opt, w_opt_cap, ir_opt_cap, d_ir_opt_cap,
            t21_inc, t21_earn, t21_blend50, t21_blendopt, nrow(J21)))
res_tab[, value := round(value, 4)]
fwrite(res_tab, file.path(OUT, "bookmarginal_results.csv"))
fwrite(J[, .(date, inc_active, earn_active, blend_50)], file.path(OUT, "active_series_joined.csv"))

## 종합 판정
GO_cor   <- active_cor < 0.30
GO_dIR   <- max(d_ir_50, d_ir_opt_cap) >= 0.05
GO_2021  <- (t21_blend50 > 1.64) || (t21_blendopt > 1.64)   # 양수 유의(one-sided 5%)
verdict  <- if (GO_cor && GO_dIR && GO_2021) "GO" else "NO-GO"

write_json(list(
  task = "PG2 W2 earnings composite book-marginal (forge-authoritative)",
  date = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  strategy = "S3_consensus + 보유밴드(Blitz) × book overlay(m4×beta_R05, clean)",
  metric_type = "backtested(contract build_bt_result, annualization=12)",
  incumbent = list(book = "STR_1715_on_M4_R05_noLayer4_PG2", incumbent_book_ir = 1.416026,
                   benchmark = "KOSPI200 pinned IKS200"),
  earnings_sleeve = list(n_months = nrow(pr), SR_geo = round(SR_geo,4), CAGR = round(CAGR,4),
                         MDD = round(MDD,4), Calmar = round(CALMAR,4),
                         PORT_t_NW_lag3 = round(PORT_t,4), IR_active = round(IR_earn,4),
                         alpha_ann = round(ALPHA,4), beta = round(BETA,4),
                         turnover_annual = round(mean(mg$traded, na.rm=TRUE)*12,2)),
  orthogonality = list(overlap_months = nrow(J), gross_cor = round(active_cor_gross,4),
                       active_cor = round(active_cor,4), gate = "active_cor < 0.30",
                       pass = GO_cor, bench_sanity_maxdiff = signif(bench_diff,3)),
  book_marginal = list(inc_IR_full = 1.416026, inc_IR_overlap = round(inc_ir_overlap,4),
                       blend50_IR = round(ir_50,4), dIR_blend50 = round(d_ir_50,4),
                       IRmax_cap_w_earn = w_opt_cap, IRmax_cap_IR = round(ir_opt_cap,4),
                       dIR_IRmax_cap = round(d_ir_opt_cap,4),
                       gate = "dIR >= 0.05", pass = GO_dIR),
  survival_2021 = list(n = nrow(J21), t_inc = round(t21_inc,3), t_earn = round(t21_earn,3),
                       t_blend50 = round(t21_blend50,3), t_blend_opt = round(t21_blendopt,3),
                       gate = "blend active PORT_t(2021+) > 1.64 (양수 유의)", pass = GO_2021),
  dsr_holdout = list(selection_type_signal = "chain", n_trials_signal = n_trials_signal,
                     n_trials_blend = n_trials_blend,
                     blend_note = "book 블렌드 비중은 IR-max grid = sweep 소지 → DSR 진단 대상(게이트 아님, governor 정지).",
                     dsr_diag = dsr_diag),
  verdict = verdict,
  verdict_basis = "GO = active_cor<0.30 AND dIR>=0.05 AND blend 2021+ PORT_t 양수유의. 하나라도 실패 시 NO-GO.",
  governance = "book-marginal 스크리닝 증거만. graduation/admit 선언 금지 — governor 정지(도훈 수동)."
), file.path(OUT, "meta_bookmarginal.json"), auto_unbox = TRUE, pretty = TRUE)

cat(sprintf("\n===== 종합 판정 =====\n"))
cat(sprintf("  GO_active_cor(<0.30)   : %s (%.4f)\n", GO_cor, active_cor))
cat(sprintf("  GO_dIR(>=0.05)         : %s (best Δ=%+.4f)\n", GO_dIR, max(d_ir_50, d_ir_opt_cap)))
cat(sprintf("  GO_2021(PORT_t>1.64)   : %s (blend50=%.3f opt=%.3f)\n", GO_2021, t21_blend50, t21_blendopt))
cat(sprintf("  >>> VERDICT: %s <<<\n", verdict))
cat("\n[DONE] 저장: bookmarginal_results.csv / meta_bookmarginal.json / bt_result_earn_sleeve.rds / active_series_joined.csv\n")
