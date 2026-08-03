source("02_Infrastructure/config.R")
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/close_round.R"))

close_round(
  round_id      = "AS-FQ004-MaterialExclusion-20260804",
  verdict_type  = "config_scoped_negative",
  mechanism_diagnosis = paste(
    "K200∪KQ150 유니버스는 이미 우량주 필터링 완료 상태 — exclusion 재료(AdminStock/UnfaithfulDisc/TradingHalt)의 발생 빈도 자체가 너무 낮아 통계적 전력 부재.",
    "AdminStock 월평균 1.4종목(52개월 전부 ≤2), UnfaithfulDisc 1.3종목(56/62개월 ≤2), TradingHalt 1.7종목(130/155개월 ≤2).",
    "포트폴리오 delta: 전부 <0.02%/yr, cap-w PORT_t <2.0 (최대 t=1.89 UnfaithfulDisc).",
    "규모 편향(TradingHalt 이벤트종목 중앙값 시총 소형주 편향)도 Size-adjusted 후 개선 없음(t=-1.48).",
    "Miller(1977) exclusion 논리 전제(충분한 발생 빈도) 성립 불가 = 유니버스 자체의 사전필터가 신호를 소멸시킴."
  ),
  next_probes   = c(
    "FQ-038: 소형주 확장 유니버스 — AdminStock 582,973건/1,208 tickers 전체(K200∪KQ150 외)에서 재측정. monitoring/risk 소비면 국한.",
    "TradingHalt MEGA_MID tier 대형주 N>=150 도달 후 재측정 (현재 N=76, 방향 -6bp/월 유망하나 표본 부족).",
    "FQ-003 공매도+halt 교차: 공매도 데이터 결합 시 halt 복합 패턴 유의성 확인 (도훈 데이터 export 게이트 대기)."
  ),
  consumer_surfaces = c(
    "⑤monitoring 신호: book 현재 편입 종목 중 TradingHalt·AdminStock 발생 alert tripwire 배선 정당 (독립 alpha 불가와 무관)",
    "④위험모델: tail risk indicator — 대형주 tier TradingHalt -6bp/월 방향 β예산 참고값",
    "타 모드: FR/RAMP에서 소형주 포함 유니버스 시 FQ-038로 재측정 가능"
  ),
  frontier_update   = "FQ-004 signal_round_negative_frontier_open 유지. 산출물: fq004_material_filter_20260804.json. 부활조건: FQ-038 대형 표본 확인 or TradingHalt N>=150 or FQ-003 교차",
  live_trigger      = paste(
    "TradingHalt MEGA_MID 이벤트 N>=150 도달 시 즉시 재측정.",
    "FQ-003(공매도+halt) 데이터 export 완료 시 교차 검증.",
    "monitoring tripwire 배선: 즉시 착수 가능 — book 종목 중 이벤트 발생 시 alert."
  )
)
