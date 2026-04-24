#==============================================================================
# Judge Pilot 7 — Telegram brief (tg_agent_brief SOT)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source(file.path(PROJECT_ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

# ─── Gate A~F table ─────────────────────────────
gate_df <- data.frame(
  Gate   = c("A_PIT", "B_ISOL", "C_ALPHA", "D_CROWD", "E_CONC", "F_DRIFT"),
  Name   = c("PIT C1~C15", "Hash Isolation", "Net Alpha", "Crowding", "Concentration", "Regime Drift"),
  Verdict= c("PASS", "PASS_NOTES", "COND_FAIL", "PASS", "COND_PASS", "FAIL"),
  Key    = c("lockbox sealed",
             "opt append VERIFIED_SAME",
             "SR 0.258 < 0.5",
             "mkt_risk 39.0% PASS",
             "n=19 (QP natural)",
             "L-196 minvar_superior")
)

# ─── Pilot 6 vs 7 table ─────────────────────────
p67_df <- data.frame(
  Metric         = c("Forge SR", "Forge CAGR%", "Forge MDD%", "Val SR", "LB SR", "LB CAGR%", "LB MDD%", "LB Active IR", "L-195 guard", "Cluster Risk40%"),
  Pilot6         = c("0.066", "1.18", "-63.91", "-0.221", "1.086", "20.37", "-14.63", "-1.079", "0.0", "100"),
  Pilot7         = c("0.258", "4.69", "-55.22", "-0.222", "1.020", "21.31", "-21.81", "-1.033", "0.9716", "65"),
  Delta          = c("+0.192 (3.9x)", "+3.51pp (4.0x)", "+8.69pp 완화", "flat", "-0.066", "+0.94pp", "-7.18pp", "+0.046", "+0.9716", "-35pp")
)

# ─── Lockbox Regime Decomposition table (NEW) ───
lb_reg_df <- data.frame(
  Regime    = c("RISK_ON", "NEUTRAL", "CAUTION", "TOTAL"),
  Days_pct  = c("68.8%", "26.9%", "4.3%", "100%"),
  Strat_SR  = c("1.274", "0.735", "-1.703", "1.020"),
  BM_SR     = c("1.979", "1.943", "6.600", "1.020(strat only)"),
  Strat_CAGR= c("27.84%", "13.91%", "-28.57%", "21.31%"),
  Gap       = c("-0.70", "-1.21", "-8.30", "IR -1.033")
)

# ─── Cumulative P1~P7 ──────────────────────────
cum_df <- data.frame(
  Pilot = c("P1","P2","P3","P4","P5","P6","P7"),
  SR    = c("0.413","0.289","0.282","0.491","0.649","0.066","0.258"),
  CAGR  = c("8.72","4.06","6.00","9.25","12.03","1.18","4.69"),
  LB_SR = c("-","-","-","0.774","0.844","1.086","1.020"),
  LB_IR = c("-","-","-1.003","-1.311","-1.021","-1.079","-1.033"),
  Grade = c("HF","drift","D","C","C+","D","D-")
)

sections <- list(
  list(heading = "Gate A~F 판정",
       type = "table", df = gate_df,
       emoji = "⚖️"),
  list(heading = "Pilot 6 vs 7",
       type = "table", df = p67_df,
       emoji = "🔍"),
  list(heading = "Lockbox Regime 분해 (NEW, Judge 단독)",
       type = "table", df = lb_reg_df,
       emoji = "🌪️"),
  list(heading = "L-196 FINAL 판정",
       type = "text",
       emoji = "💡",
       body = paste0(
         "verdict: <b>minvar_superior</b> (regime_lucky 기각 + strategy_essence 기각)\n",
         "▪ RISK_ON 지배 68.8% (<80% threshold) → regime_lucky 기각\n",
         "▪ 2 regime positive SR / BM 전 regime 압도 → strategy_essence 기각\n",
         "▪ MinVar_BetaHard 재선택 2 consecutive pilot 확정\n",
         "▪ Lockbox Active IR -1.033 4 pilot 연속 < -1.0 structural fail\n",
         "▪ AX-007 예외지대 candidate 아님 → L-196 정식 등재"
       )),
  list(heading = "P1~P7 누적",
       type = "table", df = cum_df,
       emoji = "📈"),
  list(heading = "Pilot 8 권고",
       type = "bullet",
       emoji = "➡️",
       items = c(
         "Risk Universe Redesign Sprint (Alpha+Opt 동결, Risk 단독 수정)",
         "L-195a candidate: top-40 stratified sampling + alpha top-20 직접 선발 mode",
         "β_target 0.75→0.90 검토 (under-beta leverage loss 해소)",
         "System fix: record_package_lineage() → write_json() 순서 재배치 (3 pilot 연속 미반영)",
         "Governor: PG2 비교상 CAGR +5.17pp 우월 but Active IR -1.033 fatal → admission 구조적 불가"
       ))
)

res <- tg_agent_brief(
  agent = "Judge",
  title = "WT-D20260424_005 Pilot 7 GRADE_D_MINUS / DISCARD_WITH_STRUCTURAL_PIVOT + L-196 minvar_superior",
  as_of = "2026-04-24",
  sections = sections,
  charts = c(
    file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260424_005", "equity_curve_full.png"),
    file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260424_005", "equity_curve_oos.png")
  ),
  footer = "Next: Pilot 8 Risk Universe Redesign Sprint (L-195a 실증) — Governor PG0 gap 재진단 대기",
  emoji_min = 5L,
  force = TRUE
)

cat("\n[judge_pilot7 telegram] result:\n")
print(res)
