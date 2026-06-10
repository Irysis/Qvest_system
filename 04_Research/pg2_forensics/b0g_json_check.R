# b0g_json_check.R — validate all 4 JSON deliverables parse + UTF-8 intact
suppressPackageStartupMessages(library(jsonlite))
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/pg2_forensics"
for (f in c("b1_factor_ic_table.json","b1_redundancy_matrix.json",
            "b1_family_attribution.json","b1_oos27m_decomposition.json")) {
  d <- fromJSON(file.path(OUT, f))
  cat(f, ": parse OK | label:", substr(d$label, 1, 60), "\n")
}
d <- fromJSON(file.path(OUT, "b1_redundancy_matrix.json"))
cat("verdict:", d$verdict, "\n")
d2 <- fromJSON(file.path(OUT, "b1_factor_ic_table.json"))
cat("ic factors n:", length(d2$factors), "| first factor:", d2$factors[[1]]$factor,
    "mean_ic:", d2$factors[[1]]$mean_rank_ic, "\n")
