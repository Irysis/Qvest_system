# Self-Adversarial Challenge — WT-D20260706_004 (KRW/USD-beta export-sensitivity alpha)

**Agent**: Alpha Research (Opus 4.8 native self-adversarial, v8.2 — Codex Round 대체)
**Finalize verdict**: **KILL (FALSIFIED)**. No survivors to hand to Risk/Optimizer.
**AX-008**: self-adversarial = 3-source triangulation 중 1 (Forge/Architect 미소환 — kill이므로 forge 불필요; canonical_screen_bt = contract-grade 실측이 substantive 근거).

## Verdict evidence (real-computation, metric_type=canonical_screen, NW lag-3)

| cut | benchmark | PORT_t | IR | net_SR | n_months |
|---|---|---|---|---|---|
| FULL | cap-w K200 | **-0.429** | -0.085 | -0.085 | 258 |
| POST2017 | cap-w K200 | **-2.371** | -0.619 | -0.619 | 114 |
| REGIME_WEAK (원약세) | cap-w K200 | **-0.940** | -0.240 | -0.240 | 130 |
| REGIME_STRONG (원강세) | cap-w K200 | +0.356 | 0.112 | 0.112 | 128 |
| FULL | EW | -0.642 | -0.132 | -0.132 | 258 |
| POST2017 | EW | -1.531 | -0.442 | -0.442 | 114 |
| INVERSE FULL (long low-FX-β) | cap-w | +0.278 | 0.058 | 0.058 | 258 |

- rank-IC full = 0.0058, t = 0.87, ICIR = 0.054 (모두 게이트 미달, 방향력 부재).
- graduation HARD 3종 (PORT_t≥2.95 / oos_retention≥0.7 / calmar≥0.64): 전부 미달. best PORT_t = +0.356 ≪ 2.95.

## Devil's advocate concerns (≥3 의무) + 분류

### C1 — mega-cap 반도체 재포착(벤치허깅)? [ACCEPT as diagnostic — RULED OUT]
가장 우려한 실패모드: FX-beta top-25가 그냥 삼성/하이닉스 mega-cap 반도체이고, cap-w 벤치서만 강하고 EW서 죽는 벤치허깅([[project-megacap-anchor-construction-discovery]] 교훈).
- **측정**: top-25 mega-cap(top-10 size) share = **3.2%**, median size-rank = 166위, median size percentile = **45.3%(중형주)**.
- **판정**: 2-factor FX-beta(mkt-orthogonalized)가 시장/size 성분을 제거 → 남는 것은 **중형주 고-FX-민감 종목**. mega-cap 재포착이 **아니다**. 따라서 "벤치허깅으로 인한 가짜 alpha"도 아니고 "mega-cap 앵커 milestone 후보"도 아니다. 오히려 cap-w/EW 벤치 양쪽에서 동시에 음(-0.429/-0.642) → 벤치 아티팩트 아닌 **진짜 신호 부재**. concern은 실측으로 해소(양방향 모두 kill 지지).

### C2 — FX-beta look-ahead (full-sample 회귀)? [ACCEPT prevention — CLEAN]
- **구현**: 종목별 rolling 120일(trailing) 2-factor OLS, window가 **month-end t에서 종료**. full-sample β 사용 안 함(C1 준수). `roll_fx_beta()` si=ei-win+1, ei=month-end index — 미래 관측 미포함.
- KRW/USD는 t 시점 관측가능(spot, C11 — FX는 contemporaneous, publication lag 없음). regime 라벨은 t까지 데이터로만 계산(krw_ma12 = trailing 12m). 신호@t → 보유(t→t+1) forward return. look-ahead 없음.
- 자기검증: 만약 look-ahead가 있었다면 IC/PORT_t가 **낙관적**으로 나왔을 것. 실측이 음수 → look-ahead가 결과를 구제하지 않음. concern 무효(구현 clean + 결과 방향이 우려와 반대).

### C3 — regime 라벨 look-ahead? [ACCEPT prevention — CLEAN]
- regime = KRW/USD(month-end t) vs trailing 12m MA(≤t). t-observable. regime@t가 다음달 선택을 조건화 → 미래 regime 미사용. WEAK=150/STRONG=158 균형(과적합 소지 낮음).

### C4 — rank-IC를 PORT_t로 오독? [REBUTTAL — 명시 분리 보고]
- rank-IC(t=0.87)와 portfolio-alpha t(NW lag-3)를 **별도 보고**. 판정 권위 = long-only top-25 실현 PORT_t(모두 음/미달). rank-IC 약함과 PORT_t 미달이 **일관** — 오독 여지 없음. (Cycle 2 교훈: rank-IC 강한데 PORT_t 약한 경우가 함정인데, 여기선 rank-IC조차 약해 함정 자체가 부재.)

### C5 — 원약세 regime 표본 부족 → 과적합? [ACCEPT — 오히려 반증 강화]
- REGIME_WEAK n=130개월(충분). 표본 부족 아님. 그리고 **가설의 핵심 regime(원약세)에서 PORT_t가 가장 나쁨(-0.940)** → 표본이 충분한데도 메커니즘이 반대로 작동. 과적합으로 가짜 통과한 게 아니라, 충분한 표본에서 clean FALSIFIED.

## Self-rationalization auto-detection (금지어 스캔)
"미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" — **미사용**. 결과는 실측 음수를 정직 보고. 합리화 없이 kill.

## Escalate trigger 점검
HIGH severity ≥5 / AX axiom hard FAIL ≥3 / PIT C1(lockbox·lookahead) 위반 — 해당 없음(구현 clean, 결과가 정직 kill). escalate 불요.

## 결론 (AX-000 정직보고)
KR 수출주도 논리는 경제적으로 그럴듯하나(export earnings translation), **종목별 rolling FX-beta를 return으로부터 유도한 신호는 배포 PORT_t로 전이하지 않는다**. 원약세 regime 조건부로도 개선 없이 오히려 악화. 이는 오늘 ~15건과 동일한 **return-derived signal → top-25 long-only IC→PORT_t 전이 벽**([[project-dart-insider-exec-nonreturn-frontier]])의 FX-macro 렌즈 버전 확인. 단, 제약(envelope)을 실패 원인으로 귀속하지 않음(AX-000 따름정리) — 신호 자체가 부재. **재시도 저EV: return-derived FX-beta 계열**. milestone 아님. 정직 kill.
