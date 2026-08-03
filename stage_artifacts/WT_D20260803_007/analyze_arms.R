# =============================================================================
# analyze_arms.R — WT-D20260803_007 (FQ-135) Step C: arm canonical 실측 + 판별
#   입력: composite_main/rand/placebo.parquet + memberships.rds (Step A/B)
#   사전등록: preregistration.json (판별식 (a)/(b) 측정 전 고정)
# 실행: Rscript stage_artifacts/WT_D20260803_007/analyze_arms.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt007C] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/ramp/factor_validation.R")
nwt <- function(x, lag = 3L) { xv <- x[is.finite(x)]; if (length(xv) < 20L) return(NA_real_); .nw_t_mean(xv, lag = lag) }

MB  <- readRDS(file.path(OUT, "memberships.rds"))
LAB <- readRDS(file.path(SRC5, "registry_labels.rds"))
CP5 <- readRDS(file.path(SRC5, "canonical_pool.rds"))
MAINP <- as.data.table(read_parquet(file.path(OUT, "composite_main.parquet")))
RANDP <- as.data.table(read_parquet(file.path(OUT, "composite_rand.parquet")))
PLACP <- as.data.table(read_parquet(file.path(OUT, "composite_placebo.parquet")))
for (D in list(MAINP, RANDP, PLACP)) D[, Date := as.Date(Date)]

# ── 하네스 (WT-004/005 동일 vintage) ────────────────────────────────────────
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
META <- readRDS(file.path(SRC5, "pool_meta.rds")); sig_all <- META$sig_all
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt <- RAWME[Date %in% sig_all & (K200 == TRUE | KQ150 == TRUE) & !is.na(Size), .(Date, Ticker, Size)]

AST_FEAT <- list(
  spec_version = "ast_v1.1", leaf_count = 1L, node_count = 3L, free_param = 3L,
  conditional_op = 0L, escape_leaf = "SPECIAL_OP", combination_rule = "z_score_aligned_equal_weight",
  op_code_path = "stage_artifacts/WT_D20260803_007/build_composites.R", walk_forward = TRUE)

canon <- function(sc, tag, dual = TRUE, ast = TRUE) {
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n = 25L, cost_bps_oneway = 15,
    liq_dt = liq_dt, liq_min = 2e8, run_id = "WT-D20260803_007",
    strategy_id = paste0("WT_D20260803_007_", tag),
    diag_dual_basis = dual, size_dt = if (dual) size_dt else NULL,
    ast_features = if (ast) AST_FEAT else NULL)
}

# ── 1. main arm canonical ───────────────────────────────────────────────────
MAIN <- MB$main_arms
sink(file.path(OUT, "canon_main.log"))
RES <- list(); t0 <- Sys.time()
for (a in MAIN) {
  sc <- MAINP[arm == a, .(Date, Ticker, score)]
  RES[[a]] <- tryCatch(canon(sc, a, dual = TRUE), error = function(e) NULL)
}
sink()
say("main arm canonical %d개 / %.0fs", length(RES), as.numeric(difftime(Sys.time(), t0, units="secs")))

row_of <- function(a, r) {
  ew <- r$diag_ew_universe; ct <- r$diag_cap_tier
  data.table(arm = a, kind = MB$arms[[a]]$kind, n_months = r$n_months,
    port_t = r$portfolio_alpha_t_nw_lag3, p_val = r$portfolio_alpha_t_pvalue,
    ir = r$information_ratio, net_sr = r$net_sr, alpha_ann = r$alpha_annualized,
    mean_active = r$mean_active_net, turnover_annual = r$turnover_annual,
    ew_port_t = if (!is.null(ew$portfolio_alpha_t_nw_lag3)) ew$portfolio_alpha_t_nw_lag3 else NA_real_,
    cap_mega = if (isTRUE(ct$available)) as.numeric(ct$weight_share_avg$MEGA) else NA_real_,
    cap_mid  = if (isTRUE(ct$available)) as.numeric(ct$weight_share_avg$MID)  else NA_real_,
    cap_other = if (isTRUE(ct$available)) as.numeric(ct$weight_share_avg$OTHER) else NA_real_)
}
SUM <- rbindlist(lapply(names(RES), function(a) tryCatch(row_of(a, RES[[a]]),
        error = function(e) data.table(arm = a, kind = NA_character_))), fill = TRUE)
setorder(SUM, -port_t)
say("--- main arm 실측 (OOS canonical, metric_type=canonical_screen) ---"); print(SUM)

# ── 2. 판별식 (a)/(b) — paired NW t ─────────────────────────────────────────
pr_of <- function(a) { p <- as.data.table(RES[[a]]$period_returns)
  p[, .(date, ret_net, bm = benchmark_ret, active = ret_net - benchmark_ret)] }
paired <- function(x, y) {
  m <- merge(pr_of(x)[, .(date, ax = active)], pr_of(y)[, .(date, ay = active)], by = "date")
  d <- m$ax - m$ay
  data.table(pair = sprintf("%s - %s", x, y), n = nrow(m), mean_diff_ann = 12 * mean(d),
             t_nw_lag3 = nwt(d), win_rate = mean(d > 0))
}
PAIRS <- rbindlist(list(
  paired("A_REL_TOP", "A_REL_BOT"),          # 판별 (a)
  paired("A_REL_TOP", "SINGLE_BEST"),        # 판별 (b) ★
  paired("A_REL_TOP", "POOL_EW"),
  paired("A_ABS_TOP", "SINGLE_BEST"),
  paired("A_PERP_TOP", "SINGLE_BEST"),
  paired("A_PERP_TOP", "A_REL_BOT"),
  paired("A_ABS_TOP", "A_REL_BOT"),
  paired("A_REL_TOP_K10", "A_REL_BOT_K10"),
  paired("A_REL_TOP_K40", "A_REL_BOT_K40"),
  paired("A_REL_TOP_K10", "SINGLE_BEST"),
  paired("A_REL_TOP_K40", "SINGLE_BEST"),
  paired("SS_A_REL_TOP", "SS_A_REL_BOT"),
  paired("SS_A_REL_TOP", "SS_SINGLE_BEST"),
  paired("LEAK_FULLSAMPLE", "A_REL_BOT"),
  paired("LEAK_FULLSAMPLE", "SINGLE_BEST"),
  paired("LEAK_ORACLE_OOS", "A_REL_BOT"),
  paired("LEAK_ORACLE_OOS", "SINGLE_BEST")))
say("--- paired NW(lag3) t (OOS active 차) ---"); print(PAIRS)

disc_a_t <- PAIRS[pair == "A_REL_TOP - A_REL_BOT", t_nw_lag3]
disc_b_t <- PAIRS[pair == "A_REL_TOP - SINGLE_BEST", t_nw_lag3]
disc_a <- is.finite(disc_a_t) && disc_a_t >= 2.0
disc_b <- is.finite(disc_b_t) && disc_b_t >= 2.0

# ── 3. 무작위 귀무 200 draw ─────────────────────────────────────────────────
sink(file.path(OUT, "canon_rand.log"))
t0 <- Sys.time()
rands <- sort(unique(RANDP$arm))
RR <- rbindlist(lapply(rands, function(a) {
  r <- tryCatch(canon(RANDP[arm == a, .(Date, Ticker, score)], a, dual = FALSE, ast = FALSE),
                error = function(e) NULL)
  if (is.null(r)) return(NULL)
  data.table(arm = a, port_t = r$portfolio_alpha_t_nw_lag3, ir = r$information_ratio,
             mean_active = r$mean_active_net, turnover_annual = r$turnover_annual,
             ret = list(as.data.table(r$period_returns)[, .(date, active = ret_net - benchmark_ret)]))
}))
sink()
say("random null %d draw / %.0fs", nrow(RR), as.numeric(difftime(Sys.time(), t0, units="secs")))
a_top_t <- SUM[arm == "A_REL_TOP", port_t]; a_bot_t <- SUM[arm == "A_REL_BOT", port_t]
say("귀무(무작위 K=20 composite) PORT_t: 평균 %.3f [%.3f, %.3f] | A_REL_TOP %.3f (백분위 %.1f%%) | A_REL_BOT %.3f (백분위 %.1f%%)",
    mean(RR$port_t, na.rm=TRUE), quantile(RR$port_t, .025, na.rm=TRUE), quantile(RR$port_t, .975, na.rm=TRUE),
    a_top_t, 100*mean(RR$port_t <= a_top_t, na.rm=TRUE), a_bot_t, 100*mean(RR$port_t <= a_bot_t, na.rm=TRUE))
# paired 차이의 귀무: A_REL_TOP - RAND_i 의 t 분포
at <- pr_of("A_REL_TOP")[, .(date, ax = active)]
RD <- rbindlist(lapply(seq_len(nrow(RR)), function(i) {
  m <- merge(at, RR$ret[[i]][, .(date, ay = active)], by = "date")
  data.table(arm = RR$arm[i], t_nw = nwt(m$ax - m$ay))
}))
say("A_REL_TOP vs 무작위 paired t: 중앙값 %.3f | >=2.0 비율 %.1f%% | 5%%~95%% [%.3f, %.3f]",
    median(RD$t_nw, na.rm=TRUE), 100*mean(RD$t_nw >= 2, na.rm=TRUE),
    quantile(RD$t_nw, .05, na.rm=TRUE), quantile(RD$t_nw, .95, na.rm=TRUE))

# ── 4. placebo + lag1 스트레스 ──────────────────────────────────────────────
sink(file.path(OUT, "canon_stress.log"))
plac <- canon(PLACP[, .(Date, Ticker, score)], "PLACEBO", dual = FALSE, ast = FALSE)
lag1_panel <- function(a) {
  P <- MAINP[arm == a, .(Date, Ticker, score)]
  dts <- sort(unique(P$Date)); mp <- data.table(Date = dts[-length(dts)], Date_new = dts[-1])
  merge(P, mp, by = "Date")[, .(Date = Date_new, Ticker, score)]
}
LAG1 <- rbindlist(lapply(c("A_REL_TOP","A_REL_BOT","SINGLE_BEST","POOL_EW"), function(a) {
  r <- canon(lag1_panel(a), paste0("LAG1_", a), dual = FALSE, ast = FALSE)
  data.table(arm = a, port_t_base = SUM[arm == a, port_t], port_t_lag1 = r$portfolio_alpha_t_nw_lag3,
             ia_base = SUM[arm == a, mean_active], ia_lag1 = r$mean_active_net)
}))
sink()
say("placebo(월내 셔플): PORT_t %.3f (기대 ~0) | mean_active %.5f", plac$portfolio_alpha_t_nw_lag3, plac$mean_active_net)
say("--- lag1 스트레스 ---"); print(LAG1)

# ── 5. parity : composite top-80 절단 무해 (random arm 가정 실증) ───────────
sink(file.path(OUT, "canon_parity.log"))
P1 <- rbindlist(lapply(c("A_REL_TOP","A_REL_BOT","POOL_EW"), function(a) {
  full <- MAINP[arm == a, .(Date, Ticker, score)]
  tr <- copy(full); setorder(tr, Date, -score); tr <- tr[, head(.SD, 80L), by = Date]
  x <- canon(full, paste0("P1FULL_", a), dual = FALSE, ast = FALSE)
  y <- canon(tr,   paste0("P1T80_", a),  dual = FALSE, ast = FALSE)
  m <- merge(as.data.table(x$period_returns)[, .(date, u = ret_net)],
             as.data.table(y$period_returns)[, .(date, v = ret_net)], by = "date")
  data.table(arm = a, n = nrow(m), max_abs_diff = max(abs(m$u - m$v)),
             t_full = x$portfolio_alpha_t_nw_lag3, t_top80 = y$portfolio_alpha_t_nw_lag3)
}))
# P2 fast-path parity
select_top <- function(sc, top_n = 25L) {
  S <- as.data.table(sc)[!is.na(score)]
  S <- merge(S, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
  S <- S[is.na(adv) | adv >= 2e8][, adv := NULL]
  setorder(S, Date, -score)
  S[, { n <- min(top_n, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
}
port_from_w <- function(W, cost_bps = 15) {
  WR <- merge(W, returns_dt, by = c("Date","Ticker"), all.x = TRUE); WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
  }
  port[, traded := traded[as.character(Date)]]; port[, ret_net := port_gross - traded * cost_bps/1e4]
  setorder(port, Date); port
}
P2 <- rbindlist(lapply(c("A_REL_TOP","SINGLE_BEST"), function(a) {
  fp <- port_from_w(select_top(MAINP[arm == a, .(Date, Ticker, score)]))
  cn <- as.data.table(RES[[a]]$period_returns)
  m <- merge(fp[, .(date = Date, mine = ret_net)], cn[, .(date, canon = ret_net)], by = "date")
  data.table(arm = a, n = nrow(m), max_abs_diff = max(abs(m$mine - m$canon)))
}))
sink()
say("--- P1' composite top-80 절단 parity ---"); print(P1)
say("--- P2' fast-path parity ---"); print(P2)

# ── 6. AX-001 v2 조건부 (BM<0 월) + subperiod ───────────────────────────────
cond_tab <- rbindlist(lapply(MAIN, function(a) {
  p <- pr_of(a); bad <- p[bm < 0]; good <- p[bm >= 0]
  data.table(arm = a, n_bad = nrow(bad), active_bad_ann = 12*mean(bad$active),
             active_good_ann = 12*mean(good$active), t_bad = nwt(bad$active),
             post2017_t = nwt(p[date >= as.Date("2017-01-01"), active]),
             pre2017_t  = nwt(p[date <  as.Date("2017-01-01"), active]))
}))
say("--- AX-001 v2 조건부 (BM<0 월 active) + subperiod ---"); print(cond_tab)

# ── 7. 선택 멤버 구성 분해 (WT-005 대조) ───────────────────────────────────
memb_tab <- function(a) {
  M <- MB$arms[[a]]$members
  x <- data.table(Factor_Name = unlist(M), step = rep(seq_along(M), lengths(M)))
  merge(x, LAB[, .(Factor_Name, family)], by = "Factor_Name", all.x = TRUE)
}
FAMSHARE <- rbindlist(lapply(c("A_REL_TOP","A_REL_BOT","A_PERP_TOP","A_ABS_TOP"), function(a) {
  m <- memb_tab(a); m[, .(arm = a, n = .N, share = .N / nrow(m)), by = family] }))
FW <- dcast(FAMSHARE, family ~ arm, value.var = "share", fill = 0)
w5 <- data.table(family = c("growth","investor_flow","quality","momentum","accrual","leverage",
                            "regime","consensus","value","crowding","risk","liquidity","defense"),
                 wt005_persist = c(.6667,.6667,.6587,.6548,.6212,.6111,.6071,.6061,.5882,.5556,.5385,.4872,.4654))
FW <- merge(FW, w5, by = "family", all = TRUE)
setorder(FW, -wt005_persist)
say("--- 선택 멤버 family 구성 (WT-005 지속률 대조) ---"); print(FW)
# 정합 검정: A_REL_TOP family share 와 WT-005 지속률의 순위상관
sp_top <- suppressWarnings(cor(FW$A_REL_TOP, FW$wt005_persist, method = "spearman", use = "complete.obs"))
sp_bot <- suppressWarnings(cor(FW$A_REL_BOT, FW$wt005_persist, method = "spearman", use = "complete.obs"))
say("family share vs WT-005 지속률 Spearman: A_REL_TOP %+.3f | A_REL_BOT %+.3f", sp_top, sp_bot)
# 멤버십 회전
turn <- rbindlist(lapply(c("A_REL_TOP","A_ABS_TOP","A_PERP_TOP"), function(a) {
  M <- MB$arms[[a]]$members
  j <- vapply(2:length(M), function(i) length(intersect(M[[i]], M[[i-1]])) / length(union(M[[i]], M[[i-1]])), 1.0)
  data.table(arm = a, jaccard_mean = mean(j), jaccard_min = min(j)) }))
say("--- 멤버십 step 간 자카드 ---"); print(turn)

# ── 8. 판별 판정 ────────────────────────────────────────────────────────────
say("=== 판별 (사전등록 문턱 t >= +2.0) ===")
say("(a) 지표가 판별하는가 [A_REL_TOP - A_REL_BOT]: %s — t=%+.3f (연 %+.2f%%p)",
    ifelse(disc_a, "PASS", "FAIL"), disc_a_t, 100*PAIRS[pair=="A_REL_TOP - A_REL_BOT", mean_diff_ann])
say("(b) ★구성이 단일 최강을 이기는가 [A_REL_TOP - SINGLE_BEST]: %s — t=%+.3f (연 %+.2f%%p)",
    ifelse(disc_b, "PASS", "FAIL"), disc_b_t, 100*PAIRS[pair=="A_REL_TOP - SINGLE_BEST", mean_diff_ann])
inj_fired <- (PAIRS[pair=="LEAK_ORACLE_OOS - A_REL_BOT", t_nw_lag3] > disc_a_t + 0.5) ||
             (PAIRS[pair=="LEAK_FULLSAMPLE - A_REL_BOT", t_nw_lag3] > disc_a_t + 0.5)
say("위반 주입: %s (LEAK_FULLSAMPLE vs BOT t=%+.3f / LEAK_ORACLE vs BOT t=%+.3f / clean t=%+.3f)",
    ifelse(inj_fired, "FIRED — 가드 실효", "NOT FIRED — 검사력 부족 의심"),
    PAIRS[pair=="LEAK_FULLSAMPLE - A_REL_BOT", t_nw_lag3],
    PAIRS[pair=="LEAK_ORACLE_OOS - A_REL_BOT", t_nw_lag3], disc_a_t)

saveRDS(list(summary = SUM, pairs = PAIRS, rand = RR[, .(arm, port_t, ir, mean_active, turnover_annual)],
             rand_paired = RD, placebo = list(port_t = plac$portfolio_alpha_t_nw_lag3,
             mean_active = plac$mean_active_net), lag1 = LAG1, parity = list(p1 = P1, p2 = P2),
             cond = cond_tab, fam = FW, fam_spearman = c(top = sp_top, bot = sp_bot),
             memb_turnover = turn, disc = list(a = disc_a, b = disc_b, a_t = disc_a_t, b_t = disc_b_t,
             injection_fired = inj_fired),
             res_period_returns = lapply(RES, function(r) as.data.table(r$period_returns)),
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "arm_results.rds"))
say("저장 — arm_results.rds")
