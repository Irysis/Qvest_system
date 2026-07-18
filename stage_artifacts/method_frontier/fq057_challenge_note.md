# FQ-057 Self-Adversarial Challenge Note (v8.2 의무 — finalize 직전)

- 라운드: Method-Frontier lane 1호 (cap-tier block Σ + nonlinear shrinkage)
- 작성: risk-research agent, 2026-07-18
- pin_tag: fq057_20260718_171024
- 성격: WT 아님 (독립 리서치 라운드) — AX-008 3-source triangulation 중 Self-Adversarial 1-source만 해당. Forge/Architect source는 WT-시점 소비 단계(`.get_cor_cov` 등재 라운드)에서 발동.

## Self-concerns (6건 — 의무 하한 3건 초과)

### C1. Tier 경계 임의성 (MID/SMALL cut=150 신규 선택) — **PARTIAL**
- 제기: MEGA≤30은 배포 컨벤션(R37/R39 TOP30_N) 재사용이나, MID/SMALL 경계 150은 본 라운드 신규 선택 — cherry-pick 위험.
- 보완 실측 (`fq057_tier_boundary_sensitivity.json`, cut ∈ {100,150,200}):
  - MEGA share 불변: cap-w basis 0.9982 / EW basis 0.0292 — 경계 무관.
  - MID/SMALL만 정의적으로 이동 (EW basis MID 0.233→0.369→0.515).
- 처리: 헤드라인(mega 지배 + dual-basis 괴리)은 경계-강건으로 유지. MID/SMALL 개별 수치는 "경계-조건부" 라벨을 verdict에 명시.

### C2. Block 합성 연산자의 구조적 non-PSD — **ACCEPT** (측정이 적발한 설계 결함)
- 제기: 독립 추정한 PSD 블록들을 하드 조립(교차블록 1-factor 치환)하는 연산은 전역 PSD를 보존하지 않는다. 실측: psd_viol_rate 100% (198/198 window), min_ev −0.196 규모. eigen-clip 수리 후 cond ~1e10, MVP gross leverage 5.9/9.9, MVP OOS vol 0.549/0.959 (NLS 0.142 대비 3.9~6.8배).
- 처리: ACCEPT — 이것이 본 라운드의 핵심 negative 판정 근거. 단 판정은 **config-scoped** (INV-7): "하드 블록-치환 합성 연산자" negative이지 "tier 구조를 Σ에 내장" 개념의 반증이 아님. 증거: block_nls가 cor_rmse 전 후보 최선(0.33768) — tier-사전은 상관구조 적합에 미세 기여. PSD-보장 내장 경로 2종을 next_probes로 확정.

### C3. MVP OOS vol 지표가 conditioning과 구조를 혼동 — **PARTIAL**
- 제기: lw_linear(hrp_core 재사용)가 p>n에서 ρ-cap=1 바인딩으로 μI 완전 퇴화(cond=1, MVP=EW, leverage 1.0) → cond/stability 랭크 1위는 퇴화 아티팩트. composite rank가 퇴화를 보상할 위험.
- 보완: 6지표 equal-rank composite에서 lw_linear는 cor_rmse 최하위(0.3761)로 상쇄되어 2위. 선택(lw_nls)은 MVP OOS vol 1위 + cond 유한(98) + PSD clean — 퇴화 아티팩트 제거 관점에서도 서열 불변. 해석 주석을 verdict에 명시(lw_linear의 cond=1은 우위가 아니라 붕괴).
- 부수 발견으로 격상: **incumbent `.get_cor_cov` linear LW는 대형 유니버스(p>n)에서 상관구조 전멸** — WT-시점(p≤25)은 비바인딩이라 무해하나, 대형 유니버스 소비 금지 경고를 verdict limitations에 등재.

### C4. Frobenius/cor 손실 타깃(fwd-12m 샘플 cov, n=12)의 자체 노이즈 — **PARTIAL**
- 제기: p~300, n=12 타깃은 노이즈 덩어리 — frob 차이(0.0062~0.0070)는 대부분 타깃 노이즈.
- 보완: 전 추정기 paired(동일 타깃·동일 window)라 서열 비교는 유효하나 절대 수준 해석 금지 — verdict에 약증거 라벨. run_03 warning 45건 전량 = `cov2cor(S_fwd)` 근영변동 종목 경고(비차등, 실측 확인).

### C5. NLS 자체 구현 미교차검증 — **PARTIAL**
- 제기: `nlshrink` 부재로 Ledoit-Wolf 2020 analytical_shrinkage.m을 직접 포팅 — 포팅 오류 위험.
- 보완 (sanity 실측, `fq057_sanity.json` ALL PASS): S1 소p 극한 rel-Frob vs sample 5.19%·trace ratio 1.000 / S2 identity 고유값 분산 0.166→0.0054·평균 0.973 / S3 p=300>n=60 full-rank PSD.
- 잔여: 공식 구현 numerical parity는 미실시 → `.get_cor_cov` 등재 전 필수 조건으로 명시 (follow-up).

### C6. signal_alive 진단의 basis 오독 위험 — **ACCEPT** (라벨로 봉인)
- 제기: "trailing 36m EW-of-tier vs cap-w bench t-stat"는 breadth-vs-concentration(레짐) 진단이지 전략 신호 생존이 아님. 전 tier t<0 (MEGA −1.67 / MID −1.51 / SMALL −2.18)은 2025-26 mega 집중 레짐 실측([[reference-kr-2025-megacap-semi-regime]])과 정합 — "신호 사망"으로 오독되면 안 됨.
- 처리: JSON에 `signal_alive_basis` 문자열로 기전·prior 인용 명시. judge/alpha 소비 시 이 basis 문자열 필독.

## 자기합리화 자동탐지
- "미미 / 관행적 / 보수적이면 OK / 이미 반영" 계열 표현: 본 라운드 산출물 내 사용 없음 확인.
- 성과(SR/IR/alpha) 기반 추정기 선택: 없음 — selection_objective = shrinkage_quality (R4 P3 HARD 준수).

## Q-Lead escalate 판정
- HIGH ≥5: 해당 없음 / AX axiom hard FAIL: 없음 / PIT hard violation: 없음.
- Σ PD violation: **최종 선택 추정기(lw_nls)는 PSD clean** (violation 0/198, Phase C cond 146.5 < 500). block 후보의 PD 위반은 "기각된 후보의 측정된 속성"(본 라운드의 발견물)이지 파이프라인 사고가 아님 → escalate 불요.
