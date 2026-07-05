# DART document.xml 원문파서 — 파리티 검증 결과

**날짜**: 2026-07-05
**검증 대상**: document.xml 원문파서 net-buy 신호 vs 기존 elestock.json 24m 데이터
**검증 월**: 2024-12 (elestock 커버리지 내)

## 결론: PASS — 파서가 elestock 신호를 정확히 재현

| 지표 | 결과 |
|---|---|
| 매칭 리포트 (rcept_no join) | 256건 |
| **net_change_qty 정확 일치** | **256/256 (100.0%)** |
| after_qty 정확 일치 | 254/256 (99.2%) |
| reporter_name 일치 (raw) | 226/256 (88.3%) |
| reporter_name 일치 (정규화 후) | 251/256 (98.0%) |
| **ticker-month net qty 상관** | **1.0000** |
| n_buy 카운트 상관 | 0.9996 |
| net qty exact-match rate | 97.3% |

## 불일치 사유 (전부 benign — 파싱 오류 아님)

1. **reporter_name (30건)**: 순수 포맷 차이. 파서는 문서 원문의 공백 형태(`장 세 환`) 보존,
   elestock 은 압축형(`장세환`). 또는 한글약칭(`효성`) vs 법인정식명(`(주)효성`). 동일 인물.
   whitespace + 법인접미사 정규화 시 98.0% 일치. 나머지 2% 는 한글 vs 로마자(`조상현` vs
   `CHO SANG HYUN`) — DART 필드 자체 차이.

2. **after_qty (2건)**: `AFR_STK_SUM`(특정증권등 총합, 채권·워런트 포함) vs elestock
   `sp_stock_lmp_cnt`(보통주만). 파서가 더 넓은 특정증권 총합 포착. **net_change 100% 일치**로
   신호 무결성 유지 — 정의 차이지 오류 아님.

3. **파서 65건 초과**: 파서가 elestock 보다 더 완전 (같은 overlap 월에서 elestock 에 없는 리포트 포착).

## 파서 강건성 (form-version 실측)

| 연도 | Form v | 인코딩 | DOCUMENT-NAME | net_change | 결과 |
|---|---|---|---|---|---|
| 2005 | 2.8 | EUC-KR | 임원ㆍ주요주주**소유주식**보고서 | -467,230 ✓ | OK |
| 2010 | 3.1 | EUC-KR | 임원ㆍ주요주주특정증권등소유상황보고서 | -350 ✓ | OK |
| 2015 | 3.8 | EUC-KR | (동) | +285 ✓ | OK |
| 2020 | 4.0 | EUC-KR | (동) | +207 ✓ | OK |
| 2024 | 4.1 | UTF-8 | (동) | +2,280 ✓ | OK |

**핵심 강건성 발견**:
- 구조화 `ACODE="MDF_STK_SUM"`(증감 합계) 셀은 v2.8~v4.1 전 버전 일관 존재 → net-buy authoritative.
- 인코딩 자동판별(UTF-8/EUC-KR/CP949).
- **2005~2006 문서는 `소유주식` 용어**(특정증권 용어 이전) → 초기 doctype 가드가 오탈락시킨 버그 수리 완료.

## 한계 (정직 보고)

- **reporter-type 분류 (officer vs 10%주주)**: v3.1+ (2010+) 신뢰. v2.8 (2005~06) 은 `STF_RYN`/`MAIN_SH`
  필드가 sparse → 40/70 이 `other` 로 분류됨. net-buy 신호(주 알파)는 전기간 무결하나, 임원-only
  필터(국민연금 등 기계적 매도 격리)는 2010+ 부터 완전. 각 레코드에
  `old_formula_v2_reporter_fields_may_be_sparse` 플래그로 마킹.
