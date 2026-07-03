# Cotton (2024) Schur Complementary Allocation — 전문 지식 추출 (2026-07-02)

**논문**: Peter Cotton, "Schur Complementary Allocation: A Unification of Hierarchical Risk Parity and Minimum Variance Portfolios", arXiv:2411.05807v1 (29 Oct 2024).
**목적**: 전문 정독 → 이론·알고리즘·증명·구현 디테일 완전 추출 → PG2 충실 적용. (도훈 지시: "적당히 타협 말고 전문 해석>전체 파악>전수 활용")

## 1. 핵심 명제
HRP(De Prado 2016)와 Minimum Variance(Markowitz)는 대립 학파가 아니라 **하나의 연속체**. HRP는 quasi-diagonalization(자산 재배열)로 off-diagonal 공분산 정보(B 블록)를 사실상 폐기하는데, Cotton은 **재귀 하강 시 Schur complement로 상위 정보를 하위 클러스터에 주입**하면 top-down으로 min-variance를 정확히 복제할 수 있음을 증명. 이 연속체를 **HMV(Hierarchical Minimum Variance)** 또는 **Schur Complementary Portfolio**로 명명.

## 2. 정보품질 사고실험 (⭐ KR 적용의 이론 근거)
초과수익 0으로 두고 min-var만 목표로, **공분산 정보 품질**을 변화:
- **완전정보 극한** → 명시적 최적화(MVO)가 최선.
- **추정편차가 순전한 self-deception인 극한** → HRP(또는 균등가중)가 최선.
- **어느 학파도 지배하지 않음 — 각자의 영역.** γ가 이 연속체 위 위치를 정보품질에 따라 조절.
→ **KR 직결**: KR은 종목 적고 히스토리 짧아 공분산 추정 불안정(self-deception 위험 高). 순수 MVO(γ=1) 극단은 위험. **낮은 γ(HRP 근처)에 두되 γ>0로 일부 최적화 정보 주입**이 이론적으로 정당. 논문 §6 시뮬이 정확히 이 국면(짧은 표본)에서 γ>0가 OOS 분산 감소를 실증.

## 3. HRP 비판 (§3 — 왜 Schur가 필요한가)
- **정보 폐기**: seriation이 B 크기를 줄이나 완전 제거 못 함. 그룹1 종목이 그룹2 여럿과 강상관이면 처리 불가.
- **대칭성 위반**: Σ=등상관(1,ρ,ρ/ρ,1,ρ/ρ,ρ,1)에서 HRP는 w=(1/(3+ρ))(1,1,1+ρ) — ρ≠0이면 **틀림**(대칭 1/3이어야). 대각-only ν는 반대로 실패(고내부상관 서브포트에 과배분).

## 4. 알고리즘 (§4·§5, Table 1 — 정확한 수식)
재귀 이등분. seriated Σ를 블록분할 Σ=[[A,B],[C=Bᵀ,D]]. **핵심 변경 = A,D를 그대로 넘기지 않고 Schur 증강**:

**γ-파라미터화 (eq 5.2, 5.3)**:
- `A_c(γ) = A − γ·B·D⁻¹·C` (γ-scaled Schur complement)
- `b_A(γ) = 1⃗ − γ·B·D⁻¹·1⃗` (조건부 ones 벡터 — block inversion 항)
- 대칭: `D_c(γ) = D − γ·C·A⁻¹·B`, `b_D(γ) = 1⃗ − γ·C·A⁻¹·1⃗`

**그룹간 배분 (inter-group ratio 1/ν(A'):1/ν(D'))**:
- eq 8.4: `ν(Q,b) = 1/(bᵀQ⁻¹b)` = min-var 포트 변동성. 따라서 **적합도 = 1/ν = bᵀQ⁻¹b**.
- 그룹 A 배분 ∝ `1/ν(A') = b_Aᵀ · A_c⁻¹ · b_A`. (Table 1의 A' = (A_c⁻¹·b_A b_Aᵀ)⁻¹와 등가 — ν 계산엔 위 스칼라형이 실용적)

**그룹내 재귀 (intra-group)**:
- 증강행렬 `A'' = A_c / (b_A·b_Aᵀ)` [**원소별 나눗셈**, eq 4.2] 에 대해 재귀 호출.

**adaptive γ (footnote 2 — 중요)**: naive γ=1은 A_c의 PD를 깰 수 있음. 코드의 γ는 "A_c(γ)가 PD 유지하는 최대 γ<1을 먼저 찾아 그걸 스케일한 값". 구현: 각 레벨에서 γ를 PD 깨지지 않을 때까지 축소.

**종료 (dim≤m, 논문 m=5)**: min-variance 포트(weak shrinkage 적용).

**극단**: γ=0 → 표준 HRP 복원. γ=1 → min-variance(Σ⁻¹1⃗, rank 허용) 복원.

## 5. 증명 (Appendix A, eq 8.1-8.5)
Block inversion: `Σ⁻¹ = [[A_c⁻¹,0],[0,D_c⁻¹]]·[[1,−BD⁻¹],[−CA⁻¹,1]]`.
→ `Σ⁻¹1⃗ = [(A_c)⁻¹(1⃗−BD⁻¹1⃗); (D_c)⁻¹(1⃗−CA⁻¹1⃗)] = [(A_c)⁻¹b_A; (D_c)⁻¹b_D]`.
핵심 통찰 (8.5): 대칭계 Qx=b의 해 `Q⁻¹b = (1/ν(Q,b))·w(Q,b)` — 금융적 의미(스케일된 min-var 포트). 이걸로 5.1 재귀가 **휴리스틱이 아니라 min-var의 수학적 사실**임이 성립(ν=포트 변동성일 때).

## 6. Weak covariance shrinkage (Appendix C — 구현 필수)
min-var는 불안정(큰 long-short) 가능. Cotton의 "weak" adaptive shrinkage:
- off-diagonal을 ξ배 → **원 Σ 기준** long-only 실현분산 최소화하는 ξ 선택(short nullify + 질량 재분배 후 원 Σ로 분산 평가). 예제서 ξ=0.97.
- ν() 계산과 종료 포트 wterm 양쪽에 적용. "보통 작은 short만 남김."
- DeMiguel et al 2009(weight norm 제약)과 목표 유사, 방식 상이.

## 7. 시뮬레이션 (§6 — "HRP가 선호되는 국면")
- p=500, off-diag ρ≈0.35, true Σ = a=50~150 표본 경험공분산, 추정 Σ = o=60 관측. 종료 size 5.
- **결과**: γ>0가 OOS 포트 변동성을 **단조 감소**(~10bps/yr 수익 등가). 모든 γ가 naive 최적화·균등가중보다 우월. **γ>0가 거의 항상 도움 — 짧은표본/불안정Σ 국면(=KR 유사)에서.**

## 8. PG2 적용 설계 (내 분석 — 논문+현 구조 통합)
- PG2 = long-only 20-25종, w∈[0,0.20], Σw=1. Cotton HMV 순수형은 long-short → weak shrink + long-only 사영 + cap 필요.
- **알파-구동 caveat**: HMV는 순수 위험배분(Σ만). PG2는 알파(score_eff) 구동 → 순수 min-var는 알파 낭비(Track W 06-12 실증: HRP 변형 강sleeve 열위). **따라서 비교 3층**: (a) LinearTilt(incumbent, 알파-only) (b) 순수 Schur-HMV γ스윕(위험-only) (c) Schur-HMV × 알파틸트 결합. γ 연속체 = HRP위험(γ0)↔MVO위험(γ1), 알파는 별도 곱.
- **KR 위치 발견**: γ 스윕으로 KR PG2 최적 위치 실측. 논문 예측=낮은 γ(0.2~0.5)가 순수HRP·순수MVO 모두 우월.

## 9. 검증 게이트 (충실성 — 구현이 논문을 재현하는지)
1. **3자산 등상관** (Appendix B): γ>0 HMV가 대칭 (1/3,1/3,1/3) 복원, HRP는 (1/(3+ρ))(1,1,1+ρ)로 실패.
2. **γ=0 → HRP**: 표준 hrp()와 일치.
3. **γ=1 → min-var**: Σ⁻¹1⃗ 정규화와 일치(rank 허용, weak shrink 감안).
4. **시뮬 국면**: 짧은표본 합성Σ서 γ>0가 OOS 분산 감소(Fig1 재현).

## 10. 2순위 프론티어 연계 (Schur GO 시 layer)
- **F2 tail-dep (Lohre-Rother-Schäfer 2020)**: seriation 거리를 상관→꼬리의존으로. Cotton이 §2에서 Lohre를 seriation 변형으로 인용 — **Schur와 직교**(Schur=증강, Lohre=거리). 결합 가능: tail-거리 seriation + Schur 증강.
- **F3 regime-aware**: M4/β_R05 레짐별 Σ 재추정 → 레짐별 γ(위기=낮은γ 방어).
- **F4 계산복잡도 / F5 graph(network risk parity)**: 25종목이라 계산 비병목, graph는 tree 일반화(후순위).

## 참조
원문 텍스트: 세션 scratchpad/papers. 구현: `schur_hmv.R`. 측정: `weighted_screen_bt` 계약. incumbent: `strategy_tilt_weights.R::linear_tilt_to_penalty_qd`. 선행: Track W [[project-sr25-autonomous-program]] (HRP 변형 강sleeve 열위).
