# M4×R05 초월 오버레이 연구 (2026-07-05)

**지시**: 도훈 — "현 M4×R05를 넘어서는 오버레이 연구 시작".
**베이스라인(권위, 재현검증 PASS)**: `STR_1715_on_M4_R05_noLayer4_PG2` = STR_1715 × m4 × β_R05.
no_faith 클린 = `beta_R05×m4×ret_orig − |Δβ|×15bps` (269m, 2004-02~2026-06).
- 재현(contract build_metrics/benchmark_compare, ann=12): **SR_geo 1.895 · Calmar 1.938 · MDD 0.233 · PORT_t 6.166 · net-active IR 1.406** ≈ 권위(1.898/1.943/6.214/1.416). 하네스 신뢰 확립.
- 캐시 vintage 봉인: `pinned_cache/` (18:12, md5 기록). daily_refresh 재생성 격리.

## 죽은 각도(재실행 안 함)
R05×m4 위에 **2번째 스칼라 시장타이밍층** 추가 = vol/trend/turning-point/vol-managed **4중 최종부정**([[project-pg2-offense-overlay-settled]]). 본 연구는 이 방향 재시도 아님 — 로드맵 P3의 **잔여 유효방향 2종**(게이트 형태 정밀화 + 홀딩스-레벨 구성)만 실측.

## 방법 (검증 거버넌스)
- 클린 타이밍 + **lag1 스트레스**(동월 누출 유일 판별) 의무.
- **β-scan 정렬검증**(Track B/C): base 재구성 vs ret_orig 최고상관 offset **+2 = forward return**(cor 0.828) → Ret_1m forward-aligned, **누출 없음** 확인.
- 차분설계(재구성오차 상쇄): variant vs base를 동일 machinery로.
- paired NW-t(lag-3). 승격기준 = paired_t>~2 AND lag1 부호유지 AND SR>base 동시충족.

## 결과 — 13 변형 × 3 계열, 전부 negative/null

### Track A — 게이트 형태(연속 vs 하드빈), 평균노출 매칭 → **FALSIFIED**
| 후보 | SR_geo | Calmar | MDD | PORT_t | paired_t | lag1_t |
|---|---|---|---|---|---|---|
| BASE 하드빈 | 1.895 | 1.938 | 0.233 | 6.166 | — | — |
| A1 선형 R05z | 1.718 | 1.340 | 0.311 | 5.776 | −3.58 | −3.90 |
| A2 tailcut g2 | 1.733 | 1.540 | 0.273 | 5.565 | −2.25 | −2.29 |
| A4 tailcut g3 | 1.732 | 1.515 | 0.277 | 5.561 | −2.34 | −2.35 |
| A5 tailcut MSM-crisis-prob | 1.876 | 1.995 | **0.218** | 5.307 | −1.10 | −2.66 |
| A3 조건부 vol-target | — | — | — | — | (N/A: risk-off 7%뿐, 평균매칭 구조적 불가) | |

전 변형 paired_t 음 → **하드빈을 이기는 연속게이트 없음**. 하드빈의 국면-범주 구조(위기 집중 컷)가 우월. A5(시장 crisis-prob)만 MDD/Calmar 소폭 우위이나 realized alpha 희생(PORT_t 6.17→5.31)+lag1 취약 = 순개선 아님. → 로드맵 P3 "Continuous Jump Models" KR 비이전 실증.

### Track B — 국면조건부 sleeve 구성(선택레벨) → **NULL**
현행 score_eff=0.65·core+0.35·def(CONFIRMED). 국면조건부 가변 배합.
| 변형 | SR | MDD | paired_t | lag1_t |
|---|---|---|---|---|
| base 고정 | 0.958 | 0.456 | — | — |
| regime_blend(risk-on core/risk-off def) | 0.906 | 0.537 | −0.42 | +0.20 |
| reverse_blend | 0.855 | 0.411 | −0.94 | −1.42 |
| strong_blend(극단) | 0.970 | 0.407 | +0.22 | +0.52 |
| tilt_regime(λ 가변) | 0.947 | 0.456 | −0.80 | −0.63 |
| deconc_riskoff(risk-off EW) | 0.956 | 0.446 | −0.67 | −0.54 |

전 변형 |paired_t|<1 → 국면조건부 sleeve/틸트 회전 유의개선 없음.

### Track C — weight-stage per-name 틸트 → **NULL**
| 변형 | SR | MDD | paired_t | lag1_t |
|---|---|---|---|---|
| base | 0.958 | 0.456 | — | — |
| C1 저-tail-risk risk-off | 0.961 | 0.447 | −0.08 | −2.21 |
| C2 모멘텀 risk-on | 0.928 | 0.428 | −0.66 | −0.66 |
| C3 both | 0.928 | 0.419 | −0.70 | −1.49 |

전 변형 paired_t≤0. C1/C3 MDD 소폭↓이나 유의성 0/음(lag1 악화=미스타이밍 손해=신호없음).

## 종합 판정
**게이트 형태 정밀화도, 홀딩스-레벨 국면 구성도 M4×R05를 못 이긴다** — KR long-only envelope에서 실측 확증.
- 게이트: 하드빈 regime-cash 구조가 near-optimal, 연속화 비이전.
- 구성(B/C): §6 "직교≠수익, long-only β≈0.92 바닥" 확증 — 이름회전은 위기방어 불가(현금=R05×m4만 유효). 공짜점심 없음(MDD↓는 항상 alpha 희생으로 상쇄).

## 자기 적대검증(AX-008 Self-Adversarial, 2/3: Forge 실측 + Self-Adv)
① 재구성 cor 0.828(느슨) — 차분설계로 상쇄, 8 구성변형 uniform-null이 masked-effect 반증 ② 평균매칭 = 순수-shape 통제(비매칭 재튜닝은 DSR sweep·19위기월 과적합, 의도적 배제) ③ 선택레벨 종결 정당(오버레이 monotone scalar, base差≈0→book差≈0) ④ **미검증 잔여**: factor_db per-name 진짜 market-β 틸트(R05_Tail_Risk_Z 프록시 근사에 그침) — §6 prior 강하게 반대이나 기술적 미검증.

## 다음(EV 순)
1. **미검증 오버레이 잔여 = 진짜 market-β 틸트**(factor_db β) — 저EV(§6 prior), 필요시 확인용.
2. **오버레이 각도 종료 → 자원은 비-return 원천**(로드맵 W3 DART insider)으로 — SR-2.5 레버 중 잔여 프론티어([[project-dart-insider-exec-nonreturn-frontier]]는 deployment 감쇠벽 확정, insider 역사파싱만 잔존).

산출: `stage_artifacts/pg2_overlay_gate_composition_20260705/` (harness_trackA/B/C·results.csv·pinned_cache·run.log).
