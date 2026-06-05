#!/usr/bin/env Rscript
# META-COND alpha-selector cheap SCREEN (regime-conditional family IC)
# READ-ONLY, advisory only (Cycle2 lesson). No backtest, no admission.
#
# Idea: gate which factor *family* to turn on as a function of the 3-state regime.
# Selector-relevant payoff = monthly cross-sectional IC of each factor (sign-aligned
# in the IC build, so +IC = signal works as intended, -IC = signal inverts).
# Family payoff = mean member-factor IC that month. Condition on regime state
# (regime_v7 apply_month = PIT-applied / lagged decision basis).
#
# GO (selector worthwhile) if >=3 families show statistically significant SIGN
# DIVERGENCE: a state with significantly +mean-IC AND a state with significantly
# -mean-IC (|t|>=1.5, n>=12). Sign-flip is what makes a *family on/off selector*
# orthogonal to a magnitude-only regime-beta overlay (AR_on_M4) or a fixed
# family-mix ML (D ML). Pure magnitude variation does NOT qualify.
#
# Substrate (all PIT-correct, on disk):
#   .cache/factor_db/factor_ic_monthly.parquet : Factor_Name,IC,N_Stocks,Date,Usable_Date
#         (62885 rows, 269 factors, 2005-01..2026-02, IC NA=0; C14 Usable_Date>=Date)
#   .cache/regime_v7.parquet : apply_month, regime_state{Crisis/Normal/Transition_LR}
#   02_Infrastructure/factor_db/factor_registry.json : economic_family per factor

suppressMessages({ library(data.table); library(arrow); library(jsonlite) })

OUT <- "stage_artifacts/WT_CREATIVE_SCREEN2/META_COND"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
LOG <- file.path(OUT, "run.log"); cat("", file = LOG)
lg <- function(...) cat(sprintf(...), "\n", file = LOG, append = TRUE)
lg("START %s", as.character(Sys.time()))

LOCKBOX <- as.Date("2023-12-22")

## ---- 1. Family map -------------------------------------------------------
rj <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
fam_map <- rbindlist(lapply(names(rj), function(k){
  v <- rj[[k]]; fam <- v$labels$economic_family; if (is.null(fam)) fam <- v$category
  data.table(Factor_Name = k, family = if (is.null(fam)) NA_character_ else as.character(fam))
}), fill = TRUE)
fam_map <- fam_map[!is.na(family)]

## ---- 2. Monthly IC (selector payoff) -------------------------------------
ic <- as.data.table(read_parquet(".cache/factor_db/factor_ic_monthly.parquet"))
ic[, Date := as.Date(Date)]
ic <- ic[Date <= LOCKBOX]                                  # lockbox strict
ic <- merge(ic, fam_map, by="Factor_Name", all.x=TRUE)
n_unmapped <- ic[is.na(family), uniqueN(Factor_Name)]
ic <- ic[!is.na(family)]
ic[, ym := format(Date, "%Y%m")]
lg("ic rows(<=lockbox,mapped)=%d months=%d factors=%d unmapped_factors=%d",
   nrow(ic), uniqueN(ic$ym), uniqueN(ic$Factor_Name), n_unmapped)

# family monthly payoff = mean member-factor IC
fam_ic <- ic[, .(fam_ic = mean(IC, na.rm=TRUE), n_factors = .N), by=.(ym, family)]

## ---- 3. Regime monthly 3-state (PIT apply_month) -------------------------
v7 <- as.data.table(read_parquet(".cache/regime_v7.parquet"))
# apply_month is a "YYYY-MM" string (PIT-applied month); normalize to "YYYYMM" key.
v7[, ym := gsub("-", "", as.character(apply_month))]
lg("apply_month sample: %s", paste(head(unique(v7$apply_month), 5), collapse=","))
reg_m <- v7[!is.na(regime_state) & nchar(ym)==6, .(ym, state = as.character(regime_state))]
reg_m <- unique(reg_m, by="ym")
lg("regime states (apply_month): %s",
   paste(capture.output(print(table(reg_m$state))), collapse=" | "))

fam_ic <- merge(fam_ic, reg_m, by="ym")
fwrite(fam_ic, file.path(OUT, "monthly_family_ic.csv"))
lg("merged fam_ic obs=%d families=%d months=%d state dist: %s",
   nrow(fam_ic), uniqueN(fam_ic$family), uniqueN(fam_ic$ym),
   paste(capture.output(print(table(unique(fam_ic[,.(ym,state)])$state))), collapse=" | "))

## ---- 4. Conditional mean IC + t per (family, state) ----------------------
cond <- fam_ic[, .(mean_ic = mean(fam_ic, na.rm=TRUE),
                   sd = sd(fam_ic, na.rm=TRUE),
                   n  = .N,
                   t  = mean(fam_ic, na.rm=TRUE) /
                        (sd(fam_ic, na.rm=TRUE)/sqrt(.N))),
               by=.(family, state)]
setorder(cond, family, state)
fwrite(cond, file.path(OUT, "conditional_ic_by_state.csv"))

## ---- 5. Sign-divergence test (GO criterion) ------------------------------
div <- cond[n >= 12]
ds <- div[, {
  pos <- any(mean_ic > 0 & t >=  1.5, na.rm=TRUE)
  neg <- any(mean_ic < 0 & t <= -1.5, na.rm=TRUE)
  .(has_pos_sig=pos, has_neg_sig=neg, sign_divergent=pos&neg,
    states_eval=.N, max_abs_t=max(abs(t),na.rm=TRUE),
    ic_range=max(mean_ic,na.rm=TRUE)-min(mean_ic,na.rm=TRUE),
    min_ic=min(mean_ic,na.rm=TRUE), max_ic=max(mean_ic,na.rm=TRUE))
}, by=family]
setorder(ds, -sign_divergent, -max_abs_t)
fwrite(ds, file.path(OUT, "divergence_summary.csv"))
n_div <- sum(ds$sign_divergent, na.rm=TRUE)

# Softer secondary: families whose conditional IC *crosses zero* across states by
# an economically meaningful margin even if not both significant (selector hint).
crosses_zero <- ds[min_ic < -0.01 & max_ic > 0.01]$family

go <- n_div >= 3

res <- list(
  status="computed",
  test_type="regime-conditional-spread (family conditional IC)",
  scope="cheap_screen_advisory_only",
  pit=list(regime="regime_v7 apply_month (PIT-applied, lagged)",
           lockbox=as.character(LOCKBOX),
           ic_source="factor_ic_monthly (C14 Usable_Date>=Date, sign-aligned IC)",
           load="cache parquet (C15)"),
  regime_states=sort(unique(fam_ic$state)),
  n_months_overlap=uniqueN(fam_ic$ym),
  month_range=c(min(fam_ic$ym), max(fam_ic$ym)),
  n_families_evaluated=uniqueN(div$family),
  families_evaluated=sort(unique(div$family)),
  n_sign_divergent=n_div,
  families_sign_divergent=ds[sign_divergent==TRUE]$family,
  families_cross_zero_ge1pct=crosses_zero,
  go_threshold=">=3 sign-divergent families (|t|>=1.5, n>=12)",
  decision=ifelse(go,"GO (advisory) -> recommend canonical META-COND selector research",
                     "NO-GO (advisory)"),
  caveat="screen/advisory only, NOT tradeable (Cycle2). IC sign-flip across regimes is the selector premise; magnitude-only variation is already captured by regime-beta overlays and does not qualify. If GO, canonical step must re-test under long-only top20 production constraints."
)
writeLines(toJSON(res, auto_unbox=TRUE, pretty=TRUE), file.path(OUT, "screen_result.json"))
lg("DONE n_sign_divergent=%d cross_zero=%d go=%s", n_div, length(crosses_zero), go)
cat(sprintf("SCREEN_DONE n_div=%d cross_zero=%d go=%s\n", n_div, length(crosses_zero), go))
