#!/usr/bin/env Rscript
# =============================================================================
# p1_topcut_ab.R — FQ-170: HUMP 재료의 상단절단이 실제로 작동하는가
#
# ── 사전등록 (결과 도착 전 확정) ─────────────────────────────────────────
# 발행: WT-D20260809_003 (FQ-166 형태 분류 확립 — MONOTONE_TOP / HUMP / 상단-역전형).
# 가설: HUMP 재료(Q01_EB, argmax D8·상단이 EW 에도 뒤짐)는 top-25 대신 **D8~D9 선별**이 낫다.
#   형태→소비면 대응은 현재 가설 — 실측된 적 없음(FQ-166 명시).
# 관문 순서 (큐 next_action 고정):
#   ① 검정력 바 — paired sd 실측 → 필요효과. 기대효과 = **형태 라운드의 기공개 프로파일**
#      (p1_shape_summary.csv 의 D8~D9 vs D10 ann_ex 갭 — 본 라운드 결과 아님 = ex-ante 적법).
#      필요 > 기대면 착수 전 폐기(측정 안 함).
#   ② Q01_EB: D8~D9 선별 vs top-25 paired NW3 (통과 시에만)
#   ③ M26(MONOTONE_TOP) 음성 대조 — 같은 처치가 **해로워야** 형태-조건부 대응이 성립
#   ④ 해상도 불변성 — decile D8~D9(70~90 분위) vs quintile Q4(60~80 분위) 결론 일치 여부
# 프레임 = WT-003 1급 프레임 그대로: 유동성 adv>=2e8 · 전표본 · EW-유니버스 대비 gross.
# metric_type = canonical_screen_diag (gross 진단 — capital_claim=false, WT-003 정합)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(ROOT)) ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/FQ170_claim_20260809")
sink(file.path(OUT, "p1_topcut.log"), split = TRUE)
cat(sprintf("run_at=%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # .nw_t_mean

## ── 입력 (WT-003 프레임 재사용) ───────────────────────────────────────
B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(B, ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
X <- merge(X, liq[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
X <- X[is.na(adv) | adv >= 2e8]                       # 1급 프레임: 유동성 필터
cat(sprintf("[0] 입력: %d행 · %d개월 (%s..%s) · 유동성 필터 후\n",
            nrow(X), uniqueN(X$Date), min(X$Date), max(X$Date)))

## 선별 수익 시계열: 점수 상위 규칙별 EW gross, 유니버스 EW 대비 초과
sel_series <- function(D, scorecol, rule) {
  D <- D[!is.na(get(scorecol))]
  D[, n_m := .N, by = Date]; D <- D[n_m >= 50]
  D[, pr := frank(get(scorecol), ties.method="first") / .N, by = Date]
  sel <- switch(rule,
    top25   = D[, .SD[frank(-get(scorecol), ties.method="first") <= 25], by = Date],
    d8d9    = D[pr > 0.70 & pr <= 0.90],
    q4      = D[pr > 0.60 & pr <= 0.80])
  u <- D[, .(u = mean(Ret_1m)), by = Date]
  s <- sel[, .(r = mean(Ret_1m), n_sel = .N), by = Date]
  m <- merge(s, u, by = "Date"); setorder(m, Date)
  m[, ex := r - u]; m
}

## ── ① 검정력 바 (Q01, D8~D9 vs top-25) ───────────────────────────────
cat("\n=== [①] 검정력 바 — paired sd 실측 → 필요효과 vs ex-ante 기대효과 ===\n")
a25 <- sel_series(copy(X), "Q01_EB", "top25")
a89 <- sel_series(copy(X), "Q01_EB", "d8d9")
M <- merge(a25[, .(Date, ex25 = ex)], a89[, .(Date, ex89 = ex)], by = "Date")
d <- M$ex89 - M$ex25
sdd <- sd(d); nn <- length(d); req_pm <- 2.0 * sdd / sqrt(nn)
cat(sprintf("  paired n=%d  sd(diff)=%.3f%%/m  필요효과(|t|>=2) = %.4f%%/m = 연 %.2f%%p\n",
            nn, 100*sdd, 100*req_pm, 100*req_pm*12))
## ex-ante 기대: 형태 라운드 기공개 decile 프로파일에서 (D8~D9 평균 − D10) — 본 라운드 산출 아님
ps <- fread("stage_artifacts/WT_D20260809_003/p1_shape_summary.csv")
cat("  [ex-ante 근거] p1_shape_summary.csv 스키마:", paste(names(ps), collapse=", "), "\n")
q01row <- ps[grepl("Q01_EB", material) & grepl("full", window) & nq == 10 & liq == TRUE]
if (nrow(q01row) == 0) q01row <- ps[grepl("Q01_EB", material)][1]
print(q01row)
exp_eff_note <- "기대효과 = FQ-166 메모리 실측(Q01 5분위 [-3.81 +1.37 +3.05 +1.78 -2.41]%/yr): 중간(+3.05) - 상단(-2.41) = 연 ~5.5%p"
exp_eff_yr <- 3.05 - (-2.41)
cat(sprintf("  %s\n", exp_eff_note))
verdict1 <- if (100*req_pm*12 <= exp_eff_yr) "PROCEED" else "ABORT_UNDERPOWERED"
cat(sprintf("  ① 판정: 필요 연 %.2f%%p vs 기대 연 %.2f%%p → %s\n", 100*req_pm*12, exp_eff_yr, verdict1))
R <- list(power = list(n = nn, sd_pm = sdd, required_yr_pp = 100*req_pm*12,
                       expected_yr_pp = exp_eff_yr, verdict = verdict1))

if (verdict1 == "PROCEED") {
  ## ── ② 본검정: Q01 D8~D9 vs top-25 ──────────────────────────────────
  cat("\n=== [②] Q01_EB: D8~D9 vs top-25 (paired NW3) ===\n")
  t2 <- .nw_t_mean(d, lag = 3L)
  cat(sprintf("  top-25 ann_ex=%+.2f%%/yr · D8~D9 ann_ex=%+.2f%%/yr · diff=%+.2f%%p/yr  t_NW3=%+.3f\n",
              12*100*mean(M$ex25), 12*100*mean(M$ex89), 12*100*mean(d), t2))
  R$q01 <- list(top25_yr = 12*mean(M$ex25), d8d9_yr = 12*mean(M$ex89),
                diff_yr = 12*mean(d), t_nw3 = t2)

  ## ── ③ 음성 대조: M26 (MONOTONE_TOP — 같은 처치가 해로워야 함) ──────
  cat("\n=== [③] 음성 대조 M26 (MONOTONE_TOP): D8~D9 vs top-25 ===\n")
  b25 <- sel_series(copy(X), "M26_Revenue_Mom", "top25")
  b89 <- sel_series(copy(X), "M26_Revenue_Mom", "d8d9")
  Mb <- merge(b25[, .(Date, ex25 = ex)], b89[, .(Date, ex89 = ex)], by = "Date")
  db <- Mb$ex89 - Mb$ex25; t3 <- .nw_t_mean(db, lag = 3L)
  cat(sprintf("  top-25 %+.2f%%/yr · D8~D9 %+.2f%%/yr · diff=%+.2f%%p/yr  t_NW3=%+.3f  (기대 = 음수)\n",
              12*100*mean(Mb$ex25), 12*100*mean(Mb$ex89), 12*100*mean(db), t3))
  R$m26_control <- list(diff_yr = 12*mean(db), t_nw3 = t3,
                        as_expected = mean(db) < 0)

  ## ── ④ 해상도 불변성: quintile Q4 (60~80) 판본 ──────────────────────
  cat("\n=== [④] 해상도 불변성: quintile Q4 선별 판본 ===\n")
  aq4 <- sel_series(copy(X), "Q01_EB", "q4")
  Mq <- merge(a25[, .(Date, ex25 = ex)], aq4[, .(Date, exq4 = ex)], by = "Date")
  dq <- Mq$exq4 - Mq$ex25; t4 <- .nw_t_mean(dq, lag = 3L)
  cat(sprintf("  Q4(60~80분위) vs top-25: diff=%+.2f%%p/yr  t_NW3=%+.3f\n", 12*100*mean(dq), t4))
  same_sign <- sign(mean(d)) == sign(mean(dq))
  cat(sprintf("  ④ 결론 일치(부호): %s\n", ifelse(same_sign, "일치", "★불일치 — 해상도 민감, 결론 보류")))
  R$resolution <- list(q4_diff_yr = 12*mean(dq), t_nw3 = t4, sign_match = same_sign)

  ## 종합
  cat("\n=== [종합 판정] ===\n")
  main_ok <- t2 >= 2.0; ctrl_ok <- mean(db) < 0; res_ok <- same_sign
  vv <- if (main_ok && ctrl_ok && res_ok) "SHAPE_CONDITIONAL_CONSUMPTION_CONFIRMED"
        else if (main_ok && !ctrl_ok) "MAIN_POS_BUT_CONTROL_FAILED"
        else if (!main_ok) "NULL_OR_UNDERPOWERED"
        else "MIXED"
  cat(sprintf("  주검정 t=%.3f(%s) · 음성대조 %s · 해상도 %s → %s\n",
              t2, ifelse(main_ok,"통과","미달"), ifelse(ctrl_ok,"정상","실패"),
              ifelse(res_ok,"불변","민감"), vv))
  R$verdict <- vv
} else {
  cat("\n  ① ABORT — 측정 진입 안 함 (착수 전 폐기, 큐 규약)\n")
  R$verdict <- "ABORT_UNDERPOWERED"
}
R$meta <- list(metric_type = "canonical_screen_diag", capital_claim = FALSE,
               frame = "WT-003 1급 (유동성 adv>=2e8 · 전표본 · EW-유니버스 gross)",
               prereg = "스크립트 헤더 + FQ-170 next_action 고정 순서")
write_json(R, file.path(OUT, "p1_topcut_ab.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
cat("[done]\n"); sink()
