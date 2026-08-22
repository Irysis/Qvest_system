## Lane C — 선형 3-arm 워크포워드 스코어 산출 (WT_D20260821_001_LANEC)
##
## 사전등록 = stage_artifacts/WT-D20260821_001/PREREG_WT_D20260821_001.md (측정 전 고정).
## 이 파일은 그 사양의 구현이며 사양을 바꾸지 않는다.
##
## ★역할 경계: 여기서는 **스코어까지만** 낸다.
##   포트폴리오 수익률 구성/성과는 canonical_screen_bt() 가 한다 — 손계산 금지.
##   Σ/공분산/weight 결정 없음 (alpha-research 경계).
##
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260821_001/laneC_score.R")'

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(parallel); library(quantreg)
})

OUT   <- "stage_artifacts/WT-D20260821_001"
PANEL <- "stage_artifacts/fq233_probe0_20260813/lane_a_feature_panel.parquet"

## ── 사전등록 §1: dedup 확정 alias 7종 드롭 (arm A/B/C 자구 승계) ────────────────
DROP_ALIAS <- c("V19_Debt_to_Market", "M25_Earnings_Mom_Streak", "M29_Mom_5d",
                "C10_SUE_Persistence", "C13_Revision_Breadth_3m",
                "R12_Idiosyncratic_Risk", "CR04_Ownership_Concentration")
META     <- c("anchor", "sig_date", "Ticker", "fwd_ret_1m")
BURN_IN  <- 60L
QR_TOL   <- 1e-8      # 사전등록 §2.1 — rank 가 tol 1e-6~1e-12 에서 불변(간극 명확), 조율 파라미터 아님
TAUS     <- c(0.50, 0.90)
N_WORKER <- 4L

pan <- as.data.table(read_parquet(PANEL))
pan[, sig_date := as.Date(sig_date)]
feats <- setdiff(names(pan), c(META, DROP_ALIAS))
cat(sprintf("패널 %s행 · 피처 %d종 (드롭 %d) · %d개월\n",
            format(nrow(pan), big.mark = ","), length(feats), length(DROP_ALIAS),
            uniqueN(pan$sig_date)))
stopifnot(length(feats) == 324L)

## 월내 횡단면 중앙값 대체 → 잔여 0 (사전등록 §1 · arm A/B/C 동일)
pan[, (feats) := lapply(.SD, function(x) { m <- stats::median(x, na.rm = TRUE)
                                           x[is.na(x)] <- m; x }),
    by = sig_date, .SDcols = feats]
pan[, (feats) := lapply(.SD, function(x) { x[is.na(x)] <- 0; x }), .SDcols = feats]

X   <- as.matrix(pan[, ..feats])
yv  <- pan$fwd_ret_1m
sig <- pan$sig_date
anc <- as.Date(pan$anchor)
tkr <- as.character(pan$Ticker)
months <- sort(unique(sig))
pred_months <- months[(BURN_IN + 1L):length(months)]
## ★배관 smoke test 전용 knob — 사양 아님. 본 측정은 미설정(전 198개월)으로 실행한다.
##   설정 시 산출물은 laneC_scores_SMOKE.parquet 로 나가 본 산출물을 덮지 못한다.
SMOKE <- suppressWarnings(as.integer(Sys.getenv("LANEC_SMOKE", "")))
if (is.finite(SMOKE) && SMOKE > 0L) {
  pred_months <- utils::tail(pred_months, SMOKE)
  cat(sprintf("★SMOKE 모드 — 마지막 %d개월만 (사양 아님, 배관 검증용)\n", SMOKE))
}
cat(sprintf("학습 시작 = %d번째 달 (%s) · 예측 대상 %d개월\n",
            BURN_IN + 1L, months[BURN_IN + 1L], length(pred_months)))

## 워커가 읽을 공유 스냅샷 (소켓으로 208MB 행렬을 밀지 않는다)
snap <- file.path(tempdir(), "laneC_snapshot.rds")
saveRDS(list(X = X, y = yv, sig = sig), snap)
cat(sprintf("스냅샷 저장 %s (%.0f MB)\n", snap, file.size(snap) / 1e6))

fit_one_month <- function(m) {
  tr <- which(.LC$sig < m); te <- which(.LC$sig == m)
  if (length(te) == 0L || length(tr) < 1000L) return(NULL)

  Xtr <- .LC$X[tr, , drop = FALSE]; ytr <- .LC$y[tr]
  mu  <- colMeans(Xtr)
  sdv <- apply(Xtr, 2L, stats::sd); sdv[!is.finite(sdv) | sdv < 1e-12] <- 1
  for (j in seq_len(ncol(Xtr))) Xtr[, j] <- (Xtr[, j] - mu[j]) / sdv[j]   # 학습창 통계만 (PIT)

  ## 사전등록 §2.1 — 랭크-노출 QR 로 정확 alias 제거 (R lm/rq 내부 aliasing 과 동일 조치)
  qrp  <- qr(Xtr, tol = QR_TOL)
  k    <- qrp$rank
  keep <- sort(qrp$pivot[seq_len(k)])
  A <- cbind(1, Xtr[, keep, drop = FALSE])
  rm(Xtr); gc(FALSE)

  ## 조건수 실측 (사전등록 §2.1 기록 의무). Gram 고윳값 경유 — cond(A) = sqrt(cond(A'A)).
  ev <- eigen(crossprod(A), symmetric = TRUE, only.values = TRUE)$values
  cond_A <- if (min(ev) > 0) sqrt(max(ev) / min(ev)) else Inf

  Xte <- .LC$X[te, , drop = FALSE]
  for (j in seq_len(ncol(Xte))) Xte[, j] <- (Xte[, j] - mu[j]) / sdv[j]
  B <- cbind(1, Xte[, keep, drop = FALSE])

  warn <- character(0)
  grab <- function(expr) withCallingHandlers(expr,
    warning = function(w) { warn <<- c(warn, conditionMessage(w)); invokeRestart("muffleWarning") })

  b_mean <- grab(.lm.fit(A, ytr)$coefficients)
  b_q50  <- grab(quantreg::rq.fit(A, ytr, tau = TAUS[1], method = "fn")$coefficients)
  b_q90  <- grab(quantreg::rq.fit(A, ytr, tau = TAUS[2], method = "fn")$coefficients)
  b_mean[!is.finite(b_mean)] <- 0
  b_q50[!is.finite(b_q50)]   <- 0
  b_q90[!is.finite(b_q90)]   <- 0

  list(idx = te, n_kept = k, cond_A = cond_A, n_train = length(tr),
       warn = paste(unique(warn), collapse = " | "),
       s_mean = as.numeric(B %*% b_mean),
       s_q50  = as.numeric(B %*% b_q50),
       s_q90  = as.numeric(B %*% b_q90))
}

cl <- makeCluster(N_WORKER)
clusterExport(cl, c("snap", "QR_TOL", "TAUS"), envir = environment())
invisible(clusterEvalQ(cl, { suppressPackageStartupMessages(library(quantreg))
                            .LC <- readRDS(snap); NULL }))
t0 <- Sys.time()
res <- parLapplyLB(cl, pred_months, fit_one_month)
try(stopCluster(cl), silent = TRUE)
cat(sprintf("워크포워드 완료 %.1f분\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))

res <- Filter(Negate(is.null), res)
sc <- rbindlist(lapply(res, function(r) data.table(
  Date = anc[r$idx], sig_date = sig[r$idx], Ticker = tkr[r$idx],
  s_mean = r$s_mean, s_q50 = r$s_q50, s_q90 = r$s_q90)))
setorder(sc, Date, Ticker)
fp <- file.path(OUT, if (is.finite(SMOKE) && SMOKE > 0L) "laneC_scores_SMOKE.parquet"
                     else "laneC_scores.parquet")
write_parquet(sc, fp)
cat(sprintf("\n스코어 저장: %s — %s행 · %d개월\n", fp, format(nrow(sc), big.mark = ","),
            uniqueN(sc$sig_date)))

cond <- rbindlist(lapply(res, function(r) data.table(
  n_train = r$n_train, n_kept = r$n_kept, cond_A = r$cond_A, warn = r$warn)))
n_warn <- sum(nzchar(cond$warn))
cat(sprintf("조건화 진단 — n_kept 중앙 %d (범위 %d~%d) · cond(A) 중앙 %.3e (최대 %.3e) · 경고 월 %d/%d\n",
            as.integer(stats::median(cond$n_kept)), min(cond$n_kept), max(cond$n_kept),
            stats::median(cond$cond_A), max(cond$cond_A), n_warn, nrow(cond)))
if (n_warn > 0) print(cond[nzchar(warn), .N, by = warn])

## 진단만(성과 아님): 월별 rank-IC. ★판정 1급 결과량은 canonical_screen_bt 의 total net SR.
j <- merge(sc, pan[, .(sig_date, Ticker = as.character(Ticker), fwd_ret_1m)],
           by = c("sig_date", "Ticker"), all.x = TRUE)
j <- j[is.finite(fwd_ret_1m)]
diag <- list()
for (cc in c("s_mean", "s_q50", "s_q90")) {
  ic <- j[, .(ic = suppressWarnings(stats::cor(get(cc), fwd_ret_1m, method = "spearman"))),
          by = sig_date][is.finite(ic)]
  s_ic <- if (nrow(ic) > 1L) stats::sd(ic$ic) else NA_real_
  diag[[cc]] <- list(rank_ic_mean = if (nrow(ic) > 0L) mean(ic$ic) else NA_real_,
                     icir = if (is.finite(s_ic) && s_ic > 0) mean(ic$ic) / s_ic else NA_real_,
                     n_months = nrow(ic))
  cat(sprintf("  diag %-7s rank-IC %+.4f · ICIR %+.3f · n=%d\n", cc,
              diag[[cc]]$rank_ic_mean, diag[[cc]]$icir, diag[[cc]]$n_months))
}
cat("  ※진단이다. 판정은 total net SR + ML 대응 arm 대비 paired NW3 t.\n")

write_json(list(
  round_id = "WT_D20260821_001_LANEC", prereg = "PREREG_WT_D20260821_001.md",
  arms = list(L_mean = ".lm.fit OLS", L_q50 = "quantreg::rq.fit tau=0.50 method=fn",
              L_q90 = "quantreg::rq.fit tau=0.90 method=fn"),
  regularization = "none (사전등록 §2.1 선택지 ii) — 정확 alias 만 랭크-노출 QR 로 제거, 벌점 없음",
  qr_tol = QR_TOL, burn_in_months = BURN_IN, n_features_input = length(feats),
  dropped_alias = DROP_ALIAS,
  conditioning = list(n_kept_median = as.integer(stats::median(cond$n_kept)),
                      n_kept_min = min(cond$n_kept), n_kept_max = max(cond$n_kept),
                      cond_A_median = stats::median(cond$cond_A),
                      cond_A_max = max(cond$cond_A),
                      n_months_with_warning = n_warn, n_months = nrow(cond),
                      note = "cond_A = sqrt(cond(A'A)) 실측 (A = 절편 + 유지열, 학습창 표준화 후). 사전등록 §2.1 기록 의무"),
  n_pred_months = uniqueN(sc$sig_date), n_scores = nrow(sc), diag = diag,
  ast_leaf = list(class = "MODEL_SCORE",
                  train_window_end = "sig_date < 예측월 (확장창, 학습창 종점 ≤ t_d−1)",
                  train_leaves = "lane_a_feature_panel.parquet 324피처 (load_month_factors + Z_Score_Aligned, 팩터 Date +1개월 앵커)",
                  note = "저장 패널을 FIELD 리프로 위장하지 않음 — 학습 산출 스코어임을 명시"),
  note = "스코어 산출까지만. 성과·판정은 canonical_screen_bt 경유(python-policy §4 동치 규약)."),
  file.path(OUT, if (is.finite(SMOKE) && SMOKE > 0L) "laneC_score_meta_SMOKE.json"
                 else "laneC_score_meta.json"),
  auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
if (!(is.finite(SMOKE) && SMOKE > 0L)) saveRDS(cond, file.path(OUT, "laneC_conditioning.rds"))
cat("메타 저장 완료\n")
