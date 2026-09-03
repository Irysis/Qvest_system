PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
suppressMessages(library(arrow)); suppressMessages(library(data.table))
h <- fread("04_Research/strategies/RF_B3_13_SmallCap/stage/20260829_233235_5336/04_holdings.csv")
cat("holdings cols:", paste(names(h), collapse = ","), "\n")
tkcol <- if ("ticker" %in% names(h)) "ticker" else if ("Ticker" %in% names(h)) "Ticker" else names(h)[grepl("tick", names(h), ignore.case = TRUE)][1]
hold_tk <- unique(h[[tkcol]])
cat("고유 보유 종목 수:", length(hold_tk), "\n")

d <- as.data.table(read_parquet(".cache/rawdata.parquet"))
last <- max(d$Date)
tk <- d[, .(last_obs = max(Date)), by = Ticker]
delisted <- tk[last_obs < last - 30]
cat("패널 상장폐지(최종관측 < 마지막-30일) 종목:", nrow(delisted), "\n")
cat("★그 중 실제로 보유된 적 있는 종목:", sum(hold_tk %in% delisted$Ticker),
    sprintf(" (보유 유니버스의 %.1f%%)\n", 100 * mean(hold_tk %in% delisted$Ticker)))
