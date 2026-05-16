## Forge agent — Q-Lead Telegram brief (v6 SOT, 220-char body cap respected)
suppressMessages({source("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")})

res <- tg_agent_brief(
  agent = "Forge",
  title = "WT-D20260515_002 Forge FINALIZED — REJECT",
  sections = list(
    list(emoji = "ChartDown", header = "Verdict",
          body = "REJECT WT-D20260515_002. 60/40 blend Pareto-dominated by STR_1715-only on identical 84m sample. STR_1715 PG2 100% book_state 유지 권장."),
    list(emoji = "Bar", header = "Axis A same 84m 15bps",
          body = "Blend SR_net 0.5579 / CAGR 9.54% / MDD -27.21% / TO 13.07/yr. STR_1715 only SR 2.0054 / CAGR 36.86% / MDD -14.35%. ΔSR -1.45 (Pareto-dominated)."),
    list(emoji = "Search", header = "Sample-bias audit",
          body = "STR_1715 canon 256m SR 1.9536 vs 84m subsample SR 2.0054 = -2.7% drift (NEGLIGIBLE). 'sample bias' premise invalidated — 84m blend 구조에 불리."),
    list(emoji = "Shield", header = "DSR same-N apples (Bailey-LdP)",
          body = "Blend N=12 z_DSR -0.29 FAIL. STR_1715 N=12 z_DSR +3.43 STRONG PASS. 동일 다중검정 페널티 후에도 STR_1715 절대 우월."),
    list(emoji = "Layers", header = "Turnover 3-convention (Codex C6 FIX)",
          body = "Security round-trip 13.07/yr (Forge primary), one-way 7.33/yr (contract), cash-incl 14.65/yr. 세 컨벤션 모두 6.0/yr cap 초과."),
    list(emoji = "Robot", header = "Codex Round 9 concerns",
          body = "Stance REJECT veto_false. ACCEPT_FIX 4 (C1 bt_result + C3 DSR + C5 lockbox + C6 TO) + ACCEPT_PARTIAL 2 + ACCEPT_DOC/DEFER/DOWNGRADE 3 + REBUTTAL 0. Q-Lead escalate HIGH=6."),
    list(emoji = "Target", header = "잠재 경로 (별도 WT)",
          body = "Path A 196m re-cut / Path B bi-monthly M6 / Path C fixed-book sleeve A / Path D defensive 3rd source (KR_10y/TSMOM L-281).")
  ),
  charts = c(
    "qepm/mailbox/worktask/WT-D20260515_002/output/equity_curve.png",
    "qepm/mailbox/worktask/WT-D20260515_002/output/regime_decomposition.png"
  ),
  footer = "📦 forge_package.json + challenge_note + bt_result.rds + 4 OOS charts. 🔒 Pure Function boundary attestation: 3-package + weights MD5 unchanged."
)
print(res)
