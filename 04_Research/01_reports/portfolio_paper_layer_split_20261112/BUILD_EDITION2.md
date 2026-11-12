# 판 2(P1S02) 구축 — 계획과 진행 기록

설계 정본 = 같은 폴더 `README.md`(§2 사실 · §6 정합 · §8 실행 순서와 판정 전 점검). 이 파일은 구축 작업의 순서 · 설계 결정 · 진행 상태를 적는다. 세션이 바뀌거나 맥락이 요약돼도 여기서 이어 간다.

## 승인과 범위

- 도훈 "이어서 시작"(11-11 22시대 · 질문 = 판 2 구축을 분류 세션에서 이어서 시작할까요) — 재개 저널 `OP-20261110-V102-LADDER` 22:09 로그 · 측정 세션 커밋 `8f276b3f2`.
- 승인 범위 = 설계 §8 의 2 → 3 → 4: 레인 출력 계약 → 셀 경로 정합 → 판 2 등록 → 시드 측정 → 1908.01112 점수 패널 패치 → 레인 재측정 → 판 2 스캔 · 판정 · 보고.
- 범위 밖(따로 여쭐 것): §8 의 1(카탈로그 3종) · 5(추정기 축) · 7(노출 규칙 · P2 상설 판). §8 의 6(라우터 꼬리표)은 이번에 하지 않는다 — 레인 프롬프트 교체 한 번에 넣을 만큼 급하지 않다.

## 지킬 것

- PIT C1~C15 · τ_D 2022-12-31(입구 · 선택 규칙은 성과를 읽지 않는다) · 등급 문턱 완화 금지 · `05_Production/` · `01_Literature/` 무수정 · BOOK 자동 등록 금지 · Grade A 전 Judge 스폰 금지.
- 측정 계약: 권고안 (가). 면제 확장은 하지 않는다. 시작일 주입은 측정 변경 — 판단 T4 + 판 표식.
- 코어: 출시된 v1 · v2 파일 무수정. 입구 규칙은 새 코어 판(v3)으로 출시(`RELEASES.json`)하고 판 2 가 핀한다.
- 운영 파일(`rf_cell_engine.R` · `rf_base_cache.R` · `rf_replication_auto.sh`)은 스크래치 사본 → 시험 → 원자 교체. 레인이 도는 창을 피한다.
- 판 1(P1S01): `tick_hold` 를 지우지 않는다. 판 1 원장 · 사전등록 무수정.
- 측정: 코어 GPU 관문(레인 측정 0 + 임대) · 임대에 pid 를 넘기면 Windows pid(`/proc/$$/winpid`) · 임대 상한 12시간 · 00:03 밤 체인과 07:10 아침 체인 창 회피 · DNN 시드는 단독(지속 25~33 GB).
- 감독: 서브에이전트는 opus · Superfan 백그라운드 · 통과 판정 = 판단 T2 + 철학 P2 즉시.
- 커밋: 작업 단위마다 그 경로만 · 공유 등록부는 커밋 직전 diff 재확인.

## 인계 2(11-12 밤 — 판 2 구축 소유가 세션 local_9fa47fd9 로 넘어갔다 · 여기부터 읽는다)

- **결정**: 원 세션 `local_d1e1cc26` 은 11-12 00:16 에 멈췄다(Claude 프로세스 종료 · 다시 깨어난 뒤 '백그라운드 에이전트 2개 미완' 알림만 받고 0턴 종료). 도훈 선택 "이 세션이 이어받기"(11-12 21:1x · 질문 = 판 2 구축을 이 세션이 이어받을까요) — 판단 J-20261112-002 · 재개 저널 `OP-20261110-V102-LADDER` 21:1x 기록. 원 세션에서 같은 일을 다시 시키지 않는다(두 세션이 같은 파일을 쓰게 된다).
- **죽은 서브에이전트 둘이 남긴 것**(전사 = 원 세션 `subagents/agent-aac077097dfed8290.jsonl` · `agent-a05db63eaa67f4da3.jsonl`):
  - ① 판 2 리뷰 반영 · 리허설 · 초안 v2: **1부(리뷰 반영) 끝** — v1 점검 판정 기록(`drafts.json` v1 = revise · 00:00:58) · `init_p1s02.R` 수정 → 사양 재생성(시드 칸 md5 687d6517 · 3a085178 불변 · 사양 md5 e336f653) · DESIGN §2 · §5 · §6 · `prejudge_check.R` 기대값 인자 3종 + `--round-dir` · `--registry` · 감시 셸 순서(창 → 레인 0 → 측정 · 임대 선점 없음) · `tick_hold`. 인수 세션이 브리프 체크리스트 (a)~(f) · 1~6 을 사양 · 문서와 하나씩 대조했다(빠진 것 없음 · `standing-check` · `check` 통과 · 핀 35). **2부(리허설)는 엔진 파일 하나만 쓰고 멈췄다** · 3부(초안 v2) 없음.
  - ② S3 레인 출력 계약 후보판: `staging/s3/` 에 생성기 · 후보판 3종(`rf_replication_auto.sh` · `rf_replication_verify.R` · `rf_fidelity_axes.json`) + 패치 · 시험(`test_s3_score_panel_check.R` — 고치는 중에 멈춤). `SWAP_PROCEDURE.md` · `README_S3.md` 없음. 판 2 등록 뒤 생성기 재실행부터 이어 간다(운영 파일 무변경).

## 인계(11-11 밤 — 판 2 구축 소유가 새 세션으로 넘어갔다 · 대체됨 · 사료)

- **결정**: 도훈 "새 세션으로 이관"(질문 = 판 2 구축은 어느 세션이 맡을까요 · 앞의 "이어서 시작"을 대체) — 재개 저널 `OP-20261110-V102-LADDER` 22:20:51 로그 · 커밋 `d2dc68f42`. 판 2(P1S02) 구축 전체(S1~S7) = 새 세션 `local_d1e1cc26`. 분류 세션 `local_ffde0db1` 은 구축을 멈췄다.
- **쓰기 권한**(11-11 23시대 두 세션 합의로 바로잡음): 새 세션 = 이 문서 · 진행표 · `staging/` 와 판 2 구축 파일(운영 파일 · 시험 · 엔진 · 레인 · 코어 v3 · P1S02). 분류 세션 = 같은 폴더의 설계 문서(`README.md` · 분류표 · `data/` · `scripts/`) — 고칠 일이 생기면 새 세션이 먼저 알린다. 분류 세션의 인계 기록 = `HANDOVER_EDITION2.md`(커밋 `a04c2ae71`).
- **분류 세션이 남긴 것**(전부 main · 미푸시):
  - `526d72f12` 이 문서(계획 · 설계 결정) · 판단 J-20261111-029(달 스냅)
  - `71801c87d` `02_Infrastructure/reinforcement/rf_base_align.R` + `08_Tests/reinforcement/test_rf_base_align.R`(20/20 · 돌연변이 대조 포함) — 셀 엔진에는 아직 연결하지 않았다
  - `de255e1ae` `staging/make_s1_candidates.py`(후보판 생성기) · `staging/s1_*.patch`
- **운영 파일은 그대로다**(인계 때 md5 재확인): `rf_cell_engine.R` · `rf_base_cache.R` 둘 다 아래 'S1 이어 하기'에 적힌 원본 md5 와 같다. `rf_replication_auto.sh` · 엔진 파일 · 코어 · 등록 사양은 손대지 않았다. 판 1 `tick_hold` 유지.
- **이어 갈 자리** = 아래 'S1 이어 하기' 1번(시험의 접두 기대값)부터. 후보판은 생성기로 다시 만든다(분류 세션 스크래치 사본은 쓰지 않는다).
- **S1 이 다른 단계와 맞물리는 계약**(후보판 기준 · 운영에는 아직 없다):
  - 기저 캐시: `RF_BASE_CACHE_VERSION = "rf_base_cache_v3"` · 파일 접두 `base_v3_`. 접두를 읽는 다른 코드는 `08_Tests/reinforcement/test_rf_base_cache_key.R` 뿐이다(11-11 확인).
  - 정렬 진단: `.RF_DIAG$base_alignment[[<기저 엔진 폴더명>]]` = `rule`(`month_snap_v1`) · `n_engine_dates` · `n_cell_dates` · `n_identity` · `n_moved` · `n_superseded` · `n_dropped_tail` · `max_lag_td` · `median_lag_td` · `start_injected` · `start`. ★`.RF_DIAG` 가 산출 폴더에 저장되는 경로는 아직 확인하지 않았다('이어 하기' 6번) — 코어 v3 나 판정 전 점검이 이 값을 읽게 하려면 그것부터 확인한다.
  - 폭 배수의 정본: `02_Infrastructure/worktask/constraint_defaults.json::measurement_axis.epochs.<epoch>.effective_start.breadth_mult`. 읽기는 `02_Infrastructure/contracts/measurement_axis.R::ma_epoch()$effective_start$breadth_mult`. 코어 v3 의 `breadth_insufficient` 는 숫자를 직접 쓰지 않고 이 값을 읽는다.
- **검토가 남은 판단**: J-20261111-025(설계 보강) · J-20261111-029(달 스냅) — 판단 T4 미검토. 시작일 주입은 측정 변경이라 원자 교체 전에 T4 를 받는다('이어 하기' 2번).
- **열린 설계 문제**: S7 점수 패널의 대상(시장상관 상위 50 그대로인가 · 적격 종목 전체인가) · 판 1 을 닫는 법과 기저 풀의 최신 판 우선 규칙(S4 · S5).
- 이 문서의 '승인과 범위'(설계 §8 의 2 → 3 → 4)는 분류 세션이 받은 것이다. 범위 밖 3건(카탈로그 3종 · 추정기 축 · 노출 규칙과 P2 상설 판)은 누가 맡든 도훈께 따로 여쭌다.

## (대체됨 · 사료) 세션 사이 파일 경계 — 11-11 22:20 소유 변경 직전에 적은 것

판 2 를 목표로 하는 세션이 둘 떠 있다 — 이 세션(local_ffde0db1 · 도훈 '이어서 시작')과 총괄 세션이 띄운 local_d1e1cc26('정식 구동 — 사다리 루프 재개'). 어느 세션이 맡을지는 도훈 답 대기(기본 = 이 세션 계속). **한 파일은 한 세션만 쓴다.**

| 묶음 | 파일 | 쓰는 세션 | 상태 |
|---|---|---|---|
| S1 셀 경로 정합 | `02_Infrastructure/reinforcement/rf_cell_engine.R` · `rf_base_cache.R` · `rf_base_align.R` · `08_Tests/reinforcement/test_rf_base_align.R` · `test_rf_base_cache_key.R` | **이 세션** | 함수 · 시험 커밋됨 · 운영 파일은 후보판 단계(미교체) |
| S2 시드 엔진 스케줄 | `04_Research/strategies/RP_AUTO_2002_06975/engine.R` · `FIDELITY.json` | **이 세션**(S1 뒤) | 손대지 않음 |
| S3 레인 출력 계약 | `02_Infrastructure/ops/rf_replication_auto.sh` · 감사 프롬프트 · 레인 검증기 | 비어 있음 | 손대지 않음 — 다른 세션이 맡아도 S1 과 파일이 겹치지 않는다 |
| S4 코어 v3 | `04_Research/programs/_lib/round_core/v3/` · `RELEASES.json` · v3 시험 | 비어 있음 | 손대지 않음 — S1 과 파일이 겹치지 않는다 |
| S5~S7 판 2 등록 · 측정 · 1908 | `04_Research/programs/P1_RETURN/P1S02_*` · 판 2 원장 · `RP_AUTO_CLEAN_1908_01112/engine.R` | 비어 있음 | S1 · S3 · S4 가 끝나야 시작할 수 있다 |
| 이 폴더 | `04_Research/01_reports/portfolio_paper_layer_split_20261112/` | **이 세션** | 다른 세션은 읽기만 · 고칠 것이 있으면 메시지로 |
| 공유 등록부 | 판단 원장 · 재개 저널 · 결정 기록부 | 쓰는 순간에만 · 커밋 직전 diff 확인 | 정본 CLI 로만 쓴다 |

- 이 세션의 맥락은 한도에 가깝다(96%). 도훈께 '새 세션에서 / 여기서 계속'을 여쭌 상태다. 새 세션이 전부 이어받는 쪽으로 정해지면 S1 은 '이어 하기' 7단계(아래)부터 그대로 넘긴다 — 후보판 생성기와 원본 md5 가 이 폴더 `staging/` 에 있다.
- 나눠서 간다면 경계는 위 표대로다: 이 세션 = S1 · S2, 다른 세션 = S3 · S4. S5 부터는 한 세션이 한다.

## 작업 순서와 설계 결정

### S1. 셀 경로 정합 (`rf_cell_engine.R` · `rf_base_cache.R`)

**(a) 달 스냅 — 기저 신호를 월말 격자에 맞춘다.**
- 규칙: 월말 거래일 d 의 기저 = 구간 (직전 월말, d] 안의 엔진 신호일 가운데 가장 늦은 날의 패널. 그 구간에 엔진 신호가 없으면 그 달은 기저가 없다(앞 달 것을 이월하지 않는다 — 보유 이월은 하네스가 한다).
- 상수 · 유효 기간이 없다. 신호의 나이는 구조상 한 달 미만이다. s ≤ d 만 쓰므로 PIT 방향은 안전하다.
- 월말 거래일에 신호를 내는 엔진(월간 · 분기 · 연간)은 항등 사상이다 → 수정 전후 비트 동일(채택 조건).
- 60거래일 격자(1908.01112): 신호마다 그 달 월말로 옮겨진다(지연 0~약 21거래일). 주간 · 일간 엔진: 달마다 마지막 신호 하나.
- README §6-3 은 '다음 신호까지 이월 + 신고 주기로 만료'를 적었다(Superfan C-041). 달 스냅으로 바꾼 이유: 그 형식은 분기 · 연간 엔진의 사이 달에 묵은 신호를 다시 적용해 결과를 바꾸고(비트 동일이 깨진다) 만료 모수가 남는다. 달 스냅은 모수가 0 이다. README §6-3 은 인계 때(11-11) 이 규칙으로 고쳤다.

**(b) 시작일 주입 — 측정 변경.**
- `.load_one` 의 기저 엔진 환경에 `.RP_START_DATE` 를 넣는다(러너가 준 값 · 없으면 칸 고정 축 시작일).
- 영향 4묶음(README §2-1): 2005 로 떨어지던 14 = 시작이 당겨진다 · 자료 첫날로 떨어지던 9 = 레인 격자와 일치 · 멈추던 2 = 실패 해소 · 읽지 않는 8 = 비트 동일.

**(c) 캐시.** `RF_BASE_CACHE_VERSION` 을 올려(파일 접두도) 주입 전에 만든 캐시가 적중하지 않게 한다. 레인 시드 키도 같은 함수(`rf_base_cache_key`)라 함께 바뀐다.

**(d) 진단 · 판 표식.** 셀 엔진이 `.RF_DIAG$base_alignment` 를 남긴다 — 규칙 id · 엔진 신호일 수 · 셀 신호일 수 · 옮겨진 신호일 수 · 최대 지연 · 시작일 주입 여부. 판정 전 점검 8~10번과 판 표식의 근거다.

**(e) 시험.** 합성 엔진으로: 월말 격자 = 수정 전후 FACTORS 비트 동일 · 60거래일 격자 = 월말 신호일 수 회복 · 주간 = 달마다 1개 · 시작일 전달 · 캐시 판 접두. 기존 시험(`08_Tests/reinforcement/test_rf_cell_engine_smoke.R` · `test_rf_base_cache_key.R` · `test_rf_base_cache_seed.R`) 통과.

### S2. 2002.06975 스케줄 수리 (`RP_AUTO_2002_06975/engine.R:271-286`)

- 앵커 전 달(갱신 격자점이 없는 달)을 스케줄에서 뺀다 — 지금은 `max(integer(0))` 이 −Inf 가 되어 묶음 사이 형 불일치로 멈춘다(Superfan 재현).
- 달별 난수 시드 번호를 순번 k 가 아니라 달력 월에 묶는다(2005-01 이 지금의 k = 1 을 유지) → 2005 이후 달은 시드가 그대로다. 학습창은 달력으로 정해지므로 겹치는 달의 학습은 같은 입력 · 같은 시드다.
- 엔진 md5 가 바뀐다 → 판 2 시드 칸이 새 md5 를 핀한다. FIDELITY 의 changed 에 적는다.

### S3. 레인 출력 계약 (`rf_replication_auto.sh` 프롬프트 · 검증기)

- 프롬프트 두 절(산출 · portfolio_spec): 종목별 수치로 보유를 정하는 엔진은 PORTFOLIO 와 함께 선정 전 후보 전체의 `FACTORS(Date, Ticker, Score)`.
- FIDELITY `score_panel`: available · 정의 · 방향 · 대상 집합(좁힌 규칙) · scale(cardinal | ordinal).
- 감사 신호 축에 '점수 패널이 논문 신호인가' · 검증기에 정합 검사(롱 보유 ⊆ 그날 점수 패널) · 레인 산출에 보유/후보 비 기록(2배 근처 경고).
- 후보판 → 시험 → 레인 빈틈에 원자 교체(실행 중 스크립트는 교체가 거부된다).

### S4. 코어 v3 (`04_Research/programs/_lib/round_core/v3/`)

- v2 를 복사해 입구 사유 둘을 더한다: `portfolio_only_base`(FACTORS 대입 없음 · 정적) · `breadth_insufficient`(보는 창 월말 신호일 중 폭 ≥ 보유 상한 × 배수인 날 없음 · 숫자는 정본 참조 · `Date ≤ τ_D` 절단 · 음성 대조 시험).
- 같은 칸을 두 판이 판정하면 기저 풀은 최신 판을 읽는다 · 판 1 을 닫는 법을 판 2 등록 때 정한다.
- 시험: v2 시험의 v3 경로 실행 + 새 사유 양성/음성 대조 → `RELEASES.json` 출시.

### S5. 판 2 등록

- 사양(`core_version: v3` · 판 번호 2 · 시드 E2 · E3 새 md5 · 판정 규칙은 판 1 과 같다) → `standing-check` → 초안 → 격리 교차 점검 → 철학 P1 · 판단 T1(시작일 주입 = T4 포함) → 등록.

### S6. 시드 측정과 첫 판정

- GPU 관문 · 측정 창 확인 → 측정 → **판정 전 점검 10항목**(README §8) → judge → report(실발송) → 판단 T2 + 철학 P2.
- 측정 세션의 점검 스크립트를 판 2 경로 · 코어 판으로 고쳐 쓴다: 공유 노트 `…\local_d19cc13c-…\p1s01_measure_tools\prejudge_check.R`.

### S7. 1908.01112

- 점수 패널 패치(계산은 그대로 · 산출만 추가 · 패치 전후 PORTFOLIO 동일) → 레인 재측정 · 감사 · 인계 → 판 2 스캔 → 측정 → 점검 → 판정 → 보고.
- 정할 것: 점수 패널의 대상 — 시장상관 상위 50 그대로(폭 50 = 경계)인가, 적격 종목 전체(계산량 수십 배)인가.

## 진행 상태

| 단계 | 상태 | 메모 |
|---|---|---|
| S1 셀 경로 정합 | **완료**(11-11 23:00 운영 교체 · 아래 'S1 · S2 완료 기록') | 달 스냅 연결 · 시작일 주입(측정 변경) · 캐시 판 v3 · 진단 `base_alignment` · 러너 시드 관문 · 판단 T4 R-20261111-008 도전 4건 수용 |
| S2 2002.06975 스케줄 | **완료**(11-11 22:45 교체) | 앵커 전 달 제외 · 월 인덱스 달력 기준 · FIDELITY changed(17) · 엔진 md5 `fe301130…` |
| S3 레인 출력 계약 | 착수 전 | S5 등록 뒤(첫 판정 경로와 무관 — S7 의 선행) |
| S4 코어 v3 | **완료**(11-11 23:30 출시) | 커밋 `6e43e1158`(v3 · 시험 3종) · 출시 기록 `1b1bda18d`(RELEASES.json 매니페스트 `4d00113a…` · 파일 20) — 입구 사유 3종 · 측정 관문(상설 · 사슬 공용) · 최신 판 우선 · 판정 굳음 수리(T3 C-049) · 시험 v3 68/0 · v2 동등성 33/0 · 진단 계약 8/0(실제 셀 엔진 진단 ↔ 관문) · 입구 미리보기 51 디렉터리 통과 0(portfolio_only_base 21) |
| S5 판 2 등록 | **진행 중**(11-12 밤 인수 세션 local_9fa47fd9) | 초안 v1(`de259d86`) 점검 = revise(필수 F-1 · F-2) · 철학 P1 R-20261111-009(도전 4) · 판단 T1/T4 R-20261111-010 · 011(도전 3) — 전부 수용(J-20261112-001). 반영(사양 v2 · md5 `e336f653` · 핀 35 · `rejudge_prior_editions = false` · 시드 칸 md5 불변 · DESIGN §2 · §5 · §6 · 도구 3 · `tick_hold`) → **등록 전 리허설 통과**(`P1S02_…/rehearsal/` · run 20261112_212912 · 12단계 · 결함 0 · J-20261112-003) → **초안 v2 `b3f180ff`**(리허설 기록 실림) → 격리 교차 점검 v2(변경분) 진행 중. **남은 것**: 점검 v2 ok → `reviewed 2` → 판 폴더(`tick_hold` 포함) 커밋 → `register` → 등록 커밋 → `scan`(시드 2) |
| S6 시드 측정 | 착수 전(도구 준비됨 · 11-12 개정) | 감시 셸 `P1S02_…/tools/p1s02_seed_watch.sh`(판단 T1 C-086 개정: 창 확인 → 레인 측정 0 → 측정 · 임대를 미리 쥐지 않는다(E2 직후 E3 용 한 번만) · 낮 창 시작 08:20~11:45 · 메모리 ≥ 16 GB · `measure-item` E2 → E3 · 판정 · 발송 없음) → 판정 전 점검 `tools/prejudge_check.R <code> --eval --expect-first-engine-date 2004-07-30 --expect-engine-dates 268` → `judge` → `standing-report --send` → 판단 T2 + 철학 P2 · 판 1 tick_hold 유지. 위험: ① 자료 낡음(11-12 밤 갱신이 OHLCVS 를 못 올렸다 — 오늘 밤 00:03 이 올려야 측정 관문이 연다) ② 레인 gpu1 이 창 안에서 비어야 E2 가 시작한다(8분 틱 · 연속 작업) |
| S7 1908.01112 | 착수 전 | |

### S1 · S2 완료 기록(11-11 23:0x — 인수 세션 local_d1e1cc26)

**운영 파일(원자 교체 3회 — 22:44 · 22:50 · 23:00 · 지금 md5)**

| 파일 | md5 | 바뀐 것 |
|---|---|---|
| `02_Infrastructure/reinforcement/rf_cell_engine.R` | `25fa9a4a985280cf20daa49d8b003417` | 달 스냅 적용(적재 뒤) · 기저 엔진에 `.RP_START_DATE` 주입 · 캐시 키의 시작일 = 넘긴 값 · 진단 `base_alignment` · 스냅 뒤 빈 패널이면 멈춤 |
| `02_Infrastructure/reinforcement/rf_base_cache.R` | `3794bc7b6ec5df0ab135da3f082a5afb` | 캐시 판 `rf_base_cache_v3` · 접두 `base_v3_` · 시드 저장에 `rf_base_kind` 속성 |
| `02_Infrastructure/reinforcement/rf_base_align.R` | `e9b2852815014592bd7afaff01a33896` | 진단에 `n_offcal` · `first_engine_date` · `last_engine_date` |
| `02_Infrastructure/alpha_search/run_paper_replication.R` | `04b181466864da017e66dc9be5cdb52f` | 기저 캐시 시드 관문에 `!length(engine_vars)`(변형 스위치 실행은 시드하지 않는다) |
| `04_Research/strategies/RP_AUTO_2002_06975/engine.R` | `fe3011301e574eff1b668744cb89dc79` | 스케줄: 앵커 전 달 제외 · 월 인덱스 k = 달력 월(2005-01 = 1) |
| `04_Research/strategies/RP_AUTO_2002_06975/FIDELITY.json` | `47548a3e1ed9cfe6dd288dc5542950df` | changed(17) · 창 · 산출 행 서술 · `revision.patch_20261111` |

원본은 git 에 있다(셀 엔진 blob `d1555fa0…` = 커밋 `526d72f12` 시점). 패치 = `staging/s1_*.patch` · `staging/s2_engine_2002_06975.patch`. 생성기 = `staging/make_s1_candidates.py`(원본 → 2차) · `make_s1_cand3.py`(2차 → 3차) · `make_s2_candidate.py`(전부 원본 md5 를 단정하므로 지금 저장소에는 다시 돌지 않는다 — 기록용).

**앞 판 후보판에서 달라진 것(판단 J-20261111-031 · 032)**

- 달 스냅 파일은 엔진 기저 경로(`rf_base_cache.R` 를 적재하는 분기)에서만 적재한다 — 머리에서 적재하면 형제 파일을 골라 복사하는 격리 루트 시험 6종이 멈춘다(10-13 `rf_axes.R` 때와 같은 꼴 · `test_rf_engine_overlay_stack.R:94`).
- 캐시 키의 시작일 = 엔진에 실제로 넘긴 값(`.rf_rp_start`). 레인 시드 키와 같은 값이다.
- 진단 필드(산출 폴더 `rf_engine_diag.json` 의 `base_alignment["<엔진 폴더>/<엔진 파일>"]`): `rule` · `n_engine_dates` · `n_cell_dates` · `n_identity` · `n_moved` · `n_superseded` · `n_dropped_tail` · `n_offcal` · `max_lag_td` · `median_lag_td` · `first_engine_date` · `last_engine_date` · `start_injected` · `start` · `from_cache` · `base_kind`(factors | portfolio_weights | unknown) · `n_cell_dates_from_start` · `first_cell_date` · `last_cell_date`. 기저가 엔진인 칸은 이 파일이 항상 생긴다(기저가 `mom_12_1` 인 칸은 그대로 없다).
- `base_kind` 는 캐시 객체 속성(`rf_base_kind`)으로 남아 캐시 적중 때도 읽힌다 — 판정 전 점검 8번(기저 = 점수 패널)을 코어 v3 가 기계로 본다.

**시험**

- 새 종단 시험 `08_Tests/reinforcement/test_rf_cell_base_alignment.R` 25/0 — 구판 엔진(git blob `d1555fa0`)을 같은 절차에 걸어 양방향으로 본다: 월말 격자 = 구판과 FACTORS 비트 동일 · 60거래일 격자 = 구판 0일 → 신판 18달 · 구판은 시작일 미전달. 교체 전 운영 엔진에서는 6/14(red).
- 단위 시험 `test_rf_base_align.R` 26/0(T10 진단 · T11 PIT 방향 돌연변이 = `+ 1L` 제거 사본에서 red · T12 달 스냅 뒤 체결일 = 레인 체결일).
- `test_rf_base_cache_key.R` 38/0(판 v3 기대값 · 격리 루트에 `rf_base_align.R`) · `test_rf_base_cache_seed.R`(S10e 시드 관문).
- 회귀 묶음(셀 엔진 · 러너를 실행하는 시험 23종 · `staging/` 밖 세션 스크래치 `run_suite.sh`): 교체 전 기준선 22종 전부 통과(새 시험만 6/14) → 세 번의 교체마다 다시 돌려 전부 통과(최종 운영 파일 23/23 · 23:14).
- 2002.06975 스케줄 절 대조(`staging/sched_test.R` · 실제 거래일 달력 · 학습 없음) 7/0: 기본 시작 262개월 비트 동일 · 2000-01-01 에서 구판 멈춤 재현 · 후보판 268개월(첫 달 2004-07-30 · 앵커 전 제외 7) · 겹치는 262개월은 창 · 번호 · 시드 동일.

**실자료(날짜 · 개수만 · `staging/snap_census.R`)** — 기저 캐시 33개(엔진 md5 접두 기준)에 달 스냅: 월말 격자 엔진 = 항등(옮김 0 — 묵은 캐시의 마지막 부분월 · 2024-12-27(그때 자료에 12-30 이 없었다)만 옮겨진다 · 같은 자료 판본에서는 0) · 60거래일 1908.01112 = 월말 1 → 110(최대 지연 21거래일) · 주간 1810.08384 · 2604.16773 = 154~155 → 322~323 · 일간 2601.10732 = 241 → 243 · 달력 밖 신호일(`n_offcal`) = 전부 0.

**판단 T4(R-20261111-008 · `04_Research/programs/_supervision/superfan/20261111_2249_T4.md`)** — PIT 반례 없음 · 수혜 성과 미열람(endorse). 도전 4건 수용: C-060 러너 시드 관문 · C-061 월말 격자 밖 신호(코어 v3 입구 사유 + 측정 관문) · C-062 주입 전후 분리(창 [팩터 DB 판 11-11 19:28, 교체 22:44] 안 셀 경로 측정 = 실패 2건뿐 → 판 표식 원장 불필요 · v3 는 `base_alignment` 없는 측정을 실패로 닫는다 · P2R05 재개 전 점검을 저널 OP-20261018-P2DT 에 기록) · C-063 점검 9 = 신호일 집합 대조.

**남긴 후속(이 판에서 하지 않는다)**

- 칸 사양에 `base_signal.engine_vars`(대표 변형 명시) — 생성 함수 핀이 바뀐다. 지금은 변형 엔진 7개 모두 엔진 기본값 = FIDELITY 대표 변형(대조 확인).
- 셀 엔진의 주간 신호(MC4 잔여) — 그 전까지 주간 · 일간 신호 엔진은 상설 판에서 판정하지 않는다(`base_off_month_grid`).
- 옛 `base_v2_*.rds` 는 죽은 파일로 남는다(지우지 않았다).
- README §8 3단계의 '유효 기간 형식' 문구는 달 스냅 뒤 낡았다(T4 C-067 · 분류 세션에 알림).

## 환경 메모(11-11 22:1x)

- 레인 슬롯 gpu1 = 2601.04602(THGNN) 측정 중 · 밤 체인 00:03 · 아침 체인 07:10.
- 주간 사용량: 전 모델 41% · Fable 60%(11-13 재설정).
- 인계 자료: 공유 노트 `p1s01_measure_20261111_handover.md`(안 지난 길 = 칸 평가 패킷 · β-통제 알파 · judge · 판정 원장 · 실발송 · torch 칸 · 함정 6가지).
