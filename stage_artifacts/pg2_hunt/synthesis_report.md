"report": "```markdown
# PG2 사냥 종합 판정 — 331 팩터 전수 book-marginal 측정

**측정 범위** 331 팩터 × 2 arm × weight 5점 · 실패 0 · 샤드 8개 통합 (`stage_artifacts/pg2_hunt/z1_pooled.csv`)
**Incumbent** `05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2` · 269개월 · net active IR **1.4160**
**문턱** book-marginal ΔIR ≥ 0.05 (measurement-graduation §4)
**통합 재산출 스크립트** `z1_pool.R` / `z2_ceiling.R` / `z3_probe_design.R` / `z5_stack_design.R` / `z6_stack_sweep.R` / `z7_tstat.R`

---

## 1. 한 줄 판정

**331 재료 전수에서 PG2 를 book-marginal ΔIR ≥ 0.05 로 이기는 단일 팩터는 0건입니다.** 이것은 weight 격자의 산물이 아닙니다 — weight 를 사냥에 쓴 {0.05, 0.10, 0.15, 0.20, 0.30} 5점이 아니라 **w ∈ (0.001, 0.999) 전 구간으로 풀어도 331/331 전건 미달**이며, 도달 가능한 최대 ΔIR 은 **+0.0199** (V18_AM, 파킹 arm) 로 문턱의 **39.8%** 입니다.

### 검산 (해석해 ↔ 메인 세션 실측 3점 일치)

| 조건 | 해석해 천장(w=0.20) | 메인 세션 실측 | 일치 |
|---|---|---|---|
| ρ=0.0, IR_s = 1.4160 | **+0.3012** | +0.3012 | 소수 4자리 |
| ρ=1.0, IR_s = 1.4160 | +0.0004 | 0.0000 | 일치 |
| ρ=0.4 에서 필요 IR | **0.9249** | 지도값 0.925 | 소수 3자리 |

해석해 `ΔIR(w|ρ, IR_s)` 가 요구조건 지도와 세 점에서 일치하므로, 아래 천장·부족분·스택 계산은 같은 자를 씁니다. 슬리브 sd 는 incumbent sd 로 정규화(k=1)했고, w 를 자유롭게 두면 sd 비율이 w 에 흡수되므로 **가중 무제약 천장은 (ρ, IR_s) 만의 함수**입니다.

---

## 2. 분포표 — PG2 는 얼마나 이기기 어려운 상대인가

### arm1 무조건부 (전 기간, n = 155~270개월, 중앙 268)

| 지표 | min | q25 | 중앙 | q75 | max | 문턱 관련 |
|---|---|---|---|---|---|---|
| incumbent 상관 ρ | 0.0831 | 0.3753 | **0.4203** | 0.4511 | 0.5562 | ρ<0.2 **4건** · ρ<0 **0건** |
| 슬리브 IR | −0.5292 | −0.2421 | **−0.0827** | 0.0680 | 0.3943 | IR>0.5 **0건** · IR>0 110건 |
| ΔIR @ w=0.20 | −0.2654 | −0.2155 | −0.1832 | −0.1474 | −0.0140 | 양수 0/207 ※ |
| ΔIR best-over-w(5점) | −0.0579 | −0.0448 | −0.0364 | −0.0283 | **+0.0008** | ≥0.05 **0/331** |
| ΔIR 가중 무제약 천장 | −0.0011 | — | −0.0007 | −0.0005 | **+0.0008** | ≥0.05 **0/331** |

### arm2 파킹 (FQ-191 ON/OFF, 전환 15bps, n = 73개월 · ON 26 · 에피소드 14)

| 지표 | min | q25 | 중앙 | q75 | max | 문턱 관련 |
|---|---|---|---|---|---|---|
| incumbent 상관 ρ | 0.2037 | 0.2915 | **0.3243** | 0.3520 | 0.4491 | ρ<0.2 **0건** |
| 슬리브 IR | −0.8437 | −0.3053 | **−0.0898** | 0.1395 | 0.5756 | IR>0.5 **1건** · IR>0 136건 |
| ΔIR @ w=0.20 | −0.2440 | −0.1402 | −0.1001 | −0.0642 | −0.0014 | 양수 0/204 ※ |
| ΔIR best-over-w(5점) | −0.0532 | −0.0279 | −0.0194 | −0.0120 | **+0.0201** | ≥0.05 **0/328** · 양수 10건 |
| ΔIR 가중 무제약 천장 | −0.0013 | — | −0.0005 | −0.0003 | **+0.0199** | ≥0.05 **0/328** |

※ w=0.20 행은 207/204건 부분표본입니다 — 샤드 3·4·7 이 w=0.20 값을 산출물에 남기지 않고 best-over-w 만 기록했습니다. 판정에 쓰는 통계는 331 전건이 있는 best-over-w(후보에게 더 유리한 쪽)입니다.

### 부족분 (필요 최소 슬리브 IR @w=0.20 − 실측 IR)

| arm | min | q25 | 중앙 | q75 | max |
|---|---|---|---|---|---|
| 무조건부 | 0.3315 | 0.8782 | **1.0299** | 1.1888 | 1.4618 |
| 파킹 | 0.1416 | 0.6968 | **0.9142** | 1.1305 | 1.6488 |
| 팩터별 최소(양 arm 중) | 0.1416 | 0.6751 | **0.8336** | 0.9948 | 1.4214 |

예비 48재료 실측(상관 중앙 +0.402 / IR 중앙 −0.100 / 부족분 중앙 1.063)과 전수 331 이 방향·크기 모두 정합합니다. 표본이 전수로 늘어도 기전은 바뀌지 않았습니다.

### PG2 의 난이도를 숫자로

1. **전 재료가 양의 상관** 안에 있습니다 — 331 중 ρ<0 이 **0건**, 최소 ρ 가 0.0831. PG2 와 반대 방향으로 움직이는 재료가 DB 에 없습니다.
2. **관측 상관대(중앙 0.42)가 요구하는 IR 이 0.93~1.03** 인데, DB 최고 슬리브 IR 은 파킹 0.5756 / 무조건부 0.3943 — incumbent IR 1.4160 의 **41% / 28%** 입니다.
3. ρ=0.8 이면 필요 IR 1.428 > **PG2 자신의 IR**. 즉 상관이 높은 재료는 PG2 보다 강해야만 기여합니다.
4. **(ρ, IR) 평면에서 통과 영역에 든 재료가 무조건부 0/331, 파킹 0/328** 입니다. 근접이 아니라 영역 밖입니다.

---

## 3. 근접 후보 (부족분 최소순) — 어느 축이 모자란가

`rho_needed` = 현재 IR 을 유지한 채 통과하려면 상관이 이 값 이하여야 하는 값. `gap_ρ` = 더 내려야 할 상관 폭.

| # | 팩터 | arm(n) | ρ | 슬리브 IR | 필요 IR | 부족분 | 천장(w 무제약) | rho_needed | gap_ρ |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **V18_AM** | parked(73) | 0.2434 | **0.5756** | 0.7172 | **0.1416** | +0.0199 | 0.141 | 0.102 |
| 2 | **R17_Market_Leverage** ≡ V19_Debt_to_Market | parked(73) | 0.2597 | 0.4554 | 0.7391 | 0.2837 | +0.0029 | 0.053 | 0.207 |
| 3 | **L11_Kyle_Lambda** | parked(73) | 0.2766 | 0.4495 | 0.7618 | 0.3123 | +0.0013 | 0.049 | 0.228 |
| 4 | **V08_PSR** ≡ V20_SP | parked(73) | 0.2051 | 0.3467 | 0.6655 | 0.3188 | +0.0012 | −0.024 | 0.229 |
| 5 | **L25_Amihud_Vol** | parked(73) | 0.3008 | 0.4628 | 0.7942 | 0.3314 | +0.0005 | 0.059 | 0.242 |
| 6 | **R11_Systematic_Risk** | uncond(268) | **0.0852** | 0.1690 | 0.5005 | 0.3315 | +0.0008 | −0.146 | 0.231 |
| 7 | **R18_Book_Leverage** | parked(73) | 0.3006 | 0.4600 | 0.7938 | 0.3338 | +0.0005 | 0.057 | 0.244 |
| 8 | **XF_LL02_NetDebt** | parked(73) | 0.2339 | 0.3692 | 0.7045 | 0.3353 | +0.0005 | −0.008 | 0.242 |
| 9 | **V06_fDY** | parked(73) | 0.2754 | 0.4197 | 0.7603 | 0.3406 | +0.0004 | 0.028 | 0.247 |
| 10 | **L01_Amihud** | parked(73) | 0.3112 | 0.4525 | 0.8079 | 0.3554 | −0.0001 | 0.051 | 0.260 |
| 11 | V05_fPBR | parked(73) | 0.2397 | 0.3541 | 0.7123 | 0.3583 | +0.0001 | −0.019 | 0.259 |
| 12 | V13_EV_Sales | parked(73) | 0.2177 | 0.3016 | 0.6825 | 0.3809 | −0.0000 | −0.055 | 0.273 |
| 13 | CR11_Idiosyncratic_Return | uncond(268) | 0.0973 | 0.1257 | 0.5173 | 0.3916 | −0.0000 | −0.176 | 0.273 |

### 축 분해에서 읽히는 것

- **가장 가까운 V18_AM 조차 필요 IR 의 80.3%(0.5756/0.7172)** 이고, 그다음부터는 62% 이하로 떨어집니다.
- **11/13 이 파킹 arm** 입니다. 파킹이 근접군을 만들었습니다.
- **rho_needed 가 음수인 항목이 5건** 입니다(V08_PSR −0.024, XF_LL02 −0.008, V05_fPBR −0.019, V13 −0.055, CR11 −0.176, R11 −0.146). 이 재료들은 **상관을 0 으로 만들어도 통과하지 못합니다** — IR 축이 단독으로 부족합니다. 반면 V18_AM 만은 상관을 0.243→0.141 로 0.102 더 내리면 현재 IR 그대로 통과합니다. 즉 **"상관만 더 내리면 되는" 재료는 331 중 실질 1건**입니다.
- 근접군의 가족 구성이 셋뿐입니다: **레버리지/밸류**(V18_AM=Asset/Market, R17, V19, R18, XF_LL02, V06_fDY, V05_fPBR, V13, V08/V20) · **유동성**(L25, L01, L11) · **체계위험 분해**(R11, CR11). 조합(§7 P1)의 직교성 전망을 바로 제약하는 사실입니다.

---

## 4. 파킹 레버의 전수 효과 — 48표본과 같은가

동일 팩터 내 짝지음(n=328). **★두 arm 은 창이 다릅니다(268개월 vs 73개월)** — 아래 paired 통계는 레버 방향 진단이며, 문턱 판정 근거로 쓰지 않았습니다. 각 arm 은 문턱 0.05 와만 대조했습니다.

| 지표 | 평균 차 (park − uncond) | paired t | p | 개선 건수 |
|---|---|---|---|---|
| incumbent 상관 | **−0.0854** | **−24.442** | <2e-16 | **304 / 328 (92.7%)** |
| 슬리브 IR | −0.0075 | −0.403 | 0.687 | 156 / 328 (47.6%) |
| ΔIR (best-over-w) | **+0.0158** | **+20.000** | <2e-16 | **279 / 328 (85.1%)** |
| 부족분 | −0.1045 | — | 194 / 328 (59.1%) |

**48표본 결과가 331 전수에서 재현되었습니다.** 상관 인하 +0.405→+0.317 (paired t −6.983, 37/48) ↔ 전수 0.420→0.324 (paired t −24.442, 304/328) 로 방향·크기 정합입니다. ΔIR 개선도 48/48 ↔ 279/328 로 재현됩니다.

**단 재현되지 않은 것이 하나 있습니다: 슬리브 IR 은 파킹으로 개선되지 않습니다** (paired t −0.403, p 0.687, 개선 156/328 = 동전던지기). 파킹이 움직이는 것은 상관 성분이지 신호력이 아닙니다. 그래서 **파킹 적용 후에도 통과 0/328** — 48표본의 "재료 IR 부족이 지배"가 전수에서 그대로 성립합니다.

파킹이 문턱을 내리는 폭도 정량화됩니다: 필요 IR 중앙이 **1.030 → 0.914 (−0.116)** 로 내려가지만, 재료 IR 중앙은 −0.083 → −0.090 으로 움직이지 않습니다. **문턱을 0.116 내리는 레버로는, 부족분 중앙 0.914 를 메울 수 없습니다.**

---

## 5. 기전 유형별 사망 건수 (best arm 기준, 331)

| 유형 | 정의 | 건수 |
|---|---|---|
| **둘 다 부족** | ρ ≥ 0.3 **∧** IR < 0.5 | **244 (73.7%)** |
| **IR 부족 단독** | ρ < 0.3 (직교성 확보) ∧ IR < 0.5 | **83 (25.1%)** |
| **상관 과다 단독** | IR ≥ 0.5 ∧ ρ ≥ 0.3 | **0** |
| **양축 느슨한 기준 통과, 그래도 미달** | ρ < 0.3 ∧ IR ≥ 0.5 | **1** (V18_AM) |
| **커버리지 (판정 불가)** | 파킹 창 겹침 부족 | **3** |
| 귀무 미분리 | — | 해당 없음 (사냥 단계에서 귀무 검정 미실시 — §6·§9 참조) |

**"상관 과다 단독" 이 0건**이라는 것이 이 라운드의 핵심 기전입니다. 상관이 높아서 떨어진 재료는 없습니다 — 전부 IR 이 먼저 무너집니다. IR ≥ 0.5 인 재료가 331 중 **1건**(V18_AM 파킹 0.5756)뿐이고, 그 1건조차 ρ 0.243 에서 필요치 0.717 에 0.142 미달합니다.

**커버리지 3건 (0 이 아니라 원인 규명):**
- `Q16_Debt_to_Assets` — 파킹 겹침 11개월 (require 60). 무조건부 arm 은 정상 측정(n=155, ΔIR −0.157).
- `SE02_Consensus_Revision` — 파킹 겹침 58개월 (문턱 60 에 2개월 미달). 무조건부 정상(n=224, ΔIR −0.129).
- `D60_Leverage` — 파킹 겹침 11개월. 무조건부 정상(n=155).
세 건 모두 계산 실패가 아니라 팩터 커버리지와 FQ-191 라벨 창(2019-12~2025-12)의 겹침 부족입니다.

**명목 331 ≠ 유효 독립 재료.** (ρ, IR) 6자리 동일 벡터 검사 결과 무조건부 arm 에 18그룹, 파킹 arm 에 26그룹의 중복이 있습니다 — **유효 독립 재료는 307(무조건부) / 295(파킹)** 입니다. 최대 그룹은 6개 동일: `MK01_CAPM_Beta == D31_Relative_Beta == D10_Blume_Adj_Beta == D18_BAB_Rank == D02_Beta == D11_FP_Beta`. 근접표의 R17≡V19, V08≡V20 도 이 계열입니다. "331 전수"는 명목 개수이며, 실효 탐색 폭은 그보다 11% 작습니다.

---

## 6. 자본 주장 경계 (넘지 않은 선)

1. **자본 편입 주장 없음.** 생존 0 이므로 admit 대상 자체가 없습니다. governor admit(`book_state` 쓰기)은 어떤 경우에도 자동화 금지이며 도훈 수동 confirm 사항입니다.
2. **ΔIR 은 weight·창 조건부 국소량**입니다. 본 보고의 모든 ΔIR 에 arm(창)과 w 를 병기했습니다. 파킹 arm 수치는 73개월·2020-02~2026-02 창의 값이며 전 기간 값이 아닙니다.
3. **슬리브 PORT_t 를 자본 문턱 2.95 옆에 놓지 않았습니다.** 샤드5가 산출한 슬리브 standalone PORT_t(중앙 −0.1318, 범위 −1.92~+1.36)는 후보 벤치 빈티지 기준이며 본 판정에 쓰지 않았습니다. book-marginal 과 standalone graduation 은 다른 문턱입니다.
4. **근접군의 통계적 지위** — 슬리브 IR 을 함의 t (= IR·√(n/12), 독립월 가정)로 환산하면 파킹 arm 최대 **1.420**(V18_AM), 무조건부 최대 **1.870**(IN03_RD_to_Market)입니다. **|t|>2 인 파킹 재료는 328 중 1건**입니다. 파킹 ON 26개월이 에피소드 14개에 묶이므로 유효표본을 에피소드로 잡으면 t 는 √(14/73)=0.438 배로 줄어 **V18_AM t 1.420 → 0.622** 가 됩니다. **근접군 전체가 0 과 구분되지 않습니다** — 근접 순위를 "가능성 있는 후보"로 읽어서는 안 되고, "부족분이 작은 방향"으로만 읽어야 합니다.
5. 참고로 통과에 필요한 IR 은 73개월 창에서 함의 t 1.62(ρ 0.20)~2.12(ρ 0.35) 를 요구합니다. 즉 **파킹 창의 길이 자체가 통과 증명에 빠듯**합니다.

---

## 7. next_probe (7건, 전부 사전등록 판정조건 명시)

### P1 — 조합/스택: 사전등록 통과조건 **평균 상호상관 c̄ ≤ 0.007**

EW 스택 항등을 먼저 풀었습니다. k개 슬리브를 EW 로 묶고 구성원 간 상호상관을 c 라 하면, **스택은 IR 과 incumbent 상관을 동일 배율 g = √(k/(1+(k−1)c)) 로 함께 확대합니다** (sd 정규화 하에서 정확). 즉 직교화가 공짜가 아니라 **상관도 같이 커집니다**.

파킹 arm 의 유효 독립 295건을 스택 적합도(IR − 1.31ρ) 순으로 정렬해 상위 k개 EW 스택을 쓸었습니다:

| k | 평균 IR | 평균 ρ | 통과 필요 g | c=0 일 때 가용 g=√k | 허용 최대 상호상관 c* |
|---|---|---|---|---|---|
| 2 | 0.5155 | 0.2515 | 2.044 | 1.414 | **불가** (c=0 이어도) |
| 3 | 0.4935 | 0.2599 | 2.378 | 1.732 | **불가** |
| 5 | 0.4580 | 0.2571 | 2.804 | 2.236 | **불가** |
| 10 | 0.4345 | 0.2646 | 3.248 | 3.162 | **불가** |
| 12 | 0.4170 | 0.2635 | 3.476 | 3.464 | 불가 (−0.0006) |
| **13** | 0.4138 | 0.2675 | 3.536 | 3.606 | **+0.0033** |
| **15** | 0.3976 | 0.2677 | 3.688 | 3.873 | **+0.0073** |
| 16+ | 0.3893 | 0.2666 | 도달불가 | 4.000 | 불가 |

**해석**: k ≤ 12 에서는 구성원이 완전히 상호직교(c=0)여도 통과 불가입니다. k=13~15 의 좁은 창에서만 가능하고, 그때 요구되는 **평균 상호상관이 0.007 이하** — 사실상 완전 직교입니다. 무조건부 arm 은 **어떤 k 에서도 c=0 가정하에서조차 불가**(k=2 에서 필요 g 9.71, 이후 도달불가)입니다.

- **측정 설계**: 파킹 arm 적합도 상위 15 슬리브의 **실제 15×15 active 상관행렬**을 산출하고, 실제 EW 스택 시계열을 `bm_delta_ir()` 로 통과시킵니다.
- **사전등록 판정**: 실측 평균 상호상관 c̄ ≤ 0.007 → 조합 축 열림 / c̄ > 0.007 → 이 재료집합에서 조합 축 config-scoped 미달.
- **예상(반증 가능)**: 상위 15 가 레버리지·밸류·유동성 3가족이므로 c̄ 는 0.007 을 크게 웃돌 전망입니다. 이 예상이 맞으면 조합 축은 **재료 교체 없이는** 열리지 않습니다.
- **동반 귀무 의무**: 상위-k 선택은 73개월 in-sample 선택입니다. 무작위 k개 스택 200회 귀무를 함께 돌려 선택 이득을 분리해야 합니다([[project-episode-count-not-month-count-binds-20260809]] — 선별 후 검정은 귀무도 같은 선별로).

### P2 — 비-return 원천 (최우선): DB 의 (ρ, IR) 지지집합 밖에 답이 있음이 실측됨

계약수주 국면규칙 슬리브(메인 세션 확정: ρ 0.140 · 슬리브 IR 0.758 · ΔIR +0.0740)를 동일 프레임에 넣으면 **가중 무제약 천장 +0.1087**, 통과에 필요한 상관 상한 0.277 (관측 0.140 → 여유 0.137) 로 **단독 통과(req_g = 1.00)** 입니다.

그런데 DB 331 을 같은 자로 재면:

| 조건 | 331 중 해당 건수 |
|---|---|
| 슬리브 IR ≥ 0.758 | **0** |
| incumbent 상관 ≤ 0.140 | **3** (D24 0.083 · R11 0.085 · CR11 0.097) |
| **둘 다 (동일 arm)** | **0** |

**계약 슬리브는 DB 331 의 관측 지지집합 밖에 있습니다 — 두 축 동시에.** 이것이 "더 센 알파가 아니라 다른 원천"의 실측 근거입니다.

- **측정 설계**: FQ 큐의 비-return 원천(DART exec-insider 역사 · 계약금액 magnitude · 공매도/대차 · 뉴스)을 본 라운드와 **동일한 2-arm 프레임**(무조건부 268개월 + FQ-191 파킹 73개월, weight sweep 5점, `bm_delta_ir()` 계약 경로)으로 측정.
- **사전등록 1급 판정**: ρ ≤ 0.277 **∧** IR ≥ need_ir(ρ). 2급으로 갈아타지 않습니다([[feedback-preregistered-primary-fails-that-is-the-verdict]]).
- **착수 전 사전 확인**: 각 원천의 패널 커버리지 개월수와 FQ-191 창 겹침을 먼저 실측합니다(본 라운드에서 커버리지로 3건이 판정 불가였습니다).

### P3 — 파킹 라벨 개선: 필요 인하폭이 정량화됨

FQ-191 라벨의 상관 인하폭은 전수 실측 **−0.0854**(중앙 −0.0899)입니다. 근접군이 통과하려면 필요한 추가 인하폭 `gap_ρ` 는 **0.102(V18_AM) ~ 0.273** 입니다. 즉 **FQ-191 급 라벨 하나로 사거리에 드는 재료는 V18_AM 1건**이고, 나머지는 라벨 2~3개 분량의 인하가 필요하거나(그리고 그 사이 IR 이 보존되어야 하거나) IR 축이 단독으로 부족해 라벨로는 도달 불가입니다.

- **측정 설계**: 라벨 후보 격자 × 근접 12재료. 라벨 후보 = β_R05 국면 · vol-state · bear-prob · 유동성 국면 · 계약수주 국면(FQ-138 t-1 FROZEN 규칙). 각 (라벨 × 재료) 셀에서 Δρ 와 ΔIR 을 동시 산출.
- **사전등록 1급 = Δρ (상관 인하폭)**, 2급 = ΔIR. 1급이 미달하면 그것이 판정입니다.
- **필수 통제 3종**: ① 무작위 파킹 200회 귀무 (48표본에서만 검정됐고 331 에서 재검정하지 않았습니다) ② 라벨별 발화율·에피소드 수를 분모 계약으로 고정(`eligible_from`/`target_rate`) ③ **C5 오버레이 타이밍** — 라벨은 홀딩월 시작 전 데이터로만, `assert_overlay_pit()` HARD 통과 + lag1 스트레스 + strict-PIT A/B.

### P4 — 형태-조건부/밴드 소비가 ΔIR 을 올리는가

근접 12재료를 top-25 랭킹이 아니라 **decile 형태**(MONOTONE_TOP / HUMP / INVERTED)로 먼저 라벨하고, 형태에 따라 소비면(밴드 보유 / 북 종목 필터 / 랭킹)으로 라우팅한 뒤 ΔIR 을 잽니다. 근거는 같은 규칙이 형태에 따라 +2.881 / −3.430 으로 갈린 실측([[project-shape-is-routing-label-not-alpha-20260809]])과, 랭킹이 죽은 재료가 필터로는 ΔIR +0.169 였던 실측([[project-consumption-path-changes-verdict-20260802]])입니다.

- **사전등록**: 형태 라벨 → 소비면 매핑을 **재료를 보기 전에** 고정. 음성대조(형태가 반대인 재료 2건은 이득이 없거나 음수여야 함) 동반. 겹침률·유효분위·동일강도 무작위 대조군 3종 필수.

### P5 — (데이터에서 본 것) 잔차화 강도 λ 스윕: 이 DB 에서 직교성은 "β 제거"로만 옵니다

상관 하위 4건이 **0.083 / 0.085 / 0.097 / 0.199** 인데, 앞 3건이 전부 체계위험 분해 계열(`D24_Systematic_Risk_Prop`, `R11_Systematic_Risk`, `CR11_Idiosyncratic_Return`)이고 4위와 사이에 **0.097 → 0.199 의 단절**이 있습니다. 그리고 이 3건의 IR 은 0.083 / 0.169 / 0.126 으로 전부 작습니다. 무조건부 arm 의 스택 적합도(IR − 1.31ρ) 상위 2건도 R11(+0.053)·CR11(−0.007) 로 같은 계열입니다.

**읽히는 것**: 이 DB 에서 PG2 와의 직교성은 "다른 정보를 담아서"가 아니라 **"시장 성분을 벗겨서"** 옵니다. 그리고 벗기면 신호도 함께 깎입니다. 이 교환비가 정확히 어떤 곡선인지는 측정된 적이 없습니다.

- **측정 설계**: 근접군 상위 6재료를 λ ∈ {0, 0.25, 0.50, 0.75, 1.00} 으로 **부분 잔차화**(β 성분을 λ 만큼 제거)한 뒤 각 λ 에서 (ρ, IR, ΔIR) 궤적을 산출.
- **사전등록 falsifier**: ΔIR(λ) 가 λ 에 단조 감소면 잔차화 축은 config-scoped 미달로 표시. **내부 최댓값(λ\\* ∈ (0,1))이 존재하면 λ\\* 채택 후 재측정.** 판별식은 명시적입니다 — 요구조건 지도의 기울기가 dIR/dρ ≈ 1.31 이므로, **|dIR/dλ| < 1.31·|dρ/dλ|** 인 구간에서만 잔차화가 이득입니다.
- 이 probe 는 새 재료를 필요로 하지 않고 기존 패널만으로 돌아갑니다.

### P6 — 파킹을 슬리브가 아니라 book 에 직접 걸기

파킹 레버는 전수에서 상관을 92.7% 확률로 내리고 ΔIR 을 85.1% 확률로 올렸습니다(§4). 이 레버를 슬리브 탐색과 분리해서, **PG2 자체를 FQ-191 OFF 구간에 벤치로 파킹**했을 때의 book 성과를 직접 잽니다. 슬리브를 찾지 못해도 소비 가능한 유일한 레버입니다.

- **사전등록**: 1급 = book IR 변화(전환비용 15bps 포함) · 2급 = MDD. **C5 의무 3종**(assert_overlay_pit HARD · lag1 스트레스 · strict-PIT A/B, 인플레 >5% 면 strict 값으로 재판정). 무작위 파킹 200회 귀무 동반.
- **주의**: 오버레이 게이트가 ΔIR 단독이면 MDD 레버를 못 봅니다([[project-regime-overlay-chain-depth-axis-20260809]]) — 두 지표 병기 의무.

### P7 — 근접 순위가 창-특정인지 재료-특정인지 분리

근접군 11/13 이 73개월 파킹 창에서 나왔고, 같은 재료의 무조건부 268개월 IR 은 무너집니다(V18_AM 0.5756 → **0.1318**, R18_Book_Leverage 0.4600 → **−0.1768**, L11_Kyle_Lambda 0.4495 → **−0.0856**, IN03_RD_to_Market 은 반대로 0.3943 → **−0.3690**). 부호가 뒤집히는 건이 있다는 것은 근접 순위가 창의 산물일 가능성을 직접 시사합니다.

- **측정 설계**: FQ-191 과 **동일한 규칙 정의로 2004~ 전 기간 재구성 가능한 라벨**을 만들어(가능하면) 근접 상위 12건을 재측정. 불가능하면 73개월을 3분할(anchored)해 IR 안정성을 잽니다.
- **사전등록**: 분할 3구간 중 2구간 이상에서 IR > 0 이면 재료-특정, 아니면 창-특정으로 라벨하고 근접 순위를 폐기.

---

## 8. 소비면 (자본 편입이 아니어도 쓸 곳) — 7종 순회

| # | 소비면 | 본 라운드가 준 것 | 상태 |
|---|---|---|---|
| ① | 팩터 랭킹 | 331 전건 book-marginal 음수 — 랭킹 소비로는 쓸 것 없음 | 닫힘 (실측) |
| ② | 유니버스 필터 | `D24_Systematic_Risk_Prop`(ρ 0.083) · `R11_Systematic_Risk`(0.085) · `CR11_Idiosyncratic_Return`(0.097) = **DB 에서 PG2 와 직교한 유일한 3축**. 랭킹으로는 죽었으나 필터·배제 규칙으로는 미측정 | **FQ 등재 · P4 와 결합** |
| ③ | 오버레이/국면 입력 | **파킹 레버 자체**(전수 상관 −0.0854, t −24.44; ΔIR +0.0158, t +20.0) — 슬리브 없이 book 에 직접 적용 가능 | **P6 로 즉시 착수 가능** |
| ④ | 위험모델·β예산 | 331 × incumbent 상관 분포(중앙 0.4203, min 0.0831, max 0.5562) = PG2 의 팩터 노출 지도. 잔차 축 계측기로 ②의 3재료 사용 | 배관 있음, 소비자 미배선 |
| ⑤ | monitoring 신호 | 상관 분포가 스타일 드리프트 경보의 기준선. 근접 12재료의 ρ 가 창별로 이동하는 폭(무조건부 0.24~0.33 → 파킹 0.20~0.31) 이 정상 변동폭 | FQ 등재 |
| ⑥ | 선별 라벨 | **중복 벡터 26그룹 목록** = registry 위생. `MK01_CAPM_Beta`/`D02_Beta`/`D10_Blume_Adj_Beta`/`D11_FP_Beta`/`D18_BAB_Rank`/`D31_Relative_Beta` 6개 동일 벡터 등 — 유효 독립 295~307 | **즉시 소비 (별도 태스크 칩)** |
| ⑦ | 타 모드 이식 | RAMP 팩터군 구성 시 이 상관 지도를 사전 입력으로 사용하면 R1 의 "sleeve 불완전직교 β≈0.92" 진단과 직접 연결. FR 국면 배분에는 §4 파킹 레버 | FQ 등재 |

**부수 산출(별도 태스크)**: PG2 `04_holdings.csv` 가 0행이라 보유 겹침 분석이 불가했습니다. 본 라운드는 ΔIR 직접 측정만으로 판정했으므로 영향이 없었지만, ②·④ 소비면은 보유 겹침을 요구합니다 — production 결손 수리가 선행 조건입니다.

---

## 9. 이 라운드 설계의 약점 3개 (자가 지적)

**약점 1 — 근접군 전체가 통계적으로 0 과 구분되지 않는데, 순위를 매겼습니다.**
파킹 arm 슬리브 IR 의 함의 t 는 최대 1.420 이고, |t|>2 인 재료가 328 중 1건입니다. 에피소드(14개) 보정 시 최대 t 는 0.622 로 떨어집니다. 즉 "부족분 0.1416 인 V18_AM 이 1위" 라는 서술은 **순위 자체가 잡음일 수 있는 자 위에서 매긴 순위**입니다. 게다가 같은 재료의 무조건부 268개월 IR 은 0.1318 로 무너지고, 근접군 여러 건에서 부호가 뒤집힙니다. §7 P7 이 이 약점의 직접 반증 설계이며, **그 결과가 나오기 전까지 근접 목록은 "후보 명단"이 아니라 "부족분이 작은 방향 표시"로만 읽어야 합니다.** 판정(생존 0)에는 영향이 없습니다 — 잡음이든 아니든 문턱을 넘지 못했습니다.

**약점 2 — 조합·천장 분석에서 측정하지 않은 것을 모델로 대체했습니다.**
가중 무제약 천장과 스택 경계는 sd 정규화(k=1) 해석해와 **EW·동질 상호상관 c** 가정 위에서 계산했습니다. 해석해는 메인 세션 실측 3점(+0.3012 / 0.0000 / 0.925)과 일치하고 V18_AM 에서 실측 +0.0201 vs 해석해 +0.0199 로 근접하지만, **331 전건에 대한 parity 검증은 하지 않았습니다.** 특히 스택 항등(IR 과 ρ 가 같은 배율로 확대)은 EW·동질 c 에서만 정확하고, 최적가중 스택이나 이질 상관행렬에서는 다를 수 있습니다. **실제 15×15 상관행렬을 재지 않고 c* = 0.007 이라는 판정선을 그은 것이 이 라운드의 가장 큰 미측정 지점**이며, 그래서 P1 을 사전등록 판정조건이 붙은 실측 probe 로 남겼습니다.

**약점 3 — 프레임 자유도 3개가 통제되지 않았습니다.**
① **파킹 라벨**: FQ-191 은 이 라운드 밖에서 선택된 단일 라벨입니다. 무작위 파킹 대비 우월성은 48재료에서만 검정(paired t +4.075, p 0.00018)됐고 331 에서 재검정하지 않았습니다. ② **소비 형태**: 모든 슬리브를 top-N 랭킹 형태로만 소비했습니다 — 밴드·필터 형태는 재지 않았습니다(P4). ③ **weight 격자**: 사냥은 {0.05~0.30} 5점이었고, 샤드 3·4·7 은 w=0.20 값을 남기지 않아 pooled w=0.20 분포가 207/331 부분표본입니다. ③은 사후에 가중 무제약 천장(331 전건)으로 메워 판정 영향을 없앴지만, ①②는 남아 있습니다. 또한 **명목 331 중 유효 독립이 295~307** 이므로 "전수"라는 표현은 명목 기준입니다.

**추가 자가 검거 1건**: 초안에서 파킹 arm 의 ΔIR 개선(paired t +20.0)을 "파킹이 성과를 개선한다"로 쓸 뻔했습니다. 실제로는 슬리브 IR 이 전혀 개선되지 않았고(t −0.403, p 0.687), ΔIR 개선은 **상관 인하 성분 + 창 차이(268개월 vs 73개월)의 혼합**입니다. 두 arm 의 창이 다르므로 arm 간 ΔIR 비교는 판정 근거가 될 수 없고, 각 arm 을 문턱 0.05 와만 대조했습니다.

---

## 부활 조건 (INV-7)

이 라운드의 negative 는 **config-scoped** 입니다 — 프레임은 (재료 = Factor DB 331 · 소비 = top-N 랭킹 슬리브 · 파킹 = FQ-191 단일 라벨 · incumbent = PG2 noLayer4 · 문턱 = ΔIR 0.05 @ w≤0.30) 입니다. 아래 신호 중 하나라도 발화하면 재검토 대상입니다.

1. P1 실측에서 근접 15 의 평균 상호상관이 **0.007 이하**로 나올 때 (조합 축 재개)
2. P5 잔차화 λ 스윕에서 **내부 최댓값 λ\\* ∈ (0,1)** 이 관측될 때 (직교화 교환비가 유리한 구간 존재)
3. 비-return 원천이 (ρ ≤ 0.277 ∧ IR ≥ need_ir(ρ)) 셀에 진입할 때 — 계약 슬리브가 이미 이 셀에 있으므로 **이 조건은 실증적으로 도달 가능**합니다
4. 파킹 창이 73개월에서 확장되어 근접 상위 12건이 재료-특정으로 재라벨될 때 (P7)
5. PG2 incumbent 가 교체되어 IR 1.4160 이 내려갈 때 — 필요 IR 은 incumbent IR 에 선형에 가깝게 붙어 있으므로 문턱 전체가 함께 내려갑니다
```"
  },
  "workflowProgress": [
    {
      "type": "workflow_phase",
      "index": 1,
      "title": "사냥"
    },
    {
      "type": "workflow_phase",
      "index": 2,
      "title": "검증"
    },
    {
      "type": "workflow_phase",
      "index": 3,
      "title": "종합"
    },
    {
      "type": "workflow_agent",
      "index": 1,
      "label": "hunt:shard0",
      "phaseIndex": 1,
      "phaseTitle": "사냥",
      "agentId": "afbca3f448f6cbf92",
      "model": "claude-opus-5",
      "state": "done",
      "startedAt": 1786276309249,
      "queuedAt": 1786276306634,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,d…",
      "promptPreview": "당신은 Qvest QEPM 리서치 에이전트다. 작업 디렉토리 C:/Users/99922/OneDrive/Quant_Module_Moltbot 에서 R 로 실측한다.

## 실행 규율 (위반 = 결과 무효)
- R 은 **반드시 스크립트를 Write 로 작성한 뒤** `Rscript -e 'source("경로")'` 로 돌린다.
  `Rscript -e` 에 코드를 직접 넣지 말 것 — 한글·이스케이프가 조용히 깨진다(실사고 전력).
- 측정의 첫 출력은 **입력 실측**(행수·개월수·범위)이다. 입력 형태를 가정하지 말 것.
- 수치는 계약 경로로만: canonical_screen_bt() / bm_delta_ir() / bm_delta_ir_sweep().
  손계산 금지: prod(1+r) · cumpr…",
      "lastProgressAt": 1786276742595,
      "tokens": 114872,
      "toolCalls": 15,
      "durationMs": 433346,
      "resultPreview": "{"n_measured":41,"n_failed":0,"results_csv":"factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,dIR_park,best_arm,best_dIR,best_w\
V06_fDY,255,0.3758,-0.0487,-0.1466,0.2754,0.4197,-0.0100,parked,0.00037,0.05\
Q24_Altman_Z,268,0.3270,-0.0695,-0.1596,0.3165,0.3751,-0.0257,parked,-0.00309,0.05\
D22_Tracking_Error,268,0.3675,-0.2986,-0.1713,0.2821,0.3114,-0.0257,parked,-0.00333,0.05\
V14_EBIT_E…"
    },
    {
      "type": "workflow_agent",
      "index": 2,
      "label": "hunt:shard1",
      "phaseIndex": 1,
      "phaseTitle": "사냥",
      "agentId": "ac4ed9006867b9f0e",
      "model": "claude-opus-5",
      "state": "done",
      "startedAt": 1786276309282,
      "queuedAt": 1786276306634,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,d…",
      "promptPreview": "당신은 Qvest QEPM 리서치 에이전트다. 작업 디렉토리 C:/Users/99922/OneDrive/Quant_Module_Moltbot 에서 R 로 실측한다.

## 실행 규율 (위반 = 결과 무효)
- R 은 **반드시 스크립트를 Write 로 작성한 뒤** `Rscript -e 'source("경로")'` 로 돌린다.
  `Rscript -e` 에 코드를 직접 넣지 말 것 — 한글·이스케이프가 조용히 깨진다(실사고 전력).
- 측정의 첫 출력은 **입력 실측**(행수·개월수·범위)이다. 입력 형태를 가정하지 말 것.
- 수치는 계약 경로로만: canonical_screen_bt() / bm_delta_ir() / bm_delta_ir_sweep().
  손계산 금지: prod(1+r) · cumpr…",
      "lastProgressAt": 1786276820247,
      "tokens": 118034,
      "toolCalls": 15,
      "durationMs": 510965,
      "resultPreview": "{"n_measured":42,"n_failed":0,"results_csv":"factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,dIR_park,best_arm,best_dIR,best_w\
L16_Turnover_Vol,268,0.4298,-0.3297,-0.0454,0.2589,0.2585,-0.0041,parked,-0.0041,0.05\
L24_Range_per_Vol,268,0.4008,0.1739,-0.0201,0.3206,0.3237,-0.0043,parked,-0.0043,0.05\
V23_RAFI_Weight,268,0.3276,-0.0657,-0.0179,0.2916,0.2707,-0.0043,parked,-0.0043,0.05\
V0…"
    },
    {
      "type": "workflow_agent",
      "index": 3,
      "label": "hunt:shard2",
      "phaseIndex": 1,
      "phaseTitle": "사냥",
      "agentId": "a21579085699191e8",
      "model": "claude-opus-5",
      "state": "done",
      "startedAt": 1786276309456,
      "queuedAt": 1786276306634,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,d…",
      "promptPreview": "당신은 Qvest QEPM 리서치 에이전트다. 작업 디렉토리 C:/Users/99922/OneDrive/Quant_Module_Moltbot 에서 R 로 실측한다.

## 실행 규율 (위반 = 결과 무효)
- R 은 **반드시 스크립트를 Write 로 작성한 뒤** `Rscript -e 'source("경로")'` 로 돌린다.
  `Rscript -e` 에 코드를 직접 넣지 말 것 — 한글·이스케이프가 조용히 깨진다(실사고 전력).
- 측정의 첫 출력은 **입력 실측**(행수·개월수·범위)이다. 입력 형태를 가정하지 말 것.
- 수치는 계약 경로로만: canonical_screen_bt() / bm_delta_ir() / bm_delta_ir_sweep().
  손계산 금지: prod(1+r) · cumpr…",
      "lastProgressAt": 1786276702019,
      "tokens": 112963,
      "toolCalls": 12,
      "durationMs": 392563,
      "resultPreview": "{"n_measured":42,"n_failed":0,"survivors":[],"results_csv":"factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,dIR_park,best_arm,best_dIR,best_w\
AC02_Total_Accruals_BS,268,0.3983,-0.0723,-0.0385,0.3165,-0.5408,-0.0402,uncond,-0.0385,0.05\
AC10_Pct_Accruals,268,0.3154,-0.1553,-0.0316,0.3153,-0.0857,-0.0175,parked,-0.0175,0.05\
AC18_Accrual_Quality,268,0.3621,-0.0513,-0.0312,0.2698,-0.3195,-…"
    },
    {
      "type": "workflow_agent",
      "index": 4,
      "label": "hunt:shard3",
      "phaseIndex": 1,
      "phaseTitle": "사냥",
      "agentId": "a620597e84c7d71a6",
      "model": "claude-opus-5",
      "state": "done",
      "startedAt": 1786276312172,
      "queuedAt": 1786276306634,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,d…",
      "promptPreview": "당신은 Qvest QEPM 리서치 에이전트다. 작업 디렉토리 C:/Users/99922/OneDrive/Quant_Module_Moltbot 에서 R 로 실측한다.

## 실행 규율 (위반 = 결과 무효)
- R 은 **반드시 스크립트를 Write 로 작성한 뒤** `Rscript -e 'source("경로")'` 로 돌린다.
  `Rscript -e` 에 코드를 직접 넣지 말 것 — 한글·이스케이프가 조용히 깨진다(실사고 전력).
- 측정의 첫 출력은 **입력 실측**(행수·개월수·범위)이다. 입력 형태를 가정하지 말 것.
- 수치는 계약 경로로만: canonical_screen_bt() / bm_delta_ir() / bm_delta_ir_sweep().
  손계산 금지: prod(1+r) · cumpr…",
      "lastProgressAt": 1786276574203,
      "tokens": 107033,
      "toolCalls": 8,
      "durationMs": 262031,
      "resultPreview": "{"n_measured":42,"n_failed":0,"results_csv":"factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,dIR_park,best_arm,best_dIR,best_w\
CR11_Idiosyncratic_Return,268,0.097,0.126,-0.0017,0.232,0.226,-0.0033,uncond,-0.0017,0.05\
V01_BM,268,0.317,0.292,-0.0112,0.250,0.265,-0.0037,parked,-0.0037,0.05\
D41_Vol_of_Vol,268,0.430,-0.342,-0.0461,0.346,0.372,-0.0043,parked,-0.0043,0.05\
XF_DU01_NetMargin,…"
    },
    {
      "type": "workflow_agent",
      "index": 5,
      "label": "hunt:shard4",
      "phaseIndex": 1,
      "phaseTitle": "사냥",
      "agentId": "a91882ca4fa4c4c2a",
      "model": "claude-opus-5",
      "state": "done",
      "startedAt": 1786276309202,
      "queuedAt": 1786276306635,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,d…",
      "promptPreview": "당신은 Qvest QEPM 리서치 에이전트다. 작업 디렉토리 C:/Users/99922/OneDrive/Quant_Module_Moltbot 에서 R 로 실측한다.

## 실행 규율 (위반 = 결과 무효)
- R 은 **반드시 스크립트를 Write 로 작성한 뒤** `Rscript -e 'source("경로")'` 로 돌린다.
  `Rscript -e` 에 코드를 직접 넣지 말 것 — 한글·이스케이프가 조용히 깨진다(실사고 전력).
- 측정의 첫 출력은 **입력 실측**(행수·개월수·범위)이다. 입력 형태를 가정하지 말 것.
- 수치는 계약 경로로만: canonical_screen_bt() / bm_delta_ir() / bm_delta_ir_sweep().
  손계산 금지: prod(1+r) · cumpr…",
      "lastProgressAt": 1786276551153,
      "tokens": 103747,
      "toolCalls": 9,
      "durationMs": 241951,
      "resultPreview": "{"n_measured":41,"n_failed":0,"results_csv":"factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,dIR_park,best_arm,best_dIR,best_w\
V18_AM,270,0.284,0.1318,-0.0166,0.2434,0.5756,0.0201,parked,0.0201,0.2\
R17_Market_Leverage,270,0.3287,0.0819,-0.0237,0.2597,0.4554,0.0031,parked,0.0031,0.1\
L11_Kyle_Lambda,270,0.3432,-0.0856,-0.0229,0.2766,0.4495,0.0013,parked,0.0013,0.1\
V10_FCF_Yield,270,0.3…"
    },
    {
      "type": "workflow_agent",
      "index": 6,
      "label": "hunt:shard5",
      "phaseIndex": 1,
      "phaseTitle": "사냥",
      "agentId": "ab192a38025af96bc",
      "model": "claude-opus-5",
      "state": "done",
      "startedAt": 1786276308823,
      "queuedAt": 1786276306635,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "창 표기 필수 — arm1(uncond) = 전기간 겹침 268개월(2004-03~2…",
      "promptPreview": "당신은 Qvest QEPM 리서치 에이전트다. 작업 디렉토리 C:/Users/99922/OneDrive/Quant_Module_Moltbot 에서 R 로 실측한다.

## 실행 규율 (위반 = 결과 무효)
- R 은 **반드시 스크립트를 Write 로 작성한 뒤** `Rscript -e 'source("경로")'` 로 돌린다.
  `Rscript -e` 에 코드를 직접 넣지 말 것 — 한글·이스케이프가 조용히 깨진다(실사고 전력).
- 측정의 첫 출력은 **입력 실측**(행수·개월수·범위)이다. 입력 형태를 가정하지 말 것.
- 수치는 계약 경로로만: canonical_screen_bt() / bm_delta_ir() / bm_delta_ir_sweep().
  손계산 금지: prod(1+r) · cumpr…",
      "lastProgressAt": 1786276929569,
      "tokens": 117894,
      "toolCalls": 21,
      "durationMs": 620745,
      "resultPreview": "{"distribution_note":"창 표기 필수 — arm1(uncond) = 전기간 겹침 268개월(2004-03~2026-06, align_offset +2 자동적용; V11 218 · XF_GD04 252 · MA02 267 · D60 155 는 팩터 커버리지 결손), arm2(parked) = FQ191 국면창 73개월(2019-12~2025-12, ON 26, 에피소드 14). 두 arm 은 창이 달라 서로 직접 비교하지 않고 각각 문턱 0.05 와만 대조했다.\
\
[ARM1 무조건부 · n=41]\
- incumbent 상관: 중앙 +0.4256 [0.3981, 0.4585], 범위 0.2176~0.5496. 0.2 미만 0건.\
- 슬리브 IR: 중앙 -0.0901 [-0.2419, +0…"
    },
    {
      "type": "workflow_agent",
      "index": 7,
      "label": "hunt:shard6",
      "phaseIndex": 1,
      "phaseTitle": "사냥",
      "agentId": "a82941d5c38c96f8d",
      "model": "claude-opus-5",
      "state": "done",
      "startedAt": 1786276309661,
      "queuedAt": 1786276306635,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,d…",
      "promptPreview": "당신은 Qvest QEPM 리서치 에이전트다. 작업 디렉토리 C:/Users/99922/OneDrive/Quant_Module_Moltbot 에서 R 로 실측한다.

## 실행 규율 (위반 = 결과 무효)
- R 은 **반드시 스크립트를 Write 로 작성한 뒤** `Rscript -e 'source("경로")'` 로 돌린다.
  `Rscript -e` 에 코드를 직접 넣지 말 것 — 한글·이스케이프가 조용히 깨진다(실사고 전력).
- 측정의 첫 출력은 **입력 실측**(행수·개월수·범위)이다. 입력 형태를 가정하지 말 것.
- 수치는 계약 경로로만: canonical_screen_bt() / bm_delta_ir() / bm_delta_ir_sweep().
  손계산 금지: prod(1+r) · cumpr…",
      "lastProgressAt": 1786276633493,
      "tokens": 106395,
      "toolCalls": 10,
      "durationMs": 323832,
      "resultPreview": "{"n_measured":41,"n_failed":0,"results_csv":"factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,dIR_park,best_arm,best_dIR,best_w\
AC06_Comprehensive_Accruals,268,0.4253,-0.1194,-0.0431,0.3553,-0.7446,-0.0505,uncond,-0.0431,0.05\
AC14_Discretionary_Accruals,268,0.4385,-0.027,-0.0315,0.4458,0.2857,-0.0121,parked,-0.0121,0.05\
AC22_Accrual_Volatility,268,0.4443,-0.09,-0.0339,0.3434,0.0457,-0.…"
    },
    {
      "type": "workflow_agent",
      "index": 8,
      "label": "hunt:shard7",
      "phaseIndex": 1,
      "phaseTitle": "사냥",
      "agentId": "ad8cf021fac59c172",
      "model": "claude-opus-5",
      "state": "done",
      "startedAt": 1786276310387,
      "queuedAt": 1786276306635,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,d…",
      "promptPreview": "당신은 Qvest QEPM 리서치 에이전트다. 작업 디렉토리 C:/Users/99922/OneDrive/Quant_Module_Moltbot 에서 R 로 실측한다.

## 실행 규율 (위반 = 결과 무효)
- R 은 **반드시 스크립트를 Write 로 작성한 뒤** `Rscript -e 'source("경로")'` 로 돌린다.
  `Rscript -e` 에 코드를 직접 넣지 말 것 — 한글·이스케이프가 조용히 깨진다(실사고 전력).
- 측정의 첫 출력은 **입력 실측**(행수·개월수·범위)이다. 입력 형태를 가정하지 말 것.
- 수치는 계약 경로로만: canonical_screen_bt() / bm_delta_ir() / bm_delta_ir_sweep().
  손계산 금지: prod(1+r) · cumpr…",
      "lastProgressAt": 1786276724440,
      "tokens": 111911,
      "toolCalls": 16,
      "durationMs": 414053,
      "resultPreview": "{"n_measured":41,"n_failed":0,"results_csv":"factor,n,cor_uncond,ir_uncond,dIR_uncond,cor_park,ir_park,dIR_park,best_arm,best_dIR,best_w\
XF_LL02_NetDebt,270,0.2628,0.0649,-0.0110,0.2339,0.3692,0.0006,parked,0.0006,0.05\
V05_fPBR,270,0.3041,0.1544,-0.0182,0.2397,0.3541,-0.0002,parked,-0.0002,0.05\
V13_EV_Sales,270,0.3112,0.1454,-0.0173,0.2177,0.3016,-0.0008,parked,-0.0008,0.05\
L06_Zero_Trade_Days…"
    },
    {
      "type": "workflow_agent",
      "index": 9,
      "label": "synthesis",
      "phaseIndex": 3,
      "phaseTitle": "종합",
      "agentId": "a368594319d490238",
      "model": "claude-opus-5",
      "state": "done",
      "startedAt": 1786276933432,
      "queuedAt": 1786276931188,
      "attempt": 1,
      "lastToolName": "Bash",
      "lastToolSummary": "cd "C:/Users/99922/OneDrive/Quant_Module_Moltbot" && Rscrip…",
      "promptPreview": "당신은 Qvest QEPM 리서치 에이전트다. 작업 디렉토리 C:/Users/99922/OneDrive/Quant_Module_Moltbot 에서 R 로 실측한다.

## 실행 규율 (위반 = 결과 무효)
- R 은 **반드시 스크립트를 Write 로 작성한 뒤** `Rscript -e 'source("경로")'` 로 돌린다.
  `Rscript -e` 에 코드를 직접 넣지 말 것 — 한글·이스케이프가 조용히 깨진다(실사고 전력).
- 측정의 첫 출력은 **입력 실측**(행수·개월수·범위)이다. 입력 형태를 가정하지 말 것.
- 수치는 계약 경로로만: canonical_screen_bt() / bm_delta_ir() / bm_delta_ir_sweep().
  손계산 금지: prod(1+r) · cumpr…",
      "lastProgressAt": 1786277852326,
      "tokens": 162033,
      "toolCalls": 23,
      "durationMs": 918894,
      "resultPreview": "```markdown
# PG2 사냥 종합 판정 — 331 팩터 전수 book-marginal 측정

**측정 범위** 331 팩터 × 2 arm × weight 5점 · 실패 0 · 샤드 8개 통합 (`stage_artifacts/pg2_hunt/z1_pooled.csv`)
**Incumbent** `05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2` · 269개월 · net active IR **1.4160**
**문턱** book-marginal ΔIR ≥ 0.05 (measurement-graduation §4)
**통합 재산출 스크립트** `z1_pool.R` / `z2_ceiling.R` / `z3_probe_design.R` / …"
    }
  ],
  "totalTokens": 1054882,
  "totalToolCalls": 129
}
