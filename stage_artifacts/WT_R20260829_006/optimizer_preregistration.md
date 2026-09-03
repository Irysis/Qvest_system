# WT-R20260829_006 — Optimizer 사전등록 (선택축 · 방법 목록)

**작성 시각**: 2026-08-29, **어떤 방법도 실행하기 전**.
이 문서는 결과를 본 뒤 수정하지 않는다. 수정이 필요하면 수정 사실과 사유를 아래 §6 에 append 한다.

---

## 1. 선택축 (사전 선언 — 단일)

`selection_objective = "net_ir"`

- **정의**: 워크포워드 월별 순수익(net of 15bps delta 비용) 대비 KOSPI200 total return 벤치의
  active 수익 시계열에 대해 **계약 함수** `build_benchmark_compare()` 가 산출하는
  `Information_Ratio` (연율화). 손계산 금지 — 계약 반환값만 인용.
- **basis**: cap-weighted KOSPI200 TR (헌법 권위 basis). EW-유니버스 basis 는 진단 병기만.
- **표본**: 상류 alpha 와 동일한 248개월 전 구간. 부분기간 절단으로 선택하지 않는다.

## 2. 사전 선언 tie-break 사다리 (순서 고정)

net_IR 차이가 **0.02 미만**이면 동률로 간주하고 아래 순서로 내려간다.

1. `turnover_annual` 작은 쪽 (구현 규율 — 비용·용량)
2. `PORT_t (NW lag-3)` 큰 쪽
3. **더 단순한 방법** (EW ≺ RP ≺ HRP ≺ CVaR ≺ Band) — DeMiguel-Garlappi-Uppal (2009) 1/N 우위
   실측 사전확률. 동률에서는 단순성이 이긴다.

## 3. 실격 게이트 (선택 전 적용 — 결과와 무관)

| 게이트 | 값 | 처리 |
|---|---|---|
| long-only | w ≥ 0 전건 | 위반 = 즉시 실격 |
| 종목수 | 리밸일별 n ≤ 25 | 위반 = 즉시 실격 |
| Σw = 1 | \|Σw − 1\| ≤ 1e-9 | 위반 = 즉시 실격 |
| 유동성 | adv20(t-1) ≥ 2e8 KRW | 선택 단계에서 사전 필터 |
| turnover | ≤ 11.0 /yr (도훈 mandate 2026-05-29) | **초과 시 실격 — 단, 전 방법이 초과하면 실격 대신 `infeasibility_report` 발행 후 최선안 선택**(조용한 완화 금지) |
| schedule density | unique_dates / alpha sig_dates ≥ 0.95 | 미달 = 재작성 |

★상류 alpha 자기신고 회전율이 이미 11.98/yr 이다 — 전-방법 초과가 사전에 예상된다.
그 경우의 처리를 **결과를 보기 전에** 위와 같이 고정한다.

## 4. 방법 목록 (상한 5 — 이 목록 밖은 시도하지 않는다)

단순 → 복잡 순서. **M1~M4 는 종목집합을 alpha 사양(top-25 by score)으로 고정하고 사이징만 바꾼다**
(사이징 효과의 순수 대조). **M5 만 사이징을 EW 로 고정하고 종목집합을 바꾼다**(회전 레버의 순수 대조).

| # | 이름 | 사이징 | 종목집합 | 입력 |
|---|---|---|---|---|
| M1 | `EW` | 1/25 | top-25 by score | — (incumbent = 상류 canonical basis) |
| M2 | `RP_invvol` | 1/σ_i 정규화 | top-25 by score | σ_i = sqrt(diag Σ_d) — risk 모델 |
| M3 | `HRP` | Lopez de Prado (2016) 재귀이분 | top-25 by score | Σ_d 25×25 — risk 모델 |
| M4 | `CVaR95_LP` | Rockafellar-Uryasev (2000) min-CVaR LP | top-25 by score | 확장창 실현 시나리오 (t < d) |
| M5 | `EW_band` | 1/25 | 밴드 버퍼 (보유분은 rank ≤ B 까지 유지) | score rank |

- **M5 밴드폭 B 는 사전에 40 으로 고정한다** (= 25 × 1.6, 표준 buffer 관행).
  B 를 sweep 해서 최적값을 고르지 않는다 — sweep 은 selection operator 가 되어 DSR 을 오염시킨다.
- **하지 않는 것**: confidence-aware MVO / Black-Litterman / ERC / MaxDiv / 앙상블.
  상한 5 를 지키기 위한 배제이며, 배제 사유를 `method_shopping_log.not_attempted` 에 기록한다.

## 5. Σ_d 조달 규약 (risk 재정의 금지의 구체화)

- risk 가 넘긴 **모델 형식과 추정기를 그대로** 각 결정시점 d 에 적용한다:
  `Σ_d = B_d Ω_d B_d' + D_d`, `Ω_d = lw_nls(F[t < d])`, `D_d = EWMA(hl=24m) resid²[t < d]`, winsor 5/95.
- **새 추정기를 고르지 않는다. 정칙화로 조건수를 낮추지 않는다**(risk 규약 2).
- 입력 F / resid / B 는 risk agent 의 `r1_reg.rds` 산출물을 그대로 읽는다 — 재추정 아님.
- as_of Σ (`covariance.parquet`) 는 **as_of target_weights 와 위험지표 보고**에만 쓴다.
  248개월 전 구간에 as_of Σ 를 적용하는 것은 C1 위반이므로 하지 않는다.
- 꼬리 지표는 risk 규약 3 을 따라 **t(5) / GPD** 값을 쓴다. 정규-Σ CVaR 를 그대로 인용하지 않는다.

## 6. 사후 수정 기록

(없음 — 결과 확인 후에도 §1~§5 는 수정되지 않았다. 2026-08-29 최종 확인.)
