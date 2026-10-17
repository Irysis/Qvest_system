suppressMessages(library(data.table))
d <- "C:/qm_cache/factor_db/ic_direction_cache_v1"
stamp <- "_m36_20261006134323_1426314.rds"
fs <- list.files(d, pattern = paste0("^ic_dir_\\d{4}06\\d{2}", gsub(".", "\\.", stamp, fixed = TRUE), "$"))
want <- c("V01_BM", "Q01_GPA", "Q06_Asset_Growth")
out <- rbindlist(lapply(fs, function(f) {
  x <- readRDS(file.path(d, f))
  x <- as.data.table(x)[Factor_Name %in% want]
  if (!nrow(x)) return(NULL)
  x[, file_date := substr(f, 8, 15)]
  x
}), fill = TRUE)
setorder(out, Factor_Name, file_date)
print(out[, .(file_date, Factor_Name, Mean_IC = round(Mean_IC, 5), ic_sign, N_IC)], nrows = 500)
cat("\nflip rows (ic_sign == -1):\n")
print(out[ic_sign == -1L])
