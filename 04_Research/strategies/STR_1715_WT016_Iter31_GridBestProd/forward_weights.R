## STR_1715 Forward Weights Wrapper (Phase 1, Plan v1.0 2026-04-29)
##
## Goal: as_of_date 기준 forward production weights/holdings/capacity 자동 산출
##
## Mode 1 (schedule_recent — DEFAULT, FAST):
##   기존 산출된 weights schedule (WT-D20260427_017/weights.csv 181 monthly dates)에서
##   as_of_date 또는 max(Date) row 추출 → cap 0.20 → capacity check → 저장
##   현재 schedule end = 2023-12-01 (Iter5 alpha_scores 한계)
##
## Mode 2 (forward_recompute — TODO Phase 1.5+):
##   Iter5 alpha_scores 재산출 (multi-sleeve composite model) → STR_1715 grid params re-apply
##   → forward weights 산출. Iter5 alpha_scores production cron 인프라 별도 필요.
##
## 도훈 명령 enforcement:
##   - apply_mandate_cap = "cap_0.20" default 강제 (OVERRIDE_006 mandate strict)
##   - PerformanceAnalytics 표준 함수만 사용 (자체 cumprod/prod/mean 합성 금지)
##   - measurement_basis_primary 명시 ("forge_realized_share_based")

suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
})
options(scipen = 999)

# ─────────────────────────────────────────────────────────
generate_forward_weights_str1715 <- function(
  as_of_date         = NULL,                  # NULL = max(weights schedule)
  apply_mandate_cap  = c("cap_0.20", "no_cap"),
  weights_source     = NULL,                  # NULL = WT-D20260427_017/weights.csv
  output_root        = NULL                   # NULL = STRAT_DIR/production_weights
) {
  apply_mandate_cap <- match.arg(apply_mandate_cap)

  # ─── Resolve paths ───────────────────────────────────
  STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
  PROJECT_ROOT <- normalizePath(file.path(STRAT_DIR, "..", "..", ".."))

  if (is.null(weights_source)) {
    weights_source <- file.path(PROJECT_ROOT,
                                 "qepm/mailbox/worktask/WT-D20260427_017/weights.csv")
  }
  if (!file.exists(weights_source)) {
    stop(sprintf("[STR_1715 forward_weights] weights schedule not found: %s", weights_source))
  }

  if (is.null(output_root)) {
    output_root <- file.path(STRAT_DIR, "production_weights")
  }
  dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

  # ─── Load weights schedule ───────────────────────────
  w_all <- fread(weights_source)
  w_all[, Date := as.Date(Date)]
  setorder(w_all, Date, Ticker)

  cat(sprintf("[STR_1715] weights_source: %s\n", weights_source))
  cat(sprintf("[STR_1715] schedule range: %s ~ %s | %d unique dates | %d rows\n",
              as.character(min(w_all$Date)), as.character(max(w_all$Date)),
              uniqueN(w_all$Date), nrow(w_all)))

  # ─── Resolve as_of_date ──────────────────────────────
  if (is.null(as_of_date)) {
    as_of_date <- max(w_all$Date)
    cat(sprintf("[STR_1715] as_of_date defaulted to max schedule date: %s\n",
                as.character(as_of_date)))
  } else {
    as_of_date <- as.Date(as_of_date)
    if (!(as_of_date %in% unique(w_all$Date))) {
      # Roll back to nearest sig_date <= as_of_date
      avail <- sort(unique(w_all$Date))
      rolled <- max(avail[avail <= as_of_date])
      cat(sprintf("[STR_1715] as_of_date %s not in schedule; rolled to %s\n",
                  as.character(as_of_date), as.character(rolled)))
      as_of_date <- rolled
    }
  }

  w_t <- w_all[Date == as_of_date, .(Ticker, Weight)]
  if (nrow(w_t) == 0) stop(sprintf("[STR_1715] no weights at %s", as.character(as_of_date)))

  # ─── Renormalize (in case schedule weights don't sum to 1) ────
  raw_sum <- sum(w_t$Weight)
  w_t[, Weight := Weight / raw_sum]

  # ─── Apply mandate cap ───────────────────────────────
  if (apply_mandate_cap == "cap_0.20") {
    cap <- 0.20
    iters <- 0
    repeat {
      over <- w_t$Weight > cap
      if (!any(over)) break
      excess <- sum(w_t$Weight[over] - cap)
      w_t[over, Weight := cap]
      uncapped <- which(!over)
      if (length(uncapped) == 0) break
      share <- w_t$Weight[uncapped] / sum(w_t$Weight[uncapped])
      w_t$Weight[uncapped] <- w_t$Weight[uncapped] + excess * share
      iters <- iters + 1
      if (iters > 50) break
    }
    cat(sprintf("[STR_1715] cap_0.20 applied (%d iters); max weight = %.4f\n",
                iters, max(w_t$Weight)))
  } else {
    cat(sprintf("[STR_1715] no_cap variant; max weight = %.4f (mandate violator if >= 0.20)\n",
                max(w_t$Weight)))
  }

  # Normalize
  w_t[, Weight := Weight / sum(Weight)]

  # ─── Capacity check (require RAWDATA + Name/Sector merge) ────
  rawdata_path <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
  capacity_breach <- list()
  if (file.exists(rawdata_path)) {
    raw <- as.data.table(read_parquet(
      rawdata_path,
      col_select = c("Date", "Ticker", "Name", "Sector", "Close", "Vol")))
    raw[, Date := as.Date(Date)]
    raw[, TradingAmt := Close * Vol]

    name_map <- raw[!is.na(Name) & Ticker %in% w_t$Ticker,
                    .SD[which.max(Date)], by = Ticker,
                    .SDcols = c("Name", "Sector")]
    liq <- raw[Date >= (as_of_date - 30L) & Date <= as_of_date & Ticker %in% w_t$Ticker,
               .(AvgTV_30d_won = mean(TradingAmt, na.rm = TRUE)), by = Ticker]

    w_t <- merge(w_t, name_map[, .(Ticker, Name, Sector)], by = "Ticker", all.x = TRUE)
    w_t <- merge(w_t, liq, by = "Ticker", all.x = TRUE)
    w_t[, AvgTV_30d_won := fifelse(is.na(AvgTV_30d_won), 0, AvgTV_30d_won)]

    # ADV 5% capacity per AUM 10B (default)
    AUM_won <- 1e10
    w_t[, ADV_share_pct := round(Weight * AUM_won / pmax(AvgTV_30d_won, 1) * 100, 2)]
    w_t[, capacity_breach_50pct := ADV_share_pct > 50]

    capacity_breach <- list(
      AUM_won = AUM_won,
      n_tickers = nrow(w_t),
      n_breach_ADV50 = sum(w_t$capacity_breach_50pct, na.rm = TRUE),
      breach_tickers = w_t[capacity_breach_50pct == TRUE, Ticker],
      worst_ADV_pct = max(w_t$ADV_share_pct, na.rm = TRUE),
      worst_ticker = w_t[which.max(ADV_share_pct), Ticker]
    )
  }
  setorder(w_t, -Weight)
  w_t[, rank := seq_len(.N)]

  # ─── Save outputs ────────────────────────────────────
  date_tag <- format(as_of_date, "%Y%m%d")
  cap_tag <- gsub("\\.", "p", apply_mandate_cap)

  weights_out_path <- file.path(output_root, sprintf("%s_weights_%s.csv", date_tag, cap_tag))
  fwrite(w_t[, .(rank, Ticker, Name, Sector, Weight)], weights_out_path)

  holdings_out_path <- file.path(output_root, sprintf("%s_holdings_log_%s.csv", date_tag, cap_tag))
  if ("AvgTV_30d_won" %in% names(w_t)) {
    fwrite(w_t[, .(rank, Ticker, Name, Sector, Weight,
                    AvgTV_30d_억 = round(AvgTV_30d_won / 1e8, 1),
                    ADV_share_pct, capacity_breach_50pct)],
           holdings_out_path)
  } else {
    fwrite(w_t, holdings_out_path)
  }

  capacity_out_path <- file.path(output_root, sprintf("%s_capacity_check_%s.json", date_tag, cap_tag))
  manifest <- list(
    strategy_id = "STR_1715",
    iter_label = "Iter31_LinTilt_lam1.5_TOphi3_CashOverlay",
    as_of_date = as.character(as_of_date),
    mandate = apply_mandate_cap,
    weights_source = weights_source,
    weights_source_unique_dates = uniqueN(w_all$Date),
    weights_source_max_date = as.character(max(w_all$Date)),
    n_holdings = nrow(w_t),
    sum_weights = round(sum(w_t$Weight), 6),
    max_weight = round(max(w_t$Weight), 4),
    measurement_basis_primary = "forge_realized_share_based",
    capacity_check = capacity_breach,
    notes = "Mode=schedule_recent. Forward_recompute (Iter5 alpha_scores 재산출) TODO."
  )
  write_json(manifest, capacity_out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[STR_1715] outputs:\n"))
  cat(sprintf("  weights:   %s\n", weights_out_path))
  cat(sprintf("  holdings:  %s\n", holdings_out_path))
  cat(sprintf("  capacity:  %s\n", capacity_out_path))

  invisible(list(
    weights = w_t,
    manifest = manifest,
    paths = list(weights = weights_out_path,
                 holdings = holdings_out_path,
                 capacity = capacity_out_path)
  ))
}

# ─── CLI entrypoint ────────────────────────────────────
if (!interactive() && sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  as_of <- if (length(args) >= 1) args[1] else NULL
  cap_mode <- if (length(args) >= 2) args[2] else "cap_0.20"
  generate_forward_weights_str1715(as_of_date = as_of, apply_mandate_cap = cap_mode)
}
