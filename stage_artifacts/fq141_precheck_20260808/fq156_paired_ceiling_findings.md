# FQ-156 — cap-tilt 계열의 증분 t 천장 1.307, shrink 다이얼은 증분에 대해 **항등** (2026-08-08)

**성격**: read-only 아티팩트 재판독 + 대수 논증. 신규 백테 미실행.
**대상**: `04_Research/method_frontier/wt006_exog_forecast/` R4 cap-tilt 스윕 10변형
**착수 동기**: NP-157b(cap-tilt 우위 ↔ `d` 시대 동조) 착수 중 발견 — **NP-157b 자체는 미완**(§5).

---

## 1. 전 변형 실측 (R4_bench_aware_weight_results.csv)

| variant | port_t | **paired_vs_mom_t** | oos_ret | calmar | max_w | deploy_ok |
|---|---|---|---|---|---|---|
| ew_parity (baseline) | 1.277 | — | | | 0.040 | TRUE |
| size_prop | 2.474 | **1.307** | 0.611 | 0.738 | 0.700 | FALSE |
| shrink_l25 | 2.311 | **1.307** | 0.418 | 0.676 | 0.535 | FALSE |
| shrink_l50 | 2.028 | **1.307** | 0.144 | 0.612 | 0.370 | FALSE |
| shrink_l75 | 1.662 | **1.307** | −0.025 | 0.546 | 0.205 | FALSE |
| tilt_k0p5_cap | 2.021 | **1.258** | 0.391 | 0.566 | 0.200 | **TRUE** |
| size_prop_cap | 2.100 | 1.224 | 0.374 | 0.576 | 0.200 | **TRUE** |
| tilt_k1_cap | 1.883 | 1.185 | 0.441 | 0.508 | 0.200 | **TRUE** |
| shrink_l50_cap | 1.773 | 1.177 | 0.055 | 0.548 | 0.200 | **TRUE** |
| tilt_k2 | 1.440 | 0.844 | 0.710 | 0.333 | 0.992 | FALSE |

**paired 최댓값 = 1.307 (전 변형) · 배포가능 최댓값 = 1.258** — 저장소 문턱 2.0 에 **어느 것도 미달**.

## 2. shrink 다이얼은 증분에 대해 항등 — 대수적 이유

`run_R4_bench_aware_weight.R:52`
```r
mk_shrink <- function(D, lam){ D[, .(Ticker, w = lam*(1/.N) + (1-lam)*(size/sum(size))), by=Date] }
```
= **같은 25종목(SEL) 위** EW 와 cap-비례의 볼록결합. 그리고 baseline `ew_parity` 가 바로 그 EW(max_w 0.040 = 1/25).

가중에 대해 포트 수익이 선형이므로
```
a_λ − a_mom = (1−λ)·(a_capprop − a_mom)      ← 양의 스칼라 배
```
t = mean/se 는 **양의 스칼라에 불변** ⇒ λ ∈ {0, .25, .50, .75} 에서 paired t 가 **소수 3자리까지 동일(1.307)**.
실측이 이 예측과 정확히 일치한다. **버그가 아니라 항등의 지문**이다.
(비용 15bps 는 |Δw| 기반이라 엄밀히는 비선형이나, 소수 3자리 일치로 보아 차이 계열에 미치는 영향은 무시 가능 수준.)

**캡(cap)만 비선형**이라 capped 변형들이 값이 갈리고(1.177~1.258), 전부 uncapped 천장 1.307 **아래**다.

## 3. ★ 선택 기준 결함 — 다이얼에만 반응하는 양으로 골랐다

`run_R4_bench_aware_weight.R:105`
```r
ba <- res_deploy[which.max(port_t)]
```
**standalone `port_t` 로 최선을 선택**한다. 그런데 §2 가 보이듯 `port_t` 는 λ 다이얼에 크게 반응하고
(2.474 → 1.662) 증분과 무관하게 움직인다. paired 기준으로 보면 배포가능 최선은
`size_prop_cap`(1.224)이 **아니라 `tilt_k0p5_cap`(1.258)** 이다.

계통 = FQ-141/NP-A 와 동형 — **헤드라인 수치가, 개선 여부에 대해 정보가 없는 다이얼에 반응**한다.
(NP-A: 벤치를 바꾸면 2.86 / 여기: 가중 다이얼을 돌리면 2.474. 둘 다 증분은 그대로.)

## 4. FQ-156 판정

원안("R4 의 1.277→2.100 을 다른 composite 에서 재현")은 **무정보 라운드**다:
- 재현 대상인 standalone lift 는 λ 다이얼 산물이고,
- 진짜 증분은 **전 변형 천장 1.307 · 배포가능 1.258** 로 문턱 2.0 에 못 미치며,
- 2.100 이어도 `oos_ret` 0.374 · `calmar` 0.576 으로 **HARD 2종이 PORT_t 와 독립으로 FAIL**.

⇒ cap-tilt lane 은 **자본 자격 후보가 아니라 벽-높이 측정치**로만 성립한다.

## 5. NP-157b 는 미완 (정직 표기)

착수 목표였던 "cap-tilt 우위 ↔ `d` 의 시대 동조"는 **측정하지 못했다**:
- R4 산출물에 **시대 분할이 저장돼 있지 않다**(`R4_bench_aware_weight_results.csv` 컬럼에 era/period 없음,
  `R4_bench_aware_weight_summary.json` 에도 부재). synthesis 의 `pre-2020 t=1.95 vs 2020+ t=0.99` 는
  **서술로만 존재**하고 뒷받침 수치가 아티팩트에 없다.
- `weights_R4_best_bench_aware.parquet` 은 **best 변형 1개만** 저장(`run_..._weight.R:161`)이고,
  momentum baseline active 계열(`.a_mom`)은 저장돼 있지 않아 시대 분할 재산출에 R4 파이프라인 재실행이 필요하다.

## next_probe

- **NP-156a** — 선택 기준 수리: cap-tilt 류 스윕의 최선 선택을 `which.max(port_t)` → **paired 기준**으로.
  §3 이 보인 대로 현행은 다이얼을 고르고 있다. 같은 패턴이 다른 스윕 스크립트에도 있는지 전수(`which.max(port_t)` grep).
- **NP-156b** — 증분 천장의 일반성: 1.307 이 momentum 재료 고유인지, WT-007 composite 등 다른 재료에서도
  비슷한 천장인지. **standalone 아닌 paired 로만 채점**. 천장이 재료 무관이면 비중-측 사이즈 레버 자체가
  config-scoped 로 정리된다.
- **NP-157b (이월)** — R4 파이프라인 재실행으로 시대 분할 산출 후 `d` 와 동조 대조.
  ★현 시점 예측은 **반증 우세**(R4 서술이 pre-2020 우위 *더* 큼 = 벤치 허깅 가설과 반대 방향).

## 부활 조건 (INV-7)

paired 기준으로 2.0 에 닿는 (재료, 가중) 조합이 하나라도 나오면 cap-tilt lane 재개.
그때도 `oos_ret` 0.7 · `calmar` 0.64 는 별도 관문이다.
