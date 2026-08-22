# WT-D20260822_005 · alpha-research 구간 · ablation + canonical screen + dual-basis + KQ150 sensitivity
# PIT: 신호=sig_date(월말) Z_Score_Aligned (load_month_factors 경유, C15), 수익=forward 1M (signal_anchor off=0)
# 결합규칙 = Z_Score_Aligned EW 고정 (적합계수 0). canonical_screen_bt() 경유 실측 (자체합성 금지).
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })

root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = root)
source(file.path(root, "02_Infrastructure/config.R"))
source(file.path(root, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(root, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(root, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(root, "02_Infrastructure/ramp/factor_validation.R"))  # build_monthly_forward_returns

`%||%` <- function(a,b) if (is.null(a) || length(a)==0 || (length(a)==1 && is.na(a))) b else a
scratch <- file.path(root, "qepm/mailbox/worktask/WT-D20260822_005/scratch")
stage   <- file.path(root, "stage_artifacts/WT-D20260822_005")
dir.create(scratch, showWarnings = FALSE, recursive = TRUE)
dir.create(stage,   showWarnings = FALSE, recursive = TRUE)

# ── sig_dates: 월말 거래일 그리드 (RAWDATA 기준) ──────────────────────────────
cat("[1] RAWDATA 로드 + 월말 sig_date 그리드\n")
raw <- as.data.table(read_parquet(RAWDATA_CACHE,
        col_select = c("Date","Ticker","K200","KQ150","Close","Vol","Size")))
raw[, Date := as.Date(Date)]
udates <- sort(unique(raw$Date))
# 각 캘린더월의 마지막 거래일
me <- data.table(Date = udates)[, ym := format(Date, "%Y-%m")][, .(Date = max(Date)), by = ym]
sig_dates <- sort(me$Date)
# 측정 시작: 2005-01 (헌법 mandate 2005~). C4/데이터한계상 momentum·quality 안정.
sig_dates <- sig_dates[sig_dates >= as.Date("2004-12-01") & sig_dates <= as.Date("2026-07-31")]
cat("  sig_date n=", length(sig_dates), " range=", as.character(min(sig_dates)), "→", as.character(max(sig_dates)), "\n")

# ── forward returns + bench(proxy) + liquidity (adv20_t1) ────────────────────
cat("[2] build_monthly_forward_returns (adv20_t1 자동 계산)\n")
bmf <- build_monthly_forward_returns(raw, sig_dates, liq_daily = NULL)
returns_dt <- bmf$returns_dt      # Date(신호월말), Ticker, Ret_1m (forward)
liq_dt     <- bmf$liq_dt          # Date, Ticker, adv (20d avg t-1)
cat("  returns rows=", nrow(returns_dt), " liq_ruler=", bmf$liq_ruler, "\n")

# ── 공식 벤치(cap-w HARD basis) = IKS200 BM_Ret. build_monthly_forward_returns 의
#    Size-weighted proxy 대신 공식 KOSPI200 TR 사용 (measurement-graduation §6/§7, IKS200).
#    RAWDATA per-row BM_Ret 은 종목무관 동일값 → 월말 1행으로 축약. forward 정렬:
#    신호월 t 의 Date 에 t→t+1 forward BM_Ret 을 붙인다 (returns_dt 와 동일 anchor).
cat("[3] 공식 벤치(IKS200) forward 정렬\n")
bmraw <- as.data.table(read_parquet(RAWDATA_CACHE, col_select = c("Date","BM_Ret")))
bmraw[, Date := as.Date(Date)]
bm_daily <- unique(bmraw[!is.na(BM_Ret)], by = "Date")   # 월내 daily BM_Ret
# 월말→월말 forward BM 수익 = 신호월 다음달의 월간 복리수익.
# 여기서는 build_bench 와 동일 방식: 각 종목 Close 로부터 만든 returns_dt 의 앵커와 맞추기 위해
# 벤치도 "신호월말 → 다음 신호월말" 총수익으로 구성 (BM_Close 사용).
bmc <- as.data.table(read_parquet(BM_CACHE))   # Date, BM_Close, BM_Ret (일간)
bmc[, Date := as.Date(Date)]
asof_bmclose <- function(d) { s <- bmc[Date <= d]; if (!nrow(s)) return(NA_real_); s[Date == max(Date), BM_Close][1] }
bench_list <- list()
for (i in seq_len(length(sig_dates) - 1L)) {
  d0 <- sig_dates[i]; d1 <- sig_dates[i + 1L]
  c0 <- asof_bmclose(d0); c1 <- asof_bmclose(d1)
  if (is.na(c0) || is.na(c1) || c0 <= 0) next
  bench_list[[length(bench_list) + 1L]] <- data.table(Date = d0, BM_Ret = c1 / c0 - 1)
}
bench_dt <- rbindlist(bench_list)
cat("  bench rows=", nrow(bench_dt), " (IKS200 KOSPI200 TR forward)\n")

# ── 팩터 로드 (전 sig_date, 필요 팩터만) — load_month_factors 경유 (C15) ──────
cat("[4] load_month_factors (M08/M07/M01/Q01 + C03 대체[C17 dead])\n")
# C17_OP_Revision = 전기간 0 커버리지(dead). intent(이익수정) 보존 위해 C03_EPS_Chg_3m 대체.
FAC <- c("M08_Residual_Mom","M07_IndMom","M01_Mom_12_1","Q01_GPA","C03_EPS_Chg_3m")
uni_keys <- unique(raw[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])  # K200∪KQ150 제한
setkey(uni_keys, Date, Ticker)

load_scores <- function(sig_date) {
  fm <- tryCatch(load_month_factors(sig_date, factor_names = FAC, coverage_min = 0.03),
                 error = function(e) NULL)
  if (is.null(fm) || !nrow(fm)) return(NULL)
  # wide: Ticker × factor Z_Score_Aligned
  w <- dcast(fm, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
             fun.aggregate = function(x) mean(x, na.rm = TRUE))
  w[, Date := as.Date(sig_date)]
  w
}
score_panel <- rbindlist(lapply(sig_dates, load_scores), fill = TRUE)
cat("  score_panel rows=", nrow(score_panel), " cols=", paste(setdiff(names(score_panel), c("Ticker","Date")), collapse=","), "\n")

# K200∪KQ150 제한 조인 (유니버스 선-제한 = 호출자 책임, CF-03)
score_panel <- merge(score_panel, uni_keys, by = c("Date","Ticker"))
cat("  after univ restrict rows=", nrow(score_panel), "\n")

# ── 결합규칙: Z_Score_Aligned EW (동일가중 합, 적합계수 0). 결측 팩터는 mean으로 대체하지
#    않고 available 팩터 평균 (rowMeans na.rm) — combo 별로 컬럼 집합만 다름 ────
build_combo_scores <- function(cols) {
  present <- intersect(cols, names(score_panel))
  if (!length(present)) return(NULL)
  M <- as.matrix(score_panel[, ..present])
  s <- rowMeans(M, na.rm = TRUE)   # EW average of available aligned-Z
  n_ok <- rowSums(!is.na(M))
  dt <- data.table(Date = score_panel$Date, Ticker = score_panel$Ticker, score = s, n_fac = n_ok)
  dt <- dt[n_ok >= 1 & is.finite(score)]   # 최소 1팩터 존재
  dt[, .(Date, Ticker, score)]
}

# ── 측정 wrapper ─────────────────────────────────────────────────────────────
size_panel <- unique(raw[(K200==TRUE|KQ150==TRUE), .(Date, Ticker, Size)])
measure_combo <- function(label, cols, date_from, date_to, top_n = 25L, diag = TRUE) {
  sc <- build_combo_scores(cols)
  if (is.null(sc)) return(list(label = label, error = "no scores"))
  sc <- sc[Date >= as.Date(date_from) & Date <= as.Date(date_to)]
  rr <- returns_dt[Date >= as.Date(date_from) & Date <= as.Date(date_to)]
  bb <- bench_dt[Date >= as.Date(date_from) & Date <= as.Date(date_to)]
  ll <- liq_dt[Date >= as.Date(date_from) & Date <= as.Date(date_to)]
  data.table::setattr(ll, "liq_ruler", attr(liq_dt, "liq_ruler", exact = TRUE))
  data.table::setattr(ll, "liq_ruler_source", attr(liq_dt, "liq_ruler_source", exact = TRUE))
  ss <- size_panel[Date >= as.Date(date_from) & Date <= as.Date(date_to)]
  res <- tryCatch(
    canonical_screen_bt(sc, rr, bb, top_n = top_n, cost_bps_oneway = 15,
                        liq_dt = ll, liq_min = 2e8,
                        run_id = paste0("WT005_", label), strategy_id = label,
                        periods_per_year = 12L, diag_dual_basis = diag, size_dt = ss),
    error = function(e) list(error = conditionMessage(e)))
  res
}

pick <- function(r) {
  if (!is.null(r$error)) return(list(error = r$error))
  d <- r$diag_ew_universe
  list(
    n_months = r$n_months, top_n = r$top_n,
    port_t = r$portfolio_alpha_t_nw_lag3,
    p_value = r$portfolio_alpha_t_pvalue,
    net_ir = r$information_ratio,
    alpha_ann = r$alpha_annualized,
    net_sr = r$net_sr,
    mean_active_net = r$mean_active_net,
    turnover_ann = r$turnover_annual,
    sel_cov = r$selected_ret_coverage,
    liq_ruler = r$liq_ruler,
    diag_ew_port_t = if (is.list(d)) d$portfolio_alpha_t_nw_lag3 else NA_real_,
    diag_ew_ir = if (is.list(d)) d$information_ratio else NA_real_,
    diag_ew_post2017_t = if (is.list(d)) d$post2017_t_nw_lag3 else NA_real_,
    diag_ew_oos_approx = if (is.list(d)) d$oos_retention_approx else NA_real_
  )
}

# ============================================================================
# ① ABLATION (IS-only 선택 — 전기간을 IS 로 취급하지 않도록 IS = 2005-01~2018-12,
#    holdout(OOS) = 2019-01~2026-07 로 anchored. chain 자격 ②: 변형 선택은 IS 에서만)
# ============================================================================
IS_FROM <- "2004-12-01"; IS_TO <- "2018-12-31"
FULL_FROM <- "2004-12-01"; FULL_TO <- "2026-07-31"
CLEAN_FROM <- "2015-07-01"    # KQ150 백필 clean window (FQ-241)

combos <- list(
  A_M08_Q01        = c("M08_Residual_Mom","Q01_GPA"),
  B_M08_Q01_C03    = c("M08_Residual_Mom","Q01_GPA","C03_EPS_Chg_3m"),
  C_M07_Q01        = c("M07_IndMom","Q01_GPA"),
  D_M01_Q01        = c("M01_Mom_12_1","Q01_GPA"),
  E_M08_M07_Q01    = c("M08_Residual_Mom","M07_IndMom","Q01_GPA"),
  F_M08_only       = c("M08_Residual_Mom"),
  G_Q01_only       = c("Q01_GPA"),
  H_M08_M01_Q01    = c("M08_Residual_Mom","M01_Mom_12_1","Q01_GPA")  # redundancy 진단
)

cat("\n[5] ABLATION — IS-only (", IS_FROM, "→", IS_TO, ")\n")
abl_is <- list()
for (nm in names(combos)) {
  r <- measure_combo(nm, combos[[nm]], IS_FROM, IS_TO, diag = FALSE)
  abl_is[[nm]] <- pick(r)
  cat(sprintf("  %-16s port_t=%6.3f net_ir=%6.3f net_sr=%6.3f TO=%5.0f%% n=%d\n",
      nm, abl_is[[nm]]$port_t %||% NA, abl_is[[nm]]$net_ir %||% NA,
      abl_is[[nm]]$net_sr %||% NA, (abl_is[[nm]]$turnover_ann %||% NA)*100, abl_is[[nm]]$n_months %||% 0))
}

saveRDS(list(abl_is = abl_is, combos = combos, IS = c(IS_FROM, IS_TO)),
        file.path(scratch, "ablation_is.rds"))
write_json(abl_is, file.path(scratch, "ablation_is.json"), auto_unbox = TRUE, na = "null", pretty = TRUE)
cat("[5] ablation_is 저장 완료\n")
