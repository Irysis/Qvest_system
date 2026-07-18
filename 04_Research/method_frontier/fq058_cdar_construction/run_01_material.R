# =============================================================================
# FQ-058 run_01: 재료 선정 — 5 후보팩터 canonical top-25 EW screen → 사전등록 규칙 선정
#   selection_rule: {screen_pass ∧ calmar<0.64}, MDD 내림차순 상위<=3.
#   결과-기반 선택 금지: 게이트-실패 메타데이터(calmar/screen)만으로 결정.
# Output: fq058_material_selection.json + fq058_baskets.parquet (선정재료 월별 top-25)
# =============================================================================
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/method_frontier/fq058_cdar_construction/fq058_lib.R")

REB_FROM <- 201001L; REB_TO <- 202605L; TOPN <- 25L
LIQ_MIN <- 2e8; COST <- 0.0015
CANDIDATES <- c("mom_12_1", "mom_6_1", "low_vol", "reversal_1m", "small_size")

P <- load_panels_f58()
reb_yms <- P$yms[P$yms >= REB_FROM & P$yms <= REB_TO]
cat("[panel] months:", length(P$yms), " reb months:", length(reb_yms),
    "range", reb_yms[1], "..", reb_yms[length(reb_yms)], "\n")

# ---- return matrix (xts) ----------------------------------------------------
span_yms <- P$yms[P$yms >= min(reb_yms)]
Mw <- dcast(P$mr[ym %in% span_yms], ym ~ Ticker, value.var = "ret_m")
Rmat <- as.matrix(Mw[, -1, drop = FALSE]); Rmat[is.na(Rmat)] <- 0
R_all <- xts(Rmat, order.by = ym2date_f(Mw$ym))

# ---- benchmark: cap-w member fresh ------------------------------------------
bsnap <- P$snap[ym %in% reb_yms & member == 1L & !is.na(size) & size > 0]
bsnap <- bsnap[Ticker %in% colnames(R_all)]
bsnap[, wb := size / sum(size), by = ym]
Bw <- dcast(bsnap, ym ~ Ticker, value.var = "wb", fill = 0)
Bx <- xts(as.matrix(Bw[, -1, drop = FALSE]), order.by = ym2date_f(Bw$ym))
bench_pf <- Return.portfolio(R_all[, colnames(Bx), drop = FALSE], weights = Bx, verbose = FALSE)
bench_dt <- data.table(date = index(bench_pf), benchmark_ret = as.numeric(bench_pf))

# ---- canonical EW top-25 screen for one factor ------------------------------
screen_ew <- function(factor) {
  wl <- list(); basket <- list()
  for (t_ym in reb_yms) {
    elig <- elig_at_f(P, t_ym, win = 60L, liq_min = LIQ_MIN)
    if (length(elig) < TOPN) next
    z <- signal_f58(P, t_ym, elig, factor)
    top <- names(sort(z, decreasing = TRUE))[seq_len(TOPN)]
    wl[[length(wl) + 1L]] <- data.table(ym = t_ym, Ticker = top, w = 1 / TOPN)
    basket[[length(basket) + 1L]] <- data.table(ym = t_ym, factor = factor, Ticker = top, z = z[top])
  }
  W <- rbindlist(wl); BK <- rbindlist(basket)
  tks <- sort(unique(W$Ticker))
  Wmw <- dcast(W, ym ~ Ticker, value.var = "w", fill = 0)
  Wx <- xts(as.matrix(Wmw[, -1, drop = FALSE])[, tks, drop = FALSE], order.by = ym2date_f(Wmw$ym))
  Rx <- R_all[, tks, drop = FALSE]
  pf <- Return.portfolio(Rx, weights = Wx, verbose = TRUE)
  ret <- pf$returns; bop <- as.matrix(pf$BOP.Weight); eop <- as.matrix(pf$EOP.Weight)
  n <- nrow(bop); eop_lag <- rbind(matrix(0, 1, ncol(eop)), eop[-n, , drop = FALSE])
  to <- rowSums(abs(bop - eop_lag)); cost <- COST * to
  net <- as.numeric(ret) - cost
  d <- data.table(date = index(ret), ret_net = net, to_oneway = to)
  m <- merge(d, bench_dt, by = "date", all.x = TRUE)
  stopifnot(!anyNA(m$benchmark_ret))
  m[, active := ret_net - benchmark_ret]
  net_x <- xts(m$ret_net, order.by = m$date)
  cagr <- as.numeric(Return.annualized(net_x, scale = 12, geometric = TRUE))
  mdd  <- as.numeric(maxDrawdown(net_x))
  pt   <- nw_t_f(m$active)
  sr_net <- ann_sr_f(m$ret_net)
  m[, yr := year(date)]; yr_to <- m[, .(to = sum(to_oneway), nn = .N), by = yr][nn == 12]
  list(factor = factor, n_months = nrow(m),
       net_sr = round(sr_net, 4), active_sr = round(ann_sr_f(m$active), 4),
       cagr = round(cagr, 4), mdd = round(mdd, 4), calmar = round(cagr / mdd, 4),
       port_t = round(pt$t, 4),
       turnover_oneway_annual = round(mean(yr_to$to), 3),
       basket = BK)
}

results <- lapply(CANDIDATES, screen_ew)
names(results) <- CANDIDATES

# ---- screen_pass 판정 + 선정 -------------------------------------------------
screen_pass <- function(r) {
  (isTRUE(r$net_sr >= 0.7) && isTRUE(r$cagr >= 0.12)) ||
  (isTRUE(r$net_sr >= 0.5) && isTRUE(r$port_t >= 2.0))
}
tab <- rbindlist(lapply(results, function(r) data.table(
  factor = r$factor, net_sr = r$net_sr, cagr = r$cagr, mdd = r$mdd,
  calmar = r$calmar, port_t = r$port_t, to_annual = r$turnover_oneway_annual,
  screen_pass = screen_pass(r))))
cat("\n=== candidate screen table ===\n"); print(tab)

qualify <- tab[screen_pass == TRUE & calmar < 0.64][order(-mdd)]
relaxed <- FALSE; note <- ""
if (nrow(qualify) == 0L) {
  # 순수 calmar-단독 FAIL 재료 없음 → screen_pass 완화 없이 calmar<0.64 만족 중 최선 신호 기록
  relaxed <- TRUE
  qualify <- tab[calmar < 0.64][order(-port_t)]
  note <- "순수 screen_pass∧calmar<0.64 재료 부재 → calmar<0.64 pool 에서 신호력(port_t) 상위로 완화(사전등록 완화규칙)."
}
selected <- head(qualify$factor, 3L)
cat("\n[selection] qualified(", nrow(qualify), "):", paste(qualify$factor, collapse = ", "),
    "| selected:", paste(selected, collapse = ", "), if (relaxed) "(RELAXED)" else "", "\n")

# ---- 산출물 -----------------------------------------------------------------
sel_json <- list(
  id = "FQ-058", round_tag = ROUND_TAG_F58, pin_consumed = PIN_F58,
  measured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "canonical_screen (screen_diagnostic)",
  selection_rule = "screen_pass ∧ calmar<0.64, MDD desc, top<=3 (사전등록 fq058_preregistration.json)",
  screen_pass_def = "(net SR>=0.7 ∧ CAGR>=0.12) OR (net SR>=0.5 ∧ PORT_t>=2.0)",
  n_reb_months = length(reb_yms), reb_range = c(reb_yms[1], reb_yms[length(reb_yms)]),
  bench = "cap-w K200|KQ150 fresh (Size, Return.portfolio)",
  candidate_table = tab, relaxed = relaxed, relaxed_note = note,
  qualified = qualify$factor, selected = selected)
write_json(sel_json, file.path(OUT_F58, "fq058_material_selection.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)

# 선정재료 월별 basket 저장 (run_02 소비 — 동일 basket 보장)
BK_sel <- rbindlist(lapply(selected, function(f) results[[f]]$basket))
write_parquet(BK_sel, file.path(OUT_F58, "fq058_baskets.parquet"))
cat("[done] run_01 — selected:", paste(selected, collapse = ", "),
    "| baskets rows:", nrow(BK_sel), "\n")
