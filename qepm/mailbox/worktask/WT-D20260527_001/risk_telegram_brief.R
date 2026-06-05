#==============================================================================
# Risk Research Brief — Telegram (per qvest-telegram SOT v6 SKILL.md §7.3)
#==============================================================================

suppressPackageStartupMessages({
  source("02_Infrastructure/telegram/telegram_notify.R")
})

tg_agent_brief(
  agent = "Risk",
  title = "분포 조건 알파(DCA v7) 공분산·꼬리위험 진단 — 통과",
  sections = list(
    list(type = "summary",
         body = "Ledoit-Wolf 공분산 + 8구간 스트레스 진단 완료. PIT 재정합 후 통과."),

    list(type = "bullet", emoji = "📚", heading = "연구 컨텍스트",
         items = c(
           "목적: DCA v7 알파(상위 20종목) 공분산·꼬리·군집위험 진단",
           "데이터: KR 주식 일간 2019-2023 (1233일×20종목) + 알파스코어 97개월",
           "방법: 5개 추정기 병렬 + Pfaff EVT-GPD + 8구간 역사 스트레스 + Acadian 군집",
           "결론: Σ 조건수 14.5 양호 / 꼬리 ξ=-0.22 얇은꼬리 / RF 1건 (방어계 HHI 0.54)"
         )),

    list(type = "table", emoji = "🔬", heading = "추정기 비교",
         df = data.frame(
           추정기 = c("샘플", "Ledoit oracle", "Gerber-RMT", "대각수렴"),
           조건수 = c("33.6", "14.5 ✅", "61.6", "20.4")
         )),

    list(type = "kv", emoji = "📐", heading = "핵심 지표",
         kv = list("선택 추정기" = "Ledoit-Wolf oracle",
                   "조건수" = "14.51 (양호)",
                   "연환산 변동성" = "27.4 ~ 50.5%",
                   "공분산 평균상관" = "0.20")),

    list(type = "kv", emoji = "🔥", heading = "공통위험 분해",
         kv = list("동일가중 총 변동성" = "10.4%/연",
                   "이익변경률" = "25.9%",
                   "저변동성 방어" = "12.5%",
                   "가치 (낮은 주가수익비율)" = "7.2%",
                   "시장 베타" = "6.6%")),

    list(type = "kv", emoji = "📉", heading = "꼬리위험(일간)",
         kv = list("정보계수 95% 조건부손실" = "-2.89%",
                   "정보계수 99% 조건부손실" = "-4.58%",
                   "극단치이론 99% 기대손실" = "-6.23%",
                   "꼬리지수 ξ" = "-0.22 (얇은꼬리)",
                   "표본 최대낙폭" = "-38.76%")),

    list(type = "table", emoji = "💥", heading = "스트레스 주요 4건",
         df = data.frame(
           구간 = c("금융위기2008", "EU채무2011", "코로나2020", "금리2022"),
           손실 = c("-14.1%", "-16.0%", "-14.1%", "-24.0%")
         )),

    list(type = "bullet", emoji = "🚩", heading = "위험신호",
         items = c("방어계 HHI 0.54 (>0.40) — 옵티마이저에 탄력 헤어컷 권고",
                   "금리2022 -24% in-sample (KOSPI200 -25% 동기간 유사)",
                   "공분산 PSD 5/5 통과 / 섹터 집중 10% 양호 / 군집점수 모두 0.75 미만")),

    list(type = "bullet", emoji = "🛡️", heading = "Codex 토론 결과",
         items = c("4건 전면 수용 — 미래참조 재정합, 노출·요인공분산·고유위험 별도 산출",
                   "4건 부분 수용 — 결정계수 13% 해석, 군집 보조지표 추가, 단위 명시",
                   "2건 반박 — 헌장 미명시 캡 / 옵티마이저 영역 침범 거부")),

    list(type = "bullet", emoji = "➡️", heading = "다음 단계",
         items = c("옵티마이저 단계 spawn 준비 완료",
                   "리스크 패키지 + 공분산 행렬 + 8구간 스트레스 + 군집점수 전달",
                   "AX-008 검증 1/3 (Codex) 완료, Forge 2/3 대기"))
  )
)
