## ============================================================================
## te_baseline_ewma.R — 월간 monitoring 입력: TE 예측 기준선 = EWMA(λ=0.97)
## (task #63 배선, 도훈 승인 2026-07-13 — 선례 kalman_beta_drift.R(#56)/filing_delay_watch.R(#61) 구조 승계)
## book·전략 무변경 — monitoring TE ratio의 '예측 기준선(분모)' 교체만. TE 정의 무수정.
##
## 근거 (stage_artifacts/te_diag_202607, task #47 진단):
##   - 현행 문제: 예측 기준선 = full-sample TE(0.1898) → trail21(0.3324) 대비 ratio 1.751 ALERT.
##     full-sample 분모는 melt-up 국면(2025+)을 반영 못하는 구조적 과소예측.
##   - walk-forward 257회 평가(walkforward_estimator_eval.csv, 후보 5종 PIT past-only):
##     ewma97 최우수 — realized/predicted 1.1031(최교정) · z>1 비율 0.2763 · 1.5배 오경보율 0.0325
##     (expand_const 1.1973/0.2996/0.0610 · regime_cond 1.2905 과소예측 최악)
##
## 구현 (te_decompose.R §F ewma_sig 재사용 — 재발명 금지):
##   v_init = var(a[1:12])  (초기 12개월 표본분산)
##   t = 13..N:  v_t = λ·v_{t-1} + (1-λ)·a_{t-1}²  →  σ̂_t = sqrt(v_t)   # PIT: t-1까지만
##   현행 예측 기준선 = σ̂_N·sqrt(12)  (walk-forward 평가와 동일 convention:
##     당월 a_N 미포함 1-step-ahead — walkforward_estimator_eval의 current_TE_forecast_ann)
##   계열 a = recon net-active (contract-authoritative rds: period_returns$ret_net − benchmark_ret)
##
## 경보 규칙 (기존 값 유지 — 문턱 sweep 금지):
##   te_ratio = realized_te(trail21) / te_baseline_pred_ann(ewma97)
##   te_ratio > 1.5 → "risk_underestimate" ALERT (자동조치 없음 — Risk Agent 재추정 요청 로그)
##
## 정직 라벨:
##   - 교체 대상 = '예측 기준선(분모)'. TE 정의(sd(active)·sqrt(12))는 불변.
##   - 구 full-sample 기준선은 te_baseline_legacy_fullsample로 병기 (비교 가능성 유지).
##   - realized TE = backtested(recon 계약-authoritative) / 예측 기준선 = estimated(walk-forward 검증).
##
## 실행: 월간 monitoring agent가 source 패턴으로 실행
##   cd 02_Infrastructure/reports && Rscript -e 'source("te_baseline_ewma.R")'
## 산출: qepm/observability/te_baseline_latest.json + 월 아카이브 json + 콘솔 요약
## 규율: 단일스레드 · 파일 source(한글 -e 회피) · OneDrive 쓰기 temp-rename · rds read-only 소비.
## ============================================================================
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite)
}))
setDTthreads(1)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
## recon net-active 원천 (contract-authoritative — te_diag/monitoring_report_202607과 동일 rds.
##  북 recon 재산출 시 이 상수만 최신 bt_result rds로 교체)
BT_RDS  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
DIAG_JSON <- file.path(ROOT, "stage_artifacts/te_diag_202607/te_diag_summary.json")  # provenance soft-check용
OUT_DIR <- file.path(ROOT, "qepm/observability")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

## 사전 고정 파라미터 — sweep/조정 금지 (변경은 도훈 mandate 필요)
LAMBDA        <- 0.97   # walk-forward 최우수 (te_diag 실측 — 상단 header)
INIT_M        <- 12L    # EWMA 초기화: 첫 12개월 표본분산 (te_decompose.R §F frozen)
TE_RATIO_THRESH <- 1.5  # 기존 ALERT 문턱 유지 (monitoring_init.md — sweep 금지)
TRAIL_M       <- 21L    # realized TE 창 (기존 monitoring 진단과 동일)

check_date <- Sys.Date()

## ---- 1. recon net-active 계열 로드 (read-only) ------------------------------
bt <- readRDS(BT_RDS)
pr <- as.data.table(bt$period_returns)[, .(date = as.Date(date), book = ret_net)]
bm <- as.data.table(bt$benchmark_returns)[, .(date = as.Date(date), bm = benchmark_ret)]
d  <- merge(pr, bm, by = "date", all = FALSE)
setorder(d, date)
a  <- d$book - d$bm                      # recon net-active (월간)
N  <- length(a)
stopifnot(N >= INIT_M + TRAIL_M)         # 초기화 12m + trail21 미만이면 산출 불가
te_ann <- function(x) sd(x, na.rm = TRUE) * sqrt(12)
cat(sprintf("[load] recon net-active n=%d  %s ~ %s  (rds=%s)\n",
            N, format(min(d$date)), format(max(d$date)), basename(BT_RDS)))

## ---- 2. EWMA(λ=0.97) 재귀 (te_decompose.R §F ewma_sig 그대로 — PIT t-1) -----
s <- rep(NA_real_, N)
v <- var(a[1:INIT_M])
for (t in (INIT_M + 1L):N) { v <- LAMBDA * v + (1 - LAMBDA) * a[t - 1L]^2; s[t] <- sqrt(v) }
te_pred_ewma97 <- s[N] * sqrt(12)        # 현행 예측 기준선 (당월 a_N 미포함 — eval convention)
## 진단용(게이트 미사용): 당월 포함 다음-vintage 예측 — 다음 달 monitoring의 s[N]에 해당
te_pred_next_diag <- sqrt(LAMBDA * v + (1 - LAMBDA) * a[N]^2) * sqrt(12)

## ---- 3. realized TE + ratio (신/구 병기) ------------------------------------
idx21 <- (N - TRAIL_M + 1L):N
te_real_trail21 <- te_ann(a[idx21])
te_real_trail12 <- te_ann(a[(N - 11L):N])
te_real_trail36 <- te_ann(a[(N - 35L):N])
te_legacy_full  <- te_ann(a)             # 구 예측 기준선 (병기 — 비교 가능성 유지)

te_ratio        <- te_real_trail21 / te_pred_ewma97   # 신 기준선 ratio (authoritative)
te_ratio_legacy <- te_real_trail21 / te_legacy_full   # 구 기준선 ratio (병기)
alert_new    <- te_ratio        > TE_RATIO_THRESH
alert_legacy <- te_ratio_legacy > TE_RATIO_THRESH

## ---- 4. provenance soft-check (te_diag 동일-vintage 대조 — 실패해도 run 유지) ----
diag_check <- tryCatch({
  if (file.exists(DIAG_JSON)) {
    dj <- fromJSON(DIAG_JSON)
    ref_ewma97 <- dj$estimator_eval$current_TE_forecast_ann[dj$estimator_eval$estimator == "ewma97"]
    chk <- list(diag_as_of = dj$as_of,
                delta_full    = te_legacy_full  - dj$te_authoritative$full,
                delta_trail21 = te_real_trail21 - dj$te_authoritative$trail21,
                delta_ewma97  = te_pred_ewma97  - ref_ewma97,
                note = "동일 rds vintage면 delta≈0 기대. rds 연장 시 delta 발생은 정상(신선 데이터) — 참조값은 2026-07-13 진단 고정")
    if (max(abs(c(chk$delta_full, chk$delta_trail21, chk$delta_ewma97))) > 5e-4)
      cat(sprintf("[note] te_diag(as_of %s) 대비 delta: full %+.4f / trail21 %+.4f / ewma97 %+.4f — rds vintage 차이 여부 확인\n",
                  dj$as_of, chk$delta_full, chk$delta_trail21, chk$delta_ewma97))
    chk
  } else list(note = "te_diag_summary.json 부재 — soft-check 생략 (계산은 자립적)")
}, error = function(e) list(note = paste("soft-check 실패:", conditionMessage(e))))

## ---- 5. JSON 저장 (OneDrive temp-rename) + 콘솔 요약 ------------------------
teb_result <- list(
  as_of = format(check_date),
  book  = "STR_1715_on_M4_R05_noLayer4_PG2",
  basis = "recon net-active (contract-authoritative bt_result rds) read-only 소비 · monitoring TE 예측 기준선",
  baseline_estimator = "ewma97",
  lambda = LAMBDA,
  honest_label = list(
    scope = "교체 대상 = 예측 기준선(분모)이지 TE 정의 아님. TE 정의 sd(active)*sqrt(12) 불변",
    metric_type_realized = "backtested (recon 계약-authoritative rds 파생, 표준 sd)",
    metric_type_baseline = "estimated (walk-forward 257회 PIT 평가 검증 예측치)"),
  ewma_detail = list(
    recursion = "v_t = lambda*v_(t-1) + (1-lambda)*a_(t-1)^2 ; sigma_t = sqrt(v_t) — PIT: t-1까지만",
    init = sprintf("v_init = var(a[1:%d]) 표본분산 — 초기 %d개월은 예측 미정의(NA)", INIT_M, INIT_M),
    forecast_convention = "기준선 = sigma_N*sqrt(12), 당월 a_N 미포함 1-step-ahead (walkforward eval current_TE_forecast_ann 동일 convention)",
    source_impl = "stage_artifacts/te_diag_202607/te_decompose.R §F ewma_sig 재사용 (재발명 금지)",
    next_vintage_diag_ann = te_pred_next_diag),
  series = list(source_rds = BT_RDS, n_months = N,
                start = format(min(d$date)), end = format(max(d$date)),
                trail21_window = paste(format(d$date[idx21[1]]), "~", format(d$date[N]))),
  te_baseline_pred_ann = te_pred_ewma97,
  te_baseline_legacy_fullsample = te_legacy_full,
  te_realized_trail21_ann = te_real_trail21,
  te_realized_trail12_ann = te_real_trail12,
  te_realized_trail36_ann = te_real_trail36,
  te_ratio = te_ratio,
  te_ratio_legacy_fullsample = te_ratio_legacy,
  te_ratio_threshold = TE_RATIO_THRESH,
  te_underestimate_alert = alert_new,
  te_underestimate_alert_legacy = alert_legacy,
  rule = sprintf("te_ratio > %.1f → 'risk_underestimate' ALERT (Risk Agent 재추정 요청 로그 — 자동조치 없음·문턱 sweep 금지)", TE_RATIO_THRESH),
  walkforward_provenance = list(
    eval_csv = "stage_artifacts/te_diag_202607/walkforward_estimator_eval.csv",
    n_eval = 257,
    ewma97 = list(realized_over_pred = 1.103133, pct_z_gt1 = 0.276265, alert_1p5_rate = 0.03252),
    legacy_expand_const = list(realized_over_pred = 1.197347, pct_z_gt1 = 0.299611, alert_1p5_rate = 0.060976),
    note = "후보 5종(expand_const/roll36/ewma94/ewma97/regime_cond) 중 ewma97 최우수 — task #47 진단 실측"),
  diag_reference_check = diag_check)

write_json_atomic <- function(obj, path) {   # OneDrive temp-rename 패턴
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  write_json(obj, tmp, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
  if (file.exists(path)) file.remove(path)
  invisible(file.rename(tmp, path))
}
write_json_atomic(teb_result, file.path(OUT_DIR, "te_baseline_latest.json"))
write_json_atomic(teb_result, file.path(OUT_DIR, sprintf("te_baseline_%s.json", format(check_date, "%Y%m"))))

cat(sprintf("\n[teb] TE 예측 기준선 (baseline_estimator=ewma97, lambda=%.2f):\n", LAMBDA))
cat(sprintf("   신 기준선 (ewma97)          = %.4f\n", te_pred_ewma97))
cat(sprintf("   구 기준선 (full-sample 병기) = %.4f  [te_baseline_legacy_fullsample]\n", te_legacy_full))
cat(sprintf("   realized trail21            = %.4f  (창 %s)\n", te_real_trail21, teb_result$series$trail21_window))
cat(sprintf("   te_ratio (신)  = %.4f  → ALERT(>%.1f) = %s\n", te_ratio, TE_RATIO_THRESH, ifelse(alert_new, "TRUE", "FALSE")))
cat(sprintf("   te_ratio (구)  = %.4f  → ALERT(>%.1f) = %s  [병기]\n", te_ratio_legacy, TE_RATIO_THRESH, ifelse(alert_legacy, "TRUE", "FALSE")))
cat(sprintf("   (진단) 당월포함 다음-vintage 예측 = %.4f — 게이트 미사용\n", te_pred_next_diag))
cat("[DONE] outputs →", OUT_DIR, "\n")
