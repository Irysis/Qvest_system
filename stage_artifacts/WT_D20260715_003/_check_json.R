suppressPackageStartupMessages(library(jsonlite))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
j <- fromJSON("qepm/observability/filing_delay_watch_latest.json")
cat("as_of:", j$as_of, "| n_holdings:", j$n_holdings_equity, "\n")
cat("Part A n_warn:", j$n_warn, "| archive stale:", j$archive_freshness$stale, "\n")
cat("Part B audit_source_ok:", j$audit_distress$audit_source_ok, "| n_audit_warn:", j$audit_distress$n_audit_warn, "\n")
ins <- j$insider_net_buy_safe
cat("Part C ok:", ins$insider_source_ok, "| n_safe:", ins$n_net_buy_safe,
    "| n_with_insider:", ins$n_holdings_with_insider, "| hold_ym:", ins$current_holding_ym,
    "| stale:", ins$panel_stale, "| r34:", ins$r34_verdict, "\n")
cat("per_holding_insider rows:", length(ins$per_holding_insider), "\n")
cat("net_sell_advisory:", ins$n_net_sell_advisory, "| no_insider_data:", ins$n_no_insider_data, "\n")
