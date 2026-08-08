# =============================================================================
# np_a_bench_decomposition.R — FQ-141 NP-A: capw−EW 격차의 벤치-측 분해
#
# 질문: WT-007 의 arm 별 (port_t_capw − port_t_ew_universe) 격차가
#       ① 벤치마크 자체의 수익차(포트폴리오 무관, 회수 불가) 인가
#       ② arm 의존(포트폴리오 구성에 반응, 회수 여지 있음) 인가
#
# 분석 핵심(사전 서술 — 측정 전 고정):
#   active_capw_t = ret_net_t − BM_capw_t ,  active_ew_t = ret_net_t − BM_ew_t
#   ⇒ active_capw_t − active_ew_t = BM_ew_t − BM_capw_t  ≡ −d_t   (ret_net 소거)
#   즉 두 basis 의 active *평균차* 는 arm 과 무관한 상수여야 한다(EW 벤치 공유 시).
#   PORT_t 격차가 arm 마다 다른 것은 분자(평균)가 아니라 **분모(active 변동성)** 때문.
#   H0(벤치-측): 위 항등식이 성립하고 EW 벤치가 arm 간 사실상 동일.
#   H1(arm-측) : EW 벤치가 arm 마다 유의하게 달라 격차에 포트폴리오 정보가 실림.
#
# 하네스: WT-D20260803_007 analyze_arms.R 과 동일 vintage(RAWDATA + build_monthly_forward_returns)
# 자체합성 금지: 수익 시계열 비교는 계약 함수 build_benchmark_compare 경유.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")
W007 <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[np-a] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/ramp/factor_validation.R")

main <- function() {
  ## ── 1. 하네스 재구성 (WT-007 동일 vintage) ────────────────────────────────
  RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
          col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
  RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
  MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
  RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
  META    <- readRDS(file.path(SRC5, "pool_meta.rds")); sig_all <- META$sig_all
  fwd     <- build_monthly_forward_returns(RAWME, sig_all)
  returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
  bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
  say("하네스 재구성: returns %d행 · bench %d월", nrow(returns_dt), nrow(bench_dt))

  ## ── 2. arm 별 EW 벤치 재구성 (canonical_screen_bt L96 정의 그대로) ────────
  ##    univ_prefilter = unique(scores[, .(Date,Ticker)]) → EW = mean(Ret_1m)
  MAINP <- as.data.table(read_parquet(file.path(W007, "composite_main.parquet")))
  MAINP[, Date := as.Date(Date)]
  arms <- sort(unique(MAINP$arm))
  say("main arm %d개: %s", length(arms), paste(arms, collapse = ", "))

  ew_of <- function(a) {
    u <- unique(MAINP[arm == a & !is.na(score), .(Date, Ticker)])
    m <- merge(u, returns_dt, by = c("Date","Ticker"))
    m[, .(ew_bench_ret = mean(Ret_1m), n_names = .N), by = Date][order(Date)]
  }
  EW <- lapply(arms, ew_of); names(EW) <- arms

  ## ── 3. arm 간 EW 벤치 동일성 (H0 vs H1 의 판별축) ─────────────────────────
  wide <- Reduce(function(x, y) merge(x, y, by = "Date"),
                 lapply(arms, function(a) EW[[a]][, .(Date, ew = ew_bench_ret)][
                   , setnames(.SD, "ew", a), .SDcols = c("Date","ew")][, .SD, .SDcols = c("Date", a)]))
  M <- as.matrix(wide[, ..arms])
  rng <- apply(M, 1, function(r) max(r) - min(r))
  say("EW 벤치 arm 간 월별 max-min 스프레드: 중앙값 %.5f · 평균 %.5f · 최대 %.5f",
      median(rng), mean(rng), max(rng))
  cm <- cor(M)
  say("EW 벤치 arm 간 상관 최소 = %.6f (1.0 에 가까울수록 '사실상 동일 벤치')", min(cm))

  ## ── 4. 벤치 차 d_t = BM_capw − BM_ew (arm 별) + 계약 경유 t 통계 ──────────
  win_lo <- as.Date("2012-08-31"); win_hi <- as.Date("2026-06-30")   # WT-007 OOS 창
  rows <- list()
  for (a in arms) {
    d <- merge(bench_dt, EW[[a]][, .(Date, ew_bench_ret)], by = "Date")
    d <- d[Date >= win_lo & Date <= win_hi]
    ## 계약 경유: cap-w 벤치를 '포트폴리오', EW 벤치를 '벤치'로 두어 차이의 alpha/t 산출
    prt <- data.table(date = d$Date, ret_net = d$BM_Ret, frequency = "monthly")
    bmt <- data.table(date = d$Date, benchmark_ret = d$ew_bench_ret,
                      benchmark_id = "EW_universe_prefilter")
    bc <- build_benchmark_compare(prt, bmt, run_id = "FQ141_NPA",
                                  strategy_id = paste0("BENCHDIFF_", a),
                                  annualization_factor = 12)
    g <- function(nm) { v <- bc[metric_name == nm, active_value]
                        if (length(v) == 0) NA_real_ else as.numeric(v[1]) }
    rows[[a]] <- data.table(arm = a, n_months = nrow(d),
      d_alpha_ann = g("Alpha_Annualized"), d_t_nw3 = g("Portfolio_Alpha_t_NW_lag3"),
      d_pval = g("Portfolio_Alpha_t_pvalue"), d_ir = g("Information_Ratio"),
      d_mean_monthly = mean(d$BM_Ret - d$ew_bench_ret),
      capw_mean = mean(d$BM_Ret), ew_mean = mean(d$ew_bench_ret))
  }
  D <- rbindlist(rows); setorder(D, -d_alpha_ann)
  say("--- 벤치 차 d = cap-w BM − EW BM (metric_type=canonical_screen_diag) ---")
  print(D)

  ## ── 5. 항등식 검증: active 평균차 == −d (arm 무관 상수인가) ───────────────
  say("--- 항등식 점검: 두 basis 의 active 평균차는 ret_net 이 소거되어 −d 와 같아야 ---")
  say("d_alpha_ann 의 arm 간 sd = %.6f (0 에 가까우면 벤치-측 상수 = H0)", sd(D$d_alpha_ann))
  say("d_alpha_ann 범위 = [%.4f, %.4f]", min(D$d_alpha_ann), max(D$d_alpha_ann))

  saveRDS(list(D = D, ew_spread = rng, ew_cor = cm, arms = arms),
          file.path(OUT, "np_a_results.rds"))
  fwrite(D, file.path(OUT, "np_a_bench_diff.csv"))
  say("저장: np_a_results.rds · np_a_bench_diff.csv")
  invisible(0L)
}

main()
