# Axiom 엔진 설계 전수점검 — 2026-08-22

**질문**: 현 Axiom 엔진 설계가 선언대로 구현되고 운영에서 발화하는가.
**방법**: 3층 대조 — **선언**(SOT 문서) vs **구현**(코드) vs **운영**(산출물·실측). 6표면 병렬 판독 → 발견 적대검증(반증 시도) → 완결성 비판.
**규모**: 16 agent · 403 tool call · 1.66M token · **63 설계요소 / 48 발견 / 55 정상확인**.
**대상 루트**: `C:/Users/99922/OneDrive/Quant_Module_Moltbot` (메인 트리, 워크트리 사본 제외).
**성격**: 읽기 전용 감사. 단 §7에 감사 실행이 유발한 상태 변경을 명시 기록한다.

---

## 0. 한 문장

**적립(Ledger)은 건강하고, 증류(Distilled)는 돌지만 정정이 전파되지 않으며, 법(Law)은 얼어 있는데 그 동결의 대부분은 설계 의도다** — 그리고 이번에 처음 드러난 가장 깊은 결함은 엔진이 아니라 **엔진을 검사하는 배터리가 생산 원장을 오염시킨다**는 것이다.

---

## 1. 3층 대조 요약

| 층 | 선언 | 구현 | 운영 | 판정 |
|---|---|---|---|---|
| **① Ledger (L-code)** | corpus→2인덱스 환류 | emit·schema·harvester 정합 3축 확인 | corpus 508 = hypothesis_index 508 = knowledge_index 508 **3자 일치** | **OK** |
| **② Distilled (DIST)** | negative=탐색지도, 도훈 승인 후 활성 | `distilled.R` 필터·동기화 실재 | 카드 153 · distilled 15 · proposed 10 대기 · 부활 7건 발화 | **OK (정정 전파 결손)** |
| **③ Law (AX)** | 5축 AND → mode-local/global | `promote.R`·`promote_global.R` 실재 | **mode-local 승격 0건(엔진 가동 이래) · global 승격 0건(07-04 이후)** | **동결 — 대부분 설계 의도** |

### 강제·주입 계층

| 구간 | 상태 | 근거 |
|---|---|---|
| ⑤ 훅 자동주입 | **BROKEN (확정)** | subagent 도달 **0/1004** — 독립 재측정, 양성 대조 통과 |
| ⑨ 카드 되먹임 | **완료** | `close_round.R:198-201` 고정 4키 → FQ 4건 실기록 |
| ⑪ 재탕방지 벌점 | **입력 고갈** | `s3_orthogonality` 54건 전부 mtime ≤ 06-08, legacy 명명 |
| ⑫ 조회의무 강제 | **완료** | `alpha_hypothesis.json` 15건 중 **14건**이 `prechecks` 보유 |
| ③ mode-local 승격 | **산출 0** | `active/modes/` 4디렉터리 전부 빈 상태 |

---

## 2. 검증된 발견 9건 (적대검증 통과)

### CONFIRMED 2건

**`INJ-2` ⑤ 훅 자동주입이 subagent 에 도달하지 않는다** *(major)*
독립 재측정: 훅 고유 문자열이 메인 트랜스크립트에 `hook_additional_context` 로 **172회** 부착(전건 `isSidechain:false`), subagent 트랜스크립트 1,004건의 spawn 프롬프트 도달 **0/1004**. 양성 대조(프롬프트-탑재 AX 텍스트 7건)는 같은 측정기가 검출 — **검사 사망 아님**. 등록 구조는 08-16 이후는 물론 **2026-07-25(`d304d5cb6`) 이후 무변경**, 사용자 스코프·`settings.local` 에 대체 훅 0.
▸ 부수: 에이전트 정의 **10개**가 `_shared_prefix.md ... (모든 agent autoload)` 라 표기 — 실제 전달 형태(의무 pull)와 어긋난다.

**`HLT-4` 배터리 복구 코드가 발화하지 않는 dead code** *(major)*
`08_Tests/hooks/test_revival_flags_sync.R:42` 의 최상위 `on.exit(...)` = **r-portability 금칙② 위반**(baseline 67건에 없는 novel). `restore()`/`unlink(BK)` 는 이 `on.exit` 안이 유일 호출 site 이고 배터리는 별도 `Rscript` 프로세스라 source 프레임 구제도 없다. **물증**: `unlink` 대상 `.cache/_test_frf_sync_backup.json`(9,620B) 이 지금도 잔존.

### PARTIAL 7건 (사실이나 범위/심각도 교정)

**`HLT-1` 배터리가 라이브 지식 조회면을 오염시킨다** *(critical→major)*
`08_Tests/ops/test_hypothesis_index_paper_lane.R` 의 T5 가 형제 검사 8종이 모두 `tempdir()` 픽스처를 쓰는 것과 달리 **혼자 실 `06_Registry/method_registry.json` 에 가짜 method(`ZZ_PROBE_PAPER_LANE`)를 주입**하고, `HI_INDEX_PATH` 가 `QM_ROOT` 로 고정돼 **워크트리에서 돌려도 메인트리 라이브 인덱스를 재작성**한다.
▸ **교정**: "복구 후에도 잔류"는 **반증** — 복구는 `tryCatch` 밖 최상위라 무조건 실행되고 자가치유가 확인됐다. 현재 라이브 3원장 모두 `ZZ_PROBE` **0건**(감사 종료 시 재확인).
▸ ★그러나 **일시 오염이 소비됐다**: 같은 배터리의 **후속 3개 스위트**가 그 가짜 method 를 실물 등재 항목으로 소비했다(`test_risk_lane_verdict`·`test_nearest_arm_axis`·Σ 어댑터).

**`HLT-2` T5b 실패는 flake 가 아니라 참양성** *(critical→major)*
원 주장("배터리에서만 FAIL = 공유 상태 신호")은 **loop1·loop2 양쪽 FAIL** 실측으로 반증. 진상은 더 나쁘다 — **배터리 시작 시점에 생산 파일이 이미 `ZZ_PROBE` 로 오염돼 있었고**(T2 실측 17건 vs HEAD 16건), 스위트가 되돌린 `orig` 가 그 오염본이라 T5b 가 정확히 검거했다.
▸ 실제 결함 = "배터리에서만 깨지는 검사"가 아니라 **검사가 생산 레지스트리를 PID 격리·락·크래시 안전 복원 없이 in-place 변조한다**는 것.

**`LAW-1` INV-7 은 코드 갭이 아니라 정본 내부 모순** *(major→minor)* ★프레이밍 교정
`promote.R` 이 negative 후보에 positive 용 축을 적용하는 것은 사실(`:91` independence min 3 → negative 45/45 적용, `:205` `.axis_external` polarity 분기 **0건** → negative 44/45 FAIL).
▸ **그러나 "코드가 문서를 못 따라갔다"는 프레이밍은 부정확**: 같은 문서 **§3의 5축 표가 `promote.R` 을 명시 지목하며 "negative ≥ 3"을 그대로 규정**하고, 07-04 이후 changelog 3건이 "5축 hurdle 수치 불변"을 재확인하며, `CLAUDE.md:111` 도 구판 문언을 싣고 있다. **§2 ↔ §3 + CLAUDE.md 의 미해소 모순**이므로 선행 조치는 코드 수정이 아니라 **어느 절이 권위인지에 대한 도훈 판정**이다.
▸ 08-16 감사의 *"polarity 분기 0건"* 도 부정확 — 분기는 실재하나 전부 **구판(06-05) 의미론**이다(`HLT-10` 과 일치).

**`INJ-1` 철회된 수치가 주입면 2위 카드에 살아 있다** *(major 유지)*
`DIST-RAMP-006`(인용 14 = usage 2위, `refined_at` **2026-07-18**)이 08-20 동월 look-ahead 재기준선으로 원장에서 **명시 무효화(SUSPENDED)** 된 `pt_capwt 7.72`·`oos 0.54밴드 3/3` 을 *"졸업 수준 도달 유일 경로"* 로 계속 서술. 08-20 stale 4장 재정제에서 누락. **무효화가 DIST 계층에 전혀 전파되지 않음**(`distilled_knowledge.json` 내 SUSPENDED/동월/look-ahead/FQ-239 각 0건).
▸ **교정**: `_shared_prefix.md:205` 는 7.72 를 **서빙하지 않는다** — `<distilled_map>` 이 statement 를 334자에서 절단하고 런타임 훅도 `[:110]` 절단. **주입 노출은 제한적이나 카드 자체는 낙후**.

**`LEDGER-1` knowledge_index 세션-중 자동 재빌드 부재** *(major→minor)*
사실이나 **미발견 구조결함이 아니라 08-20 에 비용까지 측정하고(전체 빌드 0.222s) 채택한 선언된 설계 결정**. 배선도 bootstrap 단일이 아니다 — `bootstrap.sh:1067` + `weekly_cleaner_sweep.R:493-508`(주간 자동) + `--repair` opt-in + WARN_10 검출기. 없는 것은 **repair 의 자동 호출**뿐. 남은 실갭 = 08-20 노트가 "별건"으로 미룬 **소비면 5종 자가치유 미배선**.

**`DIST-1` MonthlyDistill 은 '사망'이 아니라 월간 1회 결측** *(major→minor)*
스케줄러 사실은 전건 재현(rc=3221225786, last_run 08-01, age 20.2일, next 09-01). **그러나 원인은 스크립트 결함이 아니라 08-01 15:46 전후 173초 창에서 작업 5개가 동시 강제종료된 머신 단위 사건 1회**이고, 작업은 `Ready`·`enabled`·`start_when_available=true` 로 남아 있다.
▸ **"8월 axiom 엔진 정지"는 절반이 사실과 다르다** — candidate 승격 스캔은 8월에 **주간 단위로 정상 실동**(AX-PENDING 08-02 78 · 08-08 82 · 08-15 93 · 08-21 95건).

**`HLT-3` 배터리의 Distilled 원장 재작성** *(major→minor)*
`refine_distilled()` 실호출로 실카드 1장(`DIST-AR-001`)을 쓰고 파생 인덱스를 전량 재작성하는 것은 사실. **그러나** ①인덱스는 카드 153장에서 결정적으로 재생성되는 **파생 조회면**이고 git 추적되므로 "복구 경로 없음"은 미성립 ②인용된 증거(`n_entries` 148→153)는 **배터리 소행이 아니라** `cluster_extractor.py` 가 08-21 07:41~08:10 에 만든 카드 5장을 인덱스가 따라잡은 것.

---

## 3. 미검증 발견 27건 (검증 상한 초과 — 실측 근거는 있으나 반증 시도 미실시)

**major 7건**

| id | 요지 |
|---|---|
| `HLT-5` | `SUITES` 중복 등재 2건 → 141 suite 를 **143회** 실행, FINAL 2636 중 **44 pass 이중계상**. 편입 검사기는 고유화 후 세므로 원리적으로 못 봄 |
| `HLT-6` | 편입 드리프트 검사기 **운영 소비자 0** — 현재 실드리프트 2건이 어떤 자동 경로에도 안 나타남 |
| `HLT-7` | Axiom 엔진 자체 테스트 4건이 편입 검사기 **모집단(`08_Tests/`) 밖** — '미편입 0' 이 나와도 영원히 안 세어짐 |
| `HLT-8` | Axiom 소스 8종 배터리 무커버 — **`constraint_firewall.R`(INV-7 정본)·`lcode_emit.R`(발행 정본) 포함** |
| `HLT-9` | 구간 ③ 자격 후보 5건 대기 중인데 **승격 실행 자체가 어떤 스케줄에도 없음** |
| `HLT-10` | INV-7 은 부분 구현 — **최대 차단축 External 이 polarity 를 전혀 안 봄**(88/94 로 1위 차단축) |
| `HLT-11` | MonthlyDistill 재기동 경로 부재(헬스는 `failed_known` 재출현만) |

**minor 20건** — `LAW-2`(SOT §5 자기모순) · `LAW-3`(AX-008 에 `Opus 4.8` 하드코딩 = 모델 단일출처 위반) · `LAW-4`(sot_map 깨진 참조 1) · `LAW-5`(e2e check7 낙후 기대값 `active>=8` vs 실측 4) · `LAW-6`(confirm_flags 18건 6~7주 미소비) · `LEDGER-2`(harvester 사각 3건 — **검사기가 생산자와 같은 glob 을 써 원리적으로 못 잡음**) · `LEDGER-3`(부트 harvester 배경실행에 `wait` 부재) · `DIST-2`/`INJ-6`(usage 랭킹 생산자 운영 호출자 0) · `DIST-3`(배터리 2종이 운영 정본 in-place 조작) · `ENF-1`(훅 총량 선언 46 vs 실측 **47**) · `ENF-2`(`research_continuity_guard.sh:4` 슬래시 치환 오타 — latent) · `ENF-3`(⑫ 발화 관측성 0) · `INJ-3`(`_shared_prefix` C4 = 폐기된 '연간→5월') · `INJ-4`(모델 정책 4번째 낙후 지점) · `INJ-5`(FRONTIER_AXES 마커 워크트리 미전파) · `HLT-12`(배선 지도 axiom 미포함) · `HLT-13`(헬스 헤더 6+6 vs 구현 7+11) · `HLT-14`(WARN_9 발화 — negative 4/11 next_probe 부재) · `HLT-17`(AuditWatch ALERT 본문이 `failed_known` 에 접혀 소실)

**info 12건** — `HLT-15`(**'13구간' 정의문이 저장소 어디에도 없음** — 번호는 코드 주석 5곳에만) · `HLT-16`(내 어제 L-code 의 `s3 고유 8건` 은 루트 한정, 전수는 **54건** — 결론 불변) · `INJ-7`·`INJ-8`·`LEDGER-4~7`·`DIST-4` 등

---

## 4. 정상 확인 (양방향 보고 — 55건 중 핵심)

- **지식 환류 3자 일치 유지**: corpus 508 = hypothesis_index 508 = knowledge_index 508. 어제 501 에서 7건 증가했으나 **세 원장이 함께 이동**. 고유 ID 508 · 미수확 0 · ID 충돌 0
- **헬스 HARD 게이트 7/7 PASS**, hard fail 0. WARN_10 이 **mtime 대리지표가 아니라 내용 대조**(`content_match`)로 판정
- **08-20 수리 10종 전부 오늘 재현** — 합계 **189 pass / 0 fail**
- **배터리 완주** 2636 pass / 2 fail / 2638 total, `UNREPORTED` **0건**(요약 JSON 미발행이 초록으로 위장하던 구 결함 미재발)
- **⑫ 가 산출물에 실도달**: `alpha_hypothesis.json` 15건 중 14건 `prechecks` 보유(결측 1건은 06-08 legacy), 08-21 신규 2건 hits=7·hits=5
- **⑨ 되먹임 지속**: 배선 다음날에도 FQ 4건에 4키 기록
- **PUSH 랭킹 08-16 수리 유지**: top-5 사용합계 **57**, 최다인용 `DIST-QPM-003`(19) 1위
- **INV-6 무인 활성화 0건**: proposed 10건이 사람 게이트에서 정지, 주입 3면 전부 `status=distilled` 필터 확인
- **INV-7 부활 발화 실동작**: 16 dists 중 7건 발화(4카드 × 서로 다른 signal_id)
- **강등 4건 → DIST 이관 완결** 4/4 실재
- **AX-001 차단 실효 재현**: 단일행·다중행 pretty JSON 둘 다 block
- **주간 정규 파이프라인 7주 연속 가동**: AX-PENDING 35→38→47→88→78→82→93→95

---

## 5. 완결성 비판 — 미감사 표면 18건

감사자 자신이 지적한 사각. **가장 중요한 3건**:

1. **`cluster_extractor.py`(55,872B)** — 루프의 **유일한 candidate 생성기**이자 매주 실제 실행되는 코드인데 6표면 어디서도 미판독. 특히 `supersede→expired` 로직이 **증거를 삭제할 수 있는 축**
2. **텔레그램 전달면** — `axiom_weekly_report.R:67` 이 `tg_agent_brief.R` 을 source 하는데 **그 파일이 저장소에 부재**(함수 실체는 `telegram_notify.R`)이고 `if(file.exists())` 안이라 **무음 skip** → INV-3 human-review 전달의 마지막 구간이 미측정
3. **`dogfood_reclassify.R`** — 호출자 0건이면서 **07-05 강등된 AX-003/004/005/007 을 `active/` 에서 patch 하도록 작성**돼 있고 루트 폴백이 낡은 `G:/` — 실행되면 강등 결정을 되돌리는 위험 스크립트

**교차검증 결손 3건**: candidate 모집단이 세 곳에서 다르게 세어짐(96 vs 93 vs 91) · research_mode enum 이 코퍼스 11종 vs schema 9종 vs `promote.R` 8종 · 주입 대상 파일 목록 정본 미확정(9 prompts vs 6 prompts vs 3 legacy 마커)

**증거 약한 주장 10건** — `INV-3[yes]` 는 docstring 근거뿐(실행 증거 0) · `HLT-12` 는 '전무'가 아니라 '19소스 중 4' 로 교정 필요 등

---

## 6. 결론 — 병목

### 엔진은 돈다. 그러나 **세 개의 서로 다른 종류의 정지**가 있다.

| 종류 | 실체 | 처분 |
|---|---|---|
| **설계된 정지** | Law 승격 0 = INV-6(사람 게이트) + INV-7(negative 는 Law 표적 아님) | **정상 — 고칠 것 없음** |
| **모순에 의한 정지** | INV-7 이 §2 ↔ §3 + CLAUDE.md 로 갈려 있어 코드가 어느 쪽도 배신하지 않은 채 negative 44건을 막음 | **도훈 판정 필요** — 코드 수정 아님 |
| **결함에 의한 정지** | ⑤ subagent 도달 0/1004 · 배터리의 생산 원장 오염 · 정정 전파 결손 | **수리 대상** |

### 가장 깊은 발견은 엔진 밖에 있었다

**검사 하네스가 생산 원장을 변조한다.** 그리고 이번 실행에서 **그 오염이 실제로 3개 후속 스위트에 소비됐다**. 이 저장소가 08-20 에 확립한 규율 — *"검사기는 검출력·설치·호출자 오염 내성 셋이 다 서야 산다"* — 에 **네 번째 조건이 붙는다: 격리**.

▸ 같은 뿌리로 `HLT-4`(복구가 dead code)·`DIST-3`(2종이 정본 in-place 조작)·`HLT-2`(오염이 다음 회차 배터리의 시작 상태가 됨)가 한 다발이다.

### '13구간'은 정의된 적이 없다

`HLT-15`: 내가 지난 세션들에서 인용해 온 **"루프 13구간"의 정의문이 저장소 어디에도 없다** — 08-16 보고서는 **"6구간"**이라 적었고 해당 감사는 "미수신"으로 종료됐다. 번호는 코드 주석 5곳에만 살아 있고 `⑬` 문자는 저장소 전수 **0건**. **즉 나는 정의를 조회할 수 없는 좌표계로 진척을 보고해 왔다.**

---

## 7. 이 감사가 유발한 상태 변경 (명시 기록)

지시받은 배터리 실행이 라이브 원장을 변경했다. 감사자 직접 쓰기는 `.cache/_audit21_*` 한정.

| 대상 | 변경 | 현재 |
|---|---|---|
| `06_Registry/method_registry.json` | `ZZ_PROBE` 0→1→2→0 요동 | **HEAD 와 동일 복원** |
| `06_Registry/hypothesis_index.json` | `PL_ZZ_PROBE_PAPER_LANE` 주입 | **자가치유 — `ZZ_PROBE` 0건 재확인** |
| `06_Registry/distilled_knowledge.json` | 148→153, `DIST-AR-055` 신설 | **`cluster_extractor` 소행 — 배터리 아님** |
| `.cache/_test_frf_sync_backup.json` | 잔존 9,620B | **`HLT-4` dead-code 물증 — 미삭제 유지** |

---

## 8. 다음 (도훈 결정 대기 / 자율 가능)

**도훈 결정 필요 3건**
1. **INV-7 권위 판정** — `axiom-engine.md` §2(재정의) vs §3(5축 표) + `CLAUDE.md:111` 중 무엇이 정본인가. 이것이 정해지기 전 `promote.R` 수정은 어느 쪽 배신인지 알 수 없다
2. `confirm_flags` 18건 (`within_condition_axis` 재정의) — 6~7주 미소비
3. DIST `proposed` 10건 배치 승인

**자율 수리 가능 (알파 라운드 비차단)**
- **P0** 배터리 격리 계약 — 생산 원장 변조 금지 + `HLT-4` on.exit 수리 + `HLT-2` 오염 시작상태 차단
- **P1** `INJ-1` `DIST-RAMP-006` 재정제(철회 수치 제거) + 원장 무효화 → DIST 전파 경로 신설
- **P2** `HLT-5` SUITES 중복 제거 · `HLT-6` 편입 검사기 배선 · `ENF-1` 훅 총량 47 갱신
- **P3** 미감사 18표면 중 `cluster_extractor.py`·텔레그램 전달면·`dogfood_reclassify.R` 판독

**⑤(subagent 도달)은 하네스 층 제약**이라 저장소 내 수리 대상이 아니다 — 현행 대체 경로는 에이전트 정의의 **의무 pull** 이고, 그렇다면 10개 정의의 `autoload` 표기를 정직 표기로 바꾸는 것이 실질 조치다.

---

# 부록 A — P0/P1 수리 실행 (2026-08-22, 같은 세션)

감사 §8의 "자율 수리 가능" 항목 중 **측정 신뢰를 훼손하는 결함**(헌법 자원배분 규칙의 즉시수리 대상)만 실행했다. Lane D 착수·INV-7 권위 판정은 도훈 결정이라 손대지 않았다.

## A.1 실행 내역

| 항목 | 조치 | 검증 |
|---|---|---|
| **P0-a** 검사 격리 | `test_hypothesis_index_paper_lane` T4/T5 를 임시 루트로 격리 + `lookup_hypothesis(root=)` 이음매 신설 | **17/17**, 생산 2원장 md5 불변, 주입 3축 검거 |
| **P0-b** dead cleanup | `test_revival_flags_sync:42` 최상위 `on.exit` → `reg.finalizer(globalenv(), onexit=TRUE)` + 백업 범위를 실카드까지 | `r_portability` **21/1 → 22/0**, 카드 md5 불변, 백업 잔재 소멸 |
| **P0-b'** provenance 복원 | `DIST-AR-001.refined_by` 를 git 이력 추적으로 원값(`null` / `2026-07-04`) 복원 | 재실행 후에도 유지 |
| **P0-c** 계통 가드 | 러너에 `REGISTRY_DIRTY`/`REGISTRY_ADVISORY` 신설 | 주입 5축 검거 · 대조군 무발화 |
| **HLT-5** 중복 등재 | SUITES 중복 2행 제거 | **143 → 141 고유** |
| **P1** 철회 전파 | `DIST-RAMP-006` 재정제 — `pt 7.72` 를 철회 서술 안으로 | 카드·인덱스·주입면 3면 정합 |

배터리: **2593 pass / 스위트 실패 0** (구 2636/2 — 중복 44 이중계상 제거 반영). 오염 피해자였던 `paper_intake_resolvers` 도 6/2 → **8/0**.

## A.2 감사가 놓친 축 — git 이력 오염 (병렬 세션 발견의 확장)

병렬 세션(`claude/nifty-lalande-ad9186`)이 `method_registry` 5건을 발견했고, 본 세션이 전수 스캔으로 **`hypothesis_index.json` 3건을 추가 확인**했다.

| 파일 | 오염 커밋 | 창 |
|---|---|---|
| `method_registry.json` | 5 | 08-20 20:38~21:47 |
| `hypothesis_index.json` | 3 (`4982e9e0f`·`cc4b25f02`·`843713696`) | **08-16 16:30**~08-20 21:48 |
| `distilled_knowledge.json` | 0 | — |

**최초 오염이 08-16 으로 병렬 세션이 본 창보다 나흘 이르다** — 한 사람이 본 창이 전수가 아니었다. 현재 HEAD·워킹은 청정.

## A.3 병렬 세션 설계가 두 축에서 우월 — 흡수함

1. **`md5` 만으론 눈이 먼다**: 백업→변형→**완전복원**은 바이트가 같아 내용 검사가 전부 초록인데 중간 상태는 이미 노출됐다(=실제 사고 경로, A.2 의 8커밋). ⇒ 가드에 **mtime 축** 추가. 위반 주입에서 v1 이 놓쳤을 자리를 v2 가 검거.
2. **정본마다 정당한 변경빈도가 다르다**: `hypothesis_index`·`knowledge_index`·`distilled_knowledge` 는 남의 세션이 상시 재빌드하므로 바이트 동치를 걸면 **정당한 작업에 빨개진다**. ⇒ **STRICT / ADVISORY 2단 정책**. (실증: 1차 배터리에서 `test_revival_flags_sync` 가 카드는 복원하고도 파생 인덱스 `generated_at` 만으로 걸렸다.)

병합은 도훈 결정이라 그쪽 브랜치는 그대로 두었다. `test_hypothesis_index_paper_lane.R` 은 양쪽이 각각 고쳤으므로 **병합 시 충돌**한다.

## A.4 자기정정 4건 (전부 무효한 하네스가 만든 오판)

1. **"T5d 는 검출력이 없다"** — `~/.Renviron` 이 `QM_ROOT` 를 pin 해 셸 export 를 R **시작 시점에** 덮어쓰므로 주입 하네스가 격리되지 않았다. 조작이 검사 표면에 도달한 적이 없었다. `R_ENVIRON_USER=/dev/null` 후 재측정 → **정상 검거**.
2. **FAIL 줄 누락** — `chk()` 가 `ok` 는 공백 3칸 · `FAIL` 은 1칸으로 출력하는데 grep 앵커를 3칸으로 잡아 FAIL 을 통째로 걸렀다.
3. **내 가드가 삭제축에 fail-open** — `sed 's/^> //p'` 로 추가 줄만 집어, 삭제 시 지문은 달라지는데 목록이 비어 계상 0. 위반 주입 C 에서 검출.
4. **가드 함수 추출 누락** — 검증용 추출이 첫 `}` 에서 끊겨 `_reg_fp_strict` 가 없었고, **모든 strict 결과가 빈 `[]` 로 나와 "대조군 통과"로 읽힐 뻔했다**. 지문 행수 선행검증(`0 이면 무효`)을 상설로 넣었다.

## A.5 부수 정정 — `dogfood_reclassify.R` 은 위험 스크립트가 아니다

완결성 비판이 *"실행되면 07-05 강등 결정을 되돌리는 위험 스크립트"* 로 분류했으나, 실측하면 **표적 4건(`AX-003/004/005/007`)이 `active/` 에 전부 부재**이고 `.patch()` 는 `if (!file.exists(p)) skip` 가드를 갖는다 — 파일을 **생성하지 않는다**. 루트 폴백 `G:/Quant_Module_Moltbot` 도 부재 경로라 같은 결과다.

⇒ 정확한 서술은 **"표적이 사라진 일회성 마이그레이션 스크립트, 실행하면 4건 전부 skip 하는 no-op"**. 위험은 아니고 **정리 대상**이다(r-portability 금칙③ 스테일 루트 보유).

## A.6 남은 것

- **도훈 결정 3건 불변**: INV-7 권위(§2 vs §3) · `confirm_flags` 18건 · DIST proposed 10건
- **미검증 27건 중 major 6건** (`HLT-6`~`HLT-11`) 은 적대검증 미실시 — 실측 근거는 있으나 반증 시도가 없다
- **미감사 18표면** 중 `cluster_extractor.py`(유일한 candidate 생성기)·텔레그램 전달면(부재 파일 source 후 무음 skip)이 최우선
- **`test_hypothesis_index_paper_lane.R` 병합 충돌** 예정

## A.7 미검증 발견 후속 판독 (부록 작성 중 추가 실측)

**`HLT-9` 반증 — ③ 은 배선 부재가 아니다.**
주장: *"구간 ③ 승격 실행 자체가 어떤 스케줄에도 없다"*. 실측: `02_Infrastructure/ops/weekly_cleaner_sweep.R:461-480` 이 candidate 마다 `promote.R` 을 **실제 자식 프로세스로 호출**한다(`system2("Rscript", c(promote_r, cand))`). 이름이 "promote 진단"이라 진단처럼 읽히지만 실 승격 경로이고, 5축을 통과하면 `active/modes/` 에 기록된다. 스케줄은 `Qvest_WeeklyCleaner`(최근 08-15, rc 0).
⇒ **③ 의 산출 0 은 배선 결손이 아니라 게이트가 닫혀 있는 것**이고, 그 게이트의 negative 분기를 지배하는 것이 `LAW-1` 의 INV-7 §2↔§3 모순이다. **HLT-9 는 독립 결함이 아니라 LAW-1 의 표현형**으로 병합한다.

**`HLT-6` 확정 + 악화** — 편입 검사기 소비자는 러너의 **주석 한 줄**(`run_all_hooks.sh:246`)뿐이고 실호출 0. 드리프트는 감사 시점 2건 → 현재 **4건**(`test_mode_queue_research_run` · `test_morning_run_live_pid_guard` · `test_paper_router_backlog_axis` · `test_scheduler_alert_surface`). 별도 태스크로 분리(`task_2ffc89c0`).

**텔레그램 전달면 (미감사 표면) 확정 — 단 휴면.**
`axiom_weekly_report.R:67` 이 `02_Infrastructure/telegram/tg_agent_brief.R` 을 가리키는데 **그 파일은 부재**하고(함수 실체는 `telegram_notify.R`), 68행 `if (file.exists(tg))` 가 **무음 skip** 한다. 즉 INV-3 human-review 전달 leg 는 활성화해도 아무 일도 일어나지 않는다. 다만 `axiom_weekly.sh:39` 가 `--telegram` 을 **`QVEST_AXIOM_TELEGRAM` 설정 시에만** 넘기고 그 env 는 현재 unset ⇒ **휴면 상태의 침묵 실패**. 수리는 1줄(`telegram_notify.R` 로 교체) + 부재 시 loud 처리.

**`dogfood_reclassify.R` — 위험 아님 (A.5 참조).**

**`Qvest_RAMP_AutoLoop` — 결함 아님.** rc=3221225786·last_run 06-20(62일) 이라 침묵 사망처럼 보였으나 `state=Disabled`·`enabled=False` 로 **의도적 비활성**이고, 헬스가 비활성 작업을 `failed_known` 에서 제외한 것은 정상 동작이다. RAMP 오토루프가 06-20 이후 꺼져 있다는 **사실만** 도훈 확인 사항.
▸ ★본 세션에서 "원장이 무엇을 담기로 선언했는지 먼저 읽어라" 계통의 오판이 **3회**(candidates pending / MonthlyDistill '사망' / RAMP AutoLoop) — 개수는 매번 맞고 해석이 틀렸다.

**`constraint_firewall.R` — 설치는 됐고 학습이 멈췄다.**
소비자 실재 **5곳**(`cluster_extractor.py`·`distilled.R`·`lcode_emit.R`·`close_round.R` + 스킬 문서)이라 '미설치'는 아니다. 그러나 배터리 커버 **0**이고 자기발전 원장 `06_Registry/firewall_cases.json` 이 **2026-07-04 에 15건으로 동결**(전건 `added_at=2026-07`, 7주간 append 0). "위반이 없었다"인지 "학습 경로가 끊겼다"인지는 읽기만으로 못 가른다 — **next_probe: 의도적 위반을 주입해 케이스가 append 되는지 관측**.
