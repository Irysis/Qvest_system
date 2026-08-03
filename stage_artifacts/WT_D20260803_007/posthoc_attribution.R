# =============================================================================
# posthoc_attribution.R — WT-D20260803_007 (FQ-135) 사후 기전 귀속 (★사전등록 아님)
#
#   ★경계 선언: 판별식 (a)/(b) 는 analyze_arms.R 에서 이미 산출·기록되었고(FAIL/FAIL),
#     본 스크립트는 그 판정을 **바꾸지 않는다**. 목적은 단 하나 —
#     "A_REL_TOP 이 무작위 귀무 대비 99.0 백분위인데 level-직교 arm(A_PERP_TOP)은
#      -1.068 이다. 그렇다면 남은 우위는 level 인가?" 를 실측으로 귀속한다.
#     사후 arm 은 1개(LEVEL_TOP_K20)만 추가한다 — 판별 문턱에 재적용하지 않는다.
#
#   arm: LEVEL_TOP_K20 = IS 전기간 level PORT_t 상위 20 (walk-forward, IS-only)
#        = SINGLE_BEST(K=1, level) 의 K=20 확장 ⇒ A_REL_TOP 과의 차 = robustness 순증분
# 실행: Rscript stage_artifacts/WT_D20260803_007/posthoc_attribution.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt007P] ", fmt, "\n"), ...))

MB <- readRDS(file.path(OUT, "memberships.rds"))
AR <- readRDS(file.path(OUT, "arm_results.rds"))
POOL <- MB$pool; DATES <- MB$dates; steps <- MB$steps; K <- MB$consts$K_PRIM
MET <- MB$met
pick <- function(v, K, top = TRUE) { v <- v[is.finite(v)]
  names(v)[order(v, names(v), decreasing = top)[seq_len(min(K, length(v)))]] }
memb <- lapply(MET, function(m) pick(m$level, K, TRUE))
say("LEVEL_TOP_K20 step1 멤버: %s", paste(head(memb[[1]], 6), collapse = ", "))
say("A_REL_TOP 과 멤버 겹침(step별): %s",
    paste(vapply(seq_along(memb), function(i)
      sprintf("%d/%d", length(intersect(memb[[i]], MB$arms$A_REL_TOP$members[[i]])), K), character(1)),
      collapse = " "))

# ── 월 루프 (OOS 월만) ──────────────────────────────────────────────────────
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date); RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]; setkey(UNIV, Date, Ticker)
step_of <- rep(NA_integer_, length(DATES))
for (i in seq_along(steps)) step_of[steps[[i]]$oos] <- i
CM <- MB$consts$COV_MIN_MEMBER
sink(file.path(OUT, "posthoc_connector.log"))
outl <- vector("list", length(DATES))
for (i in seq_along(DATES)) {
  if (is.na(step_of[i])) next
  d <- DATES[i]; tk <- UNIV[.(d), Ticker, nomatch = 0L]; if (!length(tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) next
  mem <- memb[[step_of[i]]]
  S <- fdt[Ticker %in% tk & Factor_Name %in% mem & is.finite(Z_Score_Aligned),
           .(Ticker, Factor_Name, z = Z_Score_Aligned)]; rm(fdt)
  if (!nrow(S)) next
  agg <- S[, .(cnt = .N, s = sum(z)), by = Ticker]
  nm <- uniqueN(S$Factor_Name)
  agg <- agg[cnt >= ceiling(CM * nm)]
  if (!nrow(agg)) next
  outl[[i]] <- data.table(Date = d, Ticker = agg$Ticker, score = agg$s / agg$cnt)
  if (i %% 24L == 0L) gc(FALSE)
}
sink()
LP <- rbindlist(Filter(Negate(is.null), outl))
say("LEVEL_TOP_K20 패널: %d행 / %d월", nrow(LP), uniqueN(LP$Date))

# ── canonical + paired ──────────────────────────────────────────────────────
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/ramp/factor_validation.R")
nwt <- function(x, lag = 3L) { xv <- x[is.finite(x)]; if (length(xv) < 20L) return(NA_real_); .nw_t_mean(xv, lag = lag) }
META <- readRDS(file.path(SRC5, "pool_meta.rds")); sig_all <- META$sig_all
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt <- RAWME[Date %in% sig_all & (K200 == TRUE | KQ150 == TRUE) & !is.na(Size), .(Date, Ticker, Size)]
sink(file.path(OUT, "posthoc_canon.log"))
r <- canonical_screen_bt(LP, returns_dt, bench_dt, top_n = 25L, cost_bps_oneway = 15,
       liq_dt = liq_dt, liq_min = 2e8, run_id = "WT-D20260803_007",
       strategy_id = "WT_D20260803_007_LEVEL_TOP_K20", diag_dual_basis = TRUE, size_dt = size_dt)
sink()
pr <- as.data.table(r$period_returns)[, .(date, active = ret_net - benchmark_ret, bm = benchmark_ret)]
say("LEVEL_TOP_K20: PORT_t %.3f | EW-basis %.3f | IR %.3f | TO %.2f | mean_active %.5f",
    r$portfolio_alpha_t_nw_lag3, r$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    r$information_ratio, r$turnover_annual, r$mean_active_net)

PRB <- AR$res_period_returns
pa <- function(nm) as.data.table(PRB[[nm]])[, .(date, active = ret_net - benchmark_ret)]
cmp <- function(x, xn, y, yn) { m <- merge(x[, .(date, ax = active)], y[, .(date, ay = active)], by = "date")
  d <- m$ax - m$ay
  data.table(pair = sprintf("%s - %s", xn, yn), n = nrow(m), mean_diff_ann = 12*mean(d),
             t_nw_lag3 = nwt(d), win_rate = mean(d > 0)) }
PP <- rbindlist(list(
  cmp(pa("A_REL_TOP"), "A_REL_TOP", pr, "LEVEL_TOP_K20"),     # ★ robustness 순증분
  cmp(pr, "LEVEL_TOP_K20", pa("A_REL_BOT"), "A_REL_BOT"),
  cmp(pr, "LEVEL_TOP_K20", pa("SINGLE_BEST"), "SINGLE_BEST"),
  cmp(pr, "LEVEL_TOP_K20", pa("POOL_EW"), "POOL_EW")))
say("--- 사후 귀속 paired NW(lag3) t ---"); print(PP)

# 무작위 귀무 대비 백분위
RND <- AR$rand
say("LEVEL_TOP_K20 PORT_t %.3f → 무작위 200 draw 내 백분위 %.1f%% (A_REL_TOP 은 99.0%%)",
    r$portfolio_alpha_t_nw_lag3, 100*mean(RND$port_t <= r$portfolio_alpha_t_nw_lag3, na.rm = TRUE))
say("AX-001 조건부: BM<0 월 active 연 %+.2f%%p (t %.3f) | post2017 t %.3f",
    100*12*mean(pr[bm < 0, active]), nwt(pr[bm < 0, active]),
    nwt(pr[date >= as.Date("2017-01-01"), active]))

saveRDS(list(members = memb, port_t = r$portfolio_alpha_t_nw_lag3,
             ew_port_t = r$diag_ew_universe$portfolio_alpha_t_nw_lag3,
             ir = r$information_ratio, turnover = r$turnover_annual,
             mean_active = r$mean_active_net, period_returns = pr, pairs = PP,
             rand_pct = 100*mean(RND$port_t <= r$portfolio_alpha_t_nw_lag3, na.rm = TRUE),
             posthoc = TRUE, not_a_discriminant = TRUE,
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "posthoc_results.rds"))
say("저장 — posthoc_results.rds")
