---
name: cleaner
description: 주간 Cleaner 증류 절차 (/cleaner) — 토 09:00 무인 기계 스윕(weekly_cleaner_sweep.R)이 남긴 .cache/cleaner_pending.json을 소비해, 주간 리서치 엑기스를 weekly_digest로 증류(실측만), 미적립 학습을 L-code로 발행, 가치없는 잔재를 참조0 검증 후 무아카이브 삭제. ★2026-09-05부터 증류는 무인 레인(cleaner_distill_run.sh)이 먼저 돈다 — 본 스킬은 그 레인이 연기·실패했을 때의 수동 경로이자 사후 검토 절차다. bootstrap "[cleaner] 주간 증류 대기" WARN 또는 수동 트리거 시 사용.
---

# Cleaner Skill — 주간 증류 절차 (LLM 세션 파트)

**발효**: 2026-07-04 (도훈 mandate — "가치없는 잔재 무아카이브 삭제 + 지식은 L-code 적립 + 시스템 자체 증류")
**설계 (v2 — 2026-09-05 도훈 지시로 개정)**: 기계 스윕은 무인(Task Scheduler `Qvest_WeeklyCleaner`, 매주 토 09:00 + StartWhenAvailable), **증류도 이제 무인**(`cleaner_distill_run.sh` — 스윕 직후 + morning_run `[0.75]` 일간 재시도). 본 스킬은 그 레인이 **연기·실패했을 때의 수동 경로**이자 산출 **사후 검토** 절차다.
**규칙 SOT**: `02_Infrastructure/docs/rules/artifact-storage.md` §8 3선.

---

## §0 트리거 조건

다음 중 하나면 본 스킬 실행:
1. **bootstrap WARN**: `[boot] WARN: [cleaner] 주간 증류 대기 — /cleaner 실행` (`.cache/cleaner_pending.json` 존재 + `status:"awaiting_distill"`)
2. **수동**: 도훈이 `/cleaner` 호출

pending 파일이 없으면: "증류 대기 없음" 보고 후 종료 (기계 스윕을 수동으로 돌리려면 `Rscript 02_Infrastructure/ops/weekly_cleaner_sweep.R`).

### §0.1 ★먼저 물을 것 — 무인 레인이 이미 했는가 (2026-09-05 신설)

WARN 이 떠 있다는 건 **무인 레인이 아직 못 돌았다**는 뜻이다. 원인이 셋이라 구분해서 시작한다:

```
Rscript 02_Infrastructure/ops/cleaner_distill_lib.R gate
```

| rc | 뜻 | 세션이 할 일 |
|---|---|---|
| 0 | 착수 가능인데 레인이 아직 안 불렸다 | `bash 02_Infrastructure/ops/cleaner_distill_run.sh` 한 번 돌리고 결과만 검토. 손으로 §1 을 반복하지 말 것 |
| 11 | 충돌로 연기 중(강화 러너 활성·스윕 실행 중) | **기다린다**. 일간 훅이 집는다. 급하면 강화 tick 이 끝난 뒤 위 명령 |
| 12 | kill switch off | 도훈 의도적 정지 — 손으로 증류할지 먼저 물을 것 |
| 10 | 할 일 없음/이미 완료 | WARN 이 남아 있다면 그게 결함이다(release 누락) — `.cache/cleaner_pending.json` 확인 |

`.cache/scheduler_logs/cleaner_distill_*.log` 와 `.cache/cleaner_distill_log.jsonl` 이 레인의 이력이다.
**반복 실패(3주+)면 그게 그 주의 과제다** — 손으로 증류를 대신하는 것보다 레인이 왜 못 도는지가 크다.

### §0.1b 사후 검토 (무인 레인이 돌았을 때 — 이쪽이 기본 경로)

`06_Registry/distill_manifest_YYYYMMDD.json` 을 읽고 **네 가지만** 본다:
1. `deleted[]` — 지워진 것 중 지우면 안 됐던 게 있나. 있으면 `git checkout` 으로 되살리고(추적분) 보호 목록에 등재.
2. `rejected[]` — 기계가 거부한 사유가 **매주 같은 것**이면 목록이나 가드가 낡은 것이다.
3. `dist_drafts[]` — v10.2 퇴역 뒤엔 비어 있어야 한다(있으면 레인 프롬프트가 퇴역 분기를 못 읽은 것).
4. `digest` — 실측만 쓰였나(추정 수치·회피표현 grep).

**★학습 고리**: digest 의 학습 고리 절에서 닫힌 라운드 · 사슬이 0 인 주가 이어지거나 열린 탐침만 늘면 그게 그 주의 관찰이다(구 `pending_5axis` 백로그 속도 점검은 퇴역).

---

## §0.2 선점 프로토콜 (claim — 2-pass 중복실행 방지, 2026-07-18 도훈 mandate W29 next_probe #4)

**사건**: W29 증류에서 스폰된 Cleaner(task#89)와 메인 세션 자동 증류가 같은 `cleaner_pending.json`을 **병행 소비 → 2-pass 중복실행**(07-06 병렬 중복실행 사고 ops 재현). 착수 선점 표시 부재가 원인.

**규약 (§1 절차 착수 *전* 의무)**: `cleaner_pending.json`의 `distill_status`(pending/in_progress/done)를 **claim 트랜잭션으로 점유**한다. `status`(awaiting_distill→distilled)는 bootstrap 마커용으로 불변 — `distill_status`가 그 사이 `in_progress` 중간상태를 표현해 두 소비자의 동시 착수를 차단한다.

★**소비자가 셋이 됐다 (2026-09-05)**: 메인 세션(`session_main`) · 스폰 Cleaner(`task#<id>`) · **무인 레인(`auto_distill`)**. 같은 프로토콜을 그대로 쓴다 — 무인 레인도 claim 을 잡고, 비정상 종료 시 `final_status="pending"` 으로 반납한다(claim 을 쥔 채 죽으면 stale 6h 까지 다음 훅이 막히기 때문). owner 가 `auto_distill` 인 `in_progress` 를 보면 **손으로 증류하지 말고 기다린다**.

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

**학습 고리 현황 (의무 절 — v10.2 · 2026-11-10)**:
- 재료 §1b(`02_Infrastructure/memory/knowledge_loop_metrics.R` — 결과 원장 · 상설 원장 · 레인 저널의 **개수 · 비율만**)를 digest 에 옮긴다: 주별 닫힌 라운드 · 사슬 · 새 탐침/이어받음 · 상설 자격 · 사전 감사 1차 통과율(논문별 첫 검사 통과/논문 수 — 재시도 뒤 통과 · 회차 소진 · 논문 키 없는 사건은 따로 · 분모 0 = NA) · 충실도 1회 통과 · 개정 근거로 안 쓴 닫힌 사슬 수. 사슬 걸음 지표(채택률 · 걸음당 개선 · 되풀이 기각)는 `02_Infrastructure/programs/rx_generator_scorecard.R` 가 정본이고 재료 §1b 에 없다 — digest 에 옮기지 않으며, 원장을 직접 세거나 추정해 채우지 않는다(없으면 '미측정'). (11-10(2) 감사 U11)
- 결과 원장은 설계 입력과 같은 규율로 읽힌다(격리 줄 · 처방 입력 검사 미통과 줄 제외 — `klm_read_outcomes` → `rc_outcomes_read(tau_clean = τ_D)`). 뺀 줄 경고가 있으면 그 건수를 그대로 옮긴다.
- 닫힌 라운드 0 · 열린 탐침만 쌓임 · 원장 손상 경고 · 뺀 줄 경고가 있으면 맨 위 1줄.

**★ 공리 사이클 · DIST 초안 — v10.2 퇴역 (2026-11-10 · `AXIOM-ENGINE-DISPOSITION-20261110`)**:
- 승격 기계(`promote` · `refine_statement` · 회로차단기)와 DIST 수명주기(`cluster_extractor` · `distilled.R` · `draft_proposed` · `approve_proposed` · `morning_steps/axiom_approval_queue.R` 노출)는 `99_Archive/axiom_engine_v10_2_20261110/` 로 보관됐다. 스위치 = `06_Registry/axiom_engine_status.json::promotion_enabled = false` — 주간 스윕은 수확(harvester)만 돌고, 증류 재료 §2 · §3 은 '퇴역' 한 줄로 바뀌며, 무인 레인은 DIST 초안을 내지 않는다(`dist_drafts` = 빈 배열 · 내더라도 apply 가 퇴역 사유로 버린다).
- 이 절의 구 절차(axiom 후보 현황 · v9.1 공리 사다리 HELD 사유 소비 · INV-6 자동초안 5체크 · pending_5axis 백로그 드레인 · supersede)는 **사료**다 — git 이력(태그 `pre-v10.2-prune-20261110` 이전 판)에 원문이 있다. 되살리는 법 = `02_Infrastructure/docs/rules/axiom-engine.md` 첫 절.

### ③ 엑기스 적립 (L-code + 메모리)

- digest 작성 중 발견한 **미적립 학습**(L-code 없는 유의미한 교훈)은 `02_Infrastructure/axiom/lcode_emit.R::emit_lcode()`로 발행 (모드별 prefix 자동, `metric_type` 정직 라벨 — proxy 결과에 backtested 금지).
- 새 L-code 발행 시 헌법 Session End 규칙 적용: `methodology_active.md` 등재 + auto-memory `MEMORY.md` 헤더 갱신 안내.
- 이미 L-code가 있는 학습은 재발행 금지 (inventory의 `new_lcodes` 목록과 대조).

### ③b 기억 inbox 검토 (주간 · 2026-09-24 P0-M1 신설 — 세션 전용)

- **왜**: 무인 레인은 이제 Claude 기억 디렉터리에 쓰지 못한다. 자동 기억은 `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` 로 꺼지고(`rf_llm_env.sh::rf_llm_agent_run` 단일 진입), 쓰기는 훅 `safety_guard.sh` Rule 3 이 막는다(`QVEST_UNATTENDED_LANE=1`). 레인이 남기려던 교훈은 `06_Registry/memory_inbox/` 에 쌓인다. 형식과 파일명은 그 디렉터리의 `README.md` 를 따른다.
- **누가**: 세션(Q)이 한다. 무인 증류 레인(`cleaner_distill_run.sh`)도 같은 차단 아래 있어 기억에 쓰지 못하므로 이 단계를 대신할 수 없다. §0.1b 사후 검토 때 함께 돈다.
- **절차**:
  1. `ls 06_Registry/memory_inbox/*.md` 로 대기 항목을 본다(`README.md` 제외). 0건이면 "inbox 0" 이라고 보고하고 넘어간다.
  2. 항목마다 셋 중 하나로 판정한다. **승격**(기억 카드로. 겹치는 카드가 있으면 병합하고 front-matter 에 `source: unattended_lane` · `inbox: <파일명>`) · **L-code**(리서치 교훈이면 L-code 가 정본) · **기각**(근거 없음·일회성·성과 수치 재방송 — 사유 1줄).
  3. 성과 수치는 권위 산출물(`authoritative_remeasure.json`)에서 다시 확인될 때만 카드에 옮긴다. inbox 의 진술은 증거가 아니다.
  4. 처리한 파일은 `06_Registry/memory_inbox/_processed/<YYYYMMDD>/` 로 옮긴다(삭제 아님). 판정과 목적지를 같은 폴더의 `verdicts.tsv` 에 한 줄씩 적는다.
  5. ⑤ 완료 보고에 `inbox 처리 n건(승격 a · L-code b · 기각 c)` 를 한 줄 넣는다.
- **기존 무인 작성 카드**: 2026-08-31~09-23 에 무인 레인이 쓴 카드 19장(09-24 전수 스캔 기준)은 front-matter 에 `source: unattended_lane` · `review: pending` 표식이 붙는다(목록 = P0-M1 산출). 표식이 있는 카드는 같은 세 갈래로 검토하고, 끝나면 `review: done(<YYYY-MM-DD>)` 로 바꾼다.

### ④ 잔재 삭제 (무아카이브 — 참조0 검증 후)

- 대상 판정: `artifact-storage.md` **§3.1**(리서치 모드 중간 산출 = 재생성 가능 스크래치) + **§4 Retention** 위반 잔재. 지식 기록이 아닌 **죽은 코드·중복·캐시만** 표적.
- **절대 보존** (어떤 삭제도 금지): `05_Production/` · `01_Literature/` · `stage_artifacts/` 내부 · `qepm/{memory,registry,mailbox}` · `qepm/research/results` · `04_Research/strategies` · `04_Research/90_legacy` · `04_Research/01_reports` · `outputs/`(canonical) · `06_Registry/` · bearish_forecast_v3 (morning_briefing 일간 소비 — 활성).
- 삭제 전 **참조 0 검증 의무**: 후보 경로를 프로젝트 전체 grep (실행코드 + config + registry json) — 참조 1건이라도 있으면 보존 + deferred 기록. 판단이 갈리면 보존.
- 통과분만 무아카이브 삭제 후 **distill manifest 기록**: `06_Registry/distill_manifest_YYYYMMDD.json` — `{deleted: [{path, reason, ref_check:"0건"}], preserved_deferred: [...]}`.

### ⑤ 마커 소거 + 완료 보고

- `.cache/cleaner_pending.json`의 `status`를 `"distilled"`로 갱신 + `distilled_at`·`digest_path` 필드 추가 (bootstrap WARN 해제 조건 = `awaiting_distill` 소거). **claim 필드(distill_status/distill_owner/distill_claimed_at)는 보존** — 덮어쓰기 금지.
- **§0.2 release 실행** (status 갱신 직후): `cleaner_release_distill("<owner>")` → `distill_status=done` + `status=distilled` 동기화. 읽기-수정-쓰기라 위 ⑤ 기록분(digest_path/distill_summary 등)은 전부 보존된다.
- 텔레그램 완료 보고: `tg_agent_brief()` (qvest-telegram SOT 준수 — 첫 섹션 한글 연구 컨텍스트. agent는 화이트리스트 내 `"Q-Lead"` 사용 — 전용 "Cleaner" 미등재). 내용: digest 경로 / 신규 L-code n건 / 삭제 n건·manifest 경로 / deferred n건 / inbox 처리 n건(③b).

---

## §2 금지·주의

- ~~**증류(digest·삭제 판단) 자동화 금지**~~ → **2026-09-05 도훈 지시로 해제**. 구 조항(2026-07-04)은 "무인 LLM 호출은 권한/판단 리스크" 를 근거로 증류를 세션에 묶었는데, 2026-08-30 "모든 작업을 무인화" 와 충돌한 채 방치되는 동안 **증류 세션이 3주 오지 않았다**(digest 마지막 2026-08-15 · `pending_5axis` 49→104건). 도훈이 무인화로 정합했고 **삭제 판단도 LLM 위임**이다. 리스크는 금지가 아니라 **경계로** 막는다:
  - 에이전트에겐 **Bash 가 없다** — 스스로 지울 수 없고 삭제 요청 JSON 만 낸다.
  - 집행 전 기계가 재도출한다: 보호목록(`06_Registry/cleaner_protected_paths.json`) · 참조0 `git grep` · 최근 24h 수정분 제외 · 건수/용량 상한. **에이전트의 `reason` 은 근거가 아니다.**
  - 검증 실패 = release 안 함 → 다음 훅이 재시도(조용한 통과 없음).
- **여전히 금지**: 퇴역한 DIST · 공리 층을 손으로 되살려 쓰는 것(보관 파일 복원 = 도훈 결정 재상정 뒤) · 증류가 `qepm/memory/axioms/**` · `06_Registry/distilled_knowledge.json` 을 고치는 것.
- **§0.2 claim 없이 증류 착수 금지** — claim `claimed=TRUE` 확인 전 digest 작성·L-code 발행·삭제 금지 (2-pass 중복실행 방지). in_progress면 병합 정합만. 무인 레인도 같은 규약을 지킨다.
- **2계층 충돌 시 손으로 밀어붙이지 말 것** — gate 가 `reinforce_active` 로 연기했다는 건 강화 러너가 원장·`stage_artifacts` 를 쓰고 있다는 뜻이다. 그 창에서 증류를 수동 실행하면 게이트를 우회하는 것이다.
- **무인 레인의 기억 쓰기 금지 (P0-M1 2026-09-24)** — 무인 증류 레인을 포함해 `QVEST_UNATTENDED_LANE=1` 레인은 기억 디렉터리에 쓰지 못한다(훅 차단). 기억 후보는 `06_Registry/memory_inbox/` 로 가고 ③b 에서 세션이 판정한다. 차단을 우회해 기억을 직접 고치게 하는 프롬프트를 레인에 넣지 말 것.
- digest에 proxy/추정 수치를 실측처럼 기재 금지 (answer-principles 회피표현 grep 대상).
- `stage_artifacts/` 내부는 인벤토리 소스일 뿐 — 어떤 파일도 이동·수정·삭제 금지 (§6 불변 런 기록).
- 커밋은 메인 세션 규율에 따름 (본 스킬이 임의 커밋하지 않음).

## 참조

- `02_Infrastructure/ops/weekly_cleaner_sweep.R` (무인 기계 스윕 — pending 생산자, schema cleaner_pending_v2)
- **`02_Infrastructure/ops/cleaner_distill_run.sh`** (무인 증류 레인 — 2026-09-05 신설. gate→claim→materials→`claude -p`(stdin)→apply→release→telegram)
- **`02_Infrastructure/ops/cleaner_distill_lib.R`** (기계 절반 — `gate`/`materials`/`apply`/`notify`. 격리 변수 `QVEST_CD_ROOT`)
- **`06_Registry/cleaner_protected_paths.json`** (절대보존 + `ref_check_ignore` + 집행 상한 — 코드가 아니라 레지스트리라 도훈이 직접 고친다)
- **`06_Registry/reinforce_auto_config.json::cleaner_distill`** (kill switch·`max_drafts`·충돌 정책) + `llm.lanes.cleaner_distill`
- **`08_Tests/ops/test_cleaner_distill.sh`** (양방향 20항 — 양성 대조 + 위반 주입 5종. `run_all_hooks.sh` SUITES 등재)
- **`06_Registry/memory_inbox/README.md`** (③b 기억 inbox 형식·처리 · P0-M1) · 차단 = `02_Infrastructure/hooks/safety_guard.sh` Rule 3 · 단일 진입 = `02_Infrastructure/ops/rf_llm_env.sh::rf_llm_agent_run` · 검사 = `08_Tests/hooks/test_safety_guard_memory.sh` · `08_Tests/ops/test_llm_single_entry.sh`
- `02_Infrastructure/ops/cleaner_claim.R` (§0.2 선점 프로토콜 — `cleaner_claim_distill`/`cleaner_release_distill`/`cleaner_distill_state`. 2-pass 중복실행 방지. owner 3종: `session_main`·`task#<id>`·`auto_distill`)
- `02_Infrastructure/ops/scheduler/Qvest_WeeklyCleaner.bat` + Task Scheduler `Qvest_WeeklyCleaner`
- `02_Infrastructure/docs/rules/artifact-storage.md` §3.1 / §4 / §8
- `02_Infrastructure/axiom/lcode_emit.R` · `.claude/skills/qvest-telegram/SKILL.md`
- `02_Infrastructure/axiom/constraint_firewall.R` (의미기반 제약 방화벽 — 재료 §4 컨텍스트 · L-code 발행 판단에 계속 쓴다) · `06_Registry/firewall_cases.json` · `02_Infrastructure/memory/knowledge_loop_metrics.R` (재료 §1b 학습 고리 계기) · 시험 `08_Tests/scenarios/test_scn_knowledge_distill.sh`
- `02_Infrastructure/docs/rules/axiom-engine.md` §0.1(메커니즘 비-ossification) + INV-7(negative=탐색지도, 제약 방화벽)
