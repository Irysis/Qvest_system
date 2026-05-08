#==============================================================================
# WT-D20260508_002 v5 Telegram brief — v6.1 SOT 강화 적용 (도훈 비판 정정)
#
# v6.1 enforcement (.TG_CONFIG):
#   TEXT_MAX = 220, BULLET_ITEM_MAX = 80, KV_VALUE_MAX = 60
#   MAX_NCOL = 2, MAX_TOTAL_WIDTH = 28, SUMMARY_MAX = 100
#   표 사용 X 우선 — kv + bullet 의무 (모바일 짤림 방지)
#==============================================================================

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))

# Codex stance load (post-Codex)
codex_path <- file.path(PROJ, "qepm/mailbox/worktask/WT-D20260508_002/codex_critic_response_alpha_v5.json")
codex_stance <- "PENDING"
codex_concerns <- 0
if (file.exists(codex_path) && file.info(codex_path)$size > 0) {
  cd <- jsonlite::fromJSON(codex_path, simplifyVector = FALSE)
  codex_stance <- cd$stance %||% "UNPARSED"
  codex_concerns <- length(cd$critical_concerns %||% list())
}
cat("Codex stance:", codex_stance, " concerns:", codex_concerns, "\n")

# ── 4 섹션 (v6.1 lengths verified) ───────────────────────────────────────────

# 📌 summary (≤100 chars, 1줄 의무)
sec_summary <- list(
  type = "summary",
  body = "v5 PIT-proper FAIL Honest. v4 IC 0.291 -> 0.0193 (lookahead 93% 입증)"
)

# 📊 kv — 핵심 지표 v4 vs v5 (값 ≤60자, named list format)
sec_kv <- list(
  type = "kv",
  kv = list(
    "IC" = "0.291 -> 0.019 (gate 0.04 FAIL)",
    "ICIR" = "2.44 -> 0.19 (gate 0.20 FAIL)",
    "Harvey-t" = "17.40 -> 1.45 (gate 3.0 FAIL)",
    "DSR" = "17.76 -> -35.78 (N=560)",
    "max20 SR" = "-0.034 net, TO 10.6 hurdle FAIL",
    "GPU" = "torch+xgb CUDA 4080S, 48m -> 12m",
    "Codex" = sprintf("%s (%d concerns)", codex_stance, codex_concerns)
  )
)

# 🚩 bullet — Codex 8 concerns 6 path remediation 결과 (각 ≤80자)
sec_remedied <- list(
  type = "bullet",
  items = c(
    "Codex 6 path remediation 모두 적용 — IC 폭락이 C1 lookahead 진단 입증",
    "PIT-rolling factor universe 137 union, 46 persistent (>=95% sig_dates)",
    "max-20 hard sim TO 10.6 -> 6.0 hurdle FAIL, top-quintile 폐기 정정",
    "Bailey-LdP 3 view DSR 모두 catastrophic (-21.7/-28.4/-35.8)",
    "GPU REAL: torch MLP + xgb CUDA RTX 4080S, v4 polynomial-EN 정정",
    "Codex v5 REJECT 7 concerns: 5 ACCEPT + 2 PARTIAL, alpha_vector NA",
    "no_deploy_flag=TRUE 강제, AX-002 grep 0건, AX-008 2/3 (alpha+Codex)"
  )
)

# ➡️ bullet — pivot 후속 priorities (각 ≤80자)
sec_next <- list(
  type = "bullet",
  items = c(
    "Pivot 4th source: crisis-conditional defense (AX-001 v2 IC ratio)",
    "또는 macro-residual long-horizon (FRED/ECOS x KOSPI), low TO 설계",
    "또는 RL state-space + economic restriction (Avramov 2023)",
    "alpha_package.json final + challenge_note_v5.md + Q-Lead 의사결정 대기"
  )
)

sections <- list(sec_summary, sec_kv, sec_remedied, sec_next)

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260508_002 v5 ALPHA_DONE — DISCOVERY_FAIL_HONEST_PIT_PROPER",
  sections = sections,
  lock_scope = "Alpha_WT-D20260508_002_v5"
)

cat("Telegram v5 brief sent\n")
