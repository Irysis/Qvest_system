## ============================================================================
## extend_nolayer4_series.R — noLayer4 오버레이-시리즈 확장 (월간 페이퍼 트래킹 연료)
## 도훈 지시 2026-07-03. FaithTrend run_layer5_faith_overlay.R 자리(Layer4 제거)를 채운다.
##
## 목적: 매월 base 오버레이 패널(β_R05/m4/ret_orig)이 새 실현월까지 연장되면,
##   그것을 β_faith 없이 noLayer4 수익으로 재계산해 monitor가 소비할 시리즈로 저장.
##   → monitor_nolayer4_paper.R가 "신규 실현월"을 감지하고 paper_nav에 append.
##
## ★오버레이 수익 공식 (명시식, self-synth 금지 — recompute_bt_noLayer4_clean.R canonical과 동일):
##   ret_noLayer4[m] = beta_R05[m] × m4[m] × ret_orig[m] − |Δbeta_R05[m]| × 0.0015
##   (β_faith·β_AR 제거. per-layer canonical cost = |Δβ_R05|×15bps. Layer4 미적용.)
##
## ★단일-vintage 재계산 원칙 (어제 07-02 캐시 tipping 버그 #4 방어):
##   materialized 03_period_returns.csv의 옛 행과 새 행을 블렌딩하지 않는다.
##   전체 시리즈를 *현재 refresh된 base 패널 1개 vintage*에서 통째 재계산 →
##   마지막 달 β_R05 tipping(0.62 vintage vs 0.50 현재) 같은 조용한 불연속 원천 차단.
##
## ★realized_ym 정렬 (어제 최대 버그 #1 방어):
##   realized_ym = 리밸/장부 기록월(내부 join key, = substr(anchor_date,1,7)) — slot 2-3 컨벤션.
##   return_ym  = 진짜 수익 달력월(= realized_ym-1). 외부 시계열(벤치/팩터) 조인은 return_ym.
##   add_return_ym + assert_panel_alignment(β vs KOSPI200 on return_ym ≥0.5)로 hard-abort 가드.
##
## 출력: 06_Registry/live_track/STR_1715_on_M4_R05_noLayer4_PG2/live_book_series.csv
##   (05_Production 정적코드/데이터 미수정 — live_track write. monitor가 이걸 우선 읽음.)
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
COST <- 0.0015
BOOK_ID <- "STR_1715_on_M4_R05_noLayer4_PG2"
LT  <- file.path(ROOT, "06_Registry/live_track", BOOK_ID)
dir.create(LT, showWarnings = FALSE, recursive = TRUE)
OUT <- file.path(LT, "live_book_series.csv")

cat("============================================================\n")
cat("[extend_nolayer4_series] noLayer4 오버레이 시리즈 재계산 (단일 vintage)\n")
cat("============================================================\n")

## --- 1. base 오버레이 패널 로드 (β_R05/m4/ret_orig/regime per realized_ym) ---
## 우선순위: WT-H rerun 산출(가장 신선, run_layer5_rerun_extended.R) > 2-2 faith 패널(동일 base) > 2-1 사본.
## 세 소스 모두 동일 STR_1715/M4/R05 base 공유 — beta_R05_V5 == faith beta_R05 검증됨(alignment verify [A]).
cand <- c(
  file.path(ROOT, "qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"),
  file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"),
  file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
)
base_path <- cand[file.exists(cand)][1]
if (is.na(base_path)) stop("[extend] base 오버레이 패널 부재 — run_layer5_rerun_extended.R 선행 필요.")
cat(sprintf("[1] base 패널: %s\n", sub(ROOT, "", base_path, fixed = TRUE)))
p <- fread(base_path)

## 컬럼 정규화: 세 소스 컬럼명 차이 흡수 → beta_R05 / m4 / ret_orig / regime / realized_ym / anchor_date
## (WT-H/2-1: beta_R05_V5·m4_weight_lag / 2-2 faith: beta_R05·m4). ★파생 아님 — 단순 rename.
if ("beta_R05_V5" %in% names(p) && !("beta_R05" %in% names(p))) setnames(p, "beta_R05_V5", "beta_R05")
if ("m4_weight_lag" %in% names(p) && !("m4" %in% names(p)))     setnames(p, "m4_weight_lag", "m4")
need <- c("realized_ym", "anchor_date", "regime", "ret_orig", "beta_R05", "m4")
miss <- setdiff(need, names(p))
if (length(miss)) stop(sprintf("[extend] base 패널 필수 컬럼 부재: %s", paste(miss, collapse = ", ")))

p <- p[is.finite(ret_orig)]
p[, anchor_date := as.Date(anchor_date)]
setorder(p, realized_ym)                         # ★shift 전 정렬 필수 (시간순)
cat(sprintf("    %d개월  %s ~ %s\n", nrow(p), p$realized_ym[1], p$realized_ym[.N]))

## --- 2. noLayer4 수익 재계산 (명시식, β_faith 제거) ---
## ★by-group 미사용(버그 #5): shift는 정렬된 컬럼에 직접, 결과는 := 컬럼 승격 후 사용.
p[, dR05 := abs(beta_R05 - shift(beta_R05, 1, fill = 1.0))]      # Δβ_R05 (전월 대비, 첫달 fill=1.0)
p[, ret_noLayer4 := beta_R05 * m4 * ret_orig - dR05 * COST]      # β_faith·β_AR 곱 없음 = Layer4 제거
cat("[2] ret_noLayer4 = beta_R05 × m4 × ret_orig − |Δbeta_R05|×0.0015  (β_faith 제거 확인)\n")

## sanity: β_faith가 곱해졌다면 CAUTION/CRISIS 달에서 값이 더 작아짐. 대조로 ret_L5_faith 있으면 병기(진단).
if ("ret_L5_faith" %in% names(p)) {
  d_last <- tail(p[, .(realized_ym, ret_noLayer4, ret_L5_faith)], 3)
  cat("    (진단) 최근 3개월 noLayer4 vs faith(β_faith 곱) — noLayer4가 faith 이상이어야 정상:\n")
  print(d_last)
}

## --- 3. return_ym 부여 + 정렬 가드 (어제 버그 #1 물리 차단) ---
cat("[3] add_return_ym + assert_panel_alignment (return_ym β vs KOSPI200 ≥0.5)\n")
source(file.path(ROOT, "02_Infrastructure/contracts/panel_alignment_guard.R"))
p <- add_return_ym(p)                            # realized_ym / return_ym(=realized_ym-1)
b_ret <- assert_panel_alignment(p, ret_col = "ret_orig", min_beta = 0.5)   # <0.5면 stop

## --- 4. slot 2-3 컨벤션 시리즈 저장 (03_period_returns.csv 미러 shape) ---
## realized_ym = substr(anchor_date,1,7) 이어야 slot 2-3와 동일 (내부 join key).
p[, ry_from_anchor := substr(as.character(anchor_date), 1, 7)]
mism <- p[realized_ym != ry_from_anchor]
if (nrow(mism)) {
  cat(sprintf("[warn] realized_ym != substr(anchor_date,1,7) %d행 — base 패널 라벨 컨벤션 확인:\n", nrow(mism)))
  print(head(mism[, .(realized_ym, anchor_date, ry_from_anchor)], 5))
}
p[, ry_from_anchor := NULL]

out <- p[, .(
  date        = anchor_date,           # slot 2-3 'date' = anchor_date (리밸일)
  realized_ym,                         # = substr(date,1,7), 내부 join key (monitor가 읽음)
  return_ym,                           # 진짜 수익 달력월 (외부조인용)
  regime,
  ret_net     = ret_noLayer4,          # monitor가 'ret_net' 컬럼을 읽음 (slot 2-3 shape)
  ret_orig, beta_R05, m4, dR05
)]
setorder(out, realized_ym)
out[, book_id := BOOK_ID]
out[, cost_model_version := "v2.4_kr_retail_15bps_perlayer"]
out[, metric_type := "backtested"]
out[, generated := as.character(Sys.time())]
out[, base_panel := sub(ROOT, "", base_path, fixed = TRUE)]

fwrite(out, OUT)
cat(sprintf("[4] 저장: %s  (%d개월, %s ~ %s)\n", sub(ROOT, "", OUT, fixed = TRUE),
            nrow(out), out$realized_ym[1], out$realized_ym[.N]))

## --- 5. 시리즈 헤드라인 (진단, PerformanceAnalytics 표준함수) ---
xr <- xts(out$ret_net, order.by = out$date)
sr  <- as.numeric(table.AnnualizedReturns(xr, scale = 12)[3, 1])
mdd <- as.numeric(maxDrawdown(xr))
cat(sprintf("[5] 시리즈 헤드라인: SR(geo)=%.3f | MDD=%.1f%% | n=%d | return_ym β(KOSPI200)=%.3f\n",
            sr, mdd * 100, nrow(out), ifelse(is.na(b_ret), NA_real_, b_ret)))
cat("    (참고: judge 확정 SR_geo 1.898 — 동일 vintage면 근사. 신규월 연장 시 소폭 변동 정상)\n")
cat("[DONE] extend_nolayer4_series\n")
