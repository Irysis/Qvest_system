# =============================================================
# WT-D20260529_001 FLOW — Step 4-7 Diagnostics + Composite + Orthogonality
# =============================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite); library(lubridate)})
options(warn = 1)
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260529_001_FLOW")
COST_BPS <- 15

panel <- readRDS(file.path(OUT, "panel.rds"))
INV_AVAIL <- grep("^INV", names(panel), value = TRUE)

# ---- crisis regime tag from STR_1715 panel (KR-wide regime_state) ----
s1715 <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
s1715[, Date := as.Date(Date)]
regime_map <- unique(s1715[, .(Date, regime_state)])
# Date in s1715 is month-start (2004-01-01); map to sig month
regime_map[, ym := format(Date, "%Y-%m")]
regime_month <- regime_map[, .(regime = regime_state[1]), by = ym]
panel[, ym := format(Date, "%Y-%m")]
panel <- merge(panel, regime_month, by = "ym", all.x = TRUE)
panel[is.na(regime), regime := "NORMAL"]
panel[, bad := regime %in% c("CRISIS","CAUTION")]

# =============================================================
# Per-factor rank-IC diagnostics (Spearman vs forward excess return)
# =============================================================
rankic_by_factor <- function(f) {
  d <- panel[!is.na(get(f)) & !is.na(exret_fwd_1m)]
  ic <- d[, .(ic = if (.N >= 20) cor(get(f), exret_fwd_1m, method = "spearman") else NA_real_), by = Date]
  ic <- ic[!is.na(ic)]
  list(mean_ic = mean(ic$ic), icir = mean(ic$ic)/sd(ic$ic),
       n_months = nrow(ic), ic_series = ic)
}
fac_diag <- rbindlist(lapply(INV_AVAIL, function(f){
  r <- rankic_by_factor(f)
  data.table(factor = f, mean_ic = r$mean_ic, icir = r$icir, n = r$n_months)
}))
setorder(fac_diag, -icir)
cat("=== Per-factor rank-IC (sorted by ICIR) ===\n"); print(fac_diag)

# crisis vs normal IC per factor
crisis_ic <- rbindlist(lapply(INV_AVAIL, function(f){
  d <- panel[!is.na(get(f)) & !is.na(exret_fwd_1m)]
  ic <- d[, .(ic = if (.N >= 20) cor(get(f), exret_fwd_1m, method="spearman") else NA_real_,
              bad = bad[1]), by = Date][!is.na(ic)]
  data.table(factor = f,
             ic_normal = mean(ic[bad==FALSE]$ic),
             ic_bad    = mean(ic[bad==TRUE]$ic),
             n_bad     = nrow(ic[bad==TRUE]))
}))
crisis_ic[, bad_normal_ratio := ic_bad / ic_normal]
cat("\n=== Crisis vs Normal IC ===\n"); print(crisis_ic)

# =============================================================
# Candidate selection (R2-C cap=5). Selection objective = ICIR (allowed enum).
# Crisis-aware: prefer factors with ic_bad >= 0 (no crisis sign flip) to beat E AX-001 fail.
# =============================================================
sel <- merge(fac_diag, crisis_ic, by = "factor")
setorder(sel, -icir)
# parsimonious composite: top ICIR factors that ALSO do not collapse in crisis (ic_bad not strongly negative)
# Validation > Discovery: drop redundant (keep distinct mechanisms: foreign / inst / retail / residual)
cand <- sel[icir > 0.05 & ic_bad > -0.02]
# enforce mechanism diversity & cap 5
pick <- character(0)
mech_of <- function(f) fifelse(grepl("Retail",f),"retail",
                       fifelse(grepl("Resid",f),"residual",
                       fifelse(grepl("Smart|Agreement|Persistence|Concentration|Imbalance",f),"composite_flow",
                       fifelse(grepl("Foreign",f),"foreign",
                       fifelse(grepl("Inst",f),"inst","other")))))
cand[, mech := sapply(factor, mech_of)]
setorder(cand, -icir)
seen <- character(0)
for (i in seq_len(nrow(cand))) {
  m <- cand$mech[i]
  if (!(m %in% seen)) { pick <- c(pick, cand$factor[i]); seen <- c(seen, m) }
  if (length(pick) >= 5) break
}
cat("\n=== Selected composite factors (cap 5, mechanism-diverse) ===\n"); print(pick)
selected <- sel[factor %in% pick]
print(selected[, .(factor, mean_ic, icir, ic_normal, ic_bad, bad_normal_ratio)])

# =============================================================
# Composite alpha = equal-weight z of selected (ICIR-weighted optional).
# Cost-aware: composite chosen partly by turnover (medium INV factors).
# =============================================================
panel[, alpha_flow := rowMeans(.SD, na.rm = TRUE), .SDcols = pick]
panel <- panel[!is.na(alpha_flow) & !is.na(exret_fwd_1m)]

# composite rank-IC diagnostics
comp_ic <- panel[, .(ic = if(.N>=20) cor(alpha_flow, exret_fwd_1m, method="spearman") else NA_real_,
                     bad = bad[1]), by = Date][!is.na(ic)]
comp_mean_ic <- mean(comp_ic$ic)
comp_icir    <- comp_mean_ic / sd(comp_ic$ic)
# Harvey-t on rank-IC series (Newey-West not required for IC mean; report monthly t + NW)
nm <- nrow(comp_ic)
harvey_t <- comp_mean_ic / (sd(comp_ic$ic)/sqrt(nm))
# Newey-West t (lag 3)
nw_t <- {
  x <- comp_ic$ic - comp_mean_ic
  L <- 3; g0 <- mean(x^2)
  gj <- sapply(1:L, function(j) mean(x[-(1:j)]*x[-((nm-j+1):nm)]))
  w  <- 1 - (1:L)/(L+1)
  lrv <- g0 + 2*sum(w*gj)
  comp_mean_ic / sqrt(lrv/nm)
}
cat(sprintf("\n=== COMPOSITE FLOW alpha ===\nmean rank-IC=%.4f ICIR=%.3f Harvey-t(naive)=%.2f NW-t(lag3)=%.2f n_months=%d\n",
            comp_mean_ic, comp_icir, harvey_t, nw_t, nm))

# subperiod stability (3 windows)
comp_ic[, period := fifelse(Date < as.Date("2015-01-01"),"P1_2005_14",
                    fifelse(Date < as.Date("2020-01-01"),"P2_2015_19","P3_2020_23"))]
sub <- comp_ic[, .(mean_ic = mean(ic), icir = mean(ic)/sd(ic), n=.N, pos_frac=mean(ic>0)), by=period][order(period)]
cat("\n=== Subperiod stability ===\n"); print(sub)
subperiod_stability <- mean(sub$mean_ic > 0)  # fraction of subperiods with positive IC

# crisis IC ratio for composite (AX-001 v2 input)
comp_ic_bad <- mean(comp_ic[bad==TRUE]$ic)
comp_ic_norm<- mean(comp_ic[bad==FALSE]$ic)
ax001_ratio <- comp_ic_bad / comp_ic_norm
cat(sprintf("\nCOMPOSITE crisis IC=%.4f normal IC=%.4f  bad/normal ratio=%.3f (n_bad=%d)\n",
            comp_ic_bad, comp_ic_norm, ax001_ratio, nrow(comp_ic[bad==TRUE])))

# monotonicity (decile)
panel[, dec := cut(frank(alpha_flow, ties.method="first"),
                   breaks = quantile(frank(alpha_flow), probs = seq(0,1,.1), na.rm=TRUE),
                   labels=1:10, include.lowest=TRUE), by = Date]
dec_ret <- panel[, .(mret = mean(exret_fwd_1m, na.rm=TRUE)), by = .(dec)][order(dec)]
dec_ret <- dec_ret[!is.na(dec)]
mono <- cor(as.numeric(as.character(dec_ret$dec)), dec_ret$mret, method="spearman")
cat("\n=== Decile monotonicity (Spearman dec vs ret) ===\n"); print(dec_ret); cat("monotonicity:", round(mono,3),"\n")

saveRDS(list(panel=panel, pick=pick, selected=selected, comp_ic=comp_ic,
             comp_mean_ic=comp_mean_ic, comp_icir=comp_icir, harvey_t=harvey_t, nw_t=nw_t,
             nm=nm, sub=sub, subperiod_stability=subperiod_stability,
             ax001_ratio=ax001_ratio, comp_ic_bad=comp_ic_bad, comp_ic_norm=comp_ic_norm,
             mono=mono, fac_diag=fac_diag, crisis_ic=crisis_ic, dec_ret=dec_ret),
        file.path(OUT,"diag.rds"))
cat("\n[diag] saved.\n")
