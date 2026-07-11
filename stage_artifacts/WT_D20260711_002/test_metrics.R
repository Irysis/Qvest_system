source("metrics_lib.R")
library(jsonlite)
ex <- fromJSON("../WT_D20260711_001/excerpts.json")
for (i in 1:3) {
  s <- ex$excerpt[i]
  m <- compute_metrics(strip_all(s))
  cat(sprintf("doc %s: sentlen=%.1f fog=%.1f hanjaLat=%.3f numDen=%.3f nchar=%d nsent=%d nwords=%d\n",
    ex$doc_id[i], m$m1_avg_sentence_len_chars, m$m2_fog_kr, m$m3_hanja_latin_density,
    m$m4_numeric_table_density, m$m5_section_nchar, m$n_sentences, m$n_words))
}
cat("OK\n")
