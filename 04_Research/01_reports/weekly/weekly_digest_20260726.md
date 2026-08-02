# Weekly Digest — 2026-W30 (07-19 ~ 07-26)

**작성**: 2026-08-02 (지연 증류 — W30 sweep 산출 `cleaner_pending.json`(2026-07-26 21:00 생성)이 미증류로 이월돼 있던 것을 소비. 지연 사유는 §5 기록)
**owner**: session_main · **claim**: `distill_status=in_progress` (2026-08-02 13:52)
**소스**: `.cache/cleaner_pending.json` (schema cleaner_pending_v2, dry_run=TRUE) + `.cache/lcode_corpus.json` 실측 인용
**규칙 SOT**: `02_Infrastructure/docs/rules/artifact-storage.md` §8

---

## §1 주간 리서치 결론 (실측 인용 — metric_type 병기)

W30 신규 L-code 9건. 수치는 전부 corpus 원문 인용이며 재계산·추정이 아니다.

### 1-1. QEPM 자가발전 라운드 6건 (07-18 밤샘 아크 — W30 인벤토리에 계상)

| L-code | 대상 | metric_type | 결론 · 핵심 수치 |
|---|---|---|---|
| L-AR-20260718_212326 | crash-aware momentum SELECTION (FQ-058 P3) | canonical_screen | config-scoped negative. 20변형 전부 OOS PORT_t < base(−0.074). IS-best(composite λ=1.0, IS calmar 0.618)가 OOS-worst(−1.02) = 명백 과적합 |
| L-AR-20260718_215751 | insider-selling 유니버스 배제 필터 | canonical_screen | FALSIFIED. 배제가 base를 **훼손** — cap-w PORT_t 1.171→0.771, paired −2.15%/yr(t −1.35). 21/21 셀 음성. EW-uni도 음(1.857→1.442) = 벤치 아티팩트 아님 |
| L-AR-20260718_222839 | Transformer/foundation-model asset pricing | canonical_screen | screen-tier negative. XATTN 배포검증 cap-w 1.31·oos −0.64·calmar 0.49 HARD 3중 FAIL. ★유동성 sweep 반증(2e8→1e9→5e9에서 1.31→0.79→−0.01) = "유동성-강건" 주장이 broad-universe 아티팩트. FM 각도는 venv 패키지 부재로 **capacity-gated**(반증 아님) |
| L-AR-20260718_232144 | transformer regime detector-swap 오버레이 | backtested | VALIDATED_NEGATIVE. base M4×AR×R05 SR 1.809/calmar 2.069 vs treat 1.796/1.993 = transformer 열위. paired NW-t −0.863. PIT clean(0/221·strict-PIT A/B inflation −0.3%) |
| L-AR-20260718_232148 | transformer 팩터 밸류에이션 timing | canonical_screen | config-scoped negative + 부수발견. ★oracle rotation port_t **12.894** ≫ static 1.202 = **타이밍 headroom 실재**(벽은 headroom이 아니라 OOS 실현가능성). valuation timing paired_t ≤1.05 FAIL. transformer는 paired_vs_static 1.855이나 vs momentum 전 seed 음 = trivial factor-momentum tilt에 지배 |
| L-AR-20260718_235244 | 외생변수 ML 조합발굴 (팩터 기대수익 직접 예측) | canonical_screen | config-scoped negative. 6 독립 경제논리(crowding/dispersion/funding/crash-risk/cross-factor/macro) 전부 oos<0·paired_vs_momentum<0(best GBM −0.359) — factor-momentum baseline을 못 이김 |

**주간 통합 판정**: ML/transformer 계열 4라운드가 전부 동일 벽에 도달했고, 그 벽의 위치가 **표현력이 아니라 OOS 실현가능성**임이 oracle 실측(12.894 vs 1.202)으로 정량화됐다. 이 지식이 이후 08-02 수학 심화 라운드(시그니처·Wasserstein)의 사전 posterior가 된다.

### 1-2. method-frontier 1건

| L-code | 대상 | metric_type | 결론 |
|---|---|---|---|
| L-QPM-20260718_201043 | FQ-058 drawdown-aware WEIGHTING (MinCDaR/MinCVaR) | canonical_screen | config-scoped negative. 5-arm 197 rebalance walk-forward, hard constraint 1970셀 위반 0. paired NW-t +0.49/−0.15 비유의·oos_retention 음수(−0.40/−0.17)·calmar 전 arm 0.64 미달(최고 EW 0.42) → **MDD 레버는 weighting이 아니라 membership**(선별) 실증 |

### 1-3. alpha-search 큐 소비 2건 (07-26)

| L-code | 전략 | metric_type | 결론 |
|---|---|---|---|
| L-AS-20260726_174643_26276 | VOL_RANK_STABILITY_v1 | **proxy** | 등급 F — CAGR 3.7%(벤치 대비 −7.2%p), 샤프 0.17. 역방향 가설 탐색 후보 |
| L-AS-20260726_174804_23216 | SPEC_LOWFREQ_MASS_v1 | **proxy** | 등급 C — CAGR 10.1%(벤치 대비 −0.8%p), 샤프 0.35. 근접 탈락, 보강 후 재검증 후보 |

⚠ 두 건은 `metric_type=proxy` — graduation 판정 근거로 사용 불가(measurement-graduation §1). 후속 canonical 재측정은 08-02 AS-20260802-R1 라운드에서 dual-basis로 수행됐다(그 결과는 W31 digest 소관).

### 1-4. 하네스 (커밋 207건 중 구조 변경분)

관측 계층 대수리가 이 주의 인프라 축이었다: 자동커밋 밸브 v2(영구개방 171회 수리) · `boot_currency_check.sh` 7축(기대값을 헌법에서 런타임 파생) · 리더 8종 감사 36확정→33 수리 · cache_freshness worse-of 위반 주입 테스트(14 assert) · spend_limit '월 단위' 오독 정정(도훈 지적). 상세는 메모리 [[project-autocommit-valve-v2-boot-currency-20260726]].

---

## §2 axiom 후보 현황 (의무 절)

W30 sweep step [3.5] 집계(dry-run — promote 미실행, 기존 review_log 스냅샷):

- **candidate 총 75건 / pending 75건** (promote crash 0 · promote_failures 0)
- **failing_axis histogram 5축** · **near_miss 2건** · **confirm_flags 8** · **lcode_integrity 9**
- **pending_5axis 3건** · **quarantined_evidence 6건**(07-04 TAINTED 이후 정체 — 초안 대상 제외는 불변)

**정직 상태**: dry-run 집계라 이 숫자는 07-26 시점 스냅샷이다. 08-02 현재 corpus가 427→430으로 갱신됐으므로 near-miss 정제·pending_5axis 드레인은 **W31 증류에서 최신 스냅샷으로 수행**한다(구 스냅샷 기준 초안 작성은 stale 판정 위험 — 08-02 registry staleness 교훈 [[project-registry-staleness-3near-misses-20260802]] 적용).

---

## §3 continuity firewall 현황

- 누적 block 로그 **37건** · 학습 케이스 **11건** · suppression **1건** · 신규 학습 0 · pending_novel **0건**
- await_review 항목 없음 = 이 주에는 새 우회 어휘가 나타나지 않았다.

---

## §4 잔재 처리

W30 sweep은 **dry_run=TRUE**로 실행돼 실삭제 0건, 후보 6건만 식별됐다:
- hygiene_audit 후보 5건 (manifest `.cache/hygiene_manifest.log`)
- weekly_temp_logs_30d 후보 1건: `/tmp/qvest_tg_brief.log`

⚠ `/tmp/qvest_tg_brief.log`는 Windows에서 `C:/tmp`로 해석되는 경로다(telegram_notify.R:1432 하드코딩). 삭제해도 재생성되며, **근본은 프로젝트 `.cache` 경로로의 이관**이다 — 위생 칩 대상으로 §5에 기록.

실삭제는 W31 증류에서 참조 0 검증과 함께 수행한다(W30 후보 목록은 이미 일주일 경과로 stale — 재스캔이 정본).

---

## §5 이 주의 운영 결함 (증류가 적발한 것)

1. **W30 증류가 7일 지연됐다**: `cleaner_pending.json`이 07-26 21:00 생성 후 `awaiting_distill` 상태로 방치. bootstrap WARN이 발화했어야 하나 세션이 알파 라운드에 집중돼 소비되지 않았다. → **W31 sweep 실행 전 이 digest 완결이 선행 조건**(pending 파일은 1본이라 덮어쓰면 W30 인벤토리가 소실된다).
2. **sweep이 dry-run 고정**: `dry_run=TRUE`로 6주째 실삭제 0 — 위생 잔재가 누적된다. 실행 모드 전환은 도훈 판단 사안으로 기록(무단 전환 금지 — 삭제는 비가역).
3. `/tmp/qvest_tg_brief.log` 하드코딩 경로 (§4).

---

## §6 후속

- W31(07-27~08-02) digest 별도 작성 — 오늘 sweep 실행 후.
- axiom near-miss 정제·pending_5axis 드레인은 W31에서 최신 스냅샷 기준 수행.
- 잔재 실삭제 판정도 W31 재스캔 기준.
