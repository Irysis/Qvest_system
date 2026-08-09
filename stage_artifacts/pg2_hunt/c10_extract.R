## c10 — 종합 보고서의 후반 절(6~9) 추출
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
p <- file.path("C:/Users/99922/AppData/Local/Temp/claude",
               "C--Users-99922-OneDrive-Quant-Module-Moltbot",
               "832fa2fc-c147-4788-b363-4b17e97ed23e/tasks/wj0x4jxbh.output")
if (!file.exists(p)) { cat("파일 부재\n"); quit(status=0) }
txt <- paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
i <- regexpr('"report"', txt, fixed = TRUE)
r <- substring(txt, i)
r <- gsub("\\\\n", "\n", r); r <- gsub('\\\\"', '"', r)
## 보고서 본문만 저장 (재사용)
writeLines(r, "stage_artifacts/pg2_hunt/synthesis_report.md")
cat(sprintf("[c10] 보고서 %d자 저장 → synthesis_report.md\n", nchar(r)))
L <- strsplit(r, "\n", fixed = TRUE)[[1]]
st <- grep("^## [6789]\\.", L)
if (!length(st)) { cat("[c10] 절 6~9 미발견 — 헤딩 목록:\n"); print(head(grep("^#", L, value=TRUE), 20)); quit(status=0) }
for (k in seq_along(st)) {
  en <- if (k < length(st)) st[k+1L]-1L else min(st[k]+70L, length(L))
  cat(paste(L[st[k]:en], collapse = "\n"), "\n\n")
}
