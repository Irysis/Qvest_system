setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages(library(data.table))
d <- "04_Research/strategies/RF_B2_8_InvVol"
for (nm in c("stage","stage_ctrl")) {
  b <- readRDS(Sys.glob(file.path(d,nm,"*","bt_result.rds")))
  h <- as.data.table(b$holdings)[, .(Date = as.Date(date), Ticker = ticker, W = target_weight)]
  ds <- sort(unique(h$Date)); to <- numeric(0); nm_ch <- numeric(0)
  for (i in 2:length(ds)) {
    a <- h[Date==ds[i]]; p <- h[Date==ds[i-1]]
    all_t <- union(a$Ticker,p$Ticker)
    wa <- setNames(a$W,a$Ticker)[all_t]; wa[is.na(wa)] <- 0
    wp <- setNames(p$W,p$Ticker)[all_t]; wp[is.na(wp)] <- 0
    to <- c(to, sum(abs(wa-wp)))
    nm_ch <- c(nm_ch, length(setdiff(a$Ticker,p$Ticker)))
  }
  cat(sprintf("== %-10s | monthly sum|dw| mean %.4f -> annual %.0f%% | 신규편입 종목수/월 mean %.2f\n",
              nm, mean(to), mean(to)*12*100, mean(nm_ch)))
}
