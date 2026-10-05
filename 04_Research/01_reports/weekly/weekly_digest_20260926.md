# Weekly Digest — 2026-W39 (2026-09-19 ~ 09-26)

**작성**: 2026-09-26 (Q / 주간 증류 · owner=`auto_distill` · claimed 2026-09-26 10:37:00)
**기계 스윕**: 2026-09-26 10:27:46 (`02_Infrastructure/ops/weekly_cleaner_sweep.R`, `dry_run=false`, 삭제 2건)
**수집 창**: 직전 스윕(2026-09-19 21:54) 이후 7일
**출처**: `.cache/cleaner_pending.json`(schema `cleaner_pending_v2`) · `04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md` · `06_Registry/pit_quarantine.json` · `06_Registry/decision_register.json` · `06_Registry/reinforce_ledger_l2.json` · `06_Registry/reinforce_auto_config.json` · `stage_artifacts/l_code/{reinforcement,factor_rotation,paper_replication}/*` · `04_Research/01_reports/organic_reinforce_20260925/lever_audit_final.md` · `04_Research/01_reports/p0_05_remeasure_20260925/batch_triad.csv` · `qepm/memory/axioms/{active,deprecated}/*` · `.cache/hygiene_manifest.log`

**수치 규약 (이번 주 특히 중요)**
1. 등급은 계약 산출만 인용한다(`authoritative_remeasure.json::essence_grade` · 블록 `l_code_*.json`). 손계산·재구성 없음.
2. **이번 주부터 규약이 둘이다.** 블록 L-code 의 t·Calmar 는 **구 규약(`close_d_legacy`, 신호일 종가 체결)** 판이고, 09-25 재측정 판은 **신 규약(`close_t1`, 익일 종가 체결)** 이다. 두 수치를 한 줄에 섞지 않는다. 레버 감사(`lever_audit_final.md` §⑤)는 **구 규약 수치 인용 자체를 금지** 목록에 올렸다 — 아래에서는 구 규약 수치를 인용할 때 매번 규약을 명기한다.
3. 값이 없는 축은 "미측정". 채우지 않는다.

> ⚠ **활성화 HOLD — 사유가 바뀌었다.** 3주 연속이던 "신규 활성 예정 4건 > MAX 3"이 사라지고, 이번 주 사유는 **"주입 길이 1990 > 1900(worst_header_render(n=8) · 2,000 예산 임박 — 활성화가 마커를 밀어낼 수 있음)"** 이다(`axiom_candidates.activation_hold`). `n_new_active_planned = 0` 이고 후보 34건 전부 `would_activate=false` 다 — **이번 주 HOLD 가 막은 활성화는 0건**이다. 막고 있는 것은 활성화 수가 아니라 **주입 예산 계기**다(§7a).

---

## 0. 주간 볼륨 (실측 — `.cache/cleaner_pending.json`)

| 항목 | 값 | 전주 | 출처 키 |
|---|---|---|---|
| 스윕 삭제 | 2 | 8 | `sweep_deleted_n` |
| stage_artifacts 신규 | **1,300** | 246 | `inventory.stage_artifacts_new.n` |
| 신규 L-code | 368 | 233 | `inventory.new_lcodes.n` |
| 커밋(7일) | 129 | 130 | `inventory.git_log_7d.n_commits` |
| hypothesis_index | 2,864 (Δ **+470**) | 2,394 | `inventory.hypothesis_index` |
| 위생 경고 | 260 (감사 삭제 **0**) | 249 (1) | `sweep_detail.hygiene_n_warnings` |
| L-code 무결성 | **COLLISIONS_PRESENT** — 1,946 기록 / 1,649 고유 / **297 충돌** | 210 충돌 | `axiom_candidates.lcode_integrity` |
| worktree | prune 0 · kept **23** · failed **0** | 0/19/3 | `worktree_prune` |
| 연속성 방화벽 | 차단 124 · case 11 · suppression 5 · 미검토 4 | **완전 동일** | `continuity_firewall` |
| 공리 후보 | 123 / pending **123** | 120/102 | `axiom_candidates` |
| pending_5axis | 111 (최고령 **80일** · `DIST-AR-005`) | 108 (73일) | `pending_5axis` |
| step_status | **13항목** 전부 OK | 11 OK | `step_status` |
| direction_replay | `insufficient` (n=3 · acted 0 · measured 0 · min_n 8) | — | `direction_replay` |

### 0a. ★ "stage_artifacts 신규 1,300" 은 신규 연구 1,300건이 아니다

`inventory.stage_artifacts_new.entries` 의 표본 100건 중 대다수가 `stage_artifacts/replication/2026082x~0831x` — **한 달 전에 만들어진 런 디렉터리**다. 원인은 09-25 의 P0-05 대량 재측정이다: 각 런 디렉터리 안에 `remeasure_close_d_legacy_<hash>/` 와 `remeasure_close_t1_<hash>/` 하위 디렉터리가 새로 생기면서 부모 디렉터리의 수정시각이 갱신됐다.

- `remeasure_close_t1_*` 하위 디렉터리 실측 개수: **1,197**(디렉터리 스캔).
- 표본 `20260829_122020_9192`: 최상위 파일 12개가 전부 2026-09-25 12:17 로 재기록됐으나 `authoritative_remeasure.json::remeasured_at` 은 **2026-08-29T12:26:30** 그대로이고 `retro.applied_at` 도 2026-09-04 그대로다 — **내용 불변**.
- 즉 이 주간 볼륨 지표는 **수정시각 신호**이지 측정 건수가 아니다. 이번 주 실제 신규 측정은 §3(강화 격자 칸)·§4(2계층 3 arm)·§5(충실구현 2편)에 열거된 것이 전부다.
- (미적립 학습 → § 결과 JSON)

★ L-code ID 충돌 **210 → 297**(+87, 4주 연속 증가). 전주와 같은 형태(`L-RP-*` 병렬 칸의 초 해상도 타임스탬프 공유)이며 3주째 미수리다. 측정은 살아 있고 식별자만 소각된다 — 원장 층 수리 대상이고 본 증류 범위 밖이다.

★ 연속성 방화벽 4지표가 **3주 연속 완전 동일**(124/11/5/4)이고 `n_new_suppressions_learned = 0` 이다. 미검토 4건은 전부 `captured_at 2026-08-22` — 35일째 같은 자리다.

---

## 1. 이번 주의 사건 — **PIT C11 위반 확정, 봉쇄, 도훈 결정**

이번 주 리서치의 중심은 알파가 아니라 **시간축**이었다. 해외(FRED) 시계열을 관측일로 한국 신호일에 결합해 온 경로가 C11 위반으로 확정됐고, 조사→판정→봉쇄→결정이 한 주 안에 닫혔다.

### 1a. 판정 (2026-09-24 · 읽기 전용 · 등급 영향 측정 0)

정본: `04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md`(조사 4건 A/B/C/D + 적대검증 3건 V1/V2/V3 종합).

**위반은 한 지점이 아니라 규약의 부재다.** 네 기전이 겹친다(판정서 §0-2): ①공표형(주간·월간) 계열을 관측일로 결합 ②같은 날짜 병합 ③1행 lag 신호를 한국 종가→종가 수익에 적용 ④최신 빈티지를 과거에 소급.

확정 위반 14건(V-01~V-14) 중 **등급 결과에 닿은 경로는 셋**(판정서 §0-3):

| 경로 | 소비 규모 | 핵심 증거 |
|---|---|---|
| **V-01** `compute_regime.R:75-77` MA01_GDP_Sensitivity | L1 **20칸**(C 18 · F 2) | 신호월 관측치를 공표 전 사용(CPI +10~17일 · INDPRO +15~20일). 공표분만 쓰면 202608·202003 MA01 **산출 불가**(n<12) |
| **V-02** `pg2_risk_overlay.R:90-91,155-173` ← AE·m4 패널 | L1 **15칸**(B 5 · C 10) · 카탈로그 15모듈 전부 `fr_eligible` | 미국 월말 종가 같은 날짜 218/223개월 · STLFSI4 223/223 · NFCI 187/223. `assert_overlay_pit` 는 날짜 라벨만 비교해 통과 |
| **V-05·V-06** `regime_signal.R:806-850` → unified Category → RCMA·module_performance·`run_wf_ensemble.R:85-91` | **2계층 FR_003 전체**(§4) | ΔFRED_MRS_t 와 ΔVIX_t 상관 **+0.838**, ΔVIX_{t−1} 과는 −0.079(V1). lag0 적합 오차 mean\|d\| 0.04~0.09 vs lag1 0.9~2.0(V2) |

★ **A등급 칸 0 · 1계층 충실구현 경로 0**(충실구현 하네스·RP_AUTO 엔진·alpha_search 에서 해외 결합 grep 0건 — 판정서 §1-6).
★ 강화 L1 전체 1,281 시도 중 오염은 **최대 35칸(B 5 · C 28 · F 2)**(판정서 §③).
★ 2계층 풀 862개(A 0 · B 278 · C 433 · F 148) 중 **B 풀 278개에서 5개가 오염**.

**소비자 조사(C)의 세 결론이 적대검증 V3 에서 반증됐다**(판정서 §0-4): "B 노출 0" → V-02 로 반증 · "2계층 풀 해외 노출은 MA04 뿐" → 반증 · "m4 게이트는 1개월 이상 지연이라 적합" → V-04 로 반증. 판정서 §1-5 는 반증·정정된 원 판정을 13행으로 열거한다 — 조사 단독 소견이 검증에서 어떻게 깎이는지가 이번 판의 부산물이다.

**방어선이 왜 못 잡았나**(판정서 §③ 말미) — 전부 양성 대조가 없는 계기였다:
- `lookahead_detector.R:236` 의 C3 면제("Macro/regime lookups are OK")는 **코드로 굳은 합리화**. factor_db 빌더는 한 번도 스캔 대상이 된 적이 없고 C11 테스트는 0건.
- `pit_verify_fred_lag` 는 **무조건 TRUE 를 반환하고 호출부가 0개**.
- `overlay_pit_guard`·AE 가드는 날짜 라벨만 비교. `ast_verify.py:360-361` 은 레지스트리의 "-1d" 선언을 그대로 믿는다.

### 1b. 봉쇄 (안 A 0단계 — 2026-09-24 04:44~05:36)

`06_Registry/pit_quarantine.json#PITQ-C11-20260924`(status `active`):
- **팩터 격리 3종** — `D32_Beta_VIX`(소비 0 · B1 풀 적격이라 봉쇄) · `MA01_GDP_Sensitivity`(L1 20칸 소비) · `MA02_CPI_Sensitivity`(소비 0).
- **오버레이 arm 정지 1종** — `pg2_risk_overlay_v1` : `overlay_catalog.json` status `active→suspended`.
- **모듈 15건** `fr_eligible → false` + `contamination{reason: pit_invalid:C11}`.
- **레인 정지** — `l2_auto.enabled true→false`(`reinforce_auto_config.json:20~26`, paused_at 2026-09-24T04:36:59).
- **원장 표식** — `rf_mark_vintage_batch`(append-only · essence·grade **불변**) : L1 35칸 + L2 2칸(FR_003 n=1 · base) `verdict: consumed`. 후손 칸 전수 대조 **0건**(`ledger_marks.descendants.method` — 승격 17 entry 의 parent·carry·source_spec 대조).

**봉쇄 자체가 적대검증에서 한 번 깨지고 수리됐다** — amendment `C11-F1`(2026-09-24 05:28·05:35): 등재 관문(`rf_overlay_admit.R:28-31 → pitq_source_hits`)이 실제 FRED 저장소(`fred_macro*`)·pg2 arm 파일 자체·BOOK 생성기(`M4gAE`)·`regime_jump_daily(JM_State)`·`regime_current.json`·`regime_forecast_series` 를 못 잡아 **샌드박스 E2E 에서 세 변형이 ADMIT 됐다.** 정규식 **18개 추가**(1차 13 + 2차 5 — 엔진 globalenv 전역 함수·상수, 밑줄 결합 식별자, 매크로 ctx provider). 재현 검사 = `08_Tests/validation/test_pit_quarantine_c11.R` L11~L13.

### 1c. 도훈 결정 (2026-09-24 10:31)

`06_Registry/decision_register.json`:

| 결정 id | 내용 | status |
|---|---|---|
| `PIT-C11-REMEDIATION` | **안 B**(계열별 가용시점 층 + 표적 재빌드 + 오염 칸 재측정, 안 A 봉쇄 포함) **후 안 C**(ALFRED as-of 빈티지) 순차 | resolved |
| `PIT-C11-BOOK0001` | 지금은 트래킹에 "C11 미해소 게이트" 표기 → 시간축 수리 뒤 게이트 이력 재산출 → A 면 Judge 스폰 | resolved |
| `PIT-C11-MA0102` | MA01·MA02 **퇴역**(후보 풀 제외 · lifecycle retired). MA01 20칸은 **무효 유지** | resolved |
| `PIT-C11-CONVENTIONS` | ①DEXKOUS→ECOS 731Y001 ②ICE OAS 한국 d+2 ③CPI 2025-10 결측은 날짜 기준 12개월 변화 ④방어선 수리(면제 삭제·`pit_verify_fred_lag` 실구현·**C11 양성 대조 검사**·레지스트리 선언 정정) ⑤C1 동시 수리(D08·RE10·RE13) ⑥WT-D20260803_005/006 오염 정본 무효 ⑦등급 체계 밖 소비자는 표식만 ⑧**P0-05·06 재측정 경로 비편입** — 표식·epoch 공유 | resolved |

산출: `06_Registry/fred_availability_rules.json`(83.7KB · 2026-09-24 18:07 — 계열별 가용시점 규약 정본) · `06_Registry/pit_c11_consumer_notices.json` · `06_Registry/pit_jm_c1_consumer_notices.json`.

★ **⑧이 핵심이다.** 오염은 보유를 고른 **신호 안에** 있으므로 보유 기반 재측정(P0-05)으로 씻기지 않는다(판정서 §P0-05·06 편입 여부). 편입하면 "오염된 보유가 rebase 된 essence 로 세탁"된다. 그래서 A 자격 관문에 `vintage_flag` 보류가 신설됐다(§2c).

### 1d. 미이행 1건 — BOOK 표기

결정 `PIT-C11-BOOK0001`(09-24 10:31 resolved)은 "트래킹에 C11 미해소 게이트 표기"를 정했으나, `06_Registry/book/book_registry.json` 은 **`last_updated 2026-08-30T00:30:56` 이고 C11 표기가 없다**(파일 수정시각은 09-25 08:37 이나 내용에 해당 문자열 부재 — grep `BOOK_0001` 이 `pit_c11_consumer_notices.json` 에서도 0건). 결정과 원장 상태가 아직 어긋나 있다. **다음 주 확인 항목**이며, writer(`book_registry.R`) 경유 사항이라 본 증류 범위 밖이다.

---

## 2. 측정 규약 교체 — `close_t1` epoch 과 레버 감사

### 2a. P0-05/06 — 전 코퍼스 3판 대조(stored / close_d_legacy / close_t1)

`04_Research/01_reports/p0_05_remeasure_20260925/` (2026-09-25 11:18~15:15):
- 각 런 디렉터리에 `remeasure_close_d_legacy_<hash>/` · `remeasure_close_t1_<hash>/` 산출물 + 자체 `authoritative_remeasure.json`.
- 산출물마다 **`measurement_regime` 지문**: `key`·`exec_price`·`cost_model_version`·`harness_md5`·`scoring_md5`·`selection_type`·`n_trials_cumulative`·`data_vintage`(RAWDATA/benchmark 경로·크기·mtime·행수·최대일자)·`data_end`. 표본 `20260829_122020_9192/remeasure_close_t1_5562284e/authoritative_remeasure.json:42~70`.
- `batch_triad.csv`(90KB · 2026-09-25 13:17) 컬럼 설계가 **두 효과를 분리**한다: `d_vint_*`(같은 규약으로 오늘 다시 재면 생기는 **데이터 빈티지 드리프트**) · `d_conv_*`(`close_d_legacy → close_t1` **체결 규약 변경**).
- `remeasure_close_t1_*` 디렉터리 실측 **1,197개**.

### 2b. 레버 감사 — 이번 주 최대 수확 (`organic_reinforce_20260925/lever_audit_final.md`)

전 격자를 신 규약으로 다시 읽은 종합(읽기 전용 · R 실행 0 · 운영 쓰기 0건 — 파일 §"읽기 전용 준수"). 핵심 실측:

| 축 | 값 | 출처 |
|---|---|---|
| 신 규약 판 커버리지 | **1,187/1,222(97%)** · 없는 35칸은 **35칸 전부 `pit_c11` 표식** | §② |
| 등급 분포(신 규약) | **A 0 · B 220 · C 884 · F 83** | §② |
| Calmar ≥ 0.64 | **0칸** | §② |
| Calmar ≥ 0.5 | **2칸** — 084807 promo1 B5_18 0.527(OOS −0.498) · B5_22 0.535(−0.589). **둘 다 적대검증 G2 fail** | §② |
| 최고 칸(신 규약) | 22632 promo3 **B1_3** — PT **3.777** · Calmar 0.433 · SR 1.06 · CAGR 25.1% · MDD 58.0% · OOS 0.117 · **Grade B** | §② |
| A 5조건 충족 수 | 0개 572칸 · 1개 166 · 2개 410 · **3개 39칸**(PT·SR·CAGR) | §② |
| 규약 민감도 | 같은 짝의 옛/새 Δ 상관 PT **0.97~0.99** · Calmar 0.92~0.96 — 블록 순위는 규약을 바꿔도 거의 그대로. 타격은 22632·084807·14760 세 계보에 집중(PT −0.58~−0.67) | §② |

**① 구속 축이 바뀌었다 — Calmar 가 아니라 OOS 다.** A 까지의 거리를 막는 축이 **1,105/1,193칸에서 OOS** 다. 필요한 개선 폭은 최고 계보 기준 **Calmar +0.16 과 OOS +0.36 동시**이고, 관측된 블록 최고 arm 의 ΔCalmar 중앙값은 +0.013~+0.026 이다.

**② OOS 벽의 실체가 특정됐다** — PT≥2 이고 고정 축을 지킨 157칸의 K200 대비 일간 활성 IR 중앙값:

| 구간 | 활성 IR 중앙값 | 양수 칸 비율 |
|---|---|---|
| 2005~16 | **+1.38** | 100% |
| 2017~20 | **−0.46** | **2%** |
| 2021~24 | +0.72 | 97% |
| 2025~26 | **−0.88** | **3%** |

두 시기에 **거의 모든 칸이 같은 부호를 공유한다.** 즉 OOS 붕괴는 칸별 과적합이 아니라 **공통 활성수익 성분**이다. 최고 칸의 구간별 값(1.53 / −0.46 / 1.22 / −0.40)은 감사가 재계산해 일치시켰고, 2026년 벤치의 연 변동성 67.3%·하루 5% 초과 변동 40일은 실제 시장으로 이미 확인됐다(결정 `BENCH-2026-VOL-OK`) — 이상치로 빼지 않는다.

**③ 전주까지의 서술 하나가 전수 데이터로 기각됐다.** "2018~20 낙폭은 어떤 레버도 못 움직인다" → **기각**. Σw=1 칸 중 **43칸(11계보)** 이 낙폭비 1.145 미만이고, PT≥2 부분집합에서 ρ(Calmar, 낙폭비) = **−0.30** 이다. 올바른 서술은 **"이 낙폭은 알파 원천과 한 몸이다"** 이다(감사 §②·§⑤).

**④ 선택 규칙으로는 A 가 안 나온다.** 사후에 오라클처럼 골라도 두 구속 축을 함께 올리는 지표가 없다(Calmar argmax 는 Calmar 0.355→0.373 이지만 OOS −0.23→−0.42). 규약 교정에서 **PT argmax 칸이 28 entry 중 23곳에서 entry 중앙값보다 더 깎였다 — 승자 인플레**.

**⑤ 우선순위 레버**(감사 §③ 상위 2건, 전부 봉투-안):
1. **P2-02 `tilt_attribution.R`** — 칸마다 [시장 · EW−CW · 틸트 · 선별]로 활성수익을 분해하는 계기. 파일 부재 확인. A 에 직접 기여 0 이지만 **L1 판정의 전제**.
2. **PR-L1 `cap_core`**(벤치 인지 비중) — 카탈로그 52 arm 중 **벤치 인지 arm 0** 인 유일한 빈 유형. 사전등록 필수 + IS 활성 IR 변화 보고 의무. 플랜 사전확률 기전 60% · 성공 10% · A 3%.

★ 감사 §⑤ "하지 말 것"이 이번 주 서술 규율을 정했다: 같은 격자 더 돌리기 · 선택 지표 교체를 A 레버로 보고 · **옛 규약 수치 인용** · IS 활성 IR 없이 OOS 개선 보고(retention 분모 게임) · B5_31 재측정 요구(C11 격리 칸) · 미결을 '벽'으로 적립.

### 2c. A 자격 관문에 보류 코드 2종 신설

`06_Registry/a_eligibility_gate.json`(P0-12·P0-13 · 2026-09-24~25):
- **`legacy_regime`**(active) — 칸의 `measurement_regime.regime/exec_price` 가 현행 `constraint_defaults.json::execution.exec_price` 와 다르면 그 A 는 현행 규약의 A 가 아니다. 판독 불가 = 보류.
- **`vintage_flag`**(active · flags `*` · verdicts `consumed`/`consumed_absence`/`possible`) — 표식 칸의 A 는 데이터 빈티지 확정 전까지 발행하지 않는다.
- 비활성 3종: `sigma_w_lt_1`(결정 D-D — Σw=1 은 위험자산 정규화로 해석, 오버레이 현금과 양립) · `dossier_pending` · `rule_pending`(결정 D-B · 플랜 비평 M9 — 서류·규칙 대기로 A 를 무기한 막지 않는다).
- 충실구현 경로 회계 요건이 분리됐다(P0-13): 강화 = `sweep`, **충실구현 = `chain`/1** — 강화 요건을 빌리면 모든 충실구현 A 가 보류된다.

★ 이번 주 **Grade A 0건 · Judge 스폰 0건**(`06_Registry/grade_a_queue.json` 부재 · `judge_request*.json` 산출물 0건 · L2 원장 `judge.spawned=false`).

---

## 3. 1계층 강화 — 7계보 · 신 규약 전환 전후

이번 주 실측 칸은 **7계보**에서 났다. 아래 블록 표는 전부 **구 규약(`close_d_legacy`)** 판이다 — §2b 의 신 규약 집계와 섞어 읽으면 안 된다.

### 3a. 계보 A — `RP_20260917_105807_22632_combo_rulefast` promo1→promo4 (6편 결합 계보, 09-19~09-21)

| 세대 | 블록 | 칸 | 최고 셀 | PORT_t | Calmar | 등급 분포 | L-code |
|---|---|---|---|---|---|---|---|
| promo2 | B1 | 10 | B1_2 | **3.806** | 0.490 | **A0/B10/C0/F0** | `L-RF-20260920_005108` |
| promo2 | B5 | 7 | B5_16 | 3.750 | 0.486 | A0/B6/C1/F0 | `L-RF-20260921_081957` |
| promo2 | B2 | 8 | B2_12 | 3.612 | 0.478 | A0/B8/C0/F0 | `L-RF-20260921_085253` |
| promo2 | B6 | 3 | B6_32 | 3.078 | 0.420 | A0/B3/C0/F0 | `L-RF-20260921_093812` |
| **promo3** | **B1** | 10 | **B1_3** | **4.349** | **0.501** | **A0/B10/C0/F0** | `L-RF-20260921_102142` |
| promo3 | B5 | 8 | B5_20 | 4.143 | 0.496 | A0/B7/C1/F0 | `L-RF-20260921_110617` |
| promo3 | B2 | 8 | B2_11 | 4.094 | 0.476 | A0/B8/C0/F0 | `L-RF-20260921_114215` |
| promo3 | B6 | 5 | B6_36 | 4.089 | 0.468 | A0/B5/C0/F0 | `L-RF-20260921_121226` |
| promo4 | B1 | 10 | B1_1 | 4.167 | 0.494 | A0/B10/C0/F0 | `L-RF-20260921_143005` |
| promo4 | B6 | 5 | B6_36 | 4.153 | 0.492 | A0/B5/C0/F0 | `L-RF-20260921_160505` |

entry `..._promo4` : `attempts_used 33` · `max_attempts 36` · `exhausted_at 2026-09-21T16:28:05`(원장 `reinforce_ledger_l1.json:16568`·`:21942`·`:21974`). 계보가 닫혔다.

- **구 규약 프로그램 최고 PORT_t 3.592 → 4.349**(promo3 B1_3). **신 규약으로 다시 재면 같은 칸이 3.777 · Calmar 0.433** 이다(§2b). 규약 교정이 이 계보에서 PT 를 −0.57 깎았다.
- B1 블록이 **세 세대 연속 10칸 전부 B**(A0/B10/C0/F0)를 냈다. 그런데 A 는 0 이다 — B 는 흔해졌고 벽은 다른 곳에 있다.
- 기전(promo4 B1 · `L-RF-20260921_143005::mechanism`, 구 규약): **"5번째 팩터 교체는 위험 축을 못 움직인다."** 10칸 전부 MDD 0.541~0.568(폭 **0.027**) · Calmar 0.449~0.494(폭 0.045) 안인데 PORT_t 는 3.770~4.167(폭 **0.397**)로 벌어진다. 위험 축을 건드린 유일한 후보도 상쇄됐다 — `CR07_Momentum_Crowding`(B1_6)이 블록 최저 MDD 0.541 을 냈지만 CAGR 0.273→0.261 로 같이 내려 Calmar 0.484 < B1_1 0.494. **2팩터 추가는 부분가법적** — B1_8(4.140)·B1_9(3.949)·B1_10(3.770) 셋 다 단일 추가 최상단 B1_1(4.167)을 못 넘고, 단일 상위 둘을 함께 넣은 B1_10 이 블록 최저다. 미결로 남긴 것: **순위 희석인지 결측 패턴 교체(inner join 통로)인지** — 추가 팩터별 보유 교집합·결측률을 재야 갈린다.

### 3b. 계보 B~E — 구 기저 재개 4건 (09-21~09-23)

| 계보 | 창 | 대표 블록 최고 | 비고 |
|---|---|---|---|
| `RP_20260831_204546_skipped_base` | 09-21 12:47~20:12 | B6_35 t 1.894 · Calmar 0.318 | `attempts_used 42` = `max_attempts 42` · `exhausted_at 2026-09-21T20:12:04` |
| `RP_20260904_102326_skipped_base` | 09-21 20:47~23:29 | B4_25 t 1.546 · Calmar 0.407 | `attempts_used 44` · **B7 첫 등장**(B7_37 t 1.116 · 0.262) |
| `RP_20260912_212323_skipped_base` | 09-22 00:35~02:47 | B6_42 t 2.399 · Calmar 0.413 (A0/B4/C1/F0) | B5_18 t 2.305 · 0.364 |
| `RP_20260913_084807_skipped_base` (+`_promo1`) | 09-22 03:25~09-23 21:39 | **promo1 B1_1 t 3.402 · Calmar 0.543** (A0/B6/C1/F0) | 이번 주 **구 규약 최고 Calmar** |

**계보 E promo1 B2 기전**(`L-RF-20260923_212816::mechanism`, 9칸, 구 규약 · `mechanism_confidence: high`) — 이번 주 가장 잘 분리된 판정이다:
- **갈린 것은 목적함수이지 Σ 추정기가 아니다.** 목적함수를 `score_tilt` 로 고정하고 추정기만 가른 3칸(shr_sample 3.152/MDD 0.486 · ledoit_wolf 3.169/0.495 · gerber_rmt 3.105/0.494)의 PORT_t 폭은 **0.064**, 목적함수를 가른 칸의 폭은 **1.133** — **18배**.
- 정렬이 **비대각 소비량에 단조**다: ivol 3.294/0.486 ≈ riskparity 3.242/0.486 > score_tilt 3칸 > nco 2.884/0.525 > minvar 2.161/0.529. **분산을 더 줄일수록 PORT_t 가 빠지고 MDD 는 오히려 올랐다 — 분산 최소화는 낙폭 최소화가 아니다.**
- 전체 Σ(riskparity) 대 대각만(ivol) 차이 = PORT_t 0.052 · Calmar 0.002 · **MDD 0.000** — 상관 정보의 배분 지점 기여 ≈ 0.
- 실현 낙폭 경로 정보(CDaR_LP)는 **두 번째 소비 지점에서도 열위**(MDD 0.571 · Calmar 0.378, 블록 최악). 총노출 지점 B5_16(MDD 0.615)과 방향이 같다 — **지점을 바꿔도 같으므로 실패는 소비 지점이 아니라 정보에 귀속된다.**
- 설계 8건 중 **8건 집행**(`prior_action_status: executed`).

### 3c. 계보 F·G — 신규 논문 2편의 격자 (09-24~09-25)

`RP_20260923_230819_4212_adapted_rulefast`(2511.12129) · `RP_20260924_052517_7308_adapted_rulefast`(2202.05702). 둘 다 기저가 낮아 격자도 낮다.

- F 계보 B2(8칸 · `L-RF-20260924_034311`, 구 규약): 최고 B2_9 t 0.676 · Calmar 0.254 · **A0/B0/C8/F0**. 기전 — **7칸 전부 동일가중 기저 B1_3(PORT_t 0.763)을 못 넘었고**, 비대각 공분산 계열이 최하위 3칸을 나란히 점유(hrp 0.156 · maxdiv 0.109 · minvar −0.042). 설계 의도 4개 중 **3개가 반증**됐다: 낙폭 경로를 직접 표적한 CDaR_LP 가 블록 차상위 MDD 0.591, 최저 MDD 0.531 은 위험을 전혀 표적하지 않은 score_tilt.
- G 계보 B6(5칸 · `L-RF-20260924_070403`, 구 규약): 최고 B6_36 t 1.331 · Calmar 0.277 · A0/B0/C5/F0. 기전 — **이 격자에서 처음으로 PORT_t 와 MDD 가 같은 방향으로 함께 움직였다.** PORT_t 순서(1.240 > 0.902 > 0.892 > 0.756 > 0.390)가 CAGR 순서와 완전히 일치하고 MDD 순서(0.583 < 0.601 < 0.607 < 0.629 < 0.682)와도 한 쌍만 어긋난다. **B6_34 MDD 0.682 가 앞선 21칸 상한 0.665 를 처음 넘겼다** — "구성을 안 바꾸니 MDD 범위를 벗어날 근거가 없다"던 B3 처방이 반증됐다. 미결: 처치 열이 5칸 동일이라 −0.767 중 집행 축 몫과 승계 차이 몫이 안 갈린다.
- G 계보 B7(5칸 · `L-RF-20260925_233320`, 구 규약): 최고 B7_41 t 1.026 · Calmar 0.247 · A0/B0/C5/F0 · oos_retention 최고 **−0.647**.

★ 감사 §② 는 **B7 을 "처치 오지정이라 판정 없음"** 으로 분류했다(ΔCalmar −0.065 · P>0 0.00). B7 과거 칸을 as-of 규칙으로 "재측정"하는 것도 금지 목록에 있다 — 새 규칙이면 새 칸이다.

### 3d. 레인 가동 — 정지 1회, 재개 1회

`06_Registry/reinforce_auto_config.json:5`:
- **정지**: 2026-09-24 10:2x 도훈 지시 **"무인 1계층 리서치는 멈춰줘"** — PIT C11 봉쇄·수리.
- **재개**: 2026-09-25 21:3x — 결정 `RUNNER-RESTART-AFTER-P0-14` · `RUNNER-RESTART-RELAX`. 선행 배포: P0-05/06 epoch `exec_v2_close_t1` · C11 2단계 · P0-08/09 · M1M2 · P0-13 · R2 · B08 상한 · B5M.
- **B5 설계 레인 봉쇄 1회**(`b5_design.paused_reason_20260925`): 09-25 22:58 — **B5LAB 배포 전 라벨 노출 재료로 설계가 돈 사고**(21:58 · 7308 B5_16~20 → `possible` 표식). 23:4x 복원. 생성 세션 성과 열람 차단 훅(`arm_gen_read_guard`)이 다루는 바로 그 경계다.
- 실측 칸이 난 날: 09-19·09-20·09-21·09-22·09-23·09-24·09-25 — **7일 중 7일**(전주 3일). 다만 09-24 07:00~09-25 22:16 은 C11 봉쇄로 **약 39시간 공백**이다.

---

## 4. 2계층 — **5주 만의 재가동, 그리고 같은 주에 무효 표식**

전주 digest 가 "2계층 0건"으로 적었던 레인이 이번 주 돌았다. 그리고 하루 뒤 PIT 로 묶였다.

### 4a. FR_003 n=1 — T/S/C 3 arm 실측 (2026-09-23 17:42~18:40)

`06_Registry/reinforce_ledger_l2.json`(entry `FR_003` · attempt n=1 · cell_code `L2_TSC` · `evidence: none` · selection_type `sweep`):

| arm | 설계 | 모듈 풀 | net_SR | **EW 기저 SR** | **edge_vs_ew** | PORT_t | Calmar | CAGR | MDD | oos_retention | DSR | 등급 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **T** π₀ 등재 | `FR_003_n1` | 561 | 0.805 | 0.848 | **−0.043** | 1.437 | 0.357 | 14.7% | 41.1% | −0.410 | 0.077 | **C** |
| **S** lag+1 PIT 스트레스 | `FR_003_n1_S_lag1` | 561 | 0.796 | 0.848 | **−0.052** | 1.296 | 0.352 | 14.3% | 40.6% | −0.485 | 0.064 | **C** |
| **C** floor-only 대조 | `FR_003_n1_C_flooronly` | 272 | 0.926 | 0.958 | **−0.032** | 1.967 | 0.419 | 17.3% | 41.3% | −0.181 | 0.262 | **C** |

출처: `stage_artifacts/l_code/factor_rotation/l_code_FR_003_n1{,_S_lag1,_C_flooronly}.json`(L-FR-20260923_180623 · 182924 · 184043) · 원장 `reinforce_ledger_l2.json:32~76`.

**세 arm 전부 EW 기저에 진다.** 국면조건부 모듈 배분이 같은 풀의 동일가중 앙상블보다 나은 구간이 이 실측에는 없다(edge −0.032 ~ −0.052). `falsification_attempts` 는 OOS retention 을 세 arm 모두 `falsified` 로 기록했다(−0.181 ~ −0.485, gate 0.7 · 하한 0.5).

세 arm 이 각각 답한 것:
- **S(lag+1)**: T 대비 SR −0.009 · PORT_t 1.437→1.296. **붕괴하지 않았다** — C5 동월누출 스트레스는 통과다. 다만 기저에 edge 가 없으므로 이 통과는 판정을 바꾸지 않는다.
- **C(floor-only 272모듈)**: PORT_t 1.967 로 T(1.437)보다 **+0.530**, Calmar 0.419 > 0.357. 원장 lessons 가 귀속을 적었다 — **"방어형 재고 귀속: 희석(방어형이 알파를 깎았다)"**. 그런데 같은 arm 의 EW 기저도 0.848→0.958 로 같이 올랐고 edge 는 여전히 음수(−0.032)다. **풀 품질이 두 값을 함께 밀었을 뿐 배분기는 여전히 값을 못 냈다.**
- MC1 전달 `true` · `mc1_jaccard` 0.3068 · `pool_truncated` false.

### 4b. 같은 결과가 하루 뒤 PIT 무효 표식을 받았다

`reinforce_ledger_l2.json:104~110`(attempt) · `:119~128`(base) — `flag: pit_c11` · `verdict: consumed`:

> V-05 `regime_signal.R:806-850` FRED_MRS 같은 날짜(+NFCI 최대 5일 · FEDFUNDS 월초 LOCF) → Category · V-06 `run_wf_ensemble.R:85-91` 1행 lag Category 로 홀딩월 배분(한국 t−1 종가 뒤 미국 t−1 세션) — **T/S/C 세 arm 공통**. 풀에 pg2 오버레이 B 모듈 포함(V-02). **S_lag1 판도 같은 라벨·풀이라 청정판 아님.**

정책은 `등급·essence 불변 · 결과 무효 표식`(pit.md 위반 시 처리 2단계). 재측정은 도훈 결정(`PIT-C11-REMEDIATION` = 안 B 승인)의 표적 재빌드 뒤다. 추가 표식 2건: `fdb_202608_v1`(possible) · `fdb_inv13_absent`(possible — 풀 561 중 5모듈이 INV13 결손으로 08-31 신호일을 잃은 칸).

★ **이 주의 교훈은 순서다.** 2계층이 5주 만에 돌아 세 arm 을 냈고, 그 세 arm 이 전부 EW 에 지는 정직한 음성을 냈는데, **그 음성조차 인용할 수 없다** — 국면 라벨 경로 자체가 오염이기 때문이다. 판정서 §③도 같은 말을 한다: 오버레이 후보 22건이 전부 기각됐지만 "오염된 신호 위에서 잰 결과라 **깨끗한 음성으로 인용하면 안 된다**".

---

## 5. 1계층 충실구현 — 논문 2편, A·B 0건

| 논문 | run_id | 등급 | PORT_t | oos_retention | L-code |
|---|---|---|---|---|---|
| **2511.12129** A Practical Machine Learning Approach for Dynamic Stock Recommendation | `20260923_221734_6636` | **F** | 미기재 | — | `L-RP-20260923_222438`(논문기준 SR 0.45 vs 15bps 0.54) |
| 同 (판2) | `20260923_230819_4212` | **C** | 0.021 | −1.113 | `L-RP-20260923_231445`(0.61 vs 0.71) |
| **2202.05702** Machine Learning for Stock Prediction Based on Fundamental Analysis | `20260924_043231_17572` | **C** | 미기재 | — | `L-RP-20260924_043703`(0.54 vs 0.60) |
| 同 (판2) | `20260924_052517_7308` | **C** | 0.085 | −1.169 | `L-RP-20260924_052943`(0.47 vs 0.56) |

출처: `stage_artifacts/l_code/paper_replication/l_code_RP_2026092*.json`.

두 논문 다 ML 선별형이고 두 판 다 C 에서 멈췄다. `oos_retention` 이 −1.1 대로 나온 것이 §2b 의 OOS 벽(2025~26 활성 IR 중앙 −0.88 · 양수 칸 3%)과 같은 방향이다 — 다만 **이 둘은 서로 다른 측정이므로 인과로 잇지 않는다**(정황).

---

## 6. 코퍼스 위생 — L-code 1,106건 재라벨

2026-09-23, `stage_artifacts/l_code/paper_replication/` 의 **1,176건 중 1,106건(94.0%)** 이 재라벨됐다:

```json
"research_mode": "reinforcement_cell",
"relabeled_from": "paper_replication",
"relabeled_at": "2026-09-23",
"relabel_reason": "강화 셀이 충실구현 L-code 로 오발행(감사 D6-03 · 플랜 P0-M3)"
```
(표본 `l_code_RP_20260923_161713_28512.json:9~12` · 실측 = 디렉터리 grep 1,106/1,176)

**이것이 DIST 후보 층에 직접 닿는다.** 이번 주 초안 대상 8건 중 `family=paper_replication` 로 표기된 3건(GEN-306 supporting 1,172 · GEN-245 994 · GEN-314 67)의 supporting 목록은 실제로는 `RF_PAR_B*` **강화 격자 셀**이 대부분이다. 즉 그 후보들의 모집단 라벨이 낡았다 — 라벨 기준으로 집계해 만든 "방법론 규칙"은 모집단 정의부터 다시 세워야 한다(각 초안의 적대검증 (b) 에 명기, § 결과 JSON).

남은 70건이 진짜 충실구현 기록이다.

---

## 7. 공리 사이클 현황 (의무 절)

### 7a. 집계

| 항목 | 값 | 전주 | 출처 |
|---|---|---|---|
| 후보 총계 / pending | **123 / 123** | 120 / 102 | `axiom_candidates` |
| **활성 공리(전체)** | **4 — global 만**(AX-000·001·002·008) | 4 mode-local + global | `qepm/memory/axioms/active/` 실측 |
| **mode-local 활성** | **0** | 4 | 同 |
| 이번 주 신규 활성화 | **0** (HOLD) | 0 | `activated_axioms: []` |
| 이번 주 신규 정제보류(HELD) | **0** | 0 | `held_axioms: []` |
| 상시 HELD(후보 측) | **12** | 15 | `preview` 집계(`refine_verdict: HELD`) |
| REFINED(후보 측) | **5** | 4 | 同 |
| pending_5axis 백로그 | 111 (최고령 80일 · `DIST-AR-005`) | 108 (73일) | `pending_5axis` |
| 5축 실패 히스토그램 | independence **80** · external **65** · falsification **54** · mechanism 49 · rigor_research 5 | 68/54/42/49/5 | `failing_axis_histogram` |
| 격리 증거 | 6 | 6 | `n_quarantined_evidence` |
| promote crash / skip | 0 / 0 | 0 / 0 | `axiom_candidates` |

### 7b. ★ 3주 교착이 활성화가 아니라 **폐지**로 풀렸다 — mode-local 19건 전량 rollback

2026-09-23, 도훈 결정 `AX-D1-FREEZE` · `AX-D2` · `AX-D3-MODELOCAL`(판정서 wf_d8ee80de-26d ⑤)으로 **mode-local 공리 19건이 전량 `deprecated/AX-*_rollback_20260923.json` + tombstone 처리**됐다(AR 4 · AS 3 · JG 1 · QPM 5 · RAMP 6 = 19 · 실측 디렉터리 스캔). 근거 L-code 는 무접촉이다.

- **무인 활성 기본 OFF** — `QVEST_AXIOM_UNATTENDED` 기본 0. 활성화는 `approve_axiom(ids, approved_by='dohoon')` 수동 경로뿐.
- **강화 기억은 P3 `rf_lessons` 로 일원화**(AX-D2 — 4번째 기억층 금지).
- 전주 digest §7 이 "active 원장 4(AX-AR-002·AX-AR-004·AX-RAMP-005·AX-RAMP-006)"로 적은 그 4건이 이 rollback 에 포함된다. **전주가 "도훈 결정 대기"로 남긴 항목은 활성화가 아니라 층 폐지로 종결됐다.**
- global 2건도 문언이 개정됐다(`AX-D5-TEXT`): AX-001 v3(방어형 판정 계약 = `defensive_score`) · AX-008 v2.0(수치는 R 계약 산출만 · 손계산 금지).

### 7c. 정제보류(HELD) 12건 — **사유 명기**

후보 측 HELD 는 그대로 12건 남아 있고, 그 공리 측 쌍둥이는 위 rollback 으로 이미 닫혔다. 사유는 rollback 기록의 `refine_failing` + `rollback_reason` 실값이다.

| 후보 cluster_key | 공리 쌍둥이 | 미달 축 | 폐기 사유(rollback_reason 실값) |
|---|---|---|---|
| `53e4aad1fbc2` | AX-AR-001 | `R0_polarity` | positive 라벨인데 실제 w1/l5 · DIST-AR-021 쌍둥이(K6) |
| `9cc9cfc93922` | AX-AR-003 | `R0_polarity` | positive 라벨인데 실제 w1/l12(K6) |
| `9053df8e65f9` | AX-AS-002 | `R1_members`·`R4_falsification` | DIST-AS-002 가 07-04 TAINTED 로 격리한 클러스터를 08-23 에 되살림 · 근거 381/507 부재 · 반증 0(K6) |
| `576b3cecd1e4` | AX-JG-001 | `R5_revival` | 판별자 `tag:BASE_DIR_MISSING`(인프라 장애) · short-side 귀속(INV-7) |
| `5c15885d429f` · `6193f0d3ac54` · `a4ed5d6c37c2` · `c487433156b2` · `c9cf9368331a` | AX-QPM-001~005 | `R5_revival` 4 · `R4_falsification` 1 (`a4ed5d6c37c2` near_miss 0.774 = falsification) | mode-local 층 폐지(AX-D2) · 개별 사유는 각 `deprecated/AX-QPM-00N_rollback_20260923.json::rollback_reason` |
| `4253c52866e1` · `5f3bdccc164d` · `ad0cd8e7e47d` | AX-RAMP-001~004 계열 | `R1`·`R2_tokens`·`R4`·`R5`·`R6` 혼재 | 同 |

REFINED 5건(`894c7d3df737`=AX-AR-002 · `f94d3e05f0b0`=AX-AR-004 · `de25bf409841`=AX-AS-003 · `c4308a214e2b` · `f70fa9d382ed`)도 공리 측은 전부 rollback 됐다. AR-002 폐기 사유 = "판별자 = 측정 계기(`metric:canonical_screen`) · mechanism(insider)↔family(overlay) 불일치(K5)", AR-004 = "family=infra_process · n=2 · **발행기 상수(`rf_block_lcode metric_type='backtested'`) 인공물 계열**", AS-003 = "proxy win 라벨(계약 재측정 PORT_t≥2.95 **0/41**) · 기전 n=1".

★ **전주 §7b 가 지배 축으로 지목한 `R5_revival`·`R4_falsification` 은 입력 결함이 아니라 후보 자체의 결함이었다.** rollback 사유 다섯 건이 "positive 라벨인데 실제는 loss", "판별자가 인프라 장애 태그", "발행기 상수 인문물", "proxy win 라벨인데 계약 재측정 0/41" 을 적는다 — 게이트가 엄격했던 게 아니라 **후보가 채점 가능한 명제가 아니었다.**

### 7d. HOLD 사유 해부 — 이번 주는 활성화를 막지 않았다

`activation_hold` 실값: `inject_len 1990` · 기준 1900 · basis `worst_header_render(n=8)` · `inject_len_last_spawn 1939` · `dry_run_crash 0`. 헤더 조합별 길이 = judge+reinforce **1990**(최악) · forge+reinforce 1978 · book+reinforce 1977 · zz-default 1939. **8조합 전부 `pc_status: ok`.**

`action` 문자열이 전제를 스스로 정정한다: "★`QVEST_AXIOM_UNATTENDED` 는 이 HOLD 와 별개 — 기본 0=OFF 라 무인 활성은 이미 0건이고 활성화는 `approve_axiom(...)` 수동 경로뿐. **0 으로 둔다고 쓰기가 보류되지 않는다.**"

즉 HOLD 가 실제로 중단시킨 것은 **promote 쓰기(proposed 발급·review_log·MAP)** 이고 활성화가 아니다. 그리고 `n_new_active_planned = 0` 이므로 이번 주에 막힌 활성화는 0건이다. **도훈 결정이 필요한 것은 "활성화 3건이냐 4건이냐"가 아니라 주입 예산 2,000 대비 헤더 렌더 1,990 을 어떻게 내릴 것인가**다(마커 3종 생존 = health HARD_10 요건).

### 7e. DIST 자동초안 — 8건 → `proposed` (§ 결과 JSON)

pending_5axis 111건 중 supporting 상위 8건(격리 6건 제외)에 `statement_refined` + 적대검증 5체크(a~e)를 부여했다. 전부 `proposed` 까지다 — 주입 스트림에 들어가지 않는다(활성화는 도훈 권한, INV-6).

**★포함 관계가 전주보다 더 굳었다.** GEN-245(994) ⊂ GEN-306(1,172) — 둘 다 `overlay_regime`. GEN-292(120) ⊂ GEN-308(125) — 둘 다 b1. GEN-105(22) ⊂ GEN-217(33) — 둘 다 b3. **8건 중 6건이 3개 모집단의 시점 슬라이스**다(전주 8건 중 6건과 같은 병). 각 초안에 포함 관계와 통합 권고를 명시했다. 근본 수리는 증류기가 같은 코퍼스의 시점 스냅샷을 새 후보로 찍지 않게 하는 것이고 본 증류 범위 밖이다.

여기에 올해 새로 생긴 결함 둘이 더 있다: ①`family=paper_replication` 라벨 낡음(§6) ②supporting 목록의 근거가 전부 **구 규약** 판이라 감사 §⑤ 금지 목록("옛 규약 수치 인용")에 걸린다. 두 결함을 각 초안의 (b) 항에 적었다.

---

## 8. 잔재 처리 (의무 절 — 삭제·거부 요약)

### 8a. 기계 스윕 삭제 2건

매니페스트 `.cache/hygiene_manifest.log:1602~1603`(2026-09-26 10:30:05) — **둘 다 `weekly_log30d`**:
`C:/Users/99922/AppData/Local/Temp/qvest_v8_ready_stderr.log` · `/tmp/qvest_hook_router_dispatch.log`.

`weekly_cache_scratch_7d` 는 **빈 배열**이고 `hygiene_audit_deleted_n = 0` 이다 — 이번 주는 실질 삭제가 임시 로그 2건뿐이다(전주 8건).

전주 digest §8b 가 삭제 제안한 4건(`run_spec_lowfreq_mass.R`·`run_fx_intensity.R`·`run_within_sector_reversal.R`·`run_vol_hurst.R`)은 **매니페스트 1597~1600 에 2026-09-19 22:26:02~22:26:13 `weekly_distill_llm` 로 집행 완료**됐고 이번 주 후보 목록에 다시 나타나지 않았다. 제안-집행 레인은 정상이다(전주 §8a 의 판정이 두 주 연속 유지).

### 8b. 세션 판단 — 후보 8건 중 **1건 삭제 제안 · 7건 보류**

| 항목 | 판정 | 사유 |
|---|---|---|
| `run_as_queue_20260806.R` (21.3KB · 50.6일 · 참조 0) | **삭제** | 파일 머리말이 스스로 일회성임을 적는다 — "alpha-search 큐 소비자 (2026-08-06, MAX_ALPHA=2) / 대상: FQ-149(FX_Intensity) + FQ-092(VolRankReverse)". 날짜·대상·상한이 전부 박힌 **1회용 드라이버**이고 상시 레인은 `02_Infrastructure/ops/auto_spawn_queue.R`·`reinforce_auto_*` 가 대체한다. `02_Infrastructure/` 참조 실측 0건. 전주 "도훈 확인 후" 보류 뒤 한 주 더 참조 0. git 이 사료를 보존하므로 루트 제거 = 소실 아님 |
| `0.20` (참조 766) · `25` (참조 3,986) | 보류 | 짧은 숫자 리터럴의 **이름 충돌** — '쓰인다'가 아니라 '이름이 겹친다'. 기계가 어차피 거부한다 |
| `Rplots.pdf` (0.5일 · 참조 1) | 보류 | 24h 가드 내 · 유일한 참조가 `cleanup.sh` 자신. 4주째 같은 자리 — 발생원(R 그래픽 디바이스 자동 산출)을 막지 않으면 매주 재생성된다 |
| `cid_smoke.rds` (5.5MB · 참조 2) | 보류 | `RP_2301_09173_CID/NOTES.md`·`diag_cid_market_comovement.R` 실참조(진단 자산) |
| `x.rds` (참조 4) | 보류 | `cleaner_distill_lib.R`·훅 테스트·`test_frontier_queue_io.R` 픽스처 |
| `downloads/` (참조 5) | 보류 | `paper_router_run.sh`·DART census 실참조 |
| `02_Infrastructure/ast/tests/parity_factor_db_result.json` (참조 2) | 보류 | 패리티 테스트 + 연산자 백로그 실참조. `misplaced_outputs` 경고는 위치 문제이지 사멸이 아니다 |

★ 판정 근거는 기계 재도출이다(보호목록 · git grep 참조0 · 24h · 상한). 위 사유는 사람이 읽을 판단 근거다.

---

## 9. 이번 주 요지

1. **PIT 가 알파보다 먼저 왔고, 그게 맞았다.** 해외 시계열의 가용시점 규약 부재가 C11 위반으로 확정됐다(14지점 · 등급 도달 경로 3개 · L1 최대 35칸 · 2계층 FR_003 전체 · BOOK_0001 게이트 · **A칸 0 · 충실구현 0**). 조사→판정→봉쇄→도훈 결정(안 B 후 안 C)이 한 주 안에 닫혔고, 봉쇄 자체가 적대검증에서 한 번 뚫려(샌드박스 E2E 에서 3변형 ADMIT) 정규식 18개로 수리됐다. 방어선이 못 잡은 이유는 전부 같다 — **양성 대조가 없는 계기였다**(`pit_verify_fred_lag` 는 무조건 TRUE 에 호출부 0, `lookahead_detector:236` 은 "Macro/regime lookups are OK"라는 코드로 굳은 합리화). 남은 미이행은 BOOK 트래킹 C11 표기 하나다(§1d).
2. **구속 축이 Calmar 에서 OOS 로 옮겨갔고, 그 벽의 실체가 특정됐다.** 신 규약(`close_t1`)으로 1,187/1,222칸을 다시 재니 A 0 · Calmar ≥0.64 **0칸** · 최고 칸도 PT 3.777/Calmar 0.433(Grade B)이고, **1,105/1,193칸에서 A 를 막는 축은 OOS** 다. 그 OOS 붕괴는 칸별 과적합이 아니라 2017~20(활성 IR 중앙 −0.46 · 양수 2%)과 2025~26(−0.88 · 3%)에 **거의 모든 칸이 공유하는 활성수익 성분**이다. 동시에 전주까지의 서술 하나가 전수로 기각됐다 — "2018~20 낙폭은 어떤 레버도 못 움직인다"는 틀렸고(43칸·11계보가 낙폭비 <1.145), 옳은 서술은 "이 낙폭은 알파 원천과 한 몸이다". 다음 수는 격자를 더 도는 것이 아니라 **계기 먼저**(P2-02 `tilt_attribution.R`)이고, 그 위에서 격자의 유일한 빈 유형인 **벤치 인지 비중(PR-L1 `cap_core`)** 을 사전등록으로 반증하는 것이다.
3. **정직한 음성 하나를 얻었는데 인용할 수 없다 — 그리고 공리 층의 3주 교착은 폐지로 풀렸다.** 2계층이 5주 만에 돌아 FR_003 T/S/C 세 arm 을 냈고 **셋 다 EW 기저에 진다**(edge −0.032~−0.052 · OOS retention 세 arm 전부 falsified). lag+1 스트레스는 붕괴하지 않았다. 그런데 국면 라벨 경로 자체가 C11 오염이라 이 음성은 "깨끗한 음성"이 아니다 — 재측정은 안 B 표적 재빌드 뒤다. 한편 공리 층에서는 3주 연속 HOLD 에 묶여 있던 mode-local 19건이 **활성화가 아니라 전량 rollback** 으로 종결됐고(AX-D1/D2/D3 · 활성 공리 = global 4건만), rollback 사유들이 그 교착의 정체를 적는다 — 게이트가 엄격했던 게 아니라 후보가 채점 가능한 명제가 아니었다("positive 라벨인데 실제 w1/l12", "발행기 상수 인공물", "proxy win 인데 계약 재측정 0/41"). 남은 HOLD 는 활성화 수가 아니라 **주입 예산 1,990/2,000** 이다.

---

**증류 산출물**: 본 digest · `.cache/cleaner_distill/2026-W39/distill_result.json`(DIST 초안 8 · 신규 L-code 2 · 삭제 제안 1 · 보류 7)
