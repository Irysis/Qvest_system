#==============================================================================
# Telegram Brief — v3.6 PIVOT GRADUATION_FAIL_TERMINATE_RECOMMENDED
#
# v6 SOT (`.claude/skills/qvest-telegram/SKILL.md`)
# 한글 연구 컨텍스트 의무 + 4 권장 섹션 + ≥5 emoji
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(BASE, "02_Infrastructure/telegram/telegram_notify.R"))

# Read final alpha_package + Codex revisions for accurate metrics
pkg <- fromJSON(file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/alpha_package.json"))
rev <- fromJSON(file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6/codex_revisions_v36.json"))

cat("Sending Telegram brief ...\n")

result <- tg_agent_brief(
  agent = "Alpha",
  title = "STR_1721 v3.6 PIVOT — 3-cycle Data Mining 방지 TERMINATE 권고",
  sections = list(
    list(type = "summary",
         body = "STR_1721 v3.6 PIVOT 3-cycle GRADUATION_FAIL 누적 — TERMINATE 권고."),
    list(type = "bullet", emoji = "📚", heading = "연구 컨텍스트",
         items = c(
           "목적: 8 패밀리 합성 + 국면 엔진 섹터 중립화 검증",
           "방법: HMM 4 상태 + 단일 vs 합성 vs 국면가중 3 비교",
           "검증: 도훈 옵션1 3 fix axes + Codex (gpt-5.5 xhigh)",
           "결론: 3 사이클 실패 — 가설 정직성 정합 TERMINATE 권고"
         )),
    list(type = "kv", emoji = "📊", heading = "v3.6 핵심 지표 (graduation 기준)",
         kv = list(
           "정보계수" = "0.0201 FAIL (≥ 0.04)",
           "ICIR" = "0.224 PASS (≥ 0.20)",
           "Harvey t (≥ 3)" = "0/5 FAIL (need ≥ 3/5)",
           "디플레이티드 샤프" = "0.000 FAIL (≥ 0.5)",
           "방어형 위기 IC비율" = "-4.82 FAIL (≥ 0.5)",
           "단조성" = "0.07 FAIL (≥ 0.7)",
           "회전율 연환산" = "5.08 FAIL (≤ 3.0)"
         )),
    list(type = "kv", emoji = "🔬", heading = "3 fix axes (Codex 정정 반영)",
         kv = list(
           "1 섹터 중립화" = "PASS 67.8% (Asness-Frazzini 2013)",
           "2 HMM 4상태 축소" = "FAIL 36.6% (사전 10.8% 과장)",
           "3 합성 vs 단일" = "FAIL 0.224 < 0.386 (단일 패밀리 우월)"
         )),
    list(type = "bullet", emoji = "🤖", heading = "Codex Round 결과",
         items = c(
           "모델 gpt-5.5 xhigh — 입장 REJECT",
           "우려 9건 (높음 5 + 중간 3 + 낮음 1)",
           "약점: HMM 고정 과장 (사전 10.8% 실제 36.6%)",
           "Q-Lead 자동 escalate 발동 (높음 임계 도달)"
         )),
    list(type = "bullet", emoji = "🚩", heading = "본질 진단",
         items = c(
           "v1: 합성 64% dilution + 국면 same-date 인공물",
           "v3.5: ICIR 0.339는 섹터 노출 의존 (유지 48.1%)",
           "v3.6: 섹터 중립 후 진짜 alpha 약함 노출",
           "위기 IC비율 -4.82 = 위기에서 alpha 역전 (방어형 실패)"
         )),
    list(type = "bullet", emoji = "➡️", heading = "Q-Lead 권고",
         items = c(
           "기본: 1721 패밀리 폐기 (3 사이클 누적 실패)",
           "salvage A안: low_vol vs quality 롱숏 (0.34 spread)",
           "salvage B안: 동적 패밀리 선택 LightGBM 비용 인식",
           "salvage C안: low_vol 단일 50+ 종목 분산",
           "alternative: 다른 가설로 신규 작업 발급",
           "산출: 200 종목 코스피200 2023-11-30 latest PIT 정합"
         ))
  )
)

cat("Telegram result:\n")
print(result)
