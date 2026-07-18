##=============================================================================
## run_sml_history_probe.R — "한국 소형주 아웃퍼폼은 없어졌나?" 실측
## V1: 유니버스(K200∪KQ150) 내 MEGA top-30 vs REST (배포권 관점)
## V2: 전체 상장 — MEGA top-30 vs 나머지 전체 / vs 시총 하위 50% (시장 전체 관점)
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(dplyr); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/decay_fit"
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")
nwt <- function(x) { x <- x[is.finite(x)]; if (length(x) < 12) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(lmtest::coeftest(m, vcov = sandwich::NeweyWest(m, lag = 3, prewhite = FALSE))[1, 3]) }

## ── 월말 전체 상장 패널 (유니버스 필터 없이 직접 구성 + sanity) ──
r6 <- as.data.table(read_parquet(".cache/pins/decay_fit_20260717/r6_factor_deployzone_active.parquet"))
sigs <- sort(unique(as.Date(r6$signal_date)))
month_end <- function(d) { m0 <- as.Date(cut(d, "month")); seq(m0, by = "1 month", length.out = 2)[2] - 1 }
sigs_ext <- c(sigs, month_end(max(sigs) + 1))
ud <- sort(unique(as.Date(as.data.table(read_parquet(".cache/rawdata.parquet", col_select = "Date"))$Date)))
me <- unique(as.Date(vapply(sigs_ext, function(d) { v <- ud[ud <= d]; if (length(v)) as.character(max(v)) else NA_character_ }, character(1))))
me <- sort(me[!is.na(me)])
.need <- c("Date", "Ticker", "Close", "K200", "KQ150", "Size")
rm_ <- as.data.table(open_dataset(".cache/rawdata.parquet") |> filter(Date %in% me) |> select(all_of(.need)) |> collect())
rm_[, Date := as.Date(Date)]
setorder(rm_, Ticker, Date)
## 월말→다음 월말 forward (전체 상장, C-M과 동일 산식·sanity는 R44 기준)
rm_[, Close1 := shift(Close, type = "lead"), by = Ticker]
rm_[, d1 := shift(Date, type = "lead"), by = Ticker]
me_next <- data.table(Date = me, nxt = shift(me, type = "lead"))
rm_ <- merge(rm_, me_next, by = "Date")
rm_ <- rm_[!is.na(Close1) & d1 == nxt & !is.na(Close) & Close > 0 & !is.na(Size) & Size > 0]
rm_[, Ret_1m := Close1 / Close - 1]
rm_ <- rm_[Ret_1m <= 5.0 & Ret_1m >= -1.0]   # R44 물리불가 격리 기준
rm_[, uni := (K200 == TRUE | KQ150 == TRUE)]
rm_[, rk_all := frankv(Size, order = -1L), by = Date]
rm_[, half := Size <= quantile(Size, 0.5), by = Date]

sp <- rm_[, .(
  sml_uni  = mean(Ret_1m[uni & rk_all > 30], na.rm = TRUE) - mean(Ret_1m[rk_all <= 30], na.rm = TRUE),
  sml_all  = mean(Ret_1m[rk_all > 30], na.rm = TRUE) - mean(Ret_1m[rk_all <= 30], na.rm = TRUE),
  sml_half = mean(Ret_1m[half], na.rm = TRUE) - mean(Ret_1m[rk_all <= 30], na.rm = TRUE),
  n_all = .N), by = Date][order(Date)]
wf("months=%d range %s..%s | 월평균 종목수=%d", nrow(sp), format(min(sp$Date)), format(max(sp$Date)), round(mean(sp$n_all)))

per <- list(c("2005-01-01","2009-12-31"), c("2010-01-01","2014-12-31"), c("2015-01-01","2015-12-31"),
            c("2016-01-01","2019-12-31"), c("2020-01-01","2021-12-31"), c("2022-01-01","2023-12-31"),
            c("2024-01-01","2026-12-31"))
wf("%-18s %8s %6s %6s | %8s %6s | %8s %6s", "기간", "uni_mean", "NW_t", "pos%", "all_mean", "NW_t", "half_mean", "NW_t")
tab <- list()
for (p in per) {
  s <- sp[Date >= p[1] & Date <= p[2]]
  if (!nrow(s)) next
  tab[[p[1]]] <- data.table(period = paste(substr(p[1],1,4), substr(p[2],3,4), sep="-"), n = nrow(s),
    uni_mean = mean(s$sml_uni), uni_t = nwt(s$sml_uni), uni_pos = mean(s$sml_uni > 0),
    all_mean = mean(s$sml_all), all_t = nwt(s$sml_all),
    half_mean = mean(s$sml_half), half_t = nwt(s$sml_half))
  x <- tab[[p[1]]]
  wf("%-18s %+8.4f %6.2f %6.2f | %+8.4f %6.2f | %+8.4f %6.2f",
     x$period, x$uni_mean, x$uni_t, x$uni_pos, x$all_mean, x$all_t, x$half_mean, x$half_t)
}
TAB <- rbindlist(tab)
## rolling 36m 현재값 + 마지막 양(+) 시점
sp[, r36_uni := frollmean(sml_uni, 36)]
sp[, r36_all := frollmean(sml_all, 36)]
last_pos_uni <- sp[r36_uni > 0, max(Date)]
wf("rolling36 uni: 현재(=%s) %+.4f | 마지막 양(+) 시점 %s", format(max(sp$Date)), sp[.N, r36_uni], format(last_pos_uni))
wf("rolling36 all: 현재 %+.4f | 마지막 양(+) %s", sp[.N, r36_all], format(sp[r36_all > 0, max(Date)]))
## 2016+ 양(+) 에피소드 (연 단위)
sp[, yr := year(Date)]
yr_tab <- sp[yr >= 2016, .(uni = mean(sml_uni), all = mean(sml_all)), by = yr][order(yr)]
wf("2016+ 연도별 (uni / all):"); for (i in seq_len(nrow(yr_tab))) wf("  %d: %+.4f / %+.4f", yr_tab$yr[i], yr_tab$uni[i], yr_tab$all[i])
write_json(list(table = TAB, yearly_2016p = yr_tab,
                r36_uni_now = sp[.N, r36_uni], r36_uni_last_pos = format(last_pos_uni),
                r36_all_now = sp[.N, r36_all],
                note = "sml_uni=유니버스內 REST vs MEGA30 / sml_all=전체상장 REST vs MEGA30 / sml_half=전체상장 시총하위50% vs MEGA30. EW forward, R44 sanity. metric_type=diagnostic",
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT, "sml_history_probe_20260718.json"), auto_unbox = TRUE, pretty = TRUE, digits = 5)
wf("[sml_history] done")
