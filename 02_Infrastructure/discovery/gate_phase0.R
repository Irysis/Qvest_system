#==============================================================================
# Phase 0 검수 게이트 — 발굴 신호 net long-only 판정 (방화벽; discovery→production 번역)
#   A score_eff / B score_eff+factors / C factors-only 를 canonical_screen_bt(net,
#   NW lag-3, 비용·턴오버·벤치 active)로 비교. ★자본 자격은 이 게이트 통과분만.
#==============================================================================
suppressPackageStartupMessages({ library(arrow); library(data.table) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))

sc <- as.data.table(read_parquet(file.path(ROOT,".cache/discovery/phase0_scores.parquet")))
sc[, Date := as.Date(paste0(ym,"-01"))]
returns_dt <- unique(sc[, .(Date, Ticker, Ret_1m = fwd_ret_1m)])

# 벤치: 월간 forward KOSPI200 (포트와 동일 forward 규약)
bm <- as.data.table(read_parquet(file.path(ROOT,".cache/benchmark.parquet")))
bmcol <- intersect(c("BM_Ret","Ret","bm_ret"), names(bm))[1]
bm[, Date := as.Date(Date)]; bm <- bm[!is.na(get(bmcol))]
bm[, ym := format(Date,"%Y-%m")]
bmm <- bm[, .(lr = sum(log(1+get(bmcol)))), by=ym]; setorder(bmm, ym)
bmm[, mret := expm1(lr)][, fwd := shift(mret,-1)]
bench_dt <- bmm[!is.na(fwd), .(Date = as.Date(paste0(ym,"-01")), BM_Ret = fwd)]

run <- function(sig, top_n){
  s <- sc[, .(Date, Ticker, score = get(sig))][!is.na(score)]
  r <- tryCatch(canonical_screen_bt(s, returns_dt, bench_dt, top_n=top_n, cost_bps_oneway=15),
                error=function(e){ cat("  ERR",sig,conditionMessage(e),"\n"); NULL })
  if(is.null(r)) return(NULL)
  data.table(signal=sig, top_n=top_n,
             PORT_t=round(r$portfolio_alpha_t_nw_lag3,3),
             net_SR=round(r$net_sr,3),
             alpha_ann_pct=round(r$alpha_annualized*100,2),
             IR=round(r$information_ratio,3),
             active_bps_m=round(r$mean_active_net,1),
             TO_ann=round(r$turnover_annual,2),
             n_months=r$n_months)
}

cat("=== Phase 0 게이트: net long-only (canonical_screen_bt, 15bps, NW lag-3) ===\n")
res <- rbindlist(lapply(c("score_eff","predB","predC"), function(s) run(s, 20)), fill=TRUE)
res25 <- rbindlist(lapply(c("score_eff","predB","predC"), function(s) run(s, 25)), fill=TRUE)
all <- rbind(res, res25)
print(all)

a20 <- res[signal=="score_eff", PORT_t]; b20 <- res[signal=="predB", PORT_t]
cat(sprintf("\n증분(top20): B−A PORT_t %+0.3f | net_SR %+0.3f | active %+0.1fbps/m\n",
            b20-a20, res[signal=="predB",net_SR]-res[signal=="score_eff",net_SR],
            res[signal=="predB",active_bps_m]-res[signal=="score_eff",active_bps_m]))
cat("graduation HARD: PORT_t>=2.95 →",
    paste(res$signal, ifelse(res$PORT_t>=2.95,"PASS","FAIL"), sep=":", collapse=" | "), "\n")
fwrite(all, file.path(ROOT,".cache/discovery/phase0_gate_results.csv"))
cat("saved .cache/discovery/phase0_gate_results.csv\n")
