# =============================================================================
# FQ-057 run_04: Phase C — cap_tier_decomposition mandatory field, first real
# implementation (risk_research_init.md section v83_dual_basis_captier schema).
# Book: STR_1715_on_M4_R05_noLayer4_PG2 (production holdings 2026-07-01,
#       read-only). Sigma = lw_nls (Phase B estimation-quality winner) on
#       60m window ending 202606 (pinned panel).
# All numbers: metric_type = estimation_quality_diagnostic (risk decomposition
# diagnostic). No alpha claim, no weight proposal.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq057_captier_sigma/estimators.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
pin_tag <- fromJSON(file.path(OUT_DIR, "fq057_pin_tag.json"))$pin_tag

mr <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
sn <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
yms <- sort(unique(mr$ym))
AS_OF <- max(yms)          # 202606 (last complete month)
cat("[phasec] as_of ym:", AS_OF, "\n")

# ---- universe + tiers at AS_OF ----------------------------------------------
memb <- sn[ym == AS_OF & member == 1L & !is.na(size), .(Ticker, size)]
win <- tail(yms[yms <= AS_OF], 60)
sub <- mr[ym %in% win & Ticker %in% memb$Ticker]
full <- sub[, .N, by = Ticker][N == 60, Ticker]
Wc <- dcast(sub[Ticker %in% full], ym ~ Ticker, value.var = "ret_m")
Rm <- as.matrix(Wc[, -1]); rownames(Rm) <- Wc$ym
uni <- colnames(Rm)
sz <- memb[match(uni, Ticker), size]
rk <- frank(-sz, ties.method = "first")
tier <- fifelse(rk <= 30, "MEGA", fifelse(rk <= 150, "MID", "SMALL"))
names(tier) <- uni
cat("[phasec] universe p =", length(uni), " tiers:",
    paste(names(table(tier)), table(tier), collapse = " "), "\n")

# ---- Sigma (lw_nls, Phase B winner) -----------------------------------------
Sig <- est_lw_nls(Rm)
cat("[phasec] Sigma cond:", round(cond_number(Sig), 1), "\n")

# ---- book weights (production holdings, read-only) --------------------------
H <- fread(file.path(ROOT, paste0("05_Production/2.Factor_Model/",
      "2-3.STR_1715_on_M4_R05_noLayer4_PG2/02_holdings_universe/",
      "20260701_noLayer4_weights_cap_0p20.csv")))
Heq <- H[Ticker != "CASH"]
cash_w <- H[Ticker == "CASH", Weight]
cat("[phasec] equity names:", nrow(Heq), " cash:", cash_w,
    " sum equity w:", sum(Heq$Weight), "\n")
in_uni <- Heq$Ticker %in% uni
cat("[phasec] holdings in Sigma universe:", sum(in_uni), "/", nrow(Heq),
    if (any(!in_uni)) paste(" missing:", paste(Heq$Ticker[!in_uni], collapse = ",")) else "", "\n")

w_book <- setNames(rep(0, length(uni)), uni)
w_book[Heq$Ticker[in_uni]] <- Heq$Weight[in_uni]

# ---- benchmark weights: cap-w and EW-uni ------------------------------------
w_capw <- setNames(sz / sum(sz), uni)
w_ew   <- setNames(rep(1 / length(uni), length(uni)), uni)

tier_shares <- function(w_active, Sig, tier) {
  m <- as.numeric(Sig %*% w_active)
  tv <- sum(w_active * m)
  rc <- w_active * m
  sh <- tapply(rc, tier, sum) / tv
  list(shares = sh, active_var = tv,
       active_vol_ann = sqrt(pmax(tv, 0)) * sqrt(12))
}
res_capw <- tier_shares(w_book - w_capw, Sig, tier)
res_ew   <- tier_shares(w_book - w_ew,   Sig, tier)
# secondary: equity-sleeve renormalized (isolates selection structure from the
# 70% cash CRISIS de-risk)
res_capw_sleeve <- tier_shares(w_book / sum(w_book) - w_capw, Sig, tier)

# ---- alpha allocation share per tier ----------------------------------------
# Basis: book equity weights are LinearTilt alpha-proportional -> weight share
# = alpha allocation share (labeled; NOT a realized-alpha measurement).
alpha_sh <- tapply(w_book, tier, sum) / sum(w_book)

# ---- signal_alive diagnostic per tier ---------------------------------------
# Basis: trailing 36m EW-of-tier monthly active return vs cap-w universe bench,
# plain t-stat. Generic tier-level cross-sectional carrier diagnostic (not the
# strategy's own signal). Prior posterior: mega signal-dead (07-06 실측).
trail <- tail(yms[yms <= AS_OF], 36)
ym_shift <- function(ym, k) { t <- (ym %/% 100L)*12L + (ym %% 100L - 1L) + k
  (t %/% 12L)*100L + t %% 12L + 1L }
sig_alive <- list()
for (tr in c("MEGA", "MID", "SMALL")) {
  act <- sapply(trail, function(m) {
    mm <- sn[ym == ym_shift(m, -1L) & member == 1L & !is.na(size)]
    if (nrow(mm) < 50) return(NA_real_)
    mm[, rk := frank(-size, ties.method = "first")]
    mm[, tr_m := fifelse(rk <= 30, "MEGA", fifelse(rk <= 150, "MID", "SMALL"))]
    r <- mr[ym == m & Ticker %in% mm$Ticker]
    r <- merge(r, mm[, .(Ticker, size, tr_m)], by = "Ticker")
    if (nrow(r) < 50) return(NA_real_)
    bench <- r[, sum(ret_m * size) / sum(size)]
    mean(r[tr_m == tr, ret_m]) - bench
  })
  act <- act[!is.na(act)]
  tstat <- mean(act) / (sd(act) / sqrt(length(act)))
  sig_alive[[tr]] <- list(t_stat = round(tstat, 3), n = length(act),
                          alive = tstat > 0)
}

# ---- assemble section v83 schema --------------------------------------------
mk_tiers <- function() {
  lapply(c("MEGA", "MID", "SMALL"), function(tr) list(
    tier = tr,
    n_names_universe = as.integer(sum(tier == tr)),
    n_names_held = as.integer(sum(w_book > 0 & tier == tr)),
    active_risk_share = round(as.numeric(res_capw$shares[tr]), 4),
    active_risk_share_ew_basis = round(as.numeric(res_ew$shares[tr]), 4),
    active_risk_share_equity_sleeve = round(as.numeric(res_capw_sleeve$shares[tr]), 4),
    alpha_share = round(as.numeric(alpha_sh[tr]), 4),
    alpha_share_basis = "book LinearTilt weight share (alpha-proportional allocation), not realized alpha",
    signal_alive = sig_alive[[tr]]$alive,
    signal_alive_t36m = sig_alive[[tr]]$t_stat
  ))
}
max_div <- max(abs(unlist(res_capw$shares) - unlist(res_ew$shares)))
ctd <- list(
  basis = "cap_w_and_ew_uni",
  as_of_ym = AS_OF,
  book = "STR_1715_on_M4_R05_noLayer4_PG2 (holdings 2026-07-01, invested 0.30 / cash 0.70 CRISIS)",
  sigma_estimator = "lw_nls (Ledoit-Wolf 2020 analytical NLS; FQ-057 Phase B estimation-quality winner)",
  sigma_cond = round(cond_number(Sig), 1),
  pin_tag = pin_tag,
  tier_rule = "size-rank at 202606 month-end: MEGA<=30 (TOP30_N deployment convention R37/R39) / MID 31..150 / SMALL >150",
  active_vol_ann_capw_basis = round(res_capw$active_vol_ann, 4),
  active_vol_ann_ew_basis = round(res_ew$active_vol_ann, 4),
  tiers = mk_tiers(),
  dual_basis_divergence_flag = max_div > 0.15,
  dual_basis_max_tier_share_divergence = round(max_div, 4),
  signal_alive_basis = "trailing 36m EW-of-tier active return vs cap-w K200|KQ150 bench, t-stat>0; generic tier carrier diagnostic, NOT strategy signal. Prior posterior: mega signal-dead (project-captier-alpha-localization-20260706)",
  metric_type = "estimation_quality_diagnostic",
  note_role_boundary = "diagnostic only — no weight proposal; tier-exposure constraint design is optimizer scope"
)
write_json(ctd, file.path(OUT_DIR, "fq057_cap_tier_decomposition.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("[phasec] capw shares:", paste(names(res_capw$shares),
    round(res_capw$shares, 3), collapse = " "), "\n")
cat("[phasec] ew   shares:", paste(names(res_ew$shares),
    round(res_ew$shares, 3), collapse = " "), "\n")
cat("[phasec] alpha shares:", paste(names(alpha_sh), round(alpha_sh, 3),
    collapse = " "), "\n")
cat("[phasec] signal_alive t:", paste(names(sig_alive),
    sapply(sig_alive, function(x) x$t_stat), collapse = " "), "\n")
cat("[phasec] dual divergence max:", round(max_div, 4), "\n")
cat("[done] run_04 complete\n")
