## probe_a5_data_check.R — L. 지수 데이터 무결성 (2026 구간이 oos 게이트를 단독 담지하므로 원천 확인)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUTD <- "stage_artifacts/probe_a5_20260822"
sink(file.path(OUTD, "probe_a5_log5.txt"), split = TRUE)
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
cat(sprintf("[parquet] rows=%d cols=%d  범위 %s..%s\n", nrow(R), ncol(R), min(R$Date), max(R$Date)))
if("source_version" %in% names(R)) print(R[, .N, by=source_version])
if("as_of_date" %in% names(R)) cat(sprintf("as_of_date: %s\n", paste(unique(as.character(R$as_of_date)), collapse=",")))
R[, yr := as.integer(format(Date,"%Y"))]
cat("\n[연도별 일별 Market 통계] — 2026 이상 여부\n")
print(R[, .(n_days=.N, mean_d=round(mean(Market),5), sd_d=round(sd(Market),5),
            ann_vol=round(sd(Market)*sqrt(252),4), min_d=round(min(Market),4),
            max_d=round(max(Market),4), yr_ret=round(prod(1+Market)-1,4)), by=yr], nrows=30)
cat("\n[연도별 팩터지수 일별 변동성 중앙값]\n")
FV <- R[, lapply(.SD, function(x) sd(x, na.rm=TRUE)*sqrt(252)), by=yr, .SDcols=fac]
print(data.table(yr=FV$yr, med_ann_vol=round(apply(FV[,-1],1,median,na.rm=TRUE),4)), nrows=30)
cat("\n[2026 일별 Market 상위/하위 5]\n")
r26 <- R[yr==2026]
print(head(r26[order(-Market), .(Date, Market)],5)); print(head(r26[order(Market), .(Date, Market)],5))
cat("\n[2026-05 일별 Market + 상위 기여 팩터]\n")
print(R[format(Date,"%Y-%m")=="2026-05", .(Date, Market=round(Market,4), Crowding=round(Crowding,4),
        GPA=round(GPA,4), Quality=round(Quality,4))], nrows=30)
cat("\n[결측/영값 점검 — 연도별 팩터 NA 비율]\n")
print(R[, .(na_frac=round(mean(is.na(as.matrix(.SD))),4), zero_frac=round(mean(as.matrix(.SD)==0, na.rm=TRUE),4)),
        by=yr, .SDcols=fac], nrows=30)
cat("\nDATACHECK_DONE\n")
sink()
