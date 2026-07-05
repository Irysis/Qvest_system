# Self-Adversarial Challenge — WT-P20260706_001 (mega-cap 앵커 forge-authoritative)

Opus 4.8 자체 적대검증 (v8.2, finalize 직전). AX-008 3-source 중 1개. forge-authoritative 수치 기반.

## Q(i) — 앵커 성공이 mega-cap 레짐 최근런 우연인가? (full-period vs 2017+ 분리)

**측정 (forge-authoritative, NW lag-3 t):**
| series | full_t | pre2017_t (n=156) | post2017_t (n=111) |
|---|---|---|---|
| baseline (LT, no anchor) | 3.83 | 3.85 | 1.41 |
| a (K=2 anchor) | 4.53 | 3.39 | 3.05 |
| **anchor EDGE (a − baseline)** | **−1.69** | **−3.29** | **+0.75** |

**적대 판정 — 앵커는 alpha 레버가 아니라 분산-축소(벤치-트래킹) 레버.**
앵커 순수 기여(a − baseline)는 full_t −1.69, pre-2017 −3.29로 **평균 active return을 빼먹는다**. post-2017에서만 +0.75 (그나마 t<1, 비유의). 그런데도 앵커의 headline PORT_t(3.83→4.53)와 oos(0.366→0.894)가 오르는 이유는: 앵커가 삼성/하이닉스를 20%씩 고정해 cap-w 벤치와의 tracking-error(active 분모)를 줄이기 때문 — **ratio 게이트(PORT_t, oos_retention)를 분모 축소로 기계적으로 올린다.** 이것이 원발견의 "cap-weighted mega-cap 벤치 아티팩트"의 정확한 정체다: 앵커는 벤치 구성을 트래킹할 뿐 real edge를 더하지 않는다.
→ **앵커 개선은 최근 레짐 우연이 아니라, 더 근본적으로 alpha 개선이 아니다.** post-2017 우연 여부 이전에 전기간 앵커 기여가 음수.

## Q(ii) — 재구성이 production STR_1715과 실제 정합하나? (selection overlap)

**정합 부분**: fill weighting = production `linear_tilt_to_penalty_qd(λ1.5, φ3, ub0.20)` verbatim (`strategy_tilt_weights.R` source). score_eff = production alpha_scores_r05_panel(268m) 그대로. 유동성/25종 헌법 제약 준수(20종 fill + 2 anchor = 22 ≤ 25). anchor selection = size(t-1, last Size<D) PIT-clean (`compute_size_mom.R` 확인).
**정합 갭 (캐비앗)**: (1) production STR_1715은 자체 regime overlay(CRISIS 시 ub=0.10) + M08 restore를 포함하나 본 재구성은 base fill만. (2) **anchor 자체가 production book에 없는 신규 구성** — production은 earnings 기준 선택이라 삼성/하이닉스 저비중. 즉 이건 production 재현이 아니라 **production alpha 위에 얹은 신규 앵커 오버레이의 측정**이다 (정확히 WT 의도). (3) parity: Return.portfolio(권위) vs 가중합 **cor=1.0, max abs diff 2.3e-16** — 계약 등가 확정(자체합성 아님).

## Q(iii) — cap-share 비례가 벤치허깅으로 붕괴하나? (알파엣지 잔존 확인)

capshare corr_bm=0.873 vs a corr_bm=0.897 (오히려 capshare가 덜 허깅). capshare PORT_t=4.573, net_active_sr=0.986 — **알파엣지 형식적으로 잔존**. BUT Q(i)와 동일 논리: capshare도 앵커 EDGE는 벤치-트래킹 분모효과. capshare가 oos_retention을 0.65(band)로 낮춘 것은 top2 집중(0.325)이 낮아 트래킹이 덜 되기 때문 — **집중 완화 ⇄ oos 게이트 완화가 trade-off (같은 분모 메커니즘의 양면).** 즉 집중을 낮추면 oos가 깨지고, oos를 살리려면 집중을 올려야 하는 구조. 독립적 두 블로커가 아니라 한 메커니즘의 두 표현.

## Q(iv) — oos band 조건부-PASS 증거 3종이 독립인가?

band 대상은 b_capshare(0.65)/d_regime(0.59). 증거 3종: ① trailing 2017+ PORT_t>0 (capshare post17_t=2.46 ✓) ② placebo p<0.05 (random-fill p=0.000 ✓) ③ ΔSR>0 ∧ |cor|<0.30. **③이 FAIL**: active_cor(anchor vs base) = 0.836~0.934 ≫ 0.30 — 앵커북은 base 재구성과 거의 동일(직교 아님). 게다가 Q(i)로 ①②는 **앵커 고유가 아니라 base 재구성이 이미 가진 성질**(baseline placebo·post17도 유사) — band 증거의 독립성 결여. → **band 조건부-PASS 2/3 미충족** (③ 명백 실패, ①②는 앵커 귀속 불가).

## 종합 적대 판정
4개 렌즈 모두 앵커의 **자본급 승격을 반증**한다. 앵커는 (i) 전기간 active return을 빼는 분산-축소 레버 (ii) production alpha 위 신규 오버레이(재현 아님, 계약 parity는 clean) (iii) 집중↔oos가 한 메커니즘 (iv) band 증거 비독립 + active_cor≫0.30. **de-rate — screening-tier 고정.** 막은 게이트: calmar(0.571<0.64, 전 변형) + book-marginal(paired NW-t 음수, 앵커 EDGE 음수) + oos band 증거 비독립.
