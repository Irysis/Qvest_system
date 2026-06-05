# =============================================================
# WT-D20260529_001 FLOW — Stage 2: Multi-sleeve blend (STR_1715 + FLOW)
# sleeve allocation sweep + LOO + portfolio-level monthly CVaR + SR 2.5 honest judgment
# selected FLOW sleeve method = from stage 1 (opt_stage2.rds)
# =============================================================
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")

st <- readRDS(file.path(OUT,"opt_stage2.rds"))
comp <- st$comp; sel_method <- st$sel_method; res <- st$res; bm_m <- st$bm_m
cat("[blend] FLOW sleeve method selected:", sel_method, "\n")

# FLOW selected sleeve net monthly returns
flow <- res[[sel_method]][, .(ym, flow_ret = ret_net, flow_to = turnover)]
flow[, Date := as.Date(paste0(ym,"-01"))]

# STR_1715 monthly (overlap pre-lockbox)
s1715 <- fread("qepm/mailbox/governor/str_1715_full_reassessment/str_1715_monthly_returns_full.csv")
s1715[, Date := as.Date(Date)]; s1715[, ym := format(Date,"%Y-%m")]
s1715 <- s1715[, .(ym, s1715_ret = monthly_ret)]

bench <- bm_m[, .(ym, bm)]

# common window
M <- Reduce(function(a,b) merge(a,b,by="ym"), list(flow[,.(ym,flow_ret,flow_to)], s1715, bench))
M[, Date := as.Date(paste0(ym,"-01"))]
setorder(M, Date)
M <- M[Date <= as.Date("2023-12-22")]   # lockbox window for clean blend comparison
cat(sprintf("[blend] common months: %d (%s..%s)\n", nrow(M), min(M$ym), max(M$ym)))

ann_sr <- function(r) mean(r)/sd(r)*sqrt(12)
ann_ret<- function(r) prod(1+r)^(12/length(r))-1
ann_vol<- function(r) sd(r)*sqrt(12)
mdd    <- function(r){x<-xts(r, order.by=as.Date(paste0(M$ym,"-01"))); as.numeric(maxDrawdown(x))}
cvar95_m <- function(r){q<-quantile(r,0.05); -mean(r[r<=q])}   # monthly CVaR95 (loss positive)
ir_vs_bm <- function(r,b){a<-r-b; mean(a)/sd(a)*sqrt(12)}

# baseline stats
sr_1715 <- ann_sr(M$s1715_ret); sr_flow <- ann_sr(M$flow_ret)
cat(sprintf("[blend] STR_1715 net SR=%.3f | FLOW(%s) net SR=%.3f | cor(returns)=%.3f\n",
            sr_1715, sel_method, sr_flow, cor(M$s1715_ret, M$flow_ret)))

# ---- allocation sweep: STR_1715 X% + FLOW Y%, X+Y=1 ----
grid <- seq(0, 0.5, by=0.05)   # FLOW weight 0..50%
sweep <- rbindlist(lapply(grid, function(y){
  x <- 1-y
  r <- x*M$s1715_ret + y*M$flow_ret
  data.table(flow_w=y, str1715_w=x,
             book_sr=round(ann_sr(r),4), book_ret=round(ann_ret(r),4),
             book_vol=round(ann_vol(r),4), book_mdd=round(mdd(r),4),
             book_ir=round(ir_vs_bm(r, M$bm),4),
             book_cvar95_m=round(cvar95_m(r),4))
}))
cat("\n=== BLEND ALLOCATION SWEEP (book-level, net) ===\n")
print(sweep)
fwrite(sweep, file.path(OUT,"blend_sweep.csv"))

best <- sweep[which.max(book_sr)]
cat(sprintf("\n[blend] max book SR at FLOW=%.0f%% / STR_1715=%.0f%%: SR=%.3f (vs 1715-only %.3f, Δ=%.3f)\n",
            best$flow_w*100, best$str1715_w*100, best$book_sr, sr_1715, best$book_sr - sr_1715))

# ---- LOO: drop FLOW vs keep ----
loo <- data.table(
  config = c("STR_1715 only (FLOW dropped)", sprintf("STR_1715 + FLOW @%.0f%%", best$flow_w*100)),
  book_sr = c(round(sr_1715,4), best$book_sr),
  book_ret= c(round(ann_ret(M$s1715_ret),4), best$book_ret),
  book_mdd= c(round(mdd(M$s1715_ret),4), best$book_mdd),
  book_cvar95_m = c(round(cvar95_m(M$s1715_ret),4), best$book_cvar95_m)
)
cat("\n=== LEAVE-ONE-OUT (FLOW contribution) ===\n"); print(loo)
fwrite(loo, file.path(OUT,"blend_loo.csv"))

# ---- portfolio-level monthly CVaR cap check (risk rec #3) ----
# Risk agent: sleeve CVaR95 daily 0.0343 -> monthly sqrt21 0.157. Set portfolio monthly CVaR95 cap.
# Use book-level realized monthly CVaR95 at best allocation as binding metric.
cvar_cap_monthly <- 0.15   # portfolio-level monthly CVaR95 cap (optimizer-set; below sleeve 0.157)
book_r_best <- best$str1715_w*M$s1715_ret + best$flow_w*M$flow_ret
book_cvar <- cvar95_m(book_r_best)
cvar_pass <- book_cvar <= cvar_cap_monthly
cat(sprintf("\n[CVaR] portfolio monthly CVaR95 cap=%.3f | realized book CVaR95=%.4f | PASS=%s\n",
            cvar_cap_monthly, book_cvar, cvar_pass))

# ---- SR 2.5 honest judgment ----
max_book_sr <- max(sweep$book_sr)
reach_25 <- max_book_sr >= 2.5
cat(sprintf("\n=== SR 2.5 JUDGMENT ===\nmax achievable book SR (this 2-sleeve blend, lockbox window) = %.3f\nSR 2.5 reached: %s\n",
            max_book_sr, reach_25))

saveRDS(list(M=M, sweep=sweep, best=best, loo=loo, sel_method=sel_method,
             sr_1715=sr_1715, sr_flow=sr_flow, book_cvar=book_cvar,
             cvar_cap_monthly=cvar_cap_monthly, cvar_pass=cvar_pass,
             max_book_sr=max_book_sr, reach_25=reach_25,
             cor_returns=cor(M$s1715_ret, M$flow_ret)),
        file.path(OUT,"opt_blend.rds"))
cat("\n[done stage 2 blend]\n")
