#==============================================================================
# guard_dryrun_real_state.R — 실제 registry/원장/기준선으로 감시를 돌려본다
# (빌드 없이: 원장에 이미 있는 202608 산출 집합을 '이번 빌드'로 간주)
#==============================================================================
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
.pick_root <- function() {
  for (c in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"), getwd())) {
    if (!nzchar(c)) next
    n <- gsub("\\\\", "/", c)
    if (file.exists(file.path(n, "02_Infrastructure/factor_db/emission_guard.R"))) return(n)
  }
  stop("root 해석 실패")
}
ROOT <- .pick_root(); setwd(ROOT)
source("02_Infrastructure/factor_db/emission_guard.R")

led <- fread(".cache/factor_db/emission_ledger.csv", colClasses = list(character = "ym"))
YM  <- "202608"
produced <- led[ym == YM & n_rows > 0L, .(Factor_Name, n_rows, n_tickers)]
hist     <- led[ym < YM]
reg      <- emission_registry_meta("02_Infrastructure/factor_db/factor_registry.json")
bl       <- emission_load_baseline("02_Infrastructure/factor_db/emission_expected_absent.json")

cat(sprintf("입력: 산출 %d종 · 원장 이력 %d개월 · registry %d(active %d) · 기준선 %d\n\n",
            nrow(produced), uniqueN(hist$ym), nrow(reg), reg[status == "active", .N], nrow(bl)))

rep <- factor_emission_check(produced, reg, hist, YM, bl)
cat(sprintf("verdict = %s\n", rep$verdict))
cat(sprintf("active %d · 산출 %d · 결측 %d\n", rep$n_registry_active, rep$n_produced, rep$n_absent))
cat(sprintf("Class R (회귀) %d종\nClass S (구조적 침묵) %d종\n\n",
            length(rep$class_R_regression), length(rep$class_S_silent)))
for (w in rep$warnings) cat("  WARN ", w, "\n\n", sep = "")

cat("--- 계열별 결측 ---\n"); print(rep$family_breakdown[n_absent > 0, .(category, n_active, n_produced, n_absent)])
cat("\n--- 연속 결측 상위 12 ---\n"); print(head(rep$absent_streak, 12))

dir.create("stage_artifacts/fq163", recursive = TRUE, showWarnings = FALSE)
write_json(rep, "stage_artifacts/fq163/guard_dryrun_202608.json",
           auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
cat("\n저장: stage_artifacts/fq163/guard_dryrun_202608.json\n")
