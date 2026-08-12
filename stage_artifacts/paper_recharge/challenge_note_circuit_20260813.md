# Self-Adversarial Challenge — T11_CIRCUIT_HIT_UPPER_21D
# AX-008 요구 / 2026-08-13

## 점검 항목

### 1. 상한가 기준 날짜 분기가 PIT 위반하지 않는가?
**결론: PIT SAFE**
- 2015-06-15 제도 변경은 KRX 공식 발표 후 시행된 역사적 사실
- 코드에서 `Date < CHANGE_DATE`로 분기 → 당일 Date를 기준으로 과거 제도를 조회
- 이는 그 시점에 투자자가 실제로 알고 있던 제도이므로 미래참조 아님
- 단, 제도 변경 당일(2015-06-15) 포함 경계는 `Date < "2015-06-15"` → 변경 전(1.15) 적용. 이는 보수적이며 PIT-safe.

### 2. 희소 신호에서 top-25 선택이 사실상 유동성 정렬인가?
**결론: 핵심 위험, 명시적 보고 필요**
- KOSPI200 대형주의 일일 ±15%/±30% 상한가 경험은 매우 희소
- 월 21거래일 중 상한가 경험 비율 > 0인 종목이 5% 미만이면 대부분 Score=0
- Score가 균일 0이면 top-25 선택은 데이터 순서(=유동성 상위)로 결정 → BM과 무차별
- 대응: factor_engine에 희소성 경고 내장 (pct_nonzero < 5% 시 WARNING 출력)
- KOSDAQ150은 변동성 높아 일부 hits 가능하나 여전히 제한적
- **판정 가이드**: 희소성 경고 발생 시 "신호 희소 → IC 구조적 0"으로 기록

### 3. net_circuit_ratio의 음수 신호가 long-only에서 어떻게 처리되는가?
**결론: 주력 신호(상한가만)로 대체, net 신호는 제외**
- net_circuit_ratio = (upper_hits - lower_hits) / n_valid_days
- 하한가 경험이 많으면 Score < 0 → top-25 선택이 음수 Score 종목 선택 가능
- Long-only 전략에서 음수 신호를 그대로 쓰면 의도치 않은 역선택 발생
- 대응: 주력 신호을 circuit_hit_upper_21d (상한가만, 항상 ≥ 0) 로 고정
- net 신호는 factor_engine에 `.score_net`으로 보조 계산하나 FACTORS 출력에는 미포함
- 두 번째 실행이 필요하면 별도 factor_engine_net.R로 분리 필요

### 4. 2015 전후 제도 변경이 IS/OOS 분할에 구조 파손을 일으키는가?
**결론: 구조 파손 가능성 있음, 진단용 분류 필요**
- IS: 2005-2015 (10년, ±15% 제도)
- OOS 구간 일부 or 전체: 2015-현재 (±30% 제도)
- ±30% 체제에서 대형주 상한가 발생은 더욱 희소 → OOS에서 신호 강도 추가 약화
- 결과 해석 시: 제도 변경 전후 sub-period 결과를 분리 기록 권고
- 단, run_alpha_search의 자동 OOS split이 2015 근방이면 두 체제가 IS/OOS에 혼재할 수 있음
- **이는 전략 결함이 아니라 현실 시장 조건의 변화로 정직 보고**

### 5. PIT sig_date 포함 여부 — 추가 점검
**결론: 코드에서 lag 1 추가 적용으로 보완됨**
- 원래 frollsum(upper_hit, 21) 적용 시 sig_date 당일 upper_hit 포함 위험
- 대응: `.uh_lag1 = shift(upper_hit, 1L)` 후 frollsum(21) → sig_date 직전 21일 집계
- 즉 실제 집계 범위 = [sig_date - 22 거래일, sig_date - 2 거래일] (sig_date 자체 및 t-1 제외)
- 이는 충분히 conservative한 접근

### 6. lookahead_detector가 잡지 못하는 PIT 위험
**결론: 해당 없음 (순수 가격 데이터 기반)**
- 외부 parquet/cache 의존 없음 → fe_ml 우회 경로 없음
- 모든 신호는 RAWDATA의 Close, Date 컬럼만 사용
- prevClose = lag(Close, 1L) → 명확한 PIT 보증

## 최종 판단
- PIT: PASS (lag 처리 적절, 제도 변경일 분기 PIT-safe)
- 핵심 위험: 희소성 (KOSPI200에서 상한가 hit는 구조적으로 드뭄)
- 예상 결과: IC 구조적 0 가능성 높음 → "신호 희소" FAIL 가능
- 그럼에도 실측이 의무: 가능성만으로 사전 기각 금지 (AX-000)
- KOSDAQ150에서 상한가 hits 일부 존재 시 약한 신호 가능성 열려 있음

## 작성자: Q-Lead / 2026-08-13 AlphaSearch Autorun
