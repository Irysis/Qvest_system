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

**주간 통합 지식 — 소비 경로가 판정을 바꾼다**: 같은 주에 두 사례가 나왔다. ① WT-011: 시그니처의 수익축은 죽고 flow축은 무손실 → 소비면은 monitoring. ② WT-014: WT-010에서 랭킹으로 죽은 MAX5가 **필터로는 산다**(ΔIR +0.169). 필터는 랭킹이 아니라 후보집합 축소라 전이-벽 기전을 우회한다. → **재료 기각 전 소비면 7종 순회 의무**(연속성 4호)의 실증 근거가 이 주에 확보됐다.

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

**진단 (정직)**: pending_5axis가 07-17 실측 49건 → 오늘 **89건**으로 늘었다. 백로그 드레인 의무(스킬 §2 ①, 세션당 5건+)가 3주 연속 미이행돼 적체가 배로 커진 상태다. 실패 축 분포가 external/independence/falsification에 몰려 있다는 것은 **개별 후보의 질 문제가 아니라 emit 지점에서 그 3축 입력이 구조적으로 안 채워진다**는 뜻 — 후보를 하나씩 정제하는 것보다 emit 스키마 보강이 상위 수리다.

**이번 세션 처리**: 오늘 라운드 3건의 L-code를 직접 emit하면서 `falsification_attempts`·`mechanism_hypothesis`·`next_probe`를 전부 채웠다(L-AR-20260802_134401/134402/134403). 이는 실패 축 3종 중 2종(falsification·mechanism)을 emit 시점에 채우는 표본이며, **emit 템플릿 보강의 실물 근거**로 남긴다.

**이월 사유 명기**: near-miss 3건 statement 정제 + pending_5axis 89건 드레인은 이번 세션에서 미이행. 사유 = 이 주 세션 자원이 알파 라운드 9건 + 판정 수집에 배분됐고(존재의의 = 알파시킹, CLAUDE.md Project Goals), axiom 드레인은 알파 라운드를 막는 결함이 아니다. **다음 세션 최우선 인프라 항목으로 등재**하되, 드레인 방식은 개별 정제가 아니라 **emit 스키마 보강(external/independence 축 자동 충전)** 으로 접근할 것 — 개별 정제는 89건 앞에서 산술적으로 따라잡지 못한다.

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
