# R28 (FQ-041) Verdict — C06_TP_Gap frozen-book pruning 검증

**판정 1 (FQ-041 본 질문): CONFIG_SCOPED_NEGATIVE** — C06_TP_Gap pruning은 PIT-clean 기준에서 자본기여 개선 아님. book_state 무변경. R26 P1 settle 완료.

**판정 2 (본 라운드 발견, HIGH severity — Q-Lead/도훈 escalate): 저장 268m frozen 백테 패널 = same-month factor vintage 사용 → 1개월 factor look-ahead 의심.** production forward recompute(_recompute_alpha_asof.R)는 PIT-clean(T-1). judge/PIT 검증 권고.

---

## 1. 방법론 무결성 — 재구축 parity (challenge #1)

frozen 재구축 recipe를 vintage 캘리브레이션(전략 선택 아님)으로 결정. 4 cell(factor_db offset × theta) × 2 sleeve 전수 측정.

| recon 변형 | factor_db 월 | parity(median cor vs stored) | 의미 |
|---|---|---|---|
| **off=+1 stored-theta** | **same-month (M-end)** | **0.913** (R26 recon fid 0.914 재현) | stored 패널 = same-month vintage |
| off=+1 ic-theta | same-month | 0.920 | 〃 |
| off=0 stored-theta | **T-1 (M-1 end)** = production | 0.612 | production forward 경로 vintage |
| off=0 ic-theta | T-1 | 0.633 | 〃 |

**parity gate**: stored-panel basis(off=+1)는 ≥0.90 충족 → stored 기준 판정 발화 가능. off=0(clean)은 서로 다른(1개월 이른) vintage이므로 stored 대비 parity 낮은 것이 정상(구현 버그 아님) — off=0은 production _recompute와 동일 convention의 독립 PIT-clean 측정.

## 2. C06 counterfactual — 6F(-C06) vs 7F, cap-w top-25 paired NW-t(lag3)

(positive = C06 제거가 도움. IS = return-month ≤ 2024-06 (247m) / holdout = 2024-07~2026-04 (21m))

| cell | 7F PORT_t | 6F PORT_t | paired IS | paired HO | ΔIR(6F-7F) | 판정 |
|---|---|---|---|---|---|---|
| **off=0 stored-theta (PIT-clean)** | 3.058 | 3.498 | **0.850** | **1.133** | +0.079 | 미달(IS·HO<2.0) |
| **off=0 ic-theta (production path)** | 3.247 | 3.307 | **0.303** | NaN(≈0) | +0.006 | near no-op |
| off=+1 stored-theta (look-ahead basis) | 6.376 | 7.641 | 3.337 | 2.027 | +0.275 | 통과(오염 basis) |
| off=+1 ic-theta (look-ahead basis) | 6.922 | 7.095 | 1.946 | NaN(≈0) | +0.045 | near no-op |

**핵심**:
- **R26 IS-positive flag(recon paired 2.45)는 same-month(look-ahead) vintage 아티팩트** — off=+1에서만 재현(IS 3.34), PIT-clean(off=0)에선 소멸(IS 0.85).
- **production live 경로(off=0, ic-theta)에서 C06는 이미 IC-theta로 self-deweight(가중 0~0.05)** → 명시 제거는 near no-op(3.25→3.31, paired 0.30). 현행 IC 빈티지 C06_TP_Gap IC ≈ 0(clip). C06는 forward book에서 이미 사실상 자가-pruned.
- clean basis에서 C06 제거는 oos_retention 0.167→0.408·post2017_t 0.51→1.25로 소폭 방향성 개선이나 **sub-significant + HARD 미달**(oos<0.7). primary(paired IS≥2.0 ∧ HO≥2.0 ∧ ΔIR≥0.05) 불충족.
- **R26 recon holdout 붕괴(-0.60)는 recon-proxy 아티팩트** — frozen 재구축(renorm 3F-core)에선 clean HO +1.13 / look-ahead HO +2.03. 붕괴 재현 안 됨. (R26 remove-only recon과 renorm 방식 차이.)

→ **branch B + C 혼합**: C06 유지가 정답(pruning 자본개선 미검증) + proxy LOO는 vintage-noisy 재료(C06=analyst TP)에서 신뢰 불가 재확인. C02_EPS_Chg_1m 필수 불변.

## 3. 판정 2 — look-ahead 발견 (escalate)

**controlled 비교(factor_db 월만 다름, 나머지 동일)**:

| cell | PORT_t off=0 (T-1, PIT-clean) | PORT_t off=+1 (same-month) | inflation |
|---|---|---|---|
| stored·7F | 3.058 | 6.376 | **2.08×** |
| stored·6F | 3.498 | 7.641 | 2.18× |
| ic·7F | 3.247 | 6.922 | 2.13× |
| ic·6F | 3.307 | 7.095 | 2.15× |

stored 패널 직접 screen PORT_t = **5.241** (clean 3.06과 look-ahead 6.38 사이 — parity 0.913 잔차 노이즈).

**근거 3축**:
1. **parity**: stored = same-month(M-end) factor_db(off=+1) 0.913. production recompute = T-1(off=0). vintage 불일치.
2. **factor_db 내부 Date**: factor_db_201506 = 2015-06-30(M-end). `load_month_factors(sig)`도 same-month 매핑. same-month 데이터를 month-M 수익 예측에 쓰면 look-ahead.
3. **controlled PORT_t**: 오직 factor_db 월만 바꿨는데 top-25 cap-w PORT_t 2.1× — 동월 데이터의 tail(top-25) 순환성(momentum 등).

**중요 nuance (over-claim 방지)**: 저장 패널은 **clean-forward(M-end factor → M+1 수익) 예측력이 실재**(rank-IC t=5.92 > contemporaneous t=4.74). 즉 알파 자체는 진짜. 문제는 **historical 백테가 동월 vintage로 top-25 cap-w PORT_t를 ~2× 부풀린 것** + historical 패널(same-month)과 forward recompute(T-1) 간 1개월 vintage seam. **live/forward 신호는 PIT-clean** — live는 backtest 대비 하회 예상(clean IR 0.66 vs 저장 1.22, 오버레이 前).

## 4. dual-basis (M2 mandate) — cap-w 감쇠 = mega-cap 벤치 아티팩트 부분 확인

| cell | cap-w PORT_t | cap-w oos | cap-w post2017_t | EW-uni PORT_t | EW-uni oos | EW-uni post2017_t |
|---|---|---|---|---|---|---|
| 0_stored_S7 (clean) | 3.06 | 0.167 | 0.51 | 3.77 | 1.16 | 1.21 |
| 0_stored_S6 (clean) | 3.50 | 0.408 | 1.25 | 2.28 | 1.66 | 1.78 |
| 0_ic_S7 (clean prod) | 3.25 | 0.324 | 0.90 | 2.08 | 1.38 | 1.53 |

clean cap-w post-2017 감쇠(post2017_t 0.51~0.90)의 상당부분 = mega-cap 벤치 아티팩트(EW-uni post2017_t 1.21~1.78 생존). cap-w oos<0.7 FAIL이나 EW-uni oos 1.16~1.66 생존.

## 5. governance / prior 정합
- book_state 무변경. 결과 = 도훈 결정 재료(실편입 = QEPM 6-agent + 수동).
- n_trials=1 (단일 구성 C06 제거). vintage/theta cell = robustness 재현(argmax 없음, 전수 보고) → DSR sweep 게이트 부적용.
- honest prior(06-24 직교327 t>2=0 · 07-10 프로브 fleet 0)와 정합 — C06 pruning도 자본기여 부재. 단 look-ahead 발견 = 신규 frontier(negative≠dead).
- pin: 현행 factor_db 캐시(vintage tag `R28_current_20260714`, factor_ic Jun30 vintage).

## 6. next_probe
1. **P1 (escalate)**: judge/PIT-agent가 저장 268m 패널 vintage seam 검증 — historical(same-month) vs forward recompute(T-1) 1개월 불일치 확정 + true admission PORT_t 재산출(clean ~3.1). live NAV로 corroborate(backtest 하회 여부).
2. **P2**: C06 = production IC-theta에서 이미 self-deweight → book 위생상 명시 SLEEVE_CORE에서 제거해도 무해(near no-op) — 단 자본개선 아님. QEPM 파이프라인 재빌드 시 clean(T-1) convention으로 통일 권고.
