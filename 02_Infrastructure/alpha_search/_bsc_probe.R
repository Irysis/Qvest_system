suppressWarnings(suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
}))
r <- load_rawdata(use_cache = TRUE); R <- r$RAWDATA
sink("02_Infrastructure/alpha_search/_bsc_probe.txt")
cat("K200 class:", class(R$K200)[1], "| KQ150 class:", class(R$KQ150)[1], "\n")
cat("K200 vals:", paste(head(unique(R$K200), 6), collapse = ","), "\n")
cat("KQ150 vals:", paste(head(unique(R$KQ150), 6), collapse = ","), "\n")
d <- max(R$Date); sub <- R[Date == d]
cat("at", as.character(d), "K200:", sum(sub$K200 %in% c(TRUE, 1), na.rm = TRUE),
    "KQ150:", sum(sub$KQ150 %in% c(TRUE, 1), na.rm = TRUE), "\n")
d2 <- R[format(Date, "%Y-%m") == "2010-06", max(Date)]; sub2 <- R[Date == d2]
cat("at", as.character(d2), "K200:", sum(sub2$K200 %in% c(TRUE, 1), na.rm = TRUE),
    "KQ150:", sum(sub2$KQ150 %in% c(TRUE, 1), na.rm = TRUE), "\n")
q <- quantile(sub$Size[is.finite(sub$Size)], c(0, .5, 1))
cat("Size q0/q50/q1:", paste(format(q, scientific = TRUE, digits = 3), collapse = " "), "\n")
cat("Ret sample summary:\n"); print(summary(R$Ret[is.finite(R$Ret)][1:1000000]))
cat("LiqPass present:", "LiqPass" %in% names(R), "\n")
sink()
