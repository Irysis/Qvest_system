# Telegram brief — WT-D20260425_008 RISK_DONE
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source("02_Infrastructure/telegram/telegram_notify.R")

estimator_df <- data.frame(
  Estimator   = c("sample_pairwise","ledoit_wolf_oracle","gerber_rmt","ledoit_wolf_constcor","nonlinear_shrinkage"),
  Cond        = c("8.86e8","82.48","1.51e9","8.74e8","8.20e8"),
  PSD         = c("Y","Y*","N","Y","Y"),
  stringsAsFactors = FALSE
)

caveat_df <- data.frame(
  Metric     = c("Panel cor","CS-avg cor","Top-20 cor","TDC (lower 20%)"),
  Q07_M08    = c("0.0021","0.0062","-0.2902","0.1667"),
  Q07_AC21   = c("0.0496","-","0.2325","0.4762"),
  stringsAsFactors = FALSE
)

stress_df <- data.frame(
  Scenario   = c("GFC 2008","Rate 2022","Market -5%","Value crash 3σ","Mom reversal 3σ"),
  Loss_pct   = c("-42.95","-22.91","-5.00","-6.49","-0.11"),
  stringsAsFactors = FALSE
)

flags <- c(
  "RF-R1 HIGH: Market 70.4% (top-20 KR 구조적)",
  "RF-R6 MEDIUM: Hill α(M08)=0.46 — heavy tail momentum crash",
  "RF-R7 MEDIUM: M08 SubStab 0.188 (P3 IC 0.0117 decay)"
)

res <- tg_agent_brief(
  agent = "Risk",
  title = "WT-D20260425_008 RISK_DONE — Σ ledoit_wolf_oracle cond 197",
  sections = list(
    list(emoji="🔬", heading="Σ Estimator 5건 비교 (R13 parallel)",
         type="table", df=estimator_df),
    list(emoji="🔍", heading="L-219 0.731 출처 + 3-metric reconciliation",
         type="table", df=caveat_df),
    list(emoji="🌪️", heading="Tail Risk + Stress",
         type="text",
         body=paste(
           "EW port vol 19.72% / Risk: Mkt 70.4% Alpha 12.2% Spec 17.4%.",
           "TDC Q07-M08 0.1667 vs baseline AC21 0.4762 (-65%).",
           "Hill α(M08)=0.46 매우 낮음 — Daniel-Moskowitz 2016 momentum crash 노출.",
           "CVaR_95 daily 2.55%, MDD 252d 18.70%.",
           collapse=" ")),
    list(emoji="📉", heading="Stress Tests (8 periods + 3 scenarios)",
         type="table", df=stress_df),
    list(emoji="🚩", heading="Risk Flags",
         type="bullet", items=flags),
    list(emoji="🎛️", heading="AX-002 Compliance + Caveat Resolution",
         type="kv",
         kv=list(
           sigma_psd="TRUE (min_eig 1.85e-5)",
           cond_post_shrink="197.47",
           caveat_resolved="YES — L-219 0.731=portfolio-level metric, not panel cor",
           m08_family="Momentum_Residual (cross-family) — AX-004 cleared"
         ))
  ),
  emoji_min = 6L
)
cat("Telegram result: ok=", isTRUE(res$ok), "\n")
