# Axiom Engine — 4-Mode 2-Tier · 3층 산출물 모델 (Level 0 SOT)

**v2 (2026-07-04 엔진 재설계 — 도훈 mandate "L-code 전수점검 증류 + 엔진 사상부터 재설계 + 4모드 실가동 재배선"). 원전 r7(`00_Lawbook/Axiom_아키텍처/r7_axiom_design.md`) 5축 보존 + 4-mode 2-tier + Distilled 소비층 + 회수(retrieval) 1급.**
**위반 = AX-002 동급.** 상위 헌법: `.claude/rules/axioms.md`(global 공리 본문) / `measurement-graduation.md`(metric_type).

**재설계 전제 (A1·A2·A3 3진단 통합)**: 승격 0의 인과는 문턱이 아니라 **emit 입력 결측**(falsification 0/598 · portfolio_alpha_t 98% 결측). 따라서 v2는 **문턱·INV 일절 불변** — ①emit이 축을 채우게(스키마 v2) ②Ledger와 Law 사이 Distilled 소비층 신설 ③4모드 회수 배선 완결이 전부다. E2E 실증: 필수필드 완비 emit 1건 → 5축 전부 실입력 도달 → hurdles PPPPP (sandbox 2026-07-04).

## §0. 3층 산출물 모델

엔진의 산출물은 승격이 아니라 **재사용되는 지식**이다.

- **①Ledger** = L-code 원장 (`stage_artifacts/l_code/**` + `.cache/lcode_corpus.json`). 정직 전수 — 실험 사실의 불변 기록. DELETE는 무학습/파손/quarantine 마감분만 (`06_Registry/lcode_distill_plan_20260704.json` 집행).
- **②Distilled** = 클러스터 통합 지식 (`qepm/memory/axioms/distilled/DIST-<MODE>-NNN.json` + `06_Registry/distilled_knowledge.json` 통합 인덱스). **검색(hypothesis_index)·주입(axiom_context_inject/strategic_truths)·negative failure-ledger의 소비 단위.** CAND 골격(supporting_l_codes/scope/mechanism/polarity/metric_type) 상속 + `statement_refined`(사람이 읽는 1~2문장). lifecycle: `pending_5axis`(초안) → `distilled`(/cleaner 세션 LLM 정제 — 무인 정제 금지, INV-6) → `promoted` | `expired`. 재생성 멱등: cluster_key(sorted supporting sha1) 매칭 — draft만 갱신, dist_id/status/statement_refined 절대 보존.
- **③Law** = axiom (`active/` + `active/modes/<mode>/`). 엄선 승격 — 5축 boolean-AND hurdle·INV-1~7·AX-008 2/3 전부 불변. 자동 승격은 documented까지(INV-2), hook block은 주간 도훈 confirm만.

## §1. 파이프라인

```
L-code(모드별 emit v2 — 승격축 필드 포함) → harvest(v2: grade normalize + family 15군 + ID guard)
   → cluster(mode-partition, polarity 정규화) → CAND + DIST 초안(②) + distilled_knowledge.json
   → [자동초안+적대검증] proposed → [도훈 배치승인] distilled(주입) ┐
   → promote(mode-local AX-<MODE>-NNN) → promote_global(AX-NNN) → inject
        ↘ 미달 CAND = review_log(AX-PENDING, same-day dedup) + DIST 초안 유지(폐기 없음)
        ↘ review(NARROW/deprecate) · rollback · weekly_report · run_axiom_weekly 진단
```

- **4 모드**: alpha_search(**proxy** — mode-local 한정) / QEPM(**backtested** forge) / factor_rotation(**backtested** build_bt_result+essence_score) / RAMP(**backtested** canonical_screen_bt/build_bt_result — `docs/rules/ramp.md`). modecode AS/QPM/FR/RAMP (`lcode_emit.R::.LCODE_MODE_PREFIX` = `promote.R::.MODE_PREFIX` 정합).
- **2-tier**: mode-local `active/modes/<mode>/AX-<MODE>-NNN.json` + global `active/AX-NNN.json`.

## §2. 안전 불변식 (절대 위반 금지 — v2 불변)

- **INV-1 metric_type 게이트**: proxy/estimated → mode-local까지. global은 supporting 전부 `backtested`(essence_score §3 HARD). `canonical_screen`은 실측 스크리닝 라벨(measurement-graduation §1)로 스키마에 추가되었으나 global 승격 자격은 `backtested`만 — 불변.
- **INV-2 생성≠강제**: 자동 승격 = `enforcement_mode=documented`/`enforcement=""`. hook block은 주간 리포트 human confirm만. 엔진산 negative 지식의 차단 실효는 enforcement 자동 생성이 아니라 **주입·검색 경로(②Distilled)** 로 확보.
- **INV-3 안전망 실작동**: 롤백 = 마커 블록 삭제(simulated diff 금지). 주간 리포트 = proxy/global 전건 human-review 플래그.
- **INV-4 r7 5축 무결성**: 승격 = 5축 각 min-hurdle 동시 충족(boolean AND). weighted는 랭킹용.
- **INV-5 AX-008**: 자동 global 승격 = Forge+Self-Adversarial+Architect **2/3** verification (v8.2 — Codex Round 제거, Opus 자체 적대검증 치환. 2/3 불변).
- **INV-6 무인 활성화 금지** (2026-07-04 도훈 재정의 — 구 "무인 정제 금지"에서 이동): cluster 초안 텍스트 active화 금지. **초안 작성은 자동화 허용, 활성화는 도훈 배치승인 게이트 필수.** `statement_refined` 초안은 적대검증 붙여 자동 작성 가능(`draft_proposed`, status=`proposed`) — 단 이 상태는 **주입 안 됨**. 활성화(status=`distilled` — 주입/truths/enforcement 소비 시작)는 도훈 배치승인(`approve_proposed`) 필수. 주입 3배선은 **status=`distilled`만** 소비 — `proposed`·`pending_5axis` 초안 텍스트 주입 금지(안전속성 보존). lifecycle: `pending_5axis` → [자동초안+적대검증] → `proposed`(주입 안 됨) → [도훈 배치승인] → `distilled`(주입 가능) → `promoted`|`expired`. /cleaner 수동 정제 직행 경로(`refine_distilled`)는 retain.
- **INV-7 negative asymmetry**: negative = **provisional failure-ledger**(불변 법칙 아님). positive보다 높은 burden(construction≥3) + expiry + 재도전 트리거. distilled negative의 '재시도 금지' 라벨도 provisional — `retry_condition` 충족 + 차별점 명시 + 재도전 사유 기록 시 재시도 가능.

## §3. 5축 (r7 — `promote.R`. 수치 전부 불변)

| 축 | hurdle | 비고 |
|---|---|---|
| Independence | distinct construction ≥ 2 (negative ≥ 3) + direction ≥ 0.8 | strategy_id 착시 폐기. **direction_consistency 정의 (2026-07-04 국소수리②, 문턱 0.8 불변)**: positive/negative = 전체 grade 최빈 비율(종전 동일) / conditional = **조건 축 내 일관성**(win군 A·B / loss군 C·F 각각의 내부 일관성 min — '전체 일치'는 conditional 정의와 모순=영구 미달이던 결함 해소). **주간 리포트 도훈 confirm 대상**(run_axiom_weekly confirm_flags) |
| Rigor | backtested: weakest port_t ≥ 2.95 / negative: backtested frac_fail ≥ 0.8 | proxy=mode-local 관대 |
| Falsification | 적극 반증 attempts ≥ 1 + none_falsified + retained ≥ 0.5 | negative +0.5 폐기. **문자열 attempts crash-safe 수용 (2026-07-04 국소수리①)**: 비구조체 = n 카운트만 + none_falsified 보수 TRUE(판정 근거 없음) — 구조체 전환 권장 WARN |
| External | supporting L-code oos_retention 실값 존재 + cluster median ≥ 0.5 | 2026-07-03 재정의(GOV-01). oos_months는 가산 증거(실값 ≥3m 시 score +0.2, hurdle 무관). corpus 실값 0건 시 draft oos_effect_vs_is 폴백 |
| Mechanism | economic_explanation present + type ≠ unknown | 보일러플레이트("unknown"/"TBD"/10자 미만) 불인정 (schema v2) |

부가 (2026-07-04 국소수리③): `.log_partial` review_log 파일명 = 날짜 기반(`AX-PENDING_<cand>_<YYYYMMDD>.json`) — same-day 동일 candidate 재실행 시 최신본 overwrite + 구 시분초-suffix 동일자 파일 자동 정리 (07-03 15×2 중복 오염 재발 차단).

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
1. **주입**: `hooks/axiom_context_inject.sh` — active 공리 + strategic_truths + **distilled negative/conditional top-5**(status=distilled만, INV-6 — `proposed`·`pending_5axis` 초안 주입 금지). 합산 상한 **2500자** (우선순위: truths > distilled > axiom body 축약).
2. **검색**: `tools/hypothesis_index.R` — 원천 4계층째 distilled 인덱스. verdict = `DISTILLED_NEG`/`DISTILLED_COND`/`DISTILLED_POS`. negative는 lookup 결과에 `retry_policy`('재시도 금지/조건' — INV-7 provisional) 라벨 표출. expired는 인덱스 제외.
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

## §3e. 주간 사이클

- **단일 진입**: `02_Infrastructure/axiom/run_axiom_weekly.R` — harvester → cluster_extractor(+DIST/인덱스) → promote 전 후보 fail-soft 순회 → distilled 인덱스/truths 동기화 → **진단 `.cache/axiom_weekly_diag.json`** ({n_pending, n_promoted, failing_axis_histogram, **near_miss**(1축만 미달 — /cleaner 정제 우선순위), confirm_flags(conditional 재정의 적용 후보 등 도훈 confirm 대상)}).
- **Cleaner 통합**: weekly_cleaner_sweep.R(토 09:00) step 3.5가 본 스크립트를 호출하고 cleaner_pending.json 다이제스트에 axiom_candidates 섹션 포함 (배선 = mode-wiring). `/cleaner` 세션이 near-miss statement 정제(INV-6 해소 → distilled 승격) 전담 — LLM 정제는 /cleaner 세션 전담(무인 배제).
- `ops/axiom_weekly.sh`는 수동 경로 retain (Cleaner 통합이 정규 경로).

## §4. 파일

- 엔진: `02_Infrastructure/axiom/{lcode_schema,lcode_emit,distilled,run_axiom_weekly,promote,promote_global,review,inject,axiom_rollback,axiom_weekly_report}.R` + `{lcode_harvester,cluster_extractor}.py`
- 파이프라인: `run_axiom_weekly.R`(정규 — Cleaner step 3.5) · `ops/axiom_weekly.sh`(수동 retain) · bootstrap(harvest)
- consumer: `hooks/{axiom_context_inject,axiom_enforcement_hook}.sh` · `tools/hypothesis_index.R` · `prompts/strategic_truths.md`(DISTILLED 블록) · `memory/memory_knowledge_health.R` · `qepm/R/axiom_dashboard.R`
- 데이터: `qepm/memory/axioms/{active/,active/modes/<mode>/,candidates/,**distilled/**,deprecated/,review_log/,axiom_sot_map.json}` · `06_Registry/{distilled_knowledge.json,hypothesis_index.json,lcode_distill_plan_20260704.json}` · `.cache/{lcode_corpus.json,axiom_weekly_diag.json}`
- 실행(Windows): `PY=%QVEST_PY%` (venv `.venv_qvest_ml/Scripts/python.exe` — bare python 금지) · `RS=C:/Program Files/R/R-4.5.2/bin/Rscript.exe` · `CLAUDE_PROJECT_DIR` + `PYTHONUTF8=1`

## §5. 운영 규칙

- mode-local 자동 승격(documented). global 승격 + hook block = 주간 리포트 도훈 confirm(비가역).
- 기존 AX-003/004/005/007 = provisional(N=2~3 잠정, 재도전 대상). 추측 폐기 금지 — 엔진 asymmetric 재검증 경유. **active axiom 8건(000~005,007,008) 의미론 절대보존.**
- **도훈 confirm 대상(집행 전 아님 — 주간 리포트 표기)**: ①conditional direction_consistency 재정의(§3) ②emit WARN→BLOCK 승격(2사이클 후) ③distilled→promoted 승격 건별.
- b434 규약: CL-B434 fallback 통합 L-code의 '미검증 잔존 가설 백로그'는 **어떤 개별 가설의 기각 증거로도 인용 금지** (AX-000 — 미검증→기각 둔갑 방지가 failure-ledger 신뢰의 전제).

## Change log
- 2026-07-04 (INV-6 재정의 — 도훈 confirm "옵션 B: 자동초안+배치승인 + 모닝브리핑 승인대상 노출"): INV-6 "무인 *정제* 금지" → "무인 *활성화* 금지". lifecycle에 `proposed` 상태 삽입(`pending_5axis`→[자동초안+적대검증]→`proposed`→[도훈 배치승인]→`distilled`). distilled.R 신규 `draft_proposed`(status=proposed, 주입 안 됨)/`approve_proposed`(proposed→distilled 사람 게이트)/`list_proposed`(모닝브리핑·다이제스트 소비) + `lookup_distilled` distilled-only 필터(proposed 누출 차단). 주입 3배선 status=distilled만 소비(안전속성 보존). INV-1~5·INV-7·AX-008 2/3·5축 hurdle·active AX JSON 전부 불변. quarantined_evidence 6건 초안 대상 제외(가드 재사용).
- 2026-07-04 v2 (엔진 재설계 — 도훈 mandate, engine-core): §0 3층 산출물 모델(Ledger/Distilled/Law) 신설 + ②Distilled 계층 구현(DIST-<MODE>-NNN + distilled_knowledge.json + distilled.R helper + cluster_extractor CAND→DIST 초안·polarity 정규화 왜곡 수리) + 소비 3배선(inject distilled top-5 ≤2500자 / hypothesis_index 4계층 DISTILLED_* + retry_policy / strategic_truths generated 블록) + emit 스키마 v2(§3b — required_for_promotion 계층·grade enum A/B/C/F+legacy alias·record_type·canonical_screen·selection_type 분리·ID 채번 가드; WARN-only, BLOCK 미도입) + harvester v2(grade normalize plan 소비·FAMILY 15군 확장 unknown 146→8·record_type·ID collision) + promote 국소수리 3건(§3 — falsification 문자열 crash-safe / conditional direction_consistency 조건 축 내 재정의(0.8 불변·confirm 플래그) / review_log same-day dedup) + 주간 단일 진입 run_axiom_weekly.R(§3e — near_miss·failing_axis_histogram 진단). **5축 hurdle 수치·INV-1~7·AX-008 2/3·active axiom 8건 의미론 전부 불변.** E2E: 완비 emit 1건 → 5축 PPPPP 실증(sandbox) / 17 CAND 재실행 crash 0 / inject 2295≤2500자.
- 2026-07-03 (도훈 confirm, 감사 GOV-01): External 축 측정가능 재정의 — hurdle을 oos_months(corpus 실값 0건 = 영구 불충족) 기반에서 **oos_retention 실값 존재 ∧ cluster median ≥ 0.5**(corpus 457/594건 실값)로 교체. '요건 완화가 아니라 측정 불가능 지표의 측정 가능 지표 교체'. 문턱 0.5는 구 vs_is 0.5 개념 유지 + measurement-graduation §3 '<0.5 무조건 FAIL' 하한 정합. oos_months는 가산 증거로 강등. (`promote.R .HURDLE/.axis_external`)
- 2026-07-03 현행화 (승격 배관 수리 — hurdle 정의 불변): ① 3-mode → **4-mode**(AS/QPM/FR/**RAMP**) ② INV-5 Codex → **Self-Adversarial**(v8.2 AX-008 치환) ③ cluster_extractor `oos_months` 하드코딩 None → L-code 실값 매핑.
- 2026-06-05 v8.0: 신규. r7 복원 + 3-mode 2-tier + INV-1~7 + 안전망. E2E 10/10 PASS.
