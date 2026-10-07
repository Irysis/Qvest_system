# 전략 역할 등급 — 1계층 = 2계층 다양한 전략풀 확보 (v1 · 2026-10-06~07)

> 도훈 결정: "1계층은 2계층을 위한 전략풀 확보가 가장 중요한 목표 · 전략 성격별 카테고리별 등급" ·
> "기존 DB 분류 + 신규 논문 분류 장치 · LLM/규칙은 Q 판단 · 단독 경로 유지" · 국면 정의 = 권고안 ·
> "강화 전략 모두를 풀에 넣을 필요 없다" · "2계층 풀 구성 전환 + 미등록 대표 등록".
> 상태: **운영 배선 완료** — 정본 설정 `06_Registry/strategy_role.json` · 계약 `02_Infrastructure/contracts/strategy_role.R` ·
> 레지스트리 `06_Registry/strategy_roles.json` · 검사 `08_Tests/contracts/test_strategy_role.R`(9/9 · 양방향).

## 1. 원칙
- **규칙 기반**(측정된 수익 행동). LLM 은 충실구현 레인의 `declared_role`(논문이 주장하는 역할) 신고만 — 측정과 다르면 불일치 표식(대조용).
  근거: LLM 사전학습 기억은 C1~C15 밖 · 라벨≠행동 선례(CM '방어형').
- **단독 A(essence → Judge → BOOK) 경로 불변.** 역할 등급은 2계층 풀 편입 전용.
- 역할 통계 = **전기간 베타 하나로 만든 잔차 e = r − β·b 의 국면 내 평균 t**. 구 방어형(하락월 r−b)은 β<1 이면 기전 없이 양수 —
  베타 맞춤 잡음의 61% 가 B+(재생 2026-10-06). 국면별 베타 분리 추정은 당월 부호 분할에서 절편 왜곡(공격 A 751) — 서술용만.

## 2. 역할 5종

| 역할 | 국면 / 통계 | 근거 |
|---|---|---|
| defensive | Pagan-Sossounov 약세장 연대기(사후) 안의 잔차 t · 강건성 = Lunde-Timmermann | JAE 18(1) · JBES 22(3) · CRAN bbdetection 기본값 |
| offensive | PS 강세장 안의 잔차 t | 〃 |
| rebound | 직전 36개월 시장 DOWN 상태(월초 기지) 안의 잔차 t — 약세 후 반등형 | Cooper-Gutierrez-Hameed (2004) JF 59(3) |
| alpha | 2요인 잔차 α(시장 + 유니버스 동일가중) NW(3) t · 강세·약세 잔차 모두 ≥0 | §diversification 재생 §11.1 |
| diversifier | 기존 essence B+ 풀 대비 생성 회귀 α t(2요인 잔차) | Huberman-Kandel (1987) |

등급: A = t ≥ 2.95(HLZ) ∧ OOS 지속(anchored 55/65/75 중 2+) · B = t ≥ 1.96 ∧ OOS 지속 · C = t>0 · F.

## 3. 국면 정의 비교 재생(8종) — 왜 PS 연대기인가
월 부호·평균 미만(당월) / PS·LT(사후 연대기) / CGH 36·DM 24·추세 12·고점 −20%(월초). 정의에 따라 방어 B+ 가 9~611 로 갈렸다.
월초 상태(CGH·DM)는 약세 **이후 회복기**를 많이 담아 '방어'가 아니라 반등을 잡는다 → 별도 역할(rebound). 결과 = `role_replay/regime_def_summary.csv`.

## 4. 풀 대표(편입) — 분류 ≠ 편입
역할별 B+ 중 ⓐ 계보(paper_key)당 역할 t 최대 1개 → ⓑ 2요인 잔차 상관 군집(complete linkage · 1−τ_dup, τ_dup 0.569)마다 1개.
2026-10-07: 1,298 분류 · 역할 B+ 923 · **대표 82(41 계보)** → 카탈로그 미등록 41 등재 → 2계층 풀 **711 → 81**(역할 대표 73 + 레거시 대표 8).
전환 = `strategy_role.json pool.mode="role"` · 되돌리기 = env `QVEST_L2_POOL_MODE=legacy`.

## 5. 배선
- 일일 리프레시 `[8.1r]`: `rf_role_classify_all.R` → `rf_role_register_reps.R` → `[8.2] build_module_performance.R`(role 모드).
- 충실구현 레인: 측정 직후 `role_card.json` + 텔레그램 '역할 카드' 절 · FIDELITY `declared_role` 요구.

## 6. PIT
역할·대표 판정은 전기간 통계(essence 와 같은 성격 — 연구 판정). 2계층 로테이션이 역할 소속을 **배합 선택**에 쓸 때는 as-of 로 다시 잰다(pit.md C1 D-E).
PS·LT 연대기는 전환점 판정에 미래 창을 쓰므로 등급 산정 전용 — 2계층 as-of 소비 금지(cgh36 은 월초 기지).
