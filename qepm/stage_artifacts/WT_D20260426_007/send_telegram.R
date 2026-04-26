#==============================================================================
# WT-D20260426_007 Alpha — Telegram brief
#==============================================================================

.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]

source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

OUT_CHART <- file.path(PROJECT_ROOT, "qepm/stage_artifacts/WT_D20260426_007/charts")

res <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260426_007 ALPHA_DONE — STR_1701_V2 Confidence-Aware Linear Tilt (Iter 14)",
  as_of = "2026-04-26",
  sections = list(
    list(emoji = "📊", heading = "Alpha Diagnostics (signal-level)",
         type = "table",
         df = data.frame(
           Metric = c("rank_IC", "ICIR", "sub_stab", "Harvey_NW", "DSR", "Turn"),
           Value = c("0.0323", "0.255", "0.786", "2.684", "0.764", "602%"),
           Gate = c("0.04", "0.20", "0.50", "3.0", "0.5", "<600"),
           Pass = c("FAIL", "PASS", "PASS", "FAIL", "PASS", "FAIL"),
           stringsAsFactors = FALSE),
         max_col_width = 8L,
         notes = c("Primary mandate RF-A1 sub_stab>=0.50 PASS",
                   "4 secondary gates FAIL — flagged in challenge_flags",
                   "Forge will measure realized PG2 SR vs 1.4625 baseline")),
    list(emoji = "💡", heading = "핵심 발견",
         type = "text",
         body = "RF-A1 sub_stab 0.786 PRIMARY MANDATE PASS — 3-component confidence sigmoid (sub_stab40+resid30+cov30) × rank tilt λ=0.5 κ=1.5가 Iter 11 base의 0.060 ex-post override를 ex-ante 0.786로 강화. ICIR 0.255 (vs best slot 0.238, +7.08%) 개선. 단 rank_ic 희석 0.052→0.032 (slot A alone vs composite tilt) 트레이드오프 발생. PG2 incremental SR 검증을 Forge에 위임."),
    list(emoji = "🚩", heading = "Challenge Flags (5건)",
         type = "bullet",
         items = c("RF-RANKIC HIGH: rank_ic 0.0323 < 0.04 (graduation gate)",
                   "RF-HARVEY HIGH: NW-HAC t=2.684 < 3.0 (n=92 한계 + multi-test)",
                   "RF-MONO MEDIUM: Q1->Q5 mono 0.50 (Q5<Q4 일부 회귀)",
                   "RF-TURN HIGH: top-decile turnover 602% > 600% (HARD limit)",
                   "RF-FF5 MEDIUM: top-20 EW 5-spec α t<2 (CAPM/FF3/C4/FF5/FF6 all)")),
    list(emoji = "🎛️", heading = "메타",
         type = "kv",
         kv = list(
           WT_ID = "WT-D20260426_007",
           Iter = "14",
           Phase = "ALPHA_DONE",
           Codex_R1 = "REJECT (resolution 9/9)",
           Method = "STR_1701 base + confidence sigmoid tilt λ=0.5 κ=1.5",
           Universe = "K200 ∪ KQ150 (322 avg names/month)",
           Liquidity = "200M production floor (Codex C2 fix)",
           N_signals = "92 sig_dates × 322 names",
           N_grid = "12 (4λ × 3κ)",
           Next = "Risk + Optimizer + Forge PG2 SR vs 1.4625"
         ))
  ),
  charts = c(
    file.path(OUT_CHART, "ic_timeseries.png"),
    file.path(OUT_CHART, "subperiod_ic.png"),
    file.path(OUT_CHART, "confidence_distribution.png"),
    file.path(OUT_CHART, "lambda_kappa_heatmap.png")
  ),
  footer = "➡️ Next: Risk Agent → Optimizer Agent → Forge PG2 backtest",
  emoji_min = 5L
)

cat("\nTelegram dispatch result:\n")
print(res)
stopifnot(isTRUE(res$ok))
cat("\n[send_telegram] complete\n")
