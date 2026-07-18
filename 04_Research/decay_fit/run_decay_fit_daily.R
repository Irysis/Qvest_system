##=============================================================================
## run_decay_fit_daily.R — FQ-055 S-D 계층 (일간 IC 감쇠 적합, carve-out 승인분)
## Stage1: fdb_daily(174팩터) x 유니버스 x fwd1d → 일간 Spearman IC 패널 (캐시)
## Stage2: rolling 252d mean IC → 공용 엔진 적합 + C-M break 대조
## prereg: stage_artifacts/decay_fit/preregistration_SD.json
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite); library(digest) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/decay_fit"
RUNTAG <- "20260718"
LOG <- file.path(OUT, "_run_log_SD.txt")
wf <- function(fmt, ...) { m <- sprintf(fmt, ...); cat(m, "\n"); cat(m, "\n", file = LOG, append = TRUE) }
t0 <- Sys.time(); set.seed(20260718)
source("04_Research/decay_fit/decay_fit_engine.R")
wf("=== FQ-055 S-D start %s ===", format(t0))

PANEL_PATH <- file.path(OUT, sprintf("sd_ic_daily_panel_%s.parquet", RUNTAG))

if (!file.exists(PANEL_PATH)) {
  ## ── Stage 1: 일간 IC 패널 ───────────────────────────────────────────────
  reg <- fromJSON(".cache/factor_db_daily/factor_db_daily_registry.json")
  FACS <- reg$factor_list
  wf("stage1: factors=%d files=%d", length(FACS), reg$n_months)

  rw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select = c("Date", "Ticker", "Ret", "K200", "KQ150")))
  rw[, Date := as.Date(Date)]
  setorder(rw, Ticker, Date)
  rw[, fwd1 := shift(Ret, type = "lead"), by = Ticker]
  ## shift 방향 기계 검증 (convention 룰): 표본 3티커 x 3일
  ok_all <- TRUE
  for (tk in c("A005930", "A000660", "A035420")) {
    s <- rw[Ticker == tk][1000:1003]
    if (nrow(s) == 4) {
      chk <- all(abs(s$fwd1[1:3] - s$Ret[2:4]) < 1e-12, na.rm = TRUE)
      wf("  shift-validate %s: %s", tk, ifelse(chk, "PASS", "FAIL")); ok_all <- ok_all && chk
    }
  }
  stopifnot(ok_all)
  uni <- rw[(K200 == TRUE | KQ150 == TRUE) & !is.na(fwd1), .(Date, Ticker, fwd1)]
  rm(rw); invisible(gc())
  setkey(uni, Date, Ticker)
  wf("stage1: universe fwd rows=%d dates=%d", nrow(uni), uniqueN(uni$Date))

  files <- sort(list.files(".cache/factor_db_daily", pattern = "^fdb_daily_\\d{6}\\.parquet$", full.names = TRUE))
  sch1 <- names(ParquetFileReader$create(files[[1]])$GetSchema())
  fac_all <- intersect(FACS, sch1)
  wf("stage1: usable factor cols=%d (of registry %d)", length(fac_all), length(FACS))
  ic_rows <- vector("list", length(files))
  for (fi in seq_along(files)) {
    f <- files[fi]
    dt <- as.data.table(read_parquet(f, col_select = all_of(c("Date", "Ticker", fac_all))))
    dt[, Date := as.Date(Date)]
    dt <- merge(dt, uni, by = c("Date", "Ticker"))
    if (!nrow(dt)) { ic_rows[[fi]] <- NULL; next }
    part <- dt[, {
      fr <- frank(fwd1, na.last = "keep")
      ics <- vapply(.SD, function(x) {
        okp <- !is.na(x) & !is.na(fr)
        if (sum(okp) < 100) NA_real_ else suppressWarnings(cor(frank(x[okp]), fr[okp]))
      }, numeric(1))
      list(factor = names(.SD), ic = ics, n_pairs = sum(!is.na(fwd1)))
    }, by = Date, .SDcols = fac_all]
    ic_rows[[fi]] <- part[!is.na(ic)]
    if (fi %% 40 == 0) wf("  stage1 %d/%d files (%.1f min)", fi, length(files), as.numeric(difftime(Sys.time(), t0, units = "mins")))
  }
  IC <- rbindlist(ic_rows)
  ## orientation: pinned 월간 IC mean sign
  micp <- ".cache/pins/decay_fit_20260717"
  mic <- as.data.table(read_parquet(file.path(micp, "factor_ic_monthly.parquet")))
  orient <- mic[, .(sgn = sign(mean(IC, na.rm = TRUE))), by = Factor_Name]
  IC <- merge(IC, orient, by.x = "factor", by.y = "Factor_Name", all.x = TRUE)
  IC[is.na(sgn) | sgn == 0, sgn := 1]
  IC[, ic_oriented := ic * sgn]
  write_parquet(IC, PANEL_PATH)
  wf("stage1 done: IC rows=%d factors=%d dates=%d (%.1f min)", nrow(IC), uniqueN(IC$factor), uniqueN(IC$Date),
     as.numeric(difftime(Sys.time(), t0, units = "mins")))
} else {
  IC <- as.data.table(read_parquet(PANEL_PATH))
  wf("stage1 cache reuse: %d rows", nrow(IC))
}

## ── Stage 2: 적합 ──────────────────────────────────────────────────────────
elig <- IC[, .N, by = factor][N >= 2500, factor]
wf("stage2: eligible %d / %d", length(elig), uniqueN(IC$factor))
rows <- list()
for (i in seq_along(elig)) {
  fc <- elig[i]
  sub <- IC[factor == fc][order(Date)]
  res <- run_one(sub$ic_oriented, sub$Date, w = 252, minobs = 200, stat = "mean",
                 n_boot = 60, min_n_fit = 1000, block = 63, t_scale = 21)
  rows[[i]] <- as_row(res, list(layer = "SD", basis = "ic1d", factor = fc, family = NA_character_))
  if (i %% 20 == 0) wf("  stage2 %d/%d (%.1f min)", i, length(elig), as.numeric(difftime(Sys.time(), t0, units = "mins")))
}
SD <- rbindlist(rows, fill = TRUE)
write_parquet(SD, file.path(OUT, sprintf("decay_fit_SD_%s.parquet", RUNTAG)))
wf("S-D done: %d rows. label dist: %s", nrow(SD),
   paste(capture.output(print(SD[, .N, by = label][order(-N)])), collapse = " | "))

## C-M capw break 대조 (교집합 팩터)
CM <- as.data.table(read_parquet(file.path(OUT, "decay_fit_CM_20260717.parquet")))
cmp <- merge(SD[label == "break_dominated", .(factor, sd_break = break_date)],
             CM[basis == "capw" & label == "break_dominated", .(factor, cm_break = break_date)], by = "factor")
if (nrow(cmp)) { cmp[, gap_m := round(as.numeric(difftime(as.Date(sd_break), as.Date(cm_break), units = "days")) / 30.44, 1)] }
wf("break 대조: 교집합 %d건", nrow(cmp))
summ <- list(round_id = "FQ-055_decay_fit_daily_SD", runtag = RUNTAG, metric_type = "diagnostic_fit",
             n_series = nrow(SD), labels = SD[, .N, by = label][order(-N)],
             break_compare_n = nrow(cmp), break_compare = if (nrow(cmp)) cmp else NULL,
             runtime_min = as.numeric(difftime(Sys.time(), t0, units = "mins")),
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
write_json(summ, file.path(OUT, sprintf("decay_fit_SD_summary_%s.json", RUNTAG)), auto_unbox = TRUE, pretty = TRUE, digits = 6)
wf("=== S-D ALL DONE %.1f min ===", as.numeric(difftime(Sys.time(), t0, units = "mins")))
