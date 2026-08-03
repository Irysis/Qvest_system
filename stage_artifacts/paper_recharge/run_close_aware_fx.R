source("02_Infrastructure/config.R")
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/close_round.R"))

close_round(
  round_id      = "AS-AWARE-FX-2607.27611-20260804",
  verdict_type  = "config_scoped_negative",
  mechanism_diagnosis = "DART 사업보고서 전문 텍스트 파이프라인 미구축으로 논문 원형(NLP FX 헤징 점수) 재현 불가. 재무 proxy(파생상품/총자산) 대용: IC=-0.0078(음수), PORT_t=-0.258(p=0.797 비유의), MDD 59.01%, CAGR 0.92%(실측 STR_AS_20260804_074545_39272, metric_type=backtested). 파생상품 보유액은 FX 헤징 목적이 아닌 규모 측정 — 금리/원자재 헤징 합산으로 FX 노출과 연계 약화.",
  next_probes   = c(
    "FQ-148: DART 전문 텍스트 FX 헤징 공시 NLP — 논문 원형 재현 (FQ-074 텍스트 파이프라인 구축 후)",
    "FQ-149: 외화자산/총자산 순수 proxy — 논문 FX exposure baseline 직접 대응 (dart_raw_financials 외화 계정 precheck 선행)"
  ),
  consumer_surfaces = c(
    "②유니버스 필터: 파생상품 급증 종목 제거 필터 미검 (FQ-149 precheck와 연계)",
    "④위험모델: 저베타(0.332) 구조 — 베타 예산 조정 참고값"
  ),
  frontier_update   = "FQ-147 config_scoped_negative + FQ-148(blocked_by_FQ-074) + FQ-149(frontier_open 외화자산 precheck) 등재",
  live_trigger      = "DART 전문 텍스트 파이프라인 구축 시(FQ-074 완료 후) FQ-148 재도전. 또는 외화자산/총자산 precheck에서 커버리지 충분(월 평균 100종+ 스코어) 확인 시 FQ-149 즉시 착수."
)
