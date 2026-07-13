# Self-Adversarial Challenge — RAMP R14 (FQ-027, cap-w×oos 퇴출 결합 chain)

- **as_of_date**: 2026-07-13 · **source_version**: RAMP_R14_v1 · **config_hash**: 0e222e5340fc3369
- **selection_type**: chain · **n_trials_lineage**: 27 (R13까지 24 + R14 3=2 arm+1 diag)
- **산출**: `outputs/ramp/r14_exitcomb_{prereg,gates,paired,conc,oossub,summary}_20260713.*` · 하네스 `02_Infrastructure/ramp/run_ramp_r14_exitcomb.R` · 로그 `.cache/_ramp_r14_20260713.txt`
- **판정 요약**: config-scoped negative (퇴출 결합 config 한정). base parity Δ=1.39e-5·ctrl_F1 R12 정확재현(Δ0.000)·IS-only 승자·2차결합 없음. best arm(C-1) cap-w 2.821·oos +0.025·HARD 0/6·max full paired +1.44(<2.0). **종결 아님.**

Opus 4.8 native adversarial reasoning으로 R14 산출을 스스로 적대 검증한다. task 지정 3 챌린지(①②③) + 자가 추가 약점(④~⑦). 각 분류 ACCEPT / PARTIAL / REBUTTAL.

---

## 태스크 지정 챌린지

### ① [ACCEPT] C-1(AND)이 F-1 궤적과 사실상 동일한가 — AND의 감쇠 조건이 비활성일 가능성
**측정**: 단일 중간점검(exit-only anchor) held당 평가 740회 중 **both-fire(순위∧감쇠) = 45회(6.1%)** = C-1 총 퇴출 45회. 대조: F-1(rank) 퇴출 72회, D-2(decay) 245회, C-2(OR) 272회. Jaccard **C-1↔base 0.956 · C-1↔F-1 0.967 · C-1↔D-2 0.956**. grace_start 227·grace_expire **0**(구조 예측대로 ExExEx 교대 → 점검 1회뿐이라 유예 만료 불가 = grace 완전 비활성).
**판정 ACCEPT**: C-1은 **base와 사실상 동일**(전 역사 45 퇴출, Jaccard 0.956)하며 F-1보다도 덜 배출한다(45<72). AND의 감쇠 조건이 F-1의 rank 퇴출을 오히려 *억제*(both⊆rank이므로 C-1은 F-1이 배출할 factor를 27건 retain). 즉 "AND의 감쇠 조건이 비활성"이 아니라 **감쇠 조건이 rank 퇴출을 축소시켜 F-1의 이점을 깎는다**(cap-w 2.937→2.821). → C-1의 cap-w 개선(vs base +0.21)은 소수 both-fire 퇴출의 효과이나 F-1 단독에 못 미침. 결합이 단일 트리거를 능가하지 못하는 직접 증거.

### ② [REBUTTAL] C-2(OR)가 과도 회전으로 비용 잠식하는가
**측정**: turnover(연) base 9.27 · C-1 9.32 · **C-2 9.27** · F-1 9.23 · D-2 9.32 — **전 모델 9.10~9.32 사실상 동일**. C-2는 272 퇴출(최다)이나 turnover 미증가(반기 full-refresh가 회전을 지배하고 퇴출-충원은 비용상 marginal).
**판정 REBUTTAL**: C-2의 열위(cap-w 2.422 < base 2.612)는 **비용 잠식이 아니다**. 기전은 **over-cleaning의 신호품질 손실** — OR-gate가 순위 이탈 *또는* 감쇠 발화 어느 쪽이든 배출하여, 아직 유효한 factor(감쇠 발화했으나 순위 건재, 또는 그 역)를 과잉 제거. cap-w는 떨어지고 EW-uni oos만 오른다(0.715). = "공격적 청소 < 정밀 지정"의 기전이 비용이 아닌 배출 대상의 신호가치임을 확증.

### ③ [ACCEPT] oos 개선이 특정 시기 아티팩트인가
**측정**: SR 2017 분해 — 전 모델 pre17 SR +1.47~+1.66 / post17 SR ≈ 0(base −0.105, C-1 +0.011, F-1 +0.035). C-1의 Δoos+0.10은 **post-2017 '덜 나쁨'(−0.105→+0.011)에 집중**. oos_post 원수치(−807 등)는 IS-SR≈0 분모의 div-by-tiny 아티팩트(무시). SR 분해는 clean.
**판정 ACCEPT**: oos 개선은 특정 캘린더 이벤트 아티팩트가 **아니라** post-2017 감쇠 국면의 미소 완화다. 어떤 퇴출 규칙도 post-2017 벽을 실질 복구하지 못함(post17 SR 최고 F-1 +0.035). = oos 천장 ~+0.12 exit-rule-invariant(R13) **재확인** — 결합이 벽을 열지 못함.

---

## 자가 추가 약점

### ④ [PARTIAL] ctrl_D2 fill-rule 불일치로 격자가 오염됐나
ctrl_D2(unified level36-fill) cap-w 2.406 ≠ R13 D-2(decay-aware fill) 2.503, Δ=−0.097. 내 통일 빌더는 fill을 level36-top으로 강제(격자 순수성)했으나 R13 D-2는 fill을 non-decaying으로 필터.
**판정 PARTIAL**: 본 라운드 격자 {base,C-1,C-2,F-1,D-2}는 **내부 정합**(전부 level36-fill) — 퇴출 술어만 변수이므로 결합 비교는 clean. R13 D-2(2.503)는 fill이 달라 이 격자 위 점이 아니며 참조로만 병기(정직 라벨). 결론("결합<단일")은 내부정합 fill 하에서 성립. 단 D-2의 fill 민감도(2.406↔2.503)는 fill-규율 자체가 소폭 레버임을 시사 → next_probe 후보(퇴출과 독립). ctrl_F1은 fill 동일이라 R12 2.937 **정확 재현(Δ0.000)** = 재구성 신뢰성 입증.

### ⑤ [ACCEPT] C-1 개선이 통계적으로 견고한가
C-1 IS paired-t = **−0.077**(사실상 0), OOS paired +2.803, full paired **+1.438(<2.0 문턱)**. IS-only 선택(chain 규율)으로는 C-1을 base와 **구별 불가**. 개선은 전적으로 out-of-sample(post-2017)에서 발생.
**판정 ACCEPT**: C-1은 **견고한 개선자가 아니다**. Δoos+0.10·cap-w+0.21은 방향성이나 IS서 zero·full paired sub-threshold. config-scoped negative가 강하게 지지됨(개선 arm 부재).

### ⑥ [REBUTTAL(+caveat)] R12→R13→R14가 사실상 exit-rule sweep로 drift하는가
3라운드가 퇴출 규칙 공간을 순차 탐색 → sweep 의심.
**판정 REBUTTAL**: 각 라운드 = 독립 기전 가설 1줄 근거(R12 비대칭 퇴출 / R13 감쇠 트리거 / R14 트리거 결합) + IS-only 선택 + 사전열거 grid argmax 아님 + holdout 반복조회 없음 = measurement-graduation §3 chain 자격 충족. **caveat**: 누적 계보가 커지면(lineage 27) sweep 재분류 압력 — 그래서 DSR을 진단용으로 계속 산출(chain→게이트 부적용)했고, DSR(post-penalty 1.2~1.7)조차 graduation 무관. verdict(negative)는 DSR·selection_type에 의존하지 않음.

### ⑦ [ACCEPT] return-derived substrate 재사용이 벽의 근원인가
R6~R14 전 라운드가 동일 return-derived(realized active NW-t) substrate 위 시간-함수형(선별/퇴출/일관성/결합) 레버. EW-uni oos는 高(D-2 0.887·D-3a 0.802)이나 cap-w oos 전부 붕괴 = **cap-tier×cap-w 벽**(FQ-015) 재확인.
**판정 ACCEPT**: 퇴출 규칙 결합(construction 축)은 이 측정 프레임(cap-w×oos, return-derived)서 **소진 지대** — honest_frame 예고대로 천장 재확인. revival_signal = 비-수익 substrate(DART insider backfill) 확보 시 결합 규율×비-수익 패널 재적용. return-derived 위 시간-함수형은 저EV.

---

## 자기합리화 detect (self-check)
- "소진/dead-end" 어휘 사용 없음 → config-scoped negative + next_probe ≥2 도출(아래).
- 정직 병기: C-1 cap-w+0.21·Δoos+0.10 = 방향성 개선이나 (a)F-1 단독에 못 미침 (b)IS서 zero·full paired<2.0 (c)HARD 0/6. 개선을 과대포장하지 않음.
- 벽 귀속 정직: cap-tier×cap-w 벽은 제약(고정 축)이지 실패 원인 아님(AX-000 따름정리) — return-derived 위 construction 레버의 한계로 정직 귀속.

## next_probe (≥2 의무)
1. **fill-규율 축(퇴출과 독립)**: ④에서 노출된 fill 민감도(D-2 2.406↔2.503) — 퇴출 트리거는 F-1(rank) 고정하고 *충원(fill) 규율*만 변주(non-decaying-preferred / rank-decay-blend). cap-w 레버가 fill에 있는지 판별(퇴출 공간과 직교, 미탐색).
2. **비-수익 substrate 결합(revival)**: DART insider backfill(2013+ 연속) 완료 시 F-1 퇴출 규율 × insider-exec 패널 결합 — return-derived 위 시간-함수형이 아닌 novel 재료에 검증된 퇴출 규율 이식. (return-derived 위 결합은 저EV로 강등)
3. **(조건부) 비대칭 grace 구조**: ExExEx 교대로 grace가 완전 비활성 — cadence_exit를 촘촘히(cadence2) 하면 진입 사이 점검 ≥2회 → C-1 grace가 실제 작동. 단 이는 회전↑ 대비 EV 낮음(오직 grace 기전 자체 검증용, 저순위).
