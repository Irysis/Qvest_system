# =============================================================================
# FQ-057 NP4 run_02: 2-arm walk-forward weight 생성 (Sigma-swap A/B)
#   Arm A (incumbent): Sigma = .get_cor_cov(ret60, "ledoit_wolf")  [linear LW]
#   Arm B (candidate): Sigma = .get_cor_cov(ret60, "lw_nls")       [NP3 등재본]
#   그 외 전부 동일: 알파(mom_12_1 z * 0.01), mvo_weights 파라미터(사전등록 고정),
#   유니버스/유동성/스케줄.
# Scenarios:
#   S1 (PRIMARY): 유니버스-레벨 p≈300 > n=60
#   S2 (SECONDARY): 알파 상위 50 pre-screen -> Sigma 재추정(p=50<n=60) -> MVO 25
# 사전등록: stage_artifacts/method_frontier/np4_preregistration.json (불변)
# Output: np4_weights.parquet + np4_run02_meta.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(quadprog)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))            # .get_cor_cov (standalone)
source(file.path(ROOT, "02_Infrastructure/portfolio/mean_variance_optimizer.R"))  # mvo_weights

OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
PIN_TAG <- "fq057_20260718_171024"

stopifnot(exists(".get_cor_cov", mode = "function"), exists("mvo_weights", mode = "function"))

# ---- 사전등록 고정 파라미터 -------------------------------------------------
LAMBDA <- 2.0; PSI <- 0.3
BOUNDS <- c(0, 0.20); MAX_NAMES <- 25L; MIN_NAMES <- 15L
HHI_CAP <- 0.10; ALPHA_WINSOR <- 2.0
ALPHA_SCALE <- 0.01
LIQ_MIN <- 2e8
REB_FROM <- 200912L; REB_TO <- 202605L
WIN <- 60L; MOM_FROM <- 11L; MOM_TO <- 1L   # months t-11..t-1 (skip month t)

# ---- 입력 로드 --------------------------------------------------------------
mr   <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
snap <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
liq  <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_liq_snapshot.parquet")))

# 월간 수익 행렬 (rows=ym asc, cols=Ticker)
Mw <- dcast(mr, ym ~ Ticker, value.var = "ret_m")
yms <- Mw$ym
mat <- as.matrix(Mw[, -1, drop = FALSE])
rownames(mat) <- as.character(yms)

# ym 연속성 확인 (모멘텀/윈도 인덱스 산술의 전제)
ym_next <- function(y) { yy <- y %/% 100L; mm <- y %% 100L; if (mm == 12L) (yy + 1L) * 100L + 1L else y + 1L }
for (i in seq_len(length(yms) - 1L)) stopifnot(yms[i + 1L] == ym_next(yms[i]))
cat("[panel] months:", length(yms), "range:", yms[1], "..", yms[length(yms)], "\n")

reb_months <- yms[yms >= REB_FROM & yms <= REB_TO]
cat("[schedule] rebalance months:", length(reb_months), "\n")

rows_list <- list(); meta_rows <- list(); failed <- list()
lw_degen_count <- 0L

# 엔진 결함 수리 완료 (2026-07-18, task_1b9e50a3 → mean_variance_optimizer.R v2.3):
#   mvo_weights 내부 hhi_cap projection(.project_hhi)이 absorber를 w=0 포함 전체
#   유니버스에서 골라 top-25 support 밖으로 비중 누출 -> max_names 하드캡(RF-O5)
#   위반하던 결함(p>25 유니버스 발현)을 엔진에서 직접 수리(절단 시 projection 을
#   non-zero support 로 제한). 구 인라인 우회(hhi_cap=NA + support-.project_hhi)는
#   수리 엔진의 hhi_cap=HHI_CAP 직접호출과 bit-identical(적대검증 L5 / battery Test C
#   3/3 max|dw|=0) 확인 → 직접호출로 복원. 재실행 시 산출 불변.
run_mvo <- function(alpha_vec, Sigma) {
  mvo_weights(alpha = alpha_vec, cov_matrix = Sigma, confidence = NULL,
              lambda = LAMBDA, psi = PSI, bounds = BOUNDS,
              max_names = MAX_NAMES, min_names = MIN_NAMES,
              hhi_cap = HHI_CAP, alpha_winsor = ALPHA_WINSOR,
              turnover_penalty = 0.0, active = FALSE)
}

t0 <- Sys.time()
for (t_ym in reb_months) {
  idx <- match(t_ym, yms)
  stopifnot(idx >= WIN)
  w_idx <- (idx - WIN + 1L):idx

  members <- snap[ym == t_ym & member == 1L, Ticker]
  liq_ok  <- liq[ym == t_ym & !is.na(avgtv20) & avgtv20 >= LIQ_MIN, Ticker]
  cand    <- intersect(intersect(members, liq_ok), colnames(mat))
  if (length(cand) < 40L) { failed[[length(failed) + 1L]] <- list(ym = t_ym, reason = "too_few_candidates"); next }

  sub60 <- mat[w_idx, cand, drop = FALSE]
  complete <- colSums(!is.na(sub60)) == WIN
  elig <- cand[complete]
  if (length(elig) < 40L) { failed[[length(failed) + 1L]] <- list(ym = t_ym, reason = "too_few_complete60"); next }
  ret60 <- sub60[, elig, drop = FALSE]

  # ---- 알파: mom_12_1 (months t-11..t-1, 최신월 t 제외) — 신호 정의 (성과합성 아님)
  mom_rows <- (idx - MOM_FROM):(idx - MOM_TO)
  mom_sub  <- mat[mom_rows, elig, drop = FALSE]          # 11 x p, 완전(60창 내부)
  mom <- expm1(colSums(log1p(mom_sub)))
  z <- as.numeric(scale(mom))
  alpha_vec <- ALPHA_SCALE * z
  names(alpha_vec) <- elig

  # ---- Sigma 양 arm ----------------------------------------------------------
  ccA <- withCallingHandlers(
    .get_cor_cov(ret60, "ledoit_wolf"),
    warning = function(w) { lw_degen_count <<- lw_degen_count + 1L; invokeRestart("muffleWarning") })
  SigA <- ccA$cov
  SigB <- .get_cor_cov(ret60, "lw_nls")$cov

  # ---- S1: universe-level (p>n) ---------------------------------------------
  resA1 <- run_mvo(alpha_vec, SigA)
  resB1 <- run_mvo(alpha_vec, SigB)

  # ---- S2: pre-screen top-50 -> Sigma 재추정 (p=50<n=60) ----------------------
  top50 <- names(sort(alpha_vec, decreasing = TRUE))[seq_len(min(50L, length(elig)))]
  ret60_50 <- ret60[, top50, drop = FALSE]
  ccA2 <- withCallingHandlers(
    .get_cor_cov(ret60_50, "ledoit_wolf"),
    warning = function(w) { lw_degen_count <<- lw_degen_count + 1L; invokeRestart("muffleWarning") })
  SigA2 <- ccA2$cov
  SigB2 <- .get_cor_cov(ret60_50, "lw_nls")$cov
  a50 <- alpha_vec[top50]
  resA2 <- run_mvo(a50, SigA2)
  resB2 <- run_mvo(a50, SigB2)

  cells <- list(list("S1", "lw_linear", resA1), list("S1", "lw_nls", resB1),
                list("S2", "lw_linear", resA2), list("S2", "lw_nls", resB2))
  # paired 무결성: 시나리오 내 한 arm이라도 weights NULL이면 그 시나리오·월 제외
  s1_ok <- !is.null(resA1$weights) && !is.null(resB1$weights)
  s2_ok <- !is.null(resA2$weights) && !is.null(resB2$weights)
  if (!s1_ok) failed[[length(failed) + 1L]] <- list(ym = t_ym, reason = "S1_qp_null")
  if (!s2_ok) failed[[length(failed) + 1L]] <- list(ym = t_ym, reason = "S2_qp_null")

  for (cl in cells) {
    sc <- cl[[1]]; arm <- cl[[2]]; res <- cl[[3]]
    if ((sc == "S1" && !s1_ok) || (sc == "S2" && !s2_ok)) next
    w <- res$weights
    # hard constraint audit
    stopifnot(length(w) <= MAX_NAMES, all(w >= -1e-9), max(w) <= BOUNDS[2] + 1e-6,
              abs(sum(w) - 1) < 1e-6)
    rows_list[[length(rows_list) + 1L]] <- data.table(
      scenario = sc, arm = arm, ym = t_ym, Ticker = names(w), w = as.numeric(w))
    meta_rows[[length(meta_rows) + 1L]] <- data.table(
      scenario = sc, arm = arm, ym = t_ym, p_universe = length(elig),
      n_names = res$n_names, hhi = res$hhi,
      soft_violation = if (is.null(res$reason)) NA_character_ else res$reason,
      lambda_used = res$lambda_used, exp_te = res$expected_tracking_error)
  }
  if (match(t_ym, reb_months) %% 24 == 0)
    cat(sprintf("[wf] %d done (%.1f min elapsed)\n", t_ym,
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

W <- rbindlist(rows_list)
MET <- rbindlist(meta_rows)
cat("[wf] weight rows:", nrow(W), " cells:", nrow(MET), " lw_degenerate warnings:", lw_degen_count, "\n")

write_parquet(W,   file.path(OUT_DIR, "np4_weights.parquet"))
write_parquet(MET, file.path(OUT_DIR, "np4_cell_meta.parquet"))
run_meta <- list(pin_tag = PIN_TAG, built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                 n_rebalances = length(reb_months),
                 lw_degenerate_warning_count = lw_degen_count,
                 failed_months = failed,
                 params = list(lambda = LAMBDA, psi = PSI, bounds = BOUNDS,
                               max_names = MAX_NAMES, min_names = MIN_NAMES,
                               hhi_cap = HHI_CAP, alpha_winsor = ALPHA_WINSOR,
                               alpha_scale = ALPHA_SCALE, liq_min = LIQ_MIN,
                               window_m = WIN, mom = "t-11..t-1 skip t"))
write_json(run_meta, file.path(OUT_DIR, "np4_run02_meta.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[done] run_02 complete —", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")
