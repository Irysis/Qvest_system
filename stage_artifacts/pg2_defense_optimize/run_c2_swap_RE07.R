## ============================================================================
## run_c2_swap_RE07.R — candidate c2_swap_RE07 pinned recon + recon-vs-recon marginal
## Candidate: Q07,M08,RE07_Crisis_Beta EW (Q25 removed). Mechanism: Q25 (drawdown
##   rank100 weakest) -> RE07_Crisis_Beta (episode hit100%).
## Authoritative marginal denominator = CURRENT-defense pinned_ic recon (convention-
##   matched to deployed book IC-sign freeze). regdir = robustness x-check.
## marginal = candidate - recon_baseline on IDENTICAL pinned cache (drift cancels).
## Real-computation only: eval_defense() -> contract build_metrics/build_benchmark_compare
##   + PerformanceAnalytics; no self-synthesis.
## NOTE: harness ed_init() segfaults when invoked internally on this box; we manually
##   populate .ED (identical reads, verified byte-safe) then set .ED$ready=TRUE so
##   eval_defense() early-returns past ed_init. Construction/metrics path unchanged.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); setDTthreads(1L)
suppressWarnings(try(arrow::set_io_thread_count(1L), silent=TRUE))
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pin.R"))
setDTthreads(1L)
OUT <- file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize")
## Local (non-OneDrive) byte-identical copies of pinned caches — avoids OneDrive
## mmap-paging segfault ([[project-windows-arrow-mmap-1224]] / stray-process segfault).
SCRATCH <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
RAW_PIN_LOCAL <- file.path(SCRATCH,"RAWDATA_pin.parquet")
BM_PIN_LOCAL  <- file.path(SCRATCH,"benchmark_pin.parquet")

## ---- manual ed_init (segfault-safe) -----------------------------------------
manual_ed_init <- function(src){
  .ED$PANEL_SRC <- src
  panel_file <- if (identical(src,"ic")) "defense_factor_panel.parquet" else "defense_factor_panel_regdir.parquet"
  .ED$PANEL <- as.data.table(read_parquet(file.path(OUT,panel_file)))
  .ED$PANEL[, sig_date := as.Date(sig_date)]
  ap <- as.data.table(read_parquet(file.path(ED_ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
  ap[, Date := as.Date(Date)]
  .ED$AP <- ap[, .(Date, Ticker, score_core_z, score_defense_z, score_eff, regime_state)]
  raw <- as.data.table(read_parquet(RAW_PIN_LOCAL,
           col_select=c("Date","Ticker","Close","Vol","Ret")))
  raw[, Date := as.Date(Date)]; raw[, TradingAmt := Close*Vol]; setkey(raw, Date, Ticker)
  .ED$RAW <- raw
  p5 <- fread(file.path(ED_ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
  p5[, anchor_date := as.Date(anchor_date)]; setorder(p5, realized_ym)
  .ED$P5 <- p5[, .(realized_ym, anchor_date, regime5=regime, beta_R05, m4, ret_orig_book=ret_orig)]
  bm <- as.data.table(read_parquet(BM_PIN_LOCAL)); bm[, Date := as.Date(Date)]
  bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date); .ED$BM_X <- xts(bm$BM_Ret, order.by=bm$Date)
  .ED$EPI <- fread(file.path(ED_ROOT,"stage_artifacts/pg2_defense_drawdown/episodes.csv"))
  .ED$ready <- TRUE
  cat(sprintf("[manual_ed_init] src=%s panel=%s rows=%d\n", src, panel_file, nrow(.ED$PANEL))); flush.console()
}

CUR  <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CAND <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","RE07_Crisis_Beta"), weights=NULL)

run_arm <- function(src){
  manual_ed_init(src)  # .ED$ready=TRUE => eval_defense early-returns past internal ed_init
  cat(sprintf("=== ARM %s: recon baseline (CUR) ===\n",src)); flush.console()
  r_base <- eval_defense(CUR,  label=paste0("recon_",src,"_base"))
  cat(sprintf("=== ARM %s: candidate (CAND RE07) ===\n",src)); flush.console()
  r_cand <- eval_defense(CAND, label=paste0("cand_",src,"_RE07"))
  list(base=r_base, cand=r_cand)
}

mm <- function(r){ data.table(SR=r$SR, MDD=abs(r$MDD), calmar=r$calmar, CAGR=r$CAGR,
                              PORT_t=r$PORT_t, IR=r$IR,
                              oos=r$oos_retention %||% NA_real_, n=r$n_periods) }
marg <- function(cand,base){ list(d_ir=cand$IR-base$IR, d_sr=cand$SR-base$SR,
                                  d_mdd=abs(cand$MDD)-abs(base$MDD),
                                  d_port_t=cand$PORT_t-base$PORT_t,
                                  d_calmar=cand$calmar-base$calmar) }

ic  <- run_arm("ic")
reg <- run_arm("regdir")

cat("\n############ IC (AUTHORITATIVE) ############\n")
cat("-- recon baseline (CUR):\n"); print(mm(ic$base))
cat("-- candidate (CAND):\n");     print(mm(ic$cand))
m_ic <- marg(ic$cand, ic$base)
cat(sprintf("[MARGINAL ic] d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f d_port_t=%+.4f d_calmar=%+.4f\n",
            m_ic$d_ir, m_ic$d_sr, m_ic$d_mdd, m_ic$d_port_t, m_ic$d_calmar))

cat("\n############ REGDIR (robustness x-check) ############\n")
cat("-- recon baseline (CUR):\n"); print(mm(reg$base))
cat("-- candidate (CAND):\n");     print(mm(reg$cand))
m_reg <- marg(reg$cand, reg$base)
cat(sprintf("[MARGINAL regdir] d_ir=%+.4f d_sr=%+.4f d_mdd=%+.4f d_port_t=%+.4f d_calmar=%+.4f\n",
            m_reg$d_ir, m_reg$d_sr, m_reg$d_mdd, m_reg$d_port_t, m_reg$d_calmar))

epc <- merge(ic$base$episodes[, .(episode, active_base=active)],
             ic$cand$episodes[, .(episode, active_cand=active)], by="episode")
epc[, d_active := active_cand - active_base]
cat("\n[EPISODES ic] base vs cand active (11 drawdown episodes):\n"); print(epc)

## mean episode active (candidate) for structured output
mean_epi_active_cand <- mean(ic$cand$episodes$active, na.rm=TRUE)

## ---- monthly return series (paired-t) — IC arm ------------------------------
mo_base <- ic$base$monthly[, .(realized_ym, anchor_date, ret_base=ret_noL4)]
mo_cand <- ic$cand$monthly[, .(realized_ym, anchor_date, ret_cand=ret_noL4)]
mo <- merge(mo_base, mo_cand, by=c("realized_ym","anchor_date"), all=TRUE); setorder(mo, realized_ym)
fwrite(mo, file.path(OUT,"c2_swap_RE07_monthly_ic.csv"))
mp2 <- mo[is.finite(ret_base) & is.finite(ret_cand)]; dvec <- mp2$ret_cand - mp2$ret_base
pt <- if (length(dvec)>2 && sd(dvec)>0) t.test(dvec) else NULL
paired_t <- if(!is.null(pt)) as.numeric(pt$statistic) else NA_real_
paired_p <- if(!is.null(pt)) as.numeric(pt$p.value) else NA_real_
cat(sprintf("\n[PAIRED-t ic] mean(cand-base)=%+.5f/mo t=%+.3f p=%.4f n=%d\n",
            mean(dvec), paired_t, paired_p, length(dvec)))

res <- list(
  candidate="c2_swap_RE07",
  spec=list(factors=CAND$factors, weighting="EW 1/3 each (theta_defense-matched)"),
  mechanism="Q25_Ohlson_O (drawdown-rank100 weakest) -> RE07_Crisis_Beta (episode hit100%)",
  authoritative_denominator="pinned_ic (convention-matched to deployed book IC-sign freeze)",
  pinned_caches=c("RAWDATA_pin20260703.parquet","benchmark_pin20260703.parquet"),
  candidate_ic=as.list(mm(ic$cand)),
  recon_baseline_ic=as.list(mm(ic$base)),
  marginal_vs_recon_ic=m_ic,
  d_ir_vs_recon=m_ic$d_ir, d_sr_vs_recon=m_ic$d_sr, d_mdd_vs_recon=m_ic$d_mdd,
  mean_episode_active_cand=mean_epi_active_cand,
  paired_t_monthly=paired_t, paired_p_monthly=paired_p, paired_n=length(dvec),
  candidate_regdir=as.list(mm(reg$cand)),
  recon_baseline_regdir=as.list(mm(reg$base)),
  marginal_vs_recon_regdir=m_reg,
  episodes_ic=epc,
  n_re07_sig_dates=257L)
write_json(res, file.path(OUT,"c2_swap_RE07_marginal.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6, na="null")
saveRDS(list(ic=ic, reg=reg, marginal_ic=m_ic, marginal_reg=m_reg,
             paired_t=paired_t, mean_epi_active_cand=mean_epi_active_cand),
        file.path(OUT,"c2_swap_RE07_result.rds"))
cat("\n[saved]", file.path(OUT,"c2_swap_RE07_marginal.json"),"\n")
cat("[saved]", file.path(OUT,"c2_swap_RE07_monthly_ic.csv"),"\n")
