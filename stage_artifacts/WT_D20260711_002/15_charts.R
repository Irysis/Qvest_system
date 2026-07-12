#==============================================================================
# WT-D20260711_002 Phase A — Step 15: charts (generate only; NO telegram send per WT prereg)
#   metrics_note cites CONTRACT/canonical values only (no in-chart recompute).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
CHART <- file.path(OUT, "charts")
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))

# best single metric m1 canonical (contract-grade period_returns)
m1 <- readRDS(file.path(OUT,"canon_m1_full.rds"))
pr <- m1$period_returns   # date, ret_net, benchmark_ret
note <- sprintf("cap-w PORT_t %.2f · IR %.2f · net_SR %.2f · turn %.0f%%/yr · EW-uni PORT_t %.2f (canonical_screen, gate 2.95 FAIL)",
                m1$portfolio_alpha_t_nw_lag3, m1$information_ratio, m1$net_sr,
                100*m1$turnover_annual, m1$diag_ew_universe$portfolio_alpha_t_nw_lag3)
paths <- tg_chart_pack(pr, out_dir = CHART,
  title = "공시 난독화 전수 — m1 문장길이(clarity long) 25종",
  metrics_note = note, prefix = "m1_")
cat("[15] pack:", paste(basename(paths), collapse=", "), "\n")

# sweep: 7-metric family cap-w PORT_t (composite + m1..m6)
tab <- readRDS(file.path(OUT,"single_metric_canon.rds"))
ar  <- readRDS(file.path(OUT,"analysis_results.rds"))
comp_t <- ar$canon_full$portfolio_alpha_t_nw_lag3
labels <- c("composite(사전등록 primary)", "m1 문장길이", "m2 Fog", "m3 한자/영문밀도",
            "m4 표/숫자밀도", "m5 섹션길이", "m6 boilerplate")
values <- c(comp_t, tab[metric=="m1"]$port_t_full, tab[metric=="m2"]$port_t_full,
            tab[metric=="m3"]$port_t_full, tab[metric=="m4"]$port_t_full,
            tab[metric=="m5"]$port_t_full, tab[metric=="m6"]$port_t_full)
sweep <- tg_chart_sweep(labels, values, out_dir = CHART,
  title = "난독화 지표군 canonical cap-w PORT_t (top25 EW·15bps·liq2e8)",
  value_label = "cap-w PORT_t (NW lag3)", hline = 2.95, hline_label = "졸업 HARD",
  highlight = "m1 문장길이", filename = "family_portt_sweep.png")
cat("[15] sweep:", basename(sweep), "\n")
writeLines(c(paths, sweep), file.path(OUT,"chart_paths.txt"))
cat("[15] DONE — chart paths written (NO telegram send: WT prereg PROHIBITS)\n")
