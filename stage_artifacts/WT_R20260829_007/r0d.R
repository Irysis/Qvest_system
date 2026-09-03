suppressMessages(library(jsonlite))
p <- fromJSON("qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json")
d <- p$diagnostics
for(k in c("beta","turnover_proxy","turnover_convention","oos_retention_approx","net_sr","deflated_sharpe_ratio","subperiod_stability","rank_ic","icir","monotonicity","diag_cap_tier_weight_share","reachability_coverage_ratio","post_neutralization_ic","post_neutralization_retention"))
  cat(k,"=",substr(paste(unlist(d[[k]]),collapse=" | "),1,400),"\n")
cat("\nchallenge_flags:\n"); print(unlist(p$challenge_flags))
