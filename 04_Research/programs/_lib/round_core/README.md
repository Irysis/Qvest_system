# round_core — 1계층 공통 판정 코어

도훈 10-20 결정 `L1-SPEED-PLAN-20261020`(1계층 리서치 속도 극대화)의 WP1 이다.

**목적**: 라운드마다 판정 코드를 복사·확장하지 않는다. 라운드는 사양(`round_spec.json`) · 사고 기록(`DESIGN.md`) · 꼭 필요한 고유 규칙(`round_ext.R`)만 쓰고, 나머지는 공통 코어와 실행기가 한다.

**배경**: P2R04 의 라운드 전용 코드는 약 570KB, P2R05 는 약 1MB 였다. 교차 점검 필수 지적 17건 가운데 11건이 같은 규칙이 여러 곳에 적혀 생긴 문구 표류였다.

## 원칙 (보증 불변)

- **보증 장치는 그대로다.** PIT · 사전등록 → 커밋 → 측정 · τ_D · β 짝 · MC8 · 격리 교차 점검 · Superfan 을 바꾸지 않는다. 판정 규칙의 내용 · 수 · 설계 재량도 현행대로다.
- **규칙은 한 번만 선언한다**(`v1/rules.R`). 같은 선언에서 사전등록 문장 · 판정 실행 · DESIGN 표를 생성한다.
  - 수치 문턱은 근거(`basis`)나 정본 참조(`value_ref`)가 없으면 거부한다.
  - 미측정(NA)은 통과로 접지 않는다.
- **수치는 R 계약 산출만 쓴다**(AX-008).
  - 계약 파일은 읽기만 한다.
  - 진행 중 라운드(P2R05)의 핀 51개 파일은 그 라운드가 끝날 때까지 수정하지 않는다.
- **판은 불변이다.** 출시된 판은 고치지 않고, 바꿀 일이 생기면 새 판(v2)을 만든다.
  - 라운드는 판과 매니페스트 md5 를 핀으로 건다(`rc_core_manifest`).
  - *v1 은 아직 개발 중이며 출시 전이다.*
- **속도 조치는 결과 동일 실증이 채택 조건이다**(`PERFORMANCE.md`). 실행 시간은 `.cache/round_core/perf/<round>.jsonl` 에 남는다.

## 사용 (P1 라운드 예)

```r
source("04_Research/programs/_lib/round_core/v1/load.R")
rc_init_p1("04_Research/programs/P1_RETURN/P1R03_<이름>", "P1R03_<이름>", engines = list(...), purpose = "...", hypothesis = "...")
```

```bash
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> check      # 규칙 문장 · 핀
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> draft      # prereg_draft.json + .md(점검자 · 감독용)
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> reviewed 1 <점검 파일> ok
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> register   # 등록 조건 ①~⑧ → 커밋
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> measure    # 배리어 · 사전 점검 · 지문 · 재측정 → 평가 자동 연쇄
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> report --next "..."   # 기본 dry-run · --send
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> close --note "<해석>" --probe "<다음 탐침 1>" --probe "<다음 탐침 2>" [--lesson "<교훈>"] [--r7 noise|signal] --p2 <id> --t2 <id>
#   close 는 등록부와 결과 원장(06_Registry/round_outcomes.jsonl · v1/outcomes.R)에 함께 쓴다 — 다음 탐침 2개 이상(없으면 --no-probes "<사유>") ·
#   글에 정보 경계 뒤 날짜가 있으면 멈춘다. 다음 라운드 설계는 rc_outcomes_md(rc_outcomes_path(), "<프로그램>") 출력에서 출발하고,
#   이어받는 탐침은 rc_probe_consume("<round_id>#<번호>", "<새 round_id>", rc_outcomes_path()) 로 표시한다(2026-11-10 · v10.2).
```

## 상설 판 (P1 상설 자격 · WP5 · 사양 `standing: true` · 첫 판 = `P1_RETURN/P1S01_standing_qualification`)

규칙을 프로그램 단위로 한 번 등록하면, 충실구현 레인이 낸 엔진마다 라운드 의식 없이 측정 · 판정한다. R2 는 그대로다 — 규칙 · 입구 규칙 · 생성 함수 핀(`rc_p1_cell_spec` md5 · 선례 · 정본 고정 축)은 등록본에 고정되고, 항목 칸 사양은 등록된 생성 함수가 재량 없이 만든다(측정 · 판정 직전 다시 만들어 md5 대조). 판정 원장 = 사전등록 정본 옆 `standing_ledger.jsonl`(추가 전용 · 줄마다 앞 줄 md5 사슬 · 보는 창 값만). 규칙을 바꾸면 새 판(P1S02 …) — 옛 판정은 남고, 새 판이 등록되면 옛 판은 새 항목을 받지 않는다. 등록부는 읽기만 한다.

```bash
round.sh <판> standing-check            # 상설 사양 · 생성 함수 핀 · 시드 회계 검사 → standing_rules.md(사양에서 생성)
round.sh <판> check · draft · reviewed · register   # 라운드와 같다(등록은 판마다 1회)
round.sh <판> scan [--dry-run] [--max N] [--out f]  # 레인 산출 → 자격 큐(입구 규칙 · 사유 코드 · 성과 수치 안 읽음)
round.sh <판> standing-measure          # 배리어 → 대기 항목마다 R2 대조 · 지문 · 정본 셀 워커 → 판정(원장 · standing_visible.json)
round.sh <판> standing-report [--send]  # 통과 = 엔진마다 push 1통 · 미달 · 미시험 = 일 요약 1통(무음)
round.sh <판> standing-status           # 측정 · 판정 · 보고 · Superfan 대기 · R2 차단 · 원장 사슬
round.sh <판> superfan-mark --codes a,b --kind pass|daily --p2 <id> --t2 <id>   # 규약 §11-1
```
- 다른 작업 트리(worktree)에서 돌릴 때만 `RC_ROOT_POSIX` · `RC_ROOT_WIN` + `R_ENVIRON_USER`(QM_ROOT 를 그 트리로)를 준다. 기본은 저장소다.

정기 실행(2026-11-10) — `bash 02_Infrastructure/ops/standing_board_run.sh [--dry-run] [--send]`: 등록된 상설 판(사양 `standing: true` · round_id = 디렉터리 이름 · 사전등록 정본 있음)마다 한 틱 = `scan` → 입구 통과 대기 항목(`pending`)이 있고 리프레시 배리어(`refresh_barrier.sh status` 한 번 · 잠김 · 판정기 없음 = 이번 틱 측정 건너뜀)가 열려 있으면 `standing-measure` → `standing-report`(기본 드라이런 · `--send` 일 때만 발송). 판이 없으면 조용히 0 종료. 자체 잠금 `.cache/standing_board_run.lock`(살아 있는 보유자 = 건너뛰고 0 · 죽은 pid = 인계) · 로그 `.cache/scheduler_logs/standing_board_<시각>.log` · 어느 단계든 실패하면 rc 1(다른 단계 · 판은 계속). `--dry-run` = 할 일 · 배리어 · 잠금 상태만 출력(round.sh · R 미호출). **예약 작업 등록은 하지 않았다**(도훈 승인 뒤 별도). 시험 = `08_Tests/ops/test_standing_board_run.sh`.

- 입구 수리(11-10): 방향 층은 호출마다 `direction` 인자로 가른다 — `"registry"` | `"defensive"` 문자열 상수 = `factor_db_static`(engine_native 허용 시 함께 허용) · 인자 없음 · `"ic_asof"` · 판정 불가 값 = `factor_db_asof`. 결합용 뷰 `fc_load_month(s)` · `fc_daily` 도 같은 규칙으로 본다. 레인 산출이 팩터 DB 수리 전 측정이어도(`contracts/factor_db_vintage.R::fdv_stale = TRUE`) 입구에서 빼지 않고 표식만 남긴다(열 `factor_db_vintage` = stale | current | na — 상설 측정이 지금의 팩터 DB 위에서 새로 잰다 · 시험은 `RC_FDV_LEDGER` 로 임시 원장). 낡은 측정의 소비는 A 자격 관문과 P4 기저 풀(등급으로 들어오는 경로)이 막는다. 자격 통과 목록 읽기 = `rc_standing_qualified(program)`.

## P4 강화 사슬 (p4_chain · v1/p4.R · v10.2 · 2026-11-10)

한 사슬 = 기저 엔진 1개에서 출발해 **한 걸음에 가설 하나 · 칸 하나 · 블록 유형 하나**씩 얹는 순차 루프(사슬형 — 스윕 아님). 규칙(채택 규칙 · 예산 · 생성기 판 핀)은 사슬 판 `chain_spec.json`(스키마 `rc_p4_chain_v1`)에 한 번 등록하고, 걸음은 추가 전용 원장 `chain_steps.jsonl`(앞 줄 md5 사슬)에 흐른다. 루프가 고쳐 쓰는 것은 생성기(`06_Registry/rx_generator.json` · 본문 `04_Research/programs/P4_ASSEMBLY/_generator/g<n>/*.md`)뿐이고, 판정 규칙을 바꾸려면 새 사슬 판을 등록한다.

```r
source("04_Research/programs/_lib/round_core/v1/load.R")
pool <- rc_p4_base_pool()                               # 등록부 kind = engine + 상설 자격 → 자격(상설 통과 ∨ 권위 등급 A/B) · 제외 사유 코드
gap  <- rc_p4_gap("<산출 폴더>")                         # 보는 창 A 하한별 값 · 문턱 · 여유 · 병목(시험 창 값 없음)
rc_p4_base_cell_spec("<풀 key>", pool, out_path = "<f>.json")   # 기저 칸 사양 = P1 표준 구성 생성기(rc_p1_cell_spec) 그대로 · 논문 메타 = rc_standing_paper
rc_p4_chain_new("<사슬 디렉터리>", "P4C01_<이름>", base_key = "<풀 key>", pool,   # base_cell_spec 생략 = 위 도우미가 <사슬>/base_cell_spec.json 을 만든다
                adoption_rules = list(                    # 보는 창 지표만 · 숫자는 정본 참조(value_ref) + source 문구(필수 셋: dS_vis · uc_vis · d_dd_capture_median_vis)
                  list(id = "improve", type = "threshold", label = "보는 창 S 개선", metric = "dS_vis", op = ">=",
                       value_ref = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.tie_eps", source = "…"),
                  list(id = "uc_floor", type = "threshold", label = "상승 포착 하한", metric = "uc_vis", op = ">=",
                       value_ref = "06_Registry/behavior_card.json::uc_floor", source = "…"),
                  list(id = "crisis_no_worse", type = "threshold", label = "위기 하락 포착 비악화", metric = "d_dd_capture_median_vis", op = "<=",
                       value = 0, basis = "정의 — 비악화 = 부모 이하", source = "…")),
                budget = list(max_steps = <정수>, max_steps_source = "<출처>", noise_k = <정수>, noise_k_source = "<출처>"))   # 예산 숫자는 사양 작성자가 출처와 함께(기본값 없음)
rc_p4_chain_register("<사슬 디렉터리>", pool, p1 = "<철학 P1 R-id>", t1 = "<판단 T1 R-id>")   # 원장 첫 줄(사양 md5 · 해석된 규칙 · 기저 보는 창 지표 · 영수증)
```

```bash
round.sh - p4-base-spec --key "<풀 key>" --out <f>.json                    # 기저 칸 사양만 따로 만들 때
round.sh <사슬 디렉터리> p4-pool [--out f] · p4-check · p4-design [--out f]  # 설계 입력 = 생성기 입력(보는 창만)
round.sh <사슬 디렉터리> p4-register --p1 <R-id> --t1 <R-id>              # 감독 영수증 없으면 거부
round.sh <사슬 디렉터리> p4-base-measure                              # 기준 칸(k = 0) — 걸음 전 필수 · 기저 칸 사양을 걸음과 같은 러너 · 배리어 · 지문 · 판 표식으로 → base_measured
round.sh <사슬 디렉터리> p4-step-open --k 1 --hypothesis "…" --mechanism "…" --block <유형> --cell <칸 사양> --parent 0 --generator g1
round.sh <사슬 디렉터리> p4-step-measure --k 1                             # 배리어 대기 → 칸 사양 md5 대조 → 정본 셀 워커 → 원장 step_measured(종료 0 · 4 배리어 · 1 실패)
round.sh <사슬 디렉터리> p4-step-decide --k 1 [--artifacts <산출 폴더>]     # 산출 = step_measured 기록(넘기면 같아야 함) · 보는 창 지표(부모 0 = base_measured) → 채택 규칙 → accept | reject · r7
round.sh <사슬 디렉터리> p4-status · p4-close --note "…" --probe "…" --probe "…" [--lesson "…"] [--regrade-write] --p2 <R-id> --t2 <R-id>
round.sh - p4-generator-review [--out f]                                   # 블록 유형별 채택률 · 보는 창 dS_vis · 주된 기각 사유(다음 판 재료)
```
- 명령 순서: `p4-register` → **`p4-base-measure`** → (`p4-design` → `p4-step-open` → `p4-step-measure` → `p4-step-decide`)× → `p4-close`. 기준 칸 측정 전에는 걸음 열기 · 측정 · 판정 · 설계 입력이 거부된다(건너뛰기 경로 없음).
- 원장(`chain_steps.jsonl`) 이벤트: `chain_registered`(규칙 해석본 · 영수증 · 풀 산출 지표 `base_metrics` = **참고 기록 · 판정에 안 씀**) · `base_measured` | `base_measure_failed` · `step_open` · `step_measured` | `step_measure_failed` · `step_result`(`artifacts_source` · `parent_basis`) · `chain_closed`.
- 기준 칸 측정(`rc_p4_base_measure(chain_dir, root, runner, barrier, fingerprint, vintage, metrics_fun)`): 기저 칸 사양 md5 = 사슬 판 확인 → 측정 사본 `measure/k0.spec.json`(sweep · family_root = 사슬 id · 시행 1) · role base → `base_measured`{artifacts · measured_spec_md5 · metrics(보는 창 — `rc_p4_visible_metrics`) · vintage · same_construction(기록) · measured_at}. 첫 걸음을 포함한 모든 비교의 기저 지표 = `base_measured$metrics` · 닫기 재채점 시행 집합의 기저 = `base_measured$artifacts`.
- 팩터 DB 판 표식: 측정마다 `contracts/factor_db_vintage.R::fdv_stamp` 의 직렬화 md5(`vintage.id` · 수리 수)를 `base_measured` · `step_measured` 에 적는다(완료 시각은 τ_D 뒤 날짜라 싣지 않는다). 걸음 측정 직전 표식 ≠ 기준 칸 표식이면 재지 않고 사유(원장 무기록) — "이 사슬을 닫고 새 사슬에서 기준 칸부터 다시". 판정도 표식이 다른 측정은 거부 · 닫기는 허용 · 표식 판독 불가 = 측정 거부(fail-closed).
- 걸음 측정(`rc_p4_step_measure(chain_dir, k, root, runner, barrier, fingerprint)`): 기준 칸 측정됨 · 열린 미판정 걸음 · 칸 사양 md5 = 열 때(R2) · 리프레시 배리어(`refresh_barrier.R::rb_status` — held · error 면 재지 않고 사유 반환 · 원장 무기록) → 측정 사본 `<사슬>/measure/k<k>.spec.json`(열린 사양 + `selection_accounting` 만 다시 씀: `selection_type = sweep` · `family_root = 사슬 id` · 계보 누적 시행 = 기저 1 + 지금까지 연 걸음 수 · `n_trials_basis` 문구 — 사슬도 회계는 스윕) → 기본 러너 `rc_p4_runner_default` = `Rscript rf_cell_worker.R <사양> 1 <사슬>_k<k> <결과 json>`(`v1/measure_cell.R` 와 같은 호출 · 요인 분석 끔 · **2계층 모듈 풀 등재 끔** `QVEST_RP_REGISTER = 0` — 기준 칸 · 걸음 칸 모두) → 데이터 지문 앞뒤 대조. ok ∧ 산출 폴더 ∧ 지문 같음 = `step_measured`{k · artifacts · vintage · measured_at · md5}, 아니면 `step_measure_failed`(다시 잴 수 있다). 시험은 `runner` 에 가짜 러너를 넣는다.
- 감독 영수증(라운드 등록 ⑥ 과 같은 규율 — 판단 원장 `06_Registry/q_judgment_ledger.json`): 등록 = 철학 P1(`register.R::rc_p1_check` 재사용 — 대상 round = 사슬 id · 파일 `…_P1_P4Cnn.md`) + 판단 T1 · 닫기 = 철학 P2 + 판단 T2 · 생성기 개정 `rxg_revise(…, philosophy_review = <R-id>)` = 철학 P1 | P4 · 대상 round = `P4_generator_<새 판 id>`. 공통: id 실재 · 역할 · 트리거 · 대상 일치 · 파일 실재 · 도전 · 정지 응답 · 열린 보류 요청 없음. 시험 우회 = `ledger` · `review_root` 인자(임시 원장)뿐.
- 걸음 열기 기계 검사: 앞 걸음 판정됨 · k 연번 · 칸 사양 1개(처음 보는 md5) · 부모 = 사슬 머리 · 부모와 **한 블록 유형만** 다름(고정 축 · 어휘 밖 축 거부 · 기저 변경은 풀 안 자격 엔진만) · 가설 · 기전 문장 · τ_D 뒤 날짜 없음 · 예산 안 · 생성기 md5 = 사슬 판.
- 닫기: 최종 후보 = 마지막 채택 걸음(채택 0 · 걸음 ≥ 1 이면 기저 자신 k = 0 · 기준 칸 산출 · 걸음 0 = `no_candidate`) · 결과 원장(`rc_outcome_record` · extra = 생성기 판 · 걸음 수 · 블록 유형별 채택/기각 · P2 · T2 id) · 마감 훅 `programs/selection_regrade.R::sr_regrade`(기준 칸 산출 + 모든 걸음 칸 = 시행 집합 · 결과는 `finalize.json`(사람 쪽)에만 · 원장엔 상태 · md5) → 새 등급 A 면 후보 관문 `programs/round_candidate_gate.R::rcg_route(후보, <사슬>_k<k>, 측정 사본 사양, root, write)`(파일이 있을 때 · 요약 action · eligible · codes · path 는 `finalize.json` 에만). 원장 · 결과 원장의 `candidate_gate` = `pending`(관문 파일 없음) | `evaluated`(A 아님도 같은 값 — 등급이 상태로 새지 않게) | `error` | `not_run`. Judge 요청 파일은 쓰지 않는다. 모듈 풀 등재 = 최종 후보 1개만 · `regrade_write` ∧ 재채점 뒤 등급 A | B 일 때 정본 등재기 `contracts/register_measured_module.R::rmm_register_measured(후보 산출, origin_mode = "replication", meta = 사슬)`를 측정 밖에서 사후 호출(sim 없이 계약 CSV 로 재조립 — `rf_replication_verify.R` 감사 뒤 등재와 같은 경로 · 자격은 등재기의 계약 술어가 다시 낸다) · `module_pool` = registered | not_registered | not_attempted | pending_manual(등재기 없음) | error → `finalize.json` · 결과 원장 줄.
- 처방 도구 상자(`02_Infrastructure/programs/rx_round.R`): `rx_validate(impl, root, pool)` 이 `base_signal`(풀 key · `engine_blend` keys ≥ 2 · 경로 지정 거부)과 `factors[].direction`(ic_asof | registry | defensive — defensive 는 등록부 방어 방향이 있는 팩터만)을 받는다 · 도구 상자 표에 방어 방향 열 · 헌장 격차 절 `rx_charter_gap_md(gap)`.
- 시험: `08_Tests/programs/test_round_core_v1_p4_chain.R`(격리 — 임시 등록부 · 원장 · 생성기 등록부 · 판단 원장 · 합성 산출물 · 가짜 러너 · 가짜 재채점 · 관문 파일 · 실제 측정 없음).

## 모듈 (v1)

| 파일 | 내용 |
|---|---|
| `v1/load.R` | 단일 진입 |
| `v1/util.R` | 경로 · md5 · 원자적 JSON · 과반 · 안전 호출 · τ_D 가림/누출 검사 · 참조 해석 · 실행 시간 기록 |
| `v1/rules.R` | 규칙 선언(threshold · all_of · any_of · report) — 검사 · 해석 · 판정 · 문장 · 표 |
| `v1/metrics.R` | 지표 공급자(β-통제 알파 · 증분 알파 · 집중 · S) — 계약 호출 |
| `v1/spec.R` | 라운드 사양 검사 |
| `v1/p1.R` | P1 엔진 자격 판정 · 표준 구성 칸 사양(P0R01 C0 선례 · 정본 대조) · 라운드 골격 |
| `v1/pins.R` | 핀 계산 · 대조 단일 함수(코어 매니페스트 · 운영 파일 · 엔진 · 패키지 · R 판) |
| `v1/cell_eval.R` | 칸 평가(rk_eval_cell 이관) + 내용 주소 캐시 · 원자료 1회 적재 |
| `v1/register.R` | 초안 · 점검 기록(drafts.json — 점검본 사본 없음) · 등록 조건 ①~⑧ · 종료 기록 |
| `v1/driver.R` | 단계 실행(check · precheck · plan · draft · reviewed · register · evaluate · report · close) |
| `v1/measure_cell.R` · `v1/fingerprint.sh` | 칸 측정(정본 셀 워커) · 데이터 지문 |
| `v1/standing.R` | 상설 판 — 사양 검사 · 생성 함수 핀 · 레인 스캔(입구 규칙 · 사유 코드) · 항목 넣기 · 항목 R2 · 측정 · 판정 · 원장(추가 전용 사슬) · 보고 · Superfan 표식 · 상태 |
| `v1/p4.R` | P4 강화 사슬 — 기저 풀 · 격차(보는 창 A 하한 여유 · 병목) · 사슬 판 검사 · 걸음 원장(추가 전용 사슬) · 걸음 열기 · 판정 · 설계 입력 · 닫기(결과 원장 · 마감 훅) · 생성기 판(rxg_*) · 생성기 검토 |
| `v1/pair.R` | 짝 평가 골격(단계 목록 · 라운드 훅 · 미시험 사유) · P2 · P3 공용 도우미(위기 과반 · 깊은 위기 · 사이클 · 집중 · 회복 · 보유 대조 · 공통 창 · β 짝 사본) · 보는 창 / 사람 쪽 칸 평가 · 라운드 판정(판정 칸 수 · 판정어별 칸 수) · 선택 · 샤딩 · 메모(원자료 · ta_load_market · MC8) |
| `v1/p2.R` | P2(장치 × 엔진) 템플릿 — P2R04 판정 ①~⑭ 단계 · 기록 · 진단 읽기 · R7 · A 거리 · 보는 창 파일(τ_D 가림 · 전수 검사) · P2R05 범용분(시드 띠 · 판정 여유 · Dimson β · 위기 유형 · 유동성 3분위 귀속) · 사양 라운드 판정 |
| `v1/p3.R` | P3(구성 변형) 템플릿 — P3R03 결정 a~e · S · 알파 · β 짝(중앙값형) · 기전 방어 · 이력 탈락 · 후보 꼬리표 · 사양 라운드 판정 |
| `v1/rules_p2.R` | rules.R 선언 형식의 P2 규칙 종류 — 위기 과반 · β 짝 승 · 비열등 알파 · 상승 포착 · 축 감사 + 판정 표 · 선언 = 단계 판정 대조 |
| `rejudge/` | 끝난 라운드 재판정(결과 동일 실증) — 구판 고유 규칙(`P2R04_ext.R` · `P2R03_ext.R` · `P3R03_ext.R`) · 구 이름 심(`shims.R` — 구 픽스처를 코어로) · 재현 루트(`make_repro_root.R`) · 실행 · 대조 · 요약(`rejudge.R` · `run_rejudge.sh` · `compare.R` · `summarize.R` → `RESULTS.json`) · 캐시 실증(`cache_check.R`) · 속도표(`perf_table.R` → `../PERF.json`) · 구판 격리 실행(`legacy_sandbox.R` — 차이 분류) · P2R05 황금값(`p2r05_golden.R`) |
| `round.sh` | 셸 진입 — 측정 파이프라인 · 샤딩 평가(칸 평가 샤드 → 짝 평가 샤드 → 병합 종합) |
| `templates/DESIGN_p1.md` | 사고 기록 템플릿(코어 승계 항목은 다시 쓰지 않는다) |

## P2 · P3 라운드(사양만 쓴다)
- `round_spec.json` — `template: p2_device | p3_construction` · 칸(`code` · `engine` · `role` · `component` · `spec`) · `params`(판정 상수: 값 + 근거 또는 정본 참조) · `devices` · `diagnostics` · `rules`(P2 종류 포함 선언).
- 고유 규칙이 필요하면 `ext`(라운드 디렉터리 `round_ext.R`)에 `RC_EXT_CFG` · `RC_EXT_HOOKS`(단계 교체) · `RC_EXT_READINGS`(진단 읽기) · `RC_EXT_RULES_MAP` 만 쓴다.
- 판정 단계 · 기록 · 라운드 판정 · 보는 창 파일은 코어가 한다. 판정 시작에 선언 규칙과 단계 판정을 칸마다 대조해 어긋나면 판정하지 않는다(문구 표류 차단).

## 검증
- `08_Tests/programs/test_round_core_v1.R`: 규칙 · 사양 · P1R01 결과 동일. 원래 evaluate.R 격리 사본과 바이트 동일한지 본다.
- `08_Tests/programs/test_round_core_v1_flow.R`: 격리 흐름. 등록 거부 7종 · 등록 → 판정 → 종료 · R2 · 캐시 키 · 핀 · 표준 구성을 본다.
- `08_Tests/programs/test_round_core_v1_standing.R`: 상설 판 격리(RC_SA_ROOT · 임시 등록부 · 임시 원장 · 임시 레인). 입구 사유 코드 전수 · 주석 토큰 양성 대조 · 성과 무관 음성 대조 · 등록 → 스캔 → 측정(대체 워커) → 판정(코어 P1 판정과 같은 값) → 보고 · 항목 R2 거부 6종 · 칸 평가 예외 재시도 · 원장 사슬 변조 · 추가 잠금 · 새 판. 소스 텍스트 치환 뮤테이션 15종 전부 검출(10-20).
- `08_Tests/programs/test_round_core_v1_p2.R`(가벼움): 구 라운드 픽스처 3종을 코어 심으로(P2R04 52 · P2R03 33 · P3R03 48) · 코어 뮤테이션 15 · P2 규칙 종류 · 최소 사본 · 샤딩 · 메모 · τ_D · 사양 라운드 배선 · P2R05 범용분 = 원판 황금값 53 사례(`08_Tests/fixtures/round_core_p2r05_golden.json` · 생성기 `rejudge/p2r05_golden.R`) · 재판정 요약(`rejudge/RESULTS.json`).
- `08_Tests/programs/heavy_round_core_v1_p2_rejudge.R`(무거움 · SUITES 밖): 등록 커밋 핀 판 재현 루트 위에서 P2R04 → P2R03 → P3R03 재판정 · 저장본 대조 · 작업 사본 패킷 대조 · 요약 갱신.
  - 10-20 결과(`rejudge/RESULTS.json`): 세 라운드 판정 · 칸 판정 · 핵심 수치 · 보는 창 / 사람 쪽 파일 구조 차이 0 · 작업 사본 패킷 16/16 · 28/28 · 10/10 바이트 동일.
- `PERF.json`: 최종 판정 전후 시간(등록 당일 로그 · 같은 날 구판 격리 사본 짝 · 스레드 실험) · 캐시 · 메모 실증(`rejudge/cache_check.R`). 짝 평가 시간의 대부분은 패킷(dp_build) — 데이터 표 스레드 수는 거의 무관(8스레드 −6%)하고 샤드 수 K 가 손잡이다.

## 다음
- 측정 서버 `ms_submit` 연결(WP2) — 상설 측정(`standing-measure`)도 서버가 생기면 그쪽을 먼저 쓴다.
- P1 상설 자격(WP5) — 코어 · 시험 · P1S01 사양 완료 · **등록은 원 세션**(P2R05 종료 또는 WP3 쓰기 잠금 · v1 출시 · WP2 재핀 뒤).
- v1 출시(RELEASES.json).
