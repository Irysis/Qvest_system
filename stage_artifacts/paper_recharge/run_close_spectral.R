source("02_Infrastructure/config.R")
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/close_round.R"))

close_round(
  round_id      = "AS-Spectral-2607.19497-20260804",
  verdict_type  = "config_scoped_negative",
  mechanism_diagnosis = "arXiv:2607.19497는 선물/CTA TF 시스템 논문이지 개별 주식 횡단면 팩터 논문 아님. IC=-0.0016(랜덤 이하), FMB NW-t=0.43, FF3알파 -2.33%/yr, MDD 66.55%(실측 BTR STR_AS_20260804_073543_45444). 저주파 스펙트럼 이론은 자산클래스 레벨 TF에서만 성립 — 종목 횡단면 적용 시 이론 가정 위반으로 IC 소멸. 세 창(252일/60일/36M) 모두 재현 = 창 선택 문제 아님.",
  next_probes   = c(
    "FQ-146: KOSPI200 지수 레벨 TF 스펙트럼 타이밍 오버레이 (rolling FFT on index returns, 논문 원래 맥락 부합)",
    "T15_AutoCorr(AR(1) 21d) 기등재 vs 스펙트럼 분해 비교 — KR 월간 수익률 자기상관 구조 실측"
  ),
  consumer_surfaces = c(
    "③오버레이/국면 입력: KOSPI200 지수 레벨 TF 신호 (FQ-146 등재)",
    "④위험모델/RAMP: 지수 추세 강도 = 시장 노출 조절 레버"
  ),
  frontier_update   = "FQ-145 config_scoped_negative + FQ-146 지수TF overlay frontier_open 등재",
  live_trigger      = "KR ETF/선물 TF 레벨 저주파 스펙트럼 오버레이 A/B(FQ-146)에서 C5 PIT+lag1스트레스 생존 시 재도전. 또는 KR 개별주식 월간 수익률 AR(1)>0.15 구조변화 관측 시."
)
