# Qvest — 리서치 큐 무인 배분 (alpha-research · risk · optimizer · regime · 측정 백로그)

발효 2026-08-21 (도훈 결정 "무인 개시까지") / **2026-08-22 확장** (도훈 결정:
"route=alpha 항목을 alpha-research 로" + "등재→측정 칸 배선").

## 왜 이 배선이 생겼나 (실측)

- `paper_research_dispatch.R` 738줄에 에이전트 스폰 **0건** — 7행 주석이 `flag(수동 분석)` 로 설계를 명시.
- mode_queue 누적 20파일 / 고유 93편 vs `method_registry.json` 16건, 전건 `added` 2026-08-08~09,
  그 뒤 **12일간 등재 0건**(08-09 이후 신규 유입 15편 → 등재 0편).
- **등재만으로는 리서치가 아니다**: 등재 16건 중 `measurement_status` 기입은 **1건**뿐이었다.
  큐→등재만 열면 어댑터가 쌓이고 원장이 다시 멈춘다 — 그래서 측정 칸을 같은 런에 넣는다.
- 무인이 닿는 에이전트가 **`alpha-search` 하나뿐**이었다. QEPM 코어(`alpha-research`)는 0건.

## 입력

`.cache/research_queue_pending.json` — 술어 정본이 만든 미소비 목록.

생성: `research_pool_predicates.py research-queue-pending <stage_dir> <root> --json <out>`

각 항목: `lane · paper_id · title · reason` (+ lane별 부가 필드)

★이 목록을 직접 다시 계산하지 말 것 — 술어 정본은 `02_Infrastructure/ops/research_pool_predicates.py`
한 곳이고, 소비자가 술어를 재구현한 것이 2026-08-02 3연발 결함(같은 날 세 소비자가 각각 조용히
틀린 숫자를 냄)의 원인이다.

## lane별 분기

| lane | 스폰 | 산출 |
|---|---|---|
| `qepm_dossier` | WT 의 **다음 단계 에이전트 1개**만 | `status.json.current_phase` 전이 |
| `paper_promotion` | `wt_create` → `alpha-hypothesis` → `alpha-research` | 새 WT + `alpha_package.json` |
| `method_measure` | 해당 어댑터를 **실측** | `method_registry` 의 그 method 에 `measurement_status`·`measured` 기입 |
| `alpha` | `alpha-hypothesis`(fable) → `alpha-research`(opus) | `alpha_hypothesis.json` → alpha 스펙 |
| `optimizer` | `optimizer-research` | 가중/사이징 어댑터 스펙 |
| `risk` | `risk-research` | Σ·tail·crowding 어댑터 스펙 |
| `regime` | `risk-research` | 국면 입력신호 평가 (regime 전담 에이전트 없음) |

**목록은 이미 `qepm_dossier` → `paper_promotion` → `method_measure` → `alpha` → opt/risk → regime 순으로 정렬돼 있다.**
위에서부터 **MAX_ITEMS 건**만 처리한다(상한 초과 금지). 순서를 바꾸지 말 것 — 이미 등재된 것을
끝내는 편이 새로 쌓는 것보다 값이 크다는 판단이 정렬에 박혀 있다.

### lane=qepm_dossier (QEPM 계속 — 최우선)

**왜 1순위인가**: 이미 알파까지 간 라운드를 판정까지 잇는 편이 새 논문을 또 쌓는 것보다 값이 크다.
실측 2026-08-22 — `alpha_package.json` 보유 WT 220건 중 **판정 전 103건**(ALPHA_DONE 78 ·
FORGE_DONE 15 · OPTIMIZER_DONE 5 · RISK_DONE 5)인데 **JUDGE 도달은 12건**뿐이다.
무인 러너 4종에 WT 진행 코드가 **0건**이라 알파 다음이 통째로 비어 있었다.

항목 필드: `wt_id · phase · next_agent`

1. **`next_agent` 하나만 스폰한다.** 한 런에서 여러 단계를 몰아 돌리지 않는다 —
   각 단계는 앞 단계 산출물을 읽는 계약이고, 중간 실패가 뒤 단계에 섞이면 판정이 오염된다.
   - `ALPHA_DONE` → `risk-research` (Σ + tail + stress + crowding + style)
   - `RISK_DONE` → `optimizer-research` (weights 결정)
   - `OPTIMIZER_DONE` → `forge` (run_all.R + backtest 통합, **실측 권위**)
   - `FORGE_DONE` → `judge` (Gate 0~18 + PIT 검증)
2. **역할 경계 절대 준수** (CLAUDE.md Multi-Agent 표):
   `risk-research` 는 alpha 수정 금지 · `optimizer-research` 는 alpha/risk 재해석 금지 ·
   `forge` 는 pure function(target_weights/cov 수정 금지) · `judge` 는 설계/구현 금지.
3. 단계 완료 후 그 WT 의 `status.json` 의 `current_phase` 를 다음 값으로 갱신한다
   (`RISK_DONE` / `OPTIMIZER_DONE` / `FORGE_DONE` / `JUDGE_DONE` 또는 `JUDGE_FAILED`).
   ★갱신하지 않으면 다음 런이 같은 단계를 또 돌린다 — 술어가 이 필드로 판정한다.
4. 진행 불가면(산출물 결손·계약 미충족) `status.json.blocker` 에 사유를 적고 넘어간다.
   억지 진행 금지 — 결손 위에 쌓은 판정은 판정이 아니다.
5. **`governor` 는 절대 스폰하지 않는다.** 이 레인은 judge 까지다. 자본 편입은 도훈 수동이며
   `book_state.json` 쓰기는 이 런의 어떤 경로에서도 금지다(AX-002 동급).

### lane=paper_promotion (경량 → QEPM 승격)

**왜 있나**: 라우터는 `screen_priority`·`verdict`·`grade` 로 가치를 판정하는데, 그 판정이
QEPM 으로 올라가는 코드가 **없었다**(무인 러너 4종 `wt_create` 0건 · 프롬프트 3종 WorkTask
언급 0건 · grade B 3건 승격 0건, 2026-08-22 실측). 이 레인이 그 게이트다.

**기준**: `grade ∈ {A, B}` ∧ 오염 라벨 없음 ∧ 아직 WT 가 그 `strategy_id` 를 참조하지 않음.
`fr_eligible` 은 국면배합(FR) 소비 자격이지 정식 라운드 값어치의 척도가 아니므로 기준이 아니다.

항목 필드: `strategy_id · grade · title · sim_result_path · bt_result_path · registered_at`

1. **승격은 등급 복사가 아니다.** 경량 산출은 `sim_result.rds` 이고 QEPM 은 `alpha_package.json`
   이라 형식이 다르다. 반드시 다음 순서로 **다시 만든다**:
   - `wt_create(hypothesis_title=<전략 아이디어 한 줄>, theme=<계열>, wt_type="discovery",
     discovery_of=<strategy_id>)` → WT id 발급 (`02_Infrastructure/worktask/worktask_manager.R`)
   - `alpha-hypothesis`(fable) 스폰 → ①메커니즘 ②가설 ③반증 조건 ④국면 경계 → `alpha_hypothesis.json`
   - `alpha-research`(opus) 스폰 → 가설 **승계**(재작성 금지) → ⑤AST + factor specs + ICIR
     → `alpha_package.json`
2. **경량 결과를 근거로 쓰되 재사용하지 않는다.** `sim_result`/`bt_result` 는 "왜 이걸 승격했나"
   의 근거로 인용하고, QEPM 의 α̂ 는 alpha-research 가 새로 만든다. 경량 수치를 QEPM 산출로
   옮겨 적으면 측정 계보가 끊긴다.
3. 착수 전 `hypothesis_index` lookup + `06_Registry/alpha_frontier_queue.json`(schema 2.0) 확인 의무.
   **착수는 `status=open` 인 항목만** — `status=parked` ∧ `parked_reason=dohoon_decision`/
   `dohoon_data_work` 는 착수 금지. 이미 같은 기전이 라운드로 돈 적 있으면 그 사실을 적고
   **건너뛴다**(중복 라운드 금지). 종결분은 `06_Registry/_archive/alpha_frontier_queue_done_*.json`.
4. WT 생성 후 `status.json.current_phase` 를 `ALPHA_DONE` 으로 두면 다음 런의 `qepm_dossier`
   레인이 risk → optimizer → forge → judge 로 **이어받는다**. 여기서 risk 를 직접 부르지 않는다
   — 한 런은 한 단계만 진행한다.
5. 승격 불가면(전략 산출물 결손·가설 재구성 불가) 이유를 `MODEQ_DONE` 줄에 남기고 넘어간다.

### lane=method_measure (측정 백로그 — 최우선)

어댑터는 이미 `method_registry` 에 있다. 할 일은 **실측**이다.

1. `entrypoint` / `adapter_kind` 로 어댑터를 찾아 실행 가능한지 확인한다.
2. 성능 수치는 **손계산 금지** — `02_Infrastructure/contracts/canonical_screen_bt.R::canonical_screen_bt()`
   또는 `build_bt_result()` 경유 (`.claude/rules/measurement-graduation.md` §1).
   `prod(1+r)` / `cumprod` / `0.8*r1+0.2*r2` 자체합성은 그 자체로 위반이다.
3. 그 method 레코드에 `measurement_status`(무엇을 어떤 프레임으로 쟀고 판정이 무엇인지 서술) +
   `measured`(date · basis · 수치) 를 기입한다.
3b. **시점을 분리해 적는다** — `recorded_at`(원장 기입일) · `source_measured_at`(근거 수치가
   **실제로 산출된** 날) · 재현했다면 `reproduced_at`. 기존 계약 산출물을 전사하는 것은 허용되지만
   (유효한 측정이 있는데 재실행하는 건 낭비다) **기입일을 측정일로 적으면 안 된다.**
   ★2026-08-22 실사고: 08-13자 CSV 를 전사하고 `date: 2026-08-22` 로 적어 9일 된 계산이
   당일 측정처럼 보였다. 이 저장소가 반복해 데인 vintage 라벨 드리프트다(§7 pinning).
3c. **산문에 쓰는 수치도 산출물에서 나온 것만** 쓴다 — `measurement_status` 서술의 모든 숫자는
   `measured` 필드나 어댑터 출력에 대응물이 있어야 한다.
   ★같은 실사고: 구조화 필드는 전부 정확했는데 산문의 "40.8% 추세 판정"만 틀렸다
   (어댑터 실측은 98/271 = 36.2%). 구조는 검증되고 산문은 안 되므로, 산문이 마지막 구멍이다.
4. **음성이어도 기입한다** — "측정했더니 미달"이 곧 지식이다. 비우고 넘어가면 다음 런이 같은 걸 또 큐에 올린다.
5. 측정이 현 데이터/환경으로 불가하면 `verdict="blocked_by_capability"` + `blocker` 사유로 바꾼다
   (그러면 술어가 측정 큐에서 자동 제외한다 — 매 런 실패하며 토큰 태우는 것을 막는 배선이다).

### lane=alpha (QEPM 코어)

이 lane 의 대상 = **route=alpha ∧ kr_feasible ∧ `factor_candidate` 부재**.
= "KR 에서 될 것 같은데 아직 팩터가 없다" — 그래서 가설 설계가 필요한 것이다.
팩터가 이미 있는 건은 바로 백테할 수 있으므로 경량 레인(alpha-search)이 맡는다.
⚠**구성상 서로소가 아니다** — `alpha_pending()` 의 폴백이 `route=alpha ∧ kr_feasible`
만으로 참이라 술어상 겹친다. 이중 소비 해소는 아래 4번의 **선점 기록**이 담당한다.

1. `alpha-hypothesis` 를 먼저 스폰한다 — Step 0 발굴 + ①메커니즘 →②가설 →③반증 →④국면 경계.
   산출 = `alpha_hypothesis.json`. **팩터 소싱·실측·AST 구성은 이 에이전트 소관이 아니다.**
2. 이어서 `alpha-research` 를 스폰해 가설을 **승계**시킨다(재작성 금지). ⑤AST 구성 + factor specs + ICIR.
3. **Σ/weight 절대 금지** — risk/optimizer 경계 침범이다.
4. **소비 즉시 공용 원장에 기록**한다 — `stage_artifacts/paper_recharge/alpha_search_queue_done.json`
   의 `processed[]` 에 `paper_id` 를 append(+ `alpha_research_queue_done.json` 에도).
   ★이 레인과 경량 레인(alpha-search)은 술어상 **겹친다**(alpha_pending 의 폴백이
   `route=alpha ∧ kr_feasible` 만으로 참). 해소는 **선점** — 공용 원장에 남겨야 alpha-search 가
   같은 논문을 다시 태우지 않는다. 기록을 빠뜨리면 이중 소비가 난다.
5. 착수 전 `hypothesis_index` lookup + `06_Registry/alpha_frontier_queue.json`(schema 2.0) 확인
   의무. **`status=open` 만 착수** — `parked`(특히 `parked_reason=dohoon_decision`)는 금지.
   중복 라운드면 그 사실을 적고 건너뛴다.

### lane=optimizer / risk / regime

논문을 확인하고 해당 에이전트를 스폰해 **어댑터 스펙**을 만든다.
`06_Registry/method_registry.json::methods` 에 append:
`method_id · paper_id · paper_title · route · adapter_kind · entrypoint · free_params ·
kr_mapping · screen_axes{screen_priority, shrinkage_builtin, statistic_order} ·
verdict · measured · routed_on · added`

구현 불가면 `verdict="blocked_by_capability"` + `blocker` 사유를 적고 넘어간다
(선례 3건: StationaryAmbiguity / PathSignature / MFCCA). 억지 구현 금지.

#### optimizer/risk 2축 — 사전 스크린 (2026-08-23 라우터에서 이관)

> 이 절은 원래 `paper_router_prompt.md` STEP 1-b 에 있었다. 라우터를 lean 으로 줄이면서
> **소비 쪽인 여기로 옮긴다** — 축을 쓰는 것도 읽는 것도 이 레인이다.
> 근거 = 사후 실측 3편(ConformalKelly · ProperScoreGAS · PreferenceRobustDistortion)이
> **전부 게이트 미달**이었고 셋의 실패가 이 2축으로 설명됐다
> (원장 `06_Registry/method_registry.json::cross_method_synthesis`).

optimizer·risk 로 분류된 논문에는 아래 2축을 **반드시 함께 판정**해 `screen_axes` 에 기록한다.

| 축 | 값 | 판정 근거 |
|---|---|---|
| `shrinkage_builtin` | `yes` / `weak` / `no` | 방법 자체가 축소·정규화·사전분포를 내장하는가. 측정틀(25종·250일 창)에서 추정오차가 지배하므로 이게 1급 판별자다 — Σ 성분 분해에서 **0.647→0.846 을 가른 것은 축소**(분산 +0.076 · 상관 +0.071 · 상호작용 +0.052)였지 어떤 구조도 아니었다 |
| `statistic_order` | `<=2nd` / `higher` / `tail_quantile` | 방법이 의존하는 통계량의 차수. **고차·꼬리 통계는 축소를 얹어도 회수가 절반에 그친다** — PRD 는 공분산을 완전 축소(δ=1)해도 minvar_lw 에 0.181 못 미쳤고, 그 잔여가 목적함수 자체의 추정오차다. α=0.99·T=250 이면 관측 2~3개에 의존하는 통계를 최적화하는 셈 |

**우선순위 규칙**: `shrinkage_builtin=yes ∧ statistic_order<=2nd` = ⭐⭐ 우선 구현 /
`weak` 또는 `higher` = ⭐ 조건부 / `no ∧ tail_quantile` = 후순위(사후 posterior 낮음 — 실측 3/3 미달).

⚠ **이 2축은 기각 사유가 아니라 우선순위다.** 후순위여도 등재는 하고 `verdict`·`blocker` 를
명시한다(INV-7 — 경로-scoped 실패이지 방향 판결이 아니며, 일별 리밸·유니버스 확대·다른
비중 규칙에서는 재검토 대상). **실측 없이 이 축만으로 `infeasible` 판정 금지.**

★**키 이름과 값 어휘 고정 — 임의 변형 금지**(2026-08-13 적발). 세 키는 정확히
`shrinkage_builtin` · `statistic_order` · `screen_priority` 철자로 쓰고 `screen_priority` 값은
**`⭐⭐`/`⭐`/`후순위` 세 문자열만** 쓴다. 실사고: 07-27·08-04·08-08 세 날짜에 `screen_priority`
대신 숫자 `priority`(1/2/3) 28건을 실었고 — 프롬프트에 없는 임의 키였으므로 **소비자가 읽지
않아 표기해도 소비되지 않았다**. 두 키가 한 번도 같이 나오지 않아 `1/2/3 ↔ ⭐⭐/⭐/후순위`
**매핑 근거가 없어 사후 복구도 불가**하다. 라우터 산출 직후
`02_Infrastructure/ops/mode_queue_axis_audit.py --date <TODAY>` 가 채움률과 비정본 키 수를 찍는다.

## 공통 기록 의무

처리한 건마다 stdout 에 한 줄: `MODEQ_DONE <paper_id|method_id> <lane> <verdict>`.
러너가 이 줄을 세어 "exit 0 인데 0건"을 `zero_progress` 로 경보한다 — 형식을 지킬 것.

## 하드 가드 (위반 시 AX-002 동급)

- **자본 경로 금지**: `governor` 스폰 금지, `book_state.json` 쓰기 금지, admission 주장 금지.
- **라벨 의무**: 이 런의 모든 산출물은 `metric_type="canonical_screen_diag"` · `tier="screen_diagnostic"`.
  graduation HARD 3종(PORT_t 2.95 · oos_retention 0.7 · calmar 0.64)을 통과했다고 **주장하지 않는다**.
  실측 결과가 문턱을 넘더라도 자본 자격은 별도 절차(judge → governor 수동)다.
- **게이트 완화 제안 금지** — 문턱을 낮추자는 제안은 그 자체로 위반이다(AX-000 따름정리, INV-7).
- **PIT C1~C15** 언어 무관 전면 적용. 팩터 접근은 `load_month_factors()` 경유(C15).
- **중복 처리 금지**: 술어가 걸러주지만, 착수 전 `method_registry` / done 원장을 재확인한다.
- **연속성**: negative 판정이어도 `next_probe` 를 남긴다(답변원칙 §리서치 연속성 3호).

## 종료

처리 0건이어도 정상이다 — 다만 **왜 0건인지**를 한 줄로 남긴다(빈 출력 금지).
"무인 stdout 은 아무도 안 읽는다"는 성문이 있으므로, 결론은 반드시 원장(`method_registry` ·
`alpha_research_queue_done.json`)이나 경보 마커에 남는 형태로 만든다.
