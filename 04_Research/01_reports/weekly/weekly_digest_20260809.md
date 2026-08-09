# Weekly Digest — 2026-W32 (2026-08-02 ~ 08-08)

**작성**: 2026-08-09 (Q-Lead, `/cleaner` 증류 세션 · owner=`session_main`)
**기계 스윕**: 2026-08-08 09:00~09:02:32, 13 steps 전건 OK, `n_fail_steps=0`, `dry_run=false`, 삭제 3건
**출처**: `.cache/cleaner_pending.json`(schema `cleaner_pending_v2`) + `.cache/lcode_corpus.json` + 각 런 아티팩트
**수치 규약**: 아래 수치는 전부 해당 런의 기록 파일 인용. `metric_type` 병기 — 라벨 없는 "backtested" 주장 없음.

---

## 0. 주간 볼륨 (실측)

| 항목 | 값 | 출처 |
|---|---|---|
| stage_artifacts 신규 | 853 | `inventory.stage_artifacts_new.n` |
| 신규 L-code | 45 | `inventory.new_lcodes.n` |
| hypothesis_index | 1,103 → 1,143 (**+40**) | `inventory.hypothesis_index` |
| 커밋(7일) | 773 | `inventory.git_log_7d.n_commits` |
| 스윕 삭제 | 3 | `sweep_deleted_n` |

---

## 1. 알파 리서치 — 실험별 결론

### ★ 양성 1건 — MAX5 제외-필터 (유일한 소비 가능 결과)
`L-AR-20260802_204801` · grade B · `metric_type=canonical_screen` · family=overlay_regime

복권형(MAX5 상위 10%) 유니버스 **제외-필터**. bare(WT-014) 기준:
- **ΔIR +0.1692** (admission 기준 0.05의 **3.4배**)
- PORT_t **2.879 → 3.620**
- absMDD **−0.5587 → −0.4443** (11.4pp 개선)
- 회전 증가 없음 (13.81 → 13.54)
- 발동률 0.957

overlay 결합 실배치 관문까지 통과. **이번 주 유일한 양성 소비면.**

### 기전 규명 — 다팩터 합성이 지는 이유 확정
`L-AR-20260802_214000` · grade B · `metric_type=canonical_screen` (FQ-116, WT-004/009/015 승계 3회 정합 현상의 규명 라운드)

지배 기전 = **M1 slot 잠식**. EW5 합성 top-25는 단일 최강(M01_PATHQ) top-25와 **overlap 4.4/25**뿐이고 월 **20.6 slot**이 교체된다. 밀어 넣은(IN) 종목을 advocate 팩터로 귀속하면 전이-음성 팩터가 최강 팩터의 자리를 빼앗는 구조.

### 자격의 시간구조 3부작 — era는 실재하나 사전 관측 불가
`L-WT20260803_005 / _006 / _007` · 전부 grade F · `metric_type=canonical_screen`

- **005**: 285팩터 × 비중첩 3격자. 자격 부호의 **달력 반감기 부재** — 비절단 sign-run 중앙값 = 1창(3격자 전부). 기하 중앙값은 창 단위 2.26/2.39/2.20으로 격자 무관 동일한데 개월 환산은 136/86/53으로 창 길이에 비례 ⇒ 실제 감쇠 시간상수 부재.
- **006**: era 실재 확증(pool 285 무작위 반분 시 월간 breadth 상관 **0.9858**)이나 **t 시점 정보만으로 사전 추정 불가**.
- **007**: 질문을 "언제 통하나"→"어느 era에서도 덜 죽나"로 전환. era-demean 후 minimax, walk-forward 7 step(OOS 24월 블록, 167월) — 실패.

### config-scoped negative
| 라운드 | L-code | 핵심 수치 | metric_type |
|---|---|---|---|
| 최적수송 W1 횡단면 (FQ-097) | `L-AR-20260802_134402` | 구현 정리-수준 **9/9 PASS**(barycenter 오차 4e-16)인데 primary OT_W1_RTAIL_63 cap-w PORT_t **−1.236** / EW-uni **−2.053** → MECHANISM_REFUTED | canonical_screen |
| 경로 시그니처 3M 평활판 (NP-2) | `L-AR-20260802_134403` | 회전 관문 달성(연 **10.53** ≤ 11.0, base 15.78 대비 −33%)하나 수익 신호 소멸: PORT_t **+1.225 → −0.268**(보존율 −0.219) | canonical_screen |
| 스마트베타 5종 튜닝 | `L-AR-20260802_134401` | **1/5 조건부 통과**. Momentum 경로효율 **+2.028**(문턱 2.0) / Value 섹터內 재표준화 −0.774 / LowVol EWMA-63d −1.737 / Quality EB수축 +1.136 | canonical_screen |
| M01_PATHQ 순수판 | `L-AR-20260802_204802` | RESID paired NW t **+1.717 < 2.0** → registry 교체안 철회. parity 검증으로 하네스 동질성 확인(재측정 +2.028 = 기록 정확 일치) | canonical_screen |
| 튜닝 5팩터 국면 로테이션 | `L-AR-20260802_204803` | 튜닝 로테이션 PORT_t **0.904 < base** — 차별점 D1 실측 반증 | canonical_screen |
| FQ-115 unified 국면 라벨 | `L-AR-20260802_203709` | book carrier 269m paired NW3 t **−1.85** | canonical_screen (weighted) |
| FQ-118 실현-하락 nowcast | `L-AR-20260802_210201` | settled negative (g=0.40 이진, n_trials=1 no-sweep) | canonical_screen (weighted) |

### 소비면 특성화 (등급 없음 — 진단)
- `L-AR-20260802_213556` (FQ-112): MAX5의 **위험-축** 증분 실재 — 252d 표준 위험축 통제 후 종목-레벨 crash 발생률 FM NW t **+13.15**, top-decile 2.11배(21.4% vs 10.1%), 십분위 단조 3.9%→21.6%, 절대문턱(−20%) 강건 t +8.43.
- `L-MF-20260803_FQ108`: 단기 꼬리-변동성(D35)의 위험-축 소비 = **증분 없음**. 사전등록 PRIMARY(실 book total-분산 × lw_nls, n=173) QLIKE 개선 DM t **+0.724** — 사전 기록한 정직 posterior가 적중(lw_nls가 이미 흡수).
- `L-RAMP-20260802_204804`: insider INS_MAGQ3 보조 tripwire 증분 **기각/UNDERPOWERED**(MID habitat t_inc +0.821, 97개월). 커버리지는 +24.0%(SAFE 종목-월 3,553→4,407) 늘었으나 분리력 미동반. **부수 성과 = 더 큰 관측가능성 결함(R43-F1) 적발·수리.**

### alpha-search (proxy 등급, 자본 자격 없음)
- **재측정으로 뒤집힌 3건** — CTR_MAG12 계열은 proxy 등급 A/C였으나 `metric_type=backtested` 실측재측정에서 **essence F, PORT_t(NW) −0.57 ~ −0.81**. 등급 A(`L-AS-20260802_213430`)조차 PORT_t 음수.
- `L-AS-20260802_115851` FQ081_DuPont: proxy C이나 **canonical cap-w PORT_t −0.413** — "근접 탈락" 문구는 proxy heuristic이며 자본 자격 없음(자동 생성 문구 주의).
- `L-AS-20260802_025436`: 07-27 QUARANTINE 2건을 canonical로 재측정 — 4-arm 전부 문턱 2.95 미달(최대 1.048), 보유 86~96%가 OTHER(시총 31위+).
- 나머지 F 다수(JumpShare A/B, RetAutoCorr, VolRank 계열, FX 계열, Spectral) — 전부 `metric_type=proxy`.

**주간 총평**: 자본 게이트 통과 0건. 소비 가능한 양성은 MAX5 제외-필터 1건(필터 소비면), 나머지는 기전 규명·negative 확정. **"직교 ≠ 수익"과 전이 벽이 이번 주에도 재확인**됐다.

---

## 2. Axiom 후보 현황 (스윕 step 3.5 실측)

`n_candidates_total = 82` / `n_pending = 82` / `n_promote_crash = 0` / `promote_failures = []`

**실패 축 히스토그램** — 어느 축이 승격을 막는가:

| 축 | 미달 후보 수 |
|---|---|
| external | **77** |
| independence | **76** |
| falsification | 66 |
| mechanism | 39 |
| rigor | 3 |

★ 병목은 `rigor`(3건)가 아니라 **external(77) · independence(76)** — 즉 후보의 엄밀성이 아니라 **외부 확증·독립성 축의 입력 결손**이 승격을 막는다. 이는 개별 후보를 다듬어 풀 문제가 아니라 **emit 지점(해당 축 필드 생산)** 보강 대상이다.

**near-miss 3건** (1축만 미달 — 정제 시 승격 후보):

| candidate | 미달 축 | weighted_score |
|---|---|---|
| `CAND_20260808_alpha_research_infra_process_mixed_...` | independence | **0.97** |
| `CAND_20260714_alpha_research_distress_smallcap_wall_...` | external | 0.80 |
| `CAND_20260718_qepm_legacy_value_conditional_L-132_L-135_L-142` | falsification | 0.774 |

**도훈 confirm 대기 18건** (`confirm_flags`): 전부 동일 항목 — *conditional `direction_consistency` 재정의(`within_condition_axis`) 적용*. 후보별 개별 판단이 아니라 **규칙 1건 승인이 18건을 동시에 푸는 구조**.

**L-code 무결성**: `clean` — 464 entries / 464 unique / **collision 0**.

---

## 3. ★ 백로그 — 악화 중 (조치 필요)

| 항목 | 2026-07-17 실측 | 2026-08-09 실측 | 변화 |
|---|---|---|---|
| `pending_5axis` | 49건 | **92건** | **+88%** |
| 최고령 | 2026-07-08 | 2026-07-08 (**32일 정체**, `DIST-AR-005`) | 불변 |
| `quarantined_evidence` | 6건 (07-04~) | **6건 (36일 정체)** | 불변 |
| `proposed` | — | **0건** | — |

스윕 기록(`axiom_candidates.pending_5axis.n = 86`, 08-08 09:00)과 현재 실측 92건 사이에 하루 만에 +6.

★ **`proposed = 0`이 핵심 신호**다. INV-6 흐름은 `pending_5axis → [세션 자동초안] → proposed → [도훈 승인] → distilled`인데, 중간 단계 산출이 0이다. 즉 **초안 생산이 백로그 증가 속도를 전혀 따라가지 못하고 있다**(distilled 15 / expired 25 — 과거엔 흘렀다). 07-17 mandate가 "세션당 최소 5건+"를 정한 이유가 이것인데, 그 이후 3주간 잔량이 오히려 배로 늘었다.

**드레인 우선순위 (supporting L-code 수 상위)** — 다음 세션 착수 지점:

| dist_id | n_supporting | family / mode | polarity |
|---|---|---|---|
| `DIST-RAMP-018` | **46** | mixed / ramp | conditional |
| `DIST-RAMP-014` | 31 | value / ramp | conditional |
| `DIST-QPM-023` | 19 | defense / qepm_legacy | conditional |
| `DIST-QPM-035` | 19 | quality_earnings / qepm_legacy | conditional |
| `DIST-AR-041` | 17 | momentum / alpha_research | negative |

(≥5건 supporting = 25개 후보 존재. max 46.)

**본 세션 처리량 = 0건** — 정직 보고. 이번 세션은 증류 중 발견한 **지식 손실 결함 수리**(§4)에 시간을 썼고, 초안 5건+는 착수하지 못했다. 이월 사유를 남긴다(07-17 mandate가 금지한 "사유 없는 이월"이 되지 않도록): 손실 결함은 **적립 경로 자체가 새는 문제**여서 초안 생산보다 선행 순위가 높다고 판단했다 — 새는 파이프에 더 부어도 같은 비율로 샌다.

---

## 4. ★ 증류 중 발견·수리 — L-code 지식 손실 (이번 주 4건)

**증상**: 이번 주 발행 L-code 45건 중 **4건의 `lesson_text`가 공란**으로 수확됨. corpus 전체 483건 중 공란은 5건뿐이었으므로 **이번 주가 그 4/5**를 차지 — 신규·악화 결함.

**기전**: 아티팩트에는 내용이 **있었다**. `lcode_harvester.py`의 `_LEGACY_FIELD_MAP`이 `lesson_text ← (lesson, text, description)` 고정 목록인데, 신세대 emitter는 본문을 **`finding`**(3세대) / **`findings`**(4세대, 게다가 dict)에 쓴다. 매칭 실패 시 **오류가 아니라 빈 문자열**이 되므로 L-code는 45건으로 정상 계상되고 **지식만 사라진다** — corpus → `knowledge_index` → 주입면까지 공란이 전파돼 검색·회수 불가.

★ **같은 결함의 3번째 재발**이다. 해당 코드의 주석이 2026-07-25에 동일 유형("종전 harvester는 신 필드명만 읽어 구스키마를 lesson_text=''로 만들었다")을 수리했다고 기록하고 있다. **고정 alias 목록은 emitter 스키마가 바뀔 때마다 같은 구멍을 다시 연다.**

**수리** (`02_Infrastructure/axiom/lcode_harvester.py`):
1. alias 확장 — `finding` / `findings` 추가. 선택 근거는 **데이터 실측**(canonical 키가 빈 아티팩트 10건 중 본문 보유 키: finding 6 / mechanism 6 / title 8 → 의미상 lesson의 직접 대응물 = finding).
2. `_coerce_text()` — dict/list 본문을 읽을 수 있는 문자열로 평탄화(`findings`가 dict인 사례).
3. ★**근본 방어 `_warn_empty_lesson()`** — 공란이 나오면 **어느 파일의 어느 키에 본문이 있는지**까지 stderr에 찍는다. alias를 늘리는 것으로는 다음 변형을 못 막으므로, 조용한 손실을 **소리나는 손실**로 바꾼다.

**검증 (양방향)**:
- 회수: corpus 공란 **5 → 1**, `knowledge_index.json` gist 공란 **5 → 1**. 회수 4건 = `L-AS-20260808-FQ110` / `L-AS-20260808-Hurst` / `L-WT_D20260803_008_FQ125_CONTRACT_REGIME_CONDITIONAL` / `L-AR-20260804_FQ004_P1`.
- 음성 대조: **기존 non-empty `lesson_text` 변경 0건**, corpus 건수 불변(483 → 483), 신규 진입 0.
- 가드 실증: 남은 1건(`L-AR-20260718_103500`)에 대해 경고가 정확한 힌트(`본문 후보 키: hypothesis`)와 함께 발화, 나머지 482건은 침묵(항진명제 아님).

**회수된 지식 예시** (이제 검색 가능):
- `L-AS-20260808-FQ110`: JumpShare_12M direction A가 **역효과(IC = −0.028)**. frog-in-the-pan 기전 존재하나 방향 반대.
- `L-WT_D20260803_008` (FQ-125): 2019-12~2026-06 79 IC월 — 평균 rank-IC **+0.0565**, t_NW(lag3) **+1.994**, ICIR 0.234, 양수월 59.5%.
- `L-AR-20260804_FQ004_P1`: K200∪KQ150에서 DART 포렌식 재료는 **sparsity 벽**으로 측정 불가 — 재료별 월평균 발생 AdminStock 1.4 / UnfaithfulDisc 1.3 / TradingHalt 1.7 종목.

---

## 5. 다음 라운드 (next_probe)

1. **`pending_5axis` 드레인 착수** — `DIST-RAMP-018`(46) 부터 상위 5건. 07-17 mandate 이후 3주 연속 미이행이므로 다음 세션 **최우선**.
2. **승격 병목의 emit 지점 보강** — 실패 축이 external 77 / independence 76에 몰려 있다. 후보 정제가 아니라 **그 두 축의 입력을 emit 단계에서 생산**하도록 배선 조사.
3. **`confirm_flags` 18건 일괄 처리** — 단일 규칙(`within_condition_axis` 재정의) 승인 1건이 18후보를 동시에 푼다. 도훈 confirm 대상.
4. **MAX5 제외-필터 후속** — 이번 주 유일 양성. overlay 결합 실배치 관문 통과분의 book-marginal 재확인.
5. **emitter 스키마 정본화** — L-code 아티팩트가 4세대(`lesson`/`lesson_text`/`finding`/`findings`)로 갈라져 있다. 수확기 방어는 넣었으나 **생산 측 정본이 없다**(오늘 AST 노드 형태에서 고친 것과 동형 문제).

**부활 조건**: `quarantined_evidence` 6건은 07-04 증거계보 감사 TAINTED 이후 36일 정체 — 초안 대상 제외는 불변이나, **증거 재검이 가능해지는 시점**(계보 재구축 또는 원 아티팩트 확인)에 재개.

---

## 참조
- 원장: `.cache/cleaner_pending.json` (week_of 2026-W32) · `06_Registry/distilled_knowledge.json` · `.cache/lcode_corpus.json`
- 규칙: `02_Infrastructure/docs/rules/artifact-storage.md` §3.1/§4/§8 · `.claude/skills/cleaner/SKILL.md`
- 수리 파일: `02_Infrastructure/axiom/lcode_harvester.py`
