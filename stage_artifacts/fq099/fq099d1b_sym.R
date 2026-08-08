suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[d1b] ",fmt,"\n"),...))
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
dd  <- fread("stage_artifacts/fq099/fq099d1b_dedup.csv")
clean <- dd[dedup_flag==FALSE]$code
say("★입력 실측: 팩터 %d · 검사 대상(깨끗 후보) %d", length(reg), length(clean))

## 전 레지스터리의 dedup 텍스트에서 '파트너로 지목된' 코드 수집
partner <- character(0); owners <- list()
for (k in names(reg)) {
  d <- reg[[k]]$dedup; if (is.null(d)) next
  txt <- paste(unlist(d), collapse=" ")
  hit <- names(reg)[sapply(names(reg), function(o) o!=k && grepl(o, txt, fixed=TRUE))]  # ★fixed
  if (length(hit)) { partner <- c(partner, hit); for (h in hit) owners[[h]] <- c(owners[[h]], k) }
}
partner <- unique(partner)
say("dedup 텍스트에서 파트너로 지목된 코드 %d종", length(partner))
say("--- ★자기 항목엔 dedup 없는데 남이 지목한 코드 (비대칭) ---")
asym <- setdiff(partner, names(Filter(function(f) !is.null(f$dedup), reg)))
say("  전체 %d종", length(asym))
if (length(asym)) for (a in head(asym,20)) say("   %-28s ← 지목자: %s", a, paste(owners[[a]], collapse=" "))
say("--- 내 '깨끗한 26건' 중 남이 지목한 것 ---")
bad <- intersect(clean, partner)
say("  ★%d건: %s", length(bad), paste(bad, collapse=" "))
say("★정정 후 깨끗한 미탐색 = %d건", length(setdiff(clean, partner)))
writeLines(setdiff(clean, partner), "stage_artifacts/fq099/fq099d1_clean_final.txt")
