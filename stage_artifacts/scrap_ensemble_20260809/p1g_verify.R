#!/usr/bin/env Rscript
# p1g — 산출물 로드 검증 (소비자 관점에서 실제로 열어본다)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p1g_verify.log"), split = TRUE)

X <- readRDS(file.path(OUT, "ml_feature_panel.rds"))
cat(sprintf("RDS 최상위: %s\n", paste(names(X), collapse = ", ")))
D <- X$panel
cat(sprintf("panel: %d행 x %d열 | ym %s..%s | 모듈 %d | 피처 %d\n",
            nrow(D), ncol(D), min(D$ym), max(D$ym), uniqueN(D$module_id), length(X$feature_cols)))
cat(sprintf("\n열: %s\n", paste(names(D), collapse = ", ")))
cat(sprintf("\n피처(%d): %s\n", length(X$feature_cols), paste(X$feature_cols, collapse = ", ")))
cat("\n타깃 정의:\n"); for (n in names(X$target_def)) cat(sprintf("  %-10s %s\n", n, X$target_def[[n]]))

cat(sprintf("\ny_ret     mean=%+.5f sd=%.5f  결측=%d\n", mean(D$y_ret), sd(D$y_ret), sum(is.na(D$y_ret))))
cat(sprintf("y_dd      mean=%+.5f max=%.5f (<=0 이어야)  값0 비율=%.1f%%\n",
            mean(D$y_dd), max(D$y_dd), 100*mean(D$y_dd == 0)))
nbm <- uniqueN(D[y_bm_next < 0]$ym)
cat(sprintf("y_dd_bear mean=%+.5f  비0 개수=%d | bm<0 개월 %d x 85모듈 = %d (일치해야)\n",
            mean(D$y_dd_bear), sum(D$y_dd_bear != 0), nbm, nbm*85))
stopifnot(max(D$y_dd) <= 0)

cat("\n월별 행수 일정성 (모듈 85개 x 253개월 = 21505):\n")
pm <- D[, .N, by = ym]
cat(sprintf("  월당 행수 min=%d max=%d | 총 %d\n", min(pm$N), max(pm$N), nrow(D)))

cat("\n피처 결측 상위 6 (36m warm-up 기인 정상):\n")
mi <- data.table(feature = X$feature_cols,
  na_pct = vapply(X$feature_cols, function(f) 100*mean(is.na(D[[f]])), 0))
print(head(mi[order(-na_pct)], 6))

cat("\n국면 라벨 분포 (reg_cat_t, 월 t 말 = 월 t+1 적용):\n")
print(D[, .N, by = reg_cat_t][order(-N)])

J <- fromJSON(file.path(OUT, "panel_build_report.json"))
cat(sprintf("\nJSON 최상위: %s\n", paste(names(J), collapse = ", ")))
cat(sprintf("누출검사 키: %s\n", paste(names(J$leakage_checks), collapse = ", ")))
c4 <- J$leakage_checks$check4_truncation_invariance
c5 <- J$leakage_checks$check5_violation_injection
cat(sprintf("  check4 불일치=%s 최대차=%s | check5 검출=%s\n",
            c4$n_mismatch, c4$max_abs_diff, c5$detected_by_check4))
cat(sprintf("  p0_reconciliation verdict: %s\n",
            paste(names(J$p0_reconciliation$verdict), unlist(J$p0_reconciliation$verdict),
                  sep="=", collapse=" | ")))
cat(sprintf("\n파일 크기: rds %.2f MB | json %.1f KB\n",
            file.size(file.path(OUT,"ml_feature_panel.rds"))/1e6,
            file.size(file.path(OUT,"panel_build_report.json"))/1e3))
cat("\n[done]\n"); sink()
