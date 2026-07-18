##=============================================================================
## run_decay_consolidate.R — FQ-055 최종 수집: SD 요약(크래시 보완) + break 대조
##   + break-year 차트 + 부활 트리거 밴드(armed artifact)
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/decay_fit"
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")

SM <- as.data.table(read_parquet(file.path(OUT, "decay_fit_SM_20260717.parquet")))
CM <- as.data.table(read_parquet(file.path(OUT, "decay_fit_CM_20260717.parquet")))
SD <- as.data.table(read_parquet(file.path(OUT, "decay_fit_SD_20260718.parquet")))
IC <- as.data.table(read_parquet(file.path(OUT, "sd_ic_daily_panel_20260718.parquet")))

## ── 1) SD conf-tier + break-year ──
wf("[SD] conf x label:")
print(dcast(SD[!is.na(conf_tier)], label ~ conf_tier, fun.aggregate = length))
sdb <- SD[label == "break_dominated" & !is.na(break_date)]; sdb[, yr := substr(break_date, 1, 4)]
wf("[SD] break-year hist:"); print(sdb[, .N, by = yr][order(yr)])

## ── 2) SD x CM break 대조 ──
cmp <- merge(SD[label == "break_dominated", .(factor, sd_break = break_date)],
             CM[basis == "capw" & label == "break_dominated", .(factor, cm_break = break_date)], by = "factor")
if (nrow(cmp)) cmp[, gap_m := round(as.numeric(difftime(as.Date(sd_break), as.Date(cm_break), units = "days")) / 30.44, 1)]
wf("[SDxCM] break 교집합 n=%d | median gap(m)=%.1f | |gap|<=18m 비율=%.2f",
   nrow(cmp), if (nrow(cmp)) median(cmp$gap_m) else NA, if (nrow(cmp)) mean(abs(cmp$gap_m) <= 18) else NA)

## ── 3) break-year 히스토그램 차트 (3계층) ──
png(file.path(OUT, "charts", "break_year_hist.png"), width = 1200, height = 420)
par(mfrow = c(1, 3), mar = c(5, 4, 3, 1))
for (pp in list(list(d = SM[label=="break_dominated"], ti = "S-M break-year (36m roll IC, lag~1.5y)"),
                list(d = CM[basis=="capw" & label=="break_dominated"], ti = "C-M capw break-year (60m roll SR, lag~2.5y)"),
                list(d = sdb, ti = "S-D break-year (252d roll IC1d, lag~6m)"))) {
  dd <- copy(pp$d)[!is.na(break_date)][, yr := as.integer(substr(break_date, 1, 4))]
  tb <- dd[, .N, by = yr][order(yr)]
  barplot(tb$N, names.arg = tb$yr, las = 2, main = pp$ti, col = "firebrick")
}
dev.off(); wf("chart break_year_hist.png written")

## ── 4) 부활 트리거 밴드 (armed) — post-break 레벨 잔차 밴드 ──
source("04_Research/decay_fit/decay_fit_engine.R")
bands <- list()
## SD (일간 IC — 재현 쉬움)
for (fc in sdb$factor) {
  sub <- IC[factor == fc][order(Date)]
  rl <- build_roll(sub$ic_oriented, sub$Date, 252, 200, "mean"); if (is.null(rl)) next
  fits <- fit_models(rl$y, rl$tvec / 21); if (is.null(fits) || is.null(fits$M4)) next
  p <- fits$M4$par
  post <- rl$y[seq_along(rl$y) >= p$tau]
  bands[[length(bands) + 1]] <- data.table(layer = "SD", basis = "ic1d", factor = fc,
    break_date = format(rl$dates[p$tau]), c1 = p$c1, c2 = p$c2, sigma_post = sd(post), n_post = length(post),
    trigger_up = p$c2 + 2 * sd(post), trigger_rule = "trailing 252d mean IC > c2+2*sigma_post (지속 63d) => revival flag")
}
## SM (월간 IC — pinned)
mic <- as.data.table(read_parquet(".cache/pins/decay_fit_20260717/factor_ic_monthly.parquet"))
mic[, Date := as.Date(Date)]
for (fc in SM[label == "break_dominated", factor]) {
  sub <- mic[Factor_Name == fc][order(Date)]
  rl <- build_roll(sub$IC, sub$Date, 36, 30, "mean"); if (is.null(rl)) next
  fits <- fit_models(rl$y, rl$tvec); if (is.null(fits) || is.null(fits$M4)) next
  p <- fits$M4$par
  post <- rl$y[seq_along(rl$y) >= p$tau]
  bands[[length(bands) + 1]] <- data.table(layer = "SM", basis = "ic", factor = fc,
    break_date = format(rl$dates[p$tau]), c1 = p$c1, c2 = p$c2, sigma_post = sd(post), n_post = length(post),
    trigger_up = p$c2 + 2 * sd(post), trigger_rule = "trailing 36m mean IC > c2+2*sigma_post (지속 3m) => revival flag")
}
BANDS <- rbindlist(bands)
write_parquet(BANDS, file.path(OUT, "revival_bands_20260718.parquet"))
wf("revival bands: %d rows (SD %d + SM %d) -> revival_bands_20260718.parquet",
   nrow(BANDS), BANDS[layer=="SD",.N], BANDS[layer=="SM",.N])

## ── 5) SD summary json (러너 크래시 보완) ──
summ <- list(round_id = "FQ-055_decay_fit_daily_SD", runtag = "20260718", metric_type = "diagnostic_fit",
  n_series = nrow(SD), labels = SD[, .N, by = label][order(-N)],
  conf = dcast(SD[!is.na(conf_tier)], label ~ conf_tier, fun.aggregate = length),
  break_year_hist = sdb[, .N, by = yr][order(yr)],
  break_compare_with_CM = if (nrow(cmp)) cmp else NULL,
  note = "러너 v1 문법오류로 요약만 크래시 — 적합 산출(parquet)은 러너 완료분. 본 파일이 요약 보완(런너 수정 완료)",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
write_json(summ, file.path(OUT, "decay_fit_SD_summary_20260718.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
wf("[consolidate] done")
