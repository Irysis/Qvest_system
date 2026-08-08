suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099d2] ",fmt,"\n"),...))
ment <- readLines("stage_artifacts/fq099/fq099d_mentioned.txt")
say("언급 있는 유량의존 팩터 %d건: %s", length(ment), paste(ment, collapse=" "))
ki <- fromJSON("06_Registry/knowledge_index.json", simplifyVector=FALSE)
hi <- fromJSON("06_Registry/hypothesis_index.json", simplifyVector=FALSE)
flat <- function(x) if (is.list(x)) unlist(lapply(x, function(y) paste(unlist(y), collapse=" | "))) else as.character(x)
ktxt <- flat(ki); htxt <- flat(hi)
say("knowledge_index 항목 %d · hypothesis_index 항목 %d", length(ktxt), length(htxt))
for (k in ment) {
  say("=== %s ===", k)
  for (nm in c("knowledge","hypothesis")) {
    v <- if (nm=="knowledge") ktxt else htxt
    hit <- which(sapply(v, function(s) grepl(k, s, fixed=TRUE)))   # ★fixed 필수
    if (!length(hit)) next
    for (i in head(hit,2)) {
      s <- v[[i]]
      ## 판정 어휘 주변만 발췌
      pos <- regexpr(k, s, fixed=TRUE)
      say("  [%s] ...%s...", nm, gsub("[[:space:]]+"," ", substr(s, max(1,pos-150), min(nchar(s), pos+220))))
    }
  }
}
