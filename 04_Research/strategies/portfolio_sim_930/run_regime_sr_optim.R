cat("=== Regime-Conditional SR Optimization (B-Plan) ===\n")
cat("## 핵심아이디어: CALM/CAUTION/CRISIS 국면별 별도 최적 가중 도출 (Differentiable SR)\n")
cat("## 기준: C5 준수 — t-1 regime score 사용, OOS expanding window 최소 60개월\n")

suppressPackageStartupMessages({
  library(data.table)
})

# ============================================================
# 1. 데이터 로드
# ============================================================
# 현재 작업 디렉토리 기준 상대 경로 사용 (한글 경로 인코딩 우회)
# Rscript 실행 시 cd 로 해당 디렉토리에 위치
RET_PATH    <- "portfolio_4sleeve_monthly_rets.csv"
REGIME_PATH <- "macro_regime_tmp.csv"  # parquet → csv 변환본 (한글 경로 우회)

cat("\n[1/6] 데이터 로드...\n")
rets_raw   <- as.data.table(read.csv(RET_PATH,    stringsAsFactors = FALSE))
regime_raw <- as.data.table(read.csv(REGIME_PATH, stringsAsFactors = FALSE))

ROOT <- getwd()  # 결과 저장용

cat("수익률 행수:", nrow(rets_raw), "| 날짜 범위:", rets_raw$Date[1], "~", rets_raw$Date[nrow(rets_raw)], "\n")
cat("Regime 행수:", nrow(regime_raw), "| 날짜 범위:", regime_raw$Date[1], "~", regime_raw$Date[nrow(regime_raw)], "\n")

# ============================================================
# 2. 날짜 정규화 및 Merge
# ============================================================
cat("\n[2/6] 날짜 정규화 및 Merge...\n")

# 수익률: Date를 YM 키로 변환 (YYYY-MM)
rets_raw[, Date := as.Date(Date)]
rets_raw[, YM := format(Date, "%Y-%m")]

# Regime: YM 기준 (이미 YYYY-MM 형식)
regime_raw[, YM := as.character(YM)]

# C5 준수: t-1 regime score (다음 달 수익률에 적용할 regime은 당월 말 기준)
# 수익률 Date = 월말, Regime Date = 월초 → 동일 YM 매칭이 t-1 lag 역할
# 실제 의사결정: 월말에 다음달 포지션 결정 = 당월 regime 사용
regime_lag <- regime_raw[, .(YM, regime_score = Macro_Risk_Score)]

# Merge
merged <- merge(rets_raw, regime_lag, by = "YM", all.x = TRUE)
merged <- merged[order(Date)]

# ret_930 == 0인 행 제거 (데이터 없는 구간)
merged <- merged[ret_930 != 0 | (ret_vdp != 0 | ret_q07 != 0)]

# NA 제거
merged <- merged[!is.na(regime_score) & !is.na(ret_vdp) & !is.na(ret_q07) & !is.na(ret_930)]

cat("Merge 후 행수:", nrow(merged), "\n")
cat("날짜 범위:", as.character(merged$Date[1]), "~", as.character(merged$Date[nrow(merged)]), "\n")

# ============================================================
# 3. Regime Bucket 분류
# ============================================================
cat("\n[3/6] Regime Bucket 분류...\n")

merged[, regime_bucket := fcase(
  regime_score < 25,  "CALM",
  regime_score < 50,  "CAUTION",
  default =           "CRISIS"
)]

bucket_counts <- merged[, .N, by = regime_bucket]
cat("Bucket 분포:\n")
print(bucket_counts)
cat("\n비율: CALM", round(mean(merged$regime_bucket == "CALM") * 100, 1), "%,",
    "CAUTION", round(mean(merged$regime_bucket == "CAUTION") * 100, 1), "%,",
    "CRISIS", round(mean(merged$regime_bucket == "CRISIS") * 100, 1), "%\n")

# ============================================================
# 4. 최적화 함수 정의
# ============================================================
cat("\n[4/6] Regime별 전체구간 최적화 (Full-Sample 참조용 — OOS 설계 기준)\n")

# Softmax 제약 + 박스 제약 (min 5%, max 80%)
optimize_sr_bucket <- function(rets_matrix, allow_cash = FALSE, seed = 42) {
  # rets_matrix: (T x 3) matrix [vdp, q07, 930]
  n_assets <- ncol(rets_matrix)

  obj <- function(raw_w) {
    # Softmax → 양수 합=1
    w_exp <- exp(raw_w - max(raw_w))
    w <- w_exp / sum(w_exp)

    # 박스 제약: min 5%, max 80%
    w <- pmax(w, 0.05)
    w <- pmin(w, 0.80)
    w <- w / sum(w)

    port <- as.numeric(rets_matrix %*% w)
    mu   <- mean(port)
    sig  <- sd(port)
    if (sig < 1e-10) return(1e6)
    -mu / sig
  }

  set.seed(seed)
  best <- NULL
  best_val <- Inf

  # 다중 시작점 (전역 최적 탐색)
  starts <- list(
    c(0, 0, 0),
    c(1, 0, 0), c(0, 1, 0), c(0, 0, 1),
    c(0.5, 0.5, 0), c(0.5, 0, 0.5), c(0, 0.5, 0.5),
    c(0.3, 0.3, 0.3)
  )

  for (s in starts) {
    res <- tryCatch(
      optim(s, obj, method = "Nelder-Mead",
            control = list(maxit = 5000, reltol = 1e-10)),
      error = function(e) NULL
    )
    if (!is.null(res) && res$value < best_val) {
      best_val <- res$value
      best <- res
    }
  }

  if (is.null(best)) return(NULL)

  raw_w <- best$par
  w_exp <- exp(raw_w - max(raw_w))
  w <- w_exp / sum(w_exp)
  w <- pmax(w, 0.05); w <- pmin(w, 0.80); w <- w / sum(w)

  port <- as.numeric(rets_matrix %*% w)
  sr_annual <- (mean(port) / sd(port)) * sqrt(12)

  list(w = w, sr_annual = sr_annual, n_obs = nrow(rets_matrix))
}

# 전체 구간 Regime별 최적화 (참조 — OOS 아님)
buckets <- c("CALM", "CAUTION", "CRISIS")
full_results <- list()

for (bkt in buckets) {
  sub <- merged[regime_bucket == bkt]
  if (nrow(sub) < 12) {
    cat(bkt, ": 관측치 부족 (", nrow(sub), "개) — 등가중 사용\n")
    full_results[[bkt]] <- list(w = c(1/3, 1/3, 1/3), sr_annual = NA, n_obs = nrow(sub))
    next
  }

  mat <- as.matrix(sub[, .(ret_vdp, ret_q07, ret_930)])
  res <- optimize_sr_bucket(mat)
  full_results[[bkt]] <- res

  cat(sprintf("%s (n=%d): VDplus=%.1f%% Q07=%.1f%% STR930=%.1f%% | SR=%.3f\n",
              bkt, nrow(sub),
              res$w[1]*100, res$w[2]*100, res$w[3]*100,
              res$sr_annual))
}

# ============================================================
# 5. OOS 시뮬레이션 (Expanding Window, 최소 60개월)
# ============================================================
cat("\n[5/6] OOS 시뮬레이션 (Expanding Window, C5 준수)...\n")

N <- nrow(merged)
MIN_TRAIN <- 60  # 최소 60개월 학습 구간

# A안 정적 가중 (참조)
W_STATIC <- c(0.34, 0.39, 0.27)  # VDplus, Q07, STR930

oos_results <- data.table(
  Date = merged$Date[(MIN_TRAIN + 1):N],
  YM   = merged$YM[(MIN_TRAIN + 1):N],
  ret_vdp = merged$ret_vdp[(MIN_TRAIN + 1):N],
  ret_q07 = merged$ret_q07[(MIN_TRAIN + 1):N],
  ret_930 = merged$ret_930[(MIN_TRAIN + 1):N],
  regime_bucket = merged$regime_bucket[(MIN_TRAIN + 1):N],
  regime_score  = merged$regime_score[(MIN_TRAIN + 1):N]
)

# 각 시점 t에서: 과거 1~t 데이터로 bucket별 최적 가중 추정 → t+1 수익률 계산
# (여기서 t = MIN_TRAIN 이후 각 달)

n_oos <- nrow(oos_results)
oos_results[, ret_dynamic := NA_real_]
oos_results[, ret_static  := NA_real_]
oos_results[, w_vdp := NA_real_]
oos_results[, w_q07 := NA_real_]
oos_results[, w_930 := NA_real_]

cat("OOS 구간:", n_oos, "개월\n")
cat("진행 중...")

# 캐시: 이전 달과 동일 bucket 결과 재사용 가능 여부 확인
prev_weights <- list(CALM = NULL, CAUTION = NULL, CRISIS = NULL)
prev_n       <- list(CALM = 0,    CAUTION = 0,    CRISIS = 0)

for (i in seq_len(n_oos)) {
  t_idx <- MIN_TRAIN + i  # 현재 시점 (예측 대상)
  train_data <- merged[1:(t_idx - 1)]  # t-1까지 학습 (C5: t-1 lag)

  # 현재 시점의 regime bucket
  cur_bucket <- oos_results$regime_bucket[i]

  # 해당 bucket의 train 데이터
  train_sub <- train_data[regime_bucket == cur_bucket]
  n_cur <- nrow(train_sub)

  # bucket 데이터가 늘었을 때만 재최적화 (효율화)
  if (n_cur >= 12 && (is.null(prev_weights[[cur_bucket]]) || n_cur > prev_n[[cur_bucket]])) {
    mat <- as.matrix(train_sub[, .(ret_vdp, ret_q07, ret_930)])
    res <- optimize_sr_bucket(mat)

    if (!is.null(res)) {
      prev_weights[[cur_bucket]] <- res$w
      prev_n[[cur_bucket]] <- n_cur
    }
  }

  # 가중 결정
  if (!is.null(prev_weights[[cur_bucket]])) {
    w_use <- prev_weights[[cur_bucket]]
  } else {
    # 학습 데이터 부족 → 등가중
    w_use <- c(1/3, 1/3, 1/3)
  }

  # 수익률 계산
  ret_vec <- c(oos_results$ret_vdp[i], oos_results$ret_q07[i], oos_results$ret_930[i])
  oos_results[i, ret_dynamic := sum(w_use * ret_vec)]
  oos_results[i, ret_static  := sum(W_STATIC * ret_vec)]
  oos_results[i, w_vdp := w_use[1]]
  oos_results[i, w_q07 := w_use[2]]
  oos_results[i, w_930 := w_use[3]]

  if (i %% 24 == 0) cat(sprintf(" t=%d/%d", i, n_oos))
}
cat("\n완료.\n")

# ============================================================
# 6. 결과 비교
# ============================================================
cat("\n[6/6] A안 vs B안 성과 비교\n")
cat(paste(rep("=", 60), collapse=""), "\n")

calc_metrics <- function(rets, label) {
  n <- length(rets)
  mu <- mean(rets) * 12
  sig <- sd(rets) * sqrt(12)
  sr <- mu / sig

  cum <- cumprod(1 + rets)
  peak <- cummax(cum)
  dd <- (cum - peak) / peak
  mdd <- min(dd)

  cagr <- (tail(cum, 1))^(12/n) - 1

  cat(sprintf("\n[%s]\n", label))
  cat(sprintf("  OOS 관측수 : %d개월\n", n))
  cat(sprintf("  SR (연율)  : %.4f\n", sr))
  cat(sprintf("  CAGR       : %.2f%%\n", cagr * 100))
  cat(sprintf("  연변동성   : %.2f%%\n", sig * 100))
  cat(sprintf("  MDD        : %.2f%%\n", mdd * 100))
  cat(sprintf("  월평균 수익: %.4f%%\n", mean(rets) * 100))

  invisible(list(sr = sr, cagr = cagr, vol = sig, mdd = mdd))
}

metrics_a <- calc_metrics(oos_results$ret_static,  "A안 (정적 가중: VDp34% + Q07 39% + 930 27%)")
metrics_b <- calc_metrics(oos_results$ret_dynamic, "B안 (동적 Regime-Conditional)")

cat("\n")
cat(paste(rep("-", 60), collapse=""), "\n")
cat(sprintf("SR 개선: A안 %.4f → B안 %.4f (차이: %+.4f, %+.2f%%)\n",
            metrics_a$sr, metrics_b$sr,
            metrics_b$sr - metrics_a$sr,
            (metrics_b$sr / metrics_a$sr - 1) * 100))
cat(sprintf("MDD 변화: A안 %.2f%% → B안 %.2f%%\n",
            metrics_a$mdd * 100, metrics_b$mdd * 100))
cat(paste(rep("-", 60), collapse=""), "\n")

# Bucket별 최종 가중 (OOS 마지막 시점)
cat("\nOOS 마지막 시점 Bucket별 가중:\n")
for (bkt in buckets) {
  last_row <- oos_results[regime_bucket == bkt][.N]
  if (nrow(last_row) > 0) {
    cat(sprintf("  %s: VDplus=%.1f%% Q07=%.1f%% STR930=%.1f%%\n",
                bkt,
                last_row$w_vdp * 100,
                last_row$w_q07 * 100,
                last_row$w_930 * 100))
  }
}

# 평균 동적 가중 by bucket
cat("\nOOS 구간 평균 동적 가중 (by Bucket):\n")
avg_w <- oos_results[, .(
  avg_vdp = mean(w_vdp, na.rm=TRUE),
  avg_q07 = mean(w_q07, na.rm=TRUE),
  avg_930 = mean(w_930, na.rm=TRUE),
  n_months = .N,
  avg_sr_monthly = mean(ret_dynamic, na.rm=TRUE)/sd(ret_dynamic, na.rm=TRUE)
), by = regime_bucket]
print(avg_w)

# Bucket별 A vs B 비교
cat("\nBucket별 월평균 수익률 비교:\n")
bkt_compare <- oos_results[, .(
  ret_static_mean  = mean(ret_static) * 100,
  ret_dynamic_mean = mean(ret_dynamic) * 100,
  ret_static_sr    = mean(ret_static) / sd(ret_static) * sqrt(12),
  ret_dynamic_sr   = mean(ret_dynamic) / sd(ret_dynamic) * sqrt(12),
  n = .N
), by = regime_bucket]
print(bkt_compare)

# ============================================================
# 결과 저장
# ============================================================
OUT_DIR <- ROOT  # getwd()가 이미 portfolio_sim_930 디렉토리

fwrite(oos_results, file.path(OUT_DIR, "regime_sr_oos_results.csv"))
cat("\n저장 완료:", file.path(OUT_DIR, "regime_sr_oos_results.csv"), "\n")

# 요약 저장
summary_list <- list(
  plan_a = list(
    label = "정적 가중 (A안)",
    weights = list(vdp = 0.34, q07 = 0.39, s930 = 0.27),
    sr_oos = metrics_a$sr,
    cagr_oos = metrics_a$cagr,
    mdd_oos = metrics_a$mdd
  ),
  plan_b = list(
    label = "동적 Regime-Conditional (B안)",
    full_sample_weights = lapply(full_results, function(r) {
      list(vdp = r$w[1], q07 = r$w[2], s930 = r$w[3], sr = r$sr_annual, n = r$n_obs)
    }),
    sr_oos = metrics_b$sr,
    cagr_oos = metrics_b$cagr,
    mdd_oos = metrics_b$mdd
  ),
  sr_improvement = metrics_b$sr - metrics_a$sr,
  oos_n_months = n_oos
)

saveRDS(summary_list, file.path(OUT_DIR, "regime_sr_summary.rds"))
cat("요약 RDS 저장 완료\n")

cat("\n=== 완료 ===\n")
