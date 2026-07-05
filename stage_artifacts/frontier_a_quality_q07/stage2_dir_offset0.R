ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
suppressMessages({ library(data.table); library(xts) })
ppy <- 12
ir_of <- function(a){ a<-a[is.finite(a)]; if(length(a)<3) return(NA_real_); mean(a)/stats::sd(a)*sqrt(ppy) }
ym <- function(d) format(as.Date(d),"%Y-%m")

bt <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
pr <- as.data.table(bt$period_returns)[,.(date,ret_net)]
br <- as.data.table(bt$benchmark_returns)[,.(date,benchmark_ret)]
book <- merge(pr,br,by="date"); setorder(book,date)
book <- book[date<=as.Date("2026-06-30")]
book[,ym:=ym(date)]; book[,book_active:=ret_net-benchmark_ret]; book[,pos:=.I]
INCUMBENT_IR <- 1.416

sl <- as.data.table(readRDS("stage_artifacts/frontier_a_quality_q07/qual_caution_active.rds"))
setnames(sl,"active","sleeve_active"); sl[,ym:=ym(Date)]

# offset-0 (contemporaneous, IR-verified) alignment: sleeve 0 outside its 13 CAUTION months
sf <- merge(book[,.(ym,pos,book_active)], sl[,.(ym,sleeve_active)], by="ym", all.x=TRUE)
sf[is.na(sleeve_active), sleeve_active:=0]; setorder(sf,pos)

# active_cor over 13 overlap (offset 0)
ov <- sf[sleeve_active!=0]
active_cor <- stats::cor(ov$sleeve_active, ov$book_active)

weights <- c(0.05,0.10,0.15,0.20,0.30)
ir_grid <- sapply(weights, function(w){ ir_of((1-w)*sf$book_active + w*sf$sleeve_active) })
names(ir_grid) <- sprintf("%.2f",weights)
best_i <- which.max(ir_grid); best_w <- weights[best_i]
best_new_ir <- as.numeric(ir_grid[best_i]); delta_ir <- best_new_ir - INCUMBENT_IR

cat("=== OFFSET-0 (IR-verified contemporaneous) dIR ===\n")
cat(sprintf("active_cor (offset0, n=%d) = %.4f\n", nrow(ov), active_cor))
cat("IR grid:\n"); print(round(ir_grid,4))
cat(sprintf("best_w=%.2f best_new_ir=%.4f incumbent=%.4f dIR=%.4f\n", best_w,best_new_ir,INCUMBENT_IR,delta_ir))
cat(sprintf("GATE dIR>=0.05: %s | active_cor<0.30: %s\n", delta_ir>=0.05, active_cor<0.30))
cat("ir_grid_str: ", paste(sprintf("%.2f=%.4f",weights,ir_grid),collapse="; "), "\n")

# baseline IR of book restricted to same series (should equal 1.416)
cat(sprintf("book_active-only IR (w=0) = %.4f\n", ir_of(sf$book_active)))
