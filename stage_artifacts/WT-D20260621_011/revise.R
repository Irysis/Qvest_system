# WT-D20260621_011 — Codex REVISE response: full panel scores, sector-neutral sens, decile-liq, lineage
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
arrow::set_cpu_count(1L); setDTthreads(1L); set.seed(20260621)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260621_011")
MBX  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260621_011")
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
nw_t <- function(x, lag=3){ x<-x[is.finite(x)]; n<-length(x); if(n<6) return(NA_real_)
  m<-mean(x); e<-x-m; v<-sum(e^2)/n; for(l in 1:lag){w<-1-l/(lag+1); v<-v+2*w*sum(e[(l+1):n]*e[1:(n-l)])/n}; m/sqrt(v/n)}

X<-readRDS(file.path(OUT,"scored.rds")); S<-X$S; best<-X$best
returns_dt<-X$returns_dt; bench_dt<-X$bench_dt; liq_dt<-X$liq_dt; build_scores<-X$build_scores

# --- FIX C1/RF-A7: full multi-date Date x Ticker x score panel ---
sc <- build_scores(S, best$A_lag, best$A_max, best$tau, best$lambda); setkey(sc,NULL)
sc <- sc[Date>=as.Date("2005-01-01")]
cat("full panel scores: n_dates=",length(unique(sc$Date))," rows=",nrow(sc),
    " score range=[",round(min(sc$score),4),",",round(max(sc$score),4),"]\n")
cat("negative score rows:", sum(sc$score<0)," (",round(100*mean(sc$score<0),2),"%)\n")
write_parquet(sc, file.path(OUT,"alpha_scores.parquet"))   # OVERWRITE with full panel

# --- FIX C5/RF-A4/A5: sector-neutral sensitivity + top-decile liquidity ---
# sector-neutral: within-month demean score by Sector, rerun canonical top-25
S[, Date := as.Date(paste0(ymk,"-01"))]
scS <- merge(sc, unique(S[,.(Date,Ticker,Sector)]), by=c("Date","Ticker"), all.x=TRUE)
scS[is.na(Sector), Sector:="UNK"]
scS[, score_sn := score - mean(score), by=.(Date,Sector)]
sn_bt <- canonical_screen_bt(scS[,.(Date,Ticker,score=score_sn)], returns_dt, bench_dt,
                             top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8)
cat("\nsector-neutral score: pt_nw=",round(sn_bt$portfolio_alpha_t_nw_lag3,3),
    " net_sr=",round(sn_bt$net_sr,3),"\n")

# top-decile liquidity: of the names actually held (top-25 by score each month), what % illiquid?
setorder(sc, Date, -score)
held <- sc[, {n<-min(25,.N); .(Ticker=Ticker[seq_len(n)])}, by="Date"]
held <- merge(held, liq_dt[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
illiq_frac <- mean(held$adv < 2e8, na.rm=TRUE)
cat("held top-25 illiquid(<2e8) fraction:", round(illiq_frac,3)," (RF-A5 threshold 0.5)\n")

# recent-3Y vs overall (RF-A3): compare net_sr recent 36m vs full
recent_bt <- canonical_screen_bt(sc[Date>=as.Date("2023-06-01")], returns_dt, bench_dt,
                                 top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8)
cat("recent-36m pt_nw=",round(recent_bt$portfolio_alpha_t_nw_lag3,3)," net_sr=",round(recent_bt$net_sr,3),
    " (RF-A3: recent should NOT >> overall; here also negative)\n")

# monotonicity Spearman of decile term-structure (reload analysis)
A<-readRDS(file.path(OUT,"analysis.rds")); dec<-A$dec_ts
mono <- cor(dec$dec, dec$mean_active, method="spearman")
cat("decile monotonicity (Spearman rank corr dec vs mean_active):", round(mono,3),"\n")

saveRDS(list(sn_pt=sn_bt$portfolio_alpha_t_nw_lag3, sn_sr=sn_bt$net_sr,
             illiq_frac=illiq_frac, recent_pt=recent_bt$portfolio_alpha_t_nw_lag3,
             recent_sr=recent_bt$net_sr, monotonicity=mono,
             n_score_dates=length(unique(sc$Date)), neg_frac=mean(sc$score<0)),
        file.path(OUT,"revise_metrics.rds"))
cat("\nDONE revise.R\n")
