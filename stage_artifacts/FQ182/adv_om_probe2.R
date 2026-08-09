## STEP 1b: macro_fred(long) + 기타 US 계열 탐색
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }

MF <- as.data.table(read_parquet(".cache/macro_fred.parquet"))
say("macro_fred: 행 %d · 열 %s", nrow(MF), paste(names(MF), collapse=", "))
print(utils::head(MF, 3))
for (c1 in names(MF)) if (is.character(MF[[c1]])) {
  u <- unique(MF[[c1]]); say("  %s: %d 고유 -> %s", c1, length(u), paste(utils::head(u, 60), collapse=" | "))
}
if ("series_id" %in% names(MF) || "series" %in% names(MF)) {
  kc <- intersect(c("series_id","series","id","name"), names(MF))[1]
  dc <- intersect(c("Date","date"), names(MF))[1]
  S <- MF[, .(n = .N, from = min(get(dc)), to = max(get(dc))), by = c(kc)][order(-n)]
  print(S)
}
