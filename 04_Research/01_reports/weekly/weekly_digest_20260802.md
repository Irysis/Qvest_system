# Weekly Digest — 2026-W31 (07-27 ~ 08-02)

**작성**: 2026-08-02 · **owner**: session_main (claim 2026-08-02 14:00)
**소스**: `.cache/cleaner_pending.json` (W31, dry_run=**FALSE**, sweep_deleted_n=1) + 각 라운드 `alpha_validation.json` 실측 인용
**직전**: `weekly_digest_20260726.md` (W30 지연 증류, 같은 날 완결)

---

## §1 이 주의 리서치 (전량 실측 인용, metric_type 병기)

주간 규모: stage_artifacts 신규 **522** · hypothesis_index 1103(+138) · 커밋 **532** · 신규 L-code 16.
사실상 **08-02 하루가 이 주의 대부분** — 밤샘 라운드 + 오전~오후 연속 라운드.

### 1-1. QEPM 정식 라운드 (alpha_validation 실측, 전부 `metric_type=canonical_screen`)

| WT | 주제 | 판정 | 핵심 실측 |
|---|---|---|---|
| 004 | 변동성 팩터 조합(방어 배향) | config-scoped negative | 조합 crisis_alpha −5.26%/월(t −1.26) < 단일 최선(D55 −2.88). 저변동 수준축 3종 CS Spearman 0.91~0.97 = 사실상 동일 축. **bad월 IC가 전기간보다 더 음수(−0.108~−0.139) = '저변동=방어' 직관 불성립** |
| 005 | quarantine·skip 재고 회수 | capability_established | 25건 4분류: merit 19 / structural 4 / capability 5 / miscored 0. **회수 1호 IN03_RD_to_Market** cap-w 2.537·EW-uni 3.610 — 유실 기전 = `STANDALONE_TRACK` 소비자 코드 0건(배관 결함, 칩 분리) |
| 006 | 경로 시그니처 | config-scoped negative | cap-w 1.225·EW-uni 1.926·회전 15.78(상한 초과)·lag1 붕괴 0.237. 기전 flow 링크 t **+4.08** SUPPORTED |
| 007 | insider commitment magnitude | config-scoped negative(capital tier) | cap-w 1.371 / EW-uni **−0.788**(EW가 더 약함 = 소형주 광역 프리미엄에 흡수). FQ-079 시퀀스는 R33 breadth와 **DUPLICATE_AXIS** 자체 기각 |
| 009 | 스마트베타 5종 수리 튜닝 | capability_established | paired: Value −0.774 / **Momentum 경로효율 +2.028** / LowVol −1.737 / Quality +1.136 / Dividend −1.364. ★반증 검정 4/5 지지인데 수익 1/5 통과 = **순도≠수익**(base 수익 원천이 구조 베팅). 상관 0.209→0.145 |
| 010 | 최적수송 W1 횡단면 | config-scoped negative + 기전 반증 | cap-w −1.236 / EW-uni −2.053(양 기각). 노이즈 바닥 0.167 ≈ 실측 편차 0.156 = 형상은 표본 잡음. 스칼라 MAX5 IC-t 4.41 > W1 3.57. 기전 **부호 역전 t −7.27** |
| 011 | 시그니처 3M 평활 | config-scoped negative + 신규 분해 | 회전 관문 달성(10.53≤11.0)이나 cap-w **−0.268**(보존율 −0.219). ★**flow 링크는 무손실**(t +4.09, 보존율 1.005) = 수익축 고빈도·flow축 저빈도 **스펙트럼 분해** |
| 013 | PATHQ vol-잔차 순수판 | config-scoped negative + 방법론 실증 | paired **+1.717 < 2.0** → 교체안 미상정. vol 적재 −0.060(혐의와 다름). ★★**멤버십-섭동 placebo 5시드 {1.866~2.796} sd 0.378** = 원판 +2.028은 문턱 근방 단일 draw |
| 014 | 복권형 제외-필터 | **capability_established (첫 양성 소비면)** | **ΔIR +0.1692**(기준 0.05의 3.4배)·PORT_t 2.879→**3.620**·**MDD −55.9%→−44.4%**·회전 증가 없음. 발동률 95.7%·기전 개인 순매수 t **+3.90**. caveat: paired t 1.565(p≈0.12)·lag1 소멸(fast-decay)·CRISIS Δ 음수 |
| 012 | insider INS_MAGQ3 보조 tripwire (monitoring) | 증분 기각 + **★관측가능성 결함 적발** | 증분 t_inc **0.821** UNDERPOWERED(SAFE 종목-월 +24.0%인데 관측 행은 +0.3% = 더 관대한 선별). 확장의 41.8%가 MEGA_TOP30(저신뢰), REST 증분 평평(−0.21) → WIRE-2 기각. ★**R43-F1: 253개월 중 126개월(49.8%) 구조적 침묵** — INS02가 [−1,1] 유계라 최대 z가 문턱 1.0 도달 불가(침묵월 중앙값 0.862). 배선 당일 현 북 max_z **0.9123** = "SAFE 0"이 자격자 부재가 아니라 측정 침묵이었음 |
| 015 | 튜닝 5팩터 국면-조건부 로테이션 (도훈 지시) | 재탕 이하 | 튜닝 로테이션 **0.904** < base 로테이션 **1.403**, paired **−1.224** = 튜닝 입력이 로테이션을 악화(차별점 D1 반증). ★**단일 최강 M01_PATHQ 2.050이 전 조합 지배**(EW 정적 0.338, paired vs single −1.265) = 섞는 것 자체가 손실. post-2017 EW-uni −0.869·oos −0.407. PIT 규율 모범(assert PASS + 위반 주입 발화 실증 + 오염 진단 arm 0.762). CRISIS 25개월 active **+4.98%**만 양(+) |

**08-02 밤 추가 (digest 초판 14:05 이후 완결분)**: WT-012·015를 위 표에 소급 추가했다. 이후 3트랙(WT-016 필터×overlay / WT-017 국면→overlay / WT-018 계약수주 magnitude 파일럿)은 W32 소관.

**주간 통합 지식 — 소비 경로가 판정을 바꾼다**: 같은 날 **세 사례**가 나왔다. ① WT-011: 시그니처의 수익축은 죽고(보존율 −0.219) flow축은 무손실(1.005) → 소비면은 monitoring. ② WT-014: WT-010에서 랭킹으로 죽은 MAX5가 **필터로는 산다**(ΔIR +0.169). 필터는 랭킹이 아니라 후보집합 축소라 전이-벽 기전을 우회한다. ③ WT-015: 국면 라벨이 배분으로는 손실인데 CRISIS active만 +4.98% → overlay 소비면 미검(FQ-115). → **재료 기각 전 소비면 7종 순회 의무**(연속성 4호)가 형식이 아니라 EV의 원천임이 이 주에 실증됐다. 갭 귀속도 이동했다: 벽이 "재료가 부족하다"보다 **"소비 경로가 재료를 못 받는다"** 쪽 — `layer_bottleneck_map.md` 갭 귀속 재판정 절 참조.

### 1-2. alpha-search (07-27, 08-02 — `metric_type=proxy` 다수)

07-27 큐 2건(hill_tail_index·vol_adj_volume_surprise) QUARANTINE, 08-02 라운드에서 dual-basis canonical 재측정. 08-02 신규 L-code 6건(L-AS-20260802_*)이 이 lane. ⚠ proxy 라벨 건은 graduation 근거 불가.

### 1-3. 인프라 (이 주 구조 변경)

- **AST v1.1 사이드카 사망 수리**: 생존자 경로 배선으로 8일간 실전 캡처 0 → `canonical_screen_bt` 기각분 경유 지점에 배선. `live_with_ast` 0→**47**(Step 5 진입 조건 30 돌파)
- **벤치 2소스 정합 감시 신설**(`benchmark_source_parity.R`) — 7월 8일 불일치 적발
- **논문 크롤러 사망 수리** — python3 스텁 exit 0 위장, to_fetch 0→32
- 신설 테스트 7종 배터리 편입(340→459+)
- 상세: 메모리 [[project-ast-sidecar-survivorship-wiring-20260802]] 외

---

## §2 axiom 후보 현황 (의무 절 — W31 실측 스냅샷)

sweep step [3.5] 실행 결과(promote 실행됨, dry-run 아님):

- **candidate 총 77 / pending 77** (promote_crash 0)
- **near_miss 3건** · **confirm_flags 18** · **pending_5axis 89건(최고령 25일)** · quarantined_evidence **6건**(07-04 이후 정체 지속)
- **failing axis 히스토그램**: external **72** · independence **71** · falsification **61** · mechanism **37** · rigor 2

**진단 — ★1차 서술 정정 (같은 세션 실측으로 자가 반증)**

초판에 "실패 축이 external/independence/falsification에 몰려 있으니 emit 스키마 보강이 상위 수리"라고 썼는데, **카드 89건을 직접 열어보니 틀렸다**. 두 개의 다른 층을 혼동한 오진이었다:

- `failing_axis_histogram`(external 72·independence 71·falsification 61…)은 **CAND(candidate) 레벨의 promote 판정** 결과다.
- `pending_5axis` 89건은 **DIST 카드 레벨**이고, 실측하니 **89건 전부** `statement_refined=None` · `adversarial_verdict=None` · `frontier=[]` · `live_trigger=[]` · `constraint_firewall=None`이다. 즉 5축 검증에서 막힌 게 아니라 **자동초안(`draft_proposed`) 단계가 한 번도 실행된 적이 없다**. 스킬 §0.2 주석대로 스윕은 `draft_proposed`를 호출하지 않고, 그 호출은 /cleaner 세션 몫인데 그 세션이 3주 연속 초안을 안 돌렸다.

같은 계통의 반복이다 — **"검사가 옳은 것을 재지만 잘못된 지점에 서 있다"**(메모리 [[project-ast-sidecar-survivorship-wiring-20260802]]). 이번엔 검사가 아니라 내 진단이 잘못된 지점을 봤다. 히스토그램이라는 *있는 숫자*로 설명을 만들고 카드 실물을 안 열어본 것이 원인이다.

**팽창 기전 실측 (2차 진단)**: 완전 중복은 0건(cluster_key 89 distinct, supporting-집합 동일 0)이나 **부분집합 쌍 30건**이 있었다. 같은 클러스터가 L-code가 늘 때마다 새 `dist_id`로 재등재되는데 **구 카드가 회수되지 않아** 백로그가 부푼다.

**이번 세션 실처리**: 엄격 기준(진부분집합 ∧ family/polarity/type/research_mode 전부 동일)으로 **superseded 9건 확정** → 지식 손실 0 검증(구 카드 supporting L-code가 신 카드에 전량 포함, 미포함 0건) 통과 후 `expire_distilled(reason=superseded_by=...)` 집행. **pending_5axis 89 → 80**, expired 10 → 19.

| 회수(구) | 흡수(신) | family | n_L |
|---|---|---|---|
| DIST-RAMP-008 | DIST-RAMP-014 | value | 12 ⊂ 31 |
| DIST-AR-014 | DIST-AR-040 | momentum | 14 ⊂ 15 |
| DIST-GEN-001 | DIST-GEN-004 | overlay_regime | 9 ⊂ 10 |
| DIST-AR-030 | DIST-AR-037 | overlay_regime | 5 ⊂ 9 |
| DIST-AR-029 | DIST-AR-039 | infra_process | 6 ⊂ 7 |
| DIST-AR-006 | DIST-AR-017 | value | 3 ⊂ 5 |
| DIST-AR-015 | DIST-AR-031 | quality_earnings | 1 ⊂ 4 |
| DIST-AR-004 | DIST-AR-027 | consensus | 1 ⊂ 3 |
| DIST-AR-013 | DIST-AR-028 | flow_supply | 1 ⊂ 2 |

**남은 80건의 정본 처리**: 초안 미실행이 원인이므로 수리는 두 갈래다 — ① **재등재 시 구 카드 자동 supersede**(파이프라인 결함, 이번 9건은 수동 회수했으나 재발한다) ② `draft_proposed` 실행 자체를 세션 규약이 아니라 **기계 스텝으로 승격**(현행은 "세션이 해야 한다"는 문서 규약뿐이고 강제가 없어 3주 연속 미이행이 가능했다). 개별 정제는 80건 앞에서 산술적으로 따라잡지 못하며, 실제로 이번 회수 9건이 개별 정제 9건보다 싸고 확실했다.

**이월 사유**: 초안 작성(supporting L-code 실측을 읽어 statement 정제 + 적대검증 5체크)은 카드당 다수 L-code 정독이 필요해 이번 세션 잔여 자원으로는 상위 몇 건에 그친다. 알파 라운드 판정 수집이 병행 중이고(존재의의 = 알파시킹), 위 ①② 구조 수리가 개별 초안보다 EV가 높다고 판단해 **다음 사이클 최우선 인프라 항목**으로 등재한다. 잔량 80건·최고령 2026-07-08 명기.

---

## §3 continuity firewall

- 누적 block **53건**(W30 37 → +16) · 케이스 11 · suppression 1 · **pending_novel 1건**
- pending_novel 1건(hash `f210a9b70b1b`)의 caught_span은 alpha-search 큐 보고문의 "KR 추가 탐색 EV 낮음" 서술 — **TP성 판정**: 종결 어휘는 아니나 '탐색 중단 시사'로 AX-000과 긴장한다. 다만 같은 보고에 next_probe가 동반돼 있어 **FP 쪽으로 기운다**. 결정론 backstop에 올리면 정상 EV 서술까지 잡을 위험이 있어 **이번 주는 미승격**(관측 유지) — 같은 형태가 재발하면 그때 케이스화한다.

---

## §4 잔재 처리 (dry_run=FALSE — 실행 모드)

- **sweep 실삭제 1건** (weekly_temp_logs_30d: `/tmp/qvest_tg_brief.log`)
- hygiene_audit: **삭제 0 / 경고 18건**(status=measured) — 주요: `root_unauthorized` 17건 · `infra_underscore` (`ops/_sched_failure_classify.sh`) · `misplaced_outputs` (`02_Infrastructure/ast/tests/parity_factor_db_result.json`)
- weekly_cache_scratch_7d: 0건

**LLM 판정 (스킬 §1 ④ — 참조 0 검증 후 삭제)**: 이번 주 경고 18건은 **전부 보존**한다. 근거: ① `root_unauthorized` 17건은 오늘 신설된 테스트·수리 산출물이 다수라 참조 활성 가능성이 높고, 루트 13항목 규칙 위반 여부는 파일별 판정이 필요하다(일괄 삭제 금지) ② `_sched_failure_classify.sh`는 `_` 접두 판별을 `git grep`으로 확인해야 하며(메모리 [[project-hygiene-warnings-cleared-tg-lock-guard-20260725]]), 스케줄러 실패 분류는 07-26 수리 대상이라 활성 코드일 가능성이 크다 ③ `parity_factor_db_result.json`은 AST parity 증거물로 판정 근거 파일이다(§6 불변 런 기록에 준함).
→ **preserved_deferred 처리**, manifest에 사유 기록. 삭제는 파일별 참조 검증을 마친 다음 사이클에.

`/tmp/qvest_tg_brief.log` 경로 하드코딩(telegram_notify.R:1432)은 W30 digest에 이어 재확인 — 프로젝트 `.cache`로 이관하는 위생 수리를 후속 등재.

---

## §5 이번 주 운영 결함

1. **W30 증류 7일 지연**(→ 오늘 완결). pending 파일 단일본 구조라 sweep 재실행 전 증류가 선행 조건임을 W30 digest §5에 규약화.
2. **pending_5axis 3주 연속 미드레인**(49→89). §2에 접근법 전환 기록.
3. hygiene 경고 18건이 `measured` 상태로 자동 삭제되지 않음 — 이는 **설계대로**(참조 검증 없는 자동 삭제 금지)이나, 경고가 쌓이기만 하면 신호가 죽는다. 파일별 판정 사이클을 별도 태스크로.

---

## §6 후속 (next_probe)

- **알파**: FQ-111(제외-필터 × overlay 포함판 — 실배치 판정 관문) · FQ-112(MAX5 위험-축) · FQ-109(교체류 판정 q05 규약) · FQ-110(jump-share 직접 팩터화) · FQ-098/106/108. 큐 총 112건.
- **인프라**: axiom emit 스키마 보강(external/independence 자동 충전) → pending_5axis 구조적 드레인 · hygiene 18건 파일별 판정 · `/tmp` 로그 경로 이관.
- **도훈 판단 대기**: M01_PATHQ 교체안은 **철회**(WT-013 문턱 미달로 상정하지 않음). 잔여 대기 항목은 `next_session_task.md` 참조.
