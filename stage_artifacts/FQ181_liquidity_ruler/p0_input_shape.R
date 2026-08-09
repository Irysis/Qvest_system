## FQ-181 P0 — 입력 형태 실측 (측정 전 의무: 행수·관측단위·범위)
## 규약: [[feedback-assert-input-shape-before-measuring]] — 가정 금지.
## read-only. 산출: p0_input_shape.json (vintage pin 포함)

suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM <- gsub("\\\\", "/", QM)
setwd(QM)
OUT <- file.path(QM, "stage_artifacts/FQ181_liquidity_ruler")

RAW_PATH <- ".cache/rawdata.parquet"
fi <- file.info(RAW_PATH)
pin <- list(
  path = RAW_PATH,
  size_bytes = as.numeric(fi$size),
  mtime = format(fi$mtime, "%Y-%m-%d %H:%M:%S"),
  pinned_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
cat(sprintf("[vintage pin] %s | %.0f bytes | mtime %s\n", pin$path, pin$size_bytes, pin$mtime))

sch <- arrow::open_dataset(RAW_PATH)$schema
cat("--- parquet schema ---\n"); print(sch)

need <- c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")
R <- as.data.table(read_parquet(RAW_PATH, col_select = all_of(need)))
R[, Date := as.Date(Date)]

n_rows <- nrow(R)
n_dates <- uniqueN(R$Date)
n_tick <- uniqueN(R$Ticker)
rng <- range(R$Date)

## 관측단위 판정: 캘린더월당 고유 거래일 수
dpm <- R[, .(nd = uniqueN(Date)), by = .(ym = format(Date, "%Y-%m"))]
dpm_med <- median(dpm$nd)
unit <- if (dpm_med >= 15) "daily" else if (dpm_med <= 3) "month_end_slim" else "irregular"

cat(sprintf("\n[shape] rows=%s  dates=%s  tickers=%s  range=%s..%s\n",
            format(n_rows, big.mark = ","), format(n_dates, big.mark = ","),
            format(n_tick, big.mark = ","), rng[1], rng[2]))
cat(sprintf("[shape] 캘린더월당 거래일수: median=%.1f  min=%d  max=%d  → 관측단위 판정 = %s\n",
            dpm_med, min(dpm$nd), max(dpm$nd), unit))

## Vol / Close 스케일 — Vol*Close 가 '거래대금(KRW)' 인지 확인
smp <- R[!is.na(Vol) & !is.na(Close) & Vol > 0 & Close > 0][sample(.N, min(.N, 2e5))]
smp[, dv := Vol * Close]
qs <- quantile(smp$dv, c(0.01, 0.25, 0.5, 0.75, 0.99), na.rm = TRUE)
cat(sprintf("[scale] Vol class=%s  Close class=%s\n", class(R$Vol)[1], class(R$Close)[1]))
cat(sprintf("[scale] Vol*Close 분위 (KRW): 1%%=%.3g 25%%=%.3g 50%%=%.3g 75%%=%.3g 99%%=%.3g\n",
            qs[1], qs[2], qs[3], qs[4], qs[5]))
cat(sprintf("[scale] 중앙값이 2e8(=%.0e) 문턱과 같은 자릿수대인가: %s\n", 2e8,
            if (qs[3] > 1e6 && qs[3] < 1e13) "예 (KRW 거래대금 스케일 정합)" else "아니오 — 단위 재확인 필요"))

## 유니버스(K200|KQ150) 한정 스케일 (실제 필터 대상)
smpu <- R[(K200 == TRUE | KQ150 == TRUE) & !is.na(Vol) & !is.na(Close) & Vol > 0 & Close > 0]
smpu[, dv := Vol * Close]
qsu <- quantile(smpu$dv, c(0.01, 0.05, 0.25, 0.5), na.rm = TRUE)
cat(sprintf("[scale-univ] K200|KQ150 일간 Vol*Close 분위: 1%%=%.3g 5%%=%.3g 25%%=%.3g 50%%=%.3g (n=%s)\n",
            qsu[1], qsu[2], qsu[3], qsu[4], format(nrow(smpu), big.mark = ",")))

## NA 실태 (교정 후 NA-통과 구멍 평가용)
na_vol <- R[, sum(is.na(Vol))]; na_cl <- R[, sum(is.na(Close))]
cat(sprintf("[na] Vol NA=%s (%.4f%%)  Close NA=%s (%.4f%%)\n",
            format(na_vol, big.mark = ","), 100 * na_vol / n_rows,
            format(na_cl, big.mark = ","), 100 * na_cl / n_rows))

res <- list(
  vintage_pin = pin,
  columns = names(sch),
  n_rows = n_rows, n_dates = n_dates, n_tickers = n_tick,
  date_min = as.character(rng[1]), date_max = as.character(rng[2]),
  trading_days_per_month = list(median = dpm_med, min = min(dpm$nd), max = max(dpm$nd)),
  observation_unit = unit,
  dv_quantiles_all = as.list(round(qs)),
  dv_quantiles_universe = as.list(round(qsu)),
  na_vol = na_vol, na_close = na_cl
)
write_json(res, file.path(OUT, "p0_input_shape.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("\n[done] p0_input_shape.json\n")
