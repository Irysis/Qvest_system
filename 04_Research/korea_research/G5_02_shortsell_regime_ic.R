cat("=== TEST-KR-G5-02: Short-Selling Ban Regime Conditional IC ===\n")
cat("=== 근거: KR-022 (공매도 금지 효과), KR-007 (단기 Beta) ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/factor_db_builder.R")
})
library(data.table)

# ── 1. 공매도 금지 기간 정의 (FSC 공식) ───────────────────────────
# C11: 행정 발표 기준 t-0 (공식 결정일 = 즉시 반영)
shortsell_ban_periods <- data.table(
  ban_id = 1:4,
  start = as.Date(c("2008-10-01", "2011-08-10", "2020-03-16", "2023-11-06")),
  end   = as.Date(c("2009-06-01", "2011-11-09", "2021-05-02", "2025-03-30"))
)
cat("[G5-02] Short-selling ban periods:\n")
print(shortsell_ban_periods)

# 날짜 → regime 태그
is_ban_date <- function(d) {
  any(d >= shortsell_ban_periods$start & d <= shortsell_ban_periods$end)
}

# ── 2. Factor DB 월말 IC (ban/allow 분리) ─────────────────────────
cat("\n[G5-02] Step 2: Computing ban/allow conditional IC...\n")
.load_base_data()
raw <- .fdb_env$RAWDATA

all_dates <- sort(unique(raw$Date))
dt_dates <- data.table(Date = all_dates)
dt_dates[, YM := format(Date, "%Y%m")]
month_ends <- dt_dates[, .(Date = max(Date)), by = YM][order(YM)]$Date
month_ends <- month_ends[month_ends >= as.Date("2005-01-01")]

results <- list()
processed <- 0

for (sig_date in as.character(month_ends)) {
  sig_d <- as.Date(sig_date)

  fdb <- tryCatch(load_factor_db(sig_d, format = "wide"), error = function(e) NULL)
  if (is.null(fdb) || nrow(fdb) < 50) next

  next_idx <- which(as.character(month_ends) == sig_date) + 1
  if (next_idx > length(month_ends)) next
  next_month <- month_ends[next_idx]

  fwd <- raw[Date > sig_d & Date <= next_month,
             .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = Ticker]

  merged <- merge(fdb, fwd, by = "Ticker")
  if (nrow(merged) < 30) next

  # 공매도 regime
  ss_regime <- fifelse(is_ban_date(sig_d), "BAN", "ALLOW")

  factor_cols <- setdiff(names(fdb), c("Date", "Ticker"))
  for (fc in factor_cols) {
    vals <- merged[[fc]]
    if (sum(!is.na(vals)) < 20) next
    ic_val <- cor(vals, merged$Fwd_Ret, use = "pairwise.complete.obs")
    if (!is.finite(ic_val)) next

    results[[length(results) + 1]] <- data.table(
      sig_date = sig_d,
      factor_id = fc,
      ss_regime = ss_regime,
      ic = ic_val
    )
  }

  processed <- processed + 1
  if (processed %% 20 == 0) {
    cat(sprintf("  Processed %d months\n", processed))
  }
}

# ── 3. 집계 ──────────────────────────────────────────────────────
cat("[G5-02] Step 3: Aggregating...\n")
ic_dt <- rbindlist(results)

ss_ic <- ic_dt[, .(
  mean_ic = mean(ic, na.rm = TRUE),
  icir = mean(ic, na.rm = TRUE) / (sd(ic, na.rm = TRUE) + 1e-8),
  n_months = uniqueN(sig_date)
), by = .(factor_id, ss_regime)]

ss_wide <- dcast(ss_ic, factor_id ~ ss_regime,
                 value.var = c("mean_ic", "icir", "n_months"))

if ("mean_ic_BAN" %in% names(ss_wide) &&
    "mean_ic_ALLOW" %in% names(ss_wide)) {
  ss_wide[, ic_shift := mean_ic_BAN - mean_ic_ALLOW]
}

setorder(ss_wide, -ic_shift)

# ── 4. 저장 ──────────────────────────────────────────────────────
out_path <- file.path(CACHE_DIR, "factor_ic_shortsell_regime.csv")
fwrite(ss_wide, out_path)
cat(sprintf("\n[G5-02] Saved: %s (%d factors)\n", out_path, nrow(ss_wide)))

# ── 5. 요약 ──────────────────────────────────────────────────────
cat("\n=== 공매도 금지 시 IC 상승 Top 10 (BAN > ALLOW) ===\n")
print(head(ss_wide[, .(factor_id, mean_ic_ALLOW, mean_ic_BAN,
                        icir_ALLOW, icir_BAN, ic_shift)], 10))

cat("\n=== 공매도 금지 시 IC 하락 Top 10 (BAN < ALLOW) ===\n")
print(tail(ss_wide[, .(factor_id, mean_ic_ALLOW, mean_ic_BAN,
                        icir_ALLOW, icir_BAN, ic_shift)], 10))

# Ban/Allow 기간 분포
cat(sprintf("\n=== 기간 분포 ===\nBAN months: %d\nALLOW months: %d\n",
            ic_dt[ss_regime == "BAN", uniqueN(sig_date)],
            ic_dt[ss_regime == "ALLOW", uniqueN(sig_date)]))

cat("\n[G5-02] Complete.\n")
