suppressPackageStartupMessages({library(data.table)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
S <- readRDS("stage_artifacts/WT-D20260821_002/step0_inputs.rds")
frd <- as.data.table(S$frd)
for (nm in c("armA","armB","armC")) {
  p <- as.data.table(S$panels[[nm]]); col <- if (nm == "armB") "q50" else "score"
  P <- p[, .(Date, Ticker, sc = as.numeric(get(col)))]
  X <- merge(P, frd[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  X <- X[is.finite(sc) & is.finite(Ret_1m)]
  d <- X[, .(n = .N, sd_sc = sd(sc), sd_r = sd(Ret_1m)), by = Date]
  cat(nm, "months", nrow(d), "| sd_sc==0:", sum(d$sd_sc == 0, na.rm = TRUE),
      "| sd_r==0:", sum(d$sd_r == 0, na.rm = TRUE), "| min_n:", min(d$n),
      "| n_months_with_lt5:", sum(d$n < 5), "\n")
}
