# R27 (FQ-040) Verdict — value 제3-축 통합 (slot-carve + z-blend 형태비교)

**판정: BOOK-MARGINAL SCREENING PASS (verified, PIT-robust) — R26 value 부정판정을 측정 정정으로 REVERSE**
book_state 무변경. screening 실측 PASS → QEPM 6-agent dossier 승격 재료(forge-authoritative 확정 + 도훈 수동).

## 핵심 결과 (authoritative = frozen cap-w 축, ym-정렬 value 병합)
- **best = Z6 (z-blend V14_EBIT_EV+V07_EV_EBITDA, w=0.30)**: paired NW-t **3.807** · ΔIR window-matched **+0.481** · variant PORT_t **7.60**(vs base 5.32) · net-IR 1.755(vs base 1.275) · turnover 13.0/yr(+0.5).
- **게이트(paired≥2.0 AND dIR≥0.05) 통과 arm = 7/10** (z-blend 5 + slot-carve 2). 단일 lucky config 아닌 grid 전반 pervasive.
- **holdout(2024-07~2026-03, 21m)**: Z6 IS paired 3.171 → **HO 4.300**(강화, 붕괴 아님) · dIR_ho +1.186. (단 HO는 2024-26 KR value 반등 국면 편승 有 — persistent 근거는 IS 3.17 + post2017 marginal 4.08.)

## ★ R26 부정판정의 원인 = 측정 배관 결함 (bug 재현으로 입증)
- R26(z-blend/ADD 축)은 value z를 **exact-Date 병합** → SCdt(거래일 월말, 예 2005-04-29) vs pure_factor_scores(달력 월말 2005-04-30) 불일치로 **255개월 중 92개월 value 완전 누락**(exact-match 163/255). value가 36% 월 muted → paired 저평가.
- **재현**: exact-Date V14 w0.30 = paired **1.868** (R26 보고 1.87 정확 재현) vs **ym-정렬** V14 w0.30 = paired **2.675**. ym-정렬(255/255)은 R26 Extension B recon(ymL)이 이미 쓴 확립 규약이자 PIT-safe(달력 월말 label은 동일 last-trading-day 데이터 참조).

## PIT-robustness (판정이 병합 해석에 불변)
- **lag-stress**: concurrent 3.807 → **lag1 2.982** → lag2 3.012. value를 1개월 과거로 shift(명백 PIT-safe)해도 게이트 통과 → 동월 look-ahead 부재.
- **placebo**(월내 value z 셔플 10seed): real 3.807 vs placebo mean −1.956(max −0.603), **p=0.000**.

## 형태 비교 (z-blend vs slot-carve) — Q-Lead 가설 FALSIFIED
| 형태 | 최우수 | paired | dIR | 결론 |
|---|---|---|---|---|
| z-blend | Z6 V14+V07 w0.30 | 3.807 | +0.481 | 우위 |
| slot-carve | S4 V14+V07 N_val=8 | 2.585 | +0.323 | 통과하나 열위 |

- "sleeve 슬롯 분리가 value 전이를 개선"(가설)은 **오히려 반대** — slot-carve는 고확신 Core/Defense 종목을 강제 교체(N_val=8 added value fwd이 bumped score_eff 대비 −0.006~−0.017/yr)해 연속 tilt(z-blend)보다 열위. 단 **두 형태 모두 게이트 통과**(value 신호 자체가 실재).
- value 정의: **V14+V07 blend > 단독**(V14~V07 cor 0.20 준독립, blend가 diversification). V02_EP는 V14와 cor 0.66(별도 def 미채택, standalone 실패 prior).

## honest prior 정합
- **KR value 전수감쇠(24/24 standalone post-2015)**: 정합 — 본건은 standalone 아닌 **book-marginal orthogonal tilt**(book=Core consensus+Defense quality/mom, 순수 value 부재). post2017 marginal t **4.08** → book-marginal 기여 미감쇠.
- **06-24 직교327 t>2=0 · 07-10 프로브 fleet 0**: 이들은 exact-Date/다른 축. R26 frontier P2가 옳게 'value=미결 노출' 표시 → R27이 배관 정정으로 해소. AX-000: R26 negative는 '벽'이 아니라 측정 결함이었음.

## 방법론 무결성
cap-w authoritative + EW/cap-tier dual-basis(EW-uni PORT_t 8.48·post2017 5.61·oos_approx 1.01) · ΔIR window-matched(w=0 base) · paired∧ΔIR AND-게이트 · IS-only 선택 + holdout 1회 · bug 재현 + lag-stress + placebo 3중 검증 · pin R26_FQ039_20260714(재검증).

## next_probe
1. **P1(즉시)**: Z6을 QEPM 6-agent dossier 승격 → forge build_bt_result authoritative + HARD 3종(PORT_t 2.95·oos_retention 0.7·calmar 0.64) 판정(screening≠graduation).
2. **P2**: value weight w sweep(0.20~0.40) + regime-conditional theta(FQ-040 원 next_action) — IS-only, DSR 회계.
3. **P3(배관 시급)**: R26 ADD/replace 축 exact-Date value 병합 재측정 + deployzone/pure_factor_scores 소비 전반 ym-정렬 표준화(트랩 재발방지).
