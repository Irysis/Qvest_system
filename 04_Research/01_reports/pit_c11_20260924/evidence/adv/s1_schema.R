suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE))
cat("macro_fred cols:", paste(names(m), collapse=","), "\n"); print(head(m,3))
idcol <- if ("Series_ID" %in% names(m)) "Series_ID" else "Series"
print(m[, .N, by=idcol])
m[, Date:=as.Date(Date)]
v <- m[get(idcol) %in% c("VIXCLS","VIX")]
cat("VIX around 2020-03-16 (known close 82.69 on 3/16; 3/13 57.83; 3/17 75.91):\n"); print(v[Date>=as.Date("2020-03-12") & Date<=as.Date("2020-03-18")])
cat("VIX 2008-11-20 (known close 80.86):\n"); print(v[Date>=as.Date("2008-11-19") & Date<=as.Date("2008-11-21")])
cat("VIX 2026-08-25..09-03:\n"); print(v[Date>=as.Date("2026-08-25") & Date<=as.Date("2026-09-03")])
rs <- open_dataset(file.path(C,"RAWDATA.parquet"))
cat("RAWDATA cols:", paste(names(rs$schema), collapse=","), "\n")
fd <- as.data.table(read_parquet(file.path(C,"factor_db","factor_db_202608.parquet"), mmap=FALSE))
cat("fdb cols:", paste(names(fd), collapse=","), "\n")
print(unique(fd$Date)); 
d32 <- fd[Factor_Name=="D32_Beta_VIX"]; cat("D32 rows", nrow(d32), "\n"); print(head(d32,3))
if ("Usable_Date" %in% names(fd)) print(unique(fd$Usable_Date))
