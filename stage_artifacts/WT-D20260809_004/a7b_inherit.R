setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(arrow) })
say <- function(fmt, ...) cat(sprintf(paste0("[A7b] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
L <- readRDS(file.path(OUT, "layers.rds")); SC <- L$SC
safe_ic <- function(a, b, minn = 30L) {
  ok <- is.finite(a) & is.finite(b); if (sum(ok) < minn) return(NA_real_)
  suppressWarnings(stats::cor(a[ok], b[ok], method = "spearman"))
}
BASE <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
say("base 패널 %s행 · Date %d (%s ~ %s) · Ticker %d",
    format(nrow(BASE), big.mark=","), uniqueN(BASE$Date),
    as.character(min(BASE$Date)), as.character(max(BASE$Date)), uniqueN(BASE$Ticker))
B2 <- BASE[, .(Date = as.Date(Date), Ticker, score_eff, score_core_z, score_defense_z)]
MM <- merge(SC[, .(Date = sig_date, Ticker, growth)], B2, by = c("Date","Ticker"))
say("교집합 %s행 · %d월", format(nrow(MM), big.mark=","), uniqueN(MM$Date))
for (cc in c("score_eff","score_core_z","score_defense_z")) {
  cs <- MM[, .(rho = safe_ic(growth, get(cc))), by = Date][!is.na(rho)]
  say("  growth vs %-16s 월별 횡단면 Spearman 평균 %+.4f · sd %.3f · n=%d월 → 문턱 0.95 %s",
      cc, mean(cs$rho), sd(cs$rho), nrow(cs), if (abs(mean(cs$rho)) < 0.95) "PASS" else "FAIL")
}
## top-25 이름 중복
top_ov <- MM[, {
  a <- Ticker[frank(-growth, ties.method="first") <= 25]
  b <- Ticker[frank(-score_eff, ties.method="first") <= 25]
  .(ov = length(intersect(a,b)))
}, by = Date]
say("  top-25 이름 중복: 평균 %.2f종 / 25 (중앙 %d · 최대 %d)",
    mean(top_ov$ov), as.integer(median(top_ov$ov)), max(top_ov$ov))
saveRDS(list(inh_score_eff = MM[, .(rho = safe_ic(growth, score_eff)), by = Date][!is.na(rho)][, mean(rho)],
             top_overlap_mean = mean(top_ov$ov)), file.path(OUT, "inherit.rds"))
