## ============================================================================
## kalman_beta_drift.R — 월간 monitoring 입력: 칼만 시변 β̂ vs 배포 의도 노출 대조
## (task #56 배선, 2026-07-13 — 칼만 연구 R19/R21의 유일 잔존 소비처 = 감시 조기경보)
## book·전략 무변경 — monitoring 입력 확장만. book_state/weights/배포 파라미터 무수정.
##
## 지표 (사전 고정):
##   β̂_t       = 북 recon(계약 rds ret_net) vs 벤치 단일 시계열 dlm TV-beta 필터
##               (stage_artifacts/te_diag_202607/kalman_ext.R §[3] 구현 재사용)
##               book_t = α_t + β_t·bm_t + e_t, (α_t,β_t) random walk (dlmModReg addInt)
##               dlmMLE 확장창 walk-forward(stride 12, 정보셋 = 당월 마감까지·미래 없음)
##               ★ dlmFilter filtered only — 스무더(dlmSmooth) 금지 (PIT)
##               monitoring-basis: 월 마감 후 진단 → β̂_t = filtered β_{t|t}
##   invested_t = m4_t × β_R05_t  (배포 manifest, period_returns_layer5_faith.csv)
##   gap_t      = |β̂_t − invested_t|
##
## 경보 규칙 (사전 고정 — 임계/윈도우 sweep 금지):
##   z_t = (gap_t − mean(gap_{t−12..t−1})) / sd(gap_{t−12..t−1})  [trailing 12m, 당월 제외]
##   z_t > 2 AND z_{t−1} > 2  (2개월 연속)  →  WARN "오버레이 실효-의도 괴리"
##   자동조치 없음 — 도훈 판단 재료. WARN 발화 시에만 텔레그램 v7 1건(그 외 무발송).
##
## 실행: 월간 monitoring agent가 source 패턴으로 실행
##   cd 02_Infrastructure/reports && Rscript -e 'source("kalman_beta_drift.R")'
## 산출: qepm/mailbox/monitoring/kalman_beta_drift/
##   kalman_beta_drift_series.csv + kalman_beta_drift_latest.json + 월 아카이브 json
## 규율: 단일스레드 · arrow io(2) · 필터값만. 05_Production은 read-only 소비.
## ============================================================================
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(dlm)
}))
setDTthreads(1)
set.seed(47)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
## 계약 recon (book_state.json::rerun_20260702_*::clean_rds 포인터와 동일).
## PG2 recon 갱신 시 이 상수만 최신 canonical recon rds로 교체.
RECON_RDS  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
## 패널 소스 교체 (2026-08-02 프로덕션 정리 1단계): 구 faith 슬롯(2-2) 사본 → WT-H rerun 정본.
## 세 사본은 동일 STR_1715/M4/R05 base 공유(extend_nolayer4_series [1] 주석·alignment verify [A]) —
## faith 슬롯은 look-ahead KILL 로 철거되었고, 이 스크립트가 쓰는 컬럼은 base 공통분뿐이다.
PANEL_CSV  <- file.path(ROOT, "qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv")  # read-only
BOOK_STATE <- file.path(ROOT, "qepm/mailbox/governor/book_state.json")  # read-only (당월 manifest 주석용)
OUT_DIR    <- file.path(ROOT, "qepm/mailbox/monitoring/kalman_beta_drift")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

## 사전 고정 파라미터 — sweep/조정 금지 (변경은 도훈 mandate 필요)
Z_THRESH <- 2; Z_WIN <- 12; CONSEC <- 2; BURN <- 36; STRIDE <- 12

## ---- 1. 데이터 로드 (te_diag_202607/te_decompose.R §1과 동일 병합) ----
bt  <- readRDS(RECON_RDS)
pr  <- as.data.table(bt$period_returns)[, .(date = as.Date(date), book = ret_net)]
bmt <- as.data.table(bt$benchmark_returns)[, .(date = as.Date(date), bm = benchmark_ret)]
pan <- fread(PANEL_CSV)
## 컬럼 정규화 (extend_nolayer4_series 와 동일 — 파생 아님, 단순 rename):
## WT-H rerun 패널은 beta_R05_V5 / m4_weight_lag 명명. 구 faith 패널(beta_R05/m4)과 동치.
if ("beta_R05_V5"   %in% names(pan) && !("beta_R05" %in% names(pan))) setnames(pan, "beta_R05_V5",   "beta_R05")
if ("m4_weight_lag" %in% names(pan) && !("m4"       %in% names(pan))) setnames(pan, "m4_weight_lag", "m4")
stopifnot(all(c("beta_R05", "m4") %in% names(pan)))
pan[, anchor_date := as.Date(anchor_date)]
pan <- pan[, .(date = anchor_date, realized_ym, regime, beta_R05, m4)]
pan[, invested := beta_R05 * m4]                       # 배포 의도 노출 (manifest)
d <- Reduce(function(a, b) merge(a, b, by = "date", all = FALSE), list(pr, bmt, pan))
setorder(d, date)
N <- nrow(d)
stopifnot(N >= 100)
cat(sprintf("[load] N=%d  %s ~ %s  recon=%s\n", N, d$date[1], d$date[N], basename(RECON_RDS)))

bk <- d$book; bm <- d$bm

## ---- 2. dlm TV-beta walk-forward filter (kalman_ext.R §[3] 재사용, filtered only) ----
build_reg <- function(parm) {
  m <- dlmModReg(X = X_hist, addInt = TRUE, dV = exp(parm[1]))
  diag(m$W) <- c(exp(parm[2]), exp(parm[3])); m
}
beta_hat <- rep(NA_real_, N)
a0 <- bk - bm
last_par3 <- c(log(var(a0[1:24])), log(1e-5), log(1e-4))
for (t in (BURN + 1):N) {
  ## monitoring vintage @ t월 마감: 정보셋 = 1..t (미래 없음). MLE는 stride마다 재추정.
  if (((t - (BURN + 1)) %% STRIDE) == 0) {
    X_hist <- bm[1:t]
    fit3 <- tryCatch(
      dlmMLE(bk[1:t], parm = last_par3, build = build_reg,
             method = "L-BFGS-B", lower = rep(-25, 3), upper = rep(2, 3),
             control = list(maxit = 120)),
      error = function(e) NULL)
    if (!is.null(fit3) && fit3$convergence == 0) last_par3 <- fit3$par
  }
  X_hist <- bm[1:t]
  filt <- tryCatch(dlmFilter(bk[1:t], build_reg(last_par3)), error = function(e) NULL)
  if (is.null(filt)) next
  beta_hat[t] <- as.numeric(filt$m[nrow(filt$m), 2])   # filtered β_{t|t} — 스무더 아님
}
cat(sprintf("[filter] β̂ 가용 %d/%d개월 (t=%d..%d)  현 vintage β̂=%.4f\n",
            sum(is.finite(beta_hat)), N, BURN + 1, N, beta_hat[N]))

## ---- 3. gap + trailing-12m z(당월 제외) + 2개월 연속 WARN ----
d[, beta_hat := beta_hat]
d[, gap := abs(beta_hat - invested)]
z <- rep(NA_real_, N)
for (i in seq_len(N)) {
  if (i <= Z_WIN) next
  w <- d$gap[(i - Z_WIN):(i - 1)]
  if (all(is.finite(w)) && is.finite(d$gap[i]) && sd(w) > 0)
    z[i] <- (d$gap[i] - mean(w)) / sd(w)
}
d[, z_gap := z]
d[, warn := is.finite(z_gap) & is.finite(shift(z_gap, 1)) &
             z_gap > Z_THRESH & shift(z_gap, 1) > Z_THRESH]
d[is.na(warn), warn := FALSE]

## ---- 4. 당월 manifest 주석 (book_state live_exposure_change — 있으면, 정보용) ----
find_key <- function(x, key) {
  if (is.list(x)) {
    if (!is.null(names(x)) && key %in% names(x)) return(x[[key]])
    for (el in x) { r <- find_key(el, key); if (!is.null(r)) return(r) }
  }
  NULL
}
cur_manifest <- NULL
bs <- tryCatch(fromJSON(BOOK_STATE, simplifyVector = FALSE), error = function(e) NULL)
if (!is.null(bs)) {
  lec <- find_key(bs, "live_exposure_change")
  if (!is.null(lec) && !is.null(lec$noL4_invested)) {
    bh_last <- tail(beta_hat[is.finite(beta_hat)], 1)
    cur_manifest <- list(
      source = "book_state.json::live_exposure_change (당월 standing manifest)",
      invested_now = as.numeric(lec$noL4_invested),
      beta_hat_latest = bh_last,
      gap_vs_beta_hat_latest = abs(bh_last - as.numeric(lec$noL4_invested)),
      note = "정보용 주석 — 경보 판정은 실현월 시계열(z 규칙)로만")
  }
}

## ---- 5. 저장 + 콘솔 요약 ----
ser <- d[, .(date, realized_ym, regime, m4, beta_R05, invested, beta_hat, gap, z_gap, warn)]
fwrite(ser, file.path(OUT_DIR, "kalman_beta_drift_series.csv"))
iN <- max(which(is.finite(d$beta_hat)))
warn_hist <- d[warn == TRUE, realized_ym]
kbd_result <- list(
  as_of  = format(Sys.Date()),
  book   = "STR_1715_on_M4_R05_noLayer4_PG2",
  metric_type = "backtested",
  basis  = "recon_backtested read-only · monitoring diagnostic (book 무변경)",
  method = "dlm TV-beta filtered beta_{t|t} (te_diag_202607/kalman_ext.R [3] 재사용; dlmMLE stride-12 walk-forward 확장창·과거만; dlmFilter only — 스무더 금지 PIT)",
  rule   = "z_t=(gap_t−mean(gap_{t−12..t−1}))/sd(gap_{t−12..t−1}); z>2 2개월 연속 → WARN '오버레이 실효-의도 괴리' (자동조치 없음·임계 sweep 금지)",
  params_fixed = list(z_thresh = Z_THRESH, z_window_months = Z_WIN,
                      consecutive = CONSEC, burn = BURN, mle_stride = STRIDE),
  n_months = N,
  latest = list(month = d$realized_ym[iN], date = format(d$date[iN]),
                beta_hat = d$beta_hat[iN], invested = d$invested[iN],
                gap = d$gap[iN], z = d$z_gap[iN],
                z_prev = if (iN > 1) d$z_gap[iN - 1] else NA_real_,
                warn = isTRUE(d$warn[iN])),
  warn_active = isTRUE(d$warn[iN]),
  warn_months_history = as.list(as.character(warn_hist)),
  current_manifest = cur_manifest,
  series_csv = "qepm/mailbox/monitoring/kalman_beta_drift/kalman_beta_drift_series.csv",
  inputs = list(recon_rds = RECON_RDS, panel_csv = PANEL_CSV))
write_json(kbd_result, file.path(OUT_DIR, "kalman_beta_drift_latest.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)
write_json(kbd_result,
           file.path(OUT_DIR, sprintf("kalman_beta_drift_%s.json", format(Sys.Date(), "%Y%m"))),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)

cat(sprintf("\n[kbd] latest %s: β̂=%.4f invested=%.4f gap=%.4f z=%.3f z_prev=%.3f → WARN=%s\n",
            d$realized_ym[iN], d$beta_hat[iN], d$invested[iN], d$gap[iN],
            ifelse(is.finite(d$z_gap[iN]), d$z_gap[iN], NA),
            ifelse(iN > 1 && is.finite(d$z_gap[iN - 1]), d$z_gap[iN - 1], NA),
            ifelse(isTRUE(d$warn[iN]), "YES — '오버레이 실효-의도 괴리'", "no")))
if (length(warn_hist)) cat("[kbd] 역사적 WARN 월:", paste(warn_hist, collapse = ", "), "\n")
if (!is.null(cur_manifest))
  cat(sprintf("[kbd] 당월 standing manifest 주석: invested_now=%.4f vs β̂_latest=%.4f (gap=%.4f, 정보용)\n",
              cur_manifest$invested_now, cur_manifest$beta_hat_latest,
              cur_manifest$gap_vs_beta_hat_latest))
cat("[DONE] outputs →", OUT_DIR, "\n")
