x<-jsonlite::fromJSON("qepm/mailbox/worktask/WT-D20260802_013/alpha_package.json")
cat("pkg ok:",x$task_id,x$spec_version,x$verdict_summary$result,"| paired_t:",x$diagnostics$paired_primary$paired_t_nw,"| flags:",length(x$challenge_flags$id),"
")
