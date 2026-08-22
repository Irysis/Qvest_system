res <- readRDS("C:/Users/99922/OneDrive/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260822_012/_measure_res.rds")
o <- file("C:/Users/99922/OneDrive/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260822_012/_res_dump.txt", open="wt")
capture.output(str(res, max.level=3), file=o)
close(o); cat("DUMP_DONE\n")
