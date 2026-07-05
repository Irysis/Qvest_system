# RAMP residual-α sleeve PORT_t 검증 — 종결 판정

- generated_at: 2026-07-05 | source_version: ramp_v1.0_residual_portt | as_of_date: 2026-07-05
- security_id: strategy_id (module NAV level)
- 목적: 헌법 measurement-graduation §6 ② SR-2.5 레버("잔차-직교 sleeve 스태킹 — 미해결: RAMP 18후보 PORT_t 검증 필요") 종결
- metric_type: canonical_screen (stored-NAV monthly net-active, build_benchmark_compare 경유) — admission-binding 아님

## VERDICT: ② 잔차-직교 sleeve 레버 = CLOSED (오염된 variance-dredge, clean deployment-급 자료 0건)

## 근거 (실측)
- 후보 = `outputs/ramp/residual_alpha_candidates.parquet` 479행 중 dedup-unique ∧ unexplained_var_frac>0.5 = **18** (+uvf>0.4 확장 시 21).
- 전원 `origin_mode=alpha_search`, grade **F/C** (batch_434 13 + catalog 5). PC1~PC5 회귀 잔차분산(=설명 안 되는 특이분산)만으로 선정 — 알파 기준 선정 아님.
- 반환행렬: `outputs/ramp/pool_return_matrix.parquet` (23MB) = `02_Infrastructure/ramp/debug/_cache_pool.rds` (5303일 × 479전략, 2005-01~2026-06). 18후보 전원 ~5266일 실측 커버.
- 각 후보 stored 일별 net → PerformanceAnalytics `apply.monthly(Return.cumulative)` 월간 → KOSPI200 대비 net-active PORT_t (`build_benchmark_compare` NW lag-3, 자체합성 없음).

### 결과 (top by PORT_t)
| strategy_id | n_m | net-active PORT_t | active-cor(book) | uvf | grade | src |
|---|---|---|---|---|---|---|
| STR_AS_20260612_124658_77279 (Amihud illiq) | 257 | **1.869** | 0.049 | 0.50 | F | catalog |
| ML_momentum_ensemble | 173 | 0.262 | 0.038 | 0.52 | ung | catalog |
| STR_AS_20260612_230800_193887 | 257 | -1.333 | 0.131 | 0.81 | C | b434 |
| STR_AS_20260612_211102_178289 | 257 | -1.728 | 0.116 | 0.80 | C | b434 |
| ... (13/18 NEGATIVE PORT_t) ... | | | | | | |
| STR_AS_20260612_134025_400588 | 257 | -3.322 | 0.056 | 0.62 | F | b434 |

- **최고 PORT_t = 1.869** (HARD 2.95 미달). **13/18이 음(net-active 손실)**. PORT_t≥2.95 ∧ orthogonal ∧ ΔIR≥0.05 = **0건**. 확장 21후보서도 max 1.869, 양수 2/21.
- 따라서 §4 book-marginal ΔIR 계산 대상 자체가 없음 (PORT_t≥2.95 통과 후보 0 → 게이트 진입 불가).

## 오염 가드 (task step 3) — 최상위 후보만 검증 필요, 나머지는 임계 하 자동 CLOSED
- 유일 PORT_t>1.5 후보 = STR_AS_20260612_124658_77279 (catalog, batch_434 아님 → sim_result.rds 정본).
- 그 **frozen authoritative_essence**(alpha-search 자체 측정): port_t_nw 2.065 · **oos_retention 0.187** · calmar 0.323 · mdd 0.714 · grade F.
- 독립 재측정(본 검증) 1.869 ≈ alpha-search 자체 2.065 → stored NAV 신뢰 (오염 아님). 둘 다 2.95 미달 + oos_retention 0.187은 무조건 FAIL(§3 <0.5). **UNVERIFIABLE 불필요 — 두 측정 일치·둘 다 FAIL.**

## Self-Adversarial Challenge (AX-008)
1. **"survivor가 batch_434 아티팩트일 수 있나?"** — survivor 0건이므로 무효. 최고후보는 catalog(비-b434) 정본이며 자체 essence와 일치. batch_434 stored NAV 타당성 검증(ann_vol 7.5~13.4% 정상 백테 형상, corrupted-to-junk 아님) → 음 PORT_t는 실제 underperformance이지 데이터 손상 아님.
2. **"직교성이 gross vs active인가?(§6)"** — gross-cor(mean 0.037)·active-cor(mean 0.110) 둘 다 LOW → 직교성은 진짜(gross 아티팩트 아님). 단 **직교 ≠ 수익**: 직교분산이 곧 알파 노이즈이며 net-active drift 음. §6 원칙 재확증.
3. **"임계 임의성?"** — 2.95는 문헌-레벨 다중검정 문턱. 최고 1.869로 어떤 합리적 임계로도 미달. oos_retention 0.187로 과적합 게이트도 독립 FAIL.

## 결론 (decision-grade)
② 잔차-직교 sleeve 레버는 **variance-dredge 확정 — clean deployment-급 생존자 0**. 고-잔차분산 선정은 알파가 아니라 특이 노이즈를 뽑았고, 그 노이즈는 book에 직교하나 net-active로 음/약. §6 "직교 ≠ 수익"이 sleeve 후보 레벨에서도 확증. 헌법 §6 ② 미해결항 = **CLOSED**.
- 함의: SR-2.5 레버 중 ②(새 잔차 sleeve 사냥)는 이 후보풀에선 소진. 잔여 레버 = ① overlay 정교화(주역) · ③ DPL · ④ uncertainty. 신규 잔차 sleeve는 "고분산 선정"이 아니라 "PORT_t 사전선정 ∧ 직교" 동시조건으로만 재시도해야 함.

## 산출 파일
- `stage_artifacts/ramp_residual_alpha_portt/firstpass_stored_nav.{rds,csv}` — 18후보 PORT_t/IR/net_sr/active-cor
- `stage_artifacts/ramp_residual_alpha_portt/broadened_pool_portt.csv` — 21후보 확장
- 본 파일 VERDICT.md
