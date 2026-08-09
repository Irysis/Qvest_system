setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(arrow) })
E <- as.data.table(read_parquet(".cache/ecos_bond_rates.parquet"))
tb <- E[, .(N = .N, from = as.character(min(Date)), to = as.character(max(Date))), by = Series][order(Series)]
cat("ecos_bond_rates.parquet series:\n")
for (i in seq_len(nrow(tb)))
  cat(sprintf("  %-16s %6d  %s ~ %s\n", tb$Series[i], tb$N[i], tb$from[i], tb$to[i]))
if ("KR_CPI" %in% tb$Series) {
  C <- E[Series == "KR_CPI"][order(Date)]
  cat(sprintf("\nKR_CPI 관측단위 확인: 고유 Date %d · 간격 중앙값 %.0f일\n",
              uniqueN(C$Date), median(as.numeric(diff(sort(unique(C$Date)))))))
  print(utils::head(C, 4)); print(utils::tail(C, 4))
}
cat("\n--- ECOS API key 존재 여부 ---\n")
for (k in c("ECOS_API_KEY", "BOK_API_KEY", "ECOS_KEY"))
  cat(sprintf("  %s = %s\n", k, if (nzchar(Sys.getenv(k))) "SET" else "(없음)"))
