# Factor Rotation Cycle 3 — batch_434 산출물 소비 결과

- **일자**: 2026-06-13
- **모드**: factor-rotation (Lane3 meta-layer, 모듈 소비)
- **입력**: batch_434 (alpha-search 430 채점 → module_catalog fr_eligible 180 → RCMA admitted 16)
- **산출**: FR_002 (dedup 클린런) + book-marginal ΔIR 진단
- **거버넌스**: governor 정지 — book_state 미기록. WT-id 미사용.

## 0. 배치 완주 + 위생점검
- batch_434 item 409/409 완주(06-13 10:01). registry 4종 `.cache/fr_cycle3_snapshot/` 고정.
- **codegen 오염 = 포트폴리오-레벨 실증**: 중복 의심쌍 NAV diff=0 (서로 다른 스펙이 폴백 콤보로 동일 포트 수렴). admitted 16 내 정확중복(|cor|>0.999) 1쌍 = `STR_AS_..123546_52003 == STR_AS_..132740_321992` → 후자 dedup.

## 1. 직교성 진단 (GO/NO-GO)
- admitted 16 **상호 상관 0.65~0.80** (모듈 vs 자기 KOSPI 베타 0.60~0.75로 total-return basis 확정). **|cor|<0.5 페어 0개**. → regime_study "0.70-상관 천장" 결론이 새 풀 180건에서도 재현.
- **로테이션 직교성 = NO-GO** (직교 모듈 부재).

## 2. FR_002 클린런 (authoritative, dedup)
| 지표 | 값 | HARD 게이트 | 판정 |
|---|---|---|---|
| net Sharpe | 0.847 | (SR 2.5 목표) | 미달 gap 1.65 |
| PORT_t (NW3) | 0.750 | ≥ 2.95 | **FAIL** |
| OOS_retention | −0.822 | ≥ 0.7 | **FAIL** (음수) |
| DSR | 0.04 | ≥ 0.5 | **FAIL** |
| Calmar | 0.37 | ≥ 0.64 | **FAIL** |
| EW baseline SR | 0.699 | edge>0 | 근소 통과(+0.148) |
| n_modules | 123 | — | walk-forward 누적 churn |

- n_modules=123(=registry FR_001 124 − dedup 1). 08:57 자동 FR_001_result.json의 n_modules=12는 배치 적재 도중 stale 산출. walk-forward RCMA가 18년간 123 모듈 churn하는 광범위 바스켓 → OOS 악화.
- **로테이션 FR = grade C, HARD 4종 전부 실패. dedup도 못 살림.**

## 3. book-marginal ΔIR (유망 각도 검증 → 기각)
- **자기정정**: Phase 1 "책 대비 cor 0.08(직교)"은 total-return basis 아티팩트. 책 총수익이 cash-timing overlay 지배라 낮게 나옴. **active(알파 vs 알파) basis = 올바른 book-marginal 기준 = cor 0.42(FR_002)·0.49(EW바스켓)** — 중간 상관, 직교 아님.

| sleeve 후보 | active cor | sleeve IR | best ΔIR | threshold +0.05 |
|---|---|---|---|---|
| FR_002 rotation ensemble | 0.422 | 0.325 | +0.000 (w=0) | **FAIL** |
| EW admitted basket (15) | 0.492 | 0.460 | +0.000 (w=0.10) | **FAIL** |

- book active IR(window) ~0.89~0.92. sleeve들의 standalone IR(0.33~0.46)이 책보다 낮고 active cor 0.42~0.49라, 다각화 이득이 낮은 품질을 상쇄 못 함 → 추가 시 book IR 개선 0. **book-marginal sleeve = 기각.**

## 4. 종합 판정 (이중 NO-GO)
batch_434의 430 전략·180 fr_eligible 모듈은 **로테이션 FR(grade C, 게이트 전패)도, book-marginal 다각화 sleeve(ΔIR 0)도** 만들지 못함. 새 풀은 동일 상관 클라우드이며, active-alpha로도 책과 0.42~0.49로 중간 상관 + 더 낮은 품질.

## 5. 함의 (실증, AX-000 정직보고)
- SR 2.5 천장은 **단일팩터 박스 안에서 모듈을 더 찍어내도 안 열림** — 입력 직교성이 결정([[project-capability-assessment-2026-06-10]] / regime_study 재확인).
- 살아있는 레버: ① overlay(β/regime timing — 주역, O3 등) ② DPL(직접 SR 최적화) ③ **진짜 직교 sleeve 생산**(일간 수급 도메인 / 분포예측 exposure — measurement-graduation §6).
- **INV-7 재도전 트리거**: 진짜 CRISIS specialist 또는 직교 sleeve 등재 시 FR Cycle 재실행 정당.

## 산출물
- `04_Research/factor_rotation/output/FR_002_result.json` + `FR_002_bt_result.rds`
- `04_Research/factor_rotation/prereg_fr002.json`
- `.cache/fr_cycle3_snapshot/` (registry 스냅샷 + 상관/dedup/book-marginal 스크립트·결과)
- `06_Registry/factor_rotation_registry.json` (FR_002 grade C 등재, n=2)
