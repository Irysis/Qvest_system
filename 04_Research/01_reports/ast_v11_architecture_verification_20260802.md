# AST 계층 v1.1 실작동 검증 — "가설 설계 실력이 올라갔는가"

**작성**: 2026-08-02 (Q-Lead 야간 자율 라운드)
**발단**: 도훈 지시 — *"지난 주에 새로운 아키텍처 도입한 qepm 모드도 병렬로 실행해주고, 신규 도입 아키텍처가 제대로 작동해서 가설 설계 실력이 올라갔는지도 확인해줘"*
**대상**: AST 계층 v1.1 (2026-07-25 발효, SOT `02_Infrastructure/docs/qvest_ast_v1_1_sot.md`)
**metric_type**: `harness_verification` (전략 성과 주장 없음 — 자본 판정과 무관)

---

## 0. 한 줄 판정

**절반은 작동하고 절반은 죽어 있었다.** 예방·강제 계층(Step 1~3)은 실제로 살아서 느슨한 가설을 기계적으로 반려한다 — 검증 중 **내가 직접 두 번 반려당했다**. 반면 학습 계층(Step 4~5, "실력이 올라간다"의 기전 본체)은 배선만 있고 **실전 표본이 8일간 0건**이었다 — 오늘 수리했고 즉시 55건이 쌓이기 시작했다.

| 계층 | 역할 | 07-25~08-02 상태 | 근거 |
|---|---|---|---|
| Step 1~3 (게이트·컴파일러·정적검증) | **예방** — 잘못 설계할 수 없게 | ⚠️ **절반만** 작동 → 수리 | 게이트 8/8 block · **정적검증은 빈 순회 PASS(§2-6)** |
| Step 4 (구조특징 로깅) | **관측** — 무엇이 통했는지 축적 | ❌ 실전 캡처 0 → 수리 | live_with_ast 0 실측 |
| Step 5 (complexity_prior 주입) | **학습** — 실력이 실제로 오르는 지점 | ⛔ 미도달 (Step 4 종속) | N=0 < 30 |

즉 **"가설 설계 실력이 올라갔는가"의 정직한 답은 "설계 하한선은 올라갔고, 학습 루프는 아직 한 바퀴도 돌지 않았다"** 이다.

---

## 1. Step 1~3 — 작동 확인 (위반 주입 8/8)

게이트 `02_Infrastructure/hooks/ast_spec_gate.sh` 는 부팅 hook-fire 발화 목록에 한 번도 오른 적이 없었다. 조건부 훅이라 "트리거 미도달"일 수도, "차단 실효 사망"일 수도 있는데 **겉보기가 같고**, 게이트 전용 위반 주입 테스트가 부재해 판별 수단이 없었다. 그래서 직접 주입했다.

신설 `08_Tests/hooks/test_ast_spec_gate.sh` — **PASS=8 FAIL=0**:

| 케이스 | 주입 내용 | 결과 |
|---|---|---|
| A1 | 규약 준수 스펙 | 통과 (오탐 게이트 아님) |
| B1 | `mechanism.agent` 공백 | **block** |
| B2 | `mechanism.friction` 키 제거 | **block** |
| B3 | `regime_scope.weakens_or_reverses_in` 빈 배열 | **block** |
| B4 | `falsification` 빈 배열 | **block** |
| B5 | `LEAD` 연산자 (𝒪 밖 · 미래참조) | **block** |
| C1 | alpha_package 무관 payload | 조기-exit(무해) |
| C2 | 구식 패키지(spec_version 부재) | 통과 + advisory (하위호환) |

### 1-1. ★게이트가 나를 두 번 반려했다 — 이것이 "실력 상승"의 실체

테스트 픽스처로 "그럴듯한" v1.1 스펙을 처음 작성했더니 게이트가 순차로 두 번 반려했다. 이 반려 내역이 곧 **AST가 가설 설계에 강제하는 것의 목록**이다.

**반려 1 — 반증 조건의 자연어 도피**
```
초안:   "falsification": ["수출비중 하위 그룹에서 신호가 소멸"]
게이트: block — falsification 검증 실패 — [0] field_dictionary 밖:
        수출비중 하위 그룹에서 신호가 소멸
        (field_dictionary = factor_registry 373 팩터명 + ast_field_map_v0 group_id 58)
정정:   "falsification": [{"field":"V02_EP","expectation":"밸류 축 통제 후에도 잔존 신호가 있어야 한다"}]
```
그럴듯하게 읽히지만 **누구도 실제로 확인할 수 없는 반증 조건**이었다. 게이트는 "field_dictionary 안의 실재 필드를 지목하라"고 요구한다 — 검증 가능한 형태로만 반증 조건을 쓸 수 있다. 이것이 SOT §1의 "성과 동어반복 금지"를 기계화한 것이다.

**반려 2 — PIT 기준시점 부재**
```
게이트: block — ast_verify 실행 실패(ValueError: sig_date 결측) — PIT 정적검증 불가 (fail-closed)
정정:   "pit": {"sig_date":"2026-06-30","decision_ts":"2026-07-01"}
```
기준시점 없이는 리프 가용시각 상향 전파가 성립하지 않으므로 **판정 불가를 통과로 처리하지 않았다**(fail-closed). 침묵 통과 금지 원칙이 실제로 걸렸다.

**해석**: 게이트가 없었다면 두 스펙 다 "잘 쓴 가설"로 보였을 것이다. 특히 반려 1은 사람이 리뷰해도 놓치기 쉽다 — 문장이 자연스럽기 때문이다. **가설 설계의 하한선을 기계가 들어올린다는 주장은 실증됐다.**

**한계 (정직)**: 이것은 *하한선* 상승이지 *상한선* 상승이 아니다. 게이트는 나쁜 스펙을 막을 뿐 좋은 가설을 만들지 않는다(SOT §10 "알파를 만들지 않음"). 좋은 가설 쪽 기여는 Step 5의 몫이고, 그건 아직 0이다.

---

## 2. Step 4 — 실전 캡처 0 (수리 완료)

### 2-1. 증상

`06_Registry/ast_structure_log.jsonl` 399행. 겉보기엔 "쌓이고 있음". 실측:

```
ast_features non-null : 0
strategy_id  non-null : 0
ts 분포: 21행씩 동일-분 클러스터 (07-25 42 / 07-26 294 / 07-27 21 / 08-01 21 / 08-02 21)
07-27 블록과 08-01 블록의 값 시퀀스가 완전 동일
  (grade A,A,A,B,B,A,A,B,... port_t 3.5,...,-0.5,None,3.5,3.5,3.5)
```
→ **전량 테스트 배터리 반복 산물. 실전 레코드 0건.**

### 2-2. 근본 원인 4중

**① 설계 — 생존편향 구조 (SOT §5 M4 전제 반증)**

SOT §5는 배선점을 essence_score 단독으로 정하며 근거를 *"전 graduation 판정 경유라 capture 구조 보장"* 이라고 적었다. 실측은 반대다:

```r
# 02_Infrastructure/alpha_search/run_alpha_search.R:330
if (grade %in% c("A","A_NOVEL","A_DEF","B","B_DEF") || screen_remeasure) {
  auth <- .authoritative_remeasure(...)   # ← essence_score() 는 여기서만 호출
} else {
  cat("... proxy 유지, 실측 재측정 생략\n")   # ← 사이드카 미기록
}
```
essence_score 는 **proxy hurdle 사다리를 통과한 소수만** 경유한다. 2026-07-27 alpha-search 3라운드는 `grade=F/C`·`screen_pass=FALSE` 라 사다리를 생략했다(`hurdle_result.json` 실측). 이는 §5가 명문으로 요구한 **"governor 거절분 포함 전량 로깅(생존편향 방지)"의 정확한 반대** — 생존자만 남는 구조다.

**② 커버리지** — `canonical_screen_bt()` 는 essence_score 를 호출하지 않는다(주석 언급뿐). alpha 스크리닝 1급 지표 PORT_t 가 나오는 경로가 통째로 미도달이었다.

**③ 호출측** — main 저장소 `essence_score()` 호출자 **35곳 전수**가 `ast_features`/`strategy_id` 를 전달하지 않았다. 시그니처(`essence_score.R:200-201`)만 존재했다.

**④ 트리 분기** — worktree 6개 중 5개의 `essence_score.R` 이 사이드카 없는 구판. worktree 실행분은 원리적으로 기록 불가.

### 2-3. 위험

이 상태로 Step 5 에 진입하면 `N=399 ≥ 30` 으로 오판해 **합성 데이터로 complexity_prior 를 추정하고 그 숫자를 alpha 프롬프트에 주입**하게 된다. 가짜 사전분포가 실제 가설 설계를 지휘하는 형태이므로 AX-002 급이다.

### 2-4. 수리

| # | 내용 | 산출 |
|---|---|---|
| 1 | 단일 writer 신설 | `02_Infrastructure/contracts/ast_sidecar.R` — `ast_sidecar_log()` |
| 2 | **배선점 확장** | `lane="essence"` + `lane="canonical_screen"`(기각분이 반드시 지나는 지점) |
| 3 | 실전/테스트 분리 | `run_context`(기본 live, 배터리는 `QVEST_RUN_CONTEXT=test`) + `schema=v2` 태그 |
| 4 | 정직 카운터 | `ast_sidecar_status()` — live / live_with_ast / legacy_unlabeled 분리 |
| 5 | 침묵 실패 제거 | 실패 시 stderr WARN + `06_Registry/.ast_sidecar_failures.log` |
| 6 | 루트 resolver marker 검증 | `CLAUDE.md` + `06_Registry` 동시 존재(정규화 선행) |
| 7 | 위반 주입 테스트 | `08_Tests/contract_regression/test_ast_sidecar.R` — **24/24 PASS** |
| 8 | 배터리 편입 | `run_all_hooks.sh` SUITES +2 (총계 340 → 372) |
| 9 | 부팅 노출 | `[boot] AST sidecar: total=.. live=.. live_with_ast=.. legacy=..` |

**원장은 무변경 보존**(append-only). 구판 399행은 `schema` 필드 부재로 카운터가 자동 배제한다 — 삭제하지 않고 정직하게 `legacy_unlabeled` 로 별도 보고.

### 2-5. 수리 효과 (실측)

```
수리 전 (8일간):  total=399  live=0   live_with_ast=0   legacy=399
수리 직후:        total=456  live=55  live_with_ast=0   legacy=399
                  by_lane: essence 42 · canonical_screen 13
```

부수 효과: canonical_screen 레코드에 `diag_ew_port_t`(EW-유니버스 대비)가 자동 동반된다. v8.3 헌법의 **"기각 전 EW-대비·cap-tier 분해 확인 의무"가 이제 원장에 기계적으로 남는다** — 실측 예: `port_t 1.0319 / ew 0.087`, `port_t 0.9535 / ew -1.1202`.

`live_with_ast` 는 여전히 0이다. AST 구조특징은 alpha-research 가 `ast_compile` manifest 를 넘겨야 채워지며, WT-D20260802_001 라운드가 그 1호를 만드는 중이다.

---

## 2-6. ★정적검증기(ast_verify)는 실행되는 트리에서 죽어 있었다 — WT 라운드가 적발, 당일 수리

§1의 "Step 1~3 작동" 판정은 **게이트(`ast_spec_gate.sh`)의 스펙 검사**에 대해서만 참이었다. 그 아래 **PIT 정적검증기 `ast_verify.py` 는 컴파일러가 실제로 실행하는 트리를 순회하지 못했다.** WT-D20260802_001 alpha-research 라운드가 두 방언을 나란히 돌려 비교하다 적발했다(단일 실행으로는 판별 불가 — 깨끗한 PASS로 보인다).

**증상**: 동일 패키지에 대해 `leaf_count=0 · op_count=1 · verdict=PASS`. 리프를 하나도 보지 않고 통과를 발행했다. 오늘 밤 **세 번째 같은 계통** — "위반 0"과 "검사 0"이 같은 출력.

**원인 = 방언 4중 불일치** (컴파일러 `ast_compile.R` vs 검증기 `ast_verify.py`):

| 축 | 컴파일러 | 검증기(구) | 결과 |
|---|---|---|---|
| 자식 | `args` | `children` | 순회 0 |
| 리프 | `{"type":"leaf","class":...}` | `{"leaf":...}` | 리프 미인식 |
| 파라미터 | `params:{k:12}` | 최상위 `k` | 정상 트리가 "k 결측" 반려 |
| provenance | `contract` | `provenance` | 계약을 채웠는데 "결측" |

**수리 (2026-08-02)**:
1. **근본 방어 — 빈 순회는 PASS가 될 수 없다.** `leaf_count == 0` 이면 `FAIL_CONTRACT`. 방언이 또 갈리든 트리 형상이 바뀌든, 검사가 죽으면 통과가 아니라 계약 실패로 드러난다.
2. 4축 방언 이중 수용(진입 지점 정규화 — 하위 resolver 무수정).
3. **ALB-002 동반 수리**: `production_parity_verified` 가 `is not True` 로 판정돼 **정직한 `false` 선언이 결측과 동일 취급**됐다. 그러면 production 대응물이 없는 신규 패널은 (a) 정직히 false → FAIL (b) true → 거짓 주장 뿐이라 **정직한 진입 경로가 존재하지 않는다** — v8.3이 주력으로 선언한 비-return 신규 원천 lane을 기계가 막는 형태였다. 규범 정합: §7b의 production-코드-권위는 **incumbent base 비교**에 걸리는 요건이지 신규 후보의 존재 자격이 아니다. → 키 부재 = 계약 결측 / `false` = 통과 + `parity_unverified` 플래그(judge·governor 입력).

**수리 전후 (동일 실제 패키지)**:
```
전: leaf_count=0  op_count=1   verdict=PASS          ← 빈 순회 위장
후: leaf_count=4  op_count=12  verdict=PASS          ← 실제 검증 후 통과
    max_avail_ts=decision_ts=2026-07-31 · violations=0 · parity_unverified=4
```
같은 "PASS"지만 의미가 다르다.

**강제**: `08_Tests/hooks/test_ast_verify_dialect.sh` **12/12 PASS** — B1(빈 순회 ≠ PASS)이 근본 방어, **C1(동월 vintage 주입 → FAIL_LOOKAHEAD)이 PIT 검증 본체의 생존 지문**, D2(정직 false 통과), E1(k 진짜 결측은 여전히 반려 = 병합이 검사를 죽이지 않음), F1 음성 통제. 배터리 편입.

**남은 ALB** (`06_Registry/ast_leaf_table_bugs.jsonl`, WT 라운드가 원장 신설): ALB-003(미등재 리프의 restatement 검사 조용한 skip — 가장 개정이 심한 원천이 무경고 통과) · ALB-004(rawdata 가용성 t+0/t+1 불일치) · ALB-005/006(schema.json ↔ gate 의 falsification 타입·AST 위치·`pit.sig_date` 불일치 — 두 계층을 동시에 만족하는 패키지가 없다).

## 3. 부수 실측 — 하네스가 내 코드의 금칙을 잡았다

테스트 작성 중 `08_Tests/contract_regression/test_ast_sidecar.R` 에서 스크립트 최상위 `on.exit()` 로 환경변수 복원을 등록했는데, r-portability 계약(금칙 ②: 최상위 `on.exit()` 는 함수 프레임이 없어 **조용히 no-op**)에 걸려 `reg.finalizer(globalenv(), ..., onexit = TRUE)` 로 교정됐다. 정상종료·error halt·`quit(status=1)` 3경로 전부 미발화라 중도 실패 시 환경변수 오염이 후속 테스트로 샐 뻔했다.

**의미**: 2026-07-25 승격한 r-portability 계약도 실제로 살아 있다. 규범이 문서가 아니라 강제로 작동한 사례.

---

## 4. 남은 것 (next_probe)

1. **live_with_ast 1호 확보** — WT-D20260802_001 alpha-research 가 `ast_compile` manifest 를 essence_score/canonical_screen_bt 에 전달. 진행 중.
2. **호출자 strategy_id 배선** — 현재 canonical_screen 레코드의 `strategy_id` 가 기본값 `"canonical_screen"` 이다. 호출자가 실제 전략 ID를 넘기도록 배선해야 judge/governor verdict 사후 조인(SOT §5)이 성립한다.
3. **worktree 구판 동기화** — 5개 worktree 의 `essence_score.R` 이 구판. worktree 실행 라운드는 여전히 기록 누락된다. main 병합 또는 worktree 갱신 필요.
4. **Step 5 진입 조건 추적** — `live_with_ast ≥ 30`. 부팅이 매 세션 노출하므로 도달 시점이 자동 관측된다. SOT §5 규율(N<30 회귀 금지 / 30~80 단변량 / 80+ 다변량) 불변.
5. **escape 리프 비중 분기 모니터링** — SOT §2. escape 비중 상승 = 𝒪 확장 신호이자 사전분포 커버리지 절단. 현재 표본 0이라 미측정.
6. **run_alpha_search 사다리 자체** — 비용 절약 설계라 유지하되, 스크리닝 lane 배선으로 커버리지를 확보했다. 사다리 생략분의 구조특징이 필요해지면 hurdle_gate 지점 추가 배선이 후보.

**부활 조건(INV-7)**: SOT §5 의 essence_score-단독 배선점은 "모든 판정 경로가 essence_score 로 수렴"하도록 파이프라인이 통합되면 재검토 가능하다. 현 구조에서는 다중 lane 배선이 요건을 만족한다.

---

## 5. 규범 참조

- SOT 개정 기록: `02_Infrastructure/docs/qvest_ast_v1_1_sot.md` §5 개정 절 + §8 Step 4 라인
- 게이트: `02_Infrastructure/hooks/ast_spec_gate.sh` (등록 = `02_Infrastructure/hooks/policies/router_dispatch.json`, settings.json 아님)
- 규범: `.claude/rules/measurement-graduation.md` §1·§5 · `pit.md` C4/C5 · `02_Infrastructure/docs/rules/r-portability.md`
