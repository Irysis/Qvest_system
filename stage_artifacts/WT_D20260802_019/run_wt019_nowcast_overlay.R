# =============================================================================
# run_wt019_nowcast_overlay.R — WT-D20260802_019 실현-하락 nowcast 대체 라벨 (FQ-118)
#   사전등록: stage_artifacts/WT_D20260802_019/preregistration.json (측정 전 고정)
#   PRIMARY : DD_STATE = [벤치 TR지수(cutoff) <= 0.90 * max(지수, 트레일링 252거래일)]
#             cutoff = 홀딩월 시작(decision_date) 직전 거래일. 발화 시 g=0.40 (오라클 동일 스케줄)
#             e_cand = e_book(M4xR05 실현 beta) * g  — 파라미터 사전고정 단일값, no-sweep
#   순서    : (1) PIT HARD + 위반 주입 → (2) 라벨 품질 사전 검정(recall vs base) → (3) 성과
#   판별    : paired NW lag-3 t + ΔIR (WT-017 승계) + 오라클 대비 회수율
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_019/run_wt019_nowcast_overlay.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_019")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt019] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # .canon_oos_rough
source("02_Infrastructure/validation/overlay_pit_guard.R")
source("02_Infrastructure/contracts/ast_sidecar.R")
sc_before <- ast_sidecar_status()

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
prev_ym <- function(d, k = 1L) {
  fm <- as.Date(format(as.Date(d), "%Y-%m-01"))
  y <- as.integer(format(fm, "%Y")); m <- as.integer(format(fm, "%m")) - k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}

# ── 1. 캐리어 (production-parity, §7b) + 벤치 (일간 + 홀딩월 월간) ────────────
CARRIER <- "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"
car <- as.data.table(read_parquet(CARRIER))[selected == TRUE & !is.na(ret_fwd)]
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
returns_dt <- car[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]
periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date)

bp <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bp[, d := as.Date(Date)]; setorder(bp, d)
bp <- bp[!is.na(BM_Ret)]
bp[, cumidx := cumprod(1 + BM_Ret)]
say("벤치 일간 %d행 (%s ~ %s)", nrow(bp), min(bp$d), max(bp$d))

bench_dt <- rbindlist(lapply(seq_len(nrow(periods)), function(i) {
  dd <- periods$decision_date[i]; ed <- periods$eval_date[i]
  sd_i <- bp[d >= dd, suppressWarnings(min(d))]
  if (is.infinite(sd_i) || is.na(sd_i)) return(data.table(Date = ed, BM_Ret = NA_real_))
  win <- bp[d > sd_i & d <= ed, BM_Ret]
  data.table(Date = ed, BM_Ret = if (length(win) == 0) NA_real_ else prod(1 + win, na.rm = TRUE) - 1)
}))[!is.na(BM_Ret)]

# ★그룹핑 주의(WT-017 r1 재발 가드): 정규화는 Date 단위
W_strat <- car[, .(Ticker, w = weight_strategy / sum(weight_strategy)), by = .(Date = eval_date)][, .(Date, Ticker, w)]
W_ew    <- car[, .(Ticker, w = 1 / .N), by = .(Date = eval_date)][, .(Date, Ticker, w)]
chk <- merge(W_strat[, .(mx = max(w), n = .N), by = Date], W_ew[, .(ew = max(w)), by = Date], by = "Date")
stopifnot(chk[, mean(mx > ew * 1.05)] > 0.9)
say("carrier %d개월 (%s~%s), bench 월간 %d개월", nrow(periods),
    min(periods$eval_date), max(periods$eval_date), nrow(bench_dt))

# ── 2. 현행 book 노출 e_book = m4_weight_lag × beta_R05_V5 (read-only) ───────
L5 <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
stopifnot(all(c("anchor_date", "m4_weight_lag", "beta_R05_V5") %in% names(L5)))
e_book_dt <- L5[, .(Date = as.Date(anchor_date),
                    e_book = as.numeric(m4_weight_lag) * as.numeric(beta_R05_V5))]
per <- merge(periods, e_book_dt, by.x = "eval_date", by.y = "Date", all.x = TRUE)
n_miss_eb <- per[is.na(e_book), .N]
if (n_miss_eb > 0) say("★e_book 결측 %d행 → 1.0 대체", n_miss_eb)
per[is.na(e_book), e_book := 1.0]

# ── 3. PRIMARY 라벨: DD_STATE @ cutoff(홀딩 시작 직전 거래일) — 사전고정 규칙 ─
DD_THR <- 0.10; WIN <- 252L; G_ON <- 0.40   # preregistration.json 고정값
label_at <- function(anchor_dates) {
  # cutoff = max{bench d : d < anchor}. 트레일링 창 종점 = cutoff (홀딩월 데이터 배제)
  idx <- findInterval(as.Date(anchor_dates) - 1L, bp$d)   # d <= anchor-1  ⇔  d < anchor
  rbindlist(lapply(seq_along(idx), function(j) {
    i <- idx[j]
    if (i < 1L) return(data.table(cutoff = as.Date(NA), dd = NA_real_, n_win = 0L,
                                  vol21 = NA_real_, vol_q80 = NA_real_))
    lo <- max(1L, i - WIN + 1L)
    ddv <- bp$cumidx[i] / max(bp$cumidx[lo:i]) - 1
    v21 <- if (i >= 21L) sd(bp$BM_Ret[(i - 20L):i]) else NA_real_
    data.table(cutoff = bp$d[i], dd = ddv, n_win = i - lo + 1L, vol21 = v21, vol_q80 = NA_real_)
  }))
}
lab  <- label_at(per$decision_date)
per[, `:=`(cutoff = lab$cutoff, dd = lab$dd, n_win = lab$n_win, vol21 = lab$vol21)]
per[, dd_state := dd <= -DD_THR]
say("DD_STATE(m, thr=%.0f%%, win=%dd): ON %d / %d개월 | 창<252d(expanding) %d개월",
    100 * DD_THR, WIN, per[dd_state == TRUE, .N], nrow(per), per[n_win < WIN, .N])

# 진단 전용 변형(선택 사용 금지): DD5 / DD15 / VOL80(expanding 80분위) / M1NEG(라벨월 음수)
per[, dd_state_05 := dd <= -0.05]
per[, dd_state_15 := dd <= -0.15]
roll_sd <- frollapply(bp$BM_Ret, 21L, sd)
idx_cut <- findInterval(per$decision_date - 1L, bp$d)
per[, vol80 := vapply(idx_cut, function(i) {
  if (i < 42L) return(NA)
  roll_sd[i] > quantile(roll_sd[1:i], 0.8, na.rm = TRUE)   # expanding — cutoff 이전 데이터만
}, logical(1))]
per[, ym_lab := prev_ym(decision_date, 1L)]
m1 <- bp[, .(m1_ret = prod(1 + BM_Ret) - 1), by = .(ym = format(d, "%Y-%m"))]
per[m1, on = c(ym_lab = "ym"), m1_neg := i.m1_ret < 0]

# ── 4. PIT HARD + 위반 주입 (성과 측정 전) ───────────────────────────────────
stopifnot(all(is.finite(as.numeric(per$cutoff))))
assert_overlay_pit(per$cutoff, per$decision_date, label = "WT019_ddstate_clean")
stopifnot(per[, all(cutoff < decision_date)])   # 창 종점 = cutoff < 홀딩 시작 (직접 확인)
gap_days <- as.numeric(per$decision_date - per$cutoff)
say("PIT assert: PASS — 창 종점(cutoff)→홀딩시작 간격 median %.0f일 [%.0f, %.0f]",
    median(gap_days), min(gap_days), max(gap_days))
# 위반 주입: cutoff를 홀딩월 말(eval 직전 거래일)로 오염 → stop 발화해야 함
cut_contam <- bp$d[pmin(findInterval(per$eval_date, bp$d), nrow(bp))]
inj_block <- tryCatch({
  assert_overlay_pit(cut_contam, per$decision_date, label = "WT019_contaminated")
  FALSE
}, error = function(e) grepl("LOOK-AHEAD", conditionMessage(e)))
say("PIT 위반 주입(홀딩월말 cutoff): %s", if (isTRUE(inj_block)) "차단 발화 (PASS)" else "★가드 미발화 (FAIL)")
stopifnot(isTRUE(inj_block))

# ── 5. 라벨 품질 사전 검정 (성과 전에 먼저 — preregistration fail_line) ──────
per[bench_dt, on = c(eval_date = "Date"), bm_neg := i.BM_Ret < 0]
lab_quality <- function(on_vec, name) {
  ok <- is.finite(on_vec) & !is.na(per$bm_neg)
  tab <- table(factor(on_vec[ok], levels = c(FALSE, TRUE)),
               factor(per$bm_neg[ok], levels = c(FALSE, TRUE)))
  n_on <- sum(tab["TRUE", ]); n_neg <- sum(tab[, "TRUE"])
  rec  <- if (n_neg > 0) tab["TRUE", "TRUE"] / n_neg else NA_real_
  prec <- if (n_on > 0) tab["TRUE", "TRUE"] / n_on else NA_real_
  fp   <- tryCatch(fisher.test(tab)$p.value, error = function(e) NA_real_)
  data.table(label = name, n_on = n_on, recall = rec, precision = prec,
             base_rate = mean(per$bm_neg[ok]), fisher_p = fp)
}
LQ <- rbindlist(list(
  lab_quality(per$dd_state,    "PRIMARY_DD10_252d"),
  lab_quality(per$dd_state_05, "diag_DD5"),
  lab_quality(per$dd_state_15, "diag_DD15"),
  lab_quality(per$vol80,       "diag_VOL80_expanding"),
  lab_quality(per$m1_neg,      "diag_M1NEG")))
say("라벨 품질 사전 검정 (recall vs base=%.2f):", LQ$base_rate[1]); print(LQ)
pretest_pass <- LQ[label == "PRIMARY_DD10_252d",
                   recall > base_rate & is.finite(fisher_p) & fisher_p < 0.05]
say("PRIMARY 사전 검정: %s", if (isTRUE(pretest_pass)) "PASS (판별력 실재 — 성과 1급)"
                             else "FAIL (recall<=base 또는 fisher>=0.05 — 성과는 참고 병기)")

# ── 6. 성과 arms (weighted_screen_bt — contract-grade) ───────────────────────
G <- function(on) fifelse(on %in% TRUE, G_ON, 1.0)
per[, g := G(dd_state)]
per[, e_cand := e_book * g]
# lag 스트레스: cutoff를 1개월 더 앞당김 (라벨 정보를 한 달 더 늦춤)
lag_anchor <- as.Date(paste0(per[, prev_ym(decision_date, 1L)], "-01"))
lab_lag <- label_at(lag_anchor)
per[, g_lag := G(lab_lag$dd <= -DD_THR)]
per[, e_cand_lag := e_book * g_lag]
per[, e_oracle := e_book * fifelse(bm_neg %in% TRUE, G_ON, 1.0)]

exp_of <- function(col) per[, .(Date = eval_date, exposure = get(col))]
run_arm <- function(W, exposure_col = NULL, tag = "arm") {
  weighted_screen_bt(W, returns_dt, bench_dt, cost_bps_oneway = 15,
    run_id = "WT-D20260802_019", strategy_id = paste0("WT_D20260802_019_", tag),
    exposure_dt = if (is.null(exposure_col)) NULL else exp_of(exposure_col))
}
bt <- list()
bt$BARE         <- run_arm(W_strat, NULL,         "BARE")
bt$BOOK         <- run_arm(W_strat, "e_book",     "BOOK_M4xR05")
bt$CAND         <- run_arm(W_strat, "e_cand",     "CAND_dd10_x_book")
bt$NOWCAST_ONLY <- run_arm(W_strat, "g",          "NOWCAST_ONLY")
bt$LAG          <- run_arm(W_strat, "e_cand_lag", "STRESS_LAG")
bt$ORACLE       <- run_arm(W_strat, "e_oracle",   "DIAG_ORACLE_LOOKAHEAD")
bt$BOOK_EW      <- run_arm(W_ew,    "e_book",     "BOOK_EWbasis")
bt$CAND_EW      <- run_arm(W_ew,    "e_cand",     "CAND_EWbasis")
for (k in names(bt)) {
  r <- bt[[k]]
  say("%-13s PORT_t=%+.2f IR=%+.3f netSR(act)=%+.3f absSR=%+.3f absMDD=%.1f%% TO=%.1f/yr n=%d",
      k, r$portfolio_alpha_t_nw_lag3, r$information_ratio %||% NA, r$net_sr,
      r$abs_net_sr, 100 * r$abs_mdd, r$turnover_annual, r$n_months)
}

# ── 7. paired 판정 + 회수율 + 비용 스트레스 ──────────────────────────────────
paired <- function(a, b) {
  pa <- as.data.table(bt[[a]]$period_returns); pb <- as.data.table(bt[[b]]$period_returns)
  m <- merge(pa[, .(date, x = ret_net - benchmark_ret)],
             pb[, .(date, y = ret_net - benchmark_ret)], by = "date")
  m[, d := x - y]
  list(n = nrow(m), t = nw_t(m$d), mean_d_ann = mean(m$d) * 12,
       t_post2017 = m[date >= "2017-01-01", nw_t(d)], d_series = m)
}
PAIRED <- list(
  marginal_cand_vs_book     = paired("CAND", "BOOK"),
  nowcastonly_vs_book       = paired("NOWCAST_ONLY", "BOOK"),
  marginal_lag_vs_book      = paired("LAG", "BOOK"),
  oracle_vs_book_DIAG       = paired("ORACLE", "BOOK"),
  marginal_cand_vs_book_EWb = paired("CAND_EW", "BOOK_EW"))
for (nm in names(PAIRED))
  say("paired %-26s t=%+.2f (n=%d, %+.2f%%/yr, post17 t=%+.2f)", nm,
      PAIRED[[nm]]$t, PAIRED[[nm]]$n, 100 * PAIRED[[nm]]$mean_d_ann, PAIRED[[nm]]$t_post2017)
dIR <- (bt$CAND$information_ratio %||% NA_real_) - (bt$BOOK$information_ratio %||% NA_real_)
say("ΔIR (cand − book) = %+.3f", dIR)

# 회수율 (사전등록 mandate): return축 + MDD축
rec_ret <- PAIRED$marginal_cand_vs_book$mean_d_ann / PAIRED$oracle_vs_book_DIAG$mean_d_ann
rec_mdd <- (bt$BOOK$abs_mdd - bt$CAND$abs_mdd) / (bt$BOOK$abs_mdd - bt$ORACLE$abs_mdd)
say("오라클 회수율: return축 %.0f%% (%.2f / %.2f %%/yr) | MDD축 %.0f%% (%.1fpp / %.1fpp)",
    100 * rec_ret, 100 * PAIRED$marginal_cand_vs_book$mean_d_ann,
    100 * PAIRED$oracle_vs_book_DIAG$mean_d_ann,
    100 * rec_mdd, 100 * (bt$CAND$abs_mdd - bt$BOOK$abs_mdd) * -1,
    100 * (bt$ORACLE$abs_mdd - bt$BOOK$abs_mdd) * -1)

# 회전/비용: overlay 노출 변경 증분 |Δe| 15bps delta-cost 스트레스
setorder(per, eval_date)
to_add_book <- c(NA, abs(diff(per$e_book)))
to_add_cand <- c(NA, abs(diff(per$e_cand)))
say("overlay 노출 회전: book %.2f/yr → cand %.2f/yr (증분 %.2f/yr) | equity TO %.1f/yr (상한 11.0)",
    mean(to_add_book, na.rm = TRUE) * 12, mean(to_add_cand, na.rm = TRUE) * 12,
    (mean(to_add_cand, na.rm = TRUE) - mean(to_add_book, na.rm = TRUE)) * 12,
    bt$CAND$turnover_annual)
dcost <- data.table(date = per$eval_date,
                    dc = (fifelse(is.na(to_add_cand), 0, to_add_cand) -
                          fifelse(is.na(to_add_book), 0, to_add_book)) * 15 / 1e4)
mstress <- merge(PAIRED$marginal_cand_vs_book$d_series, dcost, by = "date")
mstress[, d_cost := d - dc]
COST_STRESS <- list(t = nw_t(mstress$d_cost), mean_d_ann = mean(mstress$d_cost) * 12)
say("비용 스트레스 반영 paired t = %+.2f (%+.2f%%/yr)", COST_STRESS$t, 100 * COST_STRESS$mean_d_ann)

# ── 8. 라벨×실현 분해 + AX-001 조건부 + 진단 ─────────────────────────────────
book_pr <- as.data.table(bt$BOOK$period_returns)[, .(Date = date, active_book = ret_net - benchmark_ret)]
cand_pr <- as.data.table(bt$CAND$period_returns)[, .(Date = date, active_cand = ret_net - benchmark_ret)]
lr <- Reduce(function(a, b) merge(a, b, by = "Date"),
             list(per[, .(Date = eval_date, dd_state, dd, g, e_book, e_cand, bm_neg)],
                  bench_dt, book_pr, cand_pr))
label_realized <- lr[, .(n = .N, bench_ann = mean(BM_Ret) * 12, frac_bm_neg = mean(bm_neg),
                         active_book_ann = mean(active_book) * 12,
                         active_cand_ann = mean(active_cand) * 12,
                         t_marginal = nw_t(active_cand - active_book)), by = dd_state]
say("DD_STATE × 실현:"); print(label_realized)
down_axis <- lr[, .(n = .N, mean_bm = mean(BM_Ret),
                    active_book_m = mean(active_book), active_cand_m = mean(active_cand),
                    t_marginal = nw_t(active_cand - active_book)), by = bm_neg]
say("실현-하락 축(BM<0):"); print(down_axis)
AX001 <- list(
  crisis_alpha_book = lr[dd_state == TRUE, mean(active_book) * 12],
  crisis_alpha_cand = lr[dd_state == TRUE, mean(active_cand) * 12],
  mdd_bare = bt$BARE$abs_mdd, mdd_book = bt$BOOK$abs_mdd,
  mdd_cand = bt$CAND$abs_mdd, mdd_oracle = bt$ORACLE$abs_mdd,
  bad_normal_book = lr[, .(m = mean(active_book)), by = bm_neg],
  bad_normal_cand = lr[, .(m = mean(active_cand)), by = bm_neg])
oos_rough <- sapply(c("BOOK", "CAND", "NOWCAST_ONLY"), function(a) {
  p <- as.data.table(bt[[a]]$period_returns)
  .canon_oos_rough(p$ret_net - p$benchmark_ret)
})
say("oos_rough(진단): %s", paste(names(oos_rough), sprintf("%.2f", oos_rough), collapse = " "))
seg2026 <- lr[Date >= "2026-01-01", .(Date, dd_state, dd, g, BM_Ret, active_book, active_cand)]
say("2026 구간:"); print(seg2026)
# ON월 연대기 (지연-지표 여부 육안 판독용)
say("DD_STATE ON월 연대기 (홀딩월):")
print(per[dd_state == TRUE, .(hold_ym = format(decision_date, "%Y-%m"), dd = round(dd, 3))])

# ── 9. strict A/B 명시 + 사이드카 + 저장 ─────────────────────────────────────
ab <- overlay_lookahead_ab(bt$CAND$portfolio_alpha_t_nw_lag3,
                           bt$CAND$portfolio_alpha_t_nw_lag3, "PORT_t(current=strict 동일)")
say("%s", ab$message)
FEAT <- list(node_count = 7, max_depth = 4, free_param_count = 2,
  distinct_field_count = 2, conditional_op_count = 1, window_variety = 1,
  restatement_exposure = 0, escape_leaf_count = 1, escape_leaf_types = list("SPECIAL_OP"),
  note = "e_cand = e_book(M4xR05 실현 beta, SPECIAL_OP) × IF(DD_STATE(bench cumidx, TS_MAX 252d, thr -10%), 0.40, 1.00) — 파라미터 사전고정")
ast_sidecar_log(lane = "weighted_screen", strategy_id = "WT_D20260802_019_CAND_dd10_x_book",
  ast_features = FEAT,
  metrics = list(metric_type = "weighted_screen",
                 port_t = bt$CAND$portfolio_alpha_t_nw_lag3,
                 net_ir = bt$CAND$information_ratio, net_sr = bt$CAND$net_sr,
                 turnover_annual = bt$CAND$turnover_annual),
  extra = list(run_id = "WT-D20260802_019", n_months = bt$CAND$n_months,
               paired_marginal_t = PAIRED$marginal_cand_vs_book$t, delta_ir = dIR,
               pretest_pass = isTRUE(pretest_pass)))
sc_after <- ast_sidecar_status()

slim <- function(r) r[setdiff(names(r), "benchmark_compare")]
saveRDS(list(bt = lapply(bt, slim),
             paired = lapply(PAIRED, function(p) p[setdiff(names(p), "d_series")]),
             d_series = PAIRED$marginal_cand_vs_book$d_series,
             cost_stress = COST_STRESS, delta_ir = dIR,
             recovery = list(ret = rec_ret, mdd = rec_mdd),
             label_quality = LQ, pretest_pass = isTRUE(pretest_pass),
             label_realized = label_realized, down_axis = down_axis,
             ax001 = AX001, oos_rough = oos_rough, seg2026 = seg2026,
             per = per[, .(decision_date, eval_date, cutoff, dd, n_win, dd_state, g,
                           g_lag, e_book, e_cand, bm_neg)],
             gap_days = summary(gap_days), inj_block = inj_block, n_miss_eb = n_miss_eb,
             overlay_turnover = list(book = mean(to_add_book, na.rm = TRUE) * 12,
                                     cand = mean(to_add_cand, na.rm = TRUE) * 12),
             sidecar = list(before = sc_before[c("live", "live_with_ast")],
                            after = sc_after[c("live", "live_with_ast")])),
        file.path(OUT, "wt019_results.rds"))
write_parquet(per[, .(Date = eval_date, decision_date, cutoff, dd, dd_state, g, e_book, e_cand)],
              file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt019_results.rds + alpha_scores.parquet (nowcast 오버레이 노출 스케줄)")
