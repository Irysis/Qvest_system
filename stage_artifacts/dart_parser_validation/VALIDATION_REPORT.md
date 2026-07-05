# DART Insider document.xml Parser — Validation Report

**작성일**: 2026-07-05
**모듈**: `02_Infrastructure/data/dart_insider_doc_parser.R`
**진입 함수**: `parse_insider_doc(rcept_no, KEY)` → `data.table`
**목적**: elestock.json 역사 blocker(≈최근2년 cap → 역사 rows=0) 우회. 공시 원문(document.xml) 직접 파싱으로 2005~2024 인사이더 거래 추출.

> ⚠ **소싱 필수**: `source("...dart_insider_doc_parser.R", encoding = "UTF-8")`. Windows 기본 `native.enc` 로 소싱하면 소스 내 한글 리터럴이 깨져 regex 컴파일 실패(`regcomp: Invalid character range`). backfill 배선 시 반드시 encoding="UTF-8" 지정.

---

## 1. 검증 결과 (실측 — 27건, API 콜 ~60)

3개 지정 샘플(2010/2024/2007) + list.json(`pblntf_ty="D"`)에서 뽑은 6개 연도(2005·2008·2012·2016·2020·2024) × 4건 = 24건.

| 연도 | N | OK(거래) | NO_TRADES | FAIL | 거래행 수 | 인코딩 |
|---|---|---|---|---|---|---|
| 2005 | 4 | 4 | 0 | 0 | 7 | EUC-KR |
| 2007 | 1 | 1 | 0 | 0 | 5 | EUC-KR |
| 2008 | 4 | 4 | 0 | 0 | 6 | EUC-KR |
| 2010 | 1 | 1 | 0 | 0 | 3 | EUC-KR |
| 2012 | 4 | 4 | 0 | 0 | 8 | EUC-KR |
| 2016 | 4 | 4 | 0 | 0 | 4 | EUC-KR |
| 2020 | 4 | 4 | 0 | 0 | 17 | EUC-KR |
| 2024 | 5 | 5 | 0 | 0 | 9 | UTF-8 |
| **합계** | **27** | **27** | **0** | **0** | **59** | 혼합 |

**파싱 성공률: 27/27 (100%)**. 총 59 거래행. 모든 연도 커버.

**정확성 (자체 검증)**:
- 산술 정합 `변동전 + 증감 == 변동후`: **51/51 성립** (나머지 8행은 변동전 dash로 NA — 위반 0).
- 단가 present: 시장거래 43/43.
- 임원 퇴임/회사분할/주식분할 등 mechanical 이벤트도 부호·크기 정확 추출.

## 2. 포맷 변화 이슈 (실측)

1. **인코딩 선언 신뢰불가**: 2007/2010 파일은 `encoding="utf-8"` 선언인데 실제 **EUC-KR**, 2024는 실제 UTF-8. → 파서는 양쪽 readLines 시도 후 **한글이 살아있고 내용이 긴 쪽 채택**(선언 무시). 27건 전부 자동 정확 판별.
2. **데이터 셀 태그**: 값은 `<TU>`/`<TE>` (DART 추출태그)에 있음. `<TD>`/`<TH>`만 파싱하면 빈 결과. 파서는 `<T[DHUE]>` 4종 전부 추출.
3. **`&cr;` 개행엔티티**: 헤더/셀에 삽입. 키워드검색·파싱 전 제거.
4. **거래상세 표 인덱스 가변**: 2007=TABLE7, 2010/2024=TABLE9. → 표 인덱스가 아니라 **헤더 키워드(`보고사유`+`변동일`) 앵커**로 위치.
5. **컬럼 라벨 변화**: `증감`(신) vs `증감주식`(구, 2005-2007), `특정증권등의종류`(신) vs `주식의종류`(구). → 포지션 기반 파싱(라벨 무의존).
6. **증감 부호 규약 이원화**: 구포맷(2005-2010)은 증감이 **부호없는 절대값** + `보고사유 (+)/(-)` 로 방향. 신포맷(2024)은 증감 자체가 signed(`-20,000`). → 파서는 **보고사유 부호 우선 → 없으면 변동후−변동전 산술 → 없으면 증감 원부호** 3단 폴백.
7. **★dash-shift 버그(발견·수정)**: 변동전이 `-`(dash)일 때 NA compaction 이 변동후/단가를 왼쪽으로 밀어 오정렬 → 5행 오류. **포지셔널 슬롯 파싱(dash=in-slot NA)으로 수정**, 정합 51/56 → 51/51.

## 3. 임원 vs 주요주주 분리 (신호 품질 관건)

`발행회사와의 관계` 행의 `임원(등기여부)` / `주요주주` 필드로 분류. **100% 일관** (contradiction 0):

| reporter_class | is_officer | is_major_holder | 거래행 N |
|---|---|---|---|
| 임원 | TRUE | FALSE | 33 |
| 주요주주 | FALSE | TRUE | 23 |
| 임원겸주요주주 | TRUE | TRUE | 3 |

Cohen-Malloy-Pomorski(2012) 신호 분리(임원 순매수 vs 주요주주 블록딜/기계적) **가능**.

## 4. 신호 구성 준비도 — net officer buying **추출 가능**

- 시장거래(`장내`/`장외`) 43건 vs mechanical(임원퇴임·회사분할·주식분할·유상신주취득·기타·행사가액조정 등) 16건 → `report_reason` 로 필터 가능. **★신호 구성 시 mechanical 반드시 제외**(주식분할 +47.5M 등이 순매수로 오염).
- **net officer open-market flow(KRW)** = Σ(qty_change × price), reporter_class="임원", 시장거래 only → 필링별 산출 실증 완료.
  - 예: 삼성전자 20200630000669 임원 14 거래 net +2,370주(+93M KRW), 진영 20240131000638 임원 net −30,000주(−131.5M KRW).

## 5. 한계 · 리스크

1. **소싱 인코딩 의존**: `source(..., encoding="UTF-8")` 누락 시 전량 FAIL. backfill 배선 필수 조건.
2. **corp_code = DART 회사코드**(예 046430), **Ticker(종목코드) 아님**. universe 매핑엔 별도 corpcode→stock_code 조인 필요(기존 `corpcode_map.parquet` 재사용).
3. **커버리지 갭 미측정 영역**: 27건은 모두 거래표 보유. holdings-only(0거래) 필링은 코드상 `NO_TRADES` 로 fail-soft(0행+메타) 처리하나 실샘플 미확보 — 대량 backfill 시 비율 관찰 필요.
4. **파생상품/복수 종류 필링**: 신주인수권표시증서·전환사채 등 혼재 시 행별 종류는 잡히나, 순매수 신호는 **보통주 시장거래로 한정 권장**(security_type 필터).
5. **API 예산**: 필링당 document.xml 1콜. 유니버스 한정 월 ~300-500필링 → 2005-2024 대량 backfill 시 다일 소요(기존 backfill driver 의 resumable 체크포인트 재사용 권장).
6. **정직 고지**: 성공률 27/27 은 **거래표 보유 필링 대상** 수치. 전수 backfill 에서 파싱불가 포맷(스캔 PDF 첨부형 등 극소수 가능성)은 미측정 — fail-soft 로 note 남기고 skip 되므로 정지는 안 되나, 대량 수집 후 `parse_status` 집계로 실제 실패율 재확인 필요.

## 6. 산출물

- 파서: `02_Infrastructure/data/dart_insider_doc_parser.R`
- 검증 요약: `stage_artifacts/dart_parser_validation/validation_summary.csv` (27 filings)
- 파싱 거래 전량: `stage_artifacts/dart_parser_validation/all_parsed_trades.csv` (59 rows)
