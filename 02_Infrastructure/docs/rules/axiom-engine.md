# Axiom Engine — 4-Mode 2-Tier · 3층 산출물 모델 (Level 0 SOT)

**v2 (2026-07-04 엔진 재설계 — 도훈 mandate "L-code 전수점검 증류 + 엔진 사상부터 재설계 + 4모드 실가동 재배선"). 원전 r7(`00_Lawbook/Axiom_아키텍처/r7_axiom_design.md`) 5축 보존 + 4-mode 2-tier + Distilled 소비층 + 회수(retrieval) 1급.**
**위반 = AX-002 동급.** 상위 헌법: `.claude/rules/axioms.md`(global 공리 본문) / `measurement-graduation.md`(metric_type).

**재설계 전제 (A1·A2·A3 3진단 통합)**: 승격 0의 인과는 문턱이 아니라 **emit 입력 결측**(falsification 0/598 · portfolio_alpha_t 98% 결측). 따라서 v2는 **문턱·INV 일절 불변** — ①emit이 축을 채우게(스키마 v2) ②Ledger와 Law 사이 Distilled 소비층 신설 ③4모드 회수 배선 완결이 전부다. E2E 실증: 필수필드 완비 emit 1건 → 5축 전부 실입력 도달 → hurdles PPPPP (sandbox 2026-07-04).

## §0. 3층 산출물 모델

엔진의 산출물은 승격이 아니라 **재사용되는 지식**이다.

- **①Ledger** = L-code 원장 (`stage_artifacts/l_code/**` + `.cache/lcode_corpus.json`). 정직 전수 — 실험 사실의 불변 기록. DELETE는 무학습/파손/quarantine 마감분만 (`06_Registry/lcode_distill_plan_20260704.json` 집행).
- **②Distilled** = 클러스터 통합 지식 (`qepm/memory/axioms/distilled/DIST-<MODE>-NNN.json` + `06_Registry/distilled_knowledge.json` 통합 인덱스). **검색(hypothesis_index)·주입(axiom_context_inject/strategic_truths)·negative failure-ledger의 소비 단위.** CAND 골격(supporting_l_codes/scope/mechanism/polarity/metric_type) 상속 + `statement_refined`(사람이 읽는 1~2문장). lifecycle: `pending_5axis`(초안) → `distilled`(/cleaner 세션 LLM 정제 — 무인 정제 금지, INV-6) → `promoted` | `expired`. 재생성 멱등: cluster_key(sorted supporting sha1) 매칭 — draft만 갱신, dist_id/status/statement_refined 절대 보존.
- **③Law** = axiom (`active/` + `active/modes/<mode>/`). 엄선 승격 — 5축 boolean-AND hurdle·INV-1~7·AX-008 2/3 전부 불변. 자동 승격은 documented까지(INV-2), hook block은 주간 도훈 confirm만.

## §0.1 메커니즘 비-ossification 원리 (Level 0 — 도훈 mandate 2026-07-04)

**대전제**: "딱 한 번 작동하는 하드코딩된 멍청이가 아닌, 유동적으로 작동하며 발전하는 아키텍처." 이 엔진이 관리하는 것(지식)뿐 아니라 **관리하는 메커니즘 자체(방화벽·트리거·게이트·판정 규칙)도 지식과 동일한 학습 루프의 대상**이다. 하드코딩 규칙을 얼려두는 것("하드코딩된 멍청이")은 아키텍처 위반이다 — 규칙은 살아있는 코퍼스처럼 케이스로 발전한다.

구현 원칙 5항 (INV-7 제약 방화벽·자동초안 적대검증·검색/주입 프레이밍 판정에 공통 적용):

1. **의미(semantic) 우선 — 판정은 정규식이 아니라 LLM 판단으로.** 제약-귀속/완화-레버 색출, frontier 생성, 과장·근거 체크는 임의 표현·영어·미묘한 프레이밍을 일반화해야 하므로 **의미 판단이 primary**다. 고정 문자열 grep은 판정의 근거가 아니다.
2. **결정론적 규칙 = backstop 전용.** 정규식/enum/키워드 매칭은 비-LLM 경로(hook·배치 스캔)를 위한 **backstop**이며 **비-소진적(non-exhaustive)임을 명시**한다 — primary 판정이 아니다. backstop이 놓친 것을 primary(LLM)가 잡고, 그 반대도 성립.
3. **케이스 축적으로 자기발전.** 잡은 위반/생성한 frontier 사례를 라이브러리에 append → 다음 판정이 few-shot로 소비 → **잡을수록 똑똑해진다**(corpus 학습 루프와 동형). 판정 규칙은 정적 스펙이 아니라 성장하는 예시집합.
4. **트리거·신호원 = 열린 스키마(등록형).** INV-7 `live_trigger`의 type(regime/spread/data/time…)·모니터 신호원은 **고정 enum이 아니라 등록형 열린 스키마**다. 새 신호원(예: DART insider, 신규 spread)을 enum 개정 없이 등록 가능.
5. **이 메커니즘들도 Cleaner 리뷰 대상.** 방화벽·트리거·판정 규칙·backstop 목록 자체를 주간 `/cleaner` 세션이 리뷰(과교정·노이즈·stale 규칙 색출) — 메커니즘도 증류·정정·만료의 대상. 메커니즘을 성역화하지 않는다.

**정합**: 본 원리는 §2 INV-7(제약 방화벽 = 의미판단 기반·케이스 학습) / §3c 소비 3배선(검색·주입 프레이밍 = 의미 우선) / §3e 주간 사이클(Cleaner 리뷰 확장 대상에 메커니즘 포함)에 배선된다. INV-1~7·AX-008 2/3·5축 hurdle 수치·active AX 의미론은 본 원리로 **변경되지 않는다**(안전 불변식은 backstop이 아니라 Law — §2 절대 불변).

## §1. 파이프라인

```
L-code(모드별 emit v2 — 승격축 필드 포함) → harvest(v2: grade normalize + family 15군 + ID guard)
   → cluster(mode-partition, polarity 정규화) → CAND + DIST 초안(②) + distilled_knowledge.json
   → [자동초안+적대검증] proposed → [도훈 배치승인] distilled(주입) ┐
   → promote(mode-local AX-<MODE>-NNN) → promote_global(AX-NNN) → inject
        ↘ 미달 CAND = review_log(AX-PENDING, same-day dedup) + DIST 초안 유지(폐기 없음)
        ↘ review(NARROW/deprecate) · rollback · weekly_report · run_axiom_weekly 진단
```

- **재등재 supersede (2026-08-02)**: `cluster_extractor.build_distilled` 후-패스 `supersede_subsumed`가 **부분집합 구 카드를 자동 회수**(status=expired, `superseded_by=<new_id>`). 클러스터가 supporting L-code 성장으로 새 dist_id에 재등재될 때 구 카드가 남아 pending 백로그가 부푸는 갭(07-17 49건 → 08-02 89건, 부분집합 쌍 30) 차단. 판정 = **진부분집합 ∧ family/polarity/type/research_mode 전부 동일 ∧ 지식 손실 0(구 카드 L-code 전량 포함) ∧ 구 카드 저술 지식 미보유**. `distilled/promoted/quarantined_evidence`는 대상 제외(활성 카드 자동 회수 금지) — 07-18 forward-migration(refined 조상의 정제 승계)과 상보: 저술 지식이 있으면 supersede가 아니라 migration/수동 /cleaner 소관. 카드 파일 삭제 없음(status 전환만). 가드 `08_Tests/axiom/test_distilled_supersede.py`(배터리 등재, 돌연변이 5축).
- **4 모드**: alpha_search(**proxy** — mode-local 한정) / QEPM(**backtested** forge) / factor_rotation(**backtested** build_bt_result+essence_score) / RAMP(**backtested** canonical_screen_bt/build_bt_result — `docs/rules/ramp.md`). modecode AS/QPM/FR/RAMP (`lcode_emit.R::.LCODE_MODE_PREFIX` = `promote.R::.MODE_PREFIX` 정합).
- **2-tier**: mode-local `active/modes/<mode>/AX-<MODE>-NNN.json` + global `active/AX-NNN.json`.

## §2. 안전 불변식 (절대 위반 금지 — v2 불변)

- **INV-1 metric_type 게이트**: proxy/estimated → mode-local까지. global은 supporting 전부 `backtested`(essence_score §3 HARD). `canonical_screen`은 실측 스크리닝 라벨(measurement-graduation §1)로 스키마에 추가되었으나 global 승격 자격은 `backtested`만 — 불변.
- **INV-2 생성≠강제**: 자동 승격 = `enforcement_mode=documented`/`enforcement=""`. hook block은 주간 리포트 human confirm만. 엔진산 negative 지식의 차단 실효는 enforcement 자동 생성이 아니라 **주입·검색 경로(②Distilled)** 로 확보.
- **INV-3 안전망 실작동**: 롤백 = 마커 블록 삭제(simulated diff 금지). 주간 리포트 = proxy/global 전건 human-review 플래그.
- **INV-4 r7 5축 무결성**: 승격 = 5축 각 min-hurdle 동시 충족(boolean AND). weighted는 랭킹용.
- **INV-5 AX-008**: 자동 global 승격 = Forge+Self-Adversarial+Architect **2/3** verification (v8.2 — Codex Round 제거, Opus 자체 적대검증 치환. 2/3 불변).
- **INV-6 주입면 자격 게이트** (2026-08-23 v9.1 재정의 — 구 "무인 활성화 금지"[07-04], 그 이전 "무인 정제 금지"): **주입면에 도달하는 텍스트는 품질 게이트를 통과한 것뿐이다.** 통제 대상은 *누가 승인했는가*가 아니라 *무엇이 주입되는가*다. ★재정의인 이유: INV-6 가 실제로 지킨 안전속성은 "무인 텍스트가 주입면에 도달하지 않는다"이고(§3 아래 '안전속성 보존 방식'), 음성 DIST 카드는 이미 D-f 승인으로 무인 활성화 중이다 — 즉 운용 실체는 이미 "사람이 승인한다"가 아니라 "주입면 도달을 통제한다"였다. **삭제하면 통제가 사라지고, 남기면 거짓말이 된다.** ① 공리(mode-local) 활성화 = `02_Infrastructure/axiom/refine_statement.R` 의 **R0~R6** 가 판정한다(R0 polarity 재현 · R1 멤버 결측 ≤0.20 · R2 판별 토큰 ≥1 · R3 메커니즘 실체 · R4 반증 시도 ≥1 · R5 반증/부활 조건 · R6 중복 비포섭 Jaccard <0.5). 통과=`REFINED`→`status=active`, 하나라도 미충족=`HELD`→`status=proposed`(주입 안 됨). ② 활성 mode-local 은 주입면에 **모드당 ≤2 · 총 ≤5줄**(`statement_inject` ≤70자)로만 렌더되고 **감축 사다리의 감축 대상**이다 — 고정부는 전역 Law 뿐. ③ 이 불변식은 문서가 아니라 `memory_knowledge_health.R` 의 **HARD_8/9/10** 이 지킨다. ④ 되돌리기: `deactivate_axiom(ids, reason=)` · `rollback_axiom(id, apply=TRUE, reason=)`(+tombstone) · `QVEST_AXIOM_UNATTENDED=0`. DIST 카드 lifecycle(`pending_5axis`→`proposed`→`distilled`)과 /cleaner 직행 정제(`refine_distilled`)는 불변.
- **INV-7 negative = Distilled 탐색-지도(exploration-map)** (2026-07-04 재정의 — 도훈 confirm "실패는 금지 아닌 탐색지도. 제약을 레버로 삼지 말 것"): negative 지식은 **Law가 아니라 Distilled 탐색-지도**다 — **5축 승격 게이트를 거치지 않는다**(Law 잔존은 process 규칙, polarity 없음, 예 AX-001 뿐). **단위 = 경로(구성-scoped)** — value/quality 같은 **방향(family) 판결 금지**(실패한 건 "EP-단독-long-only라는 특정 경로가 이 시기에 F"일 뿐). **제약 방화벽(불변)**: 고정 제약(종목수≤25·유동성 2e8·long-only·[0,0.20]·Σw=1·K200∪KQ150·15bps + PIT C1~C15)은 **문제의 고정 축** — 실패를 제약에 **귀속**하거나 제약 **완화를 레버로 제시** 금지(위반 = 초안 REJECT, envelope-상대로 재작성). **방화벽 판정 = 의미판단(LLM) 우선·케이스 학습**(§0.1 — 정규식 backstop은 비-소진적 보조, 잡은 위반 사례 축적으로 자기발전). **산출 = {탐색됨, frontier(미탐색 인접 경로), live_trigger(부활 조건)}** — "금지" 아님. **필수 필드**: `expiry` + `live_trigger` + `frontier`. **부활 기구 실가동(2026-07-05 배선 완료 — 계획서 §Ⅱ.G)**: 사람용 산문 `live_trigger`(배열, type/condition/monitored_source)는 `draft_proposed`가 카드 작성 시 기계 `revival_spec`(배열 `{signal_id, condition, from_trigger, status}`)으로 **자동번역**(type→신호명부 매핑: `time`→wall_clock expiry 바닥·`regime`→regime_category·`spread`→value_quality_spread·`data`→file_exists slug; **미등록 신호는 `revival_signals.json`에 pending 스텁 자기증식**, 조용한 소실 금지). `failure_revival_monitor.R`가 열린 등록형 신호명부(§0.1 원리4) 경유로 매일 현재값과 대조 → 충족분을 능동 재부상(모닝브리핑 노출). `expiry`는 신호 배선 여부 무관 **보편 시간부활 바닥**(만료 도달 시 재검토). 즉 **live_trigger는 표시용(inject/search)·revival_spec은 실행용(monitor)** 이원 표현이나 후자는 전자에서 자동생성되어 지속가능(신규 카드도 손 없이 자동 배선). **주입 자격 바**: `backtested` OR clean-재확인 **∧** distinct construction N≥2 **∧** 방화벽 통과분만 주입(기록은 무조건 — corpus 전수 보존, 주입만 엄선). **positive용 축(External oos_retention≥0.5·Independence≥3구성)은 negative에 부적용.** distilled negative의 라벨도 **영구 판결 아님** — `live_trigger`/`retry_condition` 충족 + 봉투-안 차별점 명시 + 재도전 사유 기록 시 재시도 가능(§3c hypothesis_index `retry_policy`).

## §3. 5축 (r7 — `promote.R`. 수치 전부 불변)

| 축 | hurdle | 비고 |
|---|---|---|
| Independence | distinct construction ≥ 2 (negative ≥ 3) + direction ≥ 0.8 | strategy_id 착시 폐기. **direction_consistency 정의 (2026-07-04 국소수리②, 문턱 0.8 불변)**: positive/negative = 전체 grade 최빈 비율(종전 동일) / conditional = **조건 축 내 일관성**(win군 A·B / loss군 C·F 각각의 내부 일관성 min — '전체 일치'는 conditional 정의와 모순=영구 미달이던 결함 해소). **주간 리포트 도훈 confirm 대상**(run_axiom_weekly confirm_flags) |
| Rigor | backtested: weakest port_t ≥ 2.95 / negative: backtested frac_fail ≥ 0.8 | proxy=mode-local 관대 |
| Falsification | 적극 반증 attempts ≥ 1 + none_falsified + retained ≥ 0.5 | negative +0.5 폐기. **문자열 attempts crash-safe 수용 (2026-07-04 국소수리①)**: 비구조체 = n 카운트만 + none_falsified 보수 TRUE(판정 근거 없음) — 구조체 전환 권장 WARN |
| External | supporting L-code oos_retention 실값 존재 + cluster median ≥ 0.5 | 2026-07-03 재정의(GOV-01). oos_months는 가산 증거(실값 ≥3m 시 score +0.2, hurdle 무관). corpus 실값 0건 시 draft oos_effect_vs_is 폴백 |
| Mechanism | economic_explanation present + type ≠ unknown | 보일러플레이트("unknown"/"TBD"/10자 미만) 불인정 (schema v2) |

부가 (2026-07-04 국소수리③, **2026-08-23 v9 로 대체**): `.log_partial` review_log 파일명은 구 규약이 날짜 기반(`AX-PENDING_<cand>_<YYYYMMDD>.json`)이었다 — same-day overwrite + 시분초-suffix 정리로 07-03 중복 오염은 막았으나 **주 단위 중복(728건 적체)과 MAX_PATH 무음 crash 는 남았다**. v9 규약 = `AX-PENDING_<cluster_key(12-hex)>.json` **클러스터당 1파일** + `history[]`(최대 10회) + `candidate_sha`. 일회성 이관 = `02_Infrastructure/axiom/migrate_candidates_v9.py`(구 파일은 삭제 없이 `review_log/_archive_20260823/` 이동).

### §3-v9. mode-local 사다리 (2026-08-23 — 도훈 결정 §3.4(a) · §6 D-f/D-g)

**전역 Law 는 불변**(`promote_global.R` · `.HURDLE` · INV-1 · PORT_t 2.95 · AX-008). 아래는 **mode-local tier 전용** 재보정이며 근거는 실측이다 — 728회 재채점에서 5축 동시 통과 **0건**, 마지막 승격 2026-05-02, external 축 중앙값 **−0.04**(07-04 의 "입력 결측" 진단이 반증됨).

| 항목 | v8 (5축) | v9 mode-local |
|---|---|---|
| hurdle 축 | independence·rigor·falsification·external·mechanism | **independence · rigor_research · mechanism** (external·falsification 은 점수만) |
| 통과 규칙 | all_hurdles ∧ weighted ≥ 0.80 | **all_hurdles** (weighted 는 랭킹 전용) |
| Independence | 전체 grade 최빈 비율 ≥ 0.8 | **win/loss 기준**(A/B=win, C/F=loss). positive·negative = 우세 방향 ≥ 0.8 ∧ 구성 ≥2 / conditional·mixed = 구성 ≥2 ∧ win ≥2 ∧ loss ≥2 |
| Rigor | mode-local 은 hurdle 무조건 TRUE(사실상 축 없음) | **rigor_research** = A/B ∨ metric_type ∈ {canonical_screen, backtested} ≥2건 (negative 는 C/F ≥2건) |
| 조기 SKIP | 없음 | **SKIP_SINGLETON**(supporting <2 — independence 원리상 불가) · **SKIP_UNKNOWN**(polarity 미상) |
| 양성·조건부 산출 | `status=proposed` + 도훈 1줄 confirm | **v9.1: 정제 verdict 가 status 를 정한다** — `REFINED ∧ QVEST_AXIOM_UNATTENDED=1 ∧ 상한 여유` → `status=active`(무인) / 그 외 → `proposed`(HELD). 공리 파일에 `refine_verdict`·`refine_failing[]`·`refine_gates`·`refine_input_sha`·`refine_attempts`·`statement_inject` 기록. `confirm_required` 필드 폐지. 동일 sha 8주 연속 HELD → `held_stale`(삭제 아님, AX-000) |
| 음성 산출 | provisional 공리 | **공리 아님** — `auto_map_negative(cluster_key)` 로 DIST 탐색지도 카드 자동 활성화(INV-7). 사람 정제문·promoted·quarantined 카드는 무변경 |
| 롤백 재발급 차단 | 없음 | **v9.1: `SKIP_TOMBSTONED`** — `axiom_rollback.R` 이 `deprecated/` 이동과 같은 트랜잭션으로 `qepm/memory/axioms/tombstones.json` append(`reason` 필수·`revive_condition` 선택), `promote.R` 멱등 스캔 직후 소비. 해제 = `clear_tombstone(cluster_key, reason=)` (INV-7 — 영구 금지 아님) |
| 활성 상한 | 없음 | **v9.1: 모드당 ≤6 · 총 ≤20**(`.TIER$mode_local`). 초과 시 `FAIL_CAP` + 다이제스트 힌트, **자동 축출 금지** — 무엇을 버릴지는 사람이 정한다 |
| 주간 폭주 차단 | 없음 | **v9.1: 2-pass + 회로차단기**(`weekly_cleaner_sweep.R`) — ①전건 `--dry-run` 으로 verdict·refine_verdict·활성 예정 수집 ②`n_new_active > WEEKLY_ACTIVATION_MAX(3)` ∨ 상한 초과 ∨ crash>0 ∨ 주입 `len>1900` 이면 **전면 중단**(`cleaner_pending.json::axiom_candidates.activation_hold`) ③통과 시 쓰기 예고분만 재스폰 |

**INV-6 안전속성 보존 방식(v9.1)**: 주입 훅 `axiom_context_inject.sh` 가 `active/modes/**` 를 **`status=="active"` 로 필터**하고, 활성분은 전역 Law 와 **다른 캐시**(`.cache/axiom_inject_modelocal.md`)로 분리돼 **감축 사다리의 tier** 로 들어간다(`ML_MAX_TOTAL=5 · ML_MAX_PER_MODE=2 · ML_LINE_MAX=70`, 마지막 단은 1줄 포인터로 접힘). ⇒ ①게이트 미통과 텍스트는 주입면에 **도달하지 않고** ②통과 텍스트도 **예산을 밀어내지 못한다**. 훅은 `:224` 직후 `.cache/axiom_inject_last.json`(`{at,len,ladder_rung,ml_rendered,ml_active_total,markers}`)을 쓰고, 그 파일이 **HARD_10 의 유일한 입력**이다 — 조립기를 R 로 재구현하지 않는다(두 구현이 갈라지면 계약이 실제 주입면 대신 자기 사본을 재게 된다). sot_map 등재는 `status` 를 그대로 싣는다(등재 자체가 HARD_3 계약).

**verdict 토큰(소비자가 grep)**: `→ PASS | MAP | FAIL | SKIP_SINGLETON | SKIP_UNKNOWN | SKIP_TOMBSTONED`. `weekly_cleaner_sweep.R::.promote_crash_verdict` 정규식 `\[promote\].*(PASS|FAIL|SKIP|MAP)` 이 이 6종을 모두 verdict 로 인정한다(구 `(PASS|FAIL)` 그대로면 정상 SKIP/MAP 자식이 crash 로 오집계).

**dry-run**: `Rscript 02_Infrastructure/axiom/promote.R --dry-run <cand>` — 판정만 출력, 쓰기 0.
**주간 스윕 사전판정**: `promotable == FALSE`(단일 L-code) 또는 `candidate_sha` 가 직전 review_log 기록과 동일하면 **Rscript 스폰 자체를 건너뛴다**(`SKIP_SINGLETON`/`SKIP_UNCHANGED`). 실측 2026-08-23: 후보 102건 중 **73건 미스폰**.

## §3b. emit 스키마 v2 — 필수·권장 필드표 (`lcode_schema.R` / `lcode_emit.R`)

**설계 원칙**: 축 도달불가의 원인은 문턱이 아니라 입력 결측 — emit 시점에 채워지게 한다.

| 계층 | 필드 | 규칙 |
|---|---|---|
| base required (hard error) | l_code / strategy_id / lesson_text / research_mode / metric_type | v1 동일. grade는 record_type=performance일 때만 필수 |
| base required | grade | **enum A/B/C/F 강제**. legacy alias(A_DEF/A_CONDITIONAL/REJECT/B_ARCHIVE 등) 수용+WARN → `normalize_lcode()` canonical 정규화 + `grade_raw` 보존. 비성과 legacy grade(INFRASTRUCTURE*/METHODOLOGY/TIER*_SUMMARY 등)는 grade 제거 + `record_type` 이동 |
| base | record_type | `{performance, process, infra, summary}` — 비성과 기록 분리 신설 |
| **required_for_promotion** (emit=WARN / promotion(strict)=error) | mechanism_hypothesis | Mechanism 축. 보일러플레이트 불인정 |
| required_for_promotion | metric_type | Rigor 축. `canonical_screen` 추가 (measurement-graduation §1 정합) |
| required_for_promotion | construction_type | Independence 축. controlled vocab (`LCODE_VALID_CONSTRUCTION_TYPES`). **selection_type 값(chain/sweep)은 거부 → `selection_type` 별도 필드 분리** |
| recommended (결측 WARN) | falsification_attempts | Falsification 축. **구조체** `[{test, result∈{survived,falsified,weakened}, effect_retained}]` 권장 — 문자열 수용+WARN |
| recommended | oos_retention (+oos_months) | External 축. essence_score oos_stat v2 산출치 |
| recommended | portfolio_alpha_t | metric_type=backtested/canonical_screen인데 결측 시 WARN (Rigor global weakest_t 2.95 도달 불가) |
| 기타 | research_mode | `qepm`→`qepm_legacy` normalize (promote GEN 폴백 봉합) |

- **emit WARN→BLOCK 승격은 2사이클 관찰 후 도훈 confirm — 지금 미도입.**
- emit v2 시그니처: 승격축 4필드 = 1급 인자 (`emit_lcode(mechanism_hypothesis=, falsification_attempts=, oos_retention=, portfolio_alpha_t=, ...)`). 기존 `metrics=list(...)` 자유목록 호출 back-compat 유지(1급 인자로 자동 승격). wrapper `emit_qepm_lcode`/`emit_fr_lcode`/`emit_ramp_lcode`는 `...` 전달.
- **신규 ID 채번 중복 가드**(A1-F6): 자동 채번 충돌 시 `_02` suffix 재발급. harvester도 ID collision WARN + `id_collision_with` 마킹.
- 하위호환: 구 L-code(v1) 읽기/재검증은 strict=FALSE — WARN까지만 (정직 원장 보존).

## §3c. 회수(retrieval) 1급 배선표 — 4모드 emit/consume 매트릭스

| 모드 | emit (1지점) | consume (1지점) |
|---|---|---|
| alpha-search | `run_alpha_search.R` 기배선 유지 — falsification만 구조체 전환 | SKILL 조회 의무 기존 완비 (no-op) |
| QEPM | judge verdict finalize 직후 `emit_qepm_lcode` 의무 (essence_score 산출치 port_t/oos/falsification 전달; governor DEFER 시 `source="governor_admission"`) | `/worktask` create 시 `hypothesis_index` lookup 의무 — FAIL/KILL/DISTILLED_NEG 히트 시 차별점 명시 없인 진행 금지(INV-7 재도전 사유 기록) |
| FR | `run_wf_ensemble.R` fr 레지스트리 등재 직후 `emit_fr_lcode` 1콜 | SKILL Step-0 지식 대조 의무 (hypothesis_index + 인접 모드 grade F 스캔) |
| RAMP | `ramp_loop.R` 기배선 — construction_type 필수 인자화 + `run_ramp_graduation.R` 실측치 자동 전달 | `ramp_observe()` xmode_keywords 교차조회 |

(모드 스크립트·SKILL 문서 배선 집행 = mode-wiring 그룹. 본 표는 규약 SOT.)

공통층 소비 3배선 (engine-core 구현 완료):
1. **주입**: `hooks/axiom_context_inject.sh` — v9 재극성 이후 구성 = 전역 Law(고정부) + **mode-local 활성 공리(감축 tier)** + 고정 축/프론티어 + 최고 연구-tier 전략 + 최근 교훈 + dead configs 1줄 포인터. **합산 상한 = 2,000자**(훅 실제값 `MAX = 2000` — 구 문서의 2,500자는 코드와 불일치였다). 그중 mode-local 렌더 상한은 **총 ≤5줄 · 모드당 ≤2줄 · 줄당 ≤70자**(`statement_inject`, 없으면 `statement[:70]`; 정렬 = `promotion.weighted_score` 내림차순). 감축 사다리: ①DIST 포기 ②최근 교훈 3→2→1 ③전략 5→3 ④mode-local 5→3→1→0(1줄 포인터). 고정부(헤더·전역 Law·고정 축·프론티어·dead 줄)는 어느 단계에서도 손대지 않는다. DIST 카드는 `status=distilled` 만 소비(INV-7 — `proposed`·`pending_5axis` 초안 주입 금지).
2. **검색**: `tools/hypothesis_index.R` — 원천 4계층째 distilled 인덱스. verdict = `DISTILLED_NEG`/`DISTILLED_COND`/`DISTILLED_POS`. negative lookup은 **금지가 아니라 탐색-지도**로 표출 (INV-7): `{탐색됨: [경로=F, 증거]; frontier(미탐색 인접): [...]; live_trigger(부활 조건): [...]}` — 봉투-안 차별점 명시 시 진행 가능. expired는 인덱스 제외.
3. **truths**: `prompts/strategic_truths.md` `<!-- DISTILLED_START/END -->` generated 블록 — **수동 큐레이션 본문 절대 보존**(블록 밖 수정 금지 · 블록 안 수동 수정 금지=재생성 시 소실). 갱신: `distilled.R::update_strategic_truths_distilled_block()` (refine/expire 시 자동). inject는 이 블록을 제거하고 distilled 인덱스에서 직접 주입(이중 주입 방지).

R-side helper: `02_Infrastructure/axiom/distilled.R` — `lookup_distilled()` / `refine_distilled(dist_id, statement_refined, retry_condition)`(/cleaner 전용, status→distilled) / `expire_distilled()` / `mark_promoted_distilled()` / `rebuild_distilled_index()`.

## §3d. falsification 구조체 스키마

```json
"falsification_attempts": [
  {"test": "placebo 셔플",        "result": "survived",  "effect_retained": 0.85},
  {"test": "subperiod 반분",      "result": "weakened",  "effect_retained": 0.55},
  {"test": "IS-only 선택 검증",   "result": "falsified", "effect_retained": 0.1}
]
```
- `result` ∈ {survived, falsified, weakened}. `effect_retained` = 반증 시도 후 잔존 효과 비율(0~1).
- hurdle: attempts ≥ 1 ∧ none_falsified ∧ (survived건 effect_retained ≥ 0.5).
- 문자열(비구조체) 기록도 수용(n 카운트 보수 처리)하되 WARN — 신규 emit은 구조체 의무 지향.
- **result 토큰 정규화 (2026-07-17)**: 비-canonical `result` 토큰은 축 판정 전 정규화 — `falsif` 포함(예: `falsification_failed`)·`negative` → `falsified`, 미상 토큰 → 보수 처리(승격 우호 방향 해석 금지).

## §3e. 주간 사이클 (2026-07-17 실배선 현행화 — 07-06 정정 SOT 반영)

- **정규 주간 경로**: `ops/weekly_cleaner_sweep.R`(토 09:00 Qvest_WeeklyCleaner + bootstrap 7일게이트) **step 3.5가 engine-core를 직접 호출** — `lcode_harvester.py` → `cluster_extractor.py` → `promote.R`(pending candidate 순회, INV-4 5축 hurdle). run_axiom_weekly.R 경유 아님.
- **진단**: `.cache/cleaner_pending.json` 의 **`axiom_candidates` 섹션** ({n_pending, failing_axis_histogram, **near_miss**(1축만 미달)} + `confirm_flags` + **v9.1 신설** `activated_axioms`(이번 주 신규 활성 — 사후 통지) · `held_axioms`(HELD **사유**별) · `activation_hold`(회로차단기 발화 시 사유·조치) · `activation_preview`). **★/cleaner 의 역할이 바뀌었다(v9.1)**: 공리 statement 정제는 **결정적 조립기**(`refine_statement.R`)가 전담한다 — LLM 정제 아님. `/cleaner` 세션은 **HELD 사유를 소비**해 *입력*을 고친다(멤버 L-code 의 `next_probe`/`live_trigger` 보강 · 반증 시도 구조화 · polarity 오라벨 정정 · 중복 클러스터 정리). 입력이 바뀌면 `refine_input_sha` 가 달라져 다음 스윕이 자동 재시도한다 — "영구 SKIP 없음"(AX-000). DIST 카드의 near-miss statement 정제(`refine_distilled`)는 종전대로 /cleaner 전담.
- **수동 경로**: `run_axiom_weekly.R` + `ops/axiom_weekly.sh` = **수동 재현/디버그 전용, 자동 트리거 없음** (구 "단일 진입 — Cleaner가 본 스크립트를 호출" 서술은 거짓 — 2026-07-06 도훈 confirm, 스크립트 헤더 정정). `.cache/axiom_weekly_diag.json`은 이 수동 경로의 산출물 — live 소비자 0.

## §4. 파일

- 엔진: `02_Infrastructure/axiom/{lcode_schema,lcode_emit,distilled,run_axiom_weekly,promote,promote_global,review,inject,axiom_rollback,axiom_weekly_report,**refine_statement**}.R` + `{lcode_harvester,cluster_extractor}.py`
  - `refine_statement.R`(v9.1 신설) = **결정적 statement 조립기 + 활성화 게이트 R0~R6**. LLM 미사용. CLI `--preview --all`(쓰기 0 · 판정 **분포** 출력) / `--backfill [--dry-run]`. 검사기 `08_Tests/axiom/test_refine_statement.R`(게이트별 위반 주입 5축 + 돌연변이 통제).
- 원장: `qepm/memory/axioms/tombstones.json`(롤백 재발급 차단, v9.1 신설) · `qepm/memory/axioms/backlinks/<AX-ID>.json`(역링크 폭증 시 역인덱스) · `.cache/axiom_inject_last.json`(주입 계측 — HARD_10 입력) · `.cache/axiom_inject_modelocal.md`(mode-local 렌더 캐시).
- 파이프라인: `ops/weekly_cleaner_sweep.R` step 3.5(정규 — engine-core 직접 호출) · `run_axiom_weekly.R`/`ops/axiom_weekly.sh`(수동 재현/디버그 전용, 자동 트리거 없음) · bootstrap(harvest)
- consumer: `hooks/{axiom_context_inject,axiom_enforcement_hook}.sh` · `tools/hypothesis_index.R` · `prompts/strategic_truths.md`(DISTILLED 블록) · `memory/memory_knowledge_health.R` · `qepm/R/axiom_dashboard.R`
- 데이터: `qepm/memory/axioms/{active/,active/modes/<mode>/,candidates/,**distilled/**,deprecated/,review_log/,axiom_sot_map.json}` · `06_Registry/{distilled_knowledge.json,hypothesis_index.json,lcode_distill_plan_20260704.json}` · `.cache/{lcode_corpus.json,cleaner_pending.json(axiom_candidates — 정규 진단),axiom_weekly_diag.json(수동 경로 산출물 — live 소비자 0)}`
- 실행(Windows): `PY=%QVEST_PY%` (venv `.venv_qvest_ml/Scripts/python.exe` — bare python 금지) · `RS=C:/Program Files/R/R-4.5.2/bin/Rscript.exe` · `CLAUDE_PROJECT_DIR` + `PYTHONUTF8=1`

## §5. 운영 규칙

- mode-local 자동 승격(documented). global 승격 + hook block = 주간 리포트 도훈 confirm(비가역).
- 기존 AX-003/004/005/007 = provisional(N=2~3 잠정, 재도전 대상). 추측 폐기 금지 — 엔진 asymmetric 재검증 경유. **active axiom 8건(000~005,007,008) 의미론 절대보존.**
- **도훈 confirm 대상(집행 전 아님 — 주간 리포트 표기)**: ①conditional direction_consistency 재정의(§3) ②emit WARN→BLOCK 승격(2사이클 후) ③distilled→promoted 승격 건별.
- b434 규약: CL-B434 fallback 통합 L-code의 '미검증 잔존 가설 백로그'는 **어떤 개별 가설의 기각 증거로도 인용 금지** (AX-000 — 미검증→기각 둔갑 방지가 failure-ledger 신뢰의 전제).

## Change log
- 2026-08-02 (재등재 supersede 자동화 — pending 백로그 구조 수리): §1에 supersede 후-패스 1줄. `cluster_extractor.py`에 `supersede_subsumed`(+`--supersede-only[/--dry-run]` CLI) 신설, `build_distilled` 후-패스 배선 — 부분집합 구 카드를 08-02 수동 회수 9건과 **동일 엄격 기준·동일 사유 형식**으로 자동 회수(수동 반복 종료). ★짝 발굴은 진부분집합이 아니라 **멤버 교집합**으로 한다 — 진부분집합으로 짝을 찾으면 '지식 손실 0' 검증이 논리적으로 통과 보장되어 **검사가 공허**해진다. 경고 3종(lossy/authored/protected-skip)은 회수하지 않고 /cleaner 수동 큐로 노출. `distilled.R`은 술어를 재구현하지 않고 이 구현을 호출(`supersede_subsumed_distilled`). 실측 집행: 현 120카드(pending 80)에서 **추가 회수 0건** — 08-02 수동 드레인이 엄격 기준 전량을 이미 소진(잔여 = lossy 3쌍·protected-skip 6쌍 = 수동 판단 대상). 가드 `08_Tests/axiom/test_distilled_supersede.py` 38/38(돌연변이 M1~M5 = 검사 사망 통제 — 추가 대상 0건이라 정상 경로만으로는 로직 사망과 정상이 겉보기 같음). INV-1~7·5축 hurdle·AX-008 2/3·주입 3배선 status=distilled-only 전부 불변.
- 2026-07-17 (도훈 승인 수리 — 07-06 정정 SOT 반영 + confirm_flags 주간 배관 + result 토큰 정규화): §3e 실배선 재서술 — 정규 주간 경로 = `weekly_cleaner_sweep.R` step 3.5의 engine-core(`lcode_harvester.py`→`cluster_extractor.py`→`promote.R`) **직접 호출**, 진단 = `cleaner_pending.json` `axiom_candidates` 섹션(+`confirm_flags` 주간 배관 2026-07-17 배선), `run_axiom_weekly.R`/`ops/axiom_weekly.sh` = 수동 재현/디버그 전용·자동 트리거 없음(구 "Cleaner가 호출" 서술은 거짓 — 07-06 스크립트 헤더 정정의 SOT 반영. `.cache/axiom_weekly_diag.json` = 수동 경로 산출물·live 소비자 0). §4 파일 목록 동기 수정. §3d에 `result` 비-canonical 토큰 정규화 규칙 1줄(falsif-포함/negative→falsified, 미상→보수 처리). **5축 hurdle 수치·INV-1~7·AX-008 2/3·active AX 의미론 전부 불변.**
- 2026-07-05 (INV-7 부활 기구 finalize — 도훈 지시 "지속가능한 성공"): INV-7 산출 §에 **부활 기구 실가동** 절 추가(계획서 §Ⅱ.G 실현). 사람용 `live_trigger`(산문) → 기계 `revival_spec`(배열 {signal_id,condition}) **자동번역**(draft_proposed, type→신호명부 매핑 time/regime/spread/data, 미등록 신호 pending 스텁 자기증식) → `failure_revival_monitor.R`가 열린 신호명부(`revival_signals.json`) 경유 매일 대조·능동 재부상. expiry=보편 시간부활 바닥. **표시용(live_trigger)·실행용(revival_spec) 이원이나 후자는 전자에서 자동생성 → 신규 카드도 손 없이 배선(지속가능·DURABLE 실증)**. 신호명부에 value_quality_spread(V02_EP 월간 IQR 백분위 PIT-safe deriver) active 등록 + regime_category/wall_clock_date 기존. E2E: 4 negative 카드 revival_spec 자동 retrofill·CRISIS 국면 실발화 3건·battery 11/11·health HARD 0. commit `da055c90`. INV-1~6·AX-008 2/3·5축 hurdle·active AX 의미론 불변.
- 2026-07-04 (§0.1 메커니즘 비-ossification 원리 신설 — 도훈 mandate "딱 한 번 작동하는 하드코딩된 멍청이가 아닌, 유동적으로 작동하며 발전하는 아키텍처"): §0.1 신설 — 엔진이 관리하는 **메커니즘 자체(방화벽·트리거·게이트·판정 규칙)도 지식과 동일한 학습 루프 대상**. 구현 5원리: ①의미(LLM) 우선(정규식 아님) ②결정론적 규칙=backstop 전용(비-소진적 명시) ③케이스 축적 자기발전(few-shot 소비) ④트리거·신호원=열린 스키마(등록형·enum 아님) ⑤메커니즘도 Cleaner 리뷰 대상. INV-7 제약 방화벽에 '의미판단 우선·케이스 학습' 판정 원리 1줄 배선. **INV-1~7·AX-008 2/3·5축 hurdle 수치·active AX 의미론 = Law이지 backstop 아님, 본 원리로 불변.** 계획서 META원리. CLAUDE.md Production Constraints/AX-000 따름정리 정합.
- 2026-07-04 (INV-7 재정의 — 도훈 confirm "실패는 성공의 어머니. 실패를 금지 아닌 탐색지도로. 제약을 레버로 삼지 말 것"): INV-7 "provisional failure-ledger" → **"Distilled 탐색-지도(exploration-map)"**. 5축 게이트 면제 명문화 / 단위=경로(방향-family 판결 금지) / **제약 방화벽**(고정 제약 7종+PIT 귀속·완화-레버 = 초안 REJECT) / 산출={탐색됨·frontier·live_trigger}(금지 아님) / 필수필드 expiry+live_trigger+frontier / 주입 자격 바(backtested OR clean-재확인 ∧ N≥2 ∧ 방화벽 통과분만, 기록은 무조건) / positive축(External oos≥0.5·Indep≥3) negative 부적용 / process(polarity 없음, AX-001)만 Law 잔존. §2 소비배선 hypothesis_index '재시도 금지' 문안 → '탐색됨+frontier+live_trigger' 지도. **INV-1~6·AX-008 2/3·5축 hurdle 수치·active AX 8건 의미론·주입 3배선 status=distilled-only(INV-6) 전부 불변.** 계획서: `04_Research/01_reports/failure_knowledge_architecture_plan_20260704.md`(A).
- 2026-07-04 (INV-6 재정의 — 도훈 confirm "옵션 B: 자동초안+배치승인 + 모닝브리핑 승인대상 노출"): INV-6 "무인 *정제* 금지" → "무인 *활성화* 금지". lifecycle에 `proposed` 상태 삽입(`pending_5axis`→[자동초안+적대검증]→`proposed`→[도훈 배치승인]→`distilled`). distilled.R 신규 `draft_proposed`(status=proposed, 주입 안 됨)/`approve_proposed`(proposed→distilled 사람 게이트)/`list_proposed`(모닝브리핑·다이제스트 소비) + `lookup_distilled` distilled-only 필터(proposed 누출 차단). 주입 3배선 status=distilled만 소비(안전속성 보존). INV-1~5·INV-7·AX-008 2/3·5축 hurdle·active AX JSON 전부 불변. quarantined_evidence 6건 초안 대상 제외(가드 재사용).
- 2026-07-04 v2 (엔진 재설계 — 도훈 mandate, engine-core): §0 3층 산출물 모델(Ledger/Distilled/Law) 신설 + ②Distilled 계층 구현(DIST-<MODE>-NNN + distilled_knowledge.json + distilled.R helper + cluster_extractor CAND→DIST 초안·polarity 정규화 왜곡 수리) + 소비 3배선(inject distilled top-5 ≤2500자 / hypothesis_index 4계층 DISTILLED_* + retry_policy / strategic_truths generated 블록) + emit 스키마 v2(§3b — required_for_promotion 계층·grade enum A/B/C/F+legacy alias·record_type·canonical_screen·selection_type 분리·ID 채번 가드; WARN-only, BLOCK 미도입) + harvester v2(grade normalize plan 소비·FAMILY 15군 확장 unknown 146→8·record_type·ID collision) + promote 국소수리 3건(§3 — falsification 문자열 crash-safe / conditional direction_consistency 조건 축 내 재정의(0.8 불변·confirm 플래그) / review_log same-day dedup) + 주간 단일 진입 run_axiom_weekly.R(§3e — near_miss·failing_axis_histogram 진단). **5축 hurdle 수치·INV-1~7·AX-008 2/3·active axiom 8건 의미론 전부 불변.** E2E: 완비 emit 1건 → 5축 PPPPP 실증(sandbox) / 17 CAND 재실행 crash 0 / inject 2295≤2500자.
- 2026-07-03 (도훈 confirm, 감사 GOV-01): External 축 측정가능 재정의 — hurdle을 oos_months(corpus 실값 0건 = 영구 불충족) 기반에서 **oos_retention 실값 존재 ∧ cluster median ≥ 0.5**(corpus 457/594건 실값)로 교체. '요건 완화가 아니라 측정 불가능 지표의 측정 가능 지표 교체'. 문턱 0.5는 구 vs_is 0.5 개념 유지 + measurement-graduation §3 '<0.5 무조건 FAIL' 하한 정합. oos_months는 가산 증거로 강등. (`promote.R .HURDLE/.axis_external`)
- 2026-07-03 현행화 (승격 배관 수리 — hurdle 정의 불변): ① 3-mode → **4-mode**(AS/QPM/FR/**RAMP**) ② INV-5 Codex → **Self-Adversarial**(v8.2 AX-008 치환) ③ cluster_extractor `oos_months` 하드코딩 None → L-code 실값 매핑.
- 2026-06-05 v8.0: 신규. r7 복원 + 3-mode 2-tier + INV-1~7 + 안전망. E2E 10/10 PASS.
