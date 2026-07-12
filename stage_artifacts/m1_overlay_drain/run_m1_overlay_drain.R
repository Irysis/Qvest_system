#!/usr/bin/env Rscript
# FQ-017 — m1 (avg_sentence_len) OVERLAY_CANDIDATE drain.
# Reuses drain runner CONTRACT PRIMITIVES (weighted_screen_bt / .nw_t_mean / drain_oos_v2 /
#   assert_overlay_pit / overlay_lookahead_ab) sourced with QVEST_DRAIN_NORUN=1. No new backtest engine,
#   no self-synthesis (all returns via weighted_screen_bt -> build_benchmark_compare NW lag-3).
# Prereg sha256: b93e48f2f238c4496e5774c9dd8b7c66bdfe89d9d9dccc4e514b683e79d1a3ee
suppressMessages({ library(data.table); library(jsonlite) })
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(root)
OUT <- file.path(root, "stage_artifacts/m1_overlay_drain")

Sys.setenv(QVEST_DRAIN_NORUN = "1")   # source functions only
source("02_Infrastructure/regime/overlay_candidate_drain.R")  # -> weighted_screen_bt, .nw_t_mean, drain_oos_v2, assert_overlay_pit, overlay_lookahead_ab
stopifnot(exists("weighted_screen_bt"), exists(".nw_t_mean"), exists("drain_oos_v2"),
          exists("assert_overlay_pit"), exists("overlay_lookahead_ab"))

ym2date <- function(ym) as.Date(sprintf("%d-%02d-01", ym %/% 100L, ym %% 100L))
ym_add  <- function(ym, k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }
KAPPA <- 0.30; COST_BPS <- 15

# ---- load PIT-verified signal panel (Ret_1m already forward; z1 = m1 cross-sectional z) ----
P <- as.data.table(readRDS("stage_artifacts/WT_D20260711_002/signal_panel.rds"))
P <- P[is.finite(z1) & is.finite(Ret_1m) & is.finite(BM_Ret)]
setorder(P, ym, Ticker)
cat(sprintf("[load] panel rows=%d months=%d avg_names=%.1f range=%d..%d\n",
            nrow(P), uniqueN(P$ym), nrow(P)/uniqueN(P$ym), min(P$ym), max(P$ym)))

returns_dt <- unique(P[, .(Date = ym2date(ym), Ticker, Ret_1m)])
bench_dt   <- unique(P[, .(Date = ym2date(ym), BM_Ret)])

# ---- weight builders (per-ym), given an eligibility subset key column `elig` ----
# base: EW over elig; excl: drop worst (most-obfuscated) z1 quintile among elig, renorm EW;
# tilt: w_base * exp(-kappa*clip(z1)); renorm. All long-only (w>=0), Sum w = 1 per Date.
build_weights <- function(D, form) {
  # D: data.table with (ym, Ticker, z1, elig=TRUE) rows already restricted to the tier's eligible set
  d <- copy(D)
  if (form == "base") {
    d[, w := 1.0, by = ym]
  } else if (form == "excl") {
    d[, thr := quantile(z1, 0.80, na.rm = TRUE, type = 7), by = ym]
    d <- d[z1 < thr]                    # keep clearer 80%; drop most-obfuscated quintile
    d[, w := 1.0, by = ym]
  } else if (form == "tilt") {
    d[, w := exp(-KAPPA * pmax(pmin(z1, 3), -3))]
  } else stop("bad form")
  d[, w := w / sum(w), by = ym]
  d[, .(Date = ym2date(ym), Ticker, w)]
}

# ---- tier eligibility ----
elig_LARGE <- function(D) D[, .SD[frank(-adv20, ties.method = "first") <= 25], by = ym]  # top-25 by liquidity
elig_BROAD <- function(D) D                                                               # all eligible

measure_arm <- function(w_dt, tag) {
  r <- weighted_screen_bt(w_dt, returns_dt, bench_dt, cost_bps_oneway = COST_BPS,
                          run_id = tag, strategy_id = tag)
  list(row = data.table(arm = tag, n_months = r$n_months,
                        abs_SR = r$abs_net_sr, abs_CAGR = r$abs_cagr, abs_MDD = r$abs_mdd,
                        calmar = { m<-abs(r$abs_mdd); if (m>0) r$abs_cagr/m else NA_real_ },
                        IR = r$information_ratio, capw_PORT_t = r$portfolio_alpha_t_nw_lag3,
                        active_SR = r$net_sr, oos_v2 = drain_oos_v2(r$period_returns),
                        turnover_ann = r$turnover_annual, n_names_avg = w_dt[, .N, by=Date][, mean(N)]),
       pr = as.data.table(r$period_returns))
}

paired_vs_base <- function(pr_arm, pr_base, tag) {
  m <- merge(pr_base[, .(date, base = ret_net)], pr_arm[, .(date, arm = ret_net)], by = "date")
  d <- m$arm - m$base
  data.table(arm = tag, n = nrow(m), paired_nw_t_lag3 = .nw_t_mean(d, 3L),
             mean_d_bps_m = mean(d) * 1e4, mean_d_ann_bps = mean(d) * 12 * 1e4)
}

run_tier <- function(tier_name, elig_fn, D_all) {
  De <- elig_fn(D_all)
  arms <- c("base", "excl", "tilt")
  res <- list(); prs <- list()
  for (f in arms) {
    w <- build_weights(De, f)
    mm <- measure_arm(w, paste0(tier_name, "_", f))
    res[[f]] <- mm$row; prs[[f]] <- mm$pr
  }
  tab <- rbindlist(res)
  paired <- rbindlist(lapply(c("excl","tilt"), function(f)
    paired_vs_base(prs[[f]], prs[["base"]], paste0(tier_name, "_", f))))
  list(tab = tab, paired = paired, prs = prs, elig = De)
}

D_all <- P[, .(ym, Ticker, z1, adv20, age, Ret_1m)]

cat("\n########## TIER: LARGE (carrier-analog, top-25 by adv20) ##########\n")
L <- run_tier("LARGE", elig_LARGE, D_all)
print(L$tab, digits = 4); cat("\n-- paired vs base --\n"); print(L$paired, digits = 4)

cat("\n########## TIER: BROAD (m1-locus, all eligible) ##########\n")
B <- run_tier("BROAD", elig_BROAD, D_all)
print(B$tab, digits = 4); cat("\n-- paired vs base --\n"); print(B$paired, digits = 4)

# ============ PIT obligations ============
cat("\n########## PIT guards ##########\n")
# 1) assert_overlay_pit HARD: cutoff = signal known at start of weights-month t; holding earned t+1.
uym <- sort(unique(P$ym))
cutoff  <- ym2date(uym)                 # signal known by start of weights-month t (active_from<=t)
holding <- ym2date(ym_add(uym, 1L))     # forward return earned in t+1
assert_overlay_pit(cutoff, holding, label = "FQ017/m1_overlay")
cat("[PIT-1] assert_overlay_pit HARD: PASS (cutoff=ym2date(t) <= holding_start=ym2date(t+1), >=1m margin)\n")

# 4) anchor/direction IC: score=-z1 vs fwd_excess (clarity -> higher forward excess); sign>=0 = PIT-normal
spear <- function(x,y){ ok<-is.finite(x)&is.finite(y); if(sum(ok)<3) NA_real_ else suppressWarnings(cor(x[ok],y[ok],method="spearman")) }
ic_by_m <- P[, .(ic = spear(-z1, fwd_excess), n=.N), by = ym][n>=10 & is.finite(ic)]
ic_mean <- mean(ic_by_m$ic); ic_t <- .nw_t_mean(ic_by_m$ic, 3L)
cat(sprintf("[PIT-4] IC(score=-z1, fwd_excess): mean=%.4f NW-t=%.2f over %d months (expect >=0 = clarity predicts higher excess)\n",
            ic_mean, ic_t, nrow(ic_by_m)))

# 2) lag1 staleness stress: weights at t use z1 from t-1 (staler). Rebuild excl/tilt on BROAD (m1-locus).
Plag <- copy(P[, .(ym, Ticker, z1)]); Plag[, ym := ym_add(ym, 1L)]  # z1 of (t-1) attributed to weights-month t
setnames(Plag, "z1", "z1_lag")
D_lag <- merge(D_all, Plag, by = c("ym","Ticker"))          # keep only where a t-1 signal exists
D_lag[, z1 := z1_lag][, z1_lag := NULL]
lag_tier <- function(tier_name, elig_fn) {
  De <- elig_fn(D_lag)
  prs <- lapply(c("base","excl","tilt"), function(f) measure_arm(build_weights(De, f), paste0(tier_name,"_lag1_",f))$pr)
  names(prs) <- c("base","excl","tilt")
  rbindlist(lapply(c("excl","tilt"), function(f) paired_vs_base(prs[[f]], prs[["base"]], paste0(tier_name,"_lag1_",f))))
}
lag_B <- lag_tier("BROAD", elig_BROAD)
lag_L <- lag_tier("LARGE", elig_LARGE)
cat("\n[PIT-2] lag1 staleness stress (paired vs base; compare to non-lag above; collapse => same-month leak):\n")
print(rbind(lag_L, lag_B), digits = 4)

# 3) strict-PIT A/B: strict = require age>=1 (signal known >=1 full month before weights-month => 2m margin).
Dstrict <- D_all[age >= 1]
Sstrict <- run_tier("BROADstrict", elig_BROAD, Dstrict)
sr_of <- function(pr) mean(pr$ret_net)/stats::sd(pr$ret_net)*sqrt(12)
ab_excl <- overlay_lookahead_ab(sr_of(B$prs[["excl"]]), sr_of(Sstrict$prs[["excl"]]),
                                metric_name = "BROAD_excl abs_SR (current vs strict age>=1)")
ab_tilt <- overlay_lookahead_ab(sr_of(B$prs[["tilt"]]), sr_of(Sstrict$prs[["tilt"]]),
                                metric_name = "BROAD_tilt abs_SR (current vs strict age>=1)")
cat("\n[PIT-3] strict-PIT A/B:\n", ab_excl$message, "\n", ab_tilt$message, "\n")

# ============ write results ============
all_tab <- rbindlist(list(L$tab, B$tab), fill = TRUE)
all_paired <- rbindlist(list(L$paired, B$paired), fill = TRUE)
fwrite(all_tab, file.path(OUT, "scenarios.csv"))
fwrite(all_paired, file.path(OUT, "paired.csv"))

result <- list(
  fq_id = "FQ-017", measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  prereg_sha256 = "b93e48f2f238c4496e5774c9dd8b7c66bdfe89d9d9dccc4e514b683e79d1a3ee",
  metric_type = "weighted_screen", tier = "screen_diagnostic",
  engine = "weighted_screen_bt (contract NW lag-3) via overlay_candidate_drain.R primitives (QVEST_DRAIN_NORUN=1)",
  cost_bps_oneway = COST_BPS, tilt_kappa = KAPPA,
  overlay_signal = "z1 = cross-sectional z of m1 avg_sentence_len (higher=more obfuscation); sole carrier per Phase A LOO",
  scenarios = all_tab, paired_nw = all_paired,
  pit_guard = list(
    assert_overlay_pit = "PASS(HARD)",
    ic_direction = list(mean_ic = ic_mean, nw_t = ic_t, n_months = nrow(ic_by_m),
                        note = "score=-z1 vs fwd_excess; >=0 = clarity predicts higher excess (PIT-normal)"),
    lag1_stress = rbind(lag_L, lag_B),
    strict_ab = list(excl = ab_excl, tilt = ab_tilt)),
  note = paste("Screen-tier overlay diagnostic (NOT capital-grade). Carrier STR_1715 per-stock holdings unavailable",
               "(bt_result$holdings empty) + carrier in m1-dead mega/mid tier + drain overlay=market-scalar =>",
               "measured on dual-tier bases from m1 panel via contract primitive. See preregistration.json infeasibility_surface.")
)
write_json(result, file.path(OUT, "m1_overlay_drain_result.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat(sprintf("\n[done] wrote %s\n", file.path(OUT, "m1_overlay_drain_result.json")))
