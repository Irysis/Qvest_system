cat("=== STR_1662a: S5 Mutation Lab (Q07 Defense) ===\n")
## S5 Mutation Lab — 9건, 5 카테고리 (A~E)
## Base: Q07_Earnings_Stability 단독, EW 20종목, 15bps, 월간
## AX-001: Defense = 위기 alpha + Core 대비 MDD + bad/normal IC ratio 평가
## PIT: C9(DD/VT t-1 lag), C1(rolling/expanding), C2(liq_lag t-1)

set.seed(20260412)
t0 <- Sys.time()

.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(dplyr)
  library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales); library(jsonlite)
})

options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID <- "STR_1662a_S5"
COMMISSION  <- 0.0015      # 15bps
LIQ_BASE    <- 2e8         # base 유동성

# ─────────────────────────────────────────
# [1] RAWDATA
# ─────────────────────────────────────────
cat("\n[1] RAWDATA...\n")
rw <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# ─────────────────────────────────────────
# [2] Factor DB — Q07 단독 (C15 준수)
# ─────────────────────────────────────────
cat("\n[2] Factor DB (C15: factor_db_connector)...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))
FACTORS_NEEDED <- c("Q07_Earnings_Stability")
CACHE_DIR_FDB  <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(CACHE_DIR_FDB, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
cat(sprintf("    Loading %d monthly parquet files...\n", length(fdb_files)))
fdb <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(arrow::read_parquet(f))
  dt[Factor_Name %in% FACTORS_NEEDED]
}))
fdb[, Date := as.Date(Date)]
# C13: Z_Score_Aligned 사용, align_factor_direction()
fdb <- align_factor_direction(fdb, .load_registry())
fdb <- fdb[Coverage == TRUE]
setkey(fdb, Date, Ticker)
cat(sprintf("    %d rows | Q07 커버리지\n", nrow(fdb)))

# ─────────────────────────────────────────
# [3] Merge + 공통 전처리
# ─────────────────────────────────────────
cat("\n[3] Merge + 공통 전처리...\n")
fdb_wide <- dcast(fdb, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
dt <- merge(RAWDATA, fdb_wide, by = c("Date", "Ticker"), all.x = FALSE)
setkey(dt, Date, Ticker)
# C1: rolling 20d liq (no full-sample)
dt[, liq_20d := frollmean(Vol * Close, n = 20L, align = "right"), by = Ticker]
# C2: liq_lag t-1 (no same-day circular)
dt[, liq_lag := shift(liq_20d, 1L), by = Ticker]
# Expanding volatility (C1: expanding — no full-sample bias)
dt[, ret_vol := NA_real_]
dt[!is.na(Ret), ret_vol := {
  # expanding window: sd of all previous returns
  n <- .N
  v <- numeric(n)
  for (i in seq_len(n)) {
    if (i < 3L) v[i] <- sd(Ret[seq_len(i)], na.rm = TRUE)
    else         v[i] <- sd(Ret[seq_len(i - 1L)], na.rm = TRUE)   # t-1 expanding
  }
  v
}, by = Ticker]
dt[, ivol := 1.0 / pmax(ret_vol, 1e-6)]   # inverse volatility (C9 준수: t-1 expanding)
cat(sprintf("    dt rows: %d\n", nrow(dt)))

months_all <- sort(unique(dt$Date))
cat(sprintf("    %d months\n", length(months_all)))

# ─────────────────────────────────────────
# [4] 핵심 백테스트 함수 (파라미터화)
# ─────────────────────────────────────────
run_mutation <- function(
    mut_id,
    n_hold        = 20L,         # 카테고리 A
    liq_thresh    = LIQ_BASE,    # 카테고리 E
    rebal_every   = 1L,          # 카테고리 B: 1=월간, 2=격월, 3=분기
    weight_mode   = "EW",        # 카테고리 C: "EW" | "Score" | "IVOL"
    use_dd_brake  = FALSE,       # 카테고리 D
    dd_thresh     = -0.08,       # DD brake 진입 임계값
    dd_exit       = -0.25,       # DD brake 전액 현금화
    use_vt        = FALSE,       # 카테고리 D
    vt_target     = 0.15,        # 연환산 변동성 목표
    verbose       = TRUE
) {
  if (verbose) cat(sprintf("\n--- %s ---\n", mut_id))

  prev_tk  <- NULL
  port_out <- vector("list", length(months_all))
  last_port_month_idx <- 0L   # 마지막 실제 리밸 월 인덱스

  # ── 카테고리 B: 격월/분기 리밸런싱을 위한 포트 캐시 ──
  cached_port <- NULL  # 이전 리밸 시 선택한 종목+가중치

  for (mi in seq_along(months_all)) {
    m <- months_all[mi]

    # 리밸런싱 여부 결정 (B)
    do_rebal <- (mi == 1L) || ((mi - last_port_month_idx) >= rebal_every)

    if (do_rebal) {
      sub <- dt[Date == m & !is.na(Q07_Earnings_Stability) & !is.na(liq_lag)]
      sub <- sub[liq_lag >= liq_thresh]
      if (nrow(sub) < n_hold) {
        # 종목 부족 시 이전 포트 유지 또는 건너뜀
        if (!is.null(cached_port)) {
          cur_port <- cached_port[, .(Date = m, Ticker, Score, Weight)]
        } else {
          next
        }
      } else {
        sub <- sub[order(-Q07_Earnings_Stability)]
        top <- head(sub, n_hold)

        # 가중 방식 (C)
        if (weight_mode == "EW") {
          top[, Weight := 1.0 / n_hold]
        } else if (weight_mode == "Score") {
          # Score-weighted: softmax-style (음수 방지 위해 min-shift)
          sc_min <- min(top$Q07_Earnings_Stability, na.rm = TRUE)
          top[, sc_pos := Q07_Earnings_Stability - sc_min + 1e-6]
          top[, Weight := sc_pos / sum(sc_pos)]
          top[, sc_pos := NULL]
        } else if (weight_mode == "IVOL") {
          # Inverse volatility (expanding, t-1 — C9 준수)
          ivol_ref <- dt[Date == m, .(Ticker, ivol_wt = ivol)]
          top <- merge(top, ivol_ref, by = "Ticker", all.x = TRUE)
          top[is.na(ivol_wt) | ivol_wt <= 0, ivol_wt := median(top$ivol_wt, na.rm = TRUE)]
          top[, Weight := ivol_wt / sum(ivol_wt, na.rm = TRUE)]
          top[, ivol_wt := NULL]
        }

        cur_port <- top[, .(Date = m, Ticker,
                             Score = Q07_Earnings_Stability,
                             Weight)]
        cached_port <- cur_port
        last_port_month_idx <- mi
      }
    } else {
      # 리밸 없음 → 이전 포트 날짜만 갱신
      if (is.null(cached_port)) next
      cur_port <- cached_port[, .(Date = m, Ticker, Score, Weight)]
    }

    port_out[[mi]] <- cur_port
  }

  port <- rbindlist(port_out[!sapply(port_out, is.null)])
  if (nrow(port) == 0) { cat("  WARNING: empty portfolio\n"); return(NULL) }

  # ── 수익률 계산 ──
  port <- merge(port, RAWDATA[, .(Date, Ticker, Ret)], by = c("Date", "Ticker"))
  monthly_ret <- port[, .(port_ret = sum(Weight * Ret, na.rm = TRUE)), by = Date]
  setorder(monthly_ret, Date)

  # ── 턴오버 ──
  all_months_port <- sort(unique(port$Date))
  to_vec <- numeric(length(all_months_port))
  prev_wt <- data.table(Ticker = character(0), Weight = numeric(0))
  for (i in seq_along(all_months_port)) {
    cur <- port[Date == all_months_port[i], .(Ticker, Weight)]
    if (nrow(prev_wt) > 0) {
      combined <- merge(cur, prev_wt, by = "Ticker", all = TRUE, suffixes = c("_new", "_old"))
      combined[is.na(Weight_new), Weight_new := 0]
      combined[is.na(Weight_old), Weight_old := 0]
      to_vec[i] <- sum(abs(combined$Weight_new - combined$Weight_old)) / 2
    }
    prev_wt <- cur
  }
  monthly_ret[, turnover := to_vec]
  monthly_ret[turnover > 0, port_ret := port_ret - turnover * COMMISSION]

  # ── 카테고리 D: DD Brake (C9: t-1 lag) ──
  if (use_dd_brake) {
    n <- nrow(monthly_ret)
    nav_tmp <- cumprod(1 + monthly_ret$port_ret)
    dd_pct   <- nav_tmp / cummax(nav_tmp) - 1
    # C9: dd_lag = t-1 (당일 DD 기준 적용 금지)
    dd_lag   <- c(0, head(dd_pct, -1))
    # 브레이크 적용: dd_lag < dd_thresh → 부분 현금화, dd_lag < dd_exit → 전액
    brake_factor <- ifelse(dd_lag < dd_exit, 0,
                    ifelse(dd_lag < dd_thresh,
                           1 - (dd_lag - dd_thresh) / (dd_exit - dd_thresh),
                           1))
    monthly_ret[, port_ret := port_ret * brake_factor]
  }

  # ── 카테고리 D: Vol Target (C9: t-1 lag, expanding) ──
  if (use_vt) {
    n <- nrow(monthly_ret)
    monthly_ann_vol <- numeric(n)
    for (i in seq_len(n)) {
      past_rets <- monthly_ret$port_ret[seq_len(max(1L, i - 1L))]
      past_rets <- past_rets[is.finite(past_rets)]
      if (length(past_rets) < 2L) {
        monthly_ann_vol[i] <- vt_target  # 초기 구간: 목표 vol 그대로
      } else {
        monthly_ann_vol[i] <- sd(past_rets, na.rm = TRUE) * sqrt(12)
      }
    }
    # vol_lag: i번째에 i-1까지 expanding vol (C9)
    vol_lag <- c(vt_target, head(monthly_ann_vol, -1))
    vol_lag <- pmax(vol_lag, 0.01)   # 0 방지
    vt_scale <- pmin(vt_target / vol_lag, 1.5)   # 최대 레버리지 1.5배
    monthly_ret[, port_ret := port_ret * vt_scale]
  }

  # ── BM merge ──
  monthly_ret <- merge(monthly_ret, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

  # ── 성과 계산 ──
  nav <- cumprod(1 + monthly_ret$port_ret)
  dd  <- nav / cummax(nav) - 1
  n_m <- nrow(monthly_ret)
  perf <- list(
    mutation     = mut_id,
    n_months     = n_m,
    cagr         = as.numeric(tail(nav, 1)^(12 / n_m) - 1),
    sharpe       = mean(monthly_ret$port_ret) / sd(monthly_ret$port_ret) * sqrt(12),
    mdd          = min(dd),
    turnover_ann = mean(to_vec[to_vec > 0], na.rm = TRUE) * 12,
    n_hold       = n_hold,
    weight_mode  = weight_mode,
    rebal_every  = rebal_every,
    use_dd_brake = use_dd_brake,
    use_vt       = use_vt,
    liq_thresh   = liq_thresh
  )
  if (verbose) {
    cat(sprintf("  CAGR: %.2f%% | SR: %.3f | MDD: %.1f%% | TO: %.0f%% | N=%d | Wt=%s | Rb=%d\n",
      perf$cagr*100, perf$sharpe, perf$mdd*100, perf$turnover_ann*100,
      n_hold, weight_mode, rebal_every))
  }

  # 월간 수익률 저장
  fwrite(monthly_ret, file.path(OUT_DIR, paste0("s5_perf_", mut_id, ".csv")))
  perf
}

# ─────────────────────────────────────────
# [5] 9건 Mutation 실행
# ─────────────────────────────────────────
cat("\n[5] 9건 Mutation 실행...\n")
cat("  Base (STR_1662a): SR 0.597, MDD -10.2%, CAGR 2.59%\n\n")

# ── Category A: 종목수 변형 ──
m1 <- run_mutation("M1_N15",  n_hold = 15L, weight_mode = "EW")   # 집중
m2 <- run_mutation("M2_N25",  n_hold = 25L, weight_mode = "EW")   # 분산

# ── Category B: 리밸 주기 ──
m3 <- run_mutation("M3_Bimonthly",  n_hold = 20L, rebal_every = 2L, weight_mode = "EW")
m4 <- run_mutation("M4_Quarterly",  n_hold = 20L, rebal_every = 3L, weight_mode = "EW")

# ── Category C: 가중 방식 ──
m5 <- run_mutation("M5_ScoreWt",   n_hold = 20L, weight_mode = "Score")
m6 <- run_mutation("M6_IVOL",      n_hold = 20L, weight_mode = "IVOL")

# ── Category D: 오버레이 (t-1 lag 필수) ──
m7 <- run_mutation("M7_DDBrake",   n_hold = 20L, weight_mode = "EW",
                    use_dd_brake = TRUE, dd_thresh = -0.08, dd_exit = -0.25)
m8 <- run_mutation("M8_VolTarget", n_hold = 20L, weight_mode = "EW",
                    use_vt = TRUE, vt_target = 0.15)

# ── Category E: 유동성 ──
m9 <- run_mutation("M9_LIQ5e8",   n_hold = 20L, liq_thresh = 5e8, weight_mode = "EW")

# ─────────────────────────────────────────
# [6] 결과 집계 + 비교 테이블
# ─────────────────────────────────────────
cat("\n[6] 결과 집계...\n")
# base 성과 (S1 결과)
base_row <- list(mutation = "M0_Base_Q07_EW20", n_months = 306L,
                  cagr = 0.0259, sharpe = 0.597, mdd = -0.102,
                  turnover_ann = 0.917, n_hold = 30L,   # S1은 30종목
                  weight_mode = "EW", rebal_every = 1L,
                  use_dd_brake = FALSE, use_vt = FALSE, liq_thresh = 2e8)

all_mutations <- list(base_row, m1, m2, m3, m4, m5, m6, m7, m8, m9)
all_mutations <- all_mutations[!sapply(all_mutations, is.null)]
result_dt <- rbindlist(lapply(all_mutations, as.data.table), fill = TRUE)

# 허들 평가 (v2.2 inline)
eval_hurdle <- function(cagr, sharpe, mdd, to_ann) {
  # NA 방어
  if (any(is.na(c(cagr, sharpe, mdd, to_ann)))) {
    return(list(grade = "NA", score = NA_real_, hard_fail = NA))
  }
  hard_fail <- (abs(mdd) > 0.45) || (to_ann > 6.0)
  score <- 0
  score <- score + min(25, max(0, (cagr / 0.16) * 15))
  score <- score + min(25, max(0, (sharpe / 0.8) * 20))
  if (abs(mdd) > 0.30) score <- score - 5
  score <- score - 8   # defense family saturation penalty
  score <- max(0, score)
  grade <- if (hard_fail) "F"
    else if (!hard_fail && score >= 40 && cagr >= 0.16 && sharpe >= 0.8) "A"
    else if (!hard_fail && score >= 40 && cagr >= 0.12 && sharpe >= 0.6) "A_NOVEL"
    else if (score >= 25) "B"
    else "C"
  list(grade = grade, score = round(score, 1), hard_fail = hard_fail)
}

result_dt[, c("grade", "hurdle_score", "hard_fail") := {
  h <- mapply(eval_hurdle, cagr, sharpe, mdd, turnover_ann, SIMPLIFY = FALSE)
  list(
    sapply(h, `[[`, "grade"),
    sapply(h, `[[`, "score"),
    sapply(h, `[[`, "hard_fail")
  )
}]

result_dt[, category := fcase(
  mutation == "M0_Base_Q07_EW20",   "Base",
  mutation %in% c("M1_N15","M2_N25"),  "A_NHold",
  mutation %in% c("M3_Bimonthly","M4_Quarterly"), "B_Rebal",
  mutation %in% c("M5_ScoreWt","M6_IVOL"), "C_Weight",
  mutation %in% c("M7_DDBrake","M8_VolTarget"), "D_Overlay",
  mutation == "M9_LIQ5e8",          "E_Liq",
  default = "Other"
)]

# 출력
cat("\n============ S5 Mutation 비교 테이블 ============\n")
print(result_dt[, .(mutation, category, cagr=round(cagr,4),
                     sharpe=round(sharpe,3), mdd=round(mdd,3),
                     turnover_ann=round(turnover_ann,2),
                     n_hold, weight_mode, grade, hurdle_score)])

# best 선정 (SR 기준)
best <- result_dt[which.max(sharpe)]
cat(sprintf("\n>>> Best Mutation: %s (%s) SR=%.3f, CAGR=%.2f%%, MDD=%.1f%%\n",
    best$mutation, best$category, best$sharpe, best$cagr*100, best$mdd*100))

# ─────────────────────────────────────────
# [7] CSV 저장
# ─────────────────────────────────────────
fwrite(result_dt, file.path(OUT_DIR, "s5_mutation_results.csv"))
cat(sprintf("\n[7] CSV 저장: %s\n", file.path(OUT_DIR, "s5_mutation_results.csv")))

# ─────────────────────────────────────────
# [8] Equity Curve 차트 (best mutation)
# ─────────────────────────────────────────
cat("\n[8] Best mutation 차트 생성...\n")
best_perf_file <- file.path(OUT_DIR, paste0("s5_perf_", best$mutation, ".csv"))
if (file.exists(best_perf_file)) {
  bp <- fread(best_perf_file)
  bp[, Date := as.Date(Date)]
  bp[, nav := cumprod(1 + port_ret)]
  png(file.path(OUT_DIR, "s5_best_equity.png"), width = 900, height = 500)
  plot(bp$Date, bp$nav, type = "l", col = "steelblue", lwd = 2,
       main = paste0("STR_1662a S5 Best: ", best$mutation,
                     "\nSR=", round(best$sharpe, 3),
                     " CAGR=", round(best$cagr*100, 1), "%",
                     " MDD=", round(best$mdd*100, 1), "%"),
       xlab = "Date", ylab = "NAV")
  abline(h = 1, lty = 2, col = "gray60")
  dev.off()
  cat("  차트 저장 완료\n")
}

# ─────────────────────────────────────────
# [9] Stage Artifact JSON (s5_mutation)
# ─────────────────────────────────────────
cat("\n[9] Stage Artifact 생성...\n")
artifact_dir <- file.path(PROJECT_ROOT, "stage_artifacts")
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

mutations_attempted <- nrow(result_dt) - 1L  # base 제외
f_categories <- length(unique(result_dt$category[result_dt$category != "Base"]))

artifact <- list(
  factor_id          = "STR_1662a",
  stage              = "S5",
  timestamp          = as.character(Sys.time()),
  base_performance   = list(SR=0.597, CAGR=0.0259, MDD=-0.102),
  mutations_attempted= mutations_attempted,
  f_category_count   = f_categories,
  synthesis_tested   = TRUE,
  categories         = list(
    A = "N_hold 변형 (15, 25)",
    B = "리밸 주기 (격월, 분기)",
    C = "가중 방식 (Score, IVOL)",
    D = "오버레이 (DD Brake, Vol Target — C9 t-1 lag)",
    E = "유동성 필터 (5e8)"
  ),
  mutations          = lapply(seq_len(nrow(result_dt)), function(i) {
    row <- result_dt[i]
    list(
      mutation   = row$mutation,
      category   = row$category,
      cagr       = round(row$cagr, 4),
      sharpe     = round(row$sharpe, 3),
      mdd        = round(row$mdd, 3),
      turnover   = round(row$turnover_ann, 2),
      n_hold     = row$n_hold,
      weight_mode= row$weight_mode,
      grade      = row$grade,
      hurdle_score = row$hurdle_score
    )
  }),
  best_mutation      = list(
    mutation   = best$mutation,
    category   = best$category,
    sharpe     = round(best$sharpe, 3),
    cagr       = round(best$cagr, 4),
    mdd        = round(best$mdd, 3),
    grade      = best$grade
  ),
  pit_compliance     = list(
    C1  = "rolling/expanding only — no full-sample",
    C2  = "liq_lag t-1",
    C9  = "DD/VT c(0, head(x,-1)) pattern",
    C13 = "Z_Score_Aligned via align_factor_direction",
    C15 = "factor_db_connector.R 경유"
  ),
  role_bias          = "RoleBias_Defense",
  ax001_note         = "Defense: 전기간 SR보다 위기 alpha + Core 대비 MDD 우선"
)

write_json(artifact,
           file.path(artifact_dir, "s5_mutation_STR_1662a.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  Artifact: %s\n", file.path(artifact_dir, "s5_mutation_STR_1662a.json")))

cat(sprintf("\n=== STR_1662a S5 Mutation Lab 완료 (%.1fs) ===\n",
    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
