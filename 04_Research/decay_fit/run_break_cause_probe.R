##=============================================================================
## run_break_cause_probe.R — FQ-055 P2: 2015-16 공통 단절의 원인 귀속 1차 실측
## Q: 왜 대부분의 팩터에서 동시에? → 공통성분 후보 실측
##  (a) 벤치 집중도(top-10 cap share) 시계열의 자체 단절 시점
##  (b) 소형-대형 forward return 스프레드(sml)의 단절 시점
##  (c) 77 break 팩터 평균 active_bm의 단절이 sml 통제 후 얼마나 소멸하는가
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(dplyr); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/decay_fit"
source("04_Research/decay_fit/decay_fit_engine.R")
source("02_Infrastructure/ramp/factor_validation.R")
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")
cusum_date <- function(u, dts) { ok <- !is.na(u); u <- u[ok]; d <- dts[ok]; cs <- cumsum(u - mean(u)); d[which.max(abs(cs))] }

## ── 데이터: 월말 유니버스 + forward + Size ──
r6 <- as.data.table(read_parquet(".cache/pins/decay_fit_20260717/r6_factor_deployzone_active.parquet"))
r6[, signal_date := as.Date(signal_date)]
sigs <- sort(unique(r6$signal_date))
month_end <- function(d) { m0 <- as.Date(cut(d, "month")); seq(m0, by = "1 month", length.out = 2)[2] - 1 }
sigs_ext <- c(sigs, month_end(max(sigs) + 1))
ud <- sort(unique(as.Date(as.data.table(read_parquet(".cache/rawdata.parquet", col_select = "Date"))$Date)))
me <- unique(as.Date(vapply(sigs_ext, function(d) { v <- ud[ud <= d]; if (length(v)) as.character(max(v)) else NA_character_ }, character(1))))
me <- me[!is.na(me)]
.need <- c("Date", "Ticker", "Close", "K200", "KQ150", "Vol", "Size")
raw_me <- as.data.table(open_dataset(".cache/rawdata.parquet") |> filter(Date %in% me) |> select(all_of(.need)) |> collect())
raw_me[, Date := as.Date(Date)]
fwd <- build_monthly_forward_returns(raw_me, sigs_ext)
ret <- fwd$returns_dt[, .(signal_date = as.Date(Date), Ticker, Ret_1m)]

## Size(월말, 유니버스) — 신호월 매핑
me_map <- data.table(Date = me)
me_map[, signal_date := as.Date(vapply(Date, function(d) as.character(min(sigs_ext[sigs_ext >= d])), character(1)))]
sz <- merge(raw_me[(K200 == TRUE | KQ150 == TRUE) & !is.na(Size) & Size > 0, .(Date, Ticker, Size)], me_map, by = "Date")
sz <- sz[signal_date %in% sigs]

## (a) 벤치 집중도: top-10 / top-30 cap share
conc <- sz[, { s <- sort(Size, decreasing = TRUE); .(top10 = sum(s[1:10]) / sum(s), top30 = sum(s[1:min(30, .N)]) / sum(s)) }, by = signal_date][order(signal_date)]
f10 <- fit_models(conc$top10, seq_len(nrow(conc)) - 1)
b10 <- if (!is.null(f10$M4)) conc$signal_date[f10$M4$par$tau] else NA
wf("[a] top-10 집중도: CUSUM=%s | M4 break=%s | 수준 2005-14 mean=%.3f -> 2017+ mean=%.3f",
   format(cusum_date(conc$top10, conc$signal_date)), format(b10),
   conc[signal_date < "2015-01-01", mean(top10)], conc[signal_date >= "2017-01-01", mean(top10)])

## (b) 소형-대형 스프레드: MEGA(top-30) vs REST forward EW
tier <- merge(ret, sz[, .(signal_date, Ticker, Size)], by = c("signal_date", "Ticker"))
tier[, rk := frankv(Size, order = -1L), by = signal_date]
sml <- tier[, .(sml = mean(Ret_1m[rk > 30], na.rm = TRUE) - mean(Ret_1m[rk <= 30], na.rm = TRUE)), by = signal_date][order(signal_date)]
wf("[b] 소형-대형 스프레드: CUSUM=%s | pre-2015 mean(월)=%.4f -> 2016+ mean=%.4f",
   format(cusum_date(sml$sml, sml$signal_date)),
   sml[signal_date < "2015-01-01", mean(sml, na.rm = TRUE)], sml[signal_date >= "2016-01-01", mean(sml, na.rm = TRUE)])

## (c) 77 break 팩터 평균 active_bm — sml 통제 전/후 단절 크기
CM <- as.data.table(read_parquet(file.path(OUT, "decay_fit_CM_20260717.parquet")))
bfacs <- CM[basis == "capw" & label == "break_dominated", factor]
avg <- r6[factor_id %in% bfacs, .(a = mean(active_bm, na.rm = TRUE)), by = signal_date][order(signal_date)]
avg <- merge(avg, sml, by = "signal_date")
cd_raw <- cusum_date(avg$a, avg$signal_date)
split_d <- as.Date("2016-01-01")
sh_raw <- avg[signal_date >= split_d, mean(a)] - avg[signal_date < split_d, mean(a)]
fitc <- lm(a ~ sml, data = avg)
avg[, resid := residuals(fitc)]
cd_res <- cusum_date(avg$resid, avg$signal_date)
sh_res <- avg[signal_date >= split_d, mean(resid)] - avg[signal_date < split_d, mean(resid)]
wf("[c] 77팩터 평균 active: CUSUM=%s | 2016 전후 mean shift=%.4f/월", format(cd_raw), sh_raw)
wf("[c] sml 회귀 통제(R2=%.2f, beta=%.2f) 후: 잔차 CUSUM=%s | shift=%.4f/월 | 단절 크기 잔존율=%.2f",
   summary(fitc)$r.squared, coef(fitc)[2], format(cd_res), sh_res, sh_res / sh_raw)

write_json(list(a_conc_cusum = format(cusum_date(conc$top10, conc$signal_date)), a_conc_m4 = format(b10),
                a_top10_pre2015 = conc[signal_date < "2015-01-01", mean(top10)], a_top10_post2017 = conc[signal_date >= "2017-01-01", mean(top10)],
                b_sml_cusum = format(cusum_date(sml$sml, sml$signal_date)),
                b_sml_pre2015 = sml[signal_date < "2015-01-01", mean(sml, na.rm = TRUE)], b_sml_post2016 = sml[signal_date >= "2016-01-01", mean(sml, na.rm = TRUE)],
                c_avg_cusum = format(cd_raw), c_shift_raw = sh_raw, c_r2 = summary(fitc)$r.squared,
                c_resid_cusum = format(cd_res), c_shift_resid = sh_res, c_shift_remain = sh_res / sh_raw,
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT, "break_cause_probe_20260718.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
wf("[probe] done")
