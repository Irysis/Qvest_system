library(jsonlite)
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_D20260711_001"
r <- fromJSON(file.path(OUT,"excerpts.json"), simplifyDataFrame=FALSE)
cat("n docs:", length(r), "\n")
dir.create(file.path(OUT,"score_sheets"), showWarnings=FALSE)
chunks <- split(seq_along(r), ceiling(seq_along(r)/9))
for (ci in names(chunks)) {
  con <- file(file.path(OUT,"score_sheets",sprintf("chunk_%s.txt",ci)), open="w", encoding="UTF-8")
  for (i in chunks[[ci]]) {
    d <- r[[i]]
    writeLines(sprintf("################ %s (cell=%s) ################", d$doc_id, d$cell), con)
    writeLines(enc2utf8(d$excerpt), con)
    writeLines("", con); writeLines("", con)
  }
  close(con)
}
cat("wrote", length(chunks), "chunks\n")
