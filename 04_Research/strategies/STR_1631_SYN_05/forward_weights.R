## STR_1631_SYN_05 Forward Weights Wrapper (Phase 1, Plan v1.0 2026-04-29)
##
## Goal: as_of_date 기준 forward production weights 산출
## Method: 본 run_all.R Step 0~4 + sim_base 실행 → HOLDINGS_LOG 추출 → max sig_date holdings
##
## 본 logic 변경 금지. patched copy (/tmp/str_1631_run_all_patched_v2.R)를 동적 생성/source.
## Step 5+ (regime overlay) skip — weights 산출만 필요.
##
## 도훈 명령 enforcement:
##   - apply_mandate_cap = "cap_0.20" default 강제 (mandate strict)
##   - measurement_basis_primary = "forge_realized_share_based"
##   - PerformanceAnalytics 표준 함수 사용 (자체 합성 금지)

suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
})
options(scipen = 999)

# ─────────────────────────────────────────────────────────
generate_forward_weights_str1631_syn05 <- function(
  as_of_date         = NULL,                  # NULL = max(HOLDINGS_LOG sig_date)
  apply_mandate_cap  = c("cap_0.20", "no_cap"),
  reuse_cached       = TRUE,                   # TRUE = use existing /tmp HOLDINGS_LOG if available
  output_root        = NULL
) {
  apply_mandate_cap <- match.arg(apply_mandate_cap)

  # ─── Resolve paths ───────────────────────────────────
  STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
  PROJECT_ROOT <- normalizePath(file.path(STRAT_DIR, "..", "..", ".."))
  RUN_ALL_PATH <- file.path(STRAT_DIR, "run_all.R")
  PATCHED_PATH <- "/tmp/str_1631_syn05_run_all_patched_forward.R"
  HOLDINGS_LOG_PATH <- "/tmp/str_1631_syn05_holdings_log.csv"

  if (is.null(output_root)) {
    output_root <- file.path(STRAT_DIR, "production_weights")
  }
  dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

  # ─── Generate or reuse HOLDINGS_LOG ──────────────────
  need_run <- TRUE
  if (reuse_cached && file.exists(HOLDINGS_LOG_PATH)) {
    age_hours <- as.numeric(difftime(Sys.time(), file.info(HOLDINGS_LOG_PATH)$mtime,
                                      units = "hours"))
    if (age_hours < 24) {
      cat(sprintf("[STR_1631_SYN_05] reusing HOLDINGS_LOG (age %.1fh): %s\n",
                  age_hours, HOLDINGS_LOG_PATH))
      need_run <- FALSE
    }
  }

  if (need_run) {
    cat(sprintf("[STR_1631_SYN_05] running patched run_all.R Step 0-4 (5-10 min)...\n"))
    src <- readLines(RUN_ALL_PATH, encoding = "UTF-8")
    anchor <- grep("^to_base <- calc_turnover", src)
    step5_hdr <- grep("^# 5\\. Regime Overlay", src)
    stopifnot(length(anchor) == 1L, length(step5_hdr) == 1L)

    save_block <- c(
      '',
      '# ─── PATCH: SAVE HOLDINGS_LOG (forward_weights.R) ───',
      sprintf('if (!is.null(sim_base$HOLDINGS_LOG)) data.table::fwrite(sim_base$HOLDINGS_LOG, "%s")',
              HOLDINGS_LOG_PATH),
      'cat("[PATCH] HOLDINGS_LOG saved\\n")',
      '',
      '# ─── PATCH: SKIP STEP 5+ ───',
      'if (FALSE) {  # PATCH SKIP'
    )
    end_skip <- '}  # PATCH END SKIP'

    src_patched <- c(src[1:(step5_hdr - 1L)], save_block,
                     src[step5_hdr:length(src)], end_skip)
    writeLines(src_patched, PATCHED_PATH, useBytes = TRUE)

    old_wd <- getwd()
    setwd(STRAT_DIR)
    on.exit(setwd(old_wd), add = TRUE)
    source(PATCHED_PATH, local = FALSE)
  }

  # ─── Load HOLDINGS_LOG ───────────────────────────────
  if (!file.exists(HOLDINGS_LOG_PATH)) {
    stop(sprintf("[STR_1631_SYN_05] HOLDINGS_LOG not generated: %s", HOLDINGS_LOG_PATH))
  }
  hl <- fread(HOLDINGS_LOG_PATH)
  hl[, Signal_Date := as.Date(Signal_Date)]
  cat(sprintf("[STR_1631_SYN_05] HOLDINGS_LOG: %d rows | %d sig_dates | range %s ~ %s\n",
              nrow(hl), uniqueN(hl$Signal_Date),
              as.character(min(hl$Signal_Date)), as.character(max(hl$Signal_Date))))

  # ─── Resolve as_of_date ──────────────────────────────
  avail <- sort(unique(hl$Signal_Date))
  if (is.null(as_of_date)) {
    as_of_date <- max(avail)
    cat(sprintf("[STR_1631_SYN_05] as_of_date = max sig_date: %s\n", as.character(as_of_date)))
  } else {
    as_of_date <- as.Date(as_of_date)
    if (!(as_of_date %in% avail)) {
      rolled <- max(avail[avail <= as_of_date])
      cat(sprintf("[STR_1631_SYN_05] %s not in HOLDINGS_LOG; rolled to %s\n",
                  as.character(as_of_date), as.character(rolled)))
      as_of_date <- rolled
    }
  }

  w_t <- hl[Signal_Date == as_of_date, .(Ticker, Name, Sector, Weight, Score)]
  if (nrow(w_t) == 0) stop(sprintf("[STR_1631_SYN_05] no holdings at %s",
                                    as.character(as_of_date)))

  # ─── Renormalize ─────────────────────────────────────
  w_t[, Weight := Weight / sum(Weight)]

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
    cat(sprintf("[STR_1631_SYN_05] cap_0.20 applied (%d iters); max weight = %.4f\n",
                iters, max(w_t$Weight)))
  }
  w_t[, Weight := Weight / sum(Weight)]

  # ─── Capacity check ──────────────────────────────────
  rawdata_path <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
  capacity_breach <- list()
  if (file.exists(rawdata_path)) {
    raw <- as.data.table(read_parquet(
      rawdata_path,
      col_select = c("Date", "Ticker", "Close", "Vol")))
    raw[, Date := as.Date(Date)]
    raw[, TradingAmt := Close * Vol]
    liq <- raw[Date >= (as_of_date - 30L) & Date <= as_of_date & Ticker %in% w_t$Ticker,
               .(AvgTV_30d_won = mean(TradingAmt, na.rm = TRUE)), by = Ticker]

    w_t <- merge(w_t, liq, by = "Ticker", all.x = TRUE)
    w_t[, AvgTV_30d_won := fifelse(is.na(AvgTV_30d_won), 0, AvgTV_30d_won)]

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
  fwrite(w_t[, .(rank, Ticker, Name, Sector, Weight, Score)], weights_out_path)

  holdings_out_path <- file.path(output_root, sprintf("%s_holdings_log_%s.csv", date_tag, cap_tag))
  if ("AvgTV_30d_won" %in% names(w_t)) {
    fwrite(w_t[, .(rank, Ticker, Name, Sector, Weight, Score,
                    AvgTV_30d_억 = round(AvgTV_30d_won / 1e8, 1),
                    ADV_share_pct, capacity_breach_50pct)],
           holdings_out_path)
  } else {
    fwrite(w_t, holdings_out_path)
  }

  capacity_out_path <- file.path(output_root, sprintf("%s_capacity_check_%s.json", date_tag, cap_tag))
  manifest <- list(
    strategy_id = "STR_1631_SYN_05",
    method = "4factor_IC_weighted_HRP_Gerber_RMT_ScoreTilt_bimonthly",
    as_of_date = as.character(as_of_date),
    mandate = apply_mandate_cap,
    holdings_log_source = HOLDINGS_LOG_PATH,
    holdings_log_unique_dates = uniqueN(hl$Signal_Date),
    holdings_log_max_date = as.character(max(hl$Signal_Date)),
    n_holdings = nrow(w_t),
    sum_weights = round(sum(w_t$Weight), 6),
    max_weight = round(max(w_t$Weight), 4),
    measurement_basis_primary = "forge_realized_share_based",
    capacity_check = capacity_breach,
    notes = "본 run_all.R Step 0-4 + sim_base full execution. Step 5+ regime overlay skipped."
  )
  write_json(manifest, capacity_out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[STR_1631_SYN_05] outputs:\n"))
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
  reuse <- if (length(args) >= 3) as.logical(args[3]) else TRUE
  generate_forward_weights_str1631_syn05(as_of_date = as_of,
                                          apply_mandate_cap = cap_mode,
                                          reuse_cached = reuse)
}
