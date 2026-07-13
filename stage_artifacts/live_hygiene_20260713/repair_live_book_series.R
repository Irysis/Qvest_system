## ============================================================================
## repair_live_book_series.R — 라이브 데이터 위생 수리 task #48 item 1 (2026-07-13)
##
## 대상: 06_Registry/live_track/STR_1715_on_M4_R05_noLayer4_PG2/live_book_series.csv
## 문제: 2026-06 ret_net 0.0582(live_book_series, 07-03 extend 재계산) vs
##       0.0724(계약-authoritative bt_result_C_noL4_CLEAN_ann12.rds) — monitoring 202607 +
##       TE 진단(te_diag_202607) 2회 연속 플래그.
## 원인(실측 추적):
##   - rds(07-02 19:51 build)의 입력 faith 패널 vintage에서는 m4 매핑
##     (stage_artifacts/WT-D20260430_001_m4_extended.csv)에 ym 2026-06 행이 아직 없어
##     merge all.x → NA → fill 1.0 (run_layer5_rerun_extended.R L131 NA-fill).
##   - 07-02 07:31 매핑이 2026-07-01까지 연장된 뒤 07-03 09:00/12:57 패널 재생성에서
##     m4_weight_lag(2026-06) = 0.8064(2026-05-04 행 weight의 lag)로 실측치 유입.
##   - β_R05(0.5)·ret_orig(0.14630390007501) 동일 — m4 vintage 1.0→0.8064 flip 단독 원인.
##     0.5×1.0×0.146304−0.5×0.0015 = 0.072401950037505 (rds/slot2-3 materialized와 exact)
##     0.5×0.8064×0.146304−0.5×0.0015 = 0.058239732510244 (구 live_book_series와 exact)
##
## 수리 원칙 (전략 변경 아님 — 기록·배관 정합):
##   - ret_net = 계약 rds period_returns$ret_net 그대로 (재계산·자체합성 없음).
##   - 구 extend 재계산치는 ret_net_panel_recompute 진단 컬럼으로 보존.
##   - book_state/holdout_interval/rds 원본 무수정. 구 파일은 .bak_20260713 백업.
## 산출: monthly_delta.csv (전 구간 old vs rds 전수 대조) + 재생성 live_book_series.csv
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})
data.table::setDTthreads(1L)

ROOT    <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
BOOK_ID <- "STR_1715_on_M4_R05_noLayer4_PG2"
LT      <- file.path(ROOT, "06_Registry/live_track", BOOK_ID)
SER     <- file.path(LT, "live_book_series.csv")
RDS     <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
MAT     <- file.path(ROOT, "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results/03_period_returns.csv")
OUTD    <- file.path(ROOT, "stage_artifacts/live_hygiene_20260713")
dir.create(OUTD, showWarnings = FALSE, recursive = TRUE)

cat("============================================================\n")
cat("[repair] live_book_series.csv <- 계약 rds 기준 재생성 (task #48 item 1)\n")
cat("============================================================\n")

## --- 0. 백업 (기존 파일 무손실 보존) ---
stopifnot(file.exists(SER), file.exists(RDS))
bak <- paste0(SER, ".bak_20260713")
if (!file.exists(bak)) {
  stopifnot(file.copy(SER, bak, copy.date = TRUE))
  cat(sprintf("[0] 백업: %s\n", basename(bak)))
} else cat("[0] 백업 이미 존재 — 재백업 생략 (원본 보존 우선)\n")

## 재실행 idempotent: 백업(.bak = 구 vintage)이 있으면 그것을 old로 사용 —
## 수리 후 재실행 시 delta 표가 "수리본 vs rds"(전부 MATCH)로 덮이는 것 방지.
old <- fread(if (file.exists(bak)) bak else SER)
old[, date := as.Date(date)]
cat(sprintf("    구 시리즈: %d행  %s ~ %s\n", nrow(old), old$realized_ym[1], old$realized_ym[nrow(old)]))

## --- 1. 계약-authoritative rds 로드 ---
bt <- readRDS(RDS)
pr <- as.data.table(bt$period_returns)
pr[, date := as.Date(date)]
setorder(pr, date)
cat(sprintf("[1] rds period_returns: %d행  %s ~ %s (run_id %s)\n",
            nrow(pr), min(pr$date), max(pr$date), pr$run_id[1]))
stopifnot(nrow(pr) == 269L)

## --- 2. 전 구간 전수 대조 (old vs rds) → monthly_delta.csv ---
cmp <- merge(
  old[, .(date, realized_ym, return_ym, regime,
          ret_net_old = ret_net, beta_R05_old = beta_R05, m4_old = m4, ret_orig_old = ret_orig)],
  pr[, .(date, ret_net_rds = ret_net)],
  by = "date", all = TRUE)
cmp[, delta := ret_net_old - ret_net_rds]
cmp[, flag  := fifelse(!is.finite(delta), "MISSING_SIDE",
               fifelse(abs(delta) > 1e-12, "DIVERGENT", "MATCH"))]
setorder(cmp, date)
fwrite(cmp, file.path(OUTD, "monthly_delta.csv"))
n_match <- sum(cmp$flag == "MATCH"); n_div <- sum(cmp$flag == "DIVERGENT"); n_miss <- sum(cmp$flag == "MISSING_SIDE")
cat(sprintf("[2] 전수 대조: n=%d | MATCH=%d | DIVERGENT=%d | MISSING_SIDE=%d → monthly_delta.csv\n",
            nrow(cmp), n_match, n_div, n_miss))
if (n_div + n_miss > 0) { cat("    비-MATCH 행:\n"); print(cmp[flag != "MATCH"]) }

## --- 3. 재생성: 구 shape 유지 + ret_net = rds (진단 컬럼 병기) ---
new <- merge(old, pr[, .(date, ret_net_rds = ret_net)], by = "date", all.x = TRUE)
stopifnot(nrow(new) == nrow(old), !anyNA(new$ret_net_rds))   # rds가 전 월 커버 필수
new[, ret_net_panel_recompute := ret_net]                    # 구 extend 재계산치 보존(진단)
new[, ret_net := ret_net_rds][, ret_net_rds := NULL]
new[, ret_net_source := "bt_result_C_noL4_CLEAN_ann12.rds(contract-authoritative, WT-D20260702_002)"]
new[, repair_note := fifelse(abs(ret_net - ret_net_panel_recompute) > 1e-12,
      "vintage divergence: rds vintage m4 != current panel m4 (repair task #48 — see stage_artifacts/live_hygiene_20260713/repair_log.md)", "")]
new[, generated := NULL]                                     # fread가 POSIXct로 파싱 — 문자열 재생성
new[, generated := as.character(Sys.time())]
setorder(new, date)
setcolorder(new, c("date", "realized_ym", "return_ym", "regime", "ret_net"))

## --- 4. 정렬 가드 재검증 (extend_nolayer4_series.R와 동일 가드, ret_orig 기준) ---
source(file.path(ROOT, "02_Infrastructure/contracts/panel_alignment_guard.R"))
b_ret <- assert_panel_alignment(new, ret_col = "ret_orig", min_beta = 0.5)   # <0.5면 stop

## --- 5. 교차 검증: slot 2-3 materialized(rds 승격본)와 parity ---
if (file.exists(MAT)) {
  mat <- fread(MAT)
  mm <- merge(new[, .(date, ret_net)], mat[, .(date = as.Date(date), ret_mat = as.numeric(ret_net))], by = "date")
  cat(sprintf("[5] parity vs slot2-3 materialized: n=%d  max|dif|=%.3e\n",
              nrow(mm), max(abs(mm$ret_net - mm$ret_mat))))
  stopifnot(max(abs(mm$ret_net - mm$ret_mat)) < 1e-12)
} else cat("[5][warn] slot2-3 materialized 부재 — parity 생략\n")

## --- 6. 저장 + 헤드라인 (PerformanceAnalytics 표준함수만, 진단) ---
fwrite(new, SER)
xr     <- xts(new$ret_net, order.by = new$date)
SR_geo <- as.numeric(table.AnnualizedReturns(xr, scale = 12)[3, 1])
mdd    <- as.numeric(maxDrawdown(xr))
cat(sprintf("[6] 저장: %s (%d행)\n", SER, nrow(new)))
cat(sprintf("    헤드라인(진단): SR_geo=%.3f [judge 확정 1.898] | MDD=%.1f%% | return_ym beta=%.3f\n",
            SR_geo, mdd * 100, ifelse(is.na(b_ret), NA_real_, b_ret)))

## --- 7. meta json ---
write_json(list(
  task = "live_hygiene_20260713_item1", repaired = "live_book_series.csv",
  book_id = BOOK_ID,
  authoritative_source = "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds",
  backup = basename(bak),
  n_months = nrow(new), n_match = n_match, n_divergent = n_div, n_missing_side = n_miss,
  divergent_months = cmp[flag == "DIVERGENT", as.character(realized_ym)],
  max_abs_delta = suppressWarnings(max(abs(cmp$delta), na.rm = TRUE)),
  sr_geo_headline = round(SR_geo, 4), judge_ref_sr_geo = 1.898,
  metric_type = "backtested(contract rds passthrough)",
  generated = as.character(Sys.time())),
  file.path(OUTD, "repair_meta_item1.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[DONE] repair_live_book_series\n")
