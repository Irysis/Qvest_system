# =============================================================
# WT-D20260529_001 FLOW — Orthogonality vs STR_1715 (core) + D (microstructure)
# cor measured on cross-sectional alpha scores at common (Date,Ticker)
# =============================================================
suppressMessages({library(data.table); library(arrow); library(lubridate)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
d <- readRDS(file.path(OUT,"diag_v2.rds"))
panel <- d$panel
flow <- panel[, .(Date, Ticker, alpha_flow)]
flow[, ym := format(Date,"%Y-%m")]

# STR_1715 score_eff
s <- as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
s[, Date:=as.Date(Date)]; s[, ym:=format(Date,"%Y-%m")]
s1715 <- s[, .(ym, Ticker, a1715=score_eff)]

# D ML pred (30f winner)
dml <- as.data.table(read_parquet("stage_artifacts/WT_D20260528_003_D_PROD/alpha_scores_30f.parquet"))
dml[, Date:=as.Date(Date)]; dml[, ym:=format(Date,"%Y-%m")]
dD <- dml[, .(ym, Ticker, aD=pred)]

# merge on ym+Ticker (cross-section)
m1 <- merge(flow, s1715, by=c("ym","Ticker"))
m2 <- merge(flow, dD,    by=c("ym","Ticker"))

# cross-sectional cor per month then average (rank + pearson)
cs_cor <- function(dt, a, b, method){
  r <- dt[, .(c=if(.N>=10) cor(get(a),get(b),method=method) else NA_real_), by=ym][!is.na(c)]
  list(mean=mean(r$c), n=nrow(r), series=r)
}
c1_p <- cs_cor(m1,"alpha_flow","a1715","pearson")
c1_s <- cs_cor(m1,"alpha_flow","a1715","spearman")
c2_p <- cs_cor(m2,"alpha_flow","aD","pearson")
c2_s <- cs_cor(m2,"alpha_flow","aD","spearman")

# pooled (all obs) cor as cross-check
pool1 <- cor(m1$alpha_flow, m1$a1715, method="spearman")
pool2 <- cor(m2$alpha_flow, m2$aD,    method="spearman")

cat("=== ORTHOGONALITY ===\n")
cat(sprintf("FLOW vs STR_1715 (score_eff): mean monthly Pearson=%.3f Spearman=%.3f (n_months=%d, pooled-spearman=%.3f, common obs=%d)\n",
  c1_p$mean, c1_s$mean, c1_s$n, pool1, nrow(m1)))
cat(sprintf("FLOW vs D (ML pred 30f):      mean monthly Pearson=%.3f Spearman=%.3f (n_months=%d, pooled-spearman=%.3f, common obs=%d)\n",
  c2_p$mean, c2_s$mean, c2_s$n, pool2, nrow(m2)))
cat(sprintf("\nBoth |cor| < 0.30 target: STR_1715=%s  D=%s\n",
  abs(c1_s$mean)<0.30, abs(c2_s$mean)<0.30))

saveRDS(list(c1_p=c1_p$mean,c1_s=c1_s$mean,c2_p=c2_p$mean,c2_s=c2_s$mean,
  pool1=pool1,pool2=pool2,n1=c1_s$n,n2=c2_s$n,obs1=nrow(m1),obs2=nrow(m2)),
  file.path(OUT,"ortho.rds"))
