# Weekly Digest — 2026-W37 (2026-09-06 ~ 09-13)

**작성**: 2026-09-13 (Q / 주간 증류 · owner=`auto_distill` · claimed 2026-09-13 07:30:10)
**기계 스윕**: 2026-09-12 16:52:47 (`02_Infrastructure/ops/weekly_cleaner_sweep.R`, `dry_run=false`, 삭제 27건)
**수집 창**: 직전 스윕 이후 지난 7일
**출처**: `.cache/cleaner_pending.json`(schema `cleaner_pending_v2`) · 각 런의 `stage_artifacts/replication/<run_id>/authoritative_remeasure.json`·`06_metrics.csv` · `04_Research/strategies/RP_AUTO_*/fidelity_audit.json` · `06_Registry/reinforce_ledger_l1.json` · `stage_artifacts/l_code/*`
**수치 규약**: 등급은 `authoritative_remeasure.json::essence_grade` 만 인용(손계산·재구성 없음). 블록 요약 t·Calmar 는 해당 `L-RF-*` 기록. 값이 없는 축은 "미측정".

> ⚠ **활성화 HOLD 재발동 — 2주 연속** (`axiom_candidates.activation_hold.held_at 2026-09-12T17:06:04`). 사유는 지난주와 **동일 문자열**("신규 활성 예정 4건 > WEEKLY_ACTIVATION_MAX 3")이고 would_activate=true 인 후보 4건도 **지난주와 같은 4건**이다. 이번 주 신규 활성화 = **0건**. 도훈 결정 없이는 다음 주도 같은 자리에서 멈춘다(§3a).

---

## 0. 주간 볼륨 (실측 — `.cache/cleaner_pending.json`)

| 항목 | 값 | 출처 키 |
|---|---|---|
| 스윕 삭제 | 27 | `sweep_deleted_n` |
| stage_artifacts 신규 | 207 | `inventory.stage_artifacts_new.n` |
| 신규 L-code | 190 | `inventory.new_lcodes.n` |
| 커밋(7일) | 144 | `inventory.git_log_7d.n_commits` |
| hypothesis_index | 2,110 (전주 1,865 · Δ+245) | `inventory.hypothesis_index` |
| 위생 경고 | 243 (감사 삭제 1) | `sweep_detail.hygiene_n_warnings` |
| L-code 무결성 | **COLLISIONS_PRESENT** — 1,318 기록 / 1,162 고유 / **156 충돌** | `axiom_candidates.lcode_integrity` |
| worktree | prune 0 · kept 9 · **failed 5** | `worktree_prune` |
| 연속성 방화벽 | 차단 로그 124 · case 11 · suppression 5 · **미검토 4** | `continuity_firewall` |

★ L-code ID 충돌이 **85 → 156** 으로 늘었다(전주 digest §4 관찰 → 미수리). 전부 `L-RP-*` 병렬 강화 재현이 초(second) 해상도 타임스탬프를 공유해 발생한다. 측정은 살아 있으나 식별자가 병렬에서 소각된다 — 원장 층 수리 대상이며 본 증류 범위 밖이다.

---

## 1. 2계층 — FR_003 로테이션: **방어형 경로 최초 발화, 그리고 유의한 손실** (이번 주 최대 수확)

**가설**: 1계층의 구속 축이 위기 동조 낙폭이라면, 하락월 볼록성이 실증된 방어형 모듈을 같은 국면조건부 배분규칙 아래 풀에 넣어 총노출을 줄이지 않고 **멤버십 교체만으로** Calmar 를 올릴 수 있다.

**결론**: **Grade C · 가설 기각**. 처치(방어형 포함 풀 115)가 대조(방어형 OFF · 18모듈)에 **전 축에서 열세**.

| 축 | 처치 arm_T | 대조 arm_C | lag+1 arm_S |
|---|---|---|---|
| net_SR | 0.825 | **1.076** | 0.819 |
| PORT_t (NW3) | 0.853 | **1.667** | 0.836 |
| Calmar | 0.399 | **0.692** | 미기재 |
| MDD | 31.5% | **22.6%** | 미기재 |
| oos_retention | −0.521 | +0.014 | 미기재 |
| essence 등급 | C | C | C |

- 대응표본(같은 213월) **−0.192%/월 · NW3 t −2.054 · p 0.041** — 무승부가 아니라 유의한 손실.
- 풀 확장 실측: **15 → 115**(방어형 97 · essence B floor 6 · legacy QEPM-A 12). 국면엔진·배분규칙은 인컴번트 고정.
- 출처: `stage_artifacts/l_code/factor_rotation/l_code_FR_003.json`(L-FR-20260912_171234) · arm 별 `l_code_FR_003_armC_flooronly.json`·`l_code_FR_003_armS_lag1.json`

**기전 4겹 (전부 처치 전달 층에서 갈렸다)**
1. **개별 방어성은 가산되지 않는다** — 벤치 −10% 이하 6개월 초과수익이 대조 +5.63% → 처치 **+3.82%** 로 *떨어졌다*. 97건은 각자 하락월 초과 t≥1.5 를 통과한 모듈인데 ~40개 준-균등 보유에서 idio 방어 성분이 분산으로 상쇄되고 공통 성분만 남았다. 포트 베타는 0.549 → **0.594 로 올랐다** — 노출 축소가 아니므로 베타 트랩으로 설명되지 않는다.
2. **배분규칙이 처치 축을 아예 안 싣는다** — 방어형 합산비중 w_def 와 풀 내 방어형 두수비중의 상관 **r=0.9997**(비율 0.96~1.00). dispatcher 는 방어/비방어 정보를 0 만큼 싣고 headcount 만 반영한다.
3. **retention 진단이 통과하는데 축은 안 실린다** — fr_diag retention 1.73(문턱 0.25 통과)은 'rp 앵커에서 벗어났나' 만 잰다. 표현력 진단을 처치 전달 증거로 인용하면 안 된다.
4. **RCMA 소표본 floor 가 부호를 뒤집는다** — 방어형 두수비중 RISK_ON 0.586 > NEUTRAL 0.485 > CAUTION 0.431 > CRISIS 0.403 > RISK_OFF 0.294. 기준 ②`n_months≥12 in-regime` 때문에 희소국면에서 방어형이 먼저 탈락한다 — **방어 슬리브가 가장 얇아지는 국면이 위기다.**

**부수 수리(침묵 실패)**: 계약이 `period_returns`·`benchmark_returns` 를 정확 날짜로 merge 하는데 벤치 일간계열 구멍으로 월말 라벨이 어긋난 달이 통째로 빠졌다 — **216월 중 교집합 110월 = 표본 49% 소실**. 라벨 정렬(값 불변) 후 213월. 수리 전후 PORT_t 0.537→0.853(T)·0.887→1.667(C). **FR_001/FR_002 도 같은 지문(n_months 110대) — 계보 전체가 반쪽 표본 위에 있었다.** 등급은 둘 다 C 로 불변.

**PIT**: C5 `assert_overlay_pit` HARD PASS(컷오프–홀딩월 시작 간격 최대 4일) · lag+1 스트레스 붕괴 없음. 단 같은 사실이 **국면 축 기여가 사실상 0** 이라는 뜻이기도 하다.

**후속**: 방어형을 멤버십이 아니라 **집계 단위**(합성 방어 슬리브 1개, 내부 가중 = `defensive_score down$t`)로 바꿔 교훈 1 경로를 닫고 재측정 — 성립 여부로 방어형 축의 존폐를 가른다.

---

## 2. 1계층 충실구현 — 논문 5편 소비, A·B 0건

출처: 각 런 `stage_artifacts/replication/<run_id>/authoritative_remeasure.json`. 등급은 15bps 순비용 판.

| 논문 | run_id | 등급 | net_SR | Calmar | PORT_t | 감사 verdict |
|---|---|---|---|---|---|---|
| 2003.02515 Time-varying NN (판1) | `20260912_194913_31448` | C | 0.931 | 0.614 | 1.305 | (판2 감사가 덮음) |
| 2003.02515 판2 (RAWDATA 특성) | `20260912_205731_6912` | **F** | 0.362 | 0.106 | −0.468 | **misdeclared** |
| 2001.04185 Equity Factor Crowding | `20260912_220329_20900` | **F** | 0.288 | 0.062 | −1.784 | adapted(발견 3) |
| 2011.05381 Dirichlet policies (판1) | `20260912_230403_4140` | **F** | 0.392 | 0.103 | −1.218 | **misdeclared** |
| 2011.05381 판2 (mom 부호 반대면) | `20260912_234505_2216` | C | 0.471 | 0.140 | −0.321 | **misdeclared** |
| 결합 5편(1403.8125+2007.08115+2011.05381+2301.09173+2404.08129) | `20260913_022403_11800` | C | 0.533 | 0.157 | 0.071 | — |
| 결합 3편(1403.8125+2301.09173+2404.08129) | `20260910_123836_21280` | C | 0.428 | 0.141 | 0.285 | — |
| 2002.06975 DNN 33팩터 | `_work/run_20260913_063040_21524` | **미측정** | — | — | — | 진행 중(스윕 시점 실행 중) |

### 2a. 2003.02515 — 1판 결함을 고치니 다른 축이 드러났다 (**misdeclared · universe 축**)

판2 는 GKX 특성 19종을 RAWDATA 원값으로 엔진 안에서 계산해 1판의 팩터-DB 경로를 제거했다. 감사 6축 팬아웃(판독 opus 3 · 대조 sonnet 3) 결과 **universe 축이 misdeclared**:

> 구현은 특성 순위·표적 winsorize/표준화·학습·검증·데실을 **전부 K200∪KQ150 안에서** 수행한다. 그러나 원문 §5.4 는 침묵하지 않는다 — §5.2/5.3 에서 **전체 유니버스로 학습된 모델**의 예측을 투자가능 집합으로 **필터링만** 하는 절차다("the same set of stocks are carried forward until the next rebalance"). 즉 이 구현은 논문의 어느 실험에도 없는 '학습 단계부터 한정된 횡단면'을 만든다.
> — `04_Research/strategies/RP_AUTO_2003_02515/fidelity_audit.json:4`(merged_at 2026-09-12T21:23:21)

**교훈**: 유니버스 K200∪KQ150 치환은 v10 충실구현이 허용하는 유일한 변경이지만, 논문이 **치환의 적용 단계**(학습 vs 선택)를 말하고 있으면 그 단계는 치환의 자유도가 아니다. 나머지 5축(signal·timing·portfolio·cost·undeclared)은 발견 0 — 반례 구성 실패까지 기록됐다.

### 2b. 2011.05381 — 논문 내부 모순이 두 재현판의 부호를 갈랐다

같은 표 안에서 `mom` 이 두 번 다르게 정의된다: 행 설명 셀 `12-1M momentum`(= P_{t-1}/P_{t-12}−1) vs 표 캡션 `lagged 12 month value divided by lagged one month value, minus one`(= P_{t-12}/P_{t-1}−1). 두 정의는 균등화 뒤 **정확한 역순위**이고, 차이는 12개 특성열 중 mom 열의 부호 반전 하나로 정확히 환원된다. 판1(F 0.392)과 판2(C 0.471)는 각각 반대 면을 골랐다. 원문은 이 선택을 판별하지 못한다 — §5.2 는 시가총액에만 부호 해석을 붙이고 Fig.5 는 momentum panel beta 를 그리되 부호 해석 문장이 없다.
— `04_Research/strategies/RP_AUTO_2011_05381/fidelity_audit.json:9`

동시에 portfolio 축 **misdeclared**: 구현은 260 리밸일 전부 99~100종 고정인데, 논문 Fig.3 캡션은 자산 수 시변을 전제로 1/N 경계선을 **두 개** 긋는다. 실현 비중도 한 리밸일 안에서 **335배**(2008-04-01 A010060 0.15698 vs A002240 0.00047)로 벌어져 §4.2 의 "EW 근방·강한 베팅 없음" 서술과 어긋난다. 선언(`engine_contract.runtime_note`)은 정반대를 예고했다.

### 2c. **음수 알파 park 게이트가 이번 주에도 방어형 5편을 attempt 0 으로 소비했다**

`06_Registry/reinforce_ledger_l1.json` 에서 이번 주 `parked_reason: skipped_base_quality` 5건 — 누적 18건:

| 논문 | PORT_t | `defensive_score.defensive` | 하락월 초과(t) | 벤치 −10% 이하 초과 |
|---|---|---|---|---|
| 2006.04639 Dynamic Network Risk (`27111`) | −0.924 | **true** | +4.74%/월 (t 6.16) | **+19.15%/월** · 라벨 `볼록(심도↑ 우위↑)` |
| 0806.2606 NN Equity Ranking (`27133`) | −2.857 | **true** | +3.82%/월 (t 9.27) | +13.19%/월 |
| 1707.05552 Wax and wane (`27155`) | −3.131 | **true** | +3.34%/월 (t 4.92) | +13.56%/월 |
| 2003.02515 (`29555`) | −0.468 | **true** | +5.36%/월 (t 6.93) | +17.26%/월 |
| 2001.04185 (`29577`) | −1.784 | **true** | +4.45%/월 (t 10.58) | +10.79%/월 |

park 사유 문자열은 **다섯 건 모두 PORT_t 만 인용하고 `defensive_score` 를 한 번도 읽지 않는다** — 두 필드는 같은 `authoritative_remeasure.json` 안에 있다. 이번 주 §1 이 그 방어형 풀을 실제로 소비해 **가산되지 않음**을 실증했으므로, 게이트가 버린 것이 곧 알파라는 뜻은 아니다. 정확한 상태는 이것이다: **버려진 집합은 '무가치'가 아니라 '아직 소비 형태가 정해지지 않은 볼록 프로파일'이고, 멤버십 형태(§1)로는 이미 기각됐으며 집계 슬리브 형태는 미측정이다.**

---

## 3. 강화 격자 (1계층) — 이번 주 블록 실측

원장: `06_Registry/reinforce_ledger_l1.json`. 이번 주 개시 entry 10건 — exhausted 5(시도 22·26·28·29 등) · **parked-at-0 5건**(§2c).

| 부모 | 블록 요약 L-code | 칸 | 최고 다중검정 t | 최고 Calmar | 등급 분포 |
|---|---|---|---|---|---|
| combo 3편(09-10 개시) | `L-RF-20260912_170118` (B1) | 9 | 1.275 | 0.246 | A0/B0/C9/F0 |
| " | `L-RF-20260912_171557` (B5) | 5 | 1.748 | 0.292 | A0/B0/C5/F0 |
| " | `L-RF-20260912_174349` (B3) | 5 | **2.071** | 0.340 | A0/B2/C3/F0 |
| combo 3편(09-12 재개시) | `L-RF-20260912_185911` (B3) | 6 | **2.071** | 0.340 | A0/B3/C3/F0 |
| 2011.05381(09-13) | `L-RF-20260913_003410` (B1) | 10 | 0.611 | 0.231 | A0/B0/C8/F2 |
| " | `L-RF-20260913_013827` (B4) | 5 | **−0.062** | 0.253 | A0/B0/C5/F0 |
| combo 5편(09-13) | `L-RF-20260913_025653` (B2) | 4 | 0.845 | 0.245 | A0/B0/C4/F0 |
| " | `L-RF-20260913_032839` (B5) | 4 | 0.790 | 0.259 | A0/B0/C4/F0 |

- **이번 주 최고 등급 = B**, 최고 15bps SR **0.98** — `L-RP-20260906_212414`(B4_24 유니버스 제외 LOO · catalog 비중 · K200∪KQ150). 최고 t = **2.071**(B3_13 소형주 하위 1/3 · 15bps SR 0.77 · `L-RP-20260912_174326`).
- **A등급 0건**(전 블록·전 주). Calmar 최고 0.34 — 낙폭 61~73% 대역에서 합격선이 연복리 39~47% 를 요구한다. 구속 축은 여전히 t 가 아니라 낙폭이다.
- 09-13 블록(2011.05381 계열)은 t 0.13~0.85 로 후퇴 — B4 는 음수 t. 기저가 C(부호 동전던지기 판)면 격자가 올려주지 못한다.
- ★B3 의 t 우위는 격자 내부 시험 축(소형 tercile·섹터중립·지수단독)의 측정치이며, **승격 carry 는 유니버스를 고정 축으로 리셋한다**(도훈 2026-09-05) — 이 t 는 승계되지 않는다.

---

## 4. 측정 표기 결함 — "논문기준 SR vs 15bps SR" 은 비용 축의 두 판이 아니다 (신규)

러너가 L-code 에 찍는 성과 문장은 `논문기준 SR a vs 15bps SR b` 한 쌍인데, 코퍼스 전반에서 **b > a 인 행이 다수다**. 같은 포트폴리오에 비용을 더해 SR 이 오를 수는 없다. 실측 대조:

| 런 | `commission_paper_bps` | paper_basis (월간 n=260) | 등급판 (일간 n=5,331) |
|---|---|---|---|
| `20260913_033408_14596`(결합 B4_21) | **15** | CAGR 0.096887 · MDD 0.549402 · SR **0.529** | CAGR 0.0972396 · MDD 0.5494019 · SR **0.602** |
| `20260912_234505_2216`(2011.05381 판2) | 0 | CAGR 0.114102 · MDD 0.651863 · SR **0.431** | CAGR 0.0917171 · MDD 0.657281 · SR **0.471** |

- 위 칸: 비용이 **양쪽 다 15bps** 라 MDD 가 소수 6자리까지 같다 — 두 SR 차이는 비용이 아니다.
- 아래 칸: 비용은 실재한다(CAGR 0.114 → 0.092) — 그런데 **SR 은 오른다**.
- 기전: `paper_basis` 는 **월간 260관측**, 등급판 SR 은 `06_metrics.csv:15` 의 `mean(ER)/sd(ER)*sqrt(252)` **일간 5,331관측**이다. 한 문장 안의 두 값이 비용 축과 **관측 빈도 축**을 동시에 바꾸고, 빈도 효과가 비용 효과를 자주 압도한다.

→ 이 쌍의 대소를 "비용을 넣었더니 좋아졌다"로 읽으면 안 된다. 본 digest 는 등급판 SR(일간)만 인용하고 논문기준 값은 병기하지 않았다. L-code 발행(§ 결과 JSON).

---

## 5. 공리 사이클 현황 (의무 절)

**집계** (`axiom_candidates`, 스윕 [3.5] 실측):

| 항목 | 값 |
|---|---|
| 후보 총계 / pending | 113 / **95** |
| 스폰 생략 / promote crash | 0 / 0 |
| active 원장 | **4** (AX-AR-002·AX-AR-004·AX-RAMP-005·AX-RAMP-006 — 전부 `refined_at 2026-09-01`, **이번 주 신규 아님**) |
| 이번 주 신규 활성화 | **0** (HOLD) |
| 정제보류(HELD) | **15** |
| L-code 무결성 | COLLISIONS_PRESENT (156, §0) |

### 5a. ⚠ 활성화 HOLD — 2주 연속 같은 자리 (맨 위 경고 재게)
`held_at 2026-09-12T17:06:04` · 사유 = **신규 활성 예정 4건 > WEEKLY_ACTIVATION_MAX 3** → "이번 주 promote 쓰기 전면 중단". `would_activate=true` 4건:
- `CAND_alpha_research_894c7d3df737`(REFINED) · `CAND_alpha_research_f94d3e05f0b0`(PASS·REFINED) · `CAND_ramp_c4308a214e2b`(PASS·REFINED) · `CAND_ramp_f70fa9d382ed`(PASS·REFINED)

**전주 digest §3a 와 동일한 4건·동일 사유**다. 자동 진행 금지(INV-6) → **도훈 결정 대기**: ①4건 중 3건만 활성화(상한 준수) ②이번 주 상한을 4로 상향 ③보류 유지. 결정이 없으면 이 HOLD 는 다음 주에도 같은 줄로 재발한다.

### 5b. 정제보류(HELD) 15건 — **사유 명기** (사유 없는 보류는 다음 주 무행동)

| 공리 | mode | n_sup | 미달 축 | 해석 |
|---|---|---|---|---|
| AX-AR-001 | alpha_research | 6 | `R0_polarity` | polarity 라벨 미확정 |
| AX-AR-003 | alpha_research | 13 | `R0_polarity` | 동일 |
| AX-AS-001 | alpha_search | 187 | `미기록`(attempts 0) | 정제 **미시도** — 다음 스윕 재큐 |
| AX-AS-002 | alpha_search | 507 | `R1_members`·`R4_falsification` | 멤버 next_probe·반증 시도 부재 |
| AX-AS-003 | alpha_search | 204 | `R6_distinct` | 기존 공리와 구별성 부족 |
| AX-JG-001 | judge_gate | 13 | `R5_revival` | live_trigger(부활 조건) 부재 |
| AX-QPM-001 | qepm_legacy | 9 | `R5_revival` | 동일 |
| AX-QPM-002 | qepm_legacy | 11 | `R5_revival` | 동일 |
| AX-QPM-003 | qepm_legacy | 14 | `R5_revival` | 동일 |
| AX-QPM-004 | qepm_legacy | 19 | `R5_revival` | 동일 |
| AX-QPM-005 | qepm_legacy | 4 | `R4_falsification` | 반증 시도 부재 |
| AX-RAMP-001 | ramp | 13 | `R1`·`R2`·`R4`·`R5`·`R6` | 5축 결측(가장 미성숙) |
| AX-RAMP-002 | ramp | 11 | `R2_tokens`·`R4`·`R6` | 통계·반증·구별성 |
| AX-RAMP-003 | ramp | 12 | `R2_tokens`·`R5_revival` | 통계·부활 조건 |
| AX-RAMP-004 | ramp | 7 | `R4_falsification` | 반증 시도 부재 |

★ 병목의 지배 축 = **`R5_revival`(부활 조건) 6건** + **`R4_falsification`(반증 시도) 5건** — 전주와 동일 분포, 15건 목록도 **전주와 완전 동일**(해제 0 · 신규 0). 둘 다 L-code emit 시점에 채울 수 있는 필드다. 이번 주 FR_003(`falsification_attempts` 7건 · `next_probes` 4건 실린 기록)이 그 형식의 양성 대조다 — 강화·재현 emit 지점을 같은 형식으로 맞추는 것이 승격률 레버다.

### 5c. DIST 자동초안 — 8건 → `proposed` (§ 결과 JSON)
pending_5axis 백로그 110건 중 supporting 상위 8건에 `statement_refined` + 적대검증 5체크(a~e) 부여. 전부 `proposed` 까지 — 주입 스트림에 들어가지 않는다(활성화는 도훈 권한, INV-6):
DIST-GEN-156(방법론 731) · GEN-080(실증 526) · GEN-151(B1 52) · GEN-137(B1 49) · GEN-155(B5/B4 48) · GEN-113(B1 46) · GEN-055(B5/B4 31) · GEN-153(B3 27).

★ 부수 관찰: **GEN-113 ⊂ GEN-137 ⊂ GEN-151 은 같은 B1 코퍼스의 포함 관계 슬라이스**(46/49/52)이고 GEN-055 ⊂ GEN-155 도 같다(31/48). 세 초안의 `R6_distinct` 는 구조적으로 위태롭다 — 각 초안에 포함 관계와 통합 권고를 명시했다.

---

## 6. 잔재 처리 (의무 절 — 삭제·거부 요약)

**기계 스윕 삭제**: 27건(매니페스트 `.cache/hygiene_manifest.log`) + 위생 감사 1건. `.cache/_battery*·_longonly*·_rf_*_backup*` 스크래치 27건은 `weekly_cache_scratch_7d` 로 기계가 자동 처리.

**★전주 세션 삭제 판단 1건이 집행되지 않았다.** 전주 `distill_result.json::deletions` 는 `delta20_monthend.csv` 1건을 올렸는데, 이 파일은 **여전히 루트에 존재**한다(16,440 bytes · 최종수정 2026-08-22 22:34 = 21.4일 · `.cache/hygiene_manifest.log` 에 기록 0건 · 이번 주 후보 목록에 참조 0 으로 재등장). 재생성 흔적이 없으므로 "지워졌다가 다시 생겼다"가 아니라 **집행 단계를 통과하지 못했다**. 거부 사유는 기록되지 않아 미확인이다 — 집행 로그가 없으면 제안-집행 분리 레인은 매주 같은 제안을 반복한다. 이번 주 재제안하되, 다음 주 후보 목록에 또 나타나면 그 자체가 레인 결함의 확정 증거다.

**세션 판단**: 삭제 후보 13건 중 **1건 삭제 제안 · 12건 보류**.

| 항목 | 판정 | 사유 |
|---|---|---|
| `delta20_monthend.csv` | **삭제(재제안)** | root_unauthorized · 참조0 · 21.4일 된 월말 델타 중간산출 CSV. 실행기·지식기록 아님. 전주 제안 미집행 |
| `0.20` · `25` | 보류 | 참조 721·3,496 = 이름 충돌(짧은 숫자 리터럴). 기계가 어차피 거부 |
| `Rplots.pdf` | 보류 | 0.2일(24h 가드에 걸림) · 참조 1건이 `cleanup.sh` 자신 — 후보 목록이 자기 참조가 되는 형태. 다음 주 재평가 |
| `cid_smoke.rds` · `x.rds` · `parity_factor_db_result.json` | 보류 | 참조 2건씩 실재(진단 자산·테스트 픽스처) |
| `downloads/` | 보류 | 참조 5 — arXiv PDF 실참조 |
| 루트 실행기 5종(`run_as_queue_20260806.R`·`run_fx_intensity.R`·`run_spec_lowfreq_mass.R`·`run_vol_hurst.R`·`run_within_sector_reversal.R`) | 보류 | 참조0 이나 실제 리서치 실행 코드. 2주 연속 "삭제 아닌 이동, 도훈 confirm" 으로 보존 승계 |

---

## 7. 이번 주 요지

1. **방어형 축이 처음으로 소비됐고, 멤버십 형태로는 기각됐다** — 풀 15→115(방어형 97), 처치가 대조에 대응표본 −0.192%/월(t −2.054 · p 0.041). 개별 인증 방어성은 준-균등 다수 보유에서 상쇄되고, RCMA 소표본 floor 가 위기 국면에서 방어 슬리브를 가장 얇게 만든다. 다음 형태는 **집계 슬리브**다.
2. **감사가 두 편에서 misdeclared 를 잡았고, 둘 다 '논문이 말하지 않았다'는 선언이 거짓이었다** — 2003.02515 는 유니버스 치환을 학습 단계까지 밀었고(원문은 학습=전체표본·필터=선택단계로 말한다), 2011.05381 은 자산 수 고정과 비중 분산 이탈을 선언하지 않았다. 부수로 2011.05381 은 논문 내부 모순(mom 부호) 위에 서 있어 두 재현판의 등급이 F↔C 로 갈렸다.
3. **계기 층에서 두 개의 침묵이 드러났다** — (a) 벤치 일간계열 구멍으로 2계층 계보 전체가 표본 49% 위에서 측정돼 왔고(수리 후 PORT_t 0.537→0.853), (b) L-code 성과 문장의 SR 쌍이 비용 축과 관측 빈도 축을 동시에 바꿔 "15bps 가 더 좋다"는 불가능한 비교를 양산해 왔다. 등급은 두 경우 모두 불변이었지만, 두 번 다 **서술이 측정보다 낙관적이었다.**

---

**증류 산출물**: 본 digest · `.cache/cleaner_distill/2026-W37/distill_result.json`(DIST 초안 8 · 신규 L-code 2 · 삭제 제안 1 · 보류 12)
