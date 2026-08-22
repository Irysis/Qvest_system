## WT-D20260822_007 (FQ-246 NP1) P0 — hypothesis_index 조회절 (착수 전 의무)
source("02_Infrastructure/tools/hypothesis_index.R")
kws <- list("argmax", "oracle", "ceiling", "headroom", "sparsity", "concentration",
            "single_factor", c("factor","selection"), c("form","loss"),
            c("weight","concentration"), "softmax", "top_n")
for (kw in kws) {
  r <- try(lookup_hypothesis(keywords = kw, max_rows = 6), silent = TRUE)
  cat("\n##### ", paste(kw, collapse = "+"), " #####\n")
  if (inherits(r, "try-error") || is.null(r) || nrow(r) == 0) { cat("  (none)\n"); next }
  d <- as.data.frame(r)
  for (i in seq_len(nrow(d)))
    cat(sprintf("  %-28s | %-100s | %s\n", d$strategy_id[i], substr(d$title[i], 1, 100), d$verdict[i]))
}
cat("\nOK\n")
