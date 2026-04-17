# STR_1622_M8_dd_brake_620: IC-Weighted Statistical Blend 5F (C19+V14+Q01+D01+M25)
# Mutation M8: 기본 5F 유지. DD Brake 오버레이는 run_all.R에서 처리.
# PIT: C1(no full-sample), C13(Z_Score_Aligned), C14(Usable_Date<=sig_d), C15(bulk preload via open_dataset)
# Arnott et al. 2019 + DeMiguel et al. 2009

cat("[factor_engine] STR_1622_M8_dd_brake_620: IC-Weighted Blend 5F (C19+V14+Q01+D01+M25)...\n")
set.seed(1622)
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD <- 2e8
N_FACTORS    <- 5L
FLOOR_W      <- 0.05
CAP_W        <- 0.40
N_FACTORS_EW <- 1.0 / N_FACTORS  # EW = 0.20

NEEDED_FACTORS <- c("C19_Composite_Earnings", "V14_EBIT_EV", "Q01_GPA",
                    "D01_IdioVol", "M25_Earnings_Mom_Streak")

# C15: bulk preload — 루프 밖에서 한 번만 (OPT-1 준수)
pq_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                       pattern = "\\.parquet$", full.names = TRUE)
ds <- open_dataset(pq_files, format = "parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% NEEDED_FACTORS) |>
  select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
FDB_ALL[, Usable_Date := Date]           # C14 fallback
setnames(FDB_ALL, "Z_Score", "Z_Score_Aligned")  # C13: no manual flip
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows | factors: %s\n", nrow(FDB_ALL),
            paste(unique(FDB_ALL$Factor_Name), collapse = ", ")))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates     <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]
setorder(RAWDATA, Ticker, Date)
RAWDATA[, FwdRet := shift(Ret, n = -1L, type = "lead"), by = Ticker]

fdb_dates   <- sort(unique(FDB_ALL$Date))
factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

# IC history accumulator (expanding window, 12M rolling)
# 루프 내 DB 재로드 없음 — FDB_ALL 메모리 슬라이스만 사용 (OPT-1 준수)
ic_history <- list()

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])

  # C14: Usable_Date <= sig_d
  valid_fdb <- fdb_dates[fdb_dates <= sig_d]
  if (length(valid_fdb) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdb_d <- max(valid_fdb)

  fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE & Usable_Date <= sig_d]
  if (nrow(fdt) == 0L) fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  liq      <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20, FwdRet)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  # IC 계산: lapply 패턴 (루프 내 DB 재로드 없음)
  ic_vals <- lapply(NEEDED_FACTORS, function(fn) {
    if (!fn %in% names(fdt_wide)) return(NA_real_)
    vals <- fdt_wide[[fn]]; fwd <- fdt_wide$FwdRet
    mask <- !is.na(vals) & !is.na(fwd)
    if (sum(mask) >= 20L) cor(rank(vals[mask]), rank(fwd[mask]), method = "spearman")
    else NA_real_
  })
  ic_current <- setNames(unlist(ic_vals), NEEDED_FACTORS)

  # t-1 lag 저장 (C5 준수)
  ic_history[[as.character(sig_d)]] <- ic_current

  past_dates <- names(ic_history)[as.Date(names(ic_history)) < sig_d]

  if (length(past_dates) == 0L) {
    weights <- setNames(rep(N_FACTORS_EW, N_FACTORS), NEEDED_FACTORS)
  } else {
    window_dates <- tail(past_dates, 12L)
    ic_mat  <- do.call(rbind, lapply(window_dates, function(d) ic_history[[d]]))
    ic_mean <- colMeans(ic_mat, na.rm = TRUE)

    ic_abs  <- abs(ic_mean); ic_abs[is.na(ic_abs)] <- 0
    ic_sum  <- sum(ic_abs)
    ic_norm <- if (ic_sum > 0) ic_abs / ic_sum else rep(N_FACTORS_EW, N_FACTORS)
    wraw    <- 0.5 * ic_norm + 0.5 * N_FACTORS_EW
    wraw    <- pmax(wraw, FLOOR_W)
    wraw    <- pmin(wraw, CAP_W)
    weights <- wraw / sum(wraw)
    names(weights) <- NEEDED_FACTORS
  }

  # 랭크 스코어: lapply 패턴
  score_parts <- lapply(NEEDED_FACTORS, function(fn) {
    w <- weights[fn]
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last = "keep", ties.method = "average") /
             sum(!is.na(fdt_wide[[fn]]))
      list(s = w * rnk, w = w)
    } else {
      list(s = rep(0, nrow(fdt_wide)), w = 0)
    }
  })
  total_w <- sum(sapply(score_parts, `[[`, "w"))
  if (total_w == 0) { n_skipped <- n_skipped + 1L; next }

  fdt_wide[, Score := Reduce("+", lapply(score_parts, `[[`, "s")) / total_w]
  fdt_wide[, Date  := sig_d]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

if ("YM"    %in% names(RAWDATA)) RAWDATA[, YM     := NULL]
if ("FwdRet" %in% names(RAWDATA)) RAWDATA[, FwdRet := NULL]
for (col in c("TradingValue", "AvgTV20")) if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
rm(FDB_ALL, ic_history); gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skipped))
