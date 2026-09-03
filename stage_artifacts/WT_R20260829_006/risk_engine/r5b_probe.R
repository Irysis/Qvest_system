suppressPackageStartupMessages({library(data.table);library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
S <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
O <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/risk006"
mk<-readRDS(file.path(S,"p1s_market.rds")); L<-mk$LIQ_DT
cat("LIQ dates tail:", as.character(tail(sort(unique(L$Date)),3)),"\n")
cat("rows at 2026-08-28:", nrow(L[Date==as.Date("2026-08-28")]),
    " non-NA adv:", sum(is.finite(L[Date==as.Date("2026-08-28")]$adv)),"\n")
cat("rows at 2026-07-31:", nrow(L[Date==as.Date("2026-07-31")]),
    " non-NA adv:", sum(is.finite(L[Date==as.Date("2026-07-31")]$adv)),"\n")
cat("liq_ruler:", mk$liq_ruler, "\n")
R3<-readRDS(file.path(O,"r3_sigma.rds")); cat("R3 U rows:", nrow(R3$U),"\n")
R4<-readRDS(file.path(O,"r4_diag.rds")); cat("R4 U rows:", nrow(R4$U),"\n")
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Vol","Close")))
RAW[, Date:=as.Date(Date)]
cat("raw max date:", as.character(max(RAW$Date)), "\n")
cat("Vol summary at last date:\n"); print(summary(RAW[Date==max(Date)]$Vol))
