# 팩터의 팩터 (Factor of Factors) — 정밀 개념 정의 (2026-07-05)

세션 실측(슈퍼팩터 6방법 + QEPM 재검증 + 비-return sweep)에 근거해 개념을 정밀화. 느슨한 용법이 낳은 5대 혼동을 각각 반증으로 해소.

## 1. 정밀 정의 — 2차 팩터(second-order factor)
팩터의 팩터 = 종목별 단일 합성점수
  **s_{i,t} = z_{i,t}' b**
- z_{i,t} = 1차 특성 노출 벡터 (327 factor DB)
- b = **1차 특성-managed 팩터들의 결합 return/공분산 구조에서 추정된** 가중 벡터
- s = SDF loading b_{t-1}=Z_{t-1}b (MVE 틸트) = 종목별 기대초과수익 대리

★"of factors"의 핵심 = **b가 팩터 집합의 집단적 거동(Fₜ=Z'ₜ₋₁Rₜ의 μ̄·Σ)에서 학습된다.** 단순 등가중 composite(b=1, 학습 없음)는 팩터의 팩터가 **아니다** — 2차 추정(meta-learning)이 있어야 한다.

## 2. 정체성 = operator × object × universe (3요소로 완전 규정)
- **Operator(추정연산자)** = b를 정하는 법: A 비지도집계(PCA/RMT) / B 지도결합(IC-weight) / C SDF추정(KNS shrinkage·IPCA·BMA) / D 결정학습(E2E·DPL·SPO+) / E 횡단면 attention(신규).
- **Object(대상)** = b가 무엇에서 추정되나: ★**raw 특성 z가 아니라 특성-managed 팩터수익 F=Z'R**(zero-invest long-short). raw z 결합은 β-오염된 다른(약한) 대상.
- **Universe(유니버스)** = F·Σ·선택의 횡단면: broad(전종목) vs deployment(K200∪KQ150). 같은 operator도 유니버스 따라 결과 상이.

## 3. 5대 혼동 (세션 실증 반증)
| # | 혼동 | 정밀 구분 (실증) |
|---|---|---|
| ① | 결합 = 팩터의 팩터 | 등가중 composite(b=1)는 2차 학습 없음. FoF는 b를 팩터 구조서 학습 |
| ② | 특성 = 팩터수익 | KNS/IPCA는 managed portfolio F=Z'R 위 작동, raw z 위 아님(초기 FWL은 β-지배 약한 대상) |
| ③ | 직교 = 기여 | 책에 잔차-직교라도 실현 PORT_t는 별개 게이트(§6). FoF 가치=순실현알파, 직교성 아님 |
| ④ | IC = PORT_t | FoF 점수 횡단 IC ≠ 배포가치. IC강한 FoF들(KNS·커버리지 t3.39·insider ICIR1.31) 전부 deployment PORT_t 전이 실패 |
| ⑤ | 유니버스 무관 | broad FoF ≠ deployment FoF. E2E broad 4.87 → 헌법 deployment 2.36 |

## 4. 전이 사슬 (가치 누출 지점 = 개념의 핵심)
```
z ──▶ F=Z'R ──▶ b(추정) ──▶ s=Zb ──▶ rank ──▶ top-25 ──▶ w ──▶ 실현 net PORT_t
   β오염    과적합       SDF loading    long-only 절단      IC≠실현
           (shrinkage)  (직접tradable아님)  ("직교≠수익")    (deployment)
```
- z→F: raw 노출 vs managed 수익 (β 오염)
- F→b: 팩터 적률 과적합 (KNS naive SR²27.5 → shrinkage 방어)
- b→s: s는 SDF loading(MVE 틸트)이지 직접 tradable 팩터 아님
- **s→top-25: long-short-최적 틸트의 long-only 절단 — SDF는 short leg를 원하나 long-only는 long tail만 보유 = "직교≠수익" 누출**
- **top-25→PORT_t: deployment 횡단면서 IC 순위 ≠ 실현 net active**

★**세션 결론: 최대 누출 = s→top-25→PORT_t의 deployment 병목.** 결합 방법이 아니라 long-only-top-25-deployment 전이가 벽.

## 5. 연산자별 실증 (operator가 정체성 — 같은 데이터 다른 b)
- A 비지도집계(RMT): 지도결합에 열위.
- B 지도결합(IC-weight): 집계 우위나 IC 천장(canonical 1.28).
- C SDF-shrinkage(KNS/IPCA/BMA): 고유값-인지 축소, deployment 졸업 미달(forge 2.36).
- D 결정학습(E2E 4.87 broad·SPO+ 실패): headline 최고나 oos-fail·hard-selection 실패.
- E 횡단면 attention(신규): 종목별독립 넘어 상호참조, broad서 강하나 deployment seed-노이즈.

## 6. 정밀 명제 (refined claim)
> **팩터의 팩터의 배포 가치는 결합 방법(operator)이 아니라 long-only-top-25-deployment 전이 병목에 의해 gated된다.** 어떤 operator로 b를 학습하든, deployment 유니버스의 IC→실현 PORT_t 전이 벽이 상한(≈1.3, screen-tier)을 정한다.

**함의(레버 재정의)**: 팩터의 팩터 연구의 레버는 "더 나은 결합(operator)"이 아니라 **전이 병목 공략** — ① long-only 절단 완화(overlay·multi-sleeve·sizing) ② 전이가 되는 신호원천(deployment-native = exec insider 등). = 기존 "SR 2.5 레버 = overlay" 실증과 정합. 즉 팩터의 팩터 자체는 SR 2.5 주역이 되기 어렵고, **전이-레버(overlay)의 입력 신호**로 위치지어야 정밀하다.
