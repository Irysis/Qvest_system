#==============================================================================
# WT-D20260508_005 — Step 7: Telegram brief (v6.2 SOT)
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))

WT_ID <- "WT-D20260508_005"
ap <- read_json(file.path(PROJ, "qepm/mailbox/worktask", WT_ID, "alpha_package.json"),
                simplifyVector = TRUE)

title <- "한국 기간 스프레드 단독 알파 정직한 검증 — 1개월 졸업 미달"

sections <- list(
  list(type = "summary", emoji = "📚", heading = "연구 컨텍스트",
       body = "단일 거시 KR 기간 스프레드 베타 종목 횡단면 알파 정직한 검증 — 1개월 졸업 미달"),
  list(type = "bullet", emoji = "🎯", heading = "연구 목적과 결론",
       items = c(
         "WT_004 합성 희석 (단일 ICIR 0.187 > 합성 0.110) 후속",
         "단일 거시 알파 정식 검증 — 합성 희석 회피",
         "결론: 1개월 졸업 미달 (REJECT_GRADUATION)",
         "12개월 호라이즌 ICIR 0.310 + 부호 3/3 보존",
         "직교성 vs Hybrid PASS (|상관| 0.137 < 0.25)"
       )),
  list(type = "kv", emoji = "📊", heading = "핵심 비교 (1개월 졸업 기준)",
       kv = list(
         "정보계수 raw" = "0.0193 (졸업 0.04 미달)",
         "정보계수 안정성" = "0.183 (졸업 0.20 미달)",
         "다중검정 t값 (NW)" = "2.14 (졸업 3.0 미달)",
         "부기간 부호 일치" = "3/3 PASS / 엄격 1/3",
         "디플레이티드 샤프 N=27" = "z=6.61 PASS",
         "Hybrid 직교성" = "|상관| 0.137 < 0.25 PASS",
         "12개월 정보계수 안정성" = "0.310 (호라이즌 강세)",
         "롱온리 20종 정보비율" = "0.19 (BM +2.98%/yr 약함)"
       )),
  list(type = "bullet", emoji = "🚩", heading = "Codex Critic 처리 (REJECT 7건)",
       items = c(
         "C1 1개월 졸업 미달 — ACCEPT (자체 졸업 거부 일관)",
         "C2 PIT-C13 부호정렬 — PARTIAL_REBUTTAL (2014-04 이후 부호 145개월 안정)",
         "C3 PIT-C15 Factor DB 우회 — ACCEPT (infeasibility_report.json 생성)",
         "C4 RF-A4 섹터중립 IC 42% — ACCEPT (섹터 매개 신호 인정)",
         "C5 디플레이티드 샤프 다중검정 N=12→17 — ACCEPT (N=27까지 PASS 유지)",
         "C6 롱온리 20종 스케줄 — PARTIAL (정보 산출 정보비율 0.19 약함)",
         "C7 challenge_note + AX-008 — ACCEPT (challenge_note.md 작성)"
       )),
  list(type = "bullet", emoji = "✅", heading = "보존 가치 (Iter 9 family pivot 인계)",
       items = c(
         "합성 희석 thesis 입증 (단일 0.183 > 합성 0.110)",
         "12개월 장기 호라이즌 정보계수 0.310 + 부호 3/3 → 후속 연구",
         "Hybrid 70/15/15 직교성 견고 (max |상관| 0.137) — 신호 축 다름",
         "섹터 매개 컴포넌트 → 잠재적 Risk overlay 재해석",
         "합리화 표현 0건 (미미/관행적/실무적/이미반영 grep clean)"
       )),
  list(type = "bullet", emoji = "➡️", heading = "다음 단계",
       items = c(
         "Risk/Optimizer 스폰 미발생 (졸업 거부 lifecycle 정합)",
         "Iter 9 family pivot 후속 가설로 인계 (Growth × Investor_Flow / Skewness 등)",
         "12M 호라이즌 변형 향후 연구 (Harvey-NW 1.90 → 추가 보강 필요)"
       ))
)

ok <- tryCatch({
  tg_agent_brief(
    agent = "Alpha",
    title = title,
    sections = sections
  )
  TRUE
}, error = function(e) {
  cat("[telegram] error:", e$message, "\n")
  FALSE
})

if (ok) {
  cat("[07] telegram brief sent\n")
} else {
  cat("[07] telegram brief failed (silent)\n")
}
