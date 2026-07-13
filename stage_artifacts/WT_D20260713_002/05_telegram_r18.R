## R18 텔레그램 v7 판정 보고 (실측 시각화 의무, 원칙 9)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260713_002"

charts <- c(file.path(QM,OUT,"portt_sweep.png"),
            file.path(QM,OUT,"fb_equity_curve.png"),
            file.path(QM,OUT,"fb_drawdown.png"))

tg_agent_brief(
  agent = "Alpha",
  title = "R18 회계-포렌식 통계 팩터 2종 — 재량적 발생액·Benford 위반도 전부 자본 문턱 미달",
  sections = list(
    list(type="summary", emoji="📌",
      body="재무제표 통계기법 새 팩터 2종(발생액 회귀 잔차·Benford 위반도) 16년 검증 — 둘 다 자본 문턱 크게 미달. 새 자본 없음, 지식만 적립."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "시도: 통계 정교화 = 회계 조작·이익조정 흔적을 재무제표에서 통계로 탐지",
        "F-A 재량적 발생액: Jones 회귀로 '경영진이 손댄 이익' 잔차를 추출(높으면 회피)",
        "F-B Benford 위반도: 재무 숫자 첫자리가 자연법칙에서 벗어난 정도(높으면 조작 의심)",
        "방법: 매달 팩터 상위 25종목 동일비중 매수 백테스팅(15bps·유동성 필터)",
        "결과: 둘 다 문턱 2.95 미달(F-A 0.45·F-B 0.57), 실제 예측력 없음",
        "핵심: F-A는 이미 있는 발생액 팩터(AC13)와 사실상 동일(상관 0.991)=중복")),
    list(type="kv", emoji="📊", heading="핵심 수치 (시총가중 기준 · 191개월)",
      kv=list(
        "F-A 재량발생액" = "시총가중 0.45 / 동일가중 0.33음 · 부기간 1.07→0.57음",
        "F-A 증분성"     = "기존 발생액팩터 AC13과 상관 0.991 = 무증분·중복",
        "F-B 벤포드위반도" = "시총가중 0.57 / 동일가중 0.30음 · 부기간 0.79→0.14음",
        "F-B 귀무검정"   = "월셔플 유의확률 0.16 = 신호구조 없음",
        "F-B 크기위장"   = "크기 상관 0.006 = 크기 대리 아님(우려 해소)",
        "게이트 종합"    = "자본문턱 0/2 · 최고 0.57 ≪ 2.95")),
    list(type="bullet", emoji="🚩", heading="주의 · 정직",
      items=c(
        "둘 다 동일가중(EW) 기준에서도 음(-0.33/-0.30) = 대형주 벤치 아티팩트 아님, 진짜 알파 부재",
        "F-A: 수정 Jones의 매출채권 조정항이 KR 대형주서 무의미(수정≈원본), 원본 AC13은 이미 과거 FAIL",
        "F-B: 정보계수 부호가 가설과 반대·무의미(t -1.00), 큰 그림 예측력 0",
        "상위 25종목 90~95% 소형주 쏠림 = 대형주 세그먼트 신호 소멸(최고감사 세그먼트=조작분산 낮음 가설)",
        "K-IFRS 2011·원천전환 2016 구조단절은 월별 표준화로 완화(수준이동 제거)",
        "Step0 필드 가용성 게이트 통과 — 추정 대체 없이 실데이터만 사용")),
    list(type="bullet", emoji="➡️", heading="판정 · 다음",
      items=c(
        "판정: 구성-국한 부정(config-scoped negative) — survivors 0, 재료 소진 아님(INV-7)",
        "F-A: standalone 부적격(중복) → quality/accrual composite 보조 feature로만 소비",
        "다음①: F-B 최악분위 배제(exclusion) 오버레이 — long 편입 아닌 회피 신호로 재소비",
        "다음②: 소형 universe(RAMP)·분기 Benford·F-A×F-B 합성 포렌식 스크린",
        "재료(재무제표×통계기법)는 미소진 — 소비 방식 전환이 남은 프론티어"))
  ),
  charts = charts,
  footer = "📚 L-AR-20260713_162115 · FQ-031 · prereg_sha256 f5b797b2 · n_trials 2(sweep) · panel 2009-06..2025-06 191m"
)
cat("R18_TELEGRAM_DONE charts=", length(charts), "\n")
