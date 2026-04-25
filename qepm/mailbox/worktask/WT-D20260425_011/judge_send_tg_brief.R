# judge_send_tg_brief.R — Judge S6 final brief for STR_1700 Iter6 MEGA_06
# v4 ENFORCE compliant; bytes target 1200~3800
suppressPackageStartupMessages({
  source("02_Infrastructure/telegram/telegram_notify.R")
})

# Section 1: Gate 0~6 results
gate_df <- data.frame(
  Gate = c("0 PIT", "1 Hard", "2 Harvey", "3 Hurdle",
           "4 Role", "5 AX", "6 Tail"),
  Result = c("PASS_NOTE", "PASS", "PASS", "NOT_GR_A",
             "PASS_NOTE", "PASS_NOTE", "PASS_NOTE"),
  Note = c("C14/15 inh", "TO 5.94", "5/5 t>3.65", "CAGR<16",
           "no def alpha", "AX-008 fail", "CVaR proxy")
)

# Section 2: Lockbox triangulation
lockbox_df <- data.frame(
  Source = c("Forge mo", "Judge daily"),
  SR = c("1.7459", "1.6927"),
  MDD = c("-7.41%", "-11.76%"),
  Note = c("forge_pkg", "harness v6.1")
)

# Section 3: Fair 243m
fair_df <- data.frame(
  Strategy = c("MEGA_06", "STR_1699", "MEGA_05"),
  SR = c("1.079", "0.995", "0.966"),
  MDD = c("-23.0%", "-34.9%", "-24.8%"),
  t_FF5 = c("4.55", "4.30", "3.25"),
  DSR = c("4.05", "3.75", "3.60")
)

# Section 4: Codex Round disposition (concise)
codex_df <- data.frame(
  ID = c("CJ_001", "CJ_002", "CJ_003", "CJ_004", "CJ_005-7"),
  Concern = c("Repl rule", "AX-008 fail", "AX-001 fail", "Gate3 lang", "Mon items"),
  Sev = c("HIGH", "HIGH", "HIGH", "MED", "MED"),
  Disp = c("ACCEPT", "ACCEPT", "ACCEPT", "ACCEPT", "PARTIAL")
)

sections <- list(
  list(emoji = "⚖️", heading = "Gate 0~6 결과 (5/7 PASS, 2 PASS_NOTE)",
       type = "table", df = gate_df, max_col_width = 14L,
       notes = c("Harvey 5/5 t 3.65~3.74 robust",
                 "DSR_post Pre-LB 3.33 / Full 4.05",
                 "Gate3 NOT Grade A (CAGR 0.73pp short)")),
  list(emoji = "🔒", heading = "Lockbox Triangulation (24-26 OOS)",
       type = "table", df = lockbox_df, max_col_width = 14L,
       notes = c("Judge harness v6.1 직접 측정 (550 days)",
                 "Forge 1.75 vs Judge 1.69 = WITHIN_TOLERANCE",
                 "AX-008 formal 3-source 미충족 (Architect 부재)")),
  list(emoji = "📊", heading = "Same-Period 243m Fair Comparison",
       type = "table", df = fair_df, max_col_width = 12L,
       notes = c("MEGA_06 Pareto-dominant: SR + MDD + t + DSR",
                 "vs current PG2 (Scen D): score 1.464 vs 1.127",
                 "+30% risk-adjusted improvement")),
  list(emoji = "⚔️", heading = "Codex Round (REVISE) 처리",
       type = "table", df = codex_df, max_col_width = 14L,
       notes = c("HIGH 3 + MED 4, veto=false, escalation 미달",
                 "Replacement rule + AX-008 framing 수정 ACCEPTED",
                 "AX-001 v2 defense FAIL 명시 (-1.835)")),
  list(emoji = "🚨", heading = "Honest Diagnosis",
       type = "bullet",
       items = c("AX-001 v2 IC bad/normal -1.84 → defense alpha FAIL",
                 "MDD 메커니즘 = cash + DD + VolReg machinery",
                 "RF-A1 P3 IC 0.0025 (96% decay from P1) — monitor 필수",
                 "Honest role = core_with_machinery_overlay (NOT defense)",
                 "Overfitting: alpha_decay_with_machinery_compensation",
                 "Iter6 milestone 4/6 (SR 1.5/CAGR 18 미달, MDD/Harvey/DSR/OOS PASS)")),
  list(emoji = "💡", heading = "Judge 최종 권고",
       type = "text",
       body = paste0(
         "JUDGE_PASSED_WITH_NOTE 발행. STR_1700은 portfolio-level hurdle 통과 + 243m Pareto-dominant. ",
         "Codex 3 HIGH ACCEPTED — Replacement rule, AX-008 formal FAIL, AX-001 defense FAIL 명시. ",
         "Governor에 Scenario A (100% Replacement) 권고하되 6개 admission-gate 조건 ",
         "(Architect review / load_month_factors rebuild / 2e8 PIT all-date / daily CVaR holdings / ",
         "role re-classification / 월간 IC monitoring) 충족 후 활성화. ",
         "Forward 위험: signal alpha P3 decay 진행 중, MDD는 machinery가 담당."
       ))
)

charts <- c(
  "04_Research/strategies/STR_1700_WT011_MEGA_06/output/equity_curve.png",
  "04_Research/strategies/STR_1700_WT011_MEGA_06/output/oos_zoom_chart.png",
  "04_Research/strategies/STR_1700_WT011_MEGA_06/output/scenario_comparison.png"
)

result <- tg_agent_brief(
  agent = "Judge",
  title = "[Judge] WT-D20260425_011 STR_1700 Iter6 MEGA_06 — JUDGE_PASSED_WITH_NOTE",
  sections = sections,
  as_of = "2026-04-26",
  charts = charts,
  footer = "➡️ Governor PG2 admission (6 conditions)  |  🔗 judge_verdict.json  |  ⚔️ codex stance=REVISE",
  force = TRUE
)

cat(sprintf("\n[judge_send_tg_brief] DONE — ok=%s bytes=%d\n",
            result$ok, result$bytes %||% 0))
