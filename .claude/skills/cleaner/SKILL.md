---
name: cleaner
description: 주간 Cleaner 증류 절차 (/cleaner) — 토 09:00 무인 기계 스윕(weekly_cleaner_sweep.R)이 남긴 .cache/cleaner_pending.json을 소비해, 주간 리서치 엑기스를 weekly_digest로 증류(실측만), 미적립 학습을 L-code로 발행, 가치없는 잔재를 참조0 검증 후 무아카이브 삭제. bootstrap "[cleaner] 주간 증류 대기" WARN 또는 수동 트리거 시 사용.
---

# Cleaner Skill — 주간 증류 절차 (LLM 세션 파트)

**발효**: 2026-07-04 (도훈 mandate — "가치없는 잔재 무아카이브 삭제 + 지식은 L-code 적립 + 시스템 자체 증류")
**설계**: 스킬+스케줄러 하이브리드. **기계 스윕은 무인**(Task Scheduler `Qvest_WeeklyCleaner`, 매주 토 09:00 + StartWhenAvailable), **증류는 본 스킬**(무인 LLM 호출은 권한/판단 리스크로 배제 — 다음 세션에서 수행).
**규칙 SOT**: `02_Infrastructure/docs/rules/artifact-storage.md` §8 3선.

---

## §0 트리거 조건

다음 중 하나면 본 스킬 실행:
1. **bootstrap WARN**: `[boot] WARN: [cleaner] 주간 증류 대기 — /cleaner 실행` (`.cache/cleaner_pending.json` 존재 + `status:"awaiting_distill"`)
2. **수동**: 도훈이 `/cleaner` 호출

pending 파일이 없으면: "증류 대기 없음" 보고 후 종료 (기계 스윕을 수동으로 돌리려면 `Rscript 02_Infrastructure/ops/weekly_cleaner_sweep.R`).

---

## §0.2 선점 프로토콜 (claim — 2-pass 중복실행 방지, 2026-07-18 도훈 mandate W29 next_probe #4)

**사건**: W29 증류에서 스폰된 Cleaner(task#89)와 메인 세션 자동 증류가 같은 `cleaner_pending.json`을 **병행 소비 → 2-pass 중복실행**(07-06 병렬 중복실행 사고 ops 재현). 착수 선점 표시 부재가 원인.

**규약 (§1 절차 착수 *전* 의무)**: `cleaner_pending.json`의 `distill_status`(pending/in_progress/done)를 **claim 트랜잭션으로 점유**한다. `status`(awaiting_distill→distilled)는 bootstrap 마커용으로 불변 — `distill_status`가 그 사이 `in_progress` 중간상태를 표현해 두 소비자의 동시 착수를 차단한다.

1. **착수 claim (atomic)** — §1 ① 직전 실행. owner는 세션/태스크 식별자(예: 메인 세션 = `session_main`, 스폰 Cleaner = `task#<id>`):
   ```
   Rscript -e 'source("02_Infrastructure/ops/cleaner_claim.R"); print(cleaner_claim_distill("<owner>"))'
   ```
   - **`claimed=TRUE`** (reason=claimed 또는 stale_reclaim) → 내가 점유. §1 ①~⑤ 진행. (stale_reclaim = 이전 owner의 claim이 6h 초과 = 크래시 세션 재점유.)
   - **`claimed=FALSE, reason="in_progress"`** → **이미 다른 세션이 증류 중**. 신규 증류(digest 작성·L-code 발행·삭제) **금지** — 아래 3항 병합 정합만 수행하고 종료.
   - **`claimed=FALSE, reason="already_done"`** → 이미 완료. "증류 완료됨" 보고 후 종료.
   - **`reason="contended"`** → claim 임계구역 경합. 잠시 후 1회 재시도.
2. **완료 release** — §1 ⑤ 마커 소거 *직후* 실행 (읽기-수정-쓰기로 ⑤가 쓴 digest_path/distill_summary 등 전부 보존):
   ```
   Rscript -e 'source("02_Infrastructure/ops/cleaner_claim.R"); print(cleaner_release_distill("<owner>"))'
   ```
   `distill_status=done` + `status=distilled` 동기화. owner 불일치 시 거부(force=TRUE 예외).
3. **2-pass 병합 정합 fallback (둘 다 돌아버린 경우 — W29 실사례)**: claim이 `in_progress`를 반환했는데도 이미 부분 산출물을 만들었거나, 사후에 두 pass가 병행 실행된 흔적(같은 week_of digest 2본·중복 L-code)이 확인되면 — **재증류 금지**, 대신 **파일-레벨 재검 후 최종본 병합**: ① digest는 더 완전한 1본 유지·타본 삭제 ② L-code는 `new_lcodes` 원장 대조로 중복 제거(재발행 금지) ③ distill_manifest는 두 pass의 deleted/preserved 합집합으로 정합. 병합 후 owner가 `cleaner_release_distill(force=TRUE)`로 마감.

**정직 경계**: claim은 소비자 간 *착수 직렬화*일 뿐, 증류 판단·삭제는 여전히 LLM+도훈 감독(§2). stale 6h 상한은 증류 세션이 sweep-lock 2h보다 길 수 있음을 반영(관대). 필드 결측 v1 파일은 `status=="distilled"→done`, else `pending`으로 하위호환.

---

## §1 절차 (① → ⑤ 순서 고정)

### ① pending 인벤토리 로드

**⚠ 착수 전 §0.2 claim 의무** — `cleaner_claim_distill("<owner>")` 호출해 `claimed=TRUE` 확인 후에만 아래 진행 (in_progress/already_done이면 §0.2 규약대로 중단·병합).

```
.cache/cleaner_pending.json
```

- `week_of` / `sweep_deleted_n` / `inventory` (stage_artifacts 신규 엔트리 · hypothesis_index 델타 · 신규 L-code · git log 7일 요약) / `step_status` 확인.
- `step_status`에 FAIL 단계가 있으면 해당 수집이 누락된 것 — 필요 시 직접 보충 수집 (예: `git log --since=7.days --oneline`).

### ② 주간 리서치 요약 (weekly_digest)

- 산출: `04_Research/01_reports/weekly/weekly_digest_YYYYMMDD.md` (YYYYMMDD = 실행일. 디렉토리 최초 사용 시 생성)
- 내용: 지난 7일 **실험별 결론·수치** — inventory의 stage_artifacts 신규 엔트리·신규 L-code·커밋 요약을 실제 산출물(각 run의 verdict/hurdle_result/manifest)로 역추적해 정리.
- **실측만** (measurement-graduation §1): 수치는 해당 런의 실제 기록 파일에서 인용, `metric_type` 라벨 병기. **추정·재구성 금지** ([[feedback-performance-real-code-only]]).
- 각 실험: 가설 1줄 / 결론(PASS·FAIL·screen-tier 등) / 핵심 수치(출처 파일 경로) / 후속 여부.

**axiom 후보 현황 (의무 절 — 2026-07-04 주간 axiom 사이클 Cleaner 통합)**:
- 기계 스윕 step [3.5]가 harvester→cluster_extractor→promote 진단을 돌리고 pending의 `axiom_candidates` 섹션(`n_pending` / `failing_axis_histogram` / `near_miss`)을 채운다 (정규 경로 — 구 `axiom_weekly.sh`는 수동/보조 retain).
- digest에 **axiom 후보 현황 절 포함**: pending 건수 + 실패 축 히스토그램(어느 축 결측이 승격을 막는지) + near-miss 목록.

**★ v9.1 공리 사다리 산출 (2026-08-23 §7-S4 — 의무 절. 구 v9 '승인 대기 큐'를 대체)**:
- **승인 대행은 더 이상 이 스킬의 역할이 아니다.** 공리 활성화는 `refine_statement.R` 의 **R0~R6 품질 게이트**가 무인으로 판정한다(INV-6 재정의 = 주입면 자격 게이트). digest 에는 **사후 통지 2절**을 옮긴다:
  - `axiom_candidates.activated_axioms[]` → `- [활성] AX-AS-001 (alpha_search, L-code 187건) <statement_inject 70자> · 되돌리기: deactivate_axiom(c("AX-AS-001"), reason=)`
  - `axiom_candidates.held_axioms[]` → `- [보류/HELD] AX-JG-001 (judge_gate, 13건) 미통과=R5_revival (시도 2회)` — **사유를 반드시 적는다**(사유 없는 보류 목록은 다음 주에 아무 행동도 유발하지 않는다).
- `axiom_candidates.activation_hold` 가 비어 있지 않으면 **맨 위에 경고 1줄**: 회로차단기가 이번 주 공리 쓰기를 전면 중단했다는 뜻이다(사유 = 활성 예정 >3 · 상한 초과 · dry-run crash · 주입 len>1900). 이건 실패가 아니라 설계된 상태이며, 조치는 `activation_hold.action` 에 들어 있다.
- `axiom_candidates.auto_mapped_negative[]`(음성 클러스터 자동 지도된 DIST id)도 1줄 목록으로 병기 — **공리가 아니라 탐색지도**(INV-7)이며 승인 대상이 아니다.
- `axiom_candidates.n_promote_skipped` / `promote_skips[]`: 스폰 자체를 건너뛴 후보(단일 L-code = `SKIP_SINGLETON`, 입력 불변 = `SKIP_UNCHANGED`). **이 수가 크다는 건 정상**이다 — 새 정보가 없는 후보를 매주 재채점하지 않는다는 뜻. 0으로 떨어지면 오히려 사전판정 배선이 죽은 것이므로 확인할 것.
- **★HELD 사유 소비가 이 스킬의 새 공리 역할이다**(정제가 아니라 *입력 수리*): `R5_revival`=멤버 L-code 에 `next_probe`/`live_trigger` 보강 · `R4_falsification`=반증 시도 구조화 기록 · `R0_polarity`=클러스터 polarity 오라벨 정정(`cluster_extractor.py` 재추출) · `R1_members`=결측 supporting 정리 · `R6_distinct`=중복 클러스터 병합 · `R2_tokens`/`R3_mechanism`=emit 지점 보강. 입력이 바뀌면 `refine_input_sha` 가 달라져 **다음 스윕이 자동 재시도**한다(영구 SKIP 없음, AX-000). statement 문안 자체를 손으로 고치지 말 것 — 조립기가 결정적으로 다시 만든다.

**★ INV-6 자동초안 흐름 (2026-07-04 도훈 confirm — "무인 정제 금지" → "무인 *활성화* 금지" 재정의)**:
DIST 초안 lifecycle이 반자동화됨:
```
pending_5axis → [자동초안 에이전트 + 적대검증] → proposed(주입 안 됨) → [도훈 승인] → distilled(주입 가능) → promoted | expired
```
- **★자동화 경계 (정직 — 무인 완주 아님)**: 무인 기계 스윕(`weekly_cleaner_sweep`, 토 09:00)은 **harvest→cluster→promote 진단 + 후보 현황 집계까지만** 수행하고 `status:"awaiting_distill"`로 멈춘다. pending_5axis → proposed 자동초안(`statement_refined` + `adversarial_verdict` 작성)은 **본 /cleaner 세션 에이전트**가 수행한다(스윕 스크립트는 `draft_proposed`를 호출하지 않음). proposed → distilled 활성화(주입 스트림 개방)는 **도훈 배치 승인**이 필수다. 즉 "스윕이 무인으로 증류를 완주한다"는 문구는 오류 — 스윕은 재료를 쌓을 뿐, 초안은 세션, 활성화는 승인.
- **자동초안(허용)**: 본 /cleaner 세션 에이전트가 pending_5axis → proposed 로 `statement_refined` 초안 + `adversarial_verdict`(적대검증)를 작성. **초안 수치·결론은 supporting L-code 실측 결론만** — 창작 금지.
- **자동초안 적대검증 5체크 (a~e — 초안 승인 전 의무)**:
  - (a) **과장**: 헤드라인 수치가 게이트/재현/deflate 반영 없이 낙관적인가? envelope-상대 정직 서술로 강등.
  - (b) **근거**: 결론이 supporting L-code 실측에 실제로 뒷받침되는가? (proxy를 backtested로 오라벨 금지).
  - (c) **AX-000**: 3~4회 실패를 '구조적 한계/dead-end'로 단정하는가? → 재작성(탐색 계속 · 미해결 열어둠 허용).
  - (d) **★의미기반 제약 방화벽 (정규식 아님)**: `Rscript -e 'source("02_Infrastructure/axiom/constraint_firewall.R"); print(load_firewall_context())'` 로 **원리 + 케이스 few-shot을 읽고**, 초안이 고정 제약 6종(종목수≤25·유동성 2e8·long-only·Σw=1·K200∪KQ150·15bps — v10: 비중 상한 폐지)+PIT를 실패 원인으로 **귀속**하거나 제약 **완화**를 레버로 제시하는지 **에이전트(LLM)가 의미로 판정**한다. 씨앗 케이스에 없는 임의 패러프레이즈·영어·미묘한 프레이밍도 원리로 일반화해 잡는다. **위반 시**: envelope-안 레버(overlay·잔차 sleeve·비-return·DPL·regime-conditional·multi-sleeve·composite·ML sizing) 상대로 재작성 + `append_firewall_case(caught, why, reframed)` 로 케이스 라이브러리에 축적(자기발전 — 잡을수록 방화벽이 똑똑해짐). ('봉투 안에서 이 경로는 천장' 정직 서술 · '미해결 열어둠'은 위반 아님 — 통과.) 정규식 backstop은 `check_constraint_firewall(text, mode="backstop")` — 비-소진적 최종 그물일 뿐(draft_proposed 내부 가드가 자동 호출).
  - (e) **프론티어 생성 (실패는 앞을 가리켜야)**: 초안이 미탐색 인접(`frontier`)을 담는가? 없으면 생성한다 — 실패 메커니즘이 가리키는 근거 있는 인접 hypothesis(구성-인접 + 메커니즘 동기, envelope-안). 예: "EP-단독이 value premium 약화+quality mix 부재로 F" → frontier = value+quality composite / regime-conditional value / spread-reversion. **창작 금지**(claim이 아니라 hypothesis, 적대검증 대상). negative 초안은 `frontier`(list) + `live_trigger`({type:regime|spread|data|time…, condition, monitored_source} — 열린 스키마) + `expiry` 필수 필드로 `draft_proposed(..., frontier=, live_trigger=, expiry=)` 저장.
- **노출(모닝브리핑)**: `02_Infrastructure/ops/morning_steps/axiom_approval_queue.R`(스텝 [5b/5])가 status=proposed 목록을 사람이 읽는 요약(dist_id·statement 1줄·적대검증·supporting L-code 수·만료)으로 매일 노출.
- **활성화(도훈 승인 게이트, 무인 금지)**: 도훈이 `Rscript -e 'source("02_Infrastructure/axiom/distilled.R"); approve_proposed(c("DIST-..."))'` 로 배치 승인 → status=proposed → distilled 전환 시에만 주입 3배선(inject/hypothesis_index/strategic_truths)이 소비. **proposed·pending_5axis 초안은 절대 주입 안 됨**(INV-6 안전속성 보존).
- **불변**: 주입 3배선은 status=distilled만 소비. active AX JSON 무변경(DIST 계층 작업). `quarantined_evidence`(현 6건, 07-04 증거계보 감사 TAINTED)는 초안·정제·활성화 대상 제외.

**★ 백로그 드레인 + stale 대조 규약 (2026-07-17 도훈 승인 수리 — 2주 운영 감사)**:
- **① pending_5axis 드레인 의무**: 매 /cleaner 세션 시작 시 `06_Registry/distilled_knowledge.json`에서 `status="pending_5axis"` **잔량 + 최고령 `created_at`** 확인(실측 2026-07-17: 49건, 최고령 2026-07-08 등재분). 세션당 **최소 초안 처리량 = 권장 5건+** — 우선순위는 **supporting L-code 수 상위**(pending → proposed 자동초안 + 위 적대검증 5체크). near-miss만 집고 백로그 전체를 이월하는 패턴 금지(W28 "잔여 pending_5axis 백로그 차주 이월" 반복이 49건 적체의 원인 — 이월 시 사유·잔량 명기).
- **② quarantined_evidence 잔량 확인**: `status="quarantined_evidence"` 잔량·정체일 1줄 보고(실측 2026-07-17: 6건, 07-04 TAINTED 이후 13일 정체) — 초안 대상 제외는 불변, 잔량 방치는 관측 대상.
- **③ distilled ↔ settled-negative 주기 대조 (§0.1 원리5 — 메커니즘·카드도 Cleaner 리뷰 대상)**: 승인된 `status="distilled"` 카드의 `frontier`/`statement_refined`를 최신 settled-negative 목록(measurement-graduation §5·§6 + 메모리 settled 항목)과 대조 — settled-negative를 '미검증 레버'로 광고 중인 stale 카드는 **재정제 대상 등재**(`refine_distilled`). 실사례: **DIST-RAMP-006**이 frontier에 DPL(2026-06-26 settled-negative — 재제안 금지)을 미검증 레버로 광고 중이며 잔차 sleeve 스태킹 항목도 07-05 RAMP R1 config-scoped 미달 실측 미반영 — **07-18 재정제 대상**.

- **④ 재등재 supersede = 기계 상시 (2026-08-02 배선 — 수동 회수 반복 종료)**: 부분집합 구 카드 회수는 이제 **엔진이 매 harvest/cluster 사이클마다 자동 집행**한다 (`cluster_extractor.py::supersede_subsumed`, `build_distilled` 후-패스). 판정 = 08-02 수동 회수 9건과 **동일 엄격 기준**(진부분집합 ∧ family/polarity/type/research_mode 전부 동일 ∧ 지식 손실 0 ∧ 구 카드가 저술 지식 미보유). 사유 형식도 동일(`superseded_by=<id> — 같은 클러스터…`)이라 이력 검색이 일관되며 꼬리 문구로 엔진/수동 출처가 갈린다. `status=distilled|promoted|quarantined_evidence`는 대상 제외.
  - **/cleaner 세션의 일 = 기계가 회수하지 **않은** 것**: 실행 로그의 `[warn:lossy]`(부분겹침 — 구 카드 전용 L-code 보유), `[warn:authored]`(정제 초안 보유), `protected-skip`(활성 카드 부분집합) 3종이 수동 판단 큐다. 08-02 실측: lossy 3쌍(QPM-003⊄007 / QPM-014⊄035 / RAMP-013⊄003), protected-skip 6쌍.
  - 수동 단발 실행: `Rscript 02_Infrastructure/axiom/distilled.R supersede [--dry-run]` (또는 `cluster_extractor.py --supersede-only`). 카드 파일은 삭제하지 않고 status만 전환(이력 보존).
  - 가드: `08_Tests/axiom/test_distilled_supersede.py` (배터리 등재). **돌연변이 축 M1~M5가 본체** — 08-02 드레인 이후 저장소 추가 회수 대상이 0건이라 정상 경로만으로는 로직 사망과 정상이 겉보기 같다.

### ③ 엑기스 적립 (L-code + 메모리)

- digest 작성 중 발견한 **미적립 학습**(L-code 없는 유의미한 교훈)은 `02_Infrastructure/axiom/lcode_emit.R::emit_lcode()`로 발행 (모드별 prefix 자동, `metric_type` 정직 라벨 — proxy 결과에 backtested 금지).
- 새 L-code 발행 시 헌법 Session End 규칙 적용: `methodology_active.md` 등재 + auto-memory `MEMORY.md` 헤더 갱신 안내.
- 이미 L-code가 있는 학습은 재발행 금지 (inventory의 `new_lcodes` 목록과 대조).

### ④ 잔재 삭제 (무아카이브 — 참조0 검증 후)

- 대상 판정: `artifact-storage.md` **§3.1**(리서치 모드 중간 산출 = 재생성 가능 스크래치) + **§4 Retention** 위반 잔재. 지식 기록이 아닌 **죽은 코드·중복·캐시만** 표적.
- **절대 보존** (어떤 삭제도 금지): `05_Production/` · `01_Literature/` · `stage_artifacts/` 내부 · `qepm/{memory,registry,mailbox}` · `qepm/research/results` · `04_Research/strategies` · `04_Research/90_legacy` · `04_Research/01_reports` · `outputs/`(canonical) · `06_Registry/` · bearish_forecast_v3 (morning_briefing 일간 소비 — 활성).
- 삭제 전 **참조 0 검증 의무**: 후보 경로를 프로젝트 전체 grep (실행코드 + config + registry json) — 참조 1건이라도 있으면 보존 + deferred 기록. 판단이 갈리면 보존.
- 통과분만 무아카이브 삭제 후 **distill manifest 기록**: `06_Registry/distill_manifest_YYYYMMDD.json` — `{deleted: [{path, reason, ref_check:"0건"}], preserved_deferred: [...]}`.

### ⑤ 마커 소거 + 완료 보고

- `.cache/cleaner_pending.json`의 `status`를 `"distilled"`로 갱신 + `distilled_at`·`digest_path` 필드 추가 (bootstrap WARN 해제 조건 = `awaiting_distill` 소거). **claim 필드(distill_status/distill_owner/distill_claimed_at)는 보존** — 덮어쓰기 금지.
- **§0.2 release 실행** (status 갱신 직후): `cleaner_release_distill("<owner>")` → `distill_status=done` + `status=distilled` 동기화. 읽기-수정-쓰기라 위 ⑤ 기록분(digest_path/distill_summary 등)은 전부 보존된다.
- 텔레그램 완료 보고: `tg_agent_brief()` (qvest-telegram SOT 준수 — 첫 섹션 한글 연구 컨텍스트. agent는 화이트리스트 내 `"Q-Lead"` 사용 — 전용 "Cleaner" 미등재). 내용: digest 경로 / 신규 L-code n건 / 삭제 n건·manifest 경로 / deferred n건.

---

## §2 금지·주의

- **증류(digest·삭제 판단) 자동화 금지** — 본 스킬은 항상 대화 세션에서 실행 (④ 삭제 판단은 LLM+도훈 감독 하).
- **§0.2 claim 없이 증류 착수 금지** — claim `claimed=TRUE` 확인 전 digest 작성·L-code 발행·삭제 금지 (2-pass 중복실행 방지). in_progress면 병합 정합만.
- **DIST 초안 무인 *활성화* 금지 (INV-6, DIST 카드 한정)** — DIST 카드는 자동초안(pending→proposed)+적대검증까지 허용되나 proposed → distilled 활성화는 **도훈 배치 승인 게이트 필수**(`approve_proposed`). ★**공리(AX-<MODE>-NNN)는 다르다(v9.1)**: 활성화는 `refine_statement.R` R0~R6 가 무인 판정하며 이 스킬은 승인 대행이 아니라 **HELD 사유 소비**(위 §공리 사다리 산출)를 한다. 두 계층을 섞지 말 것 — DIST 는 탐색지도 카드, AX 는 mode-local 공리다.
- digest에 proxy/추정 수치를 실측처럼 기재 금지 (answer-principles 회피표현 grep 대상).
- `stage_artifacts/` 내부는 인벤토리 소스일 뿐 — 어떤 파일도 이동·수정·삭제 금지 (§6 불변 런 기록).
- 커밋은 메인 세션 규율에 따름 (본 스킬이 임의 커밋하지 않음).

## 참조

- `02_Infrastructure/ops/weekly_cleaner_sweep.R` (무인 기계 스윕 — pending 생산자, schema cleaner_pending_v2)
- `02_Infrastructure/ops/cleaner_claim.R` (§0.2 선점 프로토콜 — `cleaner_claim_distill`/`cleaner_release_distill`/`cleaner_distill_state`. 2-pass 중복실행 방지)
- `02_Infrastructure/ops/scheduler/Qvest_WeeklyCleaner.bat` + Task Scheduler `Qvest_WeeklyCleaner`
- `02_Infrastructure/docs/rules/artifact-storage.md` §3.1 / §4 / §8
- `02_Infrastructure/axiom/lcode_emit.R` · `.claude/skills/qvest-telegram/SKILL.md`
- `02_Infrastructure/axiom/constraint_firewall.R` (의미기반 제약 방화벽 — semantic 우선·케이스 학습) · `06_Registry/firewall_cases.json` (케이스 라이브러리) · `02_Infrastructure/axiom/distilled.R` (`draft_proposed` frontier/live_trigger/expiry)
- `02_Infrastructure/docs/rules/axiom-engine.md` §0.1(메커니즘 비-ossification) + INV-7(negative=탐색지도, 제약 방화벽)
