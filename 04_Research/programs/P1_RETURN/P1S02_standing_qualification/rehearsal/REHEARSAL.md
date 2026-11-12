# P1S02 등록 전 리허설 — 판정 경로를 싼 엔진으로 한 번 끝까지(판단 T1 C-20261111-085)

> 리서치 산출이 아니다. 판 2 의 측정 · 판정 경로가 실자료에서 한 번도 끝까지 지난 적이 없어서(판 1 은 판정 0건), DNN 시드(지속 25~33 GB · 측정 5~6시간)로 처음 지나다 결함이 나오면 새 판 + GPU 재측정이 된다. 그 전에 싼 CPU 엔진으로 같은 경로를 격리해 지난다.
> 성과 값은 찍지도 싣지도 않았다 — 통과 여부 · 유한 여부 · 개수 · τ_D(2022-12-31) 이전 날짜 · 상태 문자열만. 판정 · 보고 원문은 `out/<run>/` 아래 파일에만 있다(커밋하지 않는다).

## 1. 무엇을 지났나

| 단계 | 하는 일 | 실제 / 대체 |
|---|---|---|
| S0 | 격리 단정 — `rc_root` = 저장소 · 코어 v3 적재 · `RC_SA_ROOT` = `out/<run>/sa` · 공유 원장(판단 · 결정 · 재개)에 리허설 표식 0 | 실제 |
| S1 | 리허설 판 `P1SR02_rehearsal` — 판 2 사양(`round_spec.json`)을 그대로 복제하고 칸만 리허설 엔진 1칸(reference)으로 · 칸 사양 = 등록된 생성 함수 `rc_p1_cell_spec` · `rc_standing_validate`(생성 함수 핀 포함) | 실제 |
| S2 | 초안 → 점검 기록 → 등록 — 점검 파일 · 철학 P1 리뷰는 스텁(격리 판단 원장 · 리뷰 뿌리) · `check_git = FALSE` · `run_tests = FALSE` · 등록부 = 실제 등록부 사본 | 점검 · P1 = 스텁 |
| S3 | `scan` — 레인 디렉터리 실물을 읽되 `max_new = 0`(시드만 넣는다) | 실제(읽기) |
| S4g | GPU 관문 판별(`rc_gpu_guard` — 레인 정본 판별기) — 리허설 엔진 = cpu · 임대 없음 | 실제 |
| S4a | `measure-item` — 실제 신선도 관문. 낡음이면 측정 없이 `data_stale` · 원장 무기록이어야 한다(음성 대조) | 실제 |
| S4b | (S4a 가 낡음일 때만 · `--inject-fresh`) 같은 `measure-item` 을 신선도 함수만 주입해 한 번 더 — 실제 셀 워커(`rf_cell_worker.R` → `run_paper_replication`) · 실제 자료 · 실제 지문 앞뒤 대조 · 측정 관문(기저 정합 `base_alignment` · 점수 패널 · 월말 격자) | 신선도 = 주입 |
| S5 | 판정 전 점검 10항목 — 판 2 도구 `tools/prejudge_check.R` 그대로(`--eval --round-dir --registry` · 자식 프로세스) | 실제 |
| S6 | `judge` — 칸 평가 캐시(S5 의 `--eval` 이 쓴 것) → 등록 규칙 기계 적용 → 판정 원장 · 판정 파일 · `standing_visible.json`(τ_D 뒤 날짜 검사) | 실제 |
| S7 | `standing-report` 드라이런(`send = FALSE` · `QVEST_TG_DRY_RUN = 1`) — 원장에 `reported` 가 남지 않아야 한다 | 실제(발송 없음) |
| S8 | `standing-status` 줄 · 원장 md5 사슬 검증 | 실제 |
| S9 | 격리 증명 — 실제 파일 앞뒤 md5 · 판 1 · 판 2 폴더(리허설 폴더 제외) 해시 · 공유 원장 표식 | 실제 |

리허설 엔진 = `engine/RP_REHEARSAL_MOM121/engine.R` — 월말 거래일마다 전 종목 12-1 모멘텀 `FACTORS(Date, Ticker, Score)`(RAWDATA 의 Date · Ticker · Ret 만 · `.RP_START_DATE` 가 없으면 멈춘다 = 시작일 전달 경로 시험). 형성 창 관행 = Jegadeesh & Titman(1993), https://doi.org/10.1111/j.1540-6261.1993.tb04702.x .

## 2. 결과(2026-11-12 밤 · 세션 local_9fa47fd9 · 코어 v3 매니페스트 4d00113a)

**통과 — run `20261112_212912`: 12단계 전부 pass · 결함 0 · 3.8분**(요약 `rehearsal_summary.json` · `ok = true`). 리허설 엔진 md5 `115790a4` · 칸 사양 md5 `6265f7f0`.

| 단계 | 결과(값 없음) |
|---|---|
| S0 · S9 | 격리 단정 · 증명 통과 — 실제 파일 10개 앞뒤 md5 같음(실제 사전등록 뿌리에 리허설 판 없음) · 판 1 · 판 2 폴더(리허설 폴더 밖) 해시 같음 · 공유 원장 표식 0/0/0(허용 id = J-20261112-003 — 아래 '실행 이력') |
| S1 · S2 | 판 2 사양 복제 → `rc_standing_validate`(생성 함수 핀 포함) 통과 → 초안 v1 → 점검 기록 → 등록(임시 등록부 기록 1 · 사전등록 두 사본) |
| S3 | 레인 디렉터리 51 읽음 · 입구 통과 0 · 넣은 항목 = 시드 1(`max_new = 0`) |
| S4g | GPU 관문 = cpu(레인 판별기 `engine_dependency … GPU 프레임워크 없음`) · 임대 없음 |
| S4a | **실제 신선도 관문 = 낡음**(RAWDATA · 기준일 2026-11-11 — 11-12 밤 갱신이 OHLCVS 적재 거부(not_advanced) 뒤 로그오프로 중단) → `data_stale` · 원장 줄 2 → 2(무기록) = 음성 대조 통과 |
| S4b | 신선도만 주입 → 실제 워커 ok · rc 0 · 지문 앞뒤 같음 · 1.6분 · 측정 관문 통과: `base_alignment` = `month_snap_v1` · `base_kind = factors` · 엔진 신호일 323(첫 2000-01-31) → 월말 323 · 옮김 0 · 덮임 0 · 달력 밖 0 · 시작일 2000-01-01 주입 · 기저 캐시 적중(run 2 는 미적중 — 두 길 다 지났다) |
| S5 | 판정 전 점검 10항목 '이상 없음'(종료 0): 키 파일 5 · 축 감사(최대 25/25 · 최소 비중 · Σw ≤ 1) · 실효 시작 2000-01-31(상태 ok) · 기저 정합 · β-통제 알파 보는 창 유한(n 275) · 칸 평가 evaluated(보는 창 2000-02-02~2022-12-29 · 위기 13 · 강세 8 · 상승 포착 유한) |
| S6 | `judge` → 판정 줄 · 판정 파일(사람 쪽) · `standing_visible.json`(τ_D 뒤 날짜 0) |
| S7 | 보고 드라이런 23줄 · 원장 `reported` 0 · 발송 없음 |
| S8 | 상태 2줄 · 원장 md5 사슬 정상(4줄) |

- 코어 v3 · 판 2 도구 · 운영 파일에서 **결함을 찾지 못했다** — 고친 것 없음(코어 무수정).
- 판정 경로 밖 경고 2종(워커 stderr · 점검 stderr): `table.Drawdowns` 'Only 7 available'(낙폭 구간 수가 요청 상한보다 적다는 안내) · tidyselect `all_of()` 권고(외부 벡터 선택 문법) — 둘 다 값 · 판정에 닿지 않는다.

### 실행 이력(같은 날 3회 — 모두 out/ 아래)

1. `20261112_212252` — S1 에서 멈춤: 리허설 판 id `P1S02RH_rehearsal` 가 사양 형식(`^P[0-9]+[A-Z]*[0-9]+_[a-z0-9_]+$` · spec.R:17)에 맞지 않았다(리허설 스크립트 쪽 이름 문제 · 코어 정상). id 를 `P1SR02_rehearsal` 로 바꿨다. 이 실행 폴더는 지웠다.
2. `20261112_212343` — S0~S8 pass · **S9 fail(공유 원장 표식 1)**. 표식 위치를 찾으니 판단 원장의 J-20261112-003 하나 — 리허설이 도는 도중 Q 가 이 리허설의 설계 판단을 손으로 기록하면서 본문에 판 이름을 적었다(리허설이 쓴 것이 아니다). 검사를 고쳤다: `--allow-ledger-ids` 로 받은 판단 id 만 판단 원장 대조에서 빼고, 뺀 id 를 요약 `isolation.allowed_ledger_ids` 에 남긴다.
3. `20261112_212912` — 전부 pass(위 표). 교훈: 리허설이 도는 동안 공유 원장에 리허설 이름이 든 기록을 남기지 않는다 · 남겼으면 그 id 를 명시해 뺀다.

## 3. 재현

```bash
# 저장소 루트에서 · 무거운 R 작업이 없을 때 · 밤(00:03)/아침(07:10) 체인 창 밖
Rscript 04_Research/programs/P1_RETURN/P1S02_standing_qualification/rehearsal/rehearse.R            # 신선도가 '신선'이면 S4 한 번
Rscript 04_Research/programs/P1_RETURN/P1S02_standing_qualification/rehearsal/rehearse.R --inject-fresh   # 낡음이면 S4a 음성 대조 뒤 S4b(배선 시험)
```

- 실행마다 `out/<YYYYmmdd_HHMMSS>/` 에 새 격리 판 · 사전등록 뿌리 · 등록부 사본 · 원장이 생긴다(앞 실행과 섞이지 않는다). 요약은 `out/<run>/rehearsal_summary.json` 과 `rehearsal/rehearsal_summary.json`(마지막 실행 · 커밋 대상 · 초안 v2 의 `rehearsal` 이 읽는다) 두 곳.
- 워커 산출은 실제 `stage_artifacts/replication/<run_id>/` 에 생긴다(러너 정본 위치 · 지우지 않는다). 역할 reference 라 2계층 풀 등재 · 팩터 분석 · L-code · 강화 원장 auto-open 은 꺼진다(`rc_standing_measure_item` · 워커 환경변수).

## 4. 격리 — 무엇이 실제에 닿지 않았나

- 사전등록 · 상설 원장 = `RC_SA_ROOT`(`out/<run>/sa/stage_artifacts/…`) — 실제 `stage_artifacts/programs/P1_RETURN/` 의 판 1 원장 · 판 2 자리 · 리허설 판 자리는 앞뒤 md5 가 같다(S9).
- 등록부 = 사본(`out/<run>/iso/research_programs.json`). 실제 등록부는 다른 프로세스(레인 인계 · 아침 체인)가 쓸 수 있어 '바뀌었으면 리허설 표식이 없는가'로 판정한다(S9).
- 판단 원장 = 스텁(`out/<run>/iso/ledger.json`) · 철학 P1 리뷰 = 스텁 파일(`out/<run>/iso/rv/…`) · 격리 점검 = 스텁 파일. 실제 판단 원장 · 결정 기록부 · 재개 저널에는 리허설 표식(`P1SR02_` · `rehearsal.p1s02.mom121`)이 없다(S0 · S9).
- 텔레그램 = 드라이런(`QVEST_TG_DRY_RUN = 1` · `send = FALSE` · 출력은 `out/<run>/report_dryrun.txt`).
- 판 1(`P1S01_…`) · 판 2 폴더(이 `rehearsal/` 밖) = 앞뒤 해시 같음(S9). 판 2 의 실제 시드 측정은 신선도 주입 없이 실제 관문을 지난다(주입은 이 스크립트의 S4b 안에서만 · 함수 인자 — 전역 설정 · 파일 변경 없음).
