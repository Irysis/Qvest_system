# Incumbent overlap v2 — CORRECT monthly alignment, deployed V4_R05 variant
suppressMessages({ library(data.table) })

# ---- CORE: aggregate daily net returns -> monthly ----
core_d <- fread("stage_artifacts/alpha_search/20260613_021015_217222/03_period_returns.csv")
core_d[, date := as.Date(date)]
core_d[, ym := format(date, "%Y-%m")]
core_m <- core_d[, .(core_total_net = prod(1+ret_net)-1), by=ym]  # compound daily->monthly (return aggregation, not perf metric)

# CORE benchmark daily -> monthly
core_bd <- fread("stage_artifacts/alpha_search/20260613_021015_217222/05_benchmark_returns.csv")
core_bd[, date := as.Date(date)]
core_bd[, ym := format(date,"%Y-%m")]
bm_m <- core_bd[, .(bm = prod(1+benchmark_ret)-1), by=ym]

core_m <- merge(core_m, bm_m, by="ym")
core_m[, core_active := core_total_net - bm]

# ---- INCUMBENT deployed: L5_V4_R05_adaptive ----
inc <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
inc[, date := as.Date(anchor_date)]
inc[, ym := format(date,"%Y-%m")]
incm <- inc[, .(ym, inc_total_net = ret_L5_V4)]
incm <- merge(incm, bm_m, by="ym")
incm[, inc_active := inc_total_net - bm]

# also baseline L4 precedent for reference
inc4 <- inc[, .(ym, inc_L4 = ret_L4_baseline)]

m <- merge(core_m[, .(ym, core_total_net, core_active, bm)],
           incm[, .(ym, inc_total_net, inc_active)], by="ym")
m <- merge(m, inc4, by="ym")
m <- m[!is.na(core_total_net) & !is.na(inc_total_net)]
m[, date := as.Date(paste0(ym,"-01"))]
setorder(m, date)
cat("[overlap2] common months:", nrow(m), " range:", min(m$ym),"->",max(m$ym),"\n")

ann <- function(r){ r<-r[!is.na(r)]; (prod(1+r))^(12/length(r))-1 }
srf <- function(r){ r<-r[!is.na(r)]; mean(r)/sd(r)*sqrt(12) }
cat(sprintf("[overlap2] CORE monthly: CAGR=%.3f SR=%.3f | INC(V4_R05): CAGR=%.3f SR=%.3f | BM CAGR=%.3f\n",
            ann(m$core_total_net), srf(m$core_total_net),
            ann(m$inc_total_net), srf(m$inc_total_net), ann(m$bm)))

cor_total_v4  <- cor(m$core_total_net, m$inc_total_net)
cor_active_v4 <- cor(m$core_active, m$inc_active)
cor_total_l4  <- cor(m$core_total_net, m$inc_L4)
cor_active_l4 <- cor(m$core_active, m$inc_L4 - m$bm)

m[, yr := as.integer(substr(ym,1,4))]
sp <- m[, .(n=.N,
            cor_active_v4=cor(core_active, inc_active),
            cor_total_v4=cor(core_total_net, inc_total_net)),
        by=.(period=fifelse(yr<=2013,"2005-2013",fifelse(yr<=2019,"2014-2019","2020-2026")))]
m[, idx:=.I]
roll <- if(nrow(m)>=36) sapply(36:nrow(m), function(i) cor(m$core_active[(i-35):i], m$inc_active[(i-35):i])) else NA

cat(sprintf("\n[overlap2] === DEPLOYED V4_R05 (incumbent) ===\n"))
cat(sprintf("  corr(total net)  = %.4f\n", cor_total_v4))
cat(sprintf("  corr(ACTIVE vs BM) = %.4f   <-- book-marginal relevant basis\n", cor_active_v4))
cat(sprintf("  rolling36m active: min=%.3f median=%.3f max=%.3f\n", min(roll),median(roll),max(roll)))
cat(sprintf("\n[overlap2] === L4 baseline precedent (reference) ===\n"))
cat(sprintf("  corr(total net)  = %.4f | corr(active) = %.4f\n", cor_total_l4, cor_active_l4))
cat("\n[overlap2] subperiod (vs V4_R05):\n"); print(sp)

saveRDS(list(
  deployed_variant="L5_V4_R05_adaptive",
  cor_total=cor_total_v4, cor_active=cor_active_v4,
  cor_total_l4=cor_total_l4, cor_active_l4=cor_active_l4,
  n=nrow(m), range=c(min(m$ym),max(m$ym)),
  roll_active=list(min=min(roll),median=median(roll),max=max(roll)),
  sp=sp,
  core_cagr=ann(m$core_total_net), core_sr=srf(m$core_total_net),
  inc_cagr=ann(m$inc_total_net), inc_sr=srf(m$inc_total_net)),
  "stage_artifacts/WT-D20260614_002/_overlap.rds")
cat("\n[overlap2] saved.\n")
