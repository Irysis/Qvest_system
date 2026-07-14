library(jsonlite)
j <- fromJSON("qepm/observability/filing_delay_watch_latest.json")
cat("JSON well-formed OK\n\n")
ins <- j$insider_net_buy_safe
cat("as_of:", j$as_of, "| holding_ym:", ins$current_holding_ym, "prev:", ins$prev_holding_ym, "\n")
cat("n_net_buy_safe:", ins$n_net_buy_safe, "| n_safe_fading:", ins$n_safe_fading,
    "| n_no_insider_data:", ins$n_no_insider_data, "\n")
cat("r40_verdict:", ins$r40_verdict, "| r40_verdict_class:", ins$r40_verdict_class, "\n\n")
cat("== state_machine.exit_rule ==\n", ins$state_machine$exit_rule, "\n\n")
cat("== state_machine.fade_horizon_rule ==\n", ins$state_machine$fade_horizon_rule, "\n\n")
cat("== catastrophic_vs_benign ==\n", ins$state_machine$catastrophic_vs_benign, "\n\n")
cat("== safe_fading_list ==\n"); print(ins$safe_fading_list)
cat("\n== per_holding SAFE_FADING months_since_off check ==\n")
ph <- ins$per_holding_insider
sf <- ph[!is.na(ph$insider_flag) & ph$insider_flag=="SAFE_FADING", c("ticker","insider_state","months_since_off","tier","insider_flag")]
print(sf)
cat("\n== 3-part report presence ==\n")
cat("Part A filing_delay n_warn:", j$n_warn, "| archive stale:", j$archive_freshness$stale, "\n")
cat("Part B audit n_audit_warn:", j$audit_distress$n_audit_warn, "| composite n_in_holdings:", j$audit_distress$composite_watchlist$n_in_holdings, "\n")
cat("Part C insider n_safe_fading:", ins$n_safe_fading, "| panel_stale:", ins$panel_stale, "\n")
