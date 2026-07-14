# Qvest 아키텍처의 "포기방식" 연구 (Abandonment Architecture Study)

**작성**: 2026-07-15 (도훈 요청 "현재 Qvest 아키텍처의 포기방식에 대해 연구해보자" 2026-07-14)
**방법**: 14-에이전트 워크플로(wf_2a348b0e) — 7개 포기-표면 병렬 정독 + 6개 긴장점 독립 적대검증 + 완결성 비평. 전 배선은 grep/파일 mtime/Task Scheduler State로 실측(문서-주장 아닌 실배선 확인).
**후속**: 본 연구의 진단이 곧바로 **Continuity Firewall 구축**(2026-07-15, `docs/rules/continuity-firewall.md`)의 근거가 됨.

---

## 0. 요약 — 가장 날카로운 단일 발견

> **전 apparatus는 포기의 *억제*만 기계화하고, 포기·부활의 *결정*은 전부 soft(인간/LLM)에 남겨, 모든 결과적 판단이 도훈 단일 노드로 funnel된다. 기계강제는 오직 '멈추지 마라 / 봉투 넘지 마라' 방향뿐이다.**

기계가 강제하는 것: 종결어휘 감시(continuity guard, 당시 warn) · 제약-귀속 regex(firewall backstop) · graduation HARD 3종(fail-closed). 전부 예방(prevention) 방향.
기계가 **못** 하는 것: (a) 내생적 "소진" 판정 문턱 부재 → 합법중단은 도훈 지시뿐 (b) semantic-primary 방화벽은 `pass=NA`로 자동 미실행 (c) 부활은 coarse regime=CRISIS 위 아무것도 자동 un-bury 못 함 (d) 최종 자본 admission은 완전 수동.
그리고 결정적 반전: **기계가 유일하게 능동·비가역으로 하는 일(/cleaner 무아카이브 삭제)은 보존 교리와 정반대 방향**이다.

요컨대 "Qvest의 포기방식" = **교리-과잉·인간부하-집중**. kill/keep/revive의 실제 결정이 전부 soft라서 도훈이 4개 결과노드(자본게이트·부활발사·삭제판정·외부게이트해제) 전부에서 유일한 load-bearing decider로 남는다.

---

## 1. 7-표면 지도 (포기방식은 단일 기능이 아니라 서브시스템)

| # | 표면 | 포기의 형태 | 판정자 | 배선 |
|---|---|---|---|---|
| S1 | **공리 + 제약 방화벽** (AX-000·INV-7·firewall_cases) | 조기 단정 *금지* + 제약-귀속/완화-레버 REJECT | 규약 + regex backstop | partial |
| S2 | **행동 가드** (research_continuity_guard·연속성 6호) | 종결어휘·대기자세 마감 감시 | Stop 훅 (당시 warn) | active_warn→**block(07-15)** |
| S3 | **3층 지식모델** (Ledger/Distilled/Law) | 폐기 아닌 *형태 전환*(피처·탐색지도) | 다층 분산 (활성화=도훈) | partial |
| S4 | **부활 기구** (revival_signals·monitor) | 포기의 *역방향* — 시스템이 먼저 깨움 | 자동 monitor + 인간 착수 | active_warn |
| S5 | **kill 게이트** (graduation HARD·screen-tier) | 자본 부적격 kill vs 라우팅 | 자동 hook (fail-closed) | **active_enforced** |
| S6 | **상태어휘 + EV 지도** (frontier_queue·ev_map·layer_bottleneck) | 내부탐색 소진 판정 → 외부게이트 핸드오프 | 4갈래 혼합 | partial |
| S7 | **settled-negative 코퍼스** (재시도금지 ↔ INV-7) | 사실상 영구 포기 vs "영구 판결 아님" | Q-Lead 규약 | partial |

### S1 — 공리 + 제약 방화벽
"합법적 포기 vs 조기 단정"의 경계를 정의하는 최상위 층. AX-000(포기 금지) + INV-7(negative=Law 아닌 Distilled 탐색지도, 경로-scoped) + 제약 방화벽(고정 제약 귀속/완화-레버=REJECT)이 삼중으로 "kill"을 "부활조건 붙은 보류"로 재정의.
- **배선 실측**: `.claude/settings.json` "firewall" grep = **0** (훅 미등록). 자동 강제 유일층 = regex backstop (`distilled.R:281` 초안 stop, `lcode_emit.R:126` 플래그만). **semantic 모드는 `constraint_firewall.R:195`에서 `pass=NA, needs_llm_judgment=TRUE` — 판정을 거부**. `append_firewall_case()` 프로덕션 caller **0건** → 케이스 07-04 8건서 성장정지.

### S2 — 행동 가드 (research_continuity_guard)
Q-Lead(LLM)의 "종결/대기 자세" 마감 편향을 Stop 이벤트에서 순수 regex로 사후 감시(당시 warn). W1(종결어휘∧next_step無)·W2(대기자세∧frontier in_progress=0)·W3(L-code후 layer_bottleneck stale). **실증 실패**: 가드 배선(07-13) 다음날 07-14 도훈이 "종착·완결·끝"으로 3회 적발. → **07-15 Continuity Firewall이 block으로 승격·대체**(§5).

### S3 — 3층 지식모델 (Ledger/Distilled/Law)
방향이 "실패"해도 삭제 않고 3층으로 형태-전환 보존. **단 실질은 2층 시스템**: mode-local 승격 0(`active/modes/*` 전부 empty)·Distilled→Law 승격 0(`promoted_to_axiom` 전건 null)·negative Law 4건(AX-003/004/005/007)은 07-05 오히려 deprecated 강등. Law는 신규 지식을 받지 않는 정적 층.
- **보존 실측**: Distilled 53카드 중 소비면(inject) 도달 = `status=distilled` **13건뿐**(33건 pending_5axis 정체). 병목 = 활성화가 도훈 /cleaner 수동승인. 가장 넓은 회수 채널(hypothesis_index)이 documented_only — hook 미강제(2026-07-06 병렬중복 사고의 원인).

### S4 — 부활 기구 (failure_revival_monitor)
Distilled negative를 신호명부 현재값이 조건 충족 시 매일 자동 감지해 "재도전 시점 도달"을 시스템이 먼저 띄우는 anti-ossification 루프. **배관은 완전 배선·실가동**(Task Scheduler `Qvest_MorningBrief`=Ready, flags mtime 07-14 07:11 = 일일 재생성, live_trigger→revival_spec 자동번역 실작동). **그러나 low-bite**: 발화 3건 전부 negative(FQ-007), 유일 발화 기계신호 = coarse regime=CRISIS, 최고-EV `dart_insider`는 07-04부터 pending 방치(한 번도 발화 안 함).

### S5 — kill 게이트 (graduation HARD + screen-tier) — 유일한 active_enforced
Deployment WT(`*/WT-P*/request.json`) 생성 시 forge-authoritative HARD 3종(PORT_t≥2.95·oos_retention≥0.7·calmar≥0.64, sweep이면 DSR)을 fail-closed 실차단. `router_dispatch.json` index8 → `qvest_hook_router.py:542` first-block verbatim으로 실전달 확인. **가장 결정론적 포기**. 단 신호 실재 시 screen_route(OVERLAY_CANDIDATE/FR_RCMA/TURNOVER_REVIEW)로 라우팅(완전 포기 아님). PIT 위반만 계층 무관 절대 기각. 최종 자본 admission(book_state)은 이 게이트와 분리 — governor 정지+도훈 수동.

### S6 — 상태어휘 + EV 지도
frontier_queue 47개 status 어휘 + research_ev_map(capital_pass=0·D1~D7 dead) + layer_bottleneck_map(갭 ①재료 귀속). **핵심**: 이 층은 포기를 *판정*하기보다 포기 어휘를 *금지*(continuity guard)하도록 배선됐고, 실제 내생중단 판단(research_ev_map)은 **강제력 0인 수동 문서**(.sh/.R/.py 전수 grep 0건 = 어떤 코드도 소비 안 함).

### S7 — settled-negative 코퍼스 ↔ INV-7
"재시도 금지/settled-negative" 라벨과 INV-7 "negative는 영구 판결 아님"을 '경로(config)-scoped 재시도금지 + 차별점 명시 시 재도전'으로 봉합. 봉합은 doctrine·산문 양쪽에서 정확히 적용(FQ-014 "선별-정렬 축은 open … Boruta-on-PORT_t-pool은 음-소진(재시도 금지)"). **단 최강 무조건 kill(DPL·conjunctive·TE net-sink·uncertainty·crisis-timer·KNS)은 자기 DIST 카드가 없어 부활 감시 밖** — 유일 부활경로가 산문뿐.

---

## 2. 6개 긴장점 적대검증 (전부 partial_gap — by-design과 real-gap 분리)

| 긴장 | 판정 | severity | 핵심 |
|---|---|---|---|
| **T1** settled-negative ↔ INV-7 | partial_gap | medium | 봉합은 real(경로-scoped)이나 retry_policy 강제 훅 0건 + 최강 6종 kill이 부활 배선 밖(무조건 어투) |
| **T2** 내생적 중단 기준 부재 | partial_gap | medium | "소진" 문턱 부재는 by-design(AX-000 immutable). 단 research_ev_map이 documented_only라 "포기를 외부게이트 대기로 재명명" |
| **T3** semantic-primary ↔ regex-only | partial_gap | medium | semantic은 에이전트 추론으로 실작동(by-design)이나 **기계적 트리거/검증 부재 + 자기발전 루프(append_case) 미배선** |
| **T4** 가드 실효성 | partial_gap | medium | theater 아님(next-turn 넛지 실재)이나 사후 warn + regex 부분성 → 표적 실패(07-14 3회) 놓침. **block 승격이 해법**(→§5) |
| **T5** 부활 실효(bite) | partial_gap | medium | ceremonial 아님(일일 실가동)이나 all-negative + coarse CRISIS 독점 + 최고-EV dart_insider 미발화 = low-bite |
| **T6** 비대칭 비용 | partial_gap | medium | Type-I(조기포기)만 억제, Type-II(안 놓음)엔 대칭 기계 없음. "포기는 있고 어휘만 금지"가 강하게 확증 |

**공통 구조**: 6긴장 전부 "배선 부재"를 정확히 잡았고, 판정은 대체로 "핵심 원리는 by-design·경계됨 + 특정 배선 조각이 real-gap"으로 균형적. T3·T4가 Continuity Firewall이 직접 메운 갭.

---

## 3. 완결성 — 놓친 표면·긴장 (7표면이 못 덮은 것)

**놓친 포기-표면 5종** (전부 파일 실존 확인):
- **S8 세대-단위 포기**: legacy_write_block + DEPRECATION.md + v55/S0-S7·178+STR = *한 아키텍처 세대 전체*를 격리로 포기. 훅-강제, **부활경로=git 고고학뿐** — INV-7이 정작 가장 큰 포기 코퍼스엔 미적용.
- **S9 module_quarantine**: metric_type/contract_pass/frozen 미달로 fr_eligible=false 격리 — 성과와 직교하는 "계약적 포기".
- **S10 governor DEFER**: HARD 3종을 *통과한* 후보가 book-marginal ΔIR<0.05로 자본 못 받는 DEFER = **16/16 admission FAIL이 사는 최종·최상위 포기 노드**. 완전 비기계(도훈 수동).
- **S11 /cleaner 무아카이브 삭제**: 시스템이 유일하게 능동·비가역 *파괴*하는 표면 — 3층 무손실 교리의 정반대.
- **S12 knowledge_recheck/axiom_recert**: 보존된 지식을 사후에 강등/무효화하는 역방향(harvey_t HARD→ADVISORY가 DIST-JG-001 소급 무효화).

**놓친 긴장 5종** (일부는 T1~T6보다 근본적):
- **T7** 무손실 vs /cleaner 삭제: 삭제 판정자와 보존 판정자가 같은 LLM인데 참조탐지(hypothesis_index)가 미강제 → 참조0 오판 시 무손실 위반.
- **T8** 보존은 데이터를, 유효성은 아님: Ledger가 batch_434 오염·harvey_t 강등·stored-panel look-ahead 수치를 "정직 전수"로 보존하고 revival이 유효한 듯 재부상 → **오염-전파 채널(T1보다 근본)**.
- **T9** 부활의 죽음-확증 편향: CRISIS만 발화 → 가장 확실히 죽은 defense/quality만 재검사, 고-EV dart_insider는 안 깨움 = anti-ossification이 실제론 ossification 확증.
- **T10** good-but-not-yet 낙하: 전 apparatus가 negative-키. governor DEFER(죽지도 자본받지도 못함)는 negative가 아니라 DIST/revival 못 받는 limbo — "충분히 좋으나 지금은 아님"의 집이 부재.
- **T11** 세대-포기의 INV-7 면제: 작은 것은 카드+트리거로 되살리고 큰 것(178+STR)은 고고학에 맡김 — 무조건-보존 교리와 실배선이 규모에 반비례.

---

## 4. 진단 종합

시스템은 **'포기'가 없는 게 아니라, 포기를 재명명하고 최상위 어휘만 단속**한다. layer_bottleneck_map은 내부적으로 "소진 지대·칼만 연구 완결" 같은 헌법 금칙어를 쓰면서, 최상위 보고에는 "config_scoped_negative_frontier_open"만 노출한다. book-closing 판단(research_ev_map)은 실존·문서화됐으나 어떤 actuator에도 안 물려 있다.

이 비대칭(예방만 기계화, 결정은 soft)은 상당부분 **의도적 설계**다 — 16/16 FAIL 기저율에서 Type-I(살아있는 유일 방향 놓침) 비용이 지배하므로 precision-favoring이 정당하고, 지식 무손실은 INV-7이 담당한다. 그러나 그 대가로 (a) Q-Lead의 종결-편향(성향)에 lexical 대증요법만 존재해 구조적 재발 (b) 최고-EV 채널을 부활이 못 깨움 (c) 모든 결과 결정이 도훈에 집중 — 이 세 실질 갭이 남는다.

---

## 5. 대응 (a) — Continuity Firewall (구축 완료, 07-15)

T3·T4가 잡은 S2 갭(사후 warn·regex·semantic 미배선)을 정면으로 메운 4-레이어 시스템 (SOT `docs/rules/continuity-firewall.md`):
- **L1** Stop 훅 warn→**block**(강제 속행) · **L2** 독립 semantic 판정(`continuity_gate.py` — 신어 verdict-close 일반화) · **L3** 건설적 종료계약(`close_round.R` — next_probe≥2·부활조건 인자강제) · **L4** 자가발전(`continuity_cases.json` + 3중 caller — firewall의 "append caller 0건" 실패 회피).
- **★전환**: "끝남 단어 금지"(어휘 발명에 짐) → "계속 산출물 요구"(단어교체로 못 속임).
- **검증**: 회귀 22/22 · 우회 red-team 12/12 차단 · 정밀도 red-team 10/10 무오차단.
- **불변**: 판정 자체(negative·천장)는 불차단 — INV-7의 frontier+live_trigger가 곧 통과조건(게이트=INV-7 실무 집행자).

---

## 6. 대응 (b) — 남은 확장 로드맵 (우선순위)

"자체적으로 포기하지 않는 자가발전형 아키텍처"를 완성하려면, S2(continuity, 완료) 외에 부활·엔진 측 갭이 남는다. EV·즉효 순:

1. **[T5/T9·즉효] 부활 최고-EV 채널 배선**: `dart_insider_present`를 pending→active + source_path=`outputs/ramp/insider_panel_meta.json`(07-14 실랜딩) + DIST-AR-001/003 revival_spec 활성화 → dry-run(write_flags=FALSE)으로 첫 비-regime 발화 검증. 부활이 "죽은 것 재확인"에서 "데이터 도착 트리거"로 전환하는 실증. **아침브리핑 surface 건드림 → 도훈 착수 확인 필요.**
2. **[T3·엔진] 방화벽 semantic attestation**: DIST 초안에 `firewall_semantic_attested` 필드 + `distilled.R:281`을 attestation 결측 시에도 stop → "이미 수행했어야 한다"는 가정을 검증 게이트로. + append_firewall_case 자동 caller 배선(continuity firewall과 동형). surface-무영향.
3. **[T2] research_ev_map 에스컬레이션**: documented_only를 morning brief 소비 입력으로 — 내부 EV 소진(R1~R3 done ∧ 최근 N라운드 ⑧위생 route)을 도훈에 명시 surface("외부게이트 대기, 저EV grind 대신 에스컬레이션"). 자동 중단·제약완화 없음(INV-7 정합).
4. **[T1] 무조건 kill 6종 DIST 카드 backfill**: DPL·conjunctive·TE net-sink·uncertainty·crisis-timer·KNS에 전용 카드 + expiry+live_trigger+revival_spec 3필드 → failure_revival_monitor 감시망 편입(산문뿐 부활경로 → 기계 배선).

의도적 non-goal: **T6의 Type-II frontier-aging book-closer**는 만들지 않는다 — "덜 포기"를 원하는 mandate와 상충(연구도 이를 명시).

---

## 부록 — 산출물
- 워크플로 결과 전문: `<session>/subagents/workflows/wf_2a348b0e-12b/journal.jsonl`
- Continuity Firewall: `docs/rules/continuity-firewall.md` + 5 신규 파일
- 메모리: `project-continuity-firewall-20260715`
