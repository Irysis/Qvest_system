suppressPackageStartupMessages(library(data.table))
D <- fread("04_Research/strategies/RF_B2_9_MinVarLW/lw_diagnostics.csv")[Date>=as.Date("2005-01-01")]
cat("2008-01~2009-06 (KR 위기 구간):\n"); print(D[Date>=as.Date("2008-01-01") & Date<=as.Date("2009-06-30"), .(Date, mode, n_obs, delta=round(delta,3), w_max=round(w_max,3), n_eff=round(n_eff,1))])
cat("\n2020-01~2020-12 (코로나):\n"); print(D[Date>=as.Date("2020-01-01") & Date<=as.Date("2020-12-31"), .(Date, mode, n_obs, delta=round(delta,3), w_max=round(w_max,3))])
