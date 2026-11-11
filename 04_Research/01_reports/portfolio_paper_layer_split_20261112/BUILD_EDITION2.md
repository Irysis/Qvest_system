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

## 인계(11-11 밤 — 판 2 구축 소유가 새 세션으로 넘어갔다 · 여기부터 읽는다)

- **결정**: 도훈 "새 세션으로 이관"(질문 = 판 2 구축은 어느 세션이 맡을까요 · 앞의 "이어서 시작"을 대체) — 재개 저널 `OP-20261110-V102-LADDER` 22:20:51 로그 · 커밋 `d2dc68f42`. 판 2(P1S02) 구축 전체(S1~S7) = 새 세션 `local_d1e1cc26`. 분류 세션 `local_ffde0db1` 은 구축을 멈췄다.
- **쓰기 권한**: 이 문서 · 진행표 · `staging/` · 같은 폴더 `README.md` 를 포함해 판 2 구축에 쓰는 파일은 이제 새 세션이 쓴다. 분류 세션의 마지막 쓰기는 이 절을 넣은 커밋이다.
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
| S1 셀 경로 정합 | **진행 중**(인계됨 — 새 세션이 '이어 하기' 1번부터) | ✅ 달 스냅 순수 함수 `02_Infrastructure/reinforcement/rf_base_align.R`(`rf_base_month_snap(b, cal)` → panel · diag) + 단위 시험 `08_Tests/reinforcement/test_rf_base_align.R` 20/20(돌연변이 대조 포함). **남은 것**: ① `rf_cell_engine.R` 연결 — 후보판에서 `.load_one` 반환 직전에 `rf_base_month_snap(.b, unique(DT$Date))` 적용(캐시에는 엔진 원산출 그대로 · 스냅은 적재 뒤) · `.env$.RP_START_DATE` 주입(러너 값 · 없으면 `.START`) · `.RF_DIAG$base_alignment` 기록 ② `rf_base_cache.R` 판 올림(`RF_BASE_CACHE_VERSION` v3 · 파일 접두 `base_v3_` — 접두를 읽는 다른 코드 grep 필요) ③ 기존 시험 3종(`test_rf_cell_engine_smoke.R` · `test_rf_base_cache_key.R` · `test_rf_base_cache_seed.R`) 통과 + 월말 격자 엔진 수정 전후 비트 동일 실증 ④ 원자 교체 ⑤ 판단 T4(시작일 주입 = 측정 변경) |
| S2 2002.06975 스케줄 | 착수 전 | |
| S3 레인 출력 계약 | 착수 전 | 레인 gpu1 = THGNN 측정 중 |
| S4 코어 v3 | 착수 전 | |
| S5 판 2 등록 | 착수 전 | |
| S6 시드 측정 | 착수 전 | GPU 임대 free · 판 1 tick_hold 유지 |
| S7 1908.01112 | 착수 전 | |

### S1 이어 하기(11-11 22:5x 기준 — 여기서부터)

지금까지: 달 스냅 함수와 단위 시험은 커밋됨(`71801c87d`). 셀 엔진 · 기저 캐시의 **후보판**을 만들었고 구문 확인을 통과했다. 운영 파일은 아직 그대로다.
- 후보판 생성기 = `staging/make_s1_candidates.py <저장소> <폴더>`(치환 4곳 + 2곳 · 각 한 곳 일치 단정 · 줄끝 보존). 패치 = `staging/s1_rf_cell_engine.patch`(46줄) · `staging/s1_rf_base_cache.patch`(20줄).
- 생성 당시 원본 md5: `rf_cell_engine.R` = `26993a0411bf1c1132df9962578dfb8d`(CRLF) · `rf_base_cache.R` = `f6fef4f9eee6adfb007b0e1d97668f9f`(LF). 교체 전에 원본이 이 값인지 확인한다(다르면 생성기를 다시 돌린다).
- 후보판 내용: ① `rf_base_align.R` 적재 ② `.rf_cal`(패널 달력) · `.rf_rp_start`(러너의 `.RP_START_DATE` · 없으면 `.START`) ③ 기저 엔진 환경에 `.RP_START_DATE` 주입 ④ `.load_one` 반환 직전에 `rf_base_month_snap` 적용 + `.RF_DIAG$base_alignment[[엔진 폴더]]` 기록 + 로그 한 줄 ⑤ 캐시 판 `rf_base_cache_v3` · 파일 접두 `base_v3_`.

다음 순서:
1. `08_Tests/reinforcement/test_rf_base_cache_key.R` 의 파일 접두 기대값(`base_v2_`)을 새 판에 맞춘다(접두를 읽는 코드는 이 시험과 `rf_base_cache.R` 뿐임을 확인했다).
2. 판단 Superfan T4(시작일 주입 = 측정 변경 · 달 스냅 = 판 규칙) — 백그라운드 · opus. 프롬프트에 '저장소 전체 재귀 검색 금지'를 적는다.
3. 후보판을 원자 교체한다(매시 37분 상설 판 틱을 피한다 · 지금 대기 측정은 없다 — 판 1 보류 · 사슬 0). 원본은 스크래치에 사본을 남긴다.
4. 회귀 시험: `test_rf_base_align.R` · `test_rf_cell_engine_smoke.R` · `test_rf_base_cache_key.R` · `test_rf_base_cache_seed.R`. 실패하면 원본으로 되돌린다.
5. 비트 동일 실증: 월말 격자 기저 캐시(예 2002.06975 — 신호일 261 전부 월말)에 `rf_base_month_snap` 을 걸어 항등(`n_moved = 0` · 패널 동일)임을 보이고, 1908.01112 캐시에서는 월말 신호일 수가 1 → 약 110 으로 돌아오는지 센다.
6. `.RF_DIAG` 가 산출 폴더에 어떻게 남는지 확인한다(셀 엔진 끝부분 · 워커) — 판정 전 점검 8~9번이 그 파일을 읽는다.
7. /simplify → 커밋(운영 파일 2개 + 시험 1개) → 이 표 갱신.

## 환경 메모(11-11 22:1x)

- 레인 슬롯 gpu1 = 2601.04602(THGNN) 측정 중 · 밤 체인 00:03 · 아침 체인 07:10.
- 주간 사용량: 전 모델 41% · Fable 60%(11-13 재설정).
- 인계 자료: 공유 노트 `p1s01_measure_20261111_handover.md`(안 지난 길 = 칸 평가 패킷 · β-통제 알파 · judge · 판정 원장 · 실발송 · torch 칸 · 함정 6가지).
