# finalize — alpha_vector(latest), subperiod IC, placebo/lag1 self-adversarial, emit artifacts + draft package
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-D20260710_001")
WT <- file.path(ROOT,"qepm","mailbox","worktask","WT-D20260710_001"); dir.create(WT, showWarnings=FALSE, recursive=TRUE)
source(file.path(ROOT,"02_Infrastructure","contracts","canonical_screen_bt.R"))
panel <- readRDS(file.path(SA,"panel.rds")); res <- readRDS(file.path(SA,"screen_result.rds"))
selected_axes <- res$selected_axes; isw <- res$isw; sel <- res$sel
tier_mult <- c(MEGA=0.25, MID=1.0, OTHER=0.5)

# ---- C3 composite score (selected): ISw within-tier z * MID emphasis ----
zt <- paste0("zt_",selected_axes); W <- isw/sum(isw)
panel[, comp_score := as.numeric(as.matrix(.SD) %*% W) * tier_mult[tier], .SDcols=zt]
scp <- panel[!is.na(comp_score)]

# ---- subperiod rank-IC (advisory) ----
sub_ic <- function(dt, lo, hi){
  d <- dt[Date>=as.Date(lo) & Date<as.Date(hi) & !is.na(Ret_1m)]
  ics <- d[, {if(.N>=8) .(ic=cor(comp_score,Ret_1m,method="spearman")) else .(ic=NA_real_)}, by=Date]$ic
  mean(ics, na.rm=TRUE)
}
sp1 <- sub_ic(scp,"2004-01-01","2015-01-01"); sp2 <- sub_ic(scp,"2015-01-01","2020-01-01")
sp3 <- sub_ic(scp,"2020-01-01","2027-01-01"); sp17 <- sub_ic(scp,"2017-01-01","2027-01-01")
subperiod_stability <- min(sp1,sp2,sp3)/max(sp1,sp2,sp3)

# ---- placebo: shuffle score within date -> IC ~ 0 ----
scp[, shuf := sample(comp_score), by=Date]
plac_ic <- mean(scp[!is.na(Ret_1m), {if(.N>=8) .(ic=cor(shuf,Ret_1m,method="spearman")) else .(ic=NA_real_)}, by=Date]$ic, na.rm=TRUE)

# ---- lag1 PIT stress: score(t-1) vs Ret_1m(t) should degrade (not improve) ----
setorder(scp, Ticker, Date)
scp[, comp_lag1 := shift(comp_score,1L), by=Ticker]
lag1_ic <- mean(scp[!is.na(Ret_1m)&!is.na(comp_lag1), {if(.N>=8) .(ic=cor(comp_lag1,Ret_1m,method="spearman")) else .(ic=NA_real_)}, by=Date]$ic, na.rm=TRUE)
real_ic <- res$rank_ic

# ---- canonical pvalue for C3 (from screen fin) ----
fin <- res$fin
capw_pval <- fin$portfolio_alpha_t_pvalue

# ---- alpha_vector at latest signal date ----
last_d <- max(panel$Date)
latest <- panel[Date==last_d & !is.na(comp_score)]
latest[, z := (comp_score-mean(comp_score))/sd(comp_score)]
latest[, alpha_hat := round(0.008*z, 5)]              # scaled expected active (monthly)
latest[, conf := round(pmin(0.9, pmax(0.3, 0.5 + 0.1*abs(z))),2)]
setorder(latest, -alpha_hat)
alpha_vector <- setNames(as.list(latest$alpha_hat), latest$Ticker)
confidence_vector <- setNames(as.list(latest$conf), latest$Ticker)
cat("[alpha_vector] date=", as.character(last_d), " n=", nrow(latest),
    " top5=", paste(head(latest$Ticker,5),collapse=","), "\n")

# ---- alpha_scores.parquet (full panel: composite score + tier + Ret_1m for downstream) ----
out_scores <- panel[!is.na(comp_score), .(Date, Ticker, alpha_hat=comp_score, tier, size_rank, score_eff, Ret_1m)]
write_parquet(out_scores, file.path(SA,"alpha_scores.parquet"))
cat("[saved] alpha_scores.parquet rows=", nrow(out_scores), "\n")

cat(sprintf("\nsubperiod IC: 2004-15=%.4f 2015-20=%.4f 2020-26=%.4f post2017=%.4f stability=%.3f\n",
            sp1,sp2,sp3,sp17,subperiod_stability))
cat(sprintf("placebo IC=%.4f (null OK if ~0) | lag1 IC=%.4f vs real IC=%.4f (PIT graceful if lag1<real)\n",
            plac_ic, lag1_ic, real_ic))
cat(sprintf("canonical cap-w PORT_t=%.4f pval=%.4f | post2017 cap-w t=%.4f\n",
            fin$portfolio_alpha_t_nw_lag3, capw_pval, res$post2017_capw_t))

# ---- stash finalize numbers for package writer ----
saveRDS(list(alpha_vector=alpha_vector, confidence_vector=confidence_vector, last_d=as.character(last_d),
             sp1=sp1,sp2=sp2,sp3=sp3,sp17=sp17, subperiod_stability=subperiod_stability,
             plac_ic=plac_ic, lag1_ic=lag1_ic, real_ic=real_ic, capw_pval=capw_pval,
             n_latest=nrow(latest)),
        file.path(SA,"finalize_stash.rds"))
cat("[saved] finalize_stash.rds\n")
