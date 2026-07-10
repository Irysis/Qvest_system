# =============================================================================
# 챔피언 재검증 슬롯 2 — book+value sleeve blend w=0.15 (원 관측 PORT_t 6.218)
# 통일 하네스 재측정 (2026-07-10, 도훈 mandate "최상급 PORT_t" 토너먼트)
# -----------------------------------------------------------------------------
# 원 kill (2026-06-12): dIR +0.036 < 0.05 게이트 + dSR -0.037 → DEFER
# 원 측정의 stale 요소: ① IKS001 버그 벤치(07-02 IKS200 교정 전)
#                       ② 구 book(L5_V2, 07-03 noLayer4 전환 전)
# 통일 하네스 = 현직 챔피언 6.272 산출 하네스 그대로:
#   carrier_STR_1715 parquet + ovl0.5 + pinned benchmark.parquet(IKS200) +
#   build_benchmark_compare PORT_t NW lag3 + oos v2(3분할 중앙값)
#   [pin tag: stage_artifacts/pg2_overlay_gate_composition_20260705/pinned_cache]
# 규율: 실측만(계약 함수), IS(2005-2018)-only 선별, placebo(circular shift),
#       n_trials 기록(grid 5, 원 sweep 5와 동일 grid — 누적 별도 기록)
# metric_type = backtested / basis = cap-w active vs pinned IKS200 (authoritative)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(lubridate)
  library(PerformanceAnalytics); library(xts); library(jsonlite)
})
setDTthreads(1); PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD10 <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
PD   <- file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
VSD  <- file.path(ROOT, "04_Research/composition_search/value_sleeve_combination")
OUT  <- file.path(VSD, "revalidation_20260710")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

COST_BPS <- 15; OVL_ALPHA <- 0.5
W_GRID <- c(0.05, 0.10, 0.15, 0.20, 0.30)   # n_trials = 5 (원 사전등록 grid 동일)
IS_END <- as.Date("2018-12-31")

# ---- 1. carrier base book (cycle10 로직 동일 재현) ----
car <- as.data.table(read_parquet(file.path(ROOT,
  "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")))
dcol <- if ("decision_date" %in% names(car)) "decision_date" else "eval_date"
car[, dd := as.Date(get(dcol))]
base <- car[selected == TRUE | is.na(selected),
            .(ret = sum(weight_strategy * ret_fwd, na.rm = TRUE),
              sw  = sum(weight_strategy, na.rm = TRUE)), by = dd]
base <- base[sw > 0.5]; setorder(base, dd)
base[, ym := format(dd, "%Y-%m")]
PG("[1] carrier base n=%d %s..%s", nrow(base), min(base$dd), max(base$dd))

# ---- 2. overlay exposure e (cycle10 동일) + fidelity offset ----
bt  <- readRDS(file.path(PD, "04_backtest_results/bt_result_layer5_R05.rds"))
prr <- as.data.table(bt$period_returns)
prr[, e := ret_L5_V5 / ret_orig]
prr[!is.finite(e) | abs(ret_orig) < 0.003, e := NA_real_]
prr[, e := nafill(nafill(e, "locf"), "nocb")]; prr[e < 0, e := 0]; prr[e > 1.2, e := 1.2]
prr[, rym := as.character(realized_ym)]
prr[, ym_key := ifelse(grepl("-", rym), rym,
  format(as.Date(paste0(substr(rym,1,4), "-", substr(rym,5,6), "-01")), "%Y-%m"))]
best <- list(o = NA, c = -2)
for (o in -2:2) {
  t <- copy(base); t[, k := format(as.Date(paste0(ym, "-01")) %m+% months(o), "%Y-%m")]
  mm <- merge(t, prr[, .(k = ym_key, ret_orig)], by = "k")
  if (nrow(mm) > 50) { cc <- cor(mm$ret, mm$ret_orig); if (cc > best$c) { best$c <- cc; best$o <- o } }
}
PG("[2] fidelity: carrier vs bt ret_orig offset=%d cor=%.4f (기대 =1.0000)", best$o, best$c)
stopifnot(best$c > 0.97)

# ---- 3. pinned benchmark (IKS200 교정, §7 pin) ----
bm <- as.data.table(read_parquet(file.path(WD10, "pinned_cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date, "%Y-%m")]
bmm <- bm[, .(bm_ret = prod(1 + BM_Ret) - 1), by = ym]
bo <- 0; bc <- -2
for (o in -1:3) {
  t <- copy(base); t[, k := format(as.Date(paste0(ym, "-01")) %m+% months(o), "%Y-%m")]
  mm <- merge(t, bmm[, .(k = ym, bm_ret)], by = "k")
  if (nrow(mm) > 50) { cc <- cor(mm$ret, mm$bm_ret); if (cc > bc) { bc <- cc; bo <- o } }
}
PG("[3] bench offset bo=%d cor=%.4f (캘린더월 키 = ym(dd)+bo)", bo, bc)

# ---- 4. book(ovl0.5) 시계열 + 캘린더월 키 ----
b <- copy(base)
b[, k := format(as.Date(paste0(ym, "-01")) %m+% months(best$o), "%Y-%m")]
b <- merge(b, prr[, .(k = ym_key, e)], by = "k", all.x = TRUE); b[is.na(e), e := 1]
b[, ret_ovl := ret * (1 - OVL_ALPHA * (1 - e))]
b[, kcal := format(as.Date(paste0(ym, "-01")) %m+% months(bo), "%Y-%m")]
b <- merge(b, bmm[, .(kcal = ym, BM_Ret = bm_ret)], by = "kcal")
setorder(b, dd)

# ---- 5. value sleeve (corrected aligned rds, read-only; 진짜 캘린더월 키) ----
V <- as.data.table(readRDS(file.path(VSD, "corrected/aligned_series_corrected.rds")))
# V: realized_ym(진짜 캘린더월) / value_ret(top-20 EW net 15bps) / bench_ret(구벤치, 미사용)
M <- merge(b[, .(kcal, dd, book_ret = ret_ovl, BM_Ret)],
           V[, .(kcal = realized_ym, value_ret)], by = "kcal")
setorder(M, dd); n <- nrow(M)
PG("[5] 교집합 n=%d %s..%s", n, M$kcal[1], M$kcal[n])
# 정렬 진단 (β-scan 스타일): value를 ±2 어긋내면 cor가 떨어져야 정렬 정상
for (o in -2:2) {
  vv <- shift(M$value_ret, o); ok <- !is.na(vv)
  PG("    offset %+d: cor(value, book)=%.4f  cor(value, BM)=%.4f",
     o, cor(vv[ok], M$book_ret[ok]), cor(vv[ok], M$BM_Ret[ok]))
}

# ---- 6. metric 블록 (cycle10 metr 동일 + IS/OOS 창 인자) ----
metr <- function(dts, ret, bmr, tag) {
  if (length(ret) < 50) return(NULL)
  prt <- data.table(date = dts, ret_net = ret, frequency = "monthly")
  brt <- data.table(date = dts, benchmark_ret = bmr, benchmark_id = "K200_pinned")
  bcp <- build_benchmark_compare(prt, brt, tag, tag, annualization_factor = 12)
  gv <- function(nm) { v <- bcp[metric_name == nm, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
  act <- ret - bmr; nn <- length(act)
  oos <- median(sapply(c(.55, .65, .75), function(q) {
    ct <- floor(nn * q)
    (mean(act[(ct+1):nn]) / sd(act[(ct+1):nn])) / (mean(act[1:ct]) / sd(act[1:ct]))
  }), na.rm = TRUE)
  i2 <- dts >= as.Date("2017-01-01"); a2 <- act[i2]; m2 <- mean(a2); dm <- a2 - m2
  n2 <- length(a2); g0 <- sum(dm^2) / n2; gs <- 0
  for (L in 1:3) { wt <- 1 - L/4; gs <- gs + 2*wt*sum(dm[(L+1):n2]*dm[1:(n2-L)])/n2 }
  p17 <- m2 / sqrt((g0 + gs) / n2)
  rx <- xts(ret, order.by = dts)
  cg <- as.numeric(Return.annualized(rx, scale = 12)); md <- as.numeric(maxDrawdown(rx))
  sr <- as.numeric(SharpeRatio.annualized(rx, Rf = 0))
  data.table(tag = tag, n = nn, PORT_t = gv("Portfolio_Alpha_t_NW_lag3"),
             IR = gv("Information_Ratio"), TE = gv("Tracking_Error"),
             SR = sr, oos_ret = oos, post2017_t = p17,
             cagr = cg, mdd = md, calmar = if (md > 0) cg/md else NA_real_)
}

# ---- 7. blend (Return.portfolio 월간 리밸 + blend 회전 15bps) ----
dts <- as.Date(paste0(M$kcal, "-01"))
ret_mat <- xts(cbind(book = M$book_ret, value = M$value_ret), order.by = dts)
blend_net <- function(wv, rm = ret_mat) {
  rp <- Return.portfolio(rm, weights = c(book = 1 - wv, value = wv),
                         rebalance_on = "months", verbose = TRUE)
  gross <- rp$returns; bop <- rp$BOP.Weight; eop <- rp$EOP.Weight
  to <- rep(0, nrow(bop))
  for (i in 2:nrow(bop)) to[i] <- sum(abs(as.numeric(bop[i,]) - as.numeric(eop[i-1,])))
  as.numeric(gross - xts(to * COST_BPS / 1e4, order.by = index(gross)))
}

res <- list(metr(dts, M$book_ret, M$BM_Ret, "BOOK_ovl0.5_base"))
for (wv in W_GRID) res[[length(res)+1]] <- metr(dts, blend_net(wv), M$BM_Ret, sprintf("BLEND_w%.2f", wv))
RES <- rbindlist(res, fill = TRUE)
bk <- RES[tag == "BOOK_ovl0.5_base"]
RES[, dPORT_t := PORT_t - bk$PORT_t][, dIR := IR - bk$IR][, dSR := SR - bk$SR][, dCalmar := calmar - bk$calmar]
PG("[7] FULL-SAMPLE (cap-w authoritative, pinned IKS200):")
print(RES[, .(tag, n, PORT_t = round(PORT_t,3), dPORT_t = round(dPORT_t,3), IR = round(IR,3),
              dIR = round(dIR,3), SR = round(SR,3), dSR = round(dSR,4), oos_ret = round(oos_ret,3),
              post2017_t = round(post2017_t,2), calmar = round(calmar,3), mdd = round(mdd,3))])

# ---- 8. IS(2005-2018)-only 선별 → OOS 1회 ----
is_idx <- dts <= IS_END; oos_idx <- !is_idx
PG("[8] IS n=%d / OOS n=%d", sum(is_idx), sum(oos_idx))
is_res <- list(metr(dts[is_idx], M$book_ret[is_idx], M$BM_Ret[is_idx], "IS_BOOK"))
for (wv in W_GRID) {
  bn <- blend_net(wv)
  is_res[[length(is_res)+1]] <- metr(dts[is_idx], bn[is_idx], M$BM_Ret[is_idx], sprintf("IS_w%.2f", wv))
}
ISR <- rbindlist(is_res, fill = TRUE)
isbk <- ISR[tag == "IS_BOOK"]
ISR[, dIR := IR - isbk$IR][, dPORT_t := PORT_t - isbk$PORT_t]
print(ISR[, .(tag, PORT_t = round(PORT_t,3), dPORT_t = round(dPORT_t,3), IR = round(IR,3), dIR = round(dIR,3))])
wstar_ir <- W_GRID[which.max(ISR[tag != "IS_BOOK", dIR])]
wstar_pt <- W_GRID[which.max(ISR[tag != "IS_BOOK", dPORT_t])]
PG("    IS-선별 w*: by dIR = %.2f / by dPORT_t = %.2f", wstar_ir, wstar_pt)
oos_book <- metr(dts[oos_idx], M$book_ret[oos_idx], M$BM_Ret[oos_idx], "OOS_BOOK")
oos_star <- metr(dts[oos_idx], blend_net(wstar_ir)[oos_idx], M$BM_Ret[oos_idx], sprintf("OOS_w%.2f_starIR", wstar_ir))
oos_star2 <- if (wstar_pt != wstar_ir)
  metr(dts[oos_idx], blend_net(wstar_pt)[oos_idx], M$BM_Ret[oos_idx], sprintf("OOS_w%.2f_starPT", wstar_pt)) else NULL
OOSR <- rbindlist(c(list(oos_book, oos_star), if (!is.null(oos_star2)) list(oos_star2)), fill = TRUE)
PG("[8b] OOS(2019+) 1회 판정:")
print(OOSR[, .(tag, n, PORT_t = round(PORT_t,3), IR = round(IR,3), SR = round(SR,3), calmar = round(calmar,3))])

# ---- 9. placebo — value_ret circular shift 전수 (12..n-12), ΔPORT_t null 분포 ----
w0 <- 0.15
obs_d <- RES[tag == "BLEND_w0.15", dPORT_t]
shifts <- 12:(n - 12)
null_d <- rep(NA_real_, length(shifts))
for (si in seq_along(shifts)) {
  s <- shifts[si]
  vperm <- M$value_ret[c((s+1):n, 1:s)]
  rm2 <- xts(cbind(book = M$book_ret, value = vperm), order.by = dts)
  bn <- blend_net(w0, rm2)
  mtmp <- metr(dts, bn, M$BM_Ret, "perm")
  null_d[si] <- mtmp$PORT_t - bk$PORT_t
}
pval <- mean(null_d >= obs_d, na.rm = TRUE)
PG("[9] placebo(circular %d개): obs dPORT_t=%.3f  null mean=%.3f q95=%.3f  p=%.4f",
   length(shifts), obs_d, mean(null_d, na.rm=TRUE), quantile(null_d, .95, na.rm=TRUE), pval)

# ---- 10. 저장 ----
fwrite(RES, file.path(OUT, "full_sample_results.csv"))
fwrite(ISR, file.path(OUT, "is_results.csv"))
fwrite(OOSR, file.path(OUT, "oos_results.csv"))
out <- list(
  meta = list(
    task = "champion_reval_slot2_book_value_blend", as_of = "2026-07-10",
    harness = "carrier(cycle10/11 동일) + pinned IKS200 bench + build_benchmark_compare NW lag3",
    pin_tag = "stage_artifacts/pg2_overlay_gate_composition_20260705/pinned_cache",
    basis = "cap-w active vs pinned IKS200 (authoritative)",
    metric_type = "backtested",
    n_trials_this_run = length(W_GRID), n_trials_cumulative_note = "원 sweep 5(20260612) + 본 재측정 동일 grid 5 (동일 가설 재측정, 신규 탐색 아님)",
    selection_type = "sweep", is_end = as.character(IS_END),
    fidelity_cor = best$c, bench_offset = bo, n_months = n
  ),
  full_sample = RES, is_sample = ISR, oos_sample = OOSR,
  placebo = list(w = w0, obs_dPORT_t = obs_d, n_perm = length(shifts),
                 null_mean = mean(null_d, na.rm=TRUE),
                 null_q95 = as.numeric(quantile(null_d, .95, na.rm=TRUE)), p_value = pval),
  champion_ref = list(book_base_6272 = "cycle11 BASE_prod+ovl0.5 n=269 (본 재측정 book은 value 교집합 n으로 재산출)")
)
write_json(out, file.path(OUT, "reval_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
PG("DONE -> %s", OUT)
