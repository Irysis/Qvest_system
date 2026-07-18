#!/usr/bin/env Rscript
root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("02_Infrastructure/telegram/tg_chart_pack.R")
ST <- "stage_artifacts/WT_D20260718_007"
# paired NW-t across refinement directions (goal line = +2)
c1 <- tg_chart_sweep(
  labels=c("AE 단독(원본)","D1 tau 재매칭","D1 global(참조)","D2 grind 보완","D2 M4+AE+grind","D3 교집합(양자합의)"),
  values=c(-1.49, -1.62, -1.55, -1.49, -2.21, 0.49),
  out_dir=ST, title="WT-007 정밀화: 초과수익 paired NW-t (목표 >=+2)",
  value_label="paired NW-t (vs M4)", hline=2.0, hline_label="유의 +2", highlight="D3 교집합(양자합의)",
  filename="chart_refine_paired.png")
# calmar across refinement directions
c2 <- tg_chart_sweep(
  labels=c("M4(인컴번트)","AE 단독","D1 재매칭","D2 M4+AE+grind","D3 교집합"),
  values=c(2.069, 2.196, 1.956, 2.120, 2.284),
  out_dir=ST, title="WT-007 정밀화: book Calmar",
  value_label="Calmar", hline=2.069, hline_label="M4", highlight="D3 교집합",
  filename="chart_refine_calmar.png")
cat("[charts]", c1, c2, "\n")
