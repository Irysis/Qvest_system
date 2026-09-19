# Weekly Digest — 2026-W38 (2026-09-13 ~ 09-19)

**작성**: 2026-09-19 (Q / 주간 증류 · owner=`auto_distill` · claimed 2026-09-19 22:04:04)
**기계 스윕**: 2026-09-19 21:54:12 (`02_Infrastructure/ops/weekly_cleaner_sweep.R`, `dry_run=false`, 삭제 8건)
**수집 창**: 직전 스윕(2026-09-12 16:52) 이후 7일
**출처**: `.cache/cleaner_pending.json`(schema `cleaner_pending_v2`) · 각 런의 `stage_artifacts/replication/<run_id>/authoritative_remeasure.json` · `stage_artifacts/l_code/reinforcement/*` · `06_Registry/reinforce_ledger_l1.json` · `04_Research/strategies/RP_AUTO_1806_01743/fidelity_audit.json` · `04_Research/meta/axiom_replay/out/*` · `.cache/hygiene_manifest.log`
**수치 규약**: 등급은 `authoritative_remeasure.json::essence_grade` 만 인용(손계산·재구성 없음). 블록 요약 t·Calmar 는 해당 `L-RF-*` 파일. 값이 없는 축은 "미측정".

> ⚠ **활성화 HOLD — 3주 연속 같은 자리** (`axiom_candidates.activation_hold.held_at 2026-09-19T22:04:01`). 사유 문자열("신규 활성 예정 4건 > WEEKLY_ACTIVATION_MAX 3")도, `would_activate=true` 4건의 후보 id 도 지난 2주와 **완전히 동일**하다. 이번 주 신규 활성화 = **0건**. 도훈 결정 없이는 다음 주도 같은 줄이 나온다(§8a).

---

## 0. 주간 볼륨 (실측 — `.cache/cleaner_pending.json`)

| 항목 | 값 | 출처 키 |
|---|---|---|
| 스윕 삭제 | 8 | `sweep_deleted_n` |
| stage_artifacts 신규 | 246 | `inventory.stage_artifacts_new.n` |
| 신규 L-code | 233 | `inventory.new_lcodes.n` |
| 커밋(7일) | 130 | `inventory.git_log_7d.n_commits` |
| hypothesis_index | 2,394 (전주 2,110 · Δ+284) | `inventory.hypothesis_index` |
| 위생 경고 | 249 (감사 삭제 1) | `sweep_detail.hygiene_n_warnings` |
| L-code 무결성 | **COLLISIONS_PRESENT** — 1,590 기록 / 1,380 고유 / **210 충돌** | `axiom_candidates.lcode_integrity` |
| worktree | prune 0 · kept 19 · **failed 3** | `worktree_prune` |
| 연속성 방화벽 | 차단 124 · case 11 · suppression 5 · **미검토 4** | `continuity_firewall` |
| step_status | 11항목 전부 OK | `step_status` |

★ L-code ID 충돌 **156 → 210** (전주 대비 +54, 3주 연속 증가). 전부 `L-RP-*` 병렬 칸이 초 해상도 타임스탬프를 공유해 생긴다. 측정은 살아 있고 식별자만 소각된다 — 원장 층 수리 대상이며 본 증류 범위 밖(전주에 이어 2주째 미수리).

★ 연속성 방화벽 4지표가 전주와 **완전 동일**하다(124/11/5/4). `n_new_suppressions_learned = 0` — 이 레인은 이번 주에 아무것도 배우지 않았다.

---

## 1. 이번 주 리서치의 전부 — 6편 결합 계보 하나 (1계층 강화)

**2계층(전략 로테이션) 0건**(`stage_artifacts/l_code/factor_rotation` 최종수정 2026-09-12) · **Judge 스폰 0건**(원장 전 entry `judge.spawned=false`) · **BOOK 변동 0건**(`06_Registry/book/book_registry.json` 최종수정 2026-08-30) · **Grade A 0건**(`grade_a_queue.json` 부재).

### 1a. 기저 — 6편 결합 충실구현이 **B** 를 냈다

**가설**: 이미 소비한 논문 6편(2002.06975 DNN · 2404.08129 One-Factor · 1403.8125 MDD-momentum · 2301.09173 Labor-Income · 2007.08115 Regression-Trees · 2011.05381 Dirichlet)의 신호를 한 엔진에 결합하면 단독 논문 기저의 천장을 넘는다.

**결론**: **Grade B** — 결합 기저로는 이 프로그램 최고 등급이다. A 미달 사유는 계약이 직접 적었다: `"A 미달[OOS_ret -0.11<0.7(band fail),Calmar<0.64]"`.

| 축 | 값 | 출처 |
|---|---|---|
| essence_grade | **B** | `stage_artifacts/replication/20260917_105807_22632/authoritative_remeasure.json:9` |
| net_SR (15bps 일간판) | 0.976 | 同 :12 |
| PORT_t (NW lag3) | 2.852 | 同 :14 |
| CAGR / MDD / Calmar | 22.2% / 52.0% / 0.427 | 同 :17~19 |
| oos_retention | −0.107 | 同 :15 |
| defensive_score | **true** — 하락월 111개 초과 +1.82%/월(t 4.99 · 적중 68%) · 벤치 −10% 이하 10개월 +3.43%/월 | 同 :60~91 |
| 롤링 등급 | 현재창 Calmar 2.513 · pass_recent 1 · 연속 pass 16개월 · 생애 pass 52.9% | 同 :42~58 |
| n_max / has_short | 25 / false | 同 :110~111 |

★ 롤링 창은 통과하는데 전표본이 통과하지 못한다(Calmar 2.513 vs 0.427). 이 계보의 낙폭은 최근이 아니라 2008~2020 구간에 있다 — §1c 의 T5 가 같은 자리를 찍는다.

### 1b. 격자 — 36칸 소진, 이어서 승격 1대 (10칸 진행 중)

entry `RP_20260917_105807_22632_combo_rulefast` — `attempts_used 36` · `status exhausted`(예산 25→36: B1 설계 8칸·B5 설계 14칸 초과분). 승격 → `..._promo1`(depth 1, carry = B1_5) · **`status active`**(원장 `06_Registry/reinforce_ledger_l1.json:36708~`·`:39633~`).

| 블록 | 칸 | 최고 셀 | 다중검정 t | Calmar | 등급 분포 | L-code |
|---|---|---|---|---|---|---|
| B1 multifactor | 8 | B1_5 | **3.202** | 0.385 | A0/B5/C3/F0 | `L-RF-20260917_120507` |
| B2 weighting | 6 | B2_7 | 3.066 | 0.382 | A0/B4/C2/F0 | `L-RF-20260917_191958` |
| B3 universe | 3 | B3_14 | 1.728 | 0.278 | A0/B0/C3/F0 | `L-RF-20260917_193646` |
| B4 combination | 5 | B4_24 | 2.159 | 0.426 | A0/B1/C4/F0 | `L-RF-20260917_195304` |
| B5 risk_overlay | **14** | B5_17 | 3.069 | 0.385 | A0/B8/C6/F0 | `L-RF-20260919_024247` |
| **promo1** B1 | 10 | **B1_1** | **3.592** | **0.457** | A0/B7/C3/F0 | `L-RF-20260919_031143` |

- **프로그램 최고 PORT_t 갱신: 3.589 → 3.592**(promo1 B1_1 = `C03_EPS_Chg_3m + M01_Mom_12_1` · CAGR 25.2% · MDD 55.2% · Calmar 0.457 · **oos_retention +0.029** — 이 계보에서 OOS 가 양수로 나온 첫 칸. 출처 `stage_artifacts/replication/20260919_025321_15152`, 원장 `:39668~39681`).
- **A등급 0건 · 46칸 전부.** Calmar 최고 0.457 — 게이트 0.64 까지 아직 0.18 남았다.
- 구속 축은 여전히 낙폭이다. promo1 B1_1 은 5조건 중 3 충족이고 남은 둘이 `calmar(0.457/0.64)`·`oos(0.029/0.70)` 다(원장 `lessons` 줄).

### 1c. **B5 14칸이 거의 한 직선 위에 있었다 — 오버레이가 한 일의 대부분은 노출 축소다** (이번 주 최대 수확)

출처: `stage_artifacts/l_code/reinforcement/l_code_RP_20260917_105807_22632_combo_rulefast_B5.json`(L-RF-20260919_024247).

- 14칸에서 **MDD 0.446~0.584(폭 0.138)** 과 **PORT_t 1.333~3.069(폭 1.736)** 이 같은 방향으로 움직여 **Calmar 는 0.350~0.429(폭 0.079)** 에 머문다. 낙폭을 줄인 만큼 CAGR 을 거의 비례로 가져갔다.
- **계열 라벨(총노출 vs 종목별)은 결과를 가르지 못한다** — 총노출 B5_18 Calmar 0.377 > 종목별 B5_21 0.362.
- 비례선에서 **위로** 벗어난 칸은 랭킹 축을 회전시키는 `multivar_channel_tilt` 하나뿐: B5_20(MDD 0.477 · CAGR 0.203 · Calmar 0.425) · 스택 B5_27(0.459 · 0.197 · **0.429**).
- **아래로** 벗어난 칸은 조건부 총노출 축소 B5_16(Calmar 0.350, 블록 최저). B1 처방이 중심에 뒀던 축이 반증됐고, 대조군으로 넣은 랭킹 회전 칸이 최고를 냈다.
- **스택은 손실이 누적된다** — 2층 스택 6칸 전부 PORT_t 가 구성 층의 최대보다 낮고(B5_27 2.062 < B5_20 2.279 < B5_19 3.001) MDD 이득은 0.018 에서 포화한다.
- 설계 **13건이 13건 집행**됐다(`prior_action_status: executed`). 미집행이 아니라 가설이 틀린 자리다.

### 1d. **오버레이 적대검증부(G2) 첫 가동 — 바닥을 넘은 칸 3건이 3건 전부 반증됐다**

2026-09-17 도훈 지시로 신설된 G2 사후 반증(`02_Infrastructure/reinforcement/rf_overlay_adversary.R`)이 이번 주에 처음 판정을 냈다. 바닥 Calmar 를 넘은 상위 3칸이 후보로 뽑혔고 **verdict 가 3건 다 `fail`** 이다(원장 `:37651`·`:39097`·`:39350`).

| 후보 | rank | 셀 Calmar | verdict | 실패 검정 |
|---|---|---|---|---|
| B5_27 (trend_persist × multivar_channel) | 1 | 0.429 | **fail** | T3, T3b |
| B5_20 (multivar_channel_tilt) | 2 | 0.425 | **fail** | **T1**, T3, T3b |
| B5_26 (erosion_grind × multivar_channel) | 3 | 0.401 | **fail** | T3, T3b |

실측 세부(B5_20, 원장 `:37531~37653`):
- **T1 lag-1**: 신호를 한 칸 밀면 Calmar **0.379** 로 **오버레이 없는 바닥 0.385 아래**로 내려간다(port_t_shift 2.957). 개선이 타이밍에 걸려 있었다는 뜻이다.
- **T3 노출 짝지은 원형블록 순열 placebo**: obs_calmar 0.4182 < placebo 95% 분위 0.4389 · **p 0.0945**(블록길이 7 · n_placebo 200).
- **T3b 횡단면 placebo**: obs 0.5180 < 0.5313 · **p 0.2786**.
- **T4 정적 등가**: pass (obs 0.4182 > const 0.3706) — 즉 "평균 노출만으로는 설명되지 않는다"는 통과하지만 순열 귀무는 못 넘는다.
- **T5 에피소드 집중**: `share_largest = 1` — 낙폭 감소 0.1163 이 **2018-01-29 ~ 2020-03-23 에피소드 하나**에서 전부 나왔고, 그 창 밖에서는 셀이 바닥보다 나빴다. B5_27 도 `share_largest = 1`(원장 `:39271`).

**판정**: B5 블록에서 비례선을 벗어난 유일한 축(랭킹 회전)은 **단일 에피소드에 귀속되고 lag-1 을 못 견딘다**. 2026-07-06 BearProb 동월 누출 사건이 남긴 교훈("placebo·OOS·DSR 를 다 통과해도 lag-1 과 strict-PIT A/B 만 판별한다")의 양성 대조가 처음으로 자동 레인에서 발화했다. ★등급은 불변이다 — verdict=fail 은 **소비 보류**이지 등급 변경이 아니다(AX-008).

### 1e. B1 — **위험 팩터를 선정 축에 넣어도 MDD 는 안 움직인다** (10칸 통제 포함)

출처: `l_code_RP_20260917_105807_22632_combo_rulefast_promo1_B1.json`(L-RF-20260919_031143).

- 수익 축 1칸(B1_1)이 PORT_t 3.592 로 최고이면서 MDD 0.552 로 **최저 권역**에 있다. 위험 팩터 9칸의 MDD 는 0.551~0.607(폭 0.056) — 가장 직접적인 `D50_MaxDrawdown`(B1_7)조차 0.586 으로 B1_1 보다 나쁘고 `RE07_Crisis_Beta`(B1_9)가 0.607 로 최악.
- 위험 팩터 **안에서** 계열이 B/C 를 정확히 가른다: 경로·꼬리 **형상**형(`D51_Ulcer_Index` 2.889 · `R13_NCSKEW` 2.729 · `D58_Vol_Asymmetry` 2.679 · `D50_MaxDrawdown` 2.653 · `D25_Left_Tail_Beta` 2.428) = 전부 **B** / **수준·적재**형(`D01_IdioVol` 1.812 · `D04_Downside_Beta` 1.631 · `RE07_Crisis_Beta` 1.624) = 전부 **C**.
- 통제 1건: **B1_10 = B1_1 + D04** → PORT_t 3.592→3.072 · CAGR 0.252→0.239 · MDD 0.552→**0.570** · Calmar 0.457→0.419. 네 지표 동시 악화. 하방베타를 선정 축에 얹으면 낙폭은 안 줄고 모멘텀 신호만 희석된다.
- 앞선 B1(8칸, 09-17)도 같은 자리를 찍었다: PORT_t 폭 2.13 인데 MDD 폭 0.067 — "어떤 신호를 넣어도 낙폭이 같은 자리에서 난다"(L-RF-20260917_120507 기전).

**정황 해석(확증 아님)**: 25종 long-only 동일가중에서 낙폭은 개별 종목의 위험 특성이 아니라 보유 전체의 시장 동조에서 오고, 종목 **선정**은 그 동조를 못 바꾼다. 남은 프론티어는 소비 지점이다 — 같은 `D04` 가 tilt 층에서는 움직이는지가 미결이고, §1c 의 B5 결과는 그 방향에도 비례선이 있음을 시사한다.

---

## 2. 1계층 충실구현 — 논문 1편 소비, A·B 0건

| 논문 | run_id | 등급 | net_SR | Calmar | PORT_t | 감사 verdict |
|---|---|---|---|---|---|---|
| 1806.01743 ML Framework for Stock Selection (판1) | `20260917_085040_30128` | **F** | 0.236 | 0.045 | **−1.772** | adapted(발견 0) |
| 1806.01743 (판2) | `20260917_095447_16940` | **F** | 0.277 | 0.064 | **−1.486** | adapted(발견 0) |
| 2026-09-15 착수 5런 | `20260915_203723_*` 외 4 | **미측정** | — | — | — | 산출물 0(빈 디렉터리) |

출처: 각 `stage_artifacts/replication/<run_id>/authoritative_remeasure.json:9~19`.

### 2a. 감사 6축이 **반례를 하나도 구성하지 못했고, 그것이 정보다**

`04_Research/strategies/RP_AUTO_1806_01743/fidelity_audit.json`(merged_at 2026-09-17T10:18:33) — 팬아웃 6축(판독형 opus 3 · 대조형 sonnet 3) · `n_findings` 전 축 0 · 병합 verdict **adapted**(signal·timing·portfolio·undeclared adapted / universe·cost faithful).

6축 전부가 `counterexample` 칸에 **"구성하지 못했다"** 를 적었고, 사유가 같다 — **논문이 값을 인쇄하지 않는다.** portfolio 축 인용:

> 반례가 성립하려면 논문이 포트폴리오 규칙을 어떤 형태로든 인쇄해야 하는데, 원문 전체에서 'long'·'short'·'position'·'buy'·'sell'·'hold'·'equally'·'equal-weight'·'value-weight'·'weighting'·'rebalance'·'benchmark'·'transaction' 이 전부 NOT PRESENT 이고, 숫자가 붙은 'stocks' 도 0건이다. … 즉 이 축에는 구현이 갈릴 수 있는 논문 값 자체가 존재하지 않는다.
> — `fidelity_audit.json:55`

signal 축도 return-to-volatility 식·Q·f·특성 룩백·정규화 어휘가 전부 NOT PRESENT 임을 프록시 재판독으로 확인했고, cost 축은 6페이지 전문에 비용 어휘 0건임을 확인했다.

**교훈**: `n_findings = 0` 은 **구현이 충실하다**는 증거가 아니라 **논문에 대조할 값이 없다**는 증거일 수 있다. 두 상태는 같은 산출물 모양을 낸다 — 가르는 것은 `counterexample` 칸이 "반례를 구성했으나 갈리지 않았다"고 적었는지, "구성할 논문 값이 없었다"고 적었는지다. 이번 판은 후자였고, 그 경우 F 판정의 신뢰는 감사가 아니라 구현 선언(`FIDELITY.changed` 14항)이 진다. (미적립 학습 → § 결과 JSON)

### 2b. 09-15 착수 5런 — **자체 양성 대조가 두 판을 죽였다**

`stage_artifacts/replication/20260915_203723_18088`·`_1856`·`_23476`·`20260915_215337_32576`·`20260915_224121_14736` 는 **전부 빈 디렉터리**다(파일 0건). `authoritative_remeasure.json` 이 없으므로 **등급 미발행 = 미측정**이며 실패가 아니다. 같은 논문이 09-17 에 재착수해 F 2판을 냈다. 전략 디렉터리에 `_gradcheck_diag.R` 이 남아 있다 — 진단이 실행됐다는 흔적이고, 모델 코드가 아니라 검산의 조건이 문제였다는 기록은 이미 메모리 카드에 있다.

---

## 3. 메타 연구 — Axiom 엔진 리플레이 (백테스트 0회)

`04_Research/meta/axiom_replay/`(사전등록 + WP1~WP4 + FINAL_report, 2026-09-18). **원장 읽기 전용 · 하네스 변경 0건 · 백테스트 0회.**

**양성 대조 먼저**(FINAL_report §2): π₀ 배치열 재현 post_0904 **121/123 배치(98.4%)** · 배치 재구성 대 레인 로그 **129/129(100%)** · 바닥 스펙 감사 **229/249(92.0%)** · 미공개 점수 엿보기 주입 차단 확인. 이 통과 뒤에 나온 판정만 인용한다.

1. **격자 순서 정책 층 = NO-GO.** 모든 트리가 25칸 격자를 전부 소비했다 — **탐색공간/예산 비 = 1.00**. 쳐낼 가지가 없으므로 순서를 바꿔도 총량이 같다.
2. **기저 관문(base_min_port_t=0)이 프로그램 최고 계보를 죽일 뻔했다.** 기저 PORT_t **−0.280** 짜리(`0913_090549_14760`)가 2.823 → 3.092 → **3.589** 로 갔다. 기저 PORT_t 가 최종 최고를 예측하는 정도는 **ρ=+0.560, CI [+0.009, +0.905]** — 하한이 0 에 닿는다. 파킹된 24건은 시도 0칸이라 반사실이 기록에 없다.
3. **승격 게이트는 예측력이 없다.** 승격 12건 = 개선 5 · 동일 1 · 악화 6. 그런데 승격을 전부 막으면 프로그램 최고가 3.589 → 3.202 로 떨어지고 **B등급 칸 137개 중 95개(69%)가 사라진다**. 게이트가 결정 시점에 보는 값과 자식 성과의 상관 **−0.252, CI [−0.771, +0.451]**. 문턱 변경은 사전등록 바(15%) 미달 → **권고 없음**.
4. **주입 채널이 일방향이다.** 공리 23개 = documented 21 · advisory 1 · block 1. 죽은 선례 경고 발화율 **91.2%**, 경고분/무경고분 PORT_t 차 +0.037(대조 68칸). 음성 DIST 카드 78장의 보정도를 재려 했으나 **0장**이 잴 수 있었다 — 94% 가 퇴역 모드 출처이고 강화 L-code 는 블록 단위·`strategy_id` 키라 칸과 조인되지 않는다(원장 `l_code` 보유 **12/878**).
5. **2계층 풀의 방어형 경로는 대체로 정당했다**(WP4, 새 백테스트 0회 재채점). 풀 301 중 **201(67%)** 이 등급 floor 미달·방어형 경로 입장. 하락월 초과 중앙 **+1.76%/월**(201건 전부 양수 · 적중 68% · t 4.88) · 깊은 낙폭(벤치 ≤ −10%) 초과 중앙 **+2.37%/월** — 얕은 하락월보다 **크다**. 다만 **깊은 낙폭에서 벤치보다 못한 모듈 36/201(18%)**, 최악 −9.97%/월. 얕은↔깊은 방어 Spearman **+0.611, CI [+0.487, +0.720]**.

★ 이것은 **전주 §1(FR_003)이 멤버십 형태로 방어형을 기각한 판정을 뒤집지 않는다.** 전주가 잰 것은 "방어형 97건을 준-균등 보유로 담으면 방어가 상쇄된다"이고, 이번 WP4 가 잰 것은 "풀 201건 각각이 깊은 낙폭에서도 벤치를 이겼는가"다. 두 판정은 양립하고, 겹치는 결론은 **하위 꼬리 36건을 잘라내는 것**이다.

★ 권고 #1(파킹 24건 중 기저 [−0.7, 0] 인 5건을 정상 25칸으로 측정)은 **준비까지 갔고 미실행**이다: `04_Research/meta/axiom_replay/run/reinforce_config_parked5.json`·`run_parked5.sh`(2026-09-18 23:53~23:57, 도훈 지시 "파킹 5건 측정 진행해. 루프는 켜지 마"). 09-19 의 실측 칸은 전부 결합 계보 B5/B1 이었다 — **parked5 측정은 이번 주 0칸**.

---

## 4. 계기 층 — 이번 주에 바뀐 것

### 4a. 벤치마크 축을 **공표 코스피200 포인트로 이관** (배율 개념 삭제)

`02_Infrastructure/data/benchmark_axis.py`(신설 2026-09-18) — 파일 머리말이 사유를 직접 적는다:

> `.cache/benchmark.parquet::BM_Close` 는 공표 코스피200 종가(포인트) 그대로여야 한다. 그런데 2026-07~09 내내 그 파일은 지수의 **8.83배** 위에 있는 리베이스 체인이었고, 갱신기가 새 값을 붙일 때마다 "이 파일이 쓰던 배수"를 추정해 되돌려야 했다. 추정이 한 번 미끄러질 때마다 그 날 하루의 수익률이 배수비를 통째로 삼켰다 — 같은 병이 **07-27 · 07-29 · 2025-01-02** 에 반복됐고, 앞의 둘만 날짜를 박은 일회성 스크립트로 고쳐졌다(그래서 또 재발했다).
> — `benchmark_axis.py:4~14`

수리는 문턱 조정이 아니라 **개념 삭제**다: 저장 규약 = 지수 레벨(포인트), 붙이기 = 순수 이어붙이기, 배율 필드 없음(`AXIS_UNIT = 'index_points'`). 정본 원천 = `03_Universe/Benchmark_price.xlsx`(QuantiWise IKS200, 생 포인트) → KRX 스냅샷 → (재구축 한정) 구 체인 ÷ 실측 구간배수. **Naver chart API 는 정본에서 빠지고 트립와이어 전용**이 됐다. 동반 파일: `benchmark_level_axis.R`·`rebuild_benchmark_canonical.py`·`naver_benchmark_update.py`·`repair_benchmark_level_axis.R`(전부 2026-09-18). 커밋 `5267f725e`.

★ 이 축 변경의 **사후 검증 수치(게이트 편차·재구축 대조)는 본 digest 범위에서 산출물로 확인하지 못했다 — 미측정으로 남긴다.** 다음 주 증류가 `.cache/benchmark_axis.json` manifest 로 확인할 자리다.

### 4b. 리서치 레인 정지 → 재개

`06_Registry/reinforce_auto_config.json:3~4` — `enabled=true`, `paused_reason`:

> (해제) 2026-09-19 02:2x 재개 — 퀀티 Update_File 갱신·적재 완료(수급 **+118,749행** · 컨센서스 **12종** · 둘 다 09-18, 정본 신선도 감사 **stale=0**). 직전 일시정지 00:1x = 엑셀 메모리 확보용(B5 DNN 배치가 커밋 여유 1.1GB).

직전 정지는 **2026-09-17 19:58 도훈 지시 "리서치 잠시 멈추고 점검해봐"** — 점검 대상이 정확히 "오버레이를 써도 MDD 가 안 줄어드는 원인"이었다. 그 점검 지시가 나온 뒤에 돈 것이 §1c 의 B5 14칸이고, **답은 '비례선'이었다.** 지시와 측정이 한 바퀴 안에서 닫혔다.

**가동 실측**: 7일 중 실측 칸이 난 날은 09-13·09-17·09-19 **3일**이다. 09-14·09-16·09-18 은 칸 0건이고 09-15 는 5런 전부 빈 산출물(§2b). 블록 L-code 발행 간격 최대 **09-13 22:17 → 09-17 12:08 ≈ 62시간**(`stage_artifacts/l_code/reinforcement/` 타임스탬프).

---

## 5. 계보 하나가 이번 주에 끝났다 — 2002.06975 depth-3

`RP_20260913_090549_14760_adapted_rulefast_promo3`(원장 `:36686` 직전 entry) — `exhausted_at 2026-09-15T20:54:07` · `handed_off: true` · **`promoted_to` 없음**.

- 부모 최고 PORT_t **3.589**, 이 세대 최고 **3.133**(B1_3 · Calmar 0.504, `L-RF-20260913_214207`). 승계 조건 ①"부모 최고 초과" 미충족.
- 동시에 `parent.depth = 3` = `promote_max_depth` 상한. **두 조건이 같이 걸려 사슬이 닫혔다** — 어느 하나만으로도 닫혔을 자리다.
- 블록 결과: B5 5칸 최고 2.806(Calmar 0.483, 블록 최고 Calmar 0.61) · B1 6칸 3.133 · B3 5칸 1.903 · B4 2칸 1.627. **B2 는 발행되지 않았다** — B4_25 칸이 `[rf_cell_engine] arm lean:hrp 커버리지 76.6% (<80%)` 로 2회 연속 실패해 `terminal` 로 닫혔다(원장 `:36616~36622`, `grade: "NA (등급 미발행 — 병렬 실행 실패)"`). 커버리지 가드 분모 결함은 09-13 에 특정되고 09-17 에 main 으로 이식됐으나, 이 칸은 그 사이에 죽었다.
- B4 기전(`L-RF-20260913_221408`)이 이 계보의 벽을 한 줄로 적었다: **MDD 는 B1 0.479~0.530 · B3 0.470~0.575 · B5 0.354~0.479 · B4 0.348~0.395 네 축을 다 돌아 0.348 이 하한이고, 그 하한 근처에서 PORT_t 가 1 미만으로 내려간다.**

---

## 6. 3주째 A등급이 없는 이유 — 두 축의 실측 상한

이번 주 46칸과 지난 두 주의 격자를 같은 축으로 놓으면 이렇게 읽힌다(전부 실측, 해석은 명시):

| 축 | 관측된 것 | 출처 |
|---|---|---|
| 선정(B1) | PORT_t 를 3.59 까지 밀지만 MDD 대역은 5~7%p 안에 갇힌다 | L-RF-20260917_120507 · 20260919_031143 |
| 비중(B2) | 공분산 추정 품질이 결과에 실리지 않는다 — 구조 추정 B2_9(2.624/0.353)가 공분산 미사용 대조 B2_11(2.647/0.354)과 구분되지 않는다 | L-RF-20260919_024247 `avoid` |
| 유니버스(B3) | 32개 블록 중 직전 최고 t ≥ 2.5 인 7블록에서 전진 0건 | DIST-GEN-205 supporting |
| 오버레이(B5) | Calmar 폭 0.079 의 비례선 · 이탈 칸은 적대검증 3/3 반증 | L-RF-20260919_024247 · 원장 adversary |
| 결합(B4) | MDD 를 0.006 더 내리며 PORT_t 를 1.493 깎는다 | L-RF-20260913_221408 |

★ **이것은 "봉투 안에서 이 다섯 축이 천장을 보였다"는 정직 서술이지, 고정 제약(25종·long-only·Σw=1·K200∪KQ150·15bps·유동성 2e8) 탓이라는 귀속이 아니다.** 아직 안 닿은 봉투-안 레버가 남아 있다: 2차 모멘트 밖을 표적하는 비중(higher_moment · PreferenceRobustDistortion — B5 기전이 명시 제안) · 유효 종목수(집중도) 축 스윕 · 비-return 재료(수급 패널은 09-18 에 +118,749행이 들어왔다) · 그리고 **파킹 5건 측정**(§3 권고 #1).

---

## 7. 공리 사이클 현황 (의무 절)

**집계**(`axiom_candidates`, 스윕 [3.5] 실측):

| 항목 | 값 | 전주 대비 |
|---|---|---|
| 후보 총계 / pending | 120 / **102** | 113/95 → +7 |
| 스폰 생략 / promote crash | 0 / 0 | 동일 |
| active 원장 | **4** (AX-AR-002 · AX-AR-004 · AX-RAMP-005 · AX-RAMP-006 — 전부 `refined_at 2026-09-01`) | **동일 4건, 신규 0** |
| 이번 주 신규 활성화 | **0** (HOLD) | 동일 |
| 정제보류(HELD) | **15** | 동일 15, **목록도 동일** |
| pending_5axis 백로그 | 108 (최고령 73일 · `DIST-AR-005`) | 110 → 108 |
| 5축 실패 히스토그램 | independence 68 · external 54 · mechanism 49 · falsification 42 · rigor_research 5 | — |
| 격리 증거 | 6 | — |

### 7a. ⚠ 활성화 HOLD — 3주 연속 (맨 위 경고 재게)

`held_at 2026-09-19T22:04:01` · 사유 = **신규 활성 예정 4건 > WEEKLY_ACTIVATION_MAX 3** → "이번 주 promote 쓰기 전면 중단". `would_activate=true` 4건:
`CAND_alpha_research_894c7d3df737`(REFINED) · `CAND_alpha_research_f94d3e05f0b0`(PASS·REFINED) · `CAND_ramp_c4308a214e2b`(PASS·REFINED) · `CAND_ramp_f70fa9d382ed`(PASS·REFINED).

**3주 연속 같은 4건·같은 사유다.** 자동 진행 금지(INV-6) → **도훈 결정 대기**: ①4건 중 3건만 활성화(상한 준수) ②이번 주 상한을 4로 상향 ③보류 유지. 결정이 없으면 다음 주도 같은 줄이다. ★부수 관찰: §3-4(주입 채널 일방향 · 공리 23개 중 21개가 문서 전용)를 감안하면, **이 HOLD 가 막고 있는 것의 하류 효과 자체가 아직 측정되지 않았다** — 활성화 상한 논쟁보다 주입→행동 경로 계측(§3 권고 #3)이 먼저일 수 있다.

### 7b. 정제보류(HELD) 15건 — **사유 명기** (사유 없는 보류는 다음 주 무행동)

| 공리 | mode | n_sup | 미달 축 | 해석 |
|---|---|---|---|---|
| AX-AR-001 | alpha_research | 6 | `R0_polarity` | polarity 라벨 미확정 |
| AX-AR-003 | alpha_research | 13 | `R0_polarity` | 동일 |
| AX-AS-001 | alpha_search | 187 | `미기록`(attempts **0**) | 정제 **미시도** — 3주 연속 attempts 0. 재큐가 도는지 자체가 미확인 |
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

★ 지배 축 = **`R5_revival`(부활 조건) 6건** + **`R4_falsification`(반증 시도) 5건** — 전주와 분포·목록 모두 동일(해제 0 · 신규 0 · `refine_attempts` 전부 1 그대로). **2주 연속 완전 동결은 "입력이 안 고쳐졌다"이지 "게이트가 엄격하다"가 아니다.** 둘 다 L-code emit 시점에 채울 수 있는 필드이고, 이번 주 강화 L-code 는 `next_probes` 2건씩을 실었으나 `live_trigger` 는 여전히 비어 있다 — 그 한 줄이 `R5_revival` 6건의 잠금이다.

### 7c. DIST 자동초안 — 8건 → `proposed` (§ 결과 JSON)

pending_5axis 백로그 108건 중 supporting 상위 8건에 `statement_refined` + 적대검증 5체크(a~e) 부여. 전부 `proposed` 까지 — 주입 스트림에 들어가지 않는다(활성화는 도훈 권한, INV-6):
DIST-GEN-210(방법론 881) · GEN-211(B1 62) · GEN-189(B1 59) · GEN-207(B5/B4 57) · GEN-209(B5/B4 57) · GEN-205(B3 32) · GEN-165(B3 28) · GEN-133(B3 25).

★ **포함 관계가 전주보다 악화됐다.** GEN-133 ⊂ GEN-165 ⊂ GEN-205 (25/28/32, 전부 B3) · GEN-189 ⊂ GEN-211 (59/62, 전부 B1) · GEN-207 ≅ GEN-209 (57/57, 한 레코드 차이 — L-RF-20260919_024247 유무). 8건 중 **6건이 3개 모집단의 시점 슬라이스**다. `R6_distinct` 가 구조적으로 위태로우므로 각 초안에 포함 관계와 통합 권고를 명시했다. 근본 수리는 증류기가 **같은 코퍼스의 시점 스냅샷을 새 후보로 찍지 않게** 하는 것이고, 그건 본 증류 범위 밖이다.

---

## 8. 잔재 처리 (의무 절 — 삭제·거부 요약)

**기계 스윕 삭제 8건**(매니페스트 `.cache/hygiene_manifest.log:1588~1596`): 빈 디렉터리 1(+위생 감사 1) · `weekly_cache_scratch7d` 6(`_battery_after_priority_20260907.log`·`_battery_repair_20260907.log`·`_ml_lane_verify.log`·`_ml_lane_verify.R`·`_reticulate_install.log`·`_torch_cu_install.log`) · `weekly_log30d` 1(Temp 훅 라우터 stderr).

### 8a. ★전주 가설 폐기 — 제안-집행 레인은 결함이 아니었다

전주 digest §6 은 `delta20_monthend.csv` 가 안 지워진 것을 두고 "집행 단계를 통과하지 못했다 … 다음 주 후보 목록에 또 나타나면 레인 결함의 확정 증거"라고 적었다. **그 검정은 음성으로 돌아왔다.** 매니페스트 실측:

```
1584:2026-09-13 07:47:52	weekly_distill_llm	delta20_monthend.csv
```

파일은 전주 digest 작성(07:30) **17분 뒤에 집행됐고**, 이번 주 후보 목록에 다시 나타나지 않았으며 루트에도 없다(`Test-Path` false). 즉 레인은 정상이고, 전주의 관찰은 **자기 사이클의 집행 이전 상태를 본 것**이다. 세션은 digest 를 먼저 쓰고 기계가 그 뒤에 집행하므로, 같은 오독은 매주 재생산될 수 있다 — 판정 근거는 파일 존재가 아니라 **매니페스트**여야 한다.

### 8b. 세션 판단 — 삭제 후보 12건 중 **4건 삭제 제안 · 8건 보류**

| 항목 | 판정 | 사유 |
|---|---|---|
| `run_fx_intensity.R` (1.1KB · 46.6일) | **삭제** | root_unauthorized · 참조0 · 일회성 탐침 드라이버. git 이 사료를 보존하므로 루트 제거 = 소실 아님 |
| `run_spec_lowfreq_mass.R` (0.6KB · 55.2일) | **삭제** | 同 (최고령) |
| `run_within_sector_reversal.R` (0.7KB · 41.4일) | **삭제** | 同 |
| `run_vol_hurst.R` (0.9KB · 29.6일) | **삭제** | 同 |
| `run_as_queue_20260806.R` (21.3KB · 44.1일) | 보류 | 참조0 이나 21KB 짜리 큐 러너 — 절차를 담고 있을 수 있다. 위 4건과 성격이 다르다(도훈 확인 후) |
| `0.20` · `25` | 보류 | 참조 736 · 3,669 = 이름 충돌(짧은 숫자 리터럴). 기계가 어차피 거부 |
| `Rplots.pdf` | 보류 | 0.8일(24h 가드) · 참조 1건이 `cleanup.sh` 자신. 3주째 같은 자리 |
| `cid_smoke.rds` · `x.rds` | 보류 | 참조 2건씩 실재(진단 자산 · 증류 라이브러리/테스트 픽스처) |
| `downloads/` | 보류 | 참조 5 — arXiv PDF 실참조 |
| `02_Infrastructure/ast/tests/parity_factor_db_result.json` | 보류 | 참조 2(패리티 테스트 · 연산자 백로그) |

★ 삭제 제안 4건의 유일한 참조처는 `06_Registry/hygiene_report.json` 과 과거 `distill_manifest_*.json` — 즉 **후보 목록 자신**이다(실측: `02_Infrastructure/` 참조 0건). 후보 목록이 후보의 참조가 되는 형태라 기계 재도출도 같은 결론을 낼 것이다.

---

## 9. 이번 주 요지

1. **오버레이 축의 정체가 드러났다 — 비례선이고, 이탈 칸은 가짜였다.** B5 14칸에서 MDD 폭 0.138 · PORT_t 폭 1.736 이 같은 방향으로 움직여 Calmar 는 0.079 안에 갇힌다. 비례선을 벗어난 유일한 축(랭킹 회전)은 적대검증 후보 3건 중 3건이 전부 반증됐고(T3/T3b 순열 귀무 미통과 · B5_20 은 lag-1 에서 바닥 아래로), **낙폭 감소분 전량이 2018~2020 에피소드 하나에 귀속된다**(share_largest=1). 도훈의 09-17 점검 지시("오버레이를 써도 MDD 가 안 줄어드는 원인")가 같은 바퀴 안에서 답을 받았다.
2. **구속 축은 선정이 아니라 소비 지점이라는 것이 통제로 확인됐다.** B1 10칸에서 위험 팩터 9종 중 어느 것도 MDD 를 못 내렸고(폭 0.056), 가장 직접적인 `D50_MaxDrawdown` 조차 수익 축 단독(B1_1)보다 나빴다. 통제 B1_10 = B1_1 + `D04_Downside_Beta` 는 네 지표 동시 악화. 그러면서 프로그램 최고 PORT_t 는 3.589 → **3.592** 로 갱신됐고 이 계보 처음으로 **oos_retention 이 양수(+0.029)** 로 나왔다 — 벽은 Calmar 0.457 / 0.64 하나로 좁혀졌다.
3. **엔진이 자기 규칙의 반사실을 처음 쟀고, 두 개는 즉시 쓸 수 있다.** 기저 관문은 최고 계보(기저 −0.280 → 3.589)를 죽일 뻔했고 예측력 CI 하한이 +0.009 에 닿는다. 승격 게이트는 예측력이 없으나 B등급 칸의 69%를 생산한다. 반면 격자 순서 정책 층은 NO-GO(공간/예산 비 1.00). ★그런데 그 보고가 낸 1순위 권고(파킹 5건 측정)는 **준비만 되고 이번 주 0칸 실행**이고, 3주 연속 같은 공리 4건이 HOLD 에 묶여 있다 — 이번 주에 가장 잘 측정된 것은 전략이 아니라 **엔진 자신의 결정 규칙**이었고, 가장 덜 집행된 것도 같은 층이다.

---

**증류 산출물**: 본 digest · `.cache/cleaner_distill/2026-W38/distill_result.json`(DIST 초안 8 · 신규 L-code 2 · 삭제 제안 4 · 보류 8)
