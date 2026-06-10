PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"); setwd(PROJ)
source("02_Infrastructure/telegram/telegram_notify.R")
tg_agent_brief(
  agent = "Q-Lead",
  title = "valearn 직교알파에 국면 오버레이 — OOS 알파회복 실패, 낙폭만 부분 개선",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "valearn 직교알파에 국면 오버레이: OOS retention -0.517 회복 실패(최선 -0.372), 낙폭만 45.6%->34.4% 개선."),
    list(type = "bullet", emoji = "📚", heading = "연구 컨텍스트",
         items = c(
           "목적: valearn 직교알파로 '직교 부재라 국면 오버레이 무가치' 결론 재검",
           "방법: 모듈 frozen, 디리스크 규칙 IS에서만 도출 -> OOS forward, 실측 계약",
           "결론: alpha 회복 실패 + 낙폭만 부분 개선. 직교 존재 != 오버레이 OOS robust 충분조건")),
    list(type = "kv", emoji = "📊", heading = "기준 vs 최선 오버레이",
         kv = list("기준 표본외유지" = "-0.517 (등급 F)",
                   "오버레이 최선" = "-0.372 (등급 C)",
                   "합격선" = "0.7 미달 (음수)",
                   "최대낙폭" = "45.6% -> 34.4%",
                   "샤프지수" = "0.713 -> 0.881")),
    list(type = "bullet", emoji = "🔬", heading = "메커니즘 (왜 회복 실패)",
         items = c("valearn=역행 가치모듈: 위기국면 최고(+7.4%/월) -> 위기 디리스크는 반등 제거(역효과)",
                   "표본외 알파붕괴는 지배국면(위험선호, 표본외 79%)에 집중: 이익변경 쇠퇴+베타, 노출조절로 타이밍 불가",
                   "유효한 건 주의국면 디리스크(급락 진입월)뿐 -> 낙폭만 다듬음")),
    list(type = "bullet", emoji = "🛡️", heading = "강건성 (Codex 라운드 반영)",
         items = c("노출 0배를 표본내에서만 선택(표본외 미열람) -> 사후선택 아님",
                   "2008·2020 위기 둘 다 제외해도 오버레이가 기준 상회 -> 2개 사건 아티팩트 아님",
                   "Codex 조건부승인, 미래참조 누수 없음")),
    list(type = "bullet", emoji = "➡️", heading = "결론 / 다음",
         items = c("거버넌스 정지: 자본장부 미기록, 운용체계 미등재 (측정·진단만)",
                   "팩터로테이션 결론 갱신: 오버레이=낙폭 보수, 알파유지 회복 아님",
                   "후속: 주의국면 내 급락확인 필터 + 위험선호국면 종목선별 조절(피처기반)"))
  ),
  charts = c("04_Research/factor_rotation/output/valearn_overlay_equity.png",
             "04_Research/factor_rotation/output/valearn_overlay_drawdown.png"),
  footer = "📚 산출: valearn_overlay_result.json / 직교알파+overlay != SR2.5 (정직 보고)"
)
