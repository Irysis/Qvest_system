## FQ-181 P1b — census 교차표 + 휴리스틱 검증(표본 수기 대조용 근거 출력)
suppressPackageStartupMessages({ library(data.table) })
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM <- gsub("\\\\", "/", QM); setwd(QM)
OUT <- file.path(QM, "stage_artifacts/FQ181_liquidity_ruler")
CEN <- fread(file.path(OUT, "p1_consumer_census.csv"))

cat("=== 교차표: panel_shape x liq_verdict ===\n")
print(dcast(CEN[, .N, by = .(panel_shape, liq_verdict)], panel_shape ~ liq_verdict,
            value.var = "N", fill = 0))

cat("\n=== ★핵심 셀: 월말-slim ∧ liq_wired (잘못 라벨된 1일치 자가 실제로 필터 중) ===\n")
key <- CEN[panel_shape %like% "month_end" & liq_verdict == "liq_wired"]
cat(sprintf("건수 = %d (전 호출부의 %.1f%%)\n", nrow(key), 100 * nrow(key) / nrow(CEN)))

cat("\n=== 계층별 분해 (상시 인프라 vs 일회성 산출물) ===\n")
CEN[, tier := fifelse(grepl("^02_Infrastructure/", file), "infra_상시",
              fifelse(grepl("^04_Research/", file), "research_반복",
              fifelse(grepl("^05_Production/", file), "production", "stage_artifacts_일회")))]
print(CEN[, .N, by = .(tier, panel_shape, liq_verdict)][order(tier, -N)])

cat("\n=== 상시 인프라 호출부 전건 (수기 검증 대상) ===\n")
print(CEN[tier %in% c("infra_상시", "research_반복", "production"),
          .(file, line, panel_var, panel_shape, liq_verdict)], nrows = 200)

cat("\n=== LIQ_UNWIRED 4건 상세 ===\n")
print(CEN[liq_verdict %like% "UNWIRED", .(file, line, panel_var, panel_shape)])

cat("\n=== 휴리스틱 플래그 분해 (오탐 진단용) ===\n")
CEN[, `:=`(f_assign = grepl("assign=TRUE", slim_flags),
           f_file   = grepl("file=TRUE", slim_flags),
           f_name   = grepl("name=TRUE", slim_flags))]
print(CEN[panel_shape %like% "month_end", .N, by = .(f_assign, f_file, f_name)])
cat("\n※ name=TRUE 단독(assign/file 모두 FALSE)은 변수명만 근거 → 오탐 위험 구간\n")
print(CEN[panel_shape %like% "month_end" & !f_assign & !f_file & f_name,
          .(file, line, panel_var)], nrows = 60)
fwrite(CEN, file.path(OUT, "p1_consumer_census.csv"))
