# FQ-018 — A급 원장 18건 재베이스 일괄 재판정 (2026-07-12)

**배경**: 도훈 지적 "실패를 실패로 규정하지 말고 자가발전 계속" → 07-02 벤치 수리(IKS001→IKS200, [[reference-benchmark-iks200-bug-fix]]) **이전**의 A급 기록은 재베이스 의무 메타규칙(FQ-011 신설) 미적용 상태. 생존자 발견 = 즉시 자본급 후보(un-bury), 전멸 = 원장 정화.

**입력**: `.cache/harvest_20260712.json` `grade=="A"` 18건 (n_lcodes 273 중).
**방법**: ① 3분류(성과주장형/process·infra형/이미 재검됨) ② 챔피언십 표(`04_Research/01_reports/port_t_championship_20260710.md`) 기판정 대조 — 중복실행 금지 ③ 보존 시계열 존재 건만 재베이스 실측: pin_cache 고정(`fq018_20260712_174206`·보조 `fq018b_*`) + 교정 벤치(`.cache/benchmark.parquet`, 07-12 00:03 vintage = IKS200 + rawdata 4월 백필 반영) + canonical 산식(`build_benchmark_compare` → `Portfolio_Alpha_t_NW_lag3` + `essence_score(selection_type="chain")` oos v2). 자체합성 0. **원 L-code JSON 무수정**(원장 불변).
**산출**: `stage_artifacts/fq018_agrade_rebase/` (스크립트 2 + 결과 JSON 2 + 차트).

---

## 1. 총괄 판정

| 판정 | 건수 | 해당 L-code |
|---|---|---|
| **유지 A (process·infra형)** | 7 | L-141 · L-142 · L-148 · L-155 · L-RAMP-20260619_103729 · L-RAMP-20260619_105903 · L-RAMP-20260619_132312 |
| **강등 (재베이스 실측 후 미달)** | 2 | L-AS-20260612_154914 · L-AS-20260612_160537 |
| **기판정 인용 — 강등/자본급 아님** | 6 | L-130 · L-AS-20260709_074129 · L-RAMP-20260618_142650 · L-RAMP-20260618_175207 · L-RAMP-20260619_152736 · L-RAMP-20260620_161507 |
| **재측정 불가 (원 시계열 소실)** | 3 | L-RAMP-20260620_171915 · L-RAMP-20260620_184815 · L-RAMP-20260620_185554 |
| **재확정 A (생존)** | **0** | — |

**결론: 생존자 0 — 자본급 un-bury 후보 없음. 원장 정화 권고 (§5).** 단 RAMP_03C(184815)는 명목 HARD 3/3 통과 이력 유일 기록으로 시계열 소실 탓에 사면도 처형도 실측 불가 — 재실행 회부 여부는 도훈 결정 (§4.3).

---

## 2. 18건 전수 판정 표

| # | L-code | 항목 (created) | 분류 | 판정 | 근거 (1줄) |
|---|---|---|---|---|---|
| 1 | L-130 | STR_1652_DFA_on_VDplus (04-16) | 성과주장형(estimated) | **기판정 인용 — 강등** | L-148이 C15_DIRECT_PARQUET 위반 실측 — PIT 위반 = 계층 무관 절대 기각. 수치는 절대-MDD(벤치독립)라 재베이스 자체는 무관. 교훈부(포지션축소>팩터교체)는 Distilled 보존 가치 |
| 2 | L-141 | AXIOM_ENRICH (04-17) | process | **유지 A** | axiom 승격 scope 제한 절차 교훈 — 성과수치 없음, 재베이스 무관 (AX-004/005는 07-05 Distilled 강등으로 내용은 역사화, 절차 교훈은 현행 유효) |
| 3 | L-142 | NO_JUDGE_SWEEP (04-17) | process | **유지 A** | 카탈로그 정합성/judge 미실시 적발 절차 기록 — 성과주장 아님 |
| 4 | L-148 | NOJUDGE_SWEEP_V2 (04-17) | process | **유지 A** | PIT C1~C15 전수 sweep 절차 기록 (C10_LIQ 전사 패턴 적발) — 성과주장 아님 |
| 5 | L-155 | STR_1679v2 rehearing (04-17) | process(판정형) | **유지 A** | attribution 방법론 판정(3-variant 분해 의무) — 핵심수치 절대-MDD 분해(벤치독립). ⚠ CAPM α t=4.50은 04-17 legacy 벤치 — 성과 인용 시 재베이스 의무 |
| 6 | L-AS-20260612_154914 | Balanced multi-factor (06-12) | 성과주장형 · **재베이스 실측** | **강등 (A→C)** | PORT_t 2.523→**1.943** · oos v2 −0.191→**−0.408** · calmar 0.362 → HARD 0/3, essence C (§3.1) |
| 7 | L-AS-20260612_160537 | EW 5-sleeve (06-12) | 성과주장형 · **재베이스 실측** | **강등 (A→C)** | PORT_t 1.938→**1.369** · oos v2 −0.496→**−0.734** · calmar 0.297 → HARD 0/3, essence C (§3.1) |
| 8 | L-AS-20260709_074129 | Chen-Welch RD/M (07-09) | 이미 재검됨(07-02 후) | **기판정 인용 — 강등(screen-tier)** | 07-09 측정 벤치 = 07-12 pinned 교정벤치와 **bit-identical**(차이 0건, §3.2 보조검증): PORT_t 2.584 · oos −0.052 · calmar 0.346 → HARD 0/3. A는 hurdle proxy 라벨, authoritative essence B |
| 9 | L-RAMP-20260618_142650 | RAMP SIGNIFICANT_EWUNI (06-18) | 성과주장형 | **기판정 인용 — 강등** | 자체 기록 cap-w 권위 basis **0.26**(EW-uni 2.39는 HARD 비바인딩 진단) + 07-05 R1 재측정(fresh 교정 cap-w 벤치)이 family 전수 survivors 0 |
| 10 | L-RAMP-20260618_175207 | RAMP GRADUATION (06-18) | 성과주장형 | **기판정 인용 — 강등** | 원 기록 자체가 게이트 FAIL(cap-w 2.37 · oos 0.15 · calmar 0.37; 3.66은 EW-uni 진단 basis) — 챔피언십 #17 "재검증 가치 없음" |
| 11 | L-RAMP-20260619_103729 | AR 엔진 배선 (06-19) | process·infra | **유지 A** | Absorption Ratio soft-membership 배선 — 가치는 동일벤치 상대 A/B(+0.68t)로 벤치버그에 강건, 절대수치(2.49)는 미달 자가고백. 자본 인용 금지 |
| 12 | L-RAMP-20260619_105903 | SELFDEV AR+MSM 분기 (06-19) | process | **유지 A** | 레버 발견(분기리밸 oos레버 + 2축 pt레버) = 동일벤치 상대 A/B — 절대수치(2.73) 미달 자가고백 |
| 13 | L-RAMP-20260619_132312 | 국면엔진 14종 bake-off (06-19) | process(비교실측) | **유지 A** | 순위 지식(Cascade>Trend>AR+MSM…)은 동일벤치 상대비교로 재베이스에 강건 — 전 엔진 게이트 미달 자가고백 |
| 14 | L-RAMP-20260619_152736 | Shu-Mulvey FINAL 7.72 (06-19) | 성과주장형 | **기판정 인용 — 자본급 아님** | 챔피언십 #1 기판정: 인덱스-레벨 idealized(5bps≠KR15bps·MINY5-의존) + **25종 전이 시 전부 음수 PORT_t 실측 = non-deployable**. R4 forensic(transfer-loss 분해)은 챔피언십 큐 잔존 — 후속은 도훈 결정 |
| 15 | L-RAMP-20260620_161507 | RAMP_03 MOMCONS 결합 3.37 (06-20) | 성과주장형 | **기판정 인용 — 강등** | FQ-011 Step 0 "RAMP_03 = R1 family 중첩 제외" 명시 + stale-baseline: 비교대상 book 2.64(164m 당시 vintage)는 현 pinned book **6.130**으로 교체 — "Book 초과" 주장 사멸 |
| 16 | L-RAMP-20260620_171915 | RAMP_03B BOOK_ABSORB (06-20) | 성과주장형 | **재측정 불가 — 강등 권고** | 원 시계열 소실(`.cache/_search2_book.rds` 부재, 06-20 비-L-code 산출물 0건 실측) + stale-baseline. "오버레이가 해친다(4.87 vs 2.64)" 주장은 FQ-011 오버레이 경제학(PORT_t 비용 +0.214 비유의 ↔ MDD −17.4p 순이득 확증)으로 대체됨 |
| 17 | L-RAMP-20260620_184815 | RAMP_03C BOOKMOM_CAPW (06-20) | 성과주장형 | **재측정 불가 (원 시계열 소실)** | **명목 HARD 3/3 통과 유일 기록**(pt 2.98·oos 1.19·calmar 0.89)이나 벤치버그기 측정 + `.cache/_construct.rds` 소실 — 추정 재구성 금지. 판별은 재실행만 가능 (§4.3) |
| 18 | L-RAMP-20260620_185554 | RAMP 8COMP EXHAUSTIVE (06-20) | 성과주장형 | **재측정 불가 — 강등 권고** | 시계열 소실 + SR/calmar 미달 자가고백 + stale-baseline(교정 book 164~168m 창 실측 4.925, FQ-011 vintage 표 — 3.06 "돌파" 전제 붕괴). process 교훈(rank-IC>active·cap-w OOS레버·SR벽 1.0~1.16)은 Distilled 보존 가치 |

---

## 3. 재베이스 실측 상세 (재측정 수치 있는 3건)

### 3.1 AS 06-12 2건 (재베이스 본측정, pin `fq018_20260712_174206`)

파이프라인 sanity: 보존 `bt_result.rds` + 저장벤치 재현 PORT_t = **2.523 / 1.938** — 원 authoritative_remeasure(06-12 16:37, 수리 전) 기록과 소수 3자리 일치 → 배관 검증 완료.

**벤치버그 정량화 (2005-02~2026-06, 5,266 거래일)**: 구(IKS001계) vs 교정(IKS200) 일수익 cor 0.9933, 누적수익 **7.43 vs 9.29** — 구벤치가 시장을 과소평가 → active 알파 과대 → PORT_t 인플레. FQ-011 bare book(7.236→6.344)과 동일 방향.

| 전략 | PORT_t (전→후) | oos v2 (전→후) | calmar | essence | HARD 3종 |
|---|---|---|---|---|---|
| STR_AS_20260612_154914 (Balanced multi-factor) | 2.523 → **1.943** | −0.191 → **−0.408** (splits −0.303/−0.408/−0.615) | 0.362 | A(proxy)→**C** | **0/3 FAIL** |
| STR_AS_20260612_160537 (EW 5-sleeve) | 1.938 → **1.369** | −0.496 → **−0.734** (splits −0.548/−0.734/−0.829) | 0.297 | A(proxy)→**C** | **0/3 FAIL** |

주: calmar는 절대 NAV 기반(벤치독립)이라 재베이스 무관 — **두 건 모두 calmar 단독으로도 이미 graduation 불가**였음. 재베이스는 PORT_t·oos를 추가로 −0.57~−0.58t / −0.22~−0.24 악화시켜 강등을 이중 확정. ⚠ 두 건은 06-12 배치 = batch_434 오염 창(가설라벨≠실행신호 가능, [[project-batch434-codegen-contamination]]) — 수치는 실측이나 라벨 신뢰도 별도 유의.

### 3.2 AS 07-09 1건 (보조검증, pin `fq018b_20260712_*`)

07-09 측정은 IKS200 수리 후이나 rawdata 4월-소실 복구(07-11)·벤치 캐시 07-12 갱신 **이전** → 07-12 pinned 벤치로 재대조: 저장벤치와 교정벤치 **완전 동일(5,261일 중 차이 0건)** → 4월 백필은 이 창의 벤치값 불변. 판정 불변: PORT_t **2.584** · oos **−0.052** · calmar **0.346** · essence B → HARD 0/3. 기판정 인용 확정.

---

## 4. 후속 조치 권고

### 4.1 원장 정화 (전멸 확정분)
- 강등 확정 11건(#1·6·7·8·9·10·14·15·16·17·18 중 17 제외 10건 + 17은 별도)의 `grade:"A"`는 **스크리닝/버그기 라벨**로, 자본 문맥 인용 금지. 원장 JSON은 불변 유지 — 본 보고서가 재베이스 판정 SOT. hypothesis_index/lcode_corpus **파생 뷰**에 `rebase_verdict=demoted_20260712` 반영은 다음 Cleaner 스윕에서 도훈 confirm 후 (원장≠뷰, [[reference-code-identity-stability]] 정합).
- harvest 표본에서 A 18건 중 **실질 A는 process형 7건뿐** — 성과형 A는 0건. 이후 harvest/주입면에서 "Grade A" 집계 시 process/성과 분리 표기 권고.

### 4.2 유지 A(process) 7건
현행 유효. 단 L-155의 CAPM t=4.50, L-130 교훈 인용 시 각각 재베이스 의무·C15 오염 각주 필수.

### 4.3 도훈 결정 대기 — RAMP_03C 재실행 회부 여부 (frontier 큐 `dohoon_decision` 후보)
- **사실**: RAMP_03C(book+mom cap-weight, 06-20)는 A급 원장에서 유일하게 명목 HARD 3/3(2.98/1.19/0.89) 통과 기록. 그러나 ① 벤치버그기 측정 ② 경계값(+0.03) ③ 동일 창 실측 재베이스 감쇠가 전부 음(−0.57~−0.58t, §3.1 — 다른 창·주기이므로 수치 이전 불가, 방향 참고만) ④ cap-weight 레버 주장은 07-06 cap-tier 국소화 실측("mega-cap signal-dead", [[project-captier-alpha-localization-20260706]])과 긴장 ⑤ 입력 캐시 전체 소실로 재실행 = RAMP search 파이프라인 재구축(build_cache→run_construct, `_bo_fwdgic.rds` 선행 재생성 필요) — 비용 중.
- **권고**: 착수하지 않음(세션 임의 착수 금지). `06_Registry/alpha_frontier_queue.json`에 `dohoon_decision` 항목으로 등재 여부만 도훈 판단에 회부.

### 4.4 Shu-Mulvey R4 forensic
챔피언십 재검증 큐 잔존 항목(transfer-loss 단계 분해) — 본 감사 범위 밖, 무간섭 유지.

---

## 5. 실행 기록
- 스크립트: `stage_artifacts/fq018_agrade_rebase/{rebase_as_20260612.R, verify_as_20260709.R}` (단일스레드·arrow io 2·source 패턴)
- 결과: `stage_artifacts/fq018_agrade_rebase/{rebase_results_20260712.json, verify_as_20260709.json}`
- pin: `.cache/pins/fq018_20260712_174206` + `fq018b_*` (benchmark.parquet 07-12 00:03 vintage)
- 원 L-code JSON 18건: 무수정 확인 (판정은 본 보고서로만)
