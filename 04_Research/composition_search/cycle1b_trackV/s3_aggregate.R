# =============================================================================
# s3_aggregate.R — Track V aggregation: deltas vs base, preregistered verdicts,
#   IS-only selection + one-shot OOS non-worsening check, DSR diagnostics,
#   cross-base axis generalization. Writes variation_results.{csv,json} + marker.
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite)
}))
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
TV   <- file.path(PROJ, "04_Research/composition_search/cycle1b_trackV")
RESD <- file.path(TV, "results")
source(file.path(PROJ, "02_Infrastructure/contracts/essence_score.R"))  # .essence_dsr (BLdP 2014)

`%||%` <- function(a, b) if (is.null(a)) b else a
N_TRIALS <- 38L
prereg <- fromJSON(file.path(TV, "prereg_variations.json"), simplifyVector = FALSE)

# run_id -> axis map from prereg (+ base runs)
axis_map <- list()
for (b in prereg$bases) {
  axis_map[[paste0(sub("_.*$", "", b$base_id), "_BASE")]] <- "base"
  for (v in b$variants) axis_map[[v$variant_id]] <- v$axis
}
TO_AXES <- c("holding_band", "rebalance_freq", "signal_smoothing", "combo")

BMM <- fread(file.path(TV, "inputs/bm_monthly.csv"))
BMM[, ym := format(as.Date(Date), "%Y-%m")]

bases <- c(B1 = "b1_str1715_vanilla", B2 = "b2_str1715v2", B3 = "b3_valmom_amp", B4 = "b4_c19_lo25")
g <- function(x, d = NA_real_) if (is.null(x) || length(x) == 0) d else as.numeric(x)

rows <- list(); sel_summary <- list(); repro_all <- list(); per_base_json <- list()
for (bk in names(bases)) {
  res <- fromJSON(file.path(RESD, paste0(bases[[bk]], "_results.json")), simplifyVector = FALSE)
  ser <- readRDS(file.path(RESD, paste0(bases[[bk]], "_series.rds")))
  repro_all[[res$base_id]] <- res$repro_check
  runs <- res$runs
  base_key <- paste0(bk, "_BASE")
  stopifnot(base_key %in% names(runs))
  bw <- runs[[base_key]]$windows
  brow_list <- list()
  for (rn in names(runs)) {
    r <- runs[[rn]]
    if (!is.null(r$error)) {
      brow_list[[rn]] <- data.table(base_id = res$base_id, run_id = rn,
                                    axis = axis_map[[rn]] %||% NA_character_, error = r$error)
      next
    }
    w <- r$windows
    # DSR diagnostic (FULL net active vs KOSPI200, n_trials = 38 sweep total)
    dsr <- NA_real_
    s <- ser[[rn]]
    if (!is.null(s)) {
      s2 <- merge(as.data.table(s), BMM[, .(ym, BM_Ret_m)], by = "ym", all.x = TRUE)
      s2[is.na(BM_Ret_m), BM_Ret_m := 0]
      a <- s2$net - s2$BM_Ret_m; a <- a[is.finite(a)]
      if (length(a) >= 12 && sd(a) > 0) {
        mu <- mean(a); sdv <- sd(a)
        dsr <- .essence_dsr(mu / sdv * sqrt(12), length(a), N_TRIALS,
                            mean(((a - mu) / sdv)^3), mean(((a - mu) / sdv)^4), A = 12)
      }
    }
    is_base <- rn == base_key
    d_is_sr   <- if (is_base) 0 else g(w$IS$sr_net)  - g(bw$IS$sr_net)
    d_oos_sr  <- if (is_base) 0 else g(w$OOS$sr_net) - g(bw$OOS$sr_net)
    d_full_sr <- if (is_base) 0 else g(w$FULL$sr_net) - g(bw$FULL$sr_net)
    d_full_cost <- if (is_base) 0 else g(w$FULL$cost_ann_pct) - g(bw$FULL$cost_ann_pct)
    d_full_to1w <- if (is_base) 0 else g(w$FULL$to_oneway_ann) - g(bw$FULL$to_oneway_ann)
    d_is_cost   <- if (is_base) 0 else g(w$IS$cost_ann_pct) - g(bw$IS$cost_ann_pct)
    ax <- axis_map[[rn]] %||% NA_character_
    leg1 <- !is_base && is.finite(d_is_sr) && d_is_sr > 0
    leg2 <- !is_base && is.finite(d_oos_sr) && d_oos_sr >= 0
    leg3 <- if (ax %in% TO_AXES) (is.finite(d_full_cost) && d_full_cost < 0) else NA
    verdict <- if (is_base) "BASE"
               else if (leg1 && leg2 && (is.na(leg3) || isTRUE(leg3))) "IMPROVED"
               else paste0("NOT_IMPROVED(", paste(c(
                 if (!leg1) "IS_dSR<=0", if (!leg2) "OOS_dSR<0",
                 if (isFALSE(leg3)) "cost_not_saved"), collapse = "+"), ")")
    brow_list[[rn]] <- data.table(
      base_id = res$base_id, run_id = rn, axis = ax,
      full_n = g(w$FULL$n_months), full_sr_net = g(w$FULL$sr_net), full_sr_gross = g(w$FULL$sr_gross),
      full_cagr_pct = g(w$FULL$cagr_net) * 100, full_mdd_pct = g(w$FULL$mdd_net) * 100,
      full_calmar = g(w$FULL$calmar), full_to_oneway = g(w$FULL$to_oneway_ann),
      full_cost_pct = g(w$FULL$cost_ann_pct), full_port_t = g(w$FULL$port_t_nw),
      full_ir = g(w$FULL$net_ir), full_active_sr = g(w$FULL$active_sr),
      is_n = g(w$IS$n_months), is_sr_net = g(w$IS$sr_net), is_cagr_pct = g(w$IS$cagr_net) * 100,
      is_mdd_pct = g(w$IS$mdd_net) * 100, is_to_oneway = g(w$IS$to_oneway_ann), is_cost_pct = g(w$IS$cost_ann_pct),
      oos_n = g(w$OOS$n_months), oos_sr_net = g(w$OOS$sr_net), oos_cagr_pct = g(w$OOS$cagr_net) * 100,
      oos_mdd_pct = g(w$OOS$mdd_net) * 100, oos_to_oneway = g(w$OOS$to_oneway_ann), oos_cost_pct = g(w$OOS$cost_ann_pct),
      r2017_sr_net = g(w$R2017$sr_net), r2017_port_t = g(w$R2017$port_t_nw),
      d_is_sr = round(d_is_sr, 4), d_oos_sr = round(d_oos_sr, 4), d_full_sr = round(d_full_sr, 4),
      d_full_cost_pct = round(d_full_cost, 4), d_is_cost_pct = round(d_is_cost, 4),
      d_full_to_oneway = round(d_full_to1w, 4),
      leg1_is_improve = leg1, leg2_oos_nonworse = leg2, leg3_cost_saved = leg3,
      verdict = verdict, dsr_full_active_n38 = round(dsr, 4),
      avg_n = g(r$diag$avg_n), n_rebal = g(r$diag$n_rebalances), na_fill_share = g(r$diag$na_fill_share),
      error = NA_character_
    )
  }
  bt <- rbindlist(brow_list, fill = TRUE)
  rows[[bk]] <- bt
  # IS-only selection (argmax IS sr_net incl. base) + one-shot OOS non-worsening
  ok <- bt[is.na(error) & is.finite(is_sr_net)]
  sel <- ok[which.max(is_sr_net)]
  base_oos <- ok[run_id == base_key, oos_sr_net]
  sel_summary[[res$base_id]] <- list(
    selected_by_IS = sel$run_id, selected_is_sr = sel$is_sr_net,
    base_is_sr = ok[run_id == base_key, is_sr_net],
    oos_check = if (sel$run_id == base_key) "BASE_SELECTED(no variant improves IS)"
                else if (is.finite(sel$oos_sr_net) && sel$oos_sr_net >= base_oos) "OOS_NONWORSENING_PASS"
                else "OOS_NONWORSENING_FAIL",
    selected_oos_sr = sel$oos_sr_net, base_oos_sr = base_oos,
    selected_dsr_n38 = sel$dsr_full_active_n38
  )
  per_base_json[[res$base_id]] <- bt
}
ALL <- rbindlist(rows, fill = TRUE)
fwrite(ALL, file.path(TV, "variation_results.csv"))

# ---- cross-base axis generalization ----
axe <- ALL[axis != "base" & is.na(error),
           .(n_runs = .N,
             n_is_improve = sum(leg1_is_improve, na.rm = TRUE),
             n_is_and_oos = sum(leg1_is_improve & leg2_oos_nonworse, na.rm = TRUE),
             n_improved = sum(verdict == "IMPROVED"),
             mean_d_is_sr = round(mean(d_is_sr, na.rm = TRUE), 4),
             mean_d_oos_sr = round(mean(d_oos_sr, na.rm = TRUE), 4),
             mean_d_full_cost_pct = round(mean(d_full_cost_pct, na.rm = TRUE), 4)),
           by = axis]

out <- list(
  artifact = "Track V variation grid measurement (Composition Search Cycle 1b)",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  prereg = "prereg_variations.json (FROZEN 2026-06-11) — all 38 preregistered runs reported, no additions",
  metric_type = "canonical_screen (screening tier only; graduation HARD gates unaffected)",
  cost_model = "v2.4_kr_retail_15bps delta: cost_t = 0.0015 x sum|dW| (buy+sell legs each 15bps, drift-aware). cost_ann = 15bps x to_traded_ann == 2 x 15bps x to_oneway_ann (B0 convention).",
  selection_protocol = list(selection_type = "sweep", n_trials = N_TRIALS,
    rule = "per base IS(2005~2018)-only argmax net SR incl. base; OOS(2019~) consulted once for non-worsening; no OOS argmax"),
  cost_consistency_note = "Verdict leg3: under a delta engine d_cost == 0.0015 x d_traded holds as an identity; the preregistered magnitude check is therefore auto-satisfied and leg3 reduces to sign-consistency (cost actually saved). Gross-vs-cost attribution visible via full_sr_gross / d_full_cost_pct.",
  repro_checks = repro_all,
  selection = sel_summary,
  axis_generalization = axe,
  results = per_base_json
)
write_json(out, file.path(TV, "variation_results.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), file.path(TV, "DONE_TRACKV"))
cat("[s3] variation_results.csv / .json + DONE_TRACKV written\n")
print(axe)
for (nm in names(sel_summary)) {
  s <- sel_summary[[nm]]
  cat(sprintf("[SELECT] %s: %s (IS %.3f vs base %.3f) | %s (OOS %.3f vs %.3f) | DSR(n38)=%.3f\n",
              nm, s$selected_by_IS, s$selected_is_sr, s$base_is_sr, s$oos_check,
              g2 <- ifelse(is.finite(s$selected_oos_sr), s$selected_oos_sr, NA),
              ifelse(is.finite(s$base_oos_sr), s$base_oos_sr, NA),
              ifelse(is.finite(s$selected_dsr_n38), s$selected_dsr_n38, NA)))
}
