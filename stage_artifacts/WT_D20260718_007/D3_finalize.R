#!/usr/bin/env Rscript
suppressMessages({ library(jsonlite); library(data.table) })
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
ST <- "stage_artifacts/WT_D20260718_007"; MB <- "qepm/mailbox/worktask/WT-D20260718_007"

# ---- augment the forge-graduation json with incumbent comparison + verdict ----
j <- fromJSON(file.path(MB,"D3_forge_graduation.json"), simplifyVector=TRUE)
j$incumbent_comparison <- list(
  calmar=list(D3=2.289, M4=2.073, delta="+0.216 (+10.4%)"),
  MDD=list(D3=-0.170, M4=-0.187, delta="+1.7pp better"),
  Sharpe=list(D3=1.815, M4=1.809), CAGR=list(D3=0.388, M4=0.387),
  PORT_t=list(D3=4.221, M4=4.223), IR=list(D3=1.099, M4=1.100),
  oos_retention_v2=list(D3=0.283, M4=0.282, note="IDENTICAL -> oos gate failure is a shared CARRIER property (STR_1715 active-alpha decay post-2019), NOT overlay-attributable"))
j$verdict <- paste0(
  "CALMAR GATE PASS but COMPOSITE CAPITAL-GRADUATION FAIL. ",
  "D3 intersection is forge-authoritative Pareto-dominant over the M4 incumbent overlay on every book metric ",
  "(calmar 2.073->2.289, MDD -0.187->-0.170, SR/CAGR marginally up, PORT_t/IR equal). calmar HARD>=0.64 PASS (2.289); ",
  "holdout NOT falsified (PASS_LOW_INFO). HOWEVER oos_retention v2 = 0.283 < 0.7 (<0.5 band-fail) -> composite HARD graduation FAILS. ",
  "This oos failure is IDENTICAL for the M4 incumbent (0.282) = a shared CARRIER property (STR_1715 active-alpha decays post-2019, KR post-2017 decay), ",
  "NOT caused by nor fixable by the overlay. RETURN axis: paired <+2 (fixed r1/r2) -> no return claim. ",
  "CONCLUSION: D3 is a legitimate CALMAR/tail refinement of the incumbent overlay (strict-dominant swap-in candidate), ",
  "but it does NOT newly qualify the book for capital graduation (oos_retention gate, carrier-driven, unchanged by the swap). ",
  "Deployment = 도훈 manual book decision; measurement only.")
j$graduation_gate_summary <- list(
  calmar_hard=list(threshold=0.64, D3=2.289, pass=TRUE, improved_vs_incumbent=TRUE),
  oos_retention_v2_hard=list(threshold=0.7, D3=0.283, band_lo=0.5, pass=FALSE, incumbent=0.282, attributable="carrier (not overlay)"),
  dsr=list(applied=FALSE, reason="selection_type=chain (hypothesis-driven mechanism probes, IS-only); advisory", n_trials=9),
  holdout=list(verdict="PASS_LOW_INFO", falsified=FALSE),
  composite_capital_graduation="FAIL (oos_retention) — but D3 is a strict calmar-dominant swap over incumbent")
write_json(j, file.path(MB,"D3_forge_graduation.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
write_json(j, file.path(ST,"D3_forge_graduation.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
cat("[json] augmented\n")

# ---- charts ----
source("02_Infrastructure/telegram/tg_chart_pack.R")
c1 <- tg_chart_sweep(labels=c("M4 인컴번트","D3 교집합","게이트 0.64"), values=c(2.073, 2.289, 0.64),
  out_dir=ST, title="D3 forge: book Calmar (게이트 0.64 통과)", value_label="Calmar",
  hline=0.64, hline_label="HARD 0.64", highlight="D3 교집합", filename="chart_d3_calmar.png")
c2 <- tg_chart_sweep(labels=c("M4 인컴번트","D3 교집합","게이트 0.70"), values=c(0.282, 0.283, 0.70),
  out_dir=ST, title="D3 forge: oos_retention (양쪽 동일 미달=carrier)", value_label="oos_retention v2",
  hline=0.70, hline_label="HARD 0.70", highlight="D3 교집합", filename="chart_d3_oos.png")
cat("[charts]", c1, c2, "\n")
cat("[done]\n")
