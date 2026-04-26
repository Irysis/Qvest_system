# Judge R2 finalize Telegram brief — WT-D20260426_004 Iter 11 STR_1701
suppressMessages({
  source("02_Infrastructure/telegram/telegram_notify.R")
})

# ── Section 1: Verdict 종합 (table) ─────────────────────────────────────────
verdict_df <- data.frame(
  항목 = c("Verdict", "Grade", "Score", "Stance", "Codex Round", "Triangulation"),
  값 = c("PASSED_WITH_NOTE ✅", "A 🏆", "76 / 100",
          "APPROVE_CONDITIONAL 🟡", "R1 REVISE → R2", "PENDING_ARCHITECT ⏳"),
  stringsAsFactors = FALSE
)

# ── Section 2: Performance (Lockbox + Full-period) (table) ──────────────────
perf_df <- data.frame(
  지표 = c("SR (daily)", "SR (full)", "CAGR", "MDD (daily)",
           "MDD (full)", "Harvey 5-spec", "DSR_post"),
  Lockbox = c("1.8894 🚀", "—", "65.14% 🎯", "-28.98% ⚠️",
              "—", "—", "—"),
  FullPeriod = c("—", "1.291 ✅", "33.28% 🎯", "—",
                 "-40.77% ⚠️", "5/5 PASS ✅", "4.07 ✅"),
  stringsAsFactors = FALSE
)

# ── Section 3: Codex R2 7 Concerns 처리 (table) ──────────────────────────────
codex_df <- data.frame(
  ID = c("C1 CVaR", "C2 AX-008", "C3 AX-001v2",
         "C4 Codex Defer", "C5 Replace/Seq",
         "C6 Lineage", "C7 Liquidity"),
  Severity = c("HIGH", "HIGH", "HIGH", "HIGH", "MED", "MED", "LOW"),
  Decision = c("PARTIAL", "PARTIAL", "ACCEPT+EVID",
               "PARTIAL_OVR", "ACCEPT", "PARTIAL_REB", "REBUTTAL"),
  Action = c("Lockbox CVaR 0.0136 PASS", "Architect PENDING",
             "Diversifier role", "RF-A1 fwd Gov",
             "Replacement scope", "Path resolved",
             "5e7 WT override"),
  stringsAsFactors = FALSE
)

# ── Section 4: Lockbox harness 측정 (table) ─────────────────────────────────
lockbox_df <- data.frame(
  metric = c("기간", "n_days", "총수익", "연수익", "연변동성",
             "SR_daily", "MDD_daily", "vs Forge OOS SR Δ"),
  실측 = c("2024-01-23~2026-04-26", "550일", "+198.86%",
           "65.14%", "28.77%", "1.8894", "-28.98%", "0.125"),
  stringsAsFactors = FALSE
)

# ── Section 5: AX-001 v2 Defense 4-metric audit (table) ─────────────────────
ax001_df <- data.frame(
  Metric = c("M1 Crisis_α", "M2 Core MDD relief",
             "M3 Bad/Normal IC ratio", "M4 Harvey t",
             "Aggregate"),
  Value = c("CRISIS IC -0.173 (n=5)", "7.27% 분산효익",
            "p1=0.032 > p3=0.005", "3.10 (>2.95)",
            "Diversifier role"),
  Verdict = c("FAIL ❌", "PARTIAL 🟡",
              "WEAK_PASS 🟡", "PASS ✅",
              "PARTIAL_PASS 🟡"),
  stringsAsFactors = FALSE
)

# ── Section 6: Governor 7건 forward (table) ─────────────────────────────────
fwd_df <- data.frame(
  ID = c("G1", "G2", "G3", "G4", "G5", "G6", "G7"),
  심각도 = c("MED", "MED", "MED", "MED", "MED", "MED", "LOW"),
  안건 = c("Defense 역할 'diversifier' 라벨링",
            "RF-A1 sub_stab 0.06 ex-ante FAIL (ex-post override)",
            "Factor R² 0.246 < 30% — Risk Mgr 재평가",
            "Architect advisory spawn (AX-008 closure)",
            "MDD -40.77% 보더라인 PG2 blend trade-off",
            "CVaR 정의 canonical Lockbox 채택",
            "Liquidity 5e7→2e8 production 재심사"),
  stringsAsFactors = FALSE
)

# ── Footer (text) ───────────────────────────────────────────────────────────
footer_text <- paste(
  "📂 verdict: qepm/mailbox/worktask/WT-D20260426_004/judge_verdict.json",
  "📂 codex R2: judge_codex_r2_response.json",
  "📂 lockbox audit: judge_lockbox_audit.json",
  "🧬 Inheritance: alpha+risk from WT-D20260425_010 (Iter 5 STR_1699)",
  "🔬 Iter 11 = Linear Tilt λ=1.0 + TOφ=8 monthly (Optimizer-only mutation)",
  "📚 L-204 적립 — judge_lockbox_harness + Codex R2 echo-chamber 방지 교훈",
  sep = "\n"
)

# ── 발송 ────────────────────────────────────────────────────────────────────
res <- tg_agent_brief(
  agent = "Judge",
  title = "WT-D20260426_004 Iter11 STR_1701 R2 Final ⚖️🔒",
  as_of = "2026-04-26",
  sections = list(
    list(heading = "Verdict 종합 ⚖️", type = "table", df = verdict_df),
    list(heading = "Performance — Lockbox vs Full 📈", type = "table", df = perf_df),
    list(heading = "Lockbox Harness 실측 (judge_lockbox_harness.R v6.1) 🔒",
         type = "table", df = lockbox_df),
    list(heading = "Codex R2 7 Concerns 처리 ⚔️", type = "table", df = codex_df),
    list(heading = "AX-001 v2 Defense 4-Metric Audit 🛡️",
         type = "table", df = ax001_df,
         notes = c("CRISIS IC 음수 → defense는 'crisis_alpha provider' 아닌 'diversifier' 역할로 재라벨")),
    list(heading = "Governor Forward 7건 ➡️", type = "table", df = fwd_df,
         notes = c("Sequential Admission TDC + AB blend scenario는 Governor 영역으로 이관"))
  ),
  charts = c(
    "qepm/mailbox/worktask/WT-D20260426_004/backtest_result/equity_curve.png",
    "qepm/mailbox/worktask/WT-D20260426_004/backtest_result/oos_zoom_chart.png",
    "qepm/mailbox/worktask/WT-D20260426_004/backtest_result/scenario_comparison.png"
  ),
  footer = footer_text,
  emoji_min = 5L
)

cat("\n=== Telegram Result ===\n")
print(res)
