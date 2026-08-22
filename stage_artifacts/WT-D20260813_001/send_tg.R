setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressWarnings(suppressMessages(source("02_Infrastructure/config.R")))
suppressWarnings(suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R")))

res <- tg_agent_brief(
  agent = "Risk",
  title = "WT-D20260813_001 RISK_DONE — Σ LW-NLS cond 434",
  sections = list(
    list(type = "summary",
         body = "q90 25종 포트 Σ 진단 완료. 지배 위험은 반도체 섹터 집중 57%·연변동성 54%·베타 1.13."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c("공분산행렬 = 25종목이 서로 얼마나 함께 움직이는지의 지도. 이걸로 포트 변동성과 집중위험을 잰다.",
                   "이 포트는 25종 중 14종이 반도체 — 한 업종에 57% 몰려 있어 분산이 약하다.",
                   "하락장에서 종목 간 상관이 오히려 올라(0.19→0.26) 방어가 약해지는 구조.",
                   "표본이 얇아(공통이력 25개월) 정밀 추정 대신 안정화 추정기(LW-NLS)를 썼다.")),
    list(type = "table", emoji = "🔬", heading = "공분산 추정기 비교",
         df = data.frame(
           추정기       = c("Sample", "Ledoit(linear)", "LW-NLS"),
           조건수_판정  = c("3.8e15 X특이(p=n)", "1.0 X muI붕괴", "434 채택 PSD")
         )),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "연변동성" = "53.9%",
           "베타(정적)" = "1.13",
           "공통인자(PC1)" = "30~35%",
           "섹터HHI(반도체)" = "0.370 / 57%",
           "유효종목수" = "24.6",
           "Rate-2022 스트레스" = "-34.7%",
           "COVID-2020" = "+9.4%"
         )),
    list(type = "bullet", emoji = "🚩", heading = "위험 경고",
         items = c("높음: 반도체 단일 업종 57% (40% 초과) — 분산이 아니라 한 업종 집중 베팅",
                   "스타일 괴리: 저변동이 아님. 모멘텀 점수 +2.57·밸류 음수·연변동성 54% (고모멘텀 비싼 성장주)",
                   "국면: 하락장에서 종목 상관 상승(0.26 대 0.19) — 낙폭 시 분산 효과 약화",
                   "얇은 표본: 공통 이력 25개월 대 종목 25개 — 비대각 정밀도는 진단 수준으로만 신뢰")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c("Optimizer 에게 공분산행렬·꼬리위험·집중도 진단 인계",
                   "상위 연구 판정은 미지지(성과 문턱 미달) — 본 공분산 분석은 기록용 독립 구조 정보",
                   "자본 배정 게이트 대상 아님 (거버넌스 정지)"))
  ),
  as_of = "2026-08-22"
)
cat("\nTG_SEND_RESULT:", if(is.list(res)) "list" else as.character(res), "\n")
