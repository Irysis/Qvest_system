#==============================================================================
# trial_build_consensus.R — FQ-163 수리 후 시범 산출 (전면 재빌드 아님)
#
# save=FALSE  → parquet 미기록 (기존 440개 월 파일 불변)
# force=TRUE  → 캐시 무시하고 실제 재계산 (force 없으면 캐시를 그대로 반환해
#               "수리했는데 옛날 값" 을 보게 된다)
#
# 산출: stage_artifacts/fq163/trial_build_result.csv  (ym × factor × 행수/종목수)
#==============================================================================
suppressPackageStartupMessages({library(data.table)})

.pick_root <- function() {
  for (c in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"), getwd())) {
    if (!nzchar(c)) next
    n <- gsub("\\\\", "/", c)
    if (file.exists(file.path(n, "02_Infrastructure/factor_db/factor_db_builder.R"))) return(n)
  }
  stop("[trial] PROJECT_ROOT 해석 실패")
}
ROOT <- .pick_root()
setwd(file.path(ROOT, "02_Infrastructure"))
source("factor_db/factor_db_builder.R")

TARGET <- c("C10_SUE_Persistence", "C11_Earnings_Streak", "C13_Revision_Breadth_3m",
            "C14_Revenue_Surprise", "C15_Forecast_Error_Trend",
            "C17_OP_Revision", "C18_Earnings_CAR_3d")
CONTROL <- c("M26_Revenue_Mom", "M25_Earnings_Mom_Streak", "M28_OP_Rev_Mom",
             "C01_SUE", "C04_ESBR")   # ★양성 대조 — 0 이 계측 사망인지 진짜인지 구별

months <- c("2012-06-30", "2018-06-30", "2022-06-30", "2025-06-30", "2026-06-30")

acc <- list()
for (d in months) {
  cat(sprintf("\n########## %s ##########\n", d))
  res <- tryCatch(build_factor_db(d, save = FALSE, force = TRUE),
                  error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL })
  if (is.null(res) || nrow(res) == 0L) next
  s <- res[, .(n_rows = .N, n_tickers = uniqueN(Ticker),
               n_nonNA = sum(!is.na(Raw_Value))), by = Factor_Name]
  s[, ym := format(as.Date(d), "%Y%m")]
  acc[[d]] <- s
  cat("  --- FQ-163 대상 ---\n")
  for (f in TARGET) {
    r <- s[Factor_Name == f]
    cat(sprintf("    %-28s %s\n", f,
                if (nrow(r) == 0L) "0행 (미산출)" else
                  sprintf("%d행 · %d종목 · non-NA %d", r$n_rows, r$n_tickers, r$n_nonNA)))
  }
  cat("  --- 양성 대조 ---\n")
  for (f in CONTROL) {
    r <- s[Factor_Name == f]
    cat(sprintf("    %-28s %s\n", f,
                if (nrow(r) == 0L) "0행 ★대조 사망 — 계측 자체를 의심할 것" else
                  sprintf("%d행 · %d종목", r$n_rows, r$n_tickers)))
  }
}

if (length(acc)) {
  out <- rbindlist(acc, use.names = TRUE)
  setcolorder(out, c("ym", "Factor_Name", "n_rows", "n_tickers", "n_nonNA"))
  outdir <- file.path(ROOT, "stage_artifacts", "fq163")
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  fwrite(out[order(ym, Factor_Name)], file.path(outdir, "trial_build_result.csv"))
  cat(sprintf("\n[trial] 저장: %s (%d행)\n", file.path(outdir, "trial_build_result.csv"), nrow(out)))

  # 수리 후 잔여 결측 목록 (기준선 시딩용)
  last_ym <- max(out$ym)
  fwrite(out[ym == last_ym, .(Factor_Name)],
         file.path(outdir, sprintf("produced_%s.csv", last_ym)))
  cat(sprintf("[trial] %s 산출 팩터 %d종 기록\n", last_ym, uniqueN(out[ym == last_ym]$Factor_Name)))
} else {
  cat("\n[trial] ★산출 0 — 계측 실패로 간주하고 중단 (0 은 결론이 아니라 정지 신호)\n")
}
