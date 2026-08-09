## S1 — 존재 축: emission_ledger.csv 재판독 (재빌드 없음, 읽기만)
##   축1 = 산출 월수 · 행수 · 최종 배출월 · registry active 대조
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/factor_emission_identity_20260809")
say <- function(fmt, ...) { cat(sprintf(paste0("[s1] ", fmt, "\n"), ...)); flush.console() }

LED <- ".cache/factor_db/emission_ledger.csv"
led <- fread(LED, colClasses = list(character = "ym"))
say("ledger 행 %d · 컬럼 %s", nrow(led), paste(names(led), collapse = "|"))
stopifnot(nrow(led) > 0)
say("ym 범위 %s ~ %s · 고유 ym %d · 고유 Factor %d",
    min(led$ym), max(led$ym), uniqueN(led$ym), uniqueN(led$Factor_Name))
say("built_at 범위 %s ~ %s", min(led$built_at), max(led$built_at))

## 이번 재빌드(20260809) 로 쓰인 행 비율 — 원장이 현행 빌드를 반영하는지 확인
led[, built_day := substr(built_at, 1, 10)]
print(led[, .N, by = built_day][order(-N)][1:5])

## registry active
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
say("registry 항목 %d", length(reg))
regm <- rbindlist(lapply(names(reg), function(k) {
  e <- reg[[k]]
  st <- tryCatch(as.character(e$lifecycle$status)[1], error = function(z) NA_character_)
  ca <- tryCatch(as.character(e$category)[1], error = function(z) NA_character_)
  data.table(Factor_Name = k, category = if (length(ca)) ca else NA_character_,
             status = if (length(st) && !is.null(st)) st else NA_character_)
}))
say("status 분포: %s", paste(sprintf("%s=%d", names(table(regm$status, useNA = "ifany")),
                                     as.integer(table(regm$status, useNA = "ifany"))), collapse = " "))
active <- regm[status == "active", Factor_Name]
say("registry active %d", length(active))

## 팩터별 존재 요약
ex <- led[n_rows > 0, .(n_months = uniqueN(ym), tot_rows = sum(n_rows),
                        first_ym = min(ym), last_ym = max(ym),
                        med_tickers = as.numeric(median(n_tickers))), by = Factor_Name]
setorder(ex, -n_months)
say("배출 이력 있는 팩터 %d종", nrow(ex))

## 최신월(202608) 배출
ym_last <- max(led$ym)
cur <- led[ym == ym_last & n_rows > 0]
say("최신월 %s 배출 팩터 %d종", ym_last, nrow(cur))

ex[, in_registry_active := Factor_Name %in% active]
ex[, emitted_last_ym := Factor_Name %in% cur$Factor_Name]
say("배출이력 있으나 registry active 아님: %d종", ex[in_registry_active == FALSE, .N])
say("registry active 인데 원장에 배출 이력 0: %d종",
    length(setdiff(active, ex$Factor_Name)))
never <- sort(setdiff(active, ex$Factor_Name))
if (length(never)) say("  → %s", paste(never, collapse = ", "))

fwrite(ex, file.path(OUT, "s1_existence_by_factor.csv"))
fwrite(regm, file.path(OUT, "s1_registry_meta.csv"))

## 표본월 후보에서 실제 배출된 팩터 수 (샘플 설계 근거)
SAMP <- c("200506", "201006", "201406", "201806", "202206", "202606")
for (s in SAMP) {
  k <- led[ym == s & n_rows > 0]
  say("표본월 %s → 배출 팩터 %d종 · 총행 %s", s, nrow(k), format(sum(k$n_rows), big.mark = ","))
}
say("완료")
