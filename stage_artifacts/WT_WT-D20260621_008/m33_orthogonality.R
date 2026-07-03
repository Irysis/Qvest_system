suppressMessages({library(arrow); library(data.table)})
arrow::set_io_thread_count(2L); setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
B <- readRDS("/tmp/m33_base.rds")
scores_dt <- B$scores_dt  # BASE IR_score
E <- readRDS("/tmp/m33_env.rds")
bench_dt <- E$bench_dt; returns_dt <- E$returns_dt

targets <- c("M01_Mom_12_1","M04_Mom_1","M11_ST_Reversal","M29_Mom_5d","M30_Mom_10d","L39_Overnight_Spread")
sig_dates <- sort(unique(scores_dt$Date))
# sample subset of sig_dates to keep it fast but representative (every month available)
percol <- list()
ok_dates <- 0
for(t in as.character(sig_dates)){
  fd <- tryCatch(load_month_factors(as.Date(t), factor_names=targets), error=function(e) NULL)
  if(is.null(fd) || nrow(fd)==0) next
  fw <- dcast(fd, Ticker~Factor_Name, value.var="Z_Score_Aligned")
  sc <- scores_dt[Date==as.Date(t), .(Ticker, score)]
  m <- merge(sc, fw, by="Ticker")
  if(nrow(m)<20) next
  ok_dates <- ok_dates+1
  row <- list(Date=t)
  for(fn in targets){
    if(fn %in% names(m)){
      v <- suppressWarnings(cor(m$score, m[[fn]], method="spearman", use="complete.obs"))
      row[[fn]] <- v
    } else row[[fn]] <- NA_real_
  }
  percol[[t]] <- as.data.table(row)
}
CR <- rbindlist(percol, fill=TRUE)
cat("matched months:", ok_dates, "\n\n=== ORTHOGONALITY: mean Spearman corr(IR_score, factor) ===\n")
for(fn in targets){
  if(fn %in% names(CR)){
    v <- CR[[fn]]; v<-v[is.finite(v)]
    cat(sprintf("%-22s mean_corr=%+.3f  sd=%.3f  n=%d\n", fn, mean(v), sd(v), length(v)))
  }
}
saveRDS(CR, "/tmp/m33_ortho.rds")
