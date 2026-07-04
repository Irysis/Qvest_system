# Negative 공리 필요성 감사 — 메타 종합 판정 (2026-07-04)

**도훈 mandate**: "negative 공리의 필요성부터 검토." 반복방지 가치는 유지하되, 그 기능이 **Law(공리, 못박음)** 에 있어야 하는가 **Distilled(failure-ledger, 재도전 품음)** 에 있어야 하는가.
**임무 S**: 메타 종합 판정관(xhigh). 5건 진단(AX-003/004/007 + AX-001 대조 + AX-005 구조확장)을 통합해 negative 공리 카테고리의 존재 이유와 계층 귀속을 판정.
**절대 규율 준수**: active/ AX JSON 의미론·강제수준 **무변경**(계층 재배치는 도훈 confirm). 수치·결론 창작 금지 — 전건 실측(파일·corpus·INV 원문) 대조.

---

## 0. 실측 검증 요약 (판정 전제 — 전부 파일 대조 완료)

| 검증 항목 | 실측 결과 | 출처 |
|---|---|---|
| AX-003/004/005/007 = polarity negative + epistemic_status provisional | 4/4 확인. `retry_trigger` 동일 문장 보유 | `active/AX-00{3,4,5,7}.json` |
| **INV-7 의무 필드 = provisional + expiry + 재도전 트리거** | 원문 확인. **네 공리 전부 `expiry` 필드 부재** (`next_review`/`review_policy`만) | `axiom-engine.md §2 INV-7` / grep 결과 0-hit |
| AX-001 = process 규칙 (채점방법) | polarity/epistemic_status **없음** + enforcement_mode **block** + 유일 hard-block hook | `active/AX-001.json` |
| AX-000 IMMUTABLE = "3~4회 실패로 dead-end 단정 금지, 모든 수단 소진까지 탐색" | 원문 확인 — negative Law와 직접 긴장 | `active/AX-000.json` |
| Distilled 소비 3배선(inject/hypothesis_index/strategic_truths) 존재 | 구현 확인 | `axiom-engine.md §3c` + 훅/R 코드 |
| **해당 domain의 negative/conditional DIST = 전부 스텁** | DIST-QPM-002/003/006·AS-002/003·AR-003 전부 `status=pending_5axis`/`quarantined_evidence`, `retry_condition=None`, `statement_refined=None` | distilled/*.json 실측 |
| inject는 `status=distilled`만 소비(INV-6) | 훅 line 88-93 `if e.get('status')=='distilled'` — 스텁 **전부 skip** | `axiom_context_inject.sh` |
| **founding 실패 L-code는 corpus 계층에서 이미 LIVE** | L-132/133/134/135/139/140/160/165/166 전부 `lcode_corpus.json` 존재, grade F(166=anti-pattern) → hypothesis_index **FAIL/KILL** 반환 (distilled 무관) | `lcode_corpus.json` + `hypothesis_index.R §b 계층` |

**핵심 발견 (판정을 뒤흔드는 사실)**: 반복방지의 **검색(search) 기능은 Law-계층 거주에도 Distilled 정제에도 의존하지 않는다.** founding L-code가 corpus 4계층에 이미 인덱싱돼 `/worktask create` 시 FAIL/KILL을 반환한다. Law에서 내려도, DIST가 스텁이어도, 검색 반복방지는 **오늘 이미 작동 중**이다. Distilled가 추가하는 유일한 것은 `retry_policy`(INV-7 provisional '재시도 조건') 라벨 + 실시간 주입이다.

---

## 1. category_verdict — negative 공리 카테고리 존치 여부

### 판정: **CONDITIONAL_KEEP — 카테고리는 유지하되 계층을 재배치한다.**

negative 지식의 *반복방지 가치*는 카테고리로서 **실재한다**(존치). 그러나 그 가치의 *실행 주체*는 Law가 아니라 **Distilled failure-ledger + corpus 검색 계층**이다. 따라서:

- **negative 지식 = Distilled failure-ledger 소속이 정본.** INV-7이 이미 이렇게 정의한다("negative = provisional failure-ledger, 불변 법칙 아님"). 어제 3층 재설계가 만든 ②Distilled 소비층(inject/hypothesis_index retry_policy/strategic_truths)이 반복방지 3기능의 설계상 홈이다.
- **Law-계층 negative는 예외적으로만 정당** — (a) enforcement가 실효 hard-block이고 (b) INV-7 provisional 필드를 완비하며 (c) AX-000과 정합할 때. 5건 중 **AX-001만** 이 조건을 만족한다(단 AX-001은 순수 negative가 아니라 process 규칙).
- **순수 empirical negative(AX-003/004/005/007)를 Law에 못박는 것은 3중 모순**: ① INV-7 expiry 필드 부재로 "잠정 실패기록"이 "불변 법칙"처럼 읽힘 ② AX-000(dead-end 단정 금지)과 정면 충돌 ③ 반복방지 실행 주체가 이미 Distilled/corpus인데 Law authority는 심리적 위신뿐(advisory/documented라 실차단 0).

**근거 요지**: negative 카테고리를 폐기하면 반복방지 손실(진짜 손해), Law에 존치하면 AX-000·INV-7 위반 + 기능 중복. 정합해가 **"카테고리 유지 + Distilled 귀속 + Law는 process 예외만"**.

---

## 2. per_axiom — 5건 verdict · necessity

| 공리 | 성격 | verdict | necessity | 1-line |
|---|---|---|---|---|
| **AX-001** | process (채점방법) | **KEEP_LAW_PROCESS** | 8.5 | negative 아닌 측정 프로토콜 — 유일 실효 hard-block(07-03 실작동), Distilled 부적격. v2.1 amendment 레거시-창 라벨만 부가. |
| **AX-003** | empirical negative (value) | **DEMOTE_TO_DISTILLED** | 7 | 반복방지 가치 HIGH(value 재시도 최다)·advisory라 Law 실차단 0. 자연 트리거(spread reversion) 명확 — Distilled retry_condition 이관이 AX-000 정합 완성. |
| **AX-004** | empirical negative (quality) | **KEEP_LAW_PROCESS (조건부)** → 재검토 시 DEMOTE 후보 | 7 | 클래스 재확인으로 N=3 갭 보강 + 실시간 주입 자산. **단 KEEP의 전제 = expiry 명시 + recert 산식 3건(B2/B3/B4) 정정** — 미정정이면 증거로 재승격 영구봉쇄 역설. 산식 미정정 시 DEMOTE가 정합. |
| **AX-005** | empirical negative (defense) | **DEMOTE_TO_DISTILLED** | 6.5 | 구조상 003과 동형(N=2·advisory·provisional·expiry 부재). 07-03 방어 DB 전수로 재확증 강하나 그 재확증분이 곧 Distilled 증거층 — Law 못박을 이유 없음. **주의: 본 임무 진단 payload에 005 전용 진단 미포함, 구조 실측 기반 확장 판정.** |
| **AX-007** | empirical negative (single-sleeve) | **DEMOTE_TO_DISTILLED** | 3.5 | 실 재시도 0·N=3·External real n=0/3·recert 0.683<0.8·documented(실차단 0). EXCLUSION 4종 라이브 book 상시행사 = death-sentence 아닌 우회로. Law 잔존 근거 = 거버넌스 관성뿐. |

### 판정 상세

**AX-001 (necessity 8.5 · KEEP_LAW_PROCESS)** — 유일한 진짜 process. `polarity`/`epistemic_status` 부재가 결정적 증거: "전략 X 실패"를 못박는 게 아니라 "방어팩터를 전기간 SR로 채점하지 말라"는 *측정 잣대*를 강제한다. AX-002(하네스내 성과)·AX-008(triangulation) 계열. Distilled로 내리면 07-03에 실제 작동한 hard-block을 잃고 채점오류가 매 방어 리서치마다 재발. Law 잔존이 도훈 프레임의 대조군 그대로. 유일 오염 = v2.1 meta_allocation amendment(레거시-창 단일 WT, evidence_audit '경미') → 레거시-창 라벨 부가(의미론 무변경).

**AX-003 (necessity 7 · DEMOTE)** — 반복방지 가치는 최상급(value = corpus 최다 재시도 방향). 그러나 enforcement가 이미 advisory(warn-only)라 Law 강등 시 **실질 강제력 손실 0**. 오히려 검색 반복방지는 Distilled가 더 강하다(worktask create lookup 의무 = INV-7 차별점 명시 없인 진행 차단). 자연 재도전 트리거(`reference-kr-value-factor-decay`: KR value spread 사상최대·reversion 미검증)가 명확해 Distilled retry_condition으로 이관하면 AX-000 정합이 완성된다. active JSON에 이미 `retry_trigger` 존재 — 이 필드를 Distilled로 옮기는 것이 재배치의 실체.

**AX-004 (necessity 7 · KEEP 조건부)** — 유일하게 KEEP 우세이나 **조건부**. KEEP 근거: (i) 클래스 재확인(07-03 방어 DB·ML 증류·16/16 admission FAIL·07-04 backtested 3건)으로 개별 N=3 갭이 메워짐 (ii) 실시간 AX-code prefix 주입(`_shared_prefix.md`, sot_map line 155 발화 실측)이 128 quality 가설 재시도를 사전 경고 (iii) advisory라 Law 잔존이 AX-000 탐색을 실차단 안 함. **그러나 KEEP은 2건 보정을 전제**: ① `expiry` 명시(현재 `next_review`만 = INV-7 부분 미준수) ② recert의 negative-polarity 산식 3건(B2 win/loss 재정의·B3 median≥0.5 극성반전·B4 essence_grade 오집계) 정정 — 미정정 시 **backtested 증거가 강할수록 재승격 점수가 낮아지는 역설(0.92→0.84)** 이 지속돼 "증거로 Law 자격 입증" 경로가 영구 봉쇄된다. **산식 미정정이면 KEEP의 정당성이 소멸 → DEMOTE로 전환이 정합.** 즉 AX-004는 "Law에 두되 작동하는 provisional로 만들거나, 아니면 내려라"의 갈림길.

**AX-005 (necessity 6.5 · DEMOTE · ★진단 payload 부재 경고)** — 본 임무 진단 데이터는 AX-003/004/007 + AX-001만 제공, **AX-005 전용 진단 미포함**. 그러나 구조 실측상 003과 동형이다: polarity negative·provisional·advisory·N=2(L-136/140)·`expiry` 부재·founding L-code(L-140 등) corpus 라이브. 07-03 방어팩터 DB 170종 전수가 재확증을 강하게 제공하나(evidence_audit SOUND_REVERIFIED), **그 재확증분 자체가 Distilled 증거 결집이지 Law 못박기 근거가 아니다**. AX-005 canonical엔 이미 "AX-001에 따라 조건부 평가, scope 밖" 우회로가 명문화 = provisional 정신 내재. DEMOTE 정합. **단 005는 003/004/007과 달리 독립 5건-진단을 거치지 않았으므로, confirm 전 별도 정밀 recert 권고**(다른 3건과 동일 프로토콜: polarity-aware 산식 + External oos_retention real 재측정).

**AX-007 (necessity 3.5 · DEMOTE · 최강 후보)** — 5건 중 강등 근거가 가장 두껍다. (a) 정확 scope의 실 재시도 이력 ≈ 0(유일 근접 gapfreq는 AR-mode cross-mode라 scope 밖에서 독립 KILL — AX-007이 막은 게 아님) (b) External real oos n=0/3, L-166 grade=null (c) recert weighted 0.683<0.8 FAIL_INSUFFICIENT_EVIDENCE (d) enforcement documented = 실차단 0건(훅 로그 0). EXCLUSION 4종이 명문 재도전 트리거로 이미 존재하고 라이브 book(STR_1715 multi-sleeve)이 EXCLUSION-1을 상시 행사 = 예외가 death-sentence 아닌 우회로로 실작동. Law 잔존의 유일 실질가치 = **거버넌스 관성**(도훈 8-axiom 의미론 보존 mandate) → 즉시 강등 금지, confirm 경유 필수.

---

## 3. architecture_recommendation — negative → Distilled 재배치 구체 설계

**설계 원칙**: 반복방지 3기능(주입·검색·retry_policy)을 **강화하며** 이관한다. Law authority 상실은 심리적일 뿐(advisory/documented는 실차단 0), 기능은 Distilled+corpus가 더 강하게 담당한다.

### 3.1 반복방지 3배선 보존 방식 (기능별)

| 기능 | 현재(Law-negative) | 재배치 후(Distilled) | 보존/강화 |
|---|---|---|---|
| **검색** | corpus 계층이 이미 founding L-code FAIL/KILL 반환 (Law 무관) | 동일 + DIST 정제 시 `DISTILLED_NEG`/`DISTILLED_COND` verdict 추가 | **강화** — worktask create lookup 차별점 명시 의무(INV-7) |
| **주입** | AX-code prefix가 Lv0로 실시간 주입(AX-004 실측 발화) | inject가 distilled top-5(≤2500자)로 주입 — **status=distilled 필요** | **조건부 강화** — 정제 완료 전엔 축소(실시간→lookup 1회). ★이것이 유일한 순손실, 정제 선행으로 해소 |
| **retry_policy** | active JSON `retry_trigger` 문자열(주입 안 됨) | DIST `retry_condition` → hypothesis_index lookup에 표출 | **신설** — 재도전 조건이 실제 소비층에 노출 |

### 3.2 재도전 트리거 의무화 (INV-7 완전 정합)

각 공리의 `retry_trigger`를 Distilled `retry_condition`으로 이관 + **`expiry` 명시**(INV-7 의무 필드, 현재 4건 전부 부재):

- **AX-003 → DIST-QPM-006 retry_condition**: "value spread reversion 발현(1급) OR 새 construction(비-EP/비-accrual value proxy) OR ML sizing OR multi-sleeve 편입 OR regime-conditional value." expiry = next_review(2026-07-16)를 명시적 expiry로 승격.
- **AX-004 → DIST-QPM-003 retry_condition**: EXCLUSION 4경로와 1:1 매핑 — ① 전통 quality composite(GP+F+O+Q07 3축) ② quality overlay in blend(QMJ+value) ③ ML sizing 재조합 ④ DART 현금흐름 품질 개선 시 cash-based 재시도.
- **AX-005 → DIST-QPM-002 retry_condition**: "신규 방어 데이터원 출현 OR multi-sleeve 내 defense sleeve 실측(EXCLUSION) OR long-short 허용 시 BAB 재도전."
- **AX-007 → DIST-QPM-002/AR-003 retry_condition**: EXCLUSION 4종(multi-sleeve/long-short/50+/ML sizing) + "single-sleeve top20 backtested 재측정으로 real oos_retention 발행(측정 자체가 재도전)."

### 3.3 AX-001 예외 처리

AX-001은 **재배치 대상 아님(KEEP_LAW_PROCESS)**. process 규칙(채점 잣대)이라 Distilled failure-ledger(전략 재도전 관리) 기능과 이질적이다. Distilled로 내리면 (i) 유일 실효 hard-block 상실 (ii) "방어팩터 자체가 재도전 대상"이라는 잘못된 시그널(실제 재도전 대상은 채점방법 재보정이지 방어팩터 아님). Law 잔존 + block 유지 + v2.1 레거시-창 라벨 부가가 최적. **negative 카테고리 재배치가 AX-001을 건드리지 않도록 process/negative 구분을 재배치 규약에 명문화**(polarity 필드 유무가 기계적 판별자: 부재=process=Law, negative=failure-ledger=Distilled).

### 3.4 기존 주입 payload 변화

- **재배치 전(현재)**: `_shared_prefix.md` agent-prefix가 AX-003/004/005/007 canonical_statement를 Lv0 공리로 주입 + advisory/documented 훅. inject는 active 공리 + distilled(현재 스텁이라 skip).
- **재배치 후**: agent-prefix에서 4건 제거(active/에서 Distilled로 이동). inject가 정제 완료된 DIST-QPM-002/003/006(+AR-003)의 `statement_refined`를 distilled top-5로 주입(≤2500자). corpus 검색 계층은 무변경(founding L-code 계속 FAIL/KILL). 순변화 = "Lv0 공리 4줄 → distilled negative 라인(retry_policy 포함)"으로 라벨 격하 + 재도전 조건 노출 추가.

### 3.5 실행 순서 (★필수 — 순서 위반 시 지식 공백)

```
1. /cleaner 세션: DIST-QPM-002/003/006 (+AR-003) 정제
   pending_5axis/quarantined → distilled
   (statement_refined 작성 + retry_condition 이관 + expiry 명시)
   ※ INV-6: 무인 정제 금지 — /cleaner 세션 전담
2. 정제 검증: inject가 distilled top-5 실주입 확인 + hypothesis_index DISTILLED_NEG/retry_policy 표출 확인
3. 도훈 confirm: category 재배치 + per-axiom verdict 승인
4. active/ AX-003/005/007 DEMOTE (AX-004는 산식 정정 후 별도 판단)
   ※ 절대규율: confirm 전 active JSON 무변경
```

**순서의 이유**: Distilled 스텁 상태에서 Law를 먼저 내리면 실시간 주입은 사라지는데 distilled 주입은 아직 skip(INV-6) → **주입 반복방지 공백**(검색은 corpus로 살아있으나 주입은 빈다). Distilled 정제 선행 → confirm → DEMOTE가 무공백 경로.

---

## 4. confirm_queue — 도훈 결정사항

1. **[category] negative 공리 카테고리 = CONDITIONAL_KEEP** 승인 여부 — 카테고리 유지 + Distilled 귀속 + Law는 process 예외(AX-001)만.
2. **[AX-003] DEMOTE_TO_DISTILLED** 승인 여부 — retry_trigger를 DIST-QPM-006 retry_condition으로 이관, expiry 명시. (선행: DIST-QPM-006 정제)
3. **[AX-004] KEEP_LAW_PROCESS vs DEMOTE 분기 결정** — KEEP 채택 시 **필수 2건 정정 동반**: (a) expiry 필드 추가 (b) recert 산식 3건(B2/B3/B4) 정정. 산식 미정정이면 DEMOTE가 정합(증거-역설 봉쇄 지속).
4. **[AX-005] DEMOTE_TO_DISTILLED (진단 payload 부재) 승인 + 별도 정밀 recert 발주 여부** — 003/004/007과 동일 프로토콜(polarity-aware 산식 + External oos real 재측정) 선행 권고.
5. **[AX-007] DEMOTE_TO_DISTILLED** 승인 여부 — 강등 근거 최강, 유일 잔류가치=거버넌스 관성. DIST-QPM-002/AR-003 재클러스터(L-166 graded-F same-lineage 편입).
6. **[AX-001] KEEP_LAW_PROCESS + block 유지 + v2.1 레거시-창 라벨** 승인 — 의미론 무변경, 라벨만 부가.
7. **[재배치 규약] process/negative 기계적 판별자 = `polarity` 필드 유무** 명문화 승인 — negative 재배치가 AX-001류 process를 건드리지 않도록.
8. **[INV-7 완전준수] active/ 잔류·이관 무관 4건 전부 `expiry` 필드 추가** — 현재 부재는 INV-7 부분 위반. (의미론 무변경, 메타 필드 추가)
9. **[실행순서] /cleaner 정제 선행 → confirm → DEMOTE** 순서 승인 — 주입 공백 방지.

---

## 5. cold_take

negative 공리는 **필요하다 — 단 Law에서가 아니라 Distilled에서.**

반복방지 가치는 진짜다(value·quality·defense는 corpus 최다 재시도 방향, trap 라벨 레버리지 실재). 그러나 그 가치를 Law에 못박은 것은 **어제 3층을 만들기 전의 아키텍처 화석**이다. 오늘 실측은 세 가지를 확정한다:

1. **반복방지 검색은 이미 Law와 무관하게 작동한다.** founding 실패 L-code 9건 전부 corpus에 살아 FAIL/KILL을 반환한다. Law의 advisory/documented는 실차단 0 — Law authority는 위신뿐이다.
2. **Law-negative는 AX-000과 INV-7을 동시에 위반한다.** AX-000(immutable)이 "3~4회로 dead-end 단정 금지"를 명령하는데, `expiry` 없는 negative Law는 "구조적 실패"(AX-004/007 canonical 문구)를 불변으로 읽히게 한다. N=2~3 증거로 Law를 못박는 것은 시스템 최상위 공리를 배반한다.
3. **Distilled가 더 강한 반복방지를 제공한다** — 단 지금은 비어있다. DIST-QPM-002/003/006이 전부 `pending_5axis` 스텁이라 소비층이 배선만 되고 채워지지 않았다. 이것이 진짜 갭이다: Law를 내려서가 아니라 **Distilled를 채워서** 반복방지를 완성해야 한다.

유일한 예외는 **AX-001**이다. 이건 negative가 아니라 process(채점 잣대)이고 유일하게 실효 hard-block이며 07-03에 실제로 나(Q)를 막았다. polarity 필드 유무가 이 구분을 기계적으로 가른다 — 부재면 Law, negative면 Distilled.

**AX-004가 시금석이다.** recert가 드러낸 역설 — backtested negative 증거를 넣을수록 재승격 점수가 낮아진다(0.92→0.84) — 는 산식이 positive 논리를 negative에 적용한 구조결함이다. 이걸 고치지 않으면 "증거로 Law 자격 입증"이 영구 봉쇄돼 provisional 라벨이 죽은 문자가 된다. AX-004는 "작동하는 provisional로 만들거나, 내려라"의 갈림길에 있고, 산식을 못 고치면 답은 자명하다.

**한 줄로**: negative 공리를 폐기하지 말라(반복방지 손실), Law에 두지도 말라(AX-000·INV-7 위반). Distilled를 채우고, expiry를 붙이고, AX-004 산식을 고치고, AX-001만 Law에 남겨라.

---

**감사 규율 준수 확인**: active/ AX JSON 무변경(계층 재배치는 confirm 대기) · 수치·결론 창작 없음(전건 파일·corpus·INV 원문 실측) · bare python 미사용(venv 경유) · Rscript -e 한글 미사용 · 커밋 없음.
