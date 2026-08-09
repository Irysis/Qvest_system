#!/usr/bin/env Rscript
# =============================================================================
# p3_np1_capw.R — FQ-170 NP-1: 배포 프레임 전이 검증
#
# ── 사전등록 (결과 도착 전 확정) ─────────────────────────────────────────
# 확립(gross EW-유니버스): HUMP(Q01_EB) 상단절단 D8~D9 가 top-25 대비 +5.62%p/yr (t 2.570),
#   MONOTONE(M26) 음성 대조 정상, 해상도 강건.
# 본 검정: 그 확립이 **배포 프레임**(25종 슬롯 · 15bps 비용 · cap-w/EW 두 basis)에서 사는가.
# arm (고정):
#   A base : top-25 by Q01_EB score
#   B band : D8~D9(70~90분위) 내 score 상위 25 재선별 (25종 제약 준수)
#   가중 2 basis: EW(w=1/25) · cap-w — cap 데이터 가용 시(불가 시 EW 만, 사유 기록)
# 측정 = weighted_screen_bt 계약 (PORT_t = 벤치 대비 net active NW3 — 계약 산출 사용).
# 판정 (사전 고정):
#   전이 성립 = B−A paired NW3 t >= 2.0 (net, 동일 basis) ∧ 부호가 gross 확립과 일치.
#   B 의 절대 PORT_t 는 참고 병기 (자본 주장은 HARD 3종 전체 요건 — 본 라운드 범위 아님).
# metric_type = backtested_screen (계약 경유 net) · capital_claim = false
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(ROOT)) ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT); OUT <- file.path(ROOT, "stage_artifacts/FQ170_claim_20260809")
sink(file.path(OUT, "p3_np1_capw.log"), split = TRUE)
cat(sprintf("run_at=%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # .nw_t_mean

## ── 입력 실측 ────────────────────────────────────────────────────────
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
cat("[0] p0_panels 구성:", paste(names(P), collapse=", "), "\n")
for (nm in names(P)) { x <- P[[nm]]
  if (is.data.frame(x)) cat(sprintf("   $%s: %d x %d | %s\n", nm, nrow(x), ncol(x),
                                    paste(head(names(x),10), collapse=","))) }
B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]
liq <- as.data.table(P$liq)
X <- merge(B, ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
X <- merge(X, liq[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
X <- X[is.na(adv) | adv >= 2e8][!is.na(Q01_EB)]
cat(sprintf("[0b] 측정 패널: %d행 %d개월\n", nrow(X), uniqueN(X$Date)))

## 벤치: WT-001 패널에 bm 있으면 사용, 없으면 유니버스 EW (라벨 명시)
bm_dt <- NULL
for (nm in names(P)) {
  x <- P[[nm]]
  if (is.data.frame(x) && all(c("Date") %in% names(x)) &&
      any(c("BM_Ret","bm","benchmark_ret") %in% names(x))) {
    bc <- intersect(c("BM_Ret","bm","benchmark_ret"), names(x))[1]
    bm_dt <- as.data.table(x)[, .(Date = as.Date(Date), BM_Ret = get(bc))]
    cat(sprintf("[0c] 벤치 = p0_panels$%s$%s (n=%d)\n", nm, bc, nrow(bm_dt))); break
  }
}
if (is.null(bm_dt)) {
  bm_dt <- X[, .(BM_Ret = mean(Ret_1m)), by = Date]
  cat("[0c] 벤치 = 유니버스 EW (패널 내 BM 부재 — basis 라벨: EW-universe)\n")
}
bm_basis <- if ("BM_Ret" %in% names(bm_dt) && !is.null(bm_dt)) "as_labeled_above" else "ew_universe"

## cap 데이터 가용성
cap_col <- NULL
for (nm in names(P)) { x <- P[[nm]]
  if (is.data.frame(x)) { cc <- intersect(c("Size","MktCap","mktcap","cap"), names(x))
    if (length(cc)) { cap_col <- list(tbl = nm, col = cc[1]); break } } }
cat(sprintf("[0d] cap 데이터: %s\n",
            if (is.null(cap_col)) "부재 → EW basis 만 측정 (cap-w 는 후속, 사유 기록)"
            else sprintf("$%s$%s 사용", cap_col$tbl, cap_col$col)))

## ── 선별 → weights_dt ────────────────────────────────────────────────
mk_w <- function(rule) {
  D <- copy(X)
  D[, n_m := .N, by = Date]; D <- D[n_m >= 50]
  D[, pr := frank(Q01_EB, ties.method="first") / .N, by = Date]
  sel <- switch(rule,
    top25 = D[, .SD[frank(-Q01_EB, ties.method="first") <= 25], by = Date],
    band25 = { b <- D[pr > 0.70 & pr <= 0.90]
               b[, .SD[frank(-Q01_EB, ties.method="first") <= 25], by = Date] })
  sel[, .(Date, Ticker, w = 1)]                       # EW: 계약이 Date 별 정규화
}
wA <- mk_w("top25"); wB <- mk_w("band25")
cat(sprintf("[1] 선별: A top25 %d행 · B band25 %d행 (월평균 A %.1f · B %.1f 종)\n",
            nrow(wA), nrow(wB), nrow(wA)/uniqueN(wA$Date), nrow(wB)/uniqueN(wB$Date)))

## ── 계약 측정 (net, 15bps) ───────────────────────────────────────────
btA <- weighted_screen_bt(wA, ret, bm_dt, cost_bps_oneway = 15,
                          run_id = "FQ170_NP1", strategy_id = "Q01_top25")
btB <- weighted_screen_bt(wB, ret, bm_dt, cost_bps_oneway = 15,
                          run_id = "FQ170_NP1", strategy_id = "Q01_band25")
show_bt <- function(bt, lab) {
  cat(sprintf("  [%s] fields: %s\n", lab, paste(head(names(bt), 12), collapse=", ")))
  for (k in intersect(c("port_t_nw3","portfolio_alpha_t_nw_lag3","ann_active","net_sharpe",
                        "sharpe","turnover_ann","n_months"), names(bt)))
    cat(sprintf("     %s = %s\n", k, paste(round(as.numeric(bt[[k]]), 4), collapse=", ")))
  bt
}
btA <- show_bt(btA, "A top25"); btB <- show_bt(btB, "B band25")

## paired (계약 산출 시계열에서)
ts_of <- function(bt) {
  for (k in c("monthly","period_returns","series","port")) {
    if (k %in% names(bt) && is.data.frame(bt[[k]])) return(as.data.table(bt[[k]]))
  }
  NULL
}
paired_t <- function(btX, btY) {
  tX <- ts_of(btX); tY <- ts_of(btY)
  # ★계약 시계열의 날짜 컬럼은 소문자 date (2026-08-09 실측)
  dc <- intersect(c("date","Date"), names(tX))[1]
  nc <- intersect(c("ret_net","port_net","net"), names(tX))[1]
  bc <- intersect(c("benchmark_ret","bm"), names(tX))[1]
  M <- merge(tX[, .(d_ = get(dc), a = get(nc) - get(bc))],
             tY[, .(d_ = get(dc), b = get(nc) - get(bc))], by = "d_")
  d <- M$b - M$a
  list(t = .nw_t_mean(d, lag = 3L), diff_yr = 12*mean(d), n = length(d))
}
pEW <- paired_t(btA, btB)
cat(sprintf("\n[2] ★EW basis  paired B−A (net active): %+.2f%%p/yr  t_NW3=%+.3f  (n=%d)\n",
            100*pEW$diff_yr, pEW$t, pEW$n))

## ── cap-w basis (사전등록 — size_dt 가용 확인됨) ─────────────────────
SZ <- as.data.table(P$size_dt)[, .(Date = as.Date(Date), Ticker, Size)]
mk_w_cap <- function(w_ew) {
  w2 <- merge(w_ew, SZ, by = c("Date","Ticker"), all.x = TRUE)
  w2[is.na(Size) | Size <= 0, Size := min(w2$Size[w2$Size > 0], na.rm = TRUE)]
  w2[, .(Date, Ticker, w = Size)]                     # 계약이 Date 별 정규화
}
btAc <- weighted_screen_bt(mk_w_cap(wA), ret, bm_dt, cost_bps_oneway = 15,
                           run_id = "FQ170_NP1", strategy_id = "Q01_top25_capw")
btBc <- weighted_screen_bt(mk_w_cap(wB), ret, bm_dt, cost_bps_oneway = 15,
                           run_id = "FQ170_NP1", strategy_id = "Q01_band25_capw")
cat(sprintf("  [cap-w] A top25 PORT_t=%+.3f · B band25 PORT_t=%+.3f\n",
            btAc$portfolio_alpha_t_nw_lag3, btBc$portfolio_alpha_t_nw_lag3))
pCW <- paired_t(btAc, btBc)
cat(sprintf("[3] ★cap-w basis paired B−A (net active): %+.2f%%p/yr  t_NW3=%+.3f  (n=%d)\n",
            100*pCW$diff_yr, pCW$t, pCW$n))

## ── 판정 (사전등록: 전이 = paired t>=2 ∧ gross 확립과 부호 일치, basis 별) ──
v_ew <- if (pEW$t >= 2.0) "CONFIRMED" else if (pEW$t > 0) "DIRECTIONAL" else "FAILED"
v_cw <- if (pCW$t >= 2.0) "CONFIRMED" else if (pCW$t > 0) "DIRECTIONAL" else "FAILED"
cat(sprintf("\n[판정] EW basis: %s (t %+.3f) · cap-w basis: %s (t %+.3f)\n", v_ew, pEW$t, v_cw, pCW$t))
cat(sprintf("  절대 PORT_t (참고, HARD 2.95 와 비교 금지 아님 — 자격은 HARD 3종 전체): ",
            ""))
cat(sprintf("EW A %+.3f → B %+.3f · cap-w A %+.3f → B %+.3f\n",
            btA$portfolio_alpha_t_nw_lag3, btB$portfolio_alpha_t_nw_lag3,
            btAc$portfolio_alpha_t_nw_lag3, btBc$portfolio_alpha_t_nw_lag3))

write_json(list(metric_type = "backtested_screen", capital_claim = FALSE,
                bm_basis = "p0_panels$bench (WT-001 계약)",
                ew = list(A_port_t = btA$portfolio_alpha_t_nw_lag3, B_port_t = btB$portfolio_alpha_t_nw_lag3,
                          paired_t = pEW$t, diff_yr = pEW$diff_yr, verdict = v_ew),
                capw = list(A_port_t = btAc$portfolio_alpha_t_nw_lag3, B_port_t = btBc$portfolio_alpha_t_nw_lag3,
                            paired_t = pCW$t, diff_yr = pCW$diff_yr, verdict = v_cw),
                turnover = list(A = btA$turnover_annual, B = btB$turnover_annual)),
           file.path(OUT, "p3_np1_capw.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
cat("[done]\n"); sink()
