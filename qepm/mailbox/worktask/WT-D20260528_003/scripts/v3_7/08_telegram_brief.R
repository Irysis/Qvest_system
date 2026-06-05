#==============================================================================
# WT-D20260528_003 v3.7 — Step 8: Telegram Brief (Alpha Agent)
#
# tg_agent_brief() single entry — v6 SOT
# Recommended 4 sections:
#   1. 📌 summary (1-line headline)
#   2. 📊 table (graduation metrics)
#   3. 🚩 challenge flags
#   4. ➡️ next steps
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
source(file.path(BASE, "02_Infrastructure/telegram/telegram_notify.R"))

# Load final
fp <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/alpha_package.json")
final <- fromJSON(fp, simplifyVector = FALSE)

# ---- Graduation metrics table (2-col) ----
grad_table <- data.frame(
  Metric_Gate = c("rank_IC 정보계수 (게이트 0.04)",
                   "ICIR 정보계수안정성 (게이트 0.20)",
                   "Harvey 5-spec 통과 (게이트 3)",
                   "부기간안정성 (게이트 0.5)",
                   "단조성 (게이트 0.7)",
                   "위기기IC비율 AX-001 v2 (게이트 0.5)",
                   "DSR z-score (게이트 0.5)",
                   "섹터중립화후IC유지 (게이트 50%)",
                   "복합>단일 RF-A2 (게이트 baseline)"),
  Value_Verdict = c("0.044 [통과]", "0.453 [통과]", "2/5 [탈락]",
                     "0.733 [통과]", "-0.261 [탈락]", "-0.211 [탈락]",
                     "5.13 [통과]", "138~151% [통과]", "PASS [통과]"),
  stringsAsFactors = FALSE
)

# ---- Codex Round table (2-col) ----
codex_table <- data.frame(
  Item = c("Codex stance (입장)", "총 critical concerns 갯수", "HIGH 등급",
            "MEDIUM 등급", "agent 분류 ACCEPT", "agent 분류 PARTIAL",
            "weakest 가정"),
  Value = c("REJECT (거절)", "7건", "5건", "2건", "5건", "2건",
             "Phase 1/3 lockbox 오염된 TOP12 selection을 v3.7 사전-cutoff 재검증이 치유 못 함"),
  stringsAsFactors = FALSE
)

sections <- list(
  list(emoji = "📌", heading = "Summary",
       type = "kv",
       kv = list(
         "대상" = "STR_1722 Factor DB 미활용 TOP12 + 통계 알파 (v3.7)",
         "선택" = "TOP3 (D22+D43+M22) 섹터중립화 ICIR-proportional",
         "정보계수안정성" = "0.453 (t=6.81 강함)",
         "최상위20수익" = "+2.63%/y, 정보비율 0.30",
         "졸업판정" = "FAIL (critical 3 + 신규 PIT 위반 2)",
         "권고" = "TERMINATE — 도훈 confirm 필요"
       )),
  list(emoji = "📊", heading = "졸업 게이트 9-점검",
       type = "table",
       df = grad_table,
       max_col_width = 18L),
  list(emoji = "🤖", heading = "Codex Round 결과",
       type = "table",
       df = codex_table,
       max_col_width = 28L),
  list(emoji = "🚩", heading = "Codex 7 critical concerns 분류",
       type = "bullet",
       items = c(
         "첫째 (높은 심각도, 인정): 1상/3상 후보선정 미래참조 위반 (관측종료 2026-02)",
         "둘째 (높은 심각도, 인정): 정적 정보계수비례 가중치 = 전기간 통계 사용",
         "셋째 (높은 심각도, 부분인정): 디플레이티드샤프 시행회수 18 과소추정 (실제 333)",
         "넷째 (높은 심각도, 인정): 위기기 -0.21 단조성 -0.26 다중검정 2/5 졸업 실패",
         "다섯 (높은 심각도, 인정): 유동성 2억원 사전관측 미적용 (요청 5천 vs 기본 2억 충돌)",
         "여섯 (중간 심각도, 부분인정): 공리7 다중슬리브 의도만, 실증 미구현",
         "일곱 (중간 심각도, 인정): v3.7 challenge note 작성 + 산출물 미러"
       )),
  list(emoji = "💡", heading = "핵심 발견 + 정직한 결론",
       type = "bullet",
       items = c(
         "정량 인상적: 섹터중립화후 정보계수안정성 0.453",
         "정보계수 t값 6.81, 부기간안정성 0.733",
         "본질 문제: 1상/3상 lineage가 lockbox 위반 — 상류 미래참조 오염",
         "v3.7 정보계수 재검증은 cutoff 적용했으나 후보군 자체 오염",
         "10분위 spread 0.03%/월 (무의미) — 단조성 -0.26 = 비단조 알파",
         "위기기 정보계수 -0.010 vs 정상 +0.046 — 방어형 알파 아님",
         "STR_1721 v1/v3.5/v3.6 + v3.7 = 4 cycles 연속 졸업탈락"
       )),
  list(emoji = "➡️", heading = "다음 단계 (도훈 결정)",
       type = "bullet",
       items = c(
         "옵션 가 (권장): STR_1722 종결 — 헌장 §5 데이터마이닝 방지",
         "옵션 나 (대안): 미래참조 청결 재실행 (4~5일, 알파약화 확률 75%+)",
         "리스크 / 옵티마이저 대기 — 도훈 confirm 후 진입 또는 폐기"
       ))
)

# Send
res <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260528_003 v3.7 ALPHA_DONE — TOP3 composite REJECT (PIT 오염 + 졸업 게이트 3 FAIL)",
  as_of = "2026-05-28",
  sections = sections,
  footer = "STR_1722 v3.7 — 정직한 TERMINATE 권고 (Codex REJECT 7건 concerns)",
  force = TRUE
)
cat("Telegram brief sent.\n")
print(res)
