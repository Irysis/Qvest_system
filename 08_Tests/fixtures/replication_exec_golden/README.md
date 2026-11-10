# 골든 재핀 기록 — `20260921_100007_6876`(22632 promo3 B1_3 liq_price_delay · legacy 규약)

소비 스위트: `08_Tests/contracts/test_replication_exec_golden.R` · `08_Tests/contracts/test_remeasure_from_holdings.R`

## 재핀 1 — 2026-11-10 (시험 정비)

**파일**: `ref_legacy_20261110.rds` = `list(bt = <build_bt_result + audit_bt_result 결과>, pin = <출처 표식>)`
- 만든 길: `test_replication_exec_golden.R` 의 `run_all("close_d_legacy")` 그대로(저장 `factors_panel.parquet` → 비중 = 저장 보유와 비트 일치 · `run_replication_simulation` · 러너와 같은 `build_bt_result` 인자 · `essence_score(chain, 1)`).
- 입력: `.cache/RAWDATA.parquet`(md5 `2b7e1330e59e48824a42618df4d36158` · `Date <= 2026-09-18` 절단 · 14,116,572행) · `.cache/benchmark.parquet`. 개정 가능 경계 REV0 = 2026-03-30.
- 값: 5,337일 · grade A(등급 규칙 v3.3) · CAGR 0.275 · SR 1.136 · MDD 0.551 · Calmar 0.500 · PORT_t 4.336 · OOS 0.115 · IR 0.949. 기간 2005~2026-09 전체(2023-01~ 시험 창 포함).
- close_t1 판(`test_remeasure_from_holdings.R` C2 · C4 · C6a 상수): grade C · PORT_t 3.772 · Calmar 0.432(같은 데이터 · 계약 `rfh_remeasure` 경유).

**왜 바뀌었나(재도출 · 저장 `bt_result.rds` 09-21 = 5,336일 · PORT_t 4.349 · Calmar 0.501 대비)**
1. **2024-12-30 거래일 복원** — 커밋 `48b3d3bfd`(2026-10-17 · 도훈 '하루 복원해'). RAWDATA 에 2024-12-30 행 2,504개가 생기고 2025-01-02 Ret 2,292개가 바뀌었다(구 01-02 Ret = 새 12-30 · 01-02 두 날 복리, max|Δ| 2.2e-16). 벤치도 12-30 추가 · 01-02 변경. → 축 +1일(경계 앞이라 구 VINTAGE 판정으로 못 넘긴다 = 구판 빨강의 직접 원인).
2. **퀀티 OHLCVS 재수출(10-17)** — 경계 2026-03-30 뒤 행 교체(저장 대비 ret_net max|Δ| 0.0109 · 차이 첫 날 2026-07-01). 시험 머리에 원래 적혀 있던 '빈티지 개정' 사례.
3. **등급 규칙** — 저장 authoritative 의 등급 B → A 는 등급 v3.3(2026-11-10 · 커밋 `63a4433b3` · OOS 관문 교체 GRADE-V33-OOS-TEST-WINDOW-CALMAR)이다. close_t1 판 B → C 는 등급 v3 승격(2026-10-13 · GRADE-V3-PROMOTE · 위기 복원력 약함 노치 −1)이다. 숫자에는 닿지 않는다.

**검증(원인이 이것뿐임)**
- 복원 전 백업(`.cache/backup_cal20241230_20261017_175419/` RAWDATA · benchmark)으로 같은 스크립트를 돌리면 5,336일 · 경계 앞 5,217일 ret_net 비트 동일 · 차이 첫 날 2026-07-01(③ = 빈티지 SKIP · ③p · ③c PASS · FAIL 0). 계약 `rfh_remeasure` 경로도 같다(경계 앞 차이 0 · close_t1 은 09-25 운영 판과 경계 앞 max|Δ| 3.75e-16).
- 백업 → 현행 RAWDATA(`Date <= 2026-09-18`) 차이 = 위 1(경계 앞 전부) + 경계 뒤 526행 변경 · 4행 소멸(2026-03-30). 그 밖 없음.
- **팩터 DB 수리(재무 v2 · 방향 · 총부채 0)와 무관** — 이 골든의 비중은 저장 `factors_panel.parquet`에서 오고(저장 보유와 비트 일치), 팩터 DB 를 읽지 않는다.

**다시 만들 때**: 시험이 경계 앞 차이로 빨강이면 먼저 원인을 재도출한다(코드 회귀가 아니라는 증거 없이는 재핀 금지). 재핀은 `test_replication_exec_golden.R` 112행까지(`L <- quiet(run_all(...))`) + `saveRDS(list(bt = L$bt, pin = ...), ...)` 로 만들고(약 1분 · 쓰기 = 이 폴더뿐), 이 파일에 '재핀 n'을 덧붙인다. 운영 산출물(`stage_artifacts/...`)은 건드리지 않는다.
