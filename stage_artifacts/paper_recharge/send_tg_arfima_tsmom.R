PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

out_dir <- file.path(PROJECT_ROOT, "stage_artifacts/alpha_search/20260821_074219_6672")

tg_agent_brief(
  agent = "AlphaSearch",
  title = "VR 조건부 모멘텀(ARFIMA_TSMOM) 백테스트 결과 — Grade F",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "분산비(VR>1) 추세 구간에서만 12-1 모멘텀을 적용했으나, 자본 배정 기준(MDD 25%)을 크게 초과해 Grade F 판정."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 주가 변동의 '추세성'을 측정해(분산비 VR>1) 추세 구간 종목만 모멘텀 전략을 적용했습니다",
           "방법: 2005~2026년 KOSPI200+KOSDAQ150 유니버스, 25종목 동일가중, 15bps 비용 백테스팅",
           "결과: 연복리 15.5% 수익이나 최대낙폭 64.3% — 자본 배정 허들(MDD 25%)을 크게 초과",
           "의미: VR 조건이 위험을 줄이지 못함. 모멘텀 고유의 크래시 리스크가 그대로 남아있습니다"
         )),
    list(type = "kv", emoji = "📊", heading = "핵심 성과 (2005-02 ~ 2026-08)",
         kv = list(
           "등급" = "F (Grade F)",
           "종합점수" = "37.6 / 100",
           "샤프지수" = "0.551",
           "연복리수익률" = "15.5%",
           "최대낙폭" = "64.3% (허들 25% 초과)",
           "칼마지수" = "0.242 (허들 0.64 미달)",
           "정보비율" = "0.239",
           "다중검정 t값" = "1.21 (허들 2.95 미달)",
           "표본외 유지율" = "0.57 (허들 0.70 미달)",
           "초과수익" = "+6.5%/yr (vs KOSPI200)",
           "벤치마크 상관" = "0.747",
           "연간 회전율" = "229.9%",
           "정보계수" = "-0.003 (안정성: -0.034)"
         )),
    list(type = "bullet", emoji = "🚩", heading = "실패 원인 진단",
         items = c(
           "구조적 낙폭 하드 실패: 55%+ 낙폭 에피소드 6회/15회 — MDD 64.3%",
           "PORT_t 1.21 < 2.95: 초과수익이 통계적으로 우연과 구분 불가",
           "IC -0.003: VR 조건부 신호가 미래 수익을 전혀 예측하지 못함",
           "OOS 유지율 0.57 < 0.70: IS 성과가 OOS로 이전되지 않음",
           "GFC(-38.7%) 및 Iran_War(-23.7%) 국면에서 벤치마크 하회"
         )),
    list(type = "bullet", emoji = "🔬", heading = "기전 진단 (next_probe)",
         items = c(
           "next_probe 1: VR 임계값(>1)이 너무 낮음 — VR>1.2~1.5 구간만 선별하면 신호 순도 개선 가능",
           "next_probe 2: VR 조건이 맨몸 모멘텀과 실제로 다른지 A/B 비교 필요(VR 없는 순수 12-1 MOM 대조군)",
           "next_probe 3: VR 신호를 오버레이 레이어(현금 비중 조절)로 이식 — standalone이 아닌 위험관리 도구로 소비",
           "부활 조건: VR>1.3 이상 강필터 + cross-sectional 분위 상위만 선택 시 IC가 양전환하면 재검토"
         ))
  ),
  charts = c(
    file.path(out_dir, "equity_curve.png"),
    file.path(out_dir, "annual_returns.png")
  ),
  glossary = TRUE
)

cat("[TG] 발송 완료\n")
