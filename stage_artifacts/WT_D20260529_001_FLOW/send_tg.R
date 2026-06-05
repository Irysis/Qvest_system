source("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")

res <- tg_agent_brief(
  agent = "Risk",
  title = "WT-D20260529_001 FLOW RISK_DONE — Sigma Ledoit-Wolf cond 6.5",
  as_of = "2026-05-29",
  sections = list(
    list(emoji = "📌", heading = "요약",
         type = "text",
         body = "수급 역추세(investor flow contrarian) 4번째 sleeve의 공동위험 구조를 진단했습니다. 공분산 추정기는 Ledoit-Wolf(조건수 6.5, 양정치성 확인)를 채택했고, 기존 운용 book과의 상관은 시장 베타를 제거하면 잔차 상관 0.24로 다각화 효익이 실재함을 확인했습니다. 위기 구간 8개에서 sleeve가 벤치마크를 일관되게 상회했습니다."),
    list(emoji = "🔬", heading = "공분산 추정기 비교",
         type = "table",
         df = data.frame(
           Estimator = c("Ledoit-Wolf", "Sample", "Constant-corr", "Gerber-RMT"),
           Cond = c("6.5", "31.5", "25.7", "65.3")
         ),
         max_col_width = 16L,
         notes = c("채택: Ledoit-Wolf (최소 조건수)", "4종 모두 양정치성 확인, 모두 조건수<100")),
    list(emoji = "📊", heading = "핵심 정량 결과",
         type = "bullet",
         items = c(
           "조건수(condition number) 6.5 — 500 한계 대비 매우 안정",
           "꼬리의존성(lower-TDC) sleeve내 평균 0.279 < 0.30 임계 통과",
           "기존 book 대비 잔차 상관 0.24 (시장베타 제거 후, 다각화 실재)",
           "잔차 꼬리의존성 0.235 / 보유종목 겹침 1/20 (5%)",
           "위기 손실: COVID +12.4% vs 벤치 -4.1% (상회)",
           "위기 손실: 금리인상2022 -10.0% vs -24.9% (상회)",
           "Style: 시장베타 1.17 + 모멘텀 tilt 유의(t 3.9), 자체위험 78.5%"
         )),
    list(emoji = "🛡️", heading = "헷지 및 권고",
         type = "bullet",
         items = c(
           "위기-강화 가설 확인: 정상 coverage 위기 전 구간에서 벤치 상회 (foreign flight reversal)",
           "단 sleeve 베타 1.16 -> beta 방어형 아님, 다각화는 상관/타이밍 기반",
           "FLOW와 기존 momentum 전략의 보유단 style 중복 -> optimizer가 결합 momentum 노출 모니터 권고",
           "일별 CVaR 0.0343은 한국 주식 sleeve로 정상, 월간 portfolio CVaR 상한은 optimizer 단계 적용"
         )),
    list(emoji = "🚩", heading = "Risk Flags 및 검토",
         type = "bullet",
         items = c(
           "위험 플래그 5종 전부 통과 (집중도/조건수/군집/위기손실/고상관쌍 무이상)",
           "Codex 비평 거부 의견(거부권 없음) — 4 수용 2 부분 2 반론, 상부 보고 불요",
           "수정 효과: 좁은 구간 착시 COVID -40% — 정상 구간 +12.4%로 반전",
           "위기 GFC/유럽위기/9.11은 상장 부분커버(85% 미만) 신뢰불가 명시"
         ))
  ),
  footer = "➡️ Next: Optimizer Agent (weights 결정)"
)
cat("tg ok:", isTRUE(res$ok), " err:", if(is.null(res$error))"none" else res$error, "\n")
