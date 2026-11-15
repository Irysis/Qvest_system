# D2 정정(11-14 18:22) 재현 도구

모든 스크립트의 `SP` = 작업 폴더(입력 csv · 출력 csv). 원래 실행은 이 세션의 스크래치 폴더였다 — 다시 돌릴 땐 `SP` 를 이 `d2_fill/` 로 바꾼다.
DART 키는 `.env` 의 `DART_API_KEY` 에서 읽고 출력하지 않는다.

| 순서 | 스크립트 | 하는 일 | 출력 |
|---|---|---|---|
| 1 | `d2_dart_classify87.R` | 시총 기준으로 채운 원천 내부 87행 — DART 목록 API 로 사건 종류(이전상장 · 일반공모 · 무상 · 분할 · 감자) 분류 | `d2_dart_classify87.csv` |
| 2 | `d2_verify_naver.R` | 네이버 수정주가(siseJson) 비율 대조 + A008080 반올림 구간 검사 | `d2_verify_naver.csv` · `d2_verify_a008080.csv` |
| 3 | `d2_axis_events.R` | 측정 축 행 — 네이버 첫 날짜(= 거래소 상장일) · DART 전 공시 제목 | (화면) |
| 4 | `nv_official_batch.py` | 거래소 원주가(네이버 모바일 일별 시세 — 체결 종가 · 전일비 · 공식 등락률) | `d2_official.csv` |
| 5 | `d2_registry_build.R` | 수동 채움 등록부 재작성(행마다 method · evidence) | `06_Registry/ret_fill_registry.json` |
| 6 | `d2b_diff.R` | 적용 전후 RAWDATA 전 열 대조 | `d2b_changed_rows.csv` |
| 7 | `d2_1015_check.R` · `close_match_sample.R` · `close_match_by_month.py` | 새 결함 1 — 퀀티 종가 vs 거래소 종가 월별 일치율 | (화면) |
| 8 | `vintage_update_d2.py` | 판 원장 D2 항목 note · evidence 갱신(다른 바이트 보존) | `06_Registry/factor_db_vintage.json` |
| 9 | `vintage_finalize_d2.py` | 판 원장 항목 닫기(completed_at · note 의 진행 중 문장 → 끝난 사실 · evidence 꼬리 · 다른 바이트 보존) — D2 항목 21:40:39 · XF 채움 수리 항목 | `06_Registry/factor_db_vintage.json` |
| 10 | `check_full_by_factor.R` | 양성 대조(팩터별) — 한 달을 전 모듈로 지은 값 vs 명세 모듈 부분 빌드, 명세 대상 팩터마다 행 · 값 대조(쓰기 없음). `Rscript … <YYYYMM> <명세.json> [명세2.json …]` | `SP/check_full_<YYYYMM>.csv` |
| 11 | `vintage_add_xffix.py` | 판 원장에 D2 부작용 수리 항목(진행 중 · 범위 = 밸류 · 성장 7팩터) 추가(추가 전용) | `06_Registry/factor_db_vintage.json` |
| 12 | `requery_1115_check.py` | 11-15 퀀티 재조회 14행 판정 재현(쓰기 없음) — 행별 주식 수 비율 · 시총 기준 · A012470 토요일 · 원주가 호가 검사 · A037030 거래소 공식 시세와 상한가 산술. `python … <SP> [RAWDATA.parquet]` | `SP/requery_1115_rows.csv` |
