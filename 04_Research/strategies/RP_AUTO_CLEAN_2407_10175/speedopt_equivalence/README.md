# 엔진 속도 최적화 — 결과 동일 실증 (RP_AUTO_CLEAN_2407_10175 · 2026-11-15)

- 결정: `06_Registry/decision_register.json#LANE-SPEEDOPT-2407-20261115` — 도훈 "머신러닝 딥러닝 쓰는건 좋은데 코드속도 최적화 필요할꺼 같네" → 측정 중단(43/322) · 엔진 가속(월 병렬 · 변형 공유 캐시 · 결과 동일 실증 · 충실도 재감사) 뒤 재측정.
- 논문: Yang & Shestopaloff (2024) arXiv:2407.10175 — 변형 `sr_opt`(대표) · `vol_min`.
- 구판(순차) = `engine.pre_speedopt.R`(레인 청정 실행 산출 · md5 `d69b17d7c9323f437ebb30fabec2b4af`) · 새 판 = `engine.R`.
- 성과 수치는 이 폴더에 없다(등급 · 수익 지표를 재지 않았다). 비교 대상은 엔진 산출(PORTFOLIO 행)과 로그 주석 · 시간뿐이다.

## 1. 진단 — 왜 느렸나

| 항목 | 실측 |
|---|---|
| 레인 실행(11-15 03:38 착수 · 09:29 중단) | sr_opt 43/322개월 · CPU 15,953초 / 벽시계 약 4.6시간 = **코어 1개**(20 논리 · 12 물리 중) |
| 달별 시간(레인 로그 `[engine] <신호일> … (N s)`) | 7~1,751초 · 꼬리가 두껍다(p 보다 EM 수렴 난도가 지배 — p 448 에 9초, p 479 에 1,751초) |
| 구조 | 신호월마다 독립 계산을 한 프로세스가 차례로 · 변형 2개가 같은 1~5단계(ADF → 분해 → SSL-EM)를 각자 다시 |
| 프로파일(2000-12-26 · 2001-04-30 · Rprof) | `.wlasso` 좌표하강 자체 시간 48~58% · ADF 15% · `.pstar`(exp) 10% |

## 2. 바꾼 것 (`engine.R` — 논문 절차 · 수치 불변)

1. **월 병렬**(§2 실행 계층) — `.fit_month(i0, i1)` 를 `.month_input`(주 프로세스가 그 달의 창 · 횡단면만 자른다) + `.fit_core`(그 입력과 상수 · 함수만 쓴다)로 나눴다. `.run_months` 가 `.fit_core` 를 PSOCK 작업자(`02_Infrastructure/ops/qv_psock.R::qv_psock_cluster` — 예약 포트 회피)에 한 달씩 동적으로 나눠 주고, 끝난 순서와 무관하게 **월 순서로** 모은다(로그 줄도 월 순서). 작업자 수 = 환경변수 `RP_2407_WORKERS` 또는 `min(PAR_MAX_WORKERS = 6, 물리 코어 − PAR_SPARE_CORES = 2)`(이 PC = 6). 작업자에는 RAWDATA 를 보내지 않는다(달마다 그 창 입력 ≈ 수 MB · 함수는 환경을 전역으로 바꿔 보낸다 — 엔진 환경째 직렬화되지 않게 · 1 MB 넘는 자료가 끼면 멈추고 순차). 클러스터를 못 열거나 도중에 끊기면 남은 달을 주 프로세스에서 순차로 돈다(같은 함수 · 같은 결과).
2. **SSL 추정 캐시** — 변형은 6단계(θ)만 다르므로 `.ssl_cointegration` 산출(P · B · steps · draws · r1)과 그 직후 난수 상태를 `<엔진 폴더>/_work/cache/ssl/<sha256>.rds` 에 둔다. 키 = sha256(SSL 함수 6개의 코드 · 그 함수가 읽는 상수 14개 · R · LAPACK · BLAS 판 · `RNGkind()` · 입력 `Cm` · `G` · `diag(G)` · `rss0` · `T` · 시드). 입력이 한 비트라도 다르면 다른 키다(데이터가 바뀌면 자동 무효 · 키에는 그 신호일까지의 창만 들어간다 — PIT 무관). 적중 = 계산을 건너뛰고 저장된 `.Random.seed` 를 되살린다. 쓰기 = 임시 파일 → 이름 바꾸기. 덮기 `RP_2407_CACHE_DIR` · 끄기 `RP_2407_CACHE=0`. `_work/cache/` 는 이미 `.gitignore` 대상이다.
3. **좌표하강 열 목록** — `.wlasso` 의 갱신 `g <- g - G[, i] * dl` 을 `g <- g - Gl[[i]] * dl` 로(`Gl` = `.ssl_cointegration` 이 달마다 한 번 만든 `G` 의 열 목록). 같은 벡터 · 같은 원소별 산술이라 결과가 같고, 갱신마다 열을 새로 잘라 내는 복사만 없어진다(실측 1.26~1.63배 · 3개월 비트 동일). 허용오차 · 반복 상한 · 알고리즘은 그대로다. Rcpp 이식 · 벡터화(좌표 순서 변경) 없음.
4. **최종 난수 상태** — 순차판은 마지막으로 SSL 2단계를 돈 달의 `set.seed` 뒤 상태를 남긴다. 새 판은 그 달의 상태(작업자 · 캐시가 돌려준 것)를 전역 `.Random.seed` 에 되살려 같은 상태로 끝난다(하네스가 뒤에서 난수를 쓰더라도 같은 입력).
5. **FIDELITY.json** — `changed` (24) 실행 계층 항목 · `constants` 에 `PAR_MAX_WORKERS` · `PAR_SPARE_CORES`(supplement · 수치 무관) · 엔진 줄 참조 27곳을 새 줄 번호로(`update_fidelity.py` — difflib 정확 대응 + 옮겨 간 코드 직접 지정 · 글자 단위 치환 · 재직렬화 없음).

## 3. 결과가 같은 이유 (구조)

- **월 독립성**(코드 판독): 구판 `.fit_month` 가 읽는 전역 = `.dates` · `.XSL` · `.dgrid` · `.bmr` · `.RETM` · `.tk_all` · 상수 · 함수 — 전부 엔진 적재 때 한 번 만들고 다시 쓰지 않는다. `<<-` · `assign` 없음. 난수는 `.ssl_cointegration` 2단계의 `set.seed(SEED + YYYYMM)` 바로 뒤 `sample.int` 뿐이다(ADF · SVD · QR · quadprog · `max.col(ties.method = "first")` · θ 단계에 난수 없음). 그래서 한 달의 결과는 다른 달 · 실행 순서 · 프로세스와 무관하다.
- **작업자 환경 = 주 프로세스**: 같은 R 4.6.2 · 같은 R 내장 참조 BLAS/LAPACK(단일 스레드 → 연산 순서 고정) · `RNGkind()` · 정렬 로케일(`LC_COLLATE` — 시총 동률일 때 종목코드 정렬) · `datatable.*` · `matprod` 등 옵션을 주 프로세스 값으로 맞춘다. 작업자의 data.table 스레드는 1(그룹 합 `sum(Weight) by Ticker` 은 스레드 수와 무관하게 행 순서로 더한다 — 그래도 시험으로 확인).
- **캐시 = 재계산**: 키가 SSL 계산이 읽는 것 전부(코드 · 상수 · 입력 비트 · 시드 · 난수 종류 · 수치 라이브러리 판)를 덮는다. 적중이면 그 계산을 다시 한 것과 같은 값이고, 난수 상태도 저장해 되살린다(`set.seed` 전에 끝난 달 = steps 0 = 상태 없음).

## 4. 등가 시험

**입력** — `prep_inputs.R`: 레인 검증기와 같은 적재(`.cache/RAWDATA.parquet` md5 `7bc9cb705a04446d9bab1ff67d9e7960` · mtime 11-15 00:14 = 레인이 03:38 에 읽은 그 파일 · `benchmark.parquet` md5 `135e9247b14874db6daf5491a9ec8285`) + 활성 epoch `all_hyg_px1000_2000_v1` 주입(`ma_inject_universe`) → 엔진이 읽는 7열(Date · Ticker · Ret · Size · K200 · KQ150 · K200_IDX)만 남긴다(행 수 14,211,157 · 행 순서 그대로). 레인 대조: 멤버 하루 중앙 1,013종 · 신호월 322개가 레인 로그와 같고, 구판의 2000-12-26 · 2001-04-30 주석(`p0=480 p=448 … draws=116` · `p0=500 p=439 … draws=135`)이 레인 로그와 글자까지 같다.

**방법** — `run_equivalence.R`: 엔진 파일을 고치지 않고 구문 분석해 최상위 식을 레인과 같은 순서로 평가하다가 마지막 '전 신호월' 식 직전에서 멈추고, 시험 월만 **그 엔진의 경로로** 돈다(old = 구판 루프 몸체 `.fit_month(.sig_lo[s], .sig_hi[s])` 를 월 순서로 · new = `.run_months(위치)` — 병렬 · 캐시 · 로그 경로 그대로). 평가 함수 프레임에 `ofile` 을 둬 `source()` 안과 같은 자기 위치 판독을 받는다. 비교 = 월마다 로그 주석 · PORTFOLIO 행(Date · Ticker · **Weight 비트 단위** `identical(num.eq = FALSE)` · Leg) · 시험 월 전체 `rbindlist` 의 `identical()` · 끝난 뒤 `.Random.seed`. 결과 원본 = `results/*.json`.

**시험 월 13개**(초기 · 중기 · 후기 · 최대 p): 2000-01-31(첫 신호월) · 2000-09-29 · 2000-10-31 · 2000-12-26 · 2001-04-30 · 2002-04-30(레인 로그 최장 1,751초) · 2008-10-31 · 2012-06-29 · 2016-03-31 · 2020-03-31 · **2021-07-30(p 최대 1,802 — 전 신호월 1~3단계 훑기 `scan_p` · p 중앙 1,030)** · 2024-07-31 · 2026-10-30(마지막 신호월).

**판정 대상 엔진**: 새 판 `engine.R` md5 `227a1f6402c74439a7afbb5417277534`(최종) · 구판 `engine.pre_speedopt.R` md5 `d69b17d7c9323f437ebb30fabec2b4af`.

| 시험 | 구판(참조 · 순차 · 캐시 없음) | 새 판 경로 | 달 | PORTFOLIO 행 | 결과 |
|---|---|---|---|---|---|
| A sr_opt | 13개월 | PSOCK 작업자 3 · 새 캐시(계산 + 저장) | 13 | 11,380 | **모두 동일**(주석 · 행 · Weight 비트 · 마지막 난수 상태) — `results/A_parallel_sr_opt.json` |
| B vol_min | 13개월 | PSOCK 작업자 3 · 캐시 적중(SSL 생략) | 13 | 11,380 | **모두 동일**(주석 · 행 · Weight 비트 · 마지막 난수 상태 · 13개월 전부 SSL 캐시 적중) — `results/B_parallel_cache_vol_min.json` |
| G sr_opt | 13개월 | 순차(작업자 1) · 캐시 적중 — 주 프로세스의 적중 · 난수 복원 경로 | 13 | 11,380 | **모두 동일**(마지막 난수 상태 포함) — `results/G_sequential_cachehit_sr_opt.json` |
| F sr_opt | 4개월 | 작업자 2 · 캐시 끔 · 기동 8초 뒤 작업자 1개 강제 종료(`kill_worker_test.ps1`) → `parallel run interrupted (error reading from connection) - remaining months in main process` → 주 프로세스가 4개월 재계산 | 4 | 1,918 | **4개월 동일** · 남은 작업자 고아 없음 — `results/F_killworker_sr_opt.json`(마지막 난수 상태 비교는 참조가 8개월 묶음이라 해당 없음 = FALSE 표기) |

네 경로(작업자 계산 · 작업자 캐시 적중 · 주 프로세스 캐시 적중 · 주 프로세스 재계산)를 모두 지났다. 앞서 같은 숫자 코드의 직전 판(md5 차이 = 종료 함수 `.par_stop` 만)으로 돈 1묶음(5개월 × 2변형)과 2개월 예비 시험도 모두 동일했다. 달마다 PORTFOLIO 지문(sha256) = 각 JSON 의 `sha256_ref` · `sha256_cand`.

## 5. 시간

같은 PC(메인 PC · 물리 코어 12 / 논리 20 · R 4.6.2 참조 BLAS) · 다른 세션 작업과 함께 돈 실측(초 · 그 달 계산만). 새 판 = 작업자 1개가 그 달에 쓴 시간(작업자 3개 동시) · 구판 = 순차 프로세스(최대 3개 동시).

| 신호일 | p | 구판 sr_opt | 새 판 sr_opt | 배율 | 구판 vol_min | 새 판 vol_min(캐시) |
|---|---|---|---|---|---|---|
| 2000-01-31 | 471 | 670 | 328 | 2.04 | 674 | 2.5 |
| 2000-09-29 | 507 | 66 | 34 | 1.95 | 79 | 5.7 |
| 2000-10-31 | 481 | 37 | 18 | 2.01 | 41 | 3.7 |
| 2000-12-26 | 448 | 9 | 7 | 1.22 | 19 | 9.9 |
| 2001-04-30 | 439 | 8 | 6 | 1.33 | 8 | 2.0 |
| 2002-04-30 | 479 | 2,032 | 1,034 | 1.97 | 2,062 | 10.3 |
| 2008-10-31 | 621 | 444 | 261 | 1.70 | 412 | 2.8 |
| 2012-06-29 | 896 | 200 | 126 | 1.58 | 202 | 3.8 |
| 2016-03-31 | 1,274 | 22 | 15 | 1.48 | 17 | 4.9 |
| 2020-03-31 | 1,287 | 20 | 17 | 1.20 | 19 | 4.7 |
| 2021-07-30 | 1,802 | 213 | 81 | 2.62 | 146 | 6.4 |
| 2024-07-31 | 1,329 | 309 | 131 | 2.36 | 214 | 5.1 |
| 2026-10-30 | 1,188 | 156 | 92 | 1.69 | 192 | 4.5 |
| **13개월 합** | | **4,186** | **2,150** | | **4,087** | **66.6** |

- 같은 달 배율(열 목록 효과) 1.20~2.62배 · 중앙 1.70배 — 병렬 · 캐시와 별개로 한 달 계산 자체가 빨라졌다.
- 묶음 벽시계: 1묶음 5개월 sr_opt = 구판 1,489초 → 새 판 319초(작업자 3) · vol_min = 1,499초 → 9초(캐시).

**322개월 × 2변형 투영**(`summarize_timing.R` · 결과 `results/timing_summary.json`): 계통 표본(신호월 12개마다 1개 = 매년 1월 · 27개월)의 새 판 sr_opt 평균 **120.0초**, vol_min(캐시) 평균 **5.5초** · 구판 = 새 판 × 같은 달 배율 중앙 1.70 · 구판 vol_min = 구판 sr_opt + (같은 달 구판 vol_min − 구판 sr_opt) 평균.

| | sr_opt | vol_min | 합계 |
|---|---|---|---|
| 구판(순차 · 변형마다 SSL 재계산) | 18.3 h | 17.6 h | **35.9 h ≈ 1.5일** |
| 새 판(작업자 6 · 캐시) | CPU 10.7 h → 벽시계 ≈ 1.8 h | CPU 0.5 h → ≈ 5분 | **≈ 1.9~2.2 h**(이상적 분배 ~ 마지막 최장 달 1,034초 꼬리 포함) |

- 투영 폭(정직하게): 레인 로그의 구판 첫 44개월 평균은 369초로 계통 표본 기반 구판 평균(≈ 204초)보다 무겁다(2000~2003 이 어려운 구간). 첫 44개월 평균을 전 기간에 쓰면 구판 ≈ 66 h(2.8일) · 새 판 ≈ 3.3 h. 요청 연기 사유의 '6~10일' 은 이보다 크다(그때 레인 PC 부하 포함 추정).
- 작업자 6개의 달별 속도는 작업자 3개 시험과 같다고 가정했다(코어 여유 · RAM 여유 전제 — P1S04 와 겹치면 느려질 수 있다).

## 6. 레인이 새 엔진을 집는 법 (코드 판독 · 레인은 돌리지 않았다)

### 6-1. 요청을 지금 그대로 두고 레인을 켜면 → 재구현(LLM)으로 간다

- 요청 `06_Registry/replication_slots/gpu1/replication_request.json`(11-15 확인): `status = pending` · `failure` 없음 · `audit_ruling` 없음 · `verify_engine_md5` 없음 · `audit_retries` 없음(0) · `lane_mode = clean`.
- `02_Infrastructure/ops/rf_replication_auto.sh` 슬롯 작업자(gpu1): 재시도 단계(246~285행) 무동작 → 상태 전이(511~536행 — `revived_verify` 없음 = `start`) → **검증기만 분기(646행)의 조건이 거짓**(`PREV_FAIL ∈ {audit_not_run, refresh_lock_deferred, audit_ruled, session_reverify, gpu_handoff, verify_interrupted}` ∨ `audit_ruling`) → 정상 경로: 프롬프트 조립 → `rf_llm_agent_run`(청정 가드)이 **엔진을 논문부터 새로 쓴다**(앞 판을 보존하라는 지시가 없다 — 새 판의 실행 계층이 사라질 수 있다) → `prov-post` → 사전검사 `rf_preaudit.py --gate` → `rp_verify`.

### 6-2. 재감사 + 측정만 하게 하는 절차 (재구현 없음)

1. (이 세션이 끝냄) `engine.R` 새 판 · `FIDELITY.json` 신고(changed 24 · constants 2 · 줄 참조) · 이 폴더.
2. 요청 파일에 세션 표식을 단다 — `"failure": "session_reverify"`(+ 권장 `"failure_detail": "LANE-SPEEDOPT-2407-20261115 — 엔진 실행 계층 가속(수치 불변 실증 speedopt_equivalence/) · 재감사 + 측정만"`). `status` 는 `pending` 그대로 둔다.
   - `session_reverify` = 레인이 아는 세션 표식(646행 분기 · 636~637행 주석 "세션이 '엔진 결함이 아니라 검증 계기 결함'으로 판정해 고친 뒤 붙이는 표식 … 재구현 에이전트를 다시 사지 않고 검증기만"). 이번은 실행 계층 수리라 같은 처분이 맞다.
   - `audit_ruling` 은 **넣지 않는다**(감사 관문이 감사를 다시 사지 않는 표식이다 — 엔진 지문이 바뀌어 어차피 무시되지만 의미가 틀린다). `audit_retries` · `auto_retries` 는 손대지 않는다.
3. 레인을 켠다 — `06_Registry/reinforce_auto_config.json` `replication_lane.enabled = true`(오케스트레이터 세션 몫 · 지금 false · 슬롯 설정 `{"cpu": 0, "gpu": 1}` · `not_before` 없음).
4. 다음 틱(예약 작업 Qvest_ReinforceAutoLoop → 디스패처 `rf_replication_slots.py tick`)이 gpu1 을 띄운다 — ★**GPU 임대가 비어 있을 때만**(`_tick` 의 `lease_blocks` → `hold = gpu_lease` · 작업자 474~483행 `halt_gpu_lease` · 지금 임대 `free`). 이 논문은 엔진 의존성으로 이제 `cpu` 로 분류되지만(`rf_replication_slots.py classify` 실측 `cpu engine_dependency`) 요청이 gpu1 에 있고 CPU 슬롯이 0 개라, P1S04 DNN 측정이 GPU 임대를 쥐면 그동안 기다린다.
5. 작업자 경로: 상태 전이 → 검증기만 분기 → 저널 `verify_only_retry`("세션 판정 — 검증 계기 결함 수리 뒤 재검증(엔진 보존 · 에이전트 재스폰 없음)") → failure 필드 비움 → `rp_verify` → `rf_replication_verify.R`:
   ① PIT 정적 검사 `detect_lookahead`(새 판 clean · 0건 — 실측) ② 패키지 스캔(새 판 = data.table · quadprog · tseries · codetools · 전부 설치됨 — 실측. ★`La_library()` 를 그대로 쓰면 스캐너가 `library(` 로 읽어 `NA` 패키지 설치 → `dependency_install_failed` 가 났다 — `do.call("La_library", list())` 로 피했다) ③ **감사 관문 `rf_audit_gate`** — 낡은 `fidelity_audit.json` 을 지우고 `rf_fidelity_audit.sh` → `rf_fidelity_fanout.sh`(6축 · 청정 모드 = 산출물 비공개)를 새로 띄운다(`fidelity_audit.enabled` · `fanout.enabled` = true) ④ 통과(proceed · proceed_suspect)면 측정 — 대표 `sr_opt` → 변형 `vol_min`(같은 검증기 프로세스 · SSL 캐시 적중).
6. 감사가 재구현 처분(misdeclared)을 내면 요청이 같은 논문 pending + `audit_feedback` 으로 돌아가고 다음 실행은 **재구현(LLM)** 이다 — 그 판은 실행 계층을 잃을 수 있다. 그래서 실행 계층을 FIDELITY changed(24)에 신고했다(선례: `RP_AUTO_2002_06975` 의 작업자 · 내용 주소 캐시 신고 — 감사 통과).
7. 측정 중 로그(`.cache/scheduler_logs/replication_auto_<날짜>_gpu1.log`): `[engine] exec: 6 PSOCK workers (port …) · ssl cache …` → 달마다 `[engine] <신호일> <주석> (N s)`(월 순서 · 캐시 적중이면 ` [ssl cache]`) → `[engine] exec: months=322 · workers=6 · ssl from cache=… · wall …s`. 메모리 = 검증기(RAWDATA 전 열) + 작업자 6 × 약 0.2~0.5 GB.

## 7. 구현 에이전트 프롬프트 지침 초안 (적용하지 않았다)

넣을 곳: `02_Infrastructure/ops/rf_replication_auto.sh`(지금 md5 `bd17de37b354d3b7a71d33c8b8859b28`) 의 `PROMPT="…"` 안 `## 실행 환경` 절 마지막 줄(898행 `- 원문 접근이 불가하거나 논문을 훼손하지 않고는 …`) 바로 뒤 · `## 금지`(900행) 앞. PROMPT 는 큰따옴표 bash 문자열이라 아래는 그 안에 그대로 붙일 수 있게 썼다(백틱 · 큰따옴표 이스케이프 · `${WDIR}` 는 의도한 전개). 청정 레인 구현자는 셸이 없어 직접 시간을 잴 수 없으므로 '시간을 남긴다' 는 엔진이 측정 때 찍는 로그 줄을 뜻한다.

```text
- ★계산 속도 — 수치를 바꾸지 않는 가속은 구현자의 몫이다(2026-11-15 도훈 '머신러닝 딥러닝 쓰는건 좋은데 코드속도 최적화 필요할꺼 같네' · decision_register LANE-SPEEDOPT-2407-20261115).
  실측: 2407.10175 첫 판은 20코어 중 1코어로 신호월 322개 × 변형 2개를 차례로 돌려(변형마다 같은 SSL 추정을 다시) 6~10일이 걸릴 참이었다.
  ① **신호일(리밸런싱일)끼리 독립이면 병렬로 돌린다.** 한 신호일 계산이 그날까지의 창 · 상수만 읽고 다른 신호일의 결과 · 전역 상태를 쓰지 않으면 독립이다.
     난수는 신호일마다 고정 시드(예: SEED + YYYYMM)로 그 계산 안에서 set.seed 한다 — 어느 프로세스 · 어느 순서로 돌려도 같은 결과가 나온다.
     (앞 신호일 결과를 초기값으로 이어 쓰는 웜스타트 · 신호일을 가로지르는 난수열은 독립이 아니다 — 논문이 그렇게 하면 순차로 두고 changed 에 적는다.)
     R: \`source(file.path(Sys.getenv(\"QM_ROOT\"), \"02_Infrastructure/ops/qv_psock.R\")); cl <- qv_psock_cluster(n)\` — makePSOCKcluster · makeCluster 직접 호출 금지(예약 포트) ·
     작업자에는 그 신호일의 입력만 보낸다(RAWDATA 통째 금지 · 작업자로 보내는 함수는 \`environment(f) <- globalenv()\` — 엔진 환경째 직렬화되지 않게) ·
     작업자는 주 프로세스의 RNGkind · 정렬 로케일 · data.table 옵션을 그대로 쓰게 한다 · 결과는 신호일 순서로 모은다 ·
     작업자 수 기본 = min(6, 물리 코어 − 2)(환경변수로 덮게) · 클러스터를 못 열거나 끊기면 같은 함수를 순차로 돈다.
     파이썬: 프로세스 풀(작업자마다 torch · OMP 스레드 1 · 선례 RP_AUTO_2002_06975).
  ② **변형끼리 같은 계산은 캐시로 나눠 쓴다.** 변형이 마지막 단계(비중 · 결합 · 손실)만 다르면 그 앞의 비싼 결과를 \`${WDIR}/_work/cache/\` 에
     내용 주소로 둔다 — 키 = 코드 · 상수 · 시드 · 난수 종류 · 입력 바이트의 해시(입력이 한 비트라도 다르면 다른 키 · 키에는 그 신호일까지의 입력만 = PIT) ·
     쓰기 = 임시 파일 → 이름 바꾸기(원자) · 다음 변형 · 재실행이 그 키로 읽는다 · 그 계산이 난수를 쓰면 직후 난수 상태도 함께 둔다.
  ③ **수치는 바꾸지 않는다.** 허용오차 · 반복 상한 · 알고리즘 · 모형 · 학습 절차를 줄이거나 바꾸는 것은 가속이 아니라 핵심 모델 훼손이다('모든 방법론' ④).
     같은 연산을 덜 복사하는 것만 가속이다 — 병렬 · 캐시 판과 순차 판의 산출이 비트 단위로 같아야 한다.
  ④ **시간을 남긴다.** 신호일마다 \`[engine] <신호일> <진단 주석> (초)\` 한 줄을 신호일 순서로 낸다(측정 로그가 병목을 보여 준다).
  ⑤ 실행 계층(작업자 수 · 캐시 위치 · 끄는 스위치)도 FIDELITY.changed 에 '실행 계층 · 수치 무관' 항목으로 적고 최상위 숫자 상수는 constants 에 올린다.
```

보조로 고려할 곳(초안 · 적용 안 함): 감사 축 정본 `06_Registry/rf_fidelity_axes.json` 의 undeclared 축이 '실행 계층(병렬 · 캐시)은 논문 절차 변경이 아니다 — 신고만 확인' 을 알게 하면 이번 같은 가속판의 재감사 오탐 위험이 준다.

## 8. 재현

```
S=<스크래치 폴더>; E=04_Research/strategies/RP_AUTO_CLEAN_2407_10175/speedopt_equivalence
Rscript <절대경로>/$E/prep_inputs.R $S/inputs.rds                      # 레인과 같은 입력(엔진이 읽는 7열)
Rscript <절대경로>/$E/run_equivalence.R run old sr_opt  $S/inputs.rds $S/old_sr.rds  <YYYY-MM-DD,…>
RP_2407_WORKERS=3 RP_2407_CACHE_DIR=$S/cache Rscript <절대경로>/$E/run_equivalence.R run new sr_opt  $S/inputs.rds $S/new_sr.rds <같은 날짜>
RP_2407_WORKERS=3 RP_2407_CACHE_DIR=$S/cache Rscript <절대경로>/$E/run_equivalence.R run new vol_min $S/inputs.rds $S/new_vm.rds <같은 날짜>   # 캐시 적중 경로
Rscript <절대경로>/$E/run_equivalence.R compare $S/old_sr.rds $S/new_sr.rds results/<이름>.json
python $E/update_fidelity.py            # FIDELITY 줄 참조 미리 보기(--write 로 적용)
```

## 9. 확인하지 못한 것 · 주의

- **청정 출처 표식이 어긋난다(사실 기록 · 고치지 않았다)**: `lane_provenance.json` 의 `post.engine_md5` = `d69b17d7…`(구판)는 새 판과 다르다 → `02_Infrastructure/reinforcement/rf_runner_gates.R::rf_engine_clean_verified()` 가 이 엔진을 '청정 실행 뒤 수정' 으로 본다. 이 판정을 지금 쓰는 곳은 A 관문의 기저 표식 전파 면제(lineage · same_engine 경로) 하나다 — 이 논문 entry 에는 기저 표식이 없어 당장 결과 차이는 없다. 사후 청정 재도출 검사(`rf_clean_base.R`)는 10-13 정리로 삭제돼 없다. 검증기는 `post` 를 대조하지 않는다(검증기만 경로는 그대로 돈다). 세션이 손댄 엔진이라는 사실을 출처 기록이 그대로 보여 주는 것이 맞다고 보고 기록을 덮지 않았다 — 청정 인정이 필요하면 도훈 · 오케스트레이터 판단.
- **전 기간(322개월) 실측은 하지 않았다** — §5 의 322개월 × 2변형 시간은 투영이고 가정을 적었다. 레인 재측정이 실측한다.
- **시험 월은 일부다** — 나머지 달로의 일반화 근거는 월 독립성(§3 구조)이다. 어느 달이든 같은 코드 경로(작업자 계산 · 캐시 읽기 · 주 프로세스 재계산)를 지나고, 시험은 그 네 경로를 모두 지났다(§4).
- **클러스터 기동 실패 경로**(포트 · 루트 판독 불가 · 작업자 준비 실패)는 코드 판독만 했다 — 순차 경로(시험 F 가 지난 그 경로)로 떨어진다.
- **로그 줄은 월 순서로만 나온다** — 앞 달이 오래 걸리면(이 논문 최대 약 30분) 그동안 줄이 멈춘 것처럼 보인다(계산은 진행 중). 진행 확인 = 작업자 Rscript 의 CPU 시간 또는 `_work/cache/ssl/` 파일 수.
- **자원**: 레인 기본 작업자 6개 = 코어 6개 + 작업자당 약 0.2~0.5 GB(시험 중 관측 0.16~0.23 GB). 검증기 본체(RAWDATA 전 열)는 그대로다. P1S04 DNN 측정과 겹치면 RAM 을 확인할 것(작업자 수 = `RP_2407_WORKERS`).
- **캐시 파일**: 항목당 약 15 KB(시험 실측 평균 14.8 KB) × 322 ≈ 5 MB 가 `_work/cache/ssl/` 에 생기고 OneDrive 가 동기화한다(`.gitignore` 대상). 시험 캐시는 스크래치 폴더에만 썼다(레인 캐시는 비어 있다 — 레인이 처음부터 직접 계산한다).
- **환경을 바꾸면 캐시는 자동 무효** — 키에 R · LAPACK · BLAS 판이 들어 있다(다시 계산 = 안전한 쪽).
