# Governor FINAL telegram brief — WT-D20260425_011 STR_1700 MEGA_06 Iter6
# v4 ENFORCE: tg_agent_brief() Single-Dispatch + auto-validation
project_root <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(project_root)
source("02_Infrastructure/telegram/telegram_notify.R")

# Section 1: Verdict KV
sec_verdict <- list(
  emoji = "👑",
  heading = "Governor FINAL Verdict",
  type = "kv",
  kv = list(
    "Verdict" = "ADMITTED_WITH_NOTE 🟡",
    "Scenario" = "A (Replacement 100% post-T+90)",
    "Pathway" = "phased_30_90_days 📅",
    "T+0 Action" = "PG1 Probe Phase admit / Book UNCHANGED",
    "Codex Round" = "TIMEOUT 2× 1200s SKIP (OVERRIDE_003)",
    "Registry Role" = "core_with_machinery_overlay (G5 ACCEPTED_NOW)"
  )
)

# Section 2: Same-period 243m Pareto comparison TABLE
sec_pareto <- list(
  emoji = "📊",
  heading = "Same-period 243m Pareto",
  type = "table",
  df = data.frame(
    Strategy = c("MEGA_06 (STR_1700)", "MEGA_05 baseline", "STR_1699 Iter5"),
    SR = c("1.079", "0.966", "0.995"),
    CAGR = c("15.27", "14.37", "20.03"),
    MDD = c("-22.98", "-24.82", "-34.93"),
    Harvey = c("4.55", "3.25", "4.30"),
    DSR_post = c("4.05", "3.60", "3.75"),
    stringsAsFactors = FALSE
  ),
  max_col_width = 12L,
  notes = c("MEGA_06 Pareto-dominates MEGA_05 on 5/5 axes",
            "vs STR_1699: SR/MDD/Harvey/DSR 우월 / CAGR -4.76pp 양보")
)

# Section 3: Phased pathway TABLE
sec_phased <- list(
  emoji = "📅",
  heading = "Phased pathway 30/60/90",
  type = "table",
  df = data.frame(
    Milestone = c("T+0 (2026-04-26)", "T+30 (2026-05-26)", "T+60 (2026-06-25)", "T+90 (2026-07-25)"),
    Action = c("PG1 admit", "Partial 50%", "Partial 75%", "Full 100%"),
    STR_1700 = c("0.00", "0.50", "0.75", "1.00"),
    MEGA_05 = c("0.80", "0.40", "0.20", "0.00"),
    STR_1656 = c("0.20", "0.10", "0.05", "0.00"),
    stringsAsFactors = FALSE
  ),
  max_col_width = 14L,
  notes = c("T+30 preconditions: G1+G2+G3+G4 PASS",
            "T+60 preconditions: T+30 KPIs PASS + Codex replay",
            "T+90 preconditions: T+60 KPIs PASS + AX-008 formal closure")
)

# Section 4: 6 admission-gate disposition KV
sec_gates <- list(
  emoji = "🚧",
  heading = "6 Admission-Gate Conditions",
  type = "kv",
  kv = list(
    "G1 Architect AX-008" = "DEFERRED → T+30 (2026-05-15 spawn)",
    "G2 load_month_factors() rebuild" = "DEFERRED → T+30 (2026-05-20)",
    "G3 2e8 KRW PIT all-date" = "DEFERRED → T+30 (2026-05-20)",
    "G4 daily CVaR/CDaR/stress" = "DEFERRED → T+30 (2026-05-20)",
    "G5 role reclassification" = "✅ ACCEPTED_NOW (core_with_machinery_overlay)",
    "G6 monitoring agent" = "🔄 REQUIRED at T+0 (별도 setup order)"
  )
)

# Section 5: AX violations + book impact TEXT
sec_ax <- list(
  emoji = "🛡️",
  heading = "AX 위반 + Book Impact",
  type = "text",
  body = paste(
    "AX-001 v2 defense alpha FAIL (bad/normal IC ratio -1.835) → G5 honest reclassification 적용 (core_with_machinery_overlay).",
    "AX-008 triangulation FAIL_FORMAL (Architect absent + Codex DISSENT) → substitute evidence accepted: Forge + Judge harness Lockbox 1.6927 vs Forge 1.7459 (Δ 0.053 within tolerance) + Iter5 lineage MD5 hash-identical.",
    "AX-002 PASS (hash audit MD5 identical pre/post). AX-005 PASS_NECESSARY 3-axis composite. AX-007 exception #1 multi-sleeve PASS.",
    "Book impact T+0: NONE (Probe Phase admit). Current PG2 active MEGA_05 80% + STR_1656 20% UNCHANGED. T+30 partial 50% contingent on G1~G4 closure. T+90 full 100% projected SR 1.0789 / CAGR 15.27 / MDD -22.98."
  )
)

# Section 6: Next steps BULLET
sec_next <- list(
  emoji = "➡️",
  heading = "Q-Lead Next Steps",
  type = "bullet",
  items = c(
    "Issue monitoring agent setup order: qepm/mailbox/monitoring/STR_1700_monthly_drift_config.json",
    "Issue Architect on-demand spawn order for T+19 (2026-05-15) G1 closure",
    "Issue Forge re-extension order for T+24 (2026-05-20) G2 + G3 + G4 closure",
    "Issue Codex replay order for T+30 milestone (4× 600s split, not 1× 1200s)",
    "Update strategy registry role = core_with_machinery_overlay",
    "T+30 milestone review: collect G1+G2+G3+G4 + KPIs → trigger PARTIAL_50PCT or DEFER",
    "Codex round 2× 1200s timeout 인정 (OVERRIDE_003) — 시간 한계로 SKIP, replay T+30"
  )
)

result <- tg_agent_brief(
  agent = "Governor",
  title = "WT-D20260425_011 STR_1700 MEGA_06 — ADMITTED_WITH_NOTE Scenario A phased_30_90",
  as_of = "2026-04-26",
  sections = list(sec_verdict, sec_pareto, sec_phased, sec_gates, sec_ax, sec_next),
  footer = "Codex timeout SKIPPED. Substitute evidence (Forge + Judge harness Lockbox + Iter5 MD5) accepted. T+30 Architect spawn + Codex replay scheduled."
)

cat("[Governor tg_agent_brief] result: ok=", result$ok, " bytes=", result$bytes, "\n", sep="")
if (!isTRUE(result$ok)) {
  cat("[Governor tg_agent_brief] error:", result$error, "\n")
}
