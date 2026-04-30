#!/usr/bin/env Rscript
# Governor Telegram Brief — WT-D20260430_001 ADMIT_CONDITIONAL_WITH_WAIVER

suppressMessages({
  library(jsonlite)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

# Section 1 (table) — AX-001 v2.1 4-axis
sec1_df <- data.frame(
  Axis = c("1 Crisis_Alpha", "2 MDD Comp", "3 Crisis Vol", "4 Tail Risk"),
  Result = c("GFC+4.6/COVID+6.2pp", "+5.23pp 완화", "0.836 [.77,.93]", "Hill+16% 4/4"),
  Verdict = c("PASS_C", "PASS", "PASS<1.0", "PASS"),
  stringsAsFactors = FALSE
)

# Section 2 (kv) — M4 vs S1 metric
sec2_kv <- list(
  "Sharpe gross" = "1.6399 (+0.04 vs 1.595)",
  "CAGR" = "40.79% (-1.12pp 보험료)",
  "MDD" = "-30.33% (+5.23pp 완화)",
  "Calmar" = "1.345 (+14.0%)",
  "Sortino" = "3.625 (+5.3%)",
  "Trade War 23mo" = "fix +3bps (false positive resolved)"
)

# Section 3 (table) — Charter §10 5-cert
sec3_df <- data.frame(
  Cert = c("alpha_disc", "sr_prov", "sched_fid", "forge_pkg", "gov_concord"),
  Status = c("DEFER v1.6", "ISSUED", "ISSUED", "ISSUED", "ISSUED+waiver"),
  Note = c("meta_alloc 별도 정의 필요", "div 0.0pp", "267/267", "audit 11/11", "4-row evid"),
  stringsAsFactors = FALSE
)

# Section 4 (text) — 본질
sec4_body <- paste0(
  "M4는 STR_1715의 87%% 클론입니다. ",
  "단순 MRS overlay (cash 10/20/40%%)를 BOCPD+decay+BL 3중 레이더로 업그레이드하는 작업이고, ",
  "weight는 한 글자도 안 바뀝니다. ",
  "즉 'sleeve 추가' admission이 아니라 '운전 보조 시스템 패치'에 가깝습니다. ",
  "Sharpe 2.0 직행 티켓은 아니지만, MDD 5.23pp 완화 + Calmar 14%% 개선이라는 '에어백' 가치는 분명. ",
  "보험료 (CAGR 1.12pp/yr) 대신 안전벨트 (MDD/tail) 와 거래된 셈."
)

# Section 5 (table) — Post-Deploy 6
sec5_df <- data.frame(
  ID = c("PD_010", "PD_011", "PD_012", "PD_013", "PD_014", "PD_015"),
  Action = c(
    "Look-through 20-stock max 0.20",
    "Trade War false positive watch",
    "Paper trade 12mo + lockbox 보강",
    "Composite simplify decay-only",
    "Charter v1.6 alpha branch motion",
    "alpha codex stance 정정"
  ),
  Due = c("T+30", "monthly", "T+12mo", "T+60", "T+30", "T+7"),
  stringsAsFactors = FALSE
)

# Section 6 (text) — Codex round 결과
sec6_body <- paste0(
  "Codex governor critic가 6 concerns 던지고 (HIGH 4 + MEDIUM 2), Governor가 그 자리에서 3건 즉시 resolve. ",
  "(1) 공리 SOT 분할 → axiom store v2.1 amendment 즉시 patch. ",
  "(2) artifact mirror dir 부재 → 12개 cp. ",
  "(3) CVaR cap 13bps 초과 → 12%% sleeve waiver Governor 자율 권한 발급 (STR_1715 -11.12%% 이미 admit, M4가 99bps 개선). ",
  "REBUTTAL 1건: 'M4-S1 Harvey t=-1.50' 지적 → meta-allocation 본질에서 NW HAC drag = risk_reduction signal. ",
  "AX-001 v2.1 Axis 3 BS CI [0.77,0.93] < 1.0이 본질적 incremental significance 측정 (sleeve-level Harvey 측정 못 하는 영역). ",
  "Q-Lead escalate NOT_TRIGGERED — 자율 권한 충분."
)

# Section 7 (kv) — Verdict 요약
sec7_kv <- list(
  "Verdict" = "ADMIT_CONDITIONAL_WITH_WAIVER",
  "Subtype" = "Overlay schedule logic upgrade (replacement)",
  "Weight 변경" = "0pp (STR_1715 100%% 유지)",
  "Schedule 변경" = "단순 MRS → BOCPD+decay+BL tri-pillar",
  "AX-001 v2.1" = "PASS_CONDITIONAL 3+ axis (첫 적용)",
  "L-code" = "L-257 (Governor reframe verdict authority)"
)

# Section 8 (text) — directive 정합 + 비유
sec8_body <- paste0(
  "directive 'meta-allocation alpha는 위기시 alpha 가장 중요한 결정요인' 정합. ",
  "전기간 SR 0.04pp 우월은 측정 노이즈 수준 (Harvey 0/3 fail 인정). ",
  "그러나 GFC +4.6pp + COVID +6.2pp + Trade War fix는 실재. ",
  "비유: '평소 도로에서 ABS는 작동 안 하지만, 빙판에서는 차이를 만든다' — incremental t-stat이 측정 못 하는 영역. ",
  "AX-001 v2.1 4-axis는 정확히 그 영역 (CRISIS regime vol BS CI 통계 유의)을 잡아냅니다."
)

result <- tryCatch({
  tg_agent_brief(
    agent = "Governor",
    title = "PG0~PG3 ADMIT_CONDITIONAL_WITH_WAIVER — Meta-Allocation Alpha 첫 정식 admission",
    sections = list(
      list(emoji = "🛡️", heading = "AX-001 v2.1 META-ALLOCATION-EXEMPT 4-Axis 평가",
           type = "table", df = sec1_df),
      list(emoji = "📊", heading = "M4 vs Core (S1) 핵심 metric",
           type = "kv", kv = sec2_kv),
      list(emoji = "📜", heading = "Charter §10 5-cert 발급",
           type = "table", df = sec3_df),
      list(emoji = "💡", heading = "본질 한 줄 — 무엇을 결정한 것인가",
           type = "text", body = sec4_body),
      list(emoji = "📅", heading = "Post-Deploy 6건 (Rollback 8 trigger 별도)",
           type = "table", df = sec5_df),
      list(emoji = "⚔️", heading = "Codex devil's advocate 6 concerns 결과",
           type = "text", body = sec6_body),
      list(emoji = "🏆", heading = "Verdict 요약",
           type = "kv", kv = sec7_kv),
      list(emoji = "🎯", heading = "directive 정합 + 비유",
           type = "text", body = sec8_body)
    ),
    footer = "➡️ Next: POST_DEPLOY 6건 + L-257 hybrid_commit() (Q-Lead)"
  )
}, error = function(e) {
  list(ok = FALSE, error = conditionMessage(e))
})

cat("Telegram brief result:", ifelse(isTRUE(result$ok), "SENT ✓", paste("FAIL:", result$error)), "\n")
if (isTRUE(result$ok)) cat("bytes:", result$bytes, "\n")
