## STR_1715 Forward Weights Wrapper (v2.0 2026-05-02 도훈 명시)
##
## Goal: as_of_date 기준 forward production weights/holdings/capacity 자동 산출
##
## Mode 1 (schedule_recent — frozen schedule lookup, FAST):
##   기존 weights schedule (WT-D20260427_017/weights.csv)에서 row 추출.
##   schedule end 이후 as_of_date 시 max로 rollback.
##   PG2 frozen 폐기 후 사용 비추 — historical inspection 용도 retain.
##
## Mode 2 (forward_recompute — DEFAULT v2.0, PG2 LIVE):
##   2-layer 산출:
##   Layer A (Iter5 alpha): stage_artifacts/WT_D20260425_010/alpha_scores.parquet
##                         (live full 269 dates, lockbox release 영구)
##   Layer B (Iter31 weighting): linear_tilt_to_penalty_qd(λ=1.5, phi=3, ub=0.20)
##                              cash overlay DEPRECATED — base risk-only top 20.
##   Layer C (M4 outer): WT-D20260430_001/stage_artifacts/alpha_scores.parquet
##                       (BOCPD + decay + BL tri-pillar, 267m + forward extension)
##                       weight_str1715 × base + weight_cash × CASH
##
## 도훈 명령 enforcement:
##   - mandate cap 0.20 strict (OVERRIDE_006)
##   - PG2 = M4 단독 cash 결정 (base의 Iter31 cash overlay 제거)
##   - PerformanceAnalytics 표준 함수만 (자체 합성 금지)
##   - measurement_basis_primary = "forge_realized_share_based"
##
## 사용:
##   source("forward_weights.R")
##   generate_forward_weights_str1715(as_of_date = "2026-05-01")
##   # 자동 mode=forward_recompute, cap_0.20

suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
})
options(scipen = 999)

# ─── Iter31 official weighting functions (mirror run_all.R) ──────────
.normalize_long_only_v2 <- function(w, lb = 0, ub = 0.20, target_sum = 1,
                                     max_iter = 50) {
  w[is.na(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  for (it in seq_len(max_iter)) {
    s <- sum(w)
    if (abs(s - target_sum) < 1e-8) break
    if (s == 0) break
    w <- w * (target_sum / s)
    w[w > ub] <- ub
    w[w < lb] <- lb
  }
  w
}
.linear_tilt_qd_v2 <- function(alpha_t, lambda = 1.0, lb = 0, ub = 0.20) {
  if (length(alpha_t) == 0L) return(numeric(0))
  alpha_z <- (alpha_t - mean(alpha_t)) / pmax(sd(alpha_t), 1e-10)
  w <- pmax(0, 1 / length(alpha_t) + lambda * alpha_z / length(alpha_t))
  if (sum(w) > 0) w <- w / sum(w)
  .normalize_long_only_v2(w, lb = lb, ub = ub, target_sum = 1)
}
.linear_tilt_to_penalty_qd_v2 <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                           phi = 3, lb = 0, ub = 0.20) {
  w_tilt <- .linear_tilt_qd_v2(alpha_t, lambda = lambda, lb = lb, ub = ub)
  if (is.null(w_prev) || length(w_prev) == 0L) {
    return(.normalize_long_only_v2(w_tilt, lb = lb, ub = ub, target_sum = 1))
  }
  all_n <- union(names(w_tilt), names(w_prev))
  wp <- setNames(rep(0, length(all_n)), all_n)
  wp[names(w_prev)] <- w_prev
  wp <- wp[names(w_tilt)]
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  .normalize_long_only_v2(w_out, lb = lb, ub = ub, target_sum = 1)
}

# ─── Mode 2: forward_recompute (PG2 LIVE) ────────────────────────────
.generate_forward_recompute_str1715 <- function(
  as_of_date,
  apply_mandate_cap,
  output_root,
  PROJECT_ROOT,
  AUM_won = 1e10,
  N_target = 20,
  LIQ_THRESHOLD = 2e8,
  LAMBDA = 1.5, TOPHI = 3, UB = 0.20
) {
  cat(sprintf("\n[forward_recompute] as_of_date=%s\n", as.character(as_of_date)))

  # ─── Layer A: Load Iter5 alpha_scores (live full) ──
  alpha_path <- file.path(
    PROJECT_ROOT, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
  if (!file.exists(alpha_path)) {
    stop(sprintf("[Layer A] Iter5 alpha_scores 부재: %s", alpha_path))
  }
  alpha <- as.data.table(read_parquet(alpha_path))
  alpha[, Date := as.Date(Date)]
  panel_t <- alpha[Date == as_of_date & !is.na(score_eff)]
  if (nrow(panel_t) == 0L) {
    stop(sprintf("[Layer A] alpha_scores에 %s sig_date 없음. ",
                 "Iter5 forward extension 먼저 실행하세요.",
                 as.character(as_of_date)))
  }
  cat(sprintf("[Layer A] Iter5 alpha 5/1 eligible: %d tickers\n", nrow(panel_t)))

  # ─── Liquidity filter (LIQ ≥ 2e8 over t-30 ~ t-1) ──
  raw <- as.data.table(read_parquet(
    file.path(PROJECT_ROOT, ".cache/rawdata.parquet"),
    col_select = c("Date", "Ticker", "Name", "Sector", "Close", "Vol")))
  raw[, Date := as.Date(Date)]
  raw[, TradingAmt := Close * Vol]
  liq_window <- raw[Date >= as_of_date - 30L & Date < as_of_date,
                    .(AvgTV_30d_won = mean(TradingAmt, na.rm = TRUE)),
                    by = Ticker]
  liquid <- liq_window[AvgTV_30d_won >= LIQ_THRESHOLD, Ticker]
  panel_liq <- panel_t[Ticker %in% liquid]
  cat(sprintf("[Layer A] after liquidity (>=2e8): %d tickers\n", nrow(panel_liq)))

  # ─── Top N by score_eff ──
  setorder(panel_liq, -score_eff)
  picks <- panel_liq[seq_len(min(N_target, nrow(panel_liq)))]
  alpha_t_liq <- setNames(picks$score_eff, picks$Ticker)
  cat(sprintf("[Layer A] picks: %d (top by score_eff)\n", length(alpha_t_liq)))

  # ─── Layer B: Iter31 weighting (cash overlay deprecated) ──
  w_risk_base <- .linear_tilt_to_penalty_qd_v2(
    alpha_t_liq, lambda = LAMBDA, w_prev = NULL,
    phi = TOPHI, lb = 0, ub = UB)
  names(w_risk_base) <- names(alpha_t_liq)
  cat(sprintf("[Layer B] Iter31 linear_tilt: sum=%.6f max=%.4f n_active=%d\n",
              sum(w_risk_base), max(w_risk_base), sum(w_risk_base > 1e-8)))

  # ─── Layer C: M4 outer overlay ──
  m4_path <- file.path(
    PROJECT_ROOT,
    "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet")
  m4_w_str <- 1.0; m4_w_cash <- 0.0; m4_status <- "DEFAULT_PASSTHROUGH"
  if (file.exists(m4_path)) {
    m4 <- as.data.table(read_parquet(m4_path))
    m4[, Date := as.Date(Date)]
    m4_row <- m4[Date == as_of_date]
    if (nrow(m4_row) >= 1L) {
      m4_w_str <- m4_row$weight_str1715[1]
      m4_w_cash <- m4_row$weight_cash[1]
      m4_status <- "M4_LOADED"
    } else {
      m4_status <- sprintf("M4_NO_SIG_DATE_%s_RUN_FACTOR_ENGINE", as.character(as_of_date))
      warning(sprintf("[Layer C] M4 schedule에 %s 부재 — passthrough 1.0/0.0 적용. ",
                      "M4 factor_engine.R AS_OF 갱신 필요.",
                      as.character(as_of_date)))
    }
  } else {
    m4_status <- "M4_FILE_MISSING_PASSTHROUGH"
    warning("[Layer C] M4 alpha_scores 파일 부재 — passthrough.")
  }
  cat(sprintf("[Layer C] M4: weight_str1715=%.4f  weight_cash=%.4f  [%s]\n",
              m4_w_str, m4_w_cash, m4_status))

  final_risk <- w_risk_base * m4_w_str
  final_cash <- m4_w_cash
  cat(sprintf("[Final] risk_sum=%.6f cash=%.4f total=%.6f\n",
              sum(final_risk), final_cash, sum(final_risk) + final_cash))

  # ─── Build output ──
  name_map <- raw[!is.na(Name) & Ticker %in% names(final_risk),
                  .SD[which.max(Date)], by = Ticker,
                  .SDcols = c("Name", "Sector")]
  out <- data.table(Ticker = names(final_risk),
                    Weight = as.numeric(final_risk))
  out <- merge(out, name_map[, .(Ticker, Name, Sector)],
               by = "Ticker", all.x = TRUE)
  out <- merge(out, liq_window, by = "Ticker", all.x = TRUE)
  out[, AvgTV_30d_won := fifelse(is.na(AvgTV_30d_won), 0, AvgTV_30d_won)]
  setorder(out, -Weight)

  if (final_cash > 1e-6) {
    cash_row <- data.table(Ticker = "CASH", Weight = final_cash,
                           Name = "CASH (단기예금/MMF)", Sector = "Cash",
                           AvgTV_30d_won = NA_real_)
    out_full <- rbindlist(list(cash_row, out), use.names = TRUE)
  } else {
    out_full <- copy(out)
  }
  out_full[, rank := .I]

  # ─── Capacity check ──
  capacity <- list()
  if ("AvgTV_30d_won" %in% names(out_full)) {
    risk_only <- out_full[Ticker != "CASH"]
    risk_only[, ADV_share_pct := round(
      Weight * AUM_won / pmax(AvgTV_30d_won, 1) * 100, 2)]
    risk_only[, capacity_breach_5pct := ADV_share_pct > 5]
    worst <- risk_only[which.max(ADV_share_pct)]
    capacity <- list(
      AUM_won = AUM_won,
      n_tickers = nrow(risk_only),
      n_breach_ADV5 = sum(risk_only$capacity_breach_5pct, na.rm = TRUE),
      breach_tickers = risk_only[capacity_breach_5pct == TRUE, Ticker],
      worst_ADV_pct = worst$ADV_share_pct,
      worst_ticker = worst$Ticker
    )
    out_full <- merge(out_full,
                      risk_only[, .(Ticker, ADV_share_pct, capacity_breach_5pct)],
                      by = "Ticker", all.x = TRUE)
    setorder(out_full, rank)
  }

  # ─── Save ──
  date_tag <- format(as_of_date, "%Y%m%d")
  cap_tag <- gsub("\\.", "p", apply_mandate_cap)

  weights_out <- file.path(output_root,
                            sprintf("%s_weights_%s.csv", date_tag, cap_tag))
  fwrite(out_full[, .(rank, Ticker, Name, Sector, Weight)], weights_out)

  holdings_out <- file.path(output_root,
                             sprintf("%s_holdings_log_%s.csv", date_tag, cap_tag))
  if ("ADV_share_pct" %in% names(out_full)) {
    fwrite(out_full[, .(rank, Ticker, Name, Sector, Weight,
                         AvgTV_30d_억 = round(AvgTV_30d_won / 1e8, 1),
                         ADV_share_pct, capacity_breach_5pct)],
           holdings_out)
  } else {
    fwrite(out_full, holdings_out)
  }

  capacity_out <- file.path(output_root,
                             sprintf("%s_capacity_check_%s.json",
                                     date_tag, cap_tag))
  manifest <- list(
    strategy_id = "STR_1715_WT016_Iter31_GridBestProd",
    iter_label = "Iter31_LinTilt_lam1.5_TOphi3_M4_outer",
    as_of_date = as.character(as_of_date),
    mandate = apply_mandate_cap,
    mode = "forward_recompute",
    layer_a = list(
      source = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
      iter = "Iter5_multi_sleeve_composite",
      lockbox = "released (PG2 live)",
      n_eligible = nrow(panel_t),
      n_after_liquidity = nrow(panel_liq),
      n_picked = length(alpha_t_liq)
    ),
    layer_b = list(
      iter = "Iter31_grid_best",
      lambda = LAMBDA, tophi = TOPHI, ub = UB,
      cash_overlay = "DEPRECATED 2026-05-02 (M4 단독)"
    ),
    layer_c = list(
      source = "WT-D20260430_001/stage_artifacts/alpha_scores.parquet",
      schedule = "M4_BOCPD_decay_BL_tri_pillar",
      weight_str1715 = m4_w_str,
      weight_cash = m4_w_cash,
      status = m4_status
    ),
    n_total_lines = nrow(out_full),
    n_risk_holdings = sum(out_full$Ticker != "CASH"),
    sum_weights = round(sum(out_full$Weight), 6),
    max_weight = round(max(out_full$Weight), 4),
    total_cash_pct = final_cash,
    measurement_basis_primary = "forge_realized_share_based",
    capacity_check = capacity,
    notes = paste("Mode=forward_recompute v2.0 (도훈 명시 2026-05-02).",
                  "PG2 LIVE — base Iter31 cash overlay 제거, M4 단독 cash 결정.",
                  "Iter5 alpha layer + Iter31 weighting + M4 outer overlay.")
  )
  write_json(manifest, capacity_out, pretty = TRUE,
             auto_unbox = TRUE, null = "null")

  cat(sprintf("\n[forward_recompute] outputs:\n"))
  cat(sprintf("  weights:   %s\n", weights_out))
  cat(sprintf("  holdings:  %s\n", holdings_out))
  cat(sprintf("  capacity:  %s\n", capacity_out))

  invisible(list(weights = out_full, manifest = manifest,
                 paths = list(weights = weights_out,
                              holdings = holdings_out,
                              capacity = capacity_out)))
}

# ─────────────────────────────────────────────────────────
generate_forward_weights_str1715 <- function(
  as_of_date         = NULL,                  # NULL = max(weights schedule) [Mode 1] / NULL = today first day [Mode 2]
  apply_mandate_cap  = c("cap_0.20", "no_cap"),
  mode               = c("forward_recompute", "schedule_recent"),
  weights_source     = NULL,                  # Mode 1만 — frozen schedule path
  output_root        = NULL
) {
  apply_mandate_cap <- match.arg(apply_mandate_cap)
  mode <- match.arg(mode)

  # ─── Resolve paths ───────────────────────────────────
  STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
  if (!dir.exists(STRAT_DIR)) STRAT_DIR <- getwd()
  if (basename(STRAT_DIR) != "STR_1715_WT016_Iter31_GridBestProd") {
    cand <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
                      "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd")
    if (dir.exists(cand)) STRAT_DIR <- cand
  }
  PROJECT_ROOT <- file.path(STRAT_DIR, "..", "..", "..")
  PROJECT_ROOT <- if (dir.exists(PROJECT_ROOT)) {
    file.path(PROJECT_ROOT)
  } else {
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
  }

  if (is.null(output_root)) {
    output_root <- file.path(STRAT_DIR, "production_weights")
  }
  dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

  # ─── Mode 2 분기 (DEFAULT — PG2 LIVE) ─────────────────
  if (mode == "forward_recompute") {
    if (is.null(as_of_date)) {
      as_of_date <- as.Date(format(Sys.Date(), "%Y-%m-01"))
      cat(sprintf("[STR_1715] as_of_date defaulted to current month: %s\n",
                  as.character(as_of_date)))
    } else {
      as_of_date <- as.Date(as_of_date)
    }
    return(.generate_forward_recompute_str1715(
      as_of_date = as_of_date,
      apply_mandate_cap = apply_mandate_cap,
      output_root = output_root,
      PROJECT_ROOT = PROJECT_ROOT))
  }

  # ─── Mode 1: schedule_recent (frozen lookup, legacy) ──
  if (is.null(weights_source)) {
    weights_source <- file.path(PROJECT_ROOT,
                                 "qepm/mailbox/worktask/WT-D20260427_017/weights.csv")
  }
  if (!file.exists(weights_source)) {
    stop(sprintf("[STR_1715 forward_weights] weights schedule not found: %s", weights_source))
  }

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
  mode <- if (length(args) >= 3) args[3] else "forward_recompute"
  generate_forward_weights_str1715(
    as_of_date = as_of,
    apply_mandate_cap = cap_mode,
    mode = mode)
}
