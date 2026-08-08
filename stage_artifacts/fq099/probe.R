## FQ-099 사전 확인 — 소스 혼합 실태 재확인(큐 서술을 그대로 믿지 않고 실측)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
f <- ".cache/fundamental_merged.parquet"
say("파일 %s (%.1f MB)", f, file.size(f)/1e6)
x <- read_parquet(f, as_data_frame=FALSE)
say("컬럼: %s", paste(names(x), collapse=", "))
D <- as.data.table(read_parquet(f))
say("행 %d", nrow(D))
if ("Source" %in% names(D)) {
  say("--- Source 분포 ---"); print(D[, .N, by=Source][order(-N)])
  qc <- intersect(c("q","Quarter","fq","period_q"), names(D))
  if (length(qc)) {
    say("--- Source x %s ---", qc[1])
    print(dcast(D[, .N, by=c("Source", qc[1])], get(qc[1]) ~ Source, value.var="N", fill=0))
  } else say("분기 컬럼 미발견 — 후보: %s", paste(head(names(D),20), collapse=","))
}
