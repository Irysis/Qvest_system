# debug_two_gate4_validate.R — Gate 4.3 validation (canonical_screen_bt) on pure factors, longer window
suppressMessages({ library(data.table); library(arrow) })
sink("02_Infrastructure/ramp/debug/_debug_gate4_validate.txt", split = TRUE)
t0 <- Sys.time()

source("02_Infrastructure/ramp/pure_factor_extraction.R")
source("02_Infrastructure/ramp/factor_validation.R")
config <- yaml::read_yaml("02_Infrastructure/ramp/ramp_config.yml")

rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet"))
test_factors <- c("M01_Mom_12_1", "V02_EP", "Q01_GPA", "D02_Beta", "S01_Size", "L01_Amihud")

# monthly sig dates: 2018-01 .. 2024-12 (month-ends) — enough for IC/screen + OOS
all_months <- seq(as.Date("2018-01-31"), as.Date("2024-12-31"), by = "month")
# snap to month-end
me <- function(d) { x <- seq(d, by="month", length.out=2)[2]; x - 1 }
sig_dates <- as.Date(sapply(all_months, function(d) as.character(me(as.Date(format(d,"%Y-%m-01")))) ))
sig_dates <- sort(unique(sig_dates))
cat("n sig_dates:", length(sig_dates), " range:", as.character(min(sig_dates)), "..", as.character(max(sig_dates)), "\n")

cat("\n=== extract pure factor scores (FWL) ===\n")
pf <- extract_pure_factor(test_factors, sig_dates, rawdata, verbose = FALSE)
cat("score rows:", nrow(pf$scores), " orth pass rate:",
    round(mean(pf$orth_summary[status=="ok"]$orthogonality_pass, na.rm=TRUE),3), "\n")

cat("\n=== forward returns + validation ===\n")
fwd <- build_monthly_forward_returns(rawdata, sig_dates)
cat("forward return months:", uniqueN(fwd$returns_dt$Date), " bench months:", nrow(fwd$bench_dt), "\n")

metrics <- list()
for (fid in unique(pf$scores$factor_id)) {
  sub <- pf$scores[factor_id == fid]
  v <- validate_factor(sub, fwd, top_n = 20L, cost_bps = 15)
  metrics[[fid]] <- as.data.table(v[c("factor_id","metric_type","n_months","n_ic_months",
    "rank_ic_mean","rank_ic_ir","net_quintile_spread_oos","cost_drag","net_sr",
    "portfolio_alpha_t_nw","information_ratio","turnover_annual")])
}
M <- rbindlist(metrics, fill = TRUE)
cat("\nvalidation metrics (metric_type=backtested via canonical_screen):\n")
print(M[, lapply(.SD, function(x) if(is.numeric(x)) round(x,4) else x)])

cat("\n=== approve_factors ===\n")
econ <- setNames(rep(TRUE, length(test_factors)), test_factors)  # debug: assume rationale present
appr <- approve_factors(M, config, econ_present = econ)
print(appr[, .(factor_id, status, reject_reason, rank_ic_ir=round(rank_ic_ir,3),
               spread=round(net_quintile_spread_oos,4), cost_drag=round(cost_drag,3))])
cat("\napproved:", sum(appr$status=="approved"), "/", nrow(appr), "\n")

cat(sprintf("\n[gate4 validate] elapsed: %.1f sec\n", as.numeric(Sys.time()-t0, units="secs")))
sink()
cat("debug_two_gate4_validate done\n")
