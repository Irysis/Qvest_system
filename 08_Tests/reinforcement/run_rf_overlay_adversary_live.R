#!/usr/bin/env Rscript
# run_rf_overlay_adversary_live.R — 실물 entry 위에서 오버레이 적대 반증 **dry-run** (G2 · 2026-09-17)
#
# 대상: RP_20260917_105807_22632_combo_rulefast · B5 블록(측정 5칸 B5_16..B5_20 · 바닥 = B1_5 · PORT_t 3.202 · Calmar 0.385).
# dry_run=TRUE — 원장 미기록. 산출은 .cache/rf_overlay_adversary/<BID>/<code>/adversary.json 뿐이다.
# reruns="auto" — 엔진이 overlay_shift/overlay_strict 를 지원하고 run_paper_replication.R 이 QVEST_RP_NO_LCODE 를
#   읽을 때만 T1/T2 재실행(워커 ≈14분/칸). 둘 중 하나라도 안 서면 T1/T2 는 skipped 로 남고 verdict=error(조용한 통과 없음).
#   해석적 T3/T3b/T4/T5 는 지금도 돈다.
# 사용: Rscript 08_Tests/reinforcement/run_rf_overlay_adversary_live.R [base_id] [block] [reruns]
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
args <- commandArgs(trailingOnly = TRUE)
BID   <- if (length(args) >= 1L) args[1] else "RP_20260917_105807_22632_combo_rulefast"
BLOCK <- if (length(args) >= 2L) args[2] else "B5"
RERUN <- if (length(args) >= 3L) args[3] else "auto"
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
suppressMessages({ library(data.table); library(jsonlite) })
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_adversary.R")))))

sup <- .adv_engine_supports(ROOT); honors <- .adv_rp_honors_lcode_switch(ROOT)
cat(sprintf("[live] engine overlay_shift=%s overlay_strict=%s · run_paper_replication honors QVEST_RP_NO_LCODE=%s · reruns=%s\n",
            sup$overlay_shift, sup$overlay_strict, honors, RERUN))
t0 <- Sys.time()
S <- rf_overlay_adversary_run(BID, block = BLOCK, layer = 1L, root = ROOT, dry_run = TRUE, reruns = RERUN)
cat(sprintf("[live] elapsed %.1fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
options(width = 200)
print(S[, .(code, n, calmar, floor_code, floor_calmar, candidate, verdict, T1, T2, T3, T3b, T4, T5_share = round(T5_share, 3))])

# 후보 칸의 검정 수치 — 판정 인용은 adversary.json 이 정본이다
for (k in which(S$candidate)) {
  J <- fromJSON(S$json[k], simplifyVector = FALSE)
  T3 <- J$tests$T3; T4 <- J$tests$T4; T5 <- J$tests$T5; T3b <- J$tests$T3b; AP <- J$approximation
  cat(sprintf("\n== %s (own layers: %s · vector_observed=%s · floor %s calmar %.3f · approx gap %.4f)\n", S$code[k],
              paste(vapply(J$own_layers, function(z) as.character(z$arm_id %||% z$kind), character(1)), collapse = "+"),
              J$vector_observed, J$floor$code, J$floor$calmar, AP$floor_approx_gap %||% NA))
  cat(sprintf("   E: mean %.3f min %.3f max %.3f · full-cash %d · missing %d / %d periods\n", AP$E_mean, AP$E_min, AP$E_max,
              AP$n_full_cash, AP$n_missing_cell_dates, AP$n_periods))
  cat(sprintf("   T3  %s · obs %.4f vs q%.0f %.4f (mean %.4f · p %.3f · b=%d %s · K=%d)\n", T3$status, T3$obs_calmar,
              100 * (1 - T3$alpha), T3$placebo_q, T3$placebo_mean, T3$p_value, T3$block_len, T3$block_rule, T3$n_placebo))
  cat(sprintf("   T4  %s · obs %.4f vs const(E=%.3f) %.4f\n", T4$status, T4$obs_calmar, T4$mean_E, T4$const_calmar))
  if (identical(T3b$status %||% "", "not_computed")) cat("   T3b not_computed (scalar)\n") else
    cat(sprintf("   T3b %s · obs %.4f vs q %.4f (p %.3f · rows %s · coverage %.3f)\n", T3b$status, T3b$obs_calmar %||% NA,
                T3b$placebo_q %||% NA, T3b$p_value %||% NA, T3b$n_rows %||% NA, T3b$rawdata_coverage %||% NA))
  cat(sprintf("   T5  MDD floor %.3f → cell(approx) %.3f · largest episode %s→%s depth %.3f→%.3f · share %.2f\n",
              T5$mdd_floor, T5$mdd_cell, T5$largest$peak, T5$largest$trough, T5$largest$depth_floor, T5$largest$depth_cell,
              T5$share_largest %||% NA))
  cat(sprintf("   T1  %s · %s\n", J$tests$T1$status, J$tests$T1$detail %||% sprintf("calmar_shift %.4f", J$tests$T1$calmar_shift %||% NA)))
  cat(sprintf("   T2  %s · %s\n", J$tests$T2$status, J$tests$T2$detail %||% ""))
  cat(sprintf("   verdict %s (analytic %s) — %s\n", J$verdict, J$analytic_verdict, J$reason))
}
cat(sprintf('\n{"live":"rf_overlay_adversary","base_id":"%s","block":"%s","cells":%d,"candidates":%d}\n', BID, BLOCK, nrow(S), sum(S$candidate)))
