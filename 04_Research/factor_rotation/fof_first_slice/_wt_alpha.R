# _wt_alpha.R — WT-D20260705_001 alpha-vector construction (as-of latest signal month).
# alpha_i = expected 1M ACTIVE return, calibrated from realized cross-sectional IC and score dispersion,
# then UNCERTAINTY-SHRUNK (research_philosophy iii: mu_tilde = mu_hat - k*SE). Long-only universe: canonical.
# Also emits alpha_scores.parquet (full history) + confidence_vector.
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(file.path(R,"04_Research/factor_rotation/fof_first_slice"))
MODE <- "canonical"  # deployment universe = K200 u KQ150
me <- function(ym){ d<-as.Date(paste0(ym,"-01")); as.Date(format(d+32,"%Y-%m-01"))-1 }

M <- as.data.table(read_parquet("kns_master_panel.parquet",
       col_select=c("ym","Ticker","F1","adv","K200f","KQ150f","bad","nret")))
M[, Date := me(ym)]
Mc <- M[(K200f|KQ150f)]
ens <- read_parquet(sprintf("scores_XATTN_%s_ENS.parquet", MODE)) |> as.data.table()
ens[, Date := as.Date(Date)]

# --- realized IC scale: regress F1 on cross-sectional z(score) per month, average slope (bps per 1 sd score) ---
D <- merge(ens[,.(Date,Ticker,score)], Mc[,.(Date,Ticker,F1,adv)], by=c("Date","Ticker"))
D <- D[!is.na(F1) & !is.na(score)]
D[, zscore := (score-mean(score))/sd(score), by=Date]
# active return = F1 - cross-sec mean F1 (universe EW proxy for active), per month
D[, F1_active := F1 - mean(F1), by=Date]
# per-month slope beta_t: F1_active ~ zscore (no intercept since both demeaned)
slopes <- D[, .(beta = sum(zscore*F1_active)/sum(zscore^2), n=.N), by=Date]
beta_mean <- mean(slopes$beta); beta_sd <- sd(slopes$beta); nS <- nrow(slopes)
beta_se <- beta_sd/sqrt(nS)
cat(sprintf("[alpha] per-month active slope beta: mean=%.4f sd=%.4f SE=%.5f n=%d (t=%.2f)\n",
            beta_mean, beta_sd, beta_se, nS, beta_mean/beta_se))
# uncertainty shrinkage: use lower-bound slope beta_lb = max(0, beta_mean - k*beta_se), k=1
k_shrink <- 1.0
beta_lb <- max(0, beta_mean - k_shrink*beta_se)

# --- alpha_scores full history: alpha_active_hat = beta_lb * zscore ---
D[, alpha_active_hat := beta_lb * zscore]
# confidence: monotone in |zscore| capped, scaled by data availability + rank stability proxy
# rank stability: |zscore| high & consistent sign is more confident; simple map to [0,1]
D[, confidence := pmin(1, pmax(0.1, 0.4 + 0.3*pmin(2,abs(zscore))/2 + 0.3*(adv>=1e9))) ]
alpha_scores <- D[, .(Date, Ticker, score, zscore, alpha_active_hat, confidence, F1_active_realized=F1_active)]
write_parquet(alpha_scores, "../../../stage_artifacts/WT-D20260705_001/alpha_scores.parquet")

# --- as-of latest month alpha_vector + confidence_vector ---
latest <- max(D$Date)
Dl <- D[Date==latest]
setorder(Dl, -alpha_active_hat)
cat(sprintf("[alpha] as-of %s  N=%d  top score->alpha: %.4f  median: %.4f\n",
            as.character(latest), nrow(Dl), max(Dl$alpha_active_hat), median(Dl$alpha_active_hat)))
alpha_vector <- setNames(round(Dl$alpha_active_hat,5), Dl$Ticker)
confidence_vector <- setNames(round(Dl$confidence,3), Dl$Ticker)
cat("[alpha] top 10 (Ticker : alpha_active_hat : conf):\n")
print(head(Dl[,.(Ticker, alpha=round(alpha_active_hat,4), conf=round(confidence,2), adv=round(adv/1e8,1))],10))

saveRDS(list(beta_mean=beta_mean, beta_sd=beta_sd, beta_se=beta_se, beta_lb=beta_lb,
             k_shrink=k_shrink, latest=as.character(latest),
             alpha_vector=alpha_vector, confidence_vector=confidence_vector,
             n_names=nrow(Dl)), "_wt_alpha.rds")
cat("[alpha] DONE -> _wt_alpha.rds + alpha_scores.parquet\n")
