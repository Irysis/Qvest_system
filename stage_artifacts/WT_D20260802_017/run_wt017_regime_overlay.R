# =============================================================================
# run_wt017_regime_overlay.R — WT-D20260802_017 국면 라벨의 overlay 소비면 실측
#   사전등록: stage_artifacts/WT_D20260802_017/preregistration.json (측정 전 고정)
#   PRIMARY : e_cand = e_book(M4×R05 noLayer4 실현 β) × g(Category_{m-1}),
#             g = {CRISIS 0.40, CAUTION 0.70, else 1.00} (사전 고정 단일 스케줄, no-sweep)
#   판별    : paired NW lag-3 t (cand active − book active) + ΔIR — 현행 대비 한계기여
#   대조군  : BARE / BOOK / REGIME_ONLY / EW_BASIS / STRESS_LAG2 / DIAG_ORACLE(진단전용)
#   PIT     : assert_overlay_pit HARD + 위반 주입(홀딩월 라벨) + lag 스트레스 + strict A/B
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_017/run_wt017_regime_overlay.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_017")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt017] ", fmt, "\n"), ...))

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

# ── 1. 캐리어 (production-parity, §7b 선례) + 벤치 ───────────────────────────
CARRIER <- "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"
car <- as.data.table(read_parquet(CARRIER))[selected == TRUE & !is.na(ret_fwd)]
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
returns_dt <- car[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]
periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date)

bp <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bp[, d := as.Date(Date)]; setorder(bp, d)
bench_dt <- rbindlist(lapply(seq_len(nrow(periods)), function(i) {
  dd <- periods$decision_date[i]; ed <- periods$eval_date[i]
  sd_i <- bp[d >= dd, suppressWarnings(min(d))]
  if (is.infinite(sd_i) || is.na(sd_i)) return(data.table(Date = ed, BM_Ret = NA_real_))
  win <- bp[d > sd_i & d <= ed, BM_Ret]
  data.table(Date = ed, BM_Ret = if (length(win) == 0) NA_real_ else prod(1 + win, na.rm = TRUE) - 1)
}))[!is.na(BM_Ret)]
# ★그룹핑 주의: 정규화는 Date 단위 (Ticker를 by에 넣으면 w=1 → 전 arm EW 붕괴. 1차 실행에서
#   BOOK==BOOK_EW 동치가 지문으로 발화 → 수리. 검증: W_strat 월별 max w > 1/N 확인 assert)
W_strat <- car[, .(Ticker, w = weight_strategy / sum(weight_strategy)), by = .(Date = eval_date)][, .(Date, Ticker, w)]
W_ew    <- car[, .(Ticker, w = 1 / .N), by = .(Date = eval_date)][, .(Date, Ticker, w)]
chk <- merge(W_strat[, .(mx = max(w), n = .N), by = Date], W_ew[, .(ew = max(w)), by = Date], by = "Date")
stopifnot(chk[, mean(mx > ew * 1.05)] > 0.9)   # strategy tilt가 EW와 실제로 다른지 (붕괴 재발 가드)
say("carrier %d개월 (%s~%s), bench %d개월", nrow(periods),
    min(periods$eval_date), max(periods$eval_date), nrow(bench_dt))

# ── 2. 현행 book 노출 e_book = m4_weight_lag × beta_R05_V5 (noLayer4 공식) ───
L5 <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
stopifnot(all(c("anchor_date", "m4_weight_lag", "beta_R05_V5") %in% names(L5)))
e_book_dt <- L5[, .(Date = as.Date(anchor_date),
                    e_book = as.numeric(m4_weight_lag) * as.numeric(beta_R05_V5))]
per <- merge(periods, e_book_dt, by.x = "eval_date", by.y = "Date", all.x = TRUE)
n_miss_eb <- per[is.na(e_book), .N]
if (n_miss_eb > 0) say("★e_book 결측 %d행 → 1.0 대체 (결측=무overlay 라벨)", n_miss_eb)
per[is.na(e_book), e_book := 1.0]

# ── 3. 국면 라벨 (m-1 월말) + PIT HARD + 위반 주입 ───────────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))
u <- u[, .(RegDate = as.Date(Date), YM = as.character(YM), Category = as.character(Category))]
setkey(u, YM)
G <- c(CRISIS = 0.40, CAUTION = 0.70, NEUTRAL = 1.00, RISK_ON = 1.00)

per[, ym_lab  := prev_ym(decision_date, 1L)]           # m-1 라벨 (의사결정용, clean)
per[, ym_lab2 := prev_ym(decision_date, 2L)]           # m-2 (lag 스트레스)
per[, ym_hold := format(decision_date, "%Y-%m")]       # 홀딩월 자체 (주입 전용 — 본판정 금지)
per[u, on = c(ym_lab = "YM"),  `:=`(Category = i.Category, RegDate = i.RegDate)]
per[u, on = c(ym_lab2 = "YM"), `:=`(Category_l2 = i.Category)]
per[u, on = c(ym_hold = "YM"), `:=`(Category_contam = i.Category, RegDate_contam = i.RegDate)]

# PIT HARD: 사용 라벨의 월말 RegDate < 홀딩월 시작(decision_date)
assert_overlay_pit(per$RegDate, per$decision_date, label = "WT017_regime_m1_clean")
gap_days <- as.numeric(per$decision_date - per$RegDate)
say("PIT assert (m-1 라벨): PASS — %d개월, 라벨월말→홀딩시작 간격 median %.0f일 [%.0f, %.0f]",
    nrow(per), median(gap_days, na.rm = TRUE), min(gap_days, na.rm = TRUE), max(gap_days, na.rm = TRUE))

# 위반 주입: 홀딩월 자체 라벨(월말 RegDate > 홀딩 시작) → assert stop 발화해야 함
inj_block <- tryCatch({
  assert_overlay_pit(per$RegDate_contam, per$decision_date, label = "WT017_regime_contaminated")
  FALSE
}, error = function(e) grepl("LOOK-AHEAD", conditionMessage(e)))
say("PIT 위반 주입(홀딩월 라벨): %s", if (isTRUE(inj_block)) "차단 발화 (PASS)" else "★가드 미발화 (FAIL)")
stopifnot(isTRUE(inj_block))

per[, g      := unname(G[Category])];    per[is.na(g), g := 1.0]        # 라벨 결측=무조절
per[, g_l2   := unname(G[Category_l2])]; per[is.na(g_l2), g_l2 := 1.0]
per[, e_cand := e_book * g]
say("라벨 분포(m-1): %s | g<1 발화 %d개월", paste(names(table(per$Category)),
    table(per$Category), collapse = " "), per[g < 1, .N])

# ── 4. Arms (weighted_screen_bt — contract-grade, metric_type=weighted_screen) ─
exp_of <- function(col) per[, .(Date = eval_date, exposure = get(col))]
bm_neg <- bench_dt[, .(Date, neg = BM_Ret < 0)]
per[bm_neg, on = c(eval_date = "Date"), bm_neg := i.neg]
per[, e_oracle := e_book * fifelse(isTRUE(bm_neg), 0.40, 1.0), by = eval_date]

run_arm <- function(W, exposure_col = NULL, tag = "arm") {
  weighted_screen_bt(W, returns_dt, bench_dt, cost_bps_oneway = 15,
    run_id = "WT-D20260802_017", strategy_id = paste0("WT_D20260802_017_", tag),
    exposure_dt = if (is.null(exposure_col)) NULL else exp_of(exposure_col))
}
bt <- list()
bt$BARE        <- run_arm(W_strat, NULL,       "BARE")
bt$BOOK        <- run_arm(W_strat, "e_book",   "BOOK_M4xR05")
bt$CAND        <- run_arm(W_strat, "e_cand",   "CAND_regime_x_book")
bt$REGIME_ONLY <- run_arm(W_strat, "g",        "REGIME_ONLY")
per[, e_cand_l2 := e_book * g_l2]
bt$LAG2        <- run_arm(W_strat, "e_cand_l2", "STRESS_LAG2")
bt$ORACLE      <- run_arm(W_strat, "e_oracle", "DIAG_ORACLE_LOOKAHEAD")
bt$BOOK_EW     <- run_arm(W_ew,    "e_book",   "BOOK_EWbasis")
bt$CAND_EW     <- run_arm(W_ew,    "e_cand",   "CAND_EWbasis")
for (k in names(bt)) {
  r <- bt[[k]]
  say("%-12s PORT_t=%+.2f IR=%+.3f netSR(active)=%+.3f absSR=%+.3f absMDD=%.1f%% TO=%.1f/yr n=%d",
      k, r$portfolio_alpha_t_nw_lag3, r$information_ratio %||% NA, r$net_sr,
      r$abs_net_sr, 100 * r$abs_mdd, r$turnover_annual, r$n_months)
}

# ── 5. paired 한계기여 판정 (사전등록 discriminant) ──────────────────────────
paired <- function(a, b) {
  pa <- as.data.table(bt[[a]]$period_returns); pb <- as.data.table(bt[[b]]$period_returns)
  m <- merge(pa[, .(date, x = ret_net - benchmark_ret)],
             pb[, .(date, y = ret_net - benchmark_ret)], by = "date")
  m[, d := x - y]
  list(n = nrow(m), t = nw_t(m$d), mean_d_ann = mean(m$d) * 12,
       t_post2017 = m[date >= "2017-01-01", nw_t(d)], d_series = m)
}
PAIRED <- list(
  marginal_cand_vs_book       = paired("CAND", "BOOK"),
  regimeonly_vs_book          = paired("REGIME_ONLY", "BOOK"),
  marginal_lag2_vs_book       = paired("LAG2", "BOOK"),
  oracle_vs_book_DIAG         = paired("ORACLE", "BOOK"),
  marginal_cand_vs_book_EWb   = paired("CAND_EW", "BOOK_EW"))
for (nm in names(PAIRED))
  say("paired %-26s t=%+.2f (n=%d, %+.2f%%/yr, post17 t=%+.2f)", nm,
      PAIRED[[nm]]$t, PAIRED[[nm]]$n, 100 * PAIRED[[nm]]$mean_d_ann, PAIRED[[nm]]$t_post2017)
dIR <- (bt$CAND$information_ratio %||% NA_real_) - (bt$BOOK$information_ratio %||% NA_real_)
say("ΔIR (cand − book) = %+.3f", dIR)

# 회전/비용 축: overlay 노출 변경 증분 |Δe| 기준 15bps delta-cost 스트레스
setorder(per, eval_date)
to_add_book <- c(NA, abs(diff(per$e_book)))
to_add_cand <- c(NA, abs(diff(per$e_cand)))
say("overlay 노출 회전: book %.2f/yr → cand %.2f/yr (증분 %.2f/yr)",
    mean(to_add_book, na.rm = TRUE) * 12, mean(to_add_cand, na.rm = TRUE) * 12,
    (mean(to_add_cand, na.rm = TRUE) - mean(to_add_book, na.rm = TRUE)) * 12)
dcost <- data.table(date = per$eval_date,
                    dc = (fifelse(is.na(to_add_cand), 0, to_add_cand) -
                          fifelse(is.na(to_add_book), 0, to_add_book)) * 15 / 1e4)
mstress <- merge(PAIRED$marginal_cand_vs_book$d_series, dcost, by = "date")
mstress[, d_cost := d - dc]
COST_STRESS <- list(t = nw_t(mstress$d_cost), mean_d_ann = mean(mstress$d_cost) * 12)
say("비용 스트레스 반영 paired t = %+.2f (%+.2f%%/yr)", COST_STRESS$t, 100 * COST_STRESS$mean_d_ann)

# ── 6. 라벨-실현 이원 판정 ((c) CRISIS +4.98% 판별) ─────────────────────────
lr <- merge(per[, .(Date = eval_date, Category, g, e_book, e_cand)],
            bench_dt, by = "Date")
book_pr <- as.data.table(bt$BOOK$period_returns)[, .(Date = date, active_book = ret_net - benchmark_ret)]
cand_pr <- as.data.table(bt$CAND$period_returns)[, .(Date = date, active_cand = ret_net - benchmark_ret)]
lr <- Reduce(function(a, b) merge(a, b, by = "Date"), list(lr, book_pr, cand_pr))
lr[, bm_neg := BM_Ret < 0]
label_realized <- lr[, .(n = .N, bench_ann = mean(BM_Ret) * 12, frac_bm_neg = mean(bm_neg),
                         active_book_ann = mean(active_book) * 12,
                         active_cand_ann = mean(active_cand) * 12,
                         t_marginal = nw_t(active_cand - active_book)), by = Category]
say("라벨(m-1) × 실현:"); print(label_realized)
# hit-rate: 라벨∈{CRISIS,CAUTION}가 실현 BM<0을 잡는가
lr[, lab_risk := Category %in% c("CRISIS", "CAUTION")]
conf <- lr[, table(lab_risk, bm_neg)]
recall    <- conf["TRUE", "TRUE"] / sum(conf[, "TRUE"])
precision <- conf["TRUE", "TRUE"] / sum(conf["TRUE", ])
base_rate <- mean(lr$bm_neg)
fisher_p  <- tryCatch(fisher.test(conf)$p.value, error = function(e) NA_real_)
say("라벨→BM<0: recall=%.2f precision=%.2f base_rate=%.2f fisher_p=%.3f",
    recall, precision, base_rate, fisher_p)
# 실현-하락 축: BM<0 에피소드에서 cand가 손실을 완화했는가
down_axis <- lr[, .(n = .N, mean_bm = mean(BM_Ret),
                    active_book_m = mean(active_book), active_cand_m = mean(active_cand),
                    t_marginal = nw_t(active_cand - active_book)), by = bm_neg]
say("실현-하락 축(BM<0):"); print(down_axis)

# ── 7. AX-001 조건부 + 진단 ─────────────────────────────────────────────────
AX001 <- list(
  crisis_alpha_book = lr[Category == "CRISIS", mean(active_book) * 12],
  crisis_alpha_cand = lr[Category == "CRISIS", mean(active_cand) * 12],
  mdd_bare = bt$BARE$abs_mdd, mdd_book = bt$BOOK$abs_mdd, mdd_cand = bt$CAND$abs_mdd,
  bad_normal_book = lr[, .(m = mean(active_book)), by = bm_neg],
  bad_normal_cand = lr[, .(m = mean(active_cand)), by = bm_neg])
oos_rough <- sapply(c("BOOK", "CAND", "REGIME_ONLY"), function(a) {
  p <- as.data.table(bt[[a]]$period_returns)
  .canon_oos_rough(p$ret_net - p$benchmark_ret)
})
say("oos_rough(진단): %s", paste(names(oos_rough), sprintf("%.2f", oos_rough), collapse = " "))
# 2026 라벨 오염 구간 국소화 (WT-004: 2026-02~07 CRISIS 멜트업)
seg2026 <- lr[Date >= "2026-01-01",
              .(Date, Category, g, BM_Ret, active_book, active_cand)]
say("2026 구간:"); print(seg2026)

# ── 8. strict-PIT A/B 명시 (현 타이밍 = strict 동일) + 사이드카 ─────────────
ab <- overlay_lookahead_ab(bt$CAND$portfolio_alpha_t_nw_lag3,
                           bt$CAND$portfolio_alpha_t_nw_lag3, "PORT_t(current=strict 동일)")
say("%s", ab$message)
FEAT <- list(node_count = 5, max_depth = 3, free_param_count = 2,
  distinct_field_count = 2, conditional_op_count = 1, window_variety = 1,
  restatement_exposure = 0, escape_leaf_count = 2, escape_leaf_types = list("SPECIAL_OP"),
  note = "e_cand = e_book(M4xR05 실현 β, SPECIAL_OP) × g(unified Category m-1, SPECIAL_OP; g CRISIS .40/CAUTION .70 고정)")
ast_sidecar_log(lane = "weighted_screen", strategy_id = "WT_D20260802_017_CAND_regime_x_book",
  ast_features = FEAT,
  metrics = list(metric_type = "weighted_screen",
                 port_t = bt$CAND$portfolio_alpha_t_nw_lag3,
                 net_ir = bt$CAND$information_ratio, net_sr = bt$CAND$net_sr,
                 turnover_annual = bt$CAND$turnover_annual),
  extra = list(run_id = "WT-D20260802_017", n_months = bt$CAND$n_months,
               paired_marginal_t = PAIRED$marginal_cand_vs_book$t, delta_ir = dIR))
sc_after <- ast_sidecar_status()

# ── 9. 저장 ──────────────────────────────────────────────────────────────────
slim <- function(r) r[setdiff(names(r), "benchmark_compare")]
saveRDS(list(bt = lapply(bt, slim), paired = lapply(PAIRED, function(p) p[setdiff(names(p), "d_series")]),
             d_series = PAIRED$marginal_cand_vs_book$d_series,
             cost_stress = COST_STRESS, delta_ir = dIR,
             label_realized = label_realized, down_axis = down_axis,
             hit = list(recall = recall, precision = precision, base_rate = base_rate,
                        fisher_p = fisher_p, conf = conf),
             ax001 = AX001, oos_rough = oos_rough, seg2026 = seg2026,
             per = per[, .(decision_date, eval_date, Category, Category_l2, g, e_book, e_cand, bm_neg)],
             gap_days = summary(gap_days), inj_block = inj_block, n_miss_eb = n_miss_eb,
             overlay_turnover = list(book = mean(to_add_book, na.rm = TRUE) * 12,
                                     cand = mean(to_add_cand, na.rm = TRUE) * 12),
             sidecar = list(before = sc_before[c("live", "live_with_ast")],
                            after = sc_after[c("live", "live_with_ast")])),
        file.path(OUT, "wt017_results.rds"))
write_parquet(per[, .(Date = eval_date, decision_date, Category, g, e_book, e_cand)],
              file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt017_results.rds + alpha_scores.parquet (오버레이 노출 스케줄)")
