## FQ-143 tail-overlay — P0 입력 실측 (측정 전 입력 형태 확인 의무)
## 규약: 결과를 내기 전에 입력의 행수/관측단위/범위를 먼저 찍는다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
stopifnot(dir.exists(file.path(ROOT, "02_Infrastructure")))

PANEL <- file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv")
p <- fread(PANEL)
cat("=== [P0-1] 패널 실측 ===\n")
cat(sprintf("path      : %s\n", PANEL))
cat(sprintf("nrow      : %d   ncol: %d\n", nrow(p), ncol(p)))
cat(sprintf("cols      : %s\n", paste(names(p), collapse=", ")))
cat(sprintf("realized_ym range : %s ~ %s\n", min(p$realized_ym), max(p$realized_ym)))
cat(sprintf("return_ym  range  : %s ~ %s\n", min(p$return_ym), max(p$return_ym)))
cat(sprintf("anchor_date range : %s ~ %s\n", min(p$anchor_date), max(p$anchor_date)))

cat("\n=== [P0-2] 관측단위 검증: return_ym vs realized_ym vs anchor_date 간격 ===\n")
p[, anchor_date := as.Date(anchor_date)]
p[, ret_ym_start := as.Date(paste0(return_ym, "-01"))]
p[, real_ym_start := as.Date(paste0(realized_ym, "-01"))]
p[, gap_anchor_minus_retym := as.numeric(anchor_date - ret_ym_start)]
print(summary(p$gap_anchor_minus_retym))
cat(sprintf("realized_ym == return_ym+1M 인 행: %d / %d\n",
            sum(p$real_ym_start == seq_along(p$ret_ym_start) * 0 + p$ret_ym_start + 0 |
                format(p$real_ym_start, "%Y-%m") == format(p$ret_ym_start + 31, "%Y-%m")), nrow(p)))

cat("\n=== [P0-3] regime 라벨 분포 ===\n")
print(p[, .N, by = regime][order(-N)])

cat("\n=== [P0-4] 오버레이 스케일 성분 ===\n")
for (cc in c("ret_orig","beta_R05","m4","beta_AR","beta_faith")) {
  v <- p[[cc]]
  cat(sprintf("%-11s n=%3d  min=%.4f  q25=%.4f  med=%.4f  q75=%.4f  max=%.4f  #distinct=%d\n",
              cc, sum(is.finite(v)), min(v,na.rm=TRUE), quantile(v,.25,na.rm=TRUE), median(v,na.rm=TRUE),
              quantile(v,.75,na.rm=TRUE), max(v,na.rm=TRUE), uniqueN(round(v,6))))
}
cat("\n-- beta_R05 고유값 --\n"); print(sort(unique(round(p$beta_R05,4))))
cat("\n-- m4 고유값 --\n");       print(sort(unique(round(p$m4,4))))
cat("\n-- scale = beta_R05*m4 분포 --\n")
p[, scale_cur := beta_R05 * m4]
print(p[, .N, by = .(scale_cur = round(scale_cur,3))][order(scale_cur)])

cat("\n=== [P0-5] regime x scale 교차 (라벨이 실제로 노출을 줄이는가) ===\n")
print(p[, .(n=.N, mean_scale=round(mean(scale_cur),3), mean_ret_orig=round(mean(ret_orig),4),
            p_lt0=round(mean(ret_orig<0),3), p_lt5=round(mean(ret_orig < -0.05),3),
            p_lt10=round(mean(ret_orig < -0.10),3)), by=regime][order(-n)])

cat("\n=== [P0-6] ret_orig 사건 정의별 기저율 (패널 269개월) ===\n")
for (thr in c(0, -0.05, -0.10)) {
  cat(sprintf("  ret_orig < %6.2f%% : %3d/%d = %.4f\n", thr*100, sum(p$ret_orig < thr), nrow(p), mean(p$ret_orig < thr)))
}

cat("\n=== [P0-7] 벤치(시장) 계열 존재 확인 ===\n")
BM_PIN <- file.path(ROOT, "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")
cat(sprintf("benchmark_pinned exists: %s\n", file.exists(BM_PIN)))

saveRDS(p, file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809/panel_p0.rds"))
cat("\n[P0 DONE]\n")
