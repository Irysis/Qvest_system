#==============================================================================
# Step 8 — Telegram Brief v3.5 (alpha-research完了)
#
# v6 SOT: .claude/skills/qvest-telegram/SKILL.md
# Hook: telegram_direct_call_guard.sh
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(data.table)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")

source(file.path(BASE, "02_Infrastructure/telegram/telegram_notify.R"))

# Load final package
pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = TRUE)

# ─── Section 1: summary (헤드라인 1줄, 20-100 chars) ───
summary_text <- "v3.5 alpha-research 졸업 FAIL — Codex REJECT (HIGH 3 ACCEPT). Q-Lead 결정 대기."

# ─── Section 2: kv (graduation 지표) ───
metric_kv <- list(
  "랭크 정보계수" = "0.0425 (>=0.04) PASS",
  "정보계수 비율" = "0.3392 (>=0.20) PASS",
  "부기간 안정성" = "1.00 (>=0.5) PASS",
  "다중검정 보정 t값" = "1/5 at t>3.0 FAIL (3/5 at t>2.5)",
  "변형 샤프지수" = "1.00 (>=0.5) PASS",
  "섹터중립 잔존 정보계수 비율" = "48.1% FAIL — RF-A4 임계 50%",
  "혼합 vs 최우수 단일" = "0.339 vs 0.393 (저변동) FAIL — 희석 14%",
  "체제 대체비율" = "54.2% (312/576) — 9-state 과세분화"
)

# ─── Section 3: bullet (Codex Round 결과) — 한글 풀어쓰기 ───
codex_bullet <- list(
  "Codex 입장: 거부 — 정보계수 0.34 = 섹터노출 + 저변동/배당 기울임 의심",
  "수용 고심각 3건: 다중검정 1/5, 섹터중립 잔존 48.1%, 혼합 < 단일 저변동",
  "부분수용 2건: 체제 대체비율 54.2%, 매크로 입출력 응용연결 부재",
  "반박 3건: 검증3축 (역할 범위), 상류 자료 결손, 단일 sleeve 증명 (Optimizer 단계)",
  "자동 상급 escalate: 미발동 (고심각 3 미만 5, 공리 강제실패 영건)"
)

# ─── Section 4: bullet (Q-Lead 다음 단계) ───
next_bullet <- list(
  "안 1 — 전환 v3.6: 섹터중립화 + 체제수 축소 (9→4~5 HMM) + 단일우세 대안",
  "안 2 — 권한부여: 다중검정 t>2.5 허용 + 공분산 섹터분해 + 섹터 active 한계",
  "안 3 — 종료: 2회 cycle 후 infeasible 판정, 대안 가설로 전환",
  "Alpha agent 권고: 안 1 (섹터 의존은 근본 문제, 차기 cycle 해결 가능)",
  "Artifacts: stage_artifacts/ 하위 (alpha_scores.parquet + alpha_validation.json)",
  "Challenge note: challenge_note.md (전체 adjudication 기록)"
)

# ─── Telegram dispatch ───
tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260528_003 ALPHA_DONE — STR_1721 v3.5 졸업 FAIL (Codex REJECT HIGH 3 ACCEPT)",
  sections = list(
    list(type = "summary", body = summary_text),
    list(type = "kv", emoji = "📊", heading = "졸업 지표", kv = metric_kv),
    list(type = "bullet", emoji = "🚩", heading = "Codex Critic Round (REJECT)", items = codex_bullet),
    list(type = "bullet", emoji = "➡️", heading = "다음 단계 (Q-Lead 결정)", items = next_bullet)
  ),
  as_of = "2026-05-28",
  footer = "STR_1721 alpha-research v3.5 | qvest-telegram v6 SOT"
)
cat("\n[Telegram brief] sent.\n")
