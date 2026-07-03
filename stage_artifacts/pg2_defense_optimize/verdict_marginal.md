# 방어 재구성 5안 recon marginal — 적대검증 최종 verdict

**작성**: 2026-07-03 · Q-Lead 적대검증 · 실측-only recon-vs-recon
**대상**: PG2 noLayer4 book 방어슬리브 재구성 4후보 (c2/c3/c4/c5)
**denominator**: 현 defense {Q07,M08,Q25} EW recon, pinned_ic (convention-matched to deployed IC-sign freeze)
**게이트**: §4 book-marginal ΔIR≥0.05 · §3 oos_v2≥0.7(또는 band 보강) · paired-NW-t 유의성

---

## 0. 검증 무결성 게이트 (전부 PASS — 판정 신뢰 근거)

| 체크 | 결과 | 근거 |
|---|---|---|
| frozen 등가 | **PASS** | identity chk core+def=stored_eff max\|diff\|=0.00e+00 cor=1.000000 · 5-panel ret_orig verbatim noL4 SR=1.8947→target 1.898 · MDD 0.2329→0.233 (`parity_stored.out`) |
| pinned cache byte-identity | **PASS** | RAWDATA/benchmark pin20260703 = 현 .cache byte-identical (max\|diff\|=0) — recon drift는 carrier 재유도분(holdings/weights)뿐, rawdata vintage drift 아님 |
| base-series 교차 identity | **PASS (독립재확인)** | c2/c3/c4/c5 base 월수익 **byte-identical** (max\|b_i−b_j\|=0.00e+00, n=269 전부). → drift가 recon-vs-recon에서 실제로 상쇄됨. **swap 효과만 격리 확인** |
| carrier 재현 | **PASS** | 4후보 전부 cur\|ic recon SR=1.8196 PORT_t=5.4658 IR=1.2421 재현 (segfault-safe key-join override, 논리스캔 semantics 정확) |
| paired-NW-t 독립 재계산 | **일치** | 내 sandwich::NeweyWest lag3 재계산이 저장 JSON과 정합 (아래 §1) |

**drift 상쇄 타당성 (검증 5번)**: 통과. 동일 종목풀·동일 오버레이(m4×β_R05, 알파독립 series 전 후보 재사용)·동일 pinned cache. 방어 factor set 차이는 오직 def_z→score_eff→top-20 선택 채널로만 진입. baseline과 candidate가 같은 carrier grid를 소비하므로 vintage/carrier 잡음이 marginal에서 상쇄.

---

## 1. marginal 유의성 (paired-NW-t lag3, 독립 재계산)

| 후보 | swap | mean_d(월) | t_ord | **t_NW3** | p_NW3 | 판정 |
|---|---|---|---|---|---|---|
| c2_swap_RE07 | Q25→RE07 | +0.00017 | +0.10 | **+0.09** | 0.93 | 노이즈 |
| **c3_swap_D45** | Q25→D45 | +0.00226 | +1.56 | **+1.35** | 0.18 | 유의 미달(최선) |
| c4_augment4 | +RE07 (4팩터) | −0.00025 | −0.18 | **−0.16** | 0.87 | 음의 노이즈 |
| c5_regime | 조건부 CRISIS만 | +0.00057 | +0.82 | **+0.87** | 0.38 | 노이즈 |

**부트스트랩 dSR 밴드(2000rep, seed42)**:
- c2: dSR +0.081, 95%CI [−0.090, +0.263], P(dSR>0)=0.81 → 노이즈
- **c3: dSR +0.175, 95%CI [+0.020, +0.328], P(dSR>0)=0.987** → 유일하게 0 배제
- c4: dSR +0.123, 95%CI [−0.024, +0.271], P(dSR>0)=0.95 → CI 0 접촉
- c5: dSR +0.055, 95%CI [−0.038, +0.147], P(dSR>0)=0.88 → 노이즈

**결론**: SE±0.6~0.09 감안 시 **어떤 후보도 paired-NW-t로 유의하지 않다**(전부 \|t\|<2). SR 개선은 부트스트랩상 c3만 0 배제하나, 이는 실현 net-active(PORT_t/paired-t)가 아닌 **SR 코스메틱**(vol-ratio 0.968 = 절반이 변동성 축소 기여). 비율비교 금지 규율 준수 — paired 검정이 정본.

---

## 2. book-marginal ΔIR≥0.05 (§4 자본 문턱)

| 후보 | ΔIR(IC) | ΔIR(regdir 교차) | ΔMDD | ΔPORT_t | 문턱 통과 |
|---|---|---|---|---|---|
| c2_swap_RE07 | **−0.148** | −0.114 | −0.032 | −0.886 | ✗ (IR 훼손) |
| **c3_swap_D45** | **+0.072** | **+0.106** | −0.015 | +0.043 | **△ 양쪽 통과** |
| c4_augment4 | **−0.114** | −0.085 | −0.014 | −0.701 | ✗ (IR 훼손) |
| c5_regime | **−0.049** | +0.021 | −0.021 | −0.158 | ✗ (IC arm 미달, 부호불안정) |

**c3만이 ΔIR≥0.05를 IC·regdir 양 컨벤션에서 동시 통과**하고 PORT_t도 유일하게 양(+0.043). c2/c4는 SR·MDD 코스메틱은 좋으나 **PORT_t −0.7~−0.9, IR −0.11~−0.15로 실현 net-active 알파를 희석**(RE07 crash-beta 틸트가 China_Oil 2015 에피소드 +0.4~0.48을 만들지만 정상장 알파를 깎음). c5는 IC arm에서 ΔIR 음, regdir에서 양 — **컨벤션 부호 불안정**.

---

## 3. oos (§3, v2 3-split median)

| 후보 | oos_v2 median | recon baseline(≈0.45) 대비 | 0.7 HARD | band[0.5,0.7) |
|---|---|---|---|---|
| c2 | 0.297 | **악화** | ✗ | ✗ (<0.5) |
| **c3** | 0.365 | **악화** | ✗ | ✗ (<0.5) |
| c4 | 0.291 | **악화(−0.16)** | ✗ | ✗ (<0.5) |
| c5 | 0.430 | 동급(−0.02) | ✗ | ✗ (<0.5) |

**전 후보 oos_retention이 recon baseline(~0.45)보다 나빠지거나 동급.** c3조차 0.365로 **band 하한 0.5 미달 → 무조건 FAIL 구간**. 즉 c3의 표면 SR/IR 개선은 **OOS 안정성을 희생**해서 얻은 것 — IS 과적합 징후. 이는 cohort-wide 2017+ decay(§6 decay-pattern)와 정합하며, book 단독 게이트로는 자본급 부적격.

---

## 4. overlay 포화 국면분해 (검증 4)

**c3 crisis-vs-normal 분해** (crisis 48개월 / normal 221개월):
- crisis mean_d=+0.00192 (t=+0.56) · normal mean_d=+0.00233 (t=+1.45)
- **누적 marginal의 85%가 정상장, 15%만 위기장**

역설적 시사: c3 이득은 **위기장 집중이 아니라 정상장 broad-based lift**. 위기 이득이 오버레이(m4×β_R05 이미 현금)와 중복돼 실질 소멸한다는 우려는 c3엔 부분 회피 — 위기 기여가 애초에 작다(15%). 그러나 **정상장 lift t=+1.45로 유의 미달**, 위기장 t=+0.56로 거의 없음. 결국 어느 국면에서도 통계적으로 실재하는 이득 없음.

**c5_regime(조건부)이 c2~c4 능가하나?** — **아니다**. c5는 CRISIS/CAUTION에서만 D48_VaR+RE07로 틸트하는 AX-001 v2 조건부 설계로 가장 원칙적이나: ΔIR(IC)=−0.049(음), paired-t=+0.87(p=0.38), 에피소드 marginal이 대부분 0(정상장 미개입 설계라 base와 동일). regdir에선 ΔIR +0.021로 부호 뒤집힘. **조건부 구조의 이점이 측정상 나타나지 않음** — 오버레이가 이미 위기 현금화를 수행하므로 CRISIS-only 방어 틸트가 얹을 여지가 없다(포화 확증).

---

## ★ 최종 verdict

### (A) 낙폭방어를 전기간 IR 훼손 없이 marginal 개선하는 재구성 — 랭킹

| 랭크 | 후보 | ΔIR(IC/regdir) | ΔSR | ΔMDD | ΔPORT_t | paired-NW-t | oos_v2 | 종합 |
|---|---|---|---|---|---|---|---|---|
| **1** | **c3_swap_D45** | +0.072/+0.106 | +0.24 | −0.015 | +0.043 | +1.35 (ns) | 0.365 ✗ | IR·MDD 동시개선 유일, but 유의 미달·oos FAIL |
| 2 | c5_regime | −0.049/+0.021 | +0.075 | −0.021 | −0.158 | +0.87 (ns) | 0.430 | 부호불안정, 원칙적이나 포화 |
| 3 | c2_swap_RE07 | −0.148/−0.114 | +0.11 | **−0.032** | −0.886 | +0.09 (ns) | 0.297 ✗ | MDD 최선이나 IR·PORT_t 대폭훼손 |
| 4 | c4_augment4 | −0.114/−0.085 | +0.16 | −0.014 | −0.701 | −0.16 (ns) | 0.291 ✗ | 음의 marginal, 희석 |

낙폭방어(ΔMDD)만 보면 c2가 최선(−0.032)이나 IR을 −0.148 파괴. **IR 훼손 없이 낙폭·calmar를 개선하는 유일 후보는 c3**.

### (B) book-marginal ΔIR≥0.05 넘는 후보 유무 — **c3 단독 통과, 그러나 자본급 부적격**

**c3_swap_D45가 ΔIR≥0.05를 IC(+0.072)·regdir(+0.106) 양 컨벤션에서 유일하게 통과.** 표면상 "낙폭 우월이 book 개선으로 번역"되는 후보.

**그러나 자본 승격 권고 불가.** 3중 방어벽에서 탈락:
1. **paired-NW-t=+1.35 (p=0.18) — 유의 미달.** ΔIR·ΔSR가 SE±0.08 밴드 안 노이즈와 구분 안 됨(부트스트랩 P(dSR>0)=0.987은 SR 코스메틱, 실현 net-active paired-t는 무의). 규율(비율비교 금지·paired 정본) 적용 시 신호 실재 미입증.
2. **oos_retention 0.365 < 0.5 → §3 무조건 FAIL 구간.** band[0.5,0.7) 보강경로도 진입 불가. IS 과적합 징후(SR/IR 개선을 OOS 안정성 희생으로 획득).
3. **국면분해상 이득의 85%가 정상장 t=+1.45(ns)** — 낙폭방어 서사가 데이터로 뒷받침 안 됨(위기 기여 15%, t=+0.56).

→ **결론: book-level에서 방어슬리브 재구성은 오버레이에 포화·소멸.** 현 {Q07/M08/Q25} EW가 확정 최적. c3의 ΔIR은 문턱을 넘지만 유의성·OOS 게이트에서 자본급 미달 → forge fresh-vintage 재빌드·judge·governor 승격 **권고하지 않음**. (도훈 mandate "낙폭으로 방어 최적화"의 답: 낙폭 개선 후보는 존재하나 book IR·OOS로 번역되지 않음 — 방어군 교체 여지 없음, 별개 DB 전수조사 결론 [[project-defense-factor-db-survey-settled]]와 정합.)

### (C) c5_regime 조건부의 특별함 — 실무 권고

c5는 AX-001 v2(방어=조건부 평가)에 가장 충실한 설계(CRISIS/CAUTION만 D48_VaR+RE07 틸트, 정상장 무개입). **그러나 측정상 특별한 우위 없음**: ΔIR IC −0.049/regdir +0.021로 **부호가 컨벤션 간 뒤집혀 robust하지 않고**, paired-t +0.87(ns), 위기 에피소드 marginal도 미미(GFC +0.049, Bear +0.108이 최대). **근본 원인 = 오버레이(m4×β_R05)가 이미 CRISIS에서 현금화를 수행** → CRISIS-only 방어 틸트가 얹을 한계공간이 없음(포화). 조건부 설계의 이론적 매력이 book 레벨 실측에서 소멸.

**실무 권고**: c5 조건부 로직은 **standalone 방어슬리브가 아니라 오버레이-부재 맥락(예: RAMP 다sleeve 국면배합)에서만 가치 검증 대상**. 현 PG2 noLayer4 book에는 편입 불가 — 오버레이와 기능 중복.

---

## 검증요약

- 무결성 5게이트 전부 PASS (frozen 등가·pin byte-identity·base 교차 identity·carrier 재현·paired-t 독립정합). recon-vs-recon marginal이 swap 효과만 격리함을 **독립 재확인**.
- paired-NW-t lag3 독립 재계산: c2 +0.09 / c3 +1.35 / c4 −0.16 / c5 +0.87 — **전 후보 유의 미달**.
- ΔIR≥0.05: **c3 단독 통과**(IC+0.072·regdir+0.106), 나머지 음 또는 부호불안정.
- oos_v2: 전 후보 recon baseline(~0.45) 대비 악화/동급, c3 0.365<0.5 무조건 FAIL.
- 국면분해: c3 이득 85% 정상장(t=+1.45 ns), c5 포화 확증.
- **최종: 자본급 승격 후보 없음. 현 {Q07/M08/Q25} 방어슬리브 = 확정 최적. 오버레이 포화로 방어 재구성 book 개선 소멸.**
