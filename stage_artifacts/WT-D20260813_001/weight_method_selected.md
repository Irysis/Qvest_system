# Weight Method Selected — WT-D20260813_001 (q90 pinball)

**Selected**: `EW_top25_semicap50` (1/N over top-25 by q90 score + 반도체 sector cap 0.50)
**selection_objective**: `net_ir` (turnover-adjusted; raw Sharpe max 금지)
**metric_type**: `canonical_screen_diag` / **tier**: `screen_diagnostic`
**production_grade**: FALSE (optimizer walk-forward simulation — forge 재측정 필요)

## 결정 요약

alpha `research_verdict = NOT_SUPPORTED` (paired NW3 t=+0.828), rank-IC = -0.028(음수), decile-mono +0.964
→ 신호 약함 + 순위력↔소비 불일치. 이 상황에서 **비중 결정의 정답은 EW**이고, 그 결론은 5-method 비교로 방어됨.

## Walk-forward method comparison (199 sig_dates, 15bps delta-cost, top-25 selection 고정)

| method | net_sr | port_t_nw3 | active_ir | ann_turnover | mdd | 판정 |
|---|---|---|---|---|---|---|
| **EW (+semicap50)** | **0.6046** | **0.9267** | **0.2569** | **10.62** | 0.6701 | **SELECTED** |
| EW (no cap) | 0.6042 | 0.9256 | 0.2566 | 10.61 | 0.6701 | baseline |
| ScoreTilt (full) | 0.6505 | 1.5820 | 0.4028 | 12.56 | 0.7302 | DISQUALIFIED (turnover>11.0) |
| InvVol (full) | 0.6513 | 1.1517 | 0.3293 | 12.27 | 0.7052 | DISQUALIFIED (turnover>11.0) |
| Blend θ=0.19 | 0.6248 | 1.0933 | 0.2974 | 10.98 | 0.6779 | feasible·개선 미미·비robust |

Snapshot-only (current 25 names, Σ walk-forward 미제공이라 스케줄 미적용):

| method | vol_ann | eff_n | semi_wt | note |
|---|---|---|---|---|
| MVO (λ grid) | 0.5735 | 15 | 0.667 | 섹터집중·vol 악화 |
| HRP (from Σ) | 0.4644 | 18.1 | 0.564 | Σ walk-forward 미제공 → snapshot only |
| ERC | 0.4748 | 22.3 | 0.523 | Σ walk-forward 미제공 → snapshot only |

## 선택 근거 (net_ir 기준)

1. **DeMiguel-Garlappi-Uppal 2009 (1/N OOS 우위)**: 약한/불확실 μ̂(rank-IC -0.028, NOT_SUPPORTED)에서 표본 최적화는 estimation error 를 증폭. MVO/AlphaTilt 는 섹터집중(반도체 56→67%)·vol(52.6→70%) 악화 실측 — Cycle 2 교훈 재현.
2. **score-tilt 개선의 비robust 성**: full-period net SR +0.046 이지만 IS/OOS split 에서 **부호반전(IS -0.16 / OOS +0.18)**. 안정 구조 아님 → 채택 시 method shopping.
3. **turnover cap 방화벽**: full-strength tilt/InvVol net SR 은 높으나(0.65) turnover 12.3~12.6 > 11.0(도훈 mandate) → silent relaxation 금지·DISQUALIFY.
4. **selection = edge, sizing 아님**: Grinold breadth — 알파의 edge 는 top-25 name selection 이지 비중이 아님. EW 가 그 selection 을 순수 반영.

## Sector cap (반도체 ≤ 0.50) 근거

- 현 book 반도체 16/25 (natural EW 64%) → 50% 로 완화 (RF-R1 HIGH 대응).
- historical: mean 7.2%·median 4%·cap binding **2/199 dates** = costless safeguard (net SR delta +0.0003·MDD 불변).
- **MDD 67% 는 sector 아닌 market beta(0.78)·구조 drawdown(2018/2022) 구동** — cap 이 MDD 를 못 낮춤 = MDD 원인이 sector 가 아님을 실증(cap 무용 아님).

## Hard constraints 확인

- max_names = 25 ✓ / Σw = 1.000000 ✓ / weight ∈ [0.0357, 0.0455] ⊂ [0, 0.20] ✓
- liquidity: 25/25 종목 20d avg TV ≥ 2e8 KRW (RAWDATA Close×Vol, PIT ≤ sig_date). 미달 0 ✓
- ann_turnover 10.62 ≤ 11.0 ✓
- schedule density: 199/199 unique dates = **1.0** ≥ 0.95 ✓

## 자본 자격 (정직 라벨)

walkforward net SR 0.605·PORT_t 0.927·MDD 67%·Calmar 0.230 → **graduation HARD 3종(PORT_t 2.95·oos 0.7·calmar 0.64) 전부 미충족**. weights 는 forge 백테스트/judge 심사용 진단이지 편입 후보 아님. upstream `research_verdict = NOT_SUPPORTED`.

## Method-shopping posterior (v1.3)

`posterior_default: true` — 약한 알파·two-stage·multi-sleeve 미성립 → sweep 4-trigger 미발화. full 방법론 sweep 미실시(알려진 메뉴 반복 재비교 회피). HRP/위험기반 배분 부활 조건 = multi-sleeve book 성립 시(현 미성립). uncertainty sizing = 전이 벽 이동 신호 시(미발화·measurement-graduation §5/§6 settled-negative 인지).
