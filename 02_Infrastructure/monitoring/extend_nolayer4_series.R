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
## ── 출력 레인 = admitted 북 (도훈 mandate 2026-08-01 하드코딩 제거) ─────────────
##   구판: BOOK_ID 를 구 슬롯 2-3 id 로 고정 → 2026-07-19 D3 swap-in 이후 이 스크립트는
##   구 레인에만 쓰고, monitor(admitted 레인을 읽음)는 07-19 에 멈춘 사본을 봤다 —
##   시리즈가 최신인데 결손으로 보이는 어긋남의 원인.
source(file.path(ROOT, "02_Infrastructure/portfolio/resolve_admitted_slot.R"))
PRIOR_BOOK_ID <- "STR_1715_on_M4_R05_noLayer4_PG2"
.slotres <- tryCatch(resolve_admitted_slot(root = ROOT, fallback_id = PRIOR_BOOK_ID),
                     error = function(e) NULL)
BOOK_ID  <- if (!is.null(.slotres)) .slotres$id else PRIOR_BOOK_ID
if (is.null(.slotres)) cat(sprintf("[extend][WARN] admitted 해석 실패 — 구 레인 %s 폴백\n", BOOK_ID))
LT  <- live_track_lane(BOOK_ID, root = ROOT, carry_from = PRIOR_BOOK_ID)
OUT <- file.path(LT, "live_book_series.csv")

cat("============================================================\n")
cat("[extend_nolayer4_series] noLayer4 오버레이 시리즈 재계산 (단일 vintage)\n")
cat("============================================================\n")

## --- 1. base 오버레이 패널 로드 (β_R05/m4/ret_orig/regime per realized_ym) ---
## 우선순위: WT-H rerun 산출(가장 신선, run_layer5_rerun_extended.R) > 2-2 faith 패널(동일 base) > 2-1 사본.
## 세 소스 모두 동일 STR_1715/M4/R05 base 공유 — beta_R05_V5 == faith beta_R05 검증됨(alignment verify [A]).
## (2026-08-02 프로덕션 정리: 2-2 faith·2-1 정적 사본 폴백 제거 — 철거 대상 슬롯.
##  단일 소스 원칙: WT-H rerun 정본이 없으면 낡은 사본으로 조용히 내려가지 말고 여기서 멈춘다.)
cand <- c(
  file.path(ROOT, "qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv")
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

## --- 2b. 계약 rds 앵커 (2026-07-13 위생수리 task #48, 도훈 지시) ---
## 배경(실사고): base 패널 재생성 시 m4 매핑(WT-D20260430_001_m4_extended.csv) 연장 시점에 따라
##   과거월 m4가 vintage flip — 2026-06 행: rds vintage m4=1.0(매핑 미연장 → merge NA-fill,
##   run_layer5_rerun_extended.R L131) vs 07-03 패널 0.8064 → ret_net 0.0724 vs 0.0582.
##   monitoring/holdout/recon IR(governor)은 전부 계약 rds 기준이라 2회 연속 플래그 발생.
## 원칙: 계약-authoritative rds가 커버하는 월은 rds ret_net으로 앵커(고정) — 단일 기준 유지.
##   신규 실현월(rds 이후)만 본 스크립트의 단일-vintage 재계산치 사용.
##   재계산치는 ret_recompute_panel 진단 컬럼으로 전 월 보존(불일치 감사 가능).
RDS_ANCHOR <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
p[, ret_recompute_panel := ret_noLayer4]
p[, ret_net_source := "panel_recompute"]
if (file.exists(RDS_ANCHOR)) {
  prA <- as.data.table(readRDS(RDS_ANCHOR)$period_returns)[, .(anchor_date = as.Date(date), ret_rds = as.numeric(ret_net))]
  p <- merge(p, prA, by = "anchor_date", all.x = TRUE)
  ndiv <- p[is.finite(ret_rds) & abs(ret_noLayer4 - ret_rds) > 1e-9, .N]
  if (ndiv > 0) cat(sprintf("[2b][warn] 패널 재계산 vs 계약 rds 불일치 %d개월 — rds로 앵커(진단: ret_recompute_panel 컬럼 대조)\n", ndiv))
  p[is.finite(ret_rds), `:=`(ret_noLayer4 = ret_rds, ret_net_source = "rds_anchor(WT-D20260702_002)")]
  p[, ret_rds := NULL]
  cat(sprintf("[2b] 계약 rds 앵커 적용: %d/%d월 rds 고정, 나머지 신규월만 재계산\n",
              p[ret_net_source != "panel_recompute", .N], nrow(p)))
} else cat("[2b][warn] 계약 rds 부재 — 앵커 스킵(전체 재계산 사용, monitoring 불일치 재발 가능)\n")

## --- 2c. ★신규월 = 배포 manifest 앵커 (2026-08-02 도훈 승인 "1번 진행") ---
## 원칙(§7b 정합): 실현월의 시리즈 배율은 재계산이 아니라 **배포가 실제 쓴 결정값**이다.
## 실사고 2건이 근거 — ① 재계산의 R05 z 소스(동결)가 NA 로 무뎌져 7월 β 0.30→0.50 왜곡
## ② D3 는 gate 가 m4 를 대체해 재계산(β×m4)과 산식 자체가 다르다.
## 방식: 신규월(rds 앵커 밖) 각각에 대해, 그 달의 **수익월 1일 배포 manifest** 의 invested 로
##   ret = invested × ret_orig − |Δinvested| × COST 재산출. manifest 탐색 = admitted 슬롯 →
##   직전 슬롯(2-3, swap-in 이전 월분) 순. 부재 시 재계산 유지 + 명시 WARN (침묵 승격 금지).
if (TRUE) {
  .fm_base <- file.path(ROOT, "05_Production/2.Factor_Model")
  .man_dirs <- c(
    if (exists(".slotres") && !is.null(.slotres)) .slotres$holdings_dir else NULL,
    file.path(.fm_base, paste0("2-3.", PRIOR_BOOK_ID), "02_holdings_universe"))
  .find_manifest <- function(dep_ym) {           # dep_ym = 수익월 "YYYY-MM" (그 1일 배포)
    pat <- paste0("^", gsub("-", "", dep_ym), "[0-9]{2}_.*_manifest\\.json$")
    for (d in .man_dirs) {
      if (!dir.exists(d)) next
      f <- list.files(d, pattern = pat, full.names = TRUE)
      if (length(f)) return(f[order(basename(f))][1])   # 같은 월 복수면 사전순 첫 파일(일자 최소 = 월초 배포)
    }
    NULL
  }
  ## ★2026-08-08 β 열 정합 (도훈 승인 "1,2 고치자").
  ##   결함: manifest 앵커가 ret_net 을 배포 실측으로 덮어써도 beta_R05 열은 패널값 그대로였다.
  ##   실측 2026-08: ret_net −8.2757%(=invested 0.30 산물)인데 같은 행 beta_R05 열은 0.50 —
  ##   원장에서 β 를 읽는 소비자는 배포되지 않은 값을 얻는다.
  ##   ★2차 피해(더 중요): 아래 prev_inv 가 `beta_R05 × m4` 로 직전월 노출을 잡는다.
  ##   열이 stale 이면 **다음 달 회전비용 |Δinvested| 가 틀린 기준으로 계산**된다.
  ##   수리: 실제 적용 노출을 invested_eff 로 명시 보존하고, beta_R05 는 실효값으로 정정,
  ##        패널 원값은 beta_R05_panel 로 남겨 감사 가능하게 한다(진단 손실 없음).
  p[, beta_R05_panel := beta_R05]
  p[, invested_eff := beta_R05 * m4]
  ## z 결측으로 β 가 무뎌졌는지 — 상류(run_layer5)가 n_R05_valid 를 전달. 구 패널 폴백 = R05_z_avg NaN.
  .blunted <- function(i) {
    if ("n_R05_valid" %in% names(p) && is.finite(p$n_R05_valid[i])) return(p$n_R05_valid[i] == 0L)
    if ("R05_z_avg" %in% names(p)) return(!is.finite(p$R05_z_avg[i]))
    NA
  }
  new_m <- which(p$ret_net_source == "panel_recompute")   # rds 앵커 밖 = 신규월 (2b 라벨)
  if (length(new_m)) {
    prev_inv <- NA_real_
    for (i in new_m) {
      ## 수익월 = 장부월(anchor) 직전월 (return_ym 은 [3]에서야 생성되므로 여기서 직접 산출)
      dep_ym <- format(as.Date(p$anchor_date[i]) - 15L, "%Y-%m")
      mf <- .find_manifest(dep_ym)
      if (is.null(mf)) {
        ## ★fail-closed (2026-08-08): 앵커가 없으면 재계산치가 그대로 기록된다.
        ##   그 재계산치가 z 결측으로 무뎌진 β 산물이면 **틀린 값이 조용히 원장에 들어간다**.
        ##   실측 규모: 2026-08 기준 재계산 −13.7429% vs 배포 실측 −8.2757% = 5.47%pt.
        ##   무뎌지지 않은 달의 앵커 부재는 정상 진행(재계산이 유효) — 조건을 좁혀 오탐을 막는다.
        bl <- .blunted(i)
        if (isTRUE(bl) && !identical(Sys.getenv("QVEST_ALLOW_BLUNT_ANCHOR", "0"), "1")) {
          stop(sprintf(paste0("[2c][fail-closed] 신규월 %s: 배포 manifest 부재(수익월 %s) ∧ β 가 z 결측으로 무뎌짐.\n",
                              "  이 상태로 진행하면 재계산치 %.4f 가 배포 실측 대신 원장에 기록된다.\n",
                              "  수리: ① 해당 월 배포 manifest 확보 또는 ② R05 z 소스 연장/live 통일.\n",
                              "  의도적 진행: QVEST_ALLOW_BLUNT_ANCHOR=1 (그 경우 원장에 무뎌진 값이 남는다)."),
                      p$realized_ym[i], dep_ym, p$ret_noLayer4[i]))
        }
        cat(sprintf(paste0("[2c][WARN] ★신규월 %s: 수익월 %s 배포 manifest 부재 — 재계산치 유지 (%.4f).\n",
                           "          β 무뎌짐 판정 = %s. 배포 실측과 대조 필요.\n"),
                    p$realized_ym[i], dep_ym, p$ret_noLayer4[i],
                    if (is.na(bl)) "판정불가(신호 부재)" else if (bl) "무뎌짐(우회 승인됨)" else "정상"))
        prev_inv <- p$invested_eff[i]
        next
      }
      mj  <- jsonlite::fromJSON(mf)
      inv <- as.numeric(mj[["invested"]])
      if (!is.finite(inv) || inv < 0 || inv > 1)
        stop(sprintf("[2c] manifest invested 값 이상(%s): %s", as.character(inv), mf))
      ## 직전월 노출: 직전 신규월의 앵커 invested, 없으면(첫 신규월) 직전 행의 실효 노출
      ## ★invested_eff 사용 — 직전 행이 앵커월이면 그 행의 beta_R05 도 이미 실효값으로 정정돼 있다.
      if (!is.finite(prev_inv)) {
        j <- i - 1L
        prev_inv <- if (j >= 1L) p$invested_eff[j] else inv
      }
      ret_a <- inv * p$ret_orig[i] - abs(inv - prev_inv) * COST
      ## β 열 정정: invested = β × m4 규약을 유지하도록 실효 β 를 역산(m4=0 이면 역산 불가 → 패널값 보존).
      b_eff <- if (is.finite(p$m4[i]) && abs(p$m4[i]) > 1e-12) inv / p$m4[i] else NA_real_
      cat(sprintf("[2c] 신규월 %s ← manifest %s: invested=%.4f · ret %.4f→%.4f (재계산 대비 %+.2f%%p) · β %.4f→%s\n",
                  p$realized_ym[i], basename(mf), inv, p$ret_noLayer4[i], ret_a,
                  100 * (ret_a - p$ret_noLayer4[i]), p$beta_R05[i],
                  if (is.finite(b_eff)) sprintf("%.4f", b_eff) else "유지(m4=0)"))
      p[i, `:=`(ret_noLayer4 = ret_a,
                ret_net_source = sprintf("manifest_anchor(%s)", basename(mf)),
                invested_eff = inv,
                beta_R05 = if (is.finite(b_eff)) b_eff else beta_R05)]
      prev_inv <- inv
    }
  } else cat("[2c] 신규월 없음 — manifest 앵커 대상 없음\n")
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
  ret_orig,
  beta_R05,                            # ★실효 β (앵커월은 배포 invested 기준으로 정정됨)
  m4, dR05,
  invested_eff,                        # ★실제 적용 노출 = 앵커월 manifest invested / 그 외 β×m4
  beta_R05_panel,                      # ★패널 원값 (동결 z 기반) — 감사용, 실효값과 다를 수 있음
  ret_recompute_panel, ret_net_source  # 2b 앵커 진단 (rds_anchor vs panel_recompute)
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
