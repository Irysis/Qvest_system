# diag_components.R — B1-5 성분 기여 구조 진단 (성과 수치 아님 — 선택 구조만)
#   (a) 최종 top-25 와 성분 단독 top-25 의 월별 중첩률
#   (b) 선택 종목의 성분 rank-Z 평균 (어느 축이 선택을 끌었나)
# 등급·성과 수치는 authoritative_remeasure.json(계약)만 인용 — 여기선 산출하지 않는다.
suppressPackageStartupMessages(library(data.table))
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT)
setwd(PROJECT_ROOT)
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
setorder(RAWDATA, Ticker, Date)

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2005-01-01")]

RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  is.finite(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(.mem, Date, Ticker)
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
setkey(.mom_all, Date, Ticker)

.rank_z <- function(x) {
  r <- frank(x, ties.method = "average", na.last = "keep")
  mu <- mean(r, na.rm = TRUE); s <- sd(r, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mu) / s
}

rows <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = "L01_Amihud"),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  ilq <- fdt[Factor_Name == "L01_Amihud" & is.finite(Z_Score_Aligned),
             .(Ticker, Ilq = Z_Score_Aligned)][Ticker %in% uni_tk]
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L][Ticker %in% uni_tk]
  cmb <- merge(ilq, mom, by = "Ticker")
  if (nrow(cmb) < 30L) next
  cmb[, Zm := .rank_z(Mom)]; cmb[, Zi := .rank_z(Ilq)]
  cmb <- cmb[is.finite(Zm) & is.finite(Zi)]
  if (nrow(cmb) < 30L) next
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]
  sel  <- cmb[order(-Score)][1:25, Ticker]
  selm <- cmb[order(-Zm)][1:25, Ticker]
  seli <- cmb[order(-Zi)][1:25, Ticker]
  rows[[i]] <- data.table(
    Date = d, n_uni = nrow(cmb),
    ov_mom = length(intersect(sel, selm)) / 25,
    ov_ilq = length(intersect(sel, seli)) / 25,
    zm_sel = cmb[Ticker %in% sel, mean(Zm)],
    zi_sel = cmb[Ticker %in% sel, mean(Zi)],
    cor_mi = cor(cmb$Zm, cmb$Zi))
}
dg <- rbindlist(Filter(Negate(is.null), rows))
cat(sprintf("[diag] months=%d | overlap(final,mom-only) median %.2f | overlap(final,ilq-only) median %.2f\n",
            nrow(dg), median(dg$ov_mom), median(dg$ov_ilq)))
cat(sprintf("[diag] selected mean rank-Z: mom %.2f | illiq %.2f | cor(Zm,Zi) median %+.3f\n",
            median(dg$zm_sel), median(dg$zi_sel), median(dg$cor_mi)))
saveRDS(dg, "04_Research/strategies/RF_B1_5_MomIlliq/component_diag.rds")
