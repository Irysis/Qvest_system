## FQ-169 P0 — 대상 8종 **산출 여부** 실측 (registry 등재 ≠ 산출: 2026-08-08 C14 사고)
## C15 준수: factor_db parquet 직접 load 금지 — load_month_factors() 경유
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ169")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

TARGET <- c("D34","D35","D36","D41","D42","D45","D47","D50")
say("=== 최신월 산출 실측 (부분일치로 정식명 탐색) ===")
F <- load_month_factors("2026-06-30")
F <- as.data.table(F)
say("  최신월 반환: %d행 · 컬럼 %s", nrow(F), paste(names(F), collapse=", "))
allf <- sort(unique(F$Factor_Name))
say("  산출 팩터 수: %d", length(allf))

found <- list()
for (p in TARGET) {
  hit <- grep(paste0("^", p, "_"), allf, value = TRUE)
  say("  %-4s -> %s", p, if (length(hit)) paste(hit, collapse=", ") else "★산출 없음")
  if (length(hit)) found[[p]] <- hit
}
## 양성 대조 · 음성 대조도 같은 방식으로 확인
for (p in c("D03","M26","M01")) {
  hit <- grep(paste0("^", p, "_"), allf, value = TRUE)
  say("  [대조] %-4s -> %s", p, if (length(hit)) paste(hit, collapse=", ") else "★산출 없음")
  if (length(hit)) found[[p]] <- hit
}
say("=== 확보 %d/%d (대상) ===", length(intersect(names(found), TARGET)), length(TARGET))
say("  ★미산출분은 라운드에서 제외하고 그 사실 자체를 기록한다(침묵 스킵 금지).")

## 커버리지 — 몇 개월 산출되나
say("=== 월별 산출 커버리지 (샘플 6개월) ===")
smp <- c("2005-06-30","2010-06-30","2015-06-30","2020-06-30","2024-06-30","2026-06-30")
cov <- rbindlist(lapply(smp, function(d) {
  Fx <- tryCatch(as.data.table(load_month_factors(d)), error = function(e) NULL)
  if (is.null(Fx)) return(data.table(date=d, factor=NA_character_, n=NA_integer_))
  rbindlist(lapply(unlist(found), function(f)
    data.table(date = d, factor = f, n = Fx[Factor_Name == f, .N])))
}))
print(dcast(cov[!is.na(factor)], factor ~ date, value.var = "n"))

saveRDS(list(found = found, cov = cov), file.path(OUT, "p0_avail.rds"))
say("=== P0 완료 ===")
