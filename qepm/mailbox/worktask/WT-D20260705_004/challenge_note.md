# Self-Adversarial Challenge — WT-D20260705_004 (Alpha Research)

**Agent**: alpha-research (QEPM Opus 4.8 self-adversarial, v8.2 — AX-008 3-source 중 1개)
**Date**: 2026-07-05
**Finalize 직전 자체 적대검증**. 각 concern ACCEPT/PARTIAL/REBUTTAL 분류 + 근거. Charter §8 No Silent Override.

---

## 산출물 요약 (검증 대상)
- α̂ mean = established composite `score_eff` (rank-IC 0.042, ICIR 0.34, 256m — 실IC 보유·신규신호 아님).
- 예측 불확실성 σ̂ = NGBoost Normal.scale (expanding-window PIT), conformal lb = MAPIE SplitConformalRegressor 68%.
- 4 변형 동일 μ̂ mean 위 선택규칙만 변경: A point-top25 / B μ̂/σ̂ / C confidence-band(conformal lb>0) / D σ̂-shrunk.
- 실측: canonical_screen_bt (build_benchmark_compare, NW lag-3, metric_type=canonical_screen).

## 핵심 결과 (like-for-like, 196 full / 112 recent2017 월)
| 변형 | full PORT_t | recent2017 PORT_t | n_months(full) |
|---|---|---|---|
| A baseline | 0.970 | −0.725 | 196 |
| B risk_adj | 0.378 | −1.646 | 196 |
| C confband | 0.525 | +0.528 | **35 (degenerate)** |
| D shrunk | 0.566 | −1.196 | 196 |

**ΔPORT_t (best like-for-like B/D − A)**: full −0.40, recent 더 음. **FAIL** (2.95 게이트 근처도 아님).

---

## Concern 1 [HIGH] — Variant C "positive"를 성과로 오독할 위험 (프롬프트 concern ii/iii)
**적대 제기**: C가 full 0.525 / recent2017 +0.528로 유일하게 양수 — "confidence-band가 전이를 회복"으로 헤드라인?
**진단**: C의 n_months = full 35 / recent2017 **9** (A는 196/112). 정밀 진단: **196개월 중 0개월**만 conformal lb68>0 종목이 ≥25개(median 0, max 3). 즉 C는 실제로 25종 포트를 **한 번도 구성 못 함** — 1~3종 보유한 소수 월만 측정됨. rank_ic n=12/n=1.
**분류: ACCEPT (자기 반증)**. C의 양수는 **조건부-표집 생존편향 아티팩트**이지 like-for-like 개선 아님. → alpha_package·보고에서 C를 INVALID/degenerate로 명시, ΔPORT_t 판정에서 제외. 프롬프트가 경계하라 한 (ii)(iii)를 정확히 포착.
**근거**: `variant_results.json` C.full.n_months=35 vs A=196; 진단 스크립트 "months with >=25 confband-eligible names: 0/196". 1M active return의 68% conformal 하한이 양수인 종목이 사실상 없음(1M active는 노이즈 지배 — 당연).

## Concern 2 [HIGH] — σ̂가 look-ahead로 부풀려진 것 아닌가 (프롬프트 concern i)
**적대 제기**: expanding-window라 주장하나 NGBoost 재학습·MAPIE 캘리브가 미래 F1을 봤을 가능성?
**진단**: (a) 코드상 재학습은 `months[:ti]` 엄격히 t 이전만; MAPIE fit=months[:ti-24], conformalize=최근 과거 24m. (b) **누출 signature 검사**: PIT μ̂의 rank-IC = 0.031 ≤ score_eff mean IC 0.036 (동일 rows). 누출 모델이면 IC가 established mean을 **크게 상회**해야 하나 오히려 이하 → 부풀림 없음. (c) σ̂ 캘리브: within-month corr(σ̂, |realized active|) = **+0.207** — σ̂가 실현 분산을 유의하게 예측(진짜 정보). 캘리브가 진짜라 σ̂ 자체는 유효하나 그래도 선택개선 실패 → 결론 강화.
**분류: REBUTTAL (근거有)**. look-ahead 부재 입증(IC 비-부풀림 + 엄격 window). 학술: Duan et al. NGBoost 2020, Angelopoulos-Bates conformal 2023. L-code: [[reference-alpha-trends-2024-2026]] uncertainty-aware. 정량 3축: (IC 0.031≤0.036) + (σ̂-|active| corr +0.207) + (엄격 window months[:ti]).

## Concern 3 [MEDIUM] — 실패가 방법(NGBoost/MAPIE) 탓, 다른 확률모델이면 다를까
**적대 제기**: NGBoost 1종·MAPIE 1종만 시험. LightGBM-quantile/NGBoost-다분포면 회복?
**진단**: σ̂가 이미 calibrated(+0.207)인데도 selection/sizing이 A를 못 이김 = 병목은 σ̂ 추정 품질이 아니라 **1M long-only top-25 active의 IC→PORT_t 전이 자체**(신호계열·horizon·원천 무관 10-lead sweep으로 기확정, [[project-dart-insider-exec-nonreturn-frontier]]). σ̂ 차원 추가도 이 벽을 못 넘음이 본 WT의 확증 기여.
**분류: PARTIAL**. 다른 확률추정기 후속 EV는 존재하나(하한), calibrated σ̂ 실패는 **추정기 교체로 뒤집힐 결과 아님**(sizing 차원이 벽에 무력). 보고에 "추정기 1종 한계 — 단 calibrated σ̂ 실패라 낮은 EV" 명시.
**자기합리화 검사**: "다른 모델이면 될 것"은 조기-낙관 — 회피. 실측(calibrated σ̂ 무력)이 근거.

## Concern 4 [MEDIUM] — full-period 양수(A 0.97)를 "약한 성공"으로 볼 여지?
**적대 제기**: A full PORT_t 0.97 > 0, recent만 음 — 부분 성공?
**진단**: 0.97 ≪ 2.95 게이트. recent2017 −0.725 = cohort-wide decay(§6). full 양수는 2010-2016 기여분. 어떤 변형도 게이트 근처 아님. 자본급 아님.
**분류: ACCEPT**. "약한 성공" 라벨 금지 — clean FAIL. AX-000 정직보고: 탐색 중단 근거 아니나 본 경로(uncertainty selection)는 negative.

---

## 처리 결과 (반영)
1. C를 degenerate/INVALID 명시 — ΔPORT_t 판정은 A vs {B,D} like-for-like만. **ΔPORT_t < 0 = FAIL**.
2. look-ahead 부재·σ̂ 캘리브를 alpha_validation에 정량 기록(REBUTTAL 근거).
3. 판정: 불확실성-인지 선택/사이징은 IC→PORT_t 전이 **회복 실패**. 전이 벽이 sizing/selection 차원에 robust함을 추가 확증.
4. Axiom emit 대상(negative): return-composite mean 위 uncertainty-selection도 KR post-2017 감쇠벽 못 넘음.

## Escalate trigger 점검
- HIGH severity 2건 (< 5) / AX axiom hard FAIL 0 / PIT C1 위반 0 → **자동 escalate 불요**. Q-Lead 정상 핸드오프.

## 회피표현 자기검사
"미미/관행/보수적이면 OK" 미사용. C 양수를 "개선"으로 포장 안 함(생존편향 명시). 실측 수치·n_months 근거만.

---
---

# Self-Adversarial Challenge — WT-D20260705_004 (Risk Research)

**Agent**: risk-research (QEPM Opus 4.8 self-adversarial, v8.2 — AX-008 3-source 중 1개)
**Date**: 2026-07-05
**Finalize 직전 자체 적대검증**. Σ 추정의 약점 자가제기 → ACCEPT/PARTIAL/REBUTTAL. Charter §8 No Silent Override.

## 산출물 요약 (검증 대상)
- Σ = 40-name 배포 유니버스 **월간** 공분산, Ledoit-Wolf constant-correlation shrinkage(δ=0.451), cond **98.7**, PSD=TRUE.
- 추정 window = 242월(2006-02 .. 2026-03, ≥60% 커버리지), PIT Date≤2026-04-30(C1).
- market var share 0.681 / port β 0.777 / PC1 0.213 / specific share 0.832 / sector HHI 0.114.
- tail Hill α=2.58, ES99=4.69%; stress covid −14.0%/rate2022 −23.0%(reliable), GFC/EuDebt/China UNRELIABLE(partial listing).
- crowding score_eff 0.271 / uncertainty 0.145 (< 0.75, flag 없음).

## Concern R1 [HIGH] — 최초 estimator 선택이 degenerate identity Σ를 골랐음 (자기결함)
**적대 제기**: 첫 실행에서 min-condition-number 목적이 LW를 cond=1.0(scaled identity)로 선택 — off-diag 상관 전부 소거된 **무의미 Σ**. 이대로 optimizer에 넘겼다면 robust-opt 테스트가 "모든 종목 독립·동일위험" 가정 위에서 돌아 thesis 검증이 무효였을 것.
**진단**: 원인 = `hrp_core` LW 폐형이 tiny monthly-return 스케일에서 ρ→1 수치붕괴(진단: sample cor mean offdiag 0.189·cond 39.5는 건강 → 붕괴는 estimator 버그이지 데이터 아님). 수정: (a) 표준 Ledoit-Wolf 2004 **constant-correlation target** 자체구현(δ=0.451, 정상), (b) **degeneracy guard** 추가 — meanOffdiagCor < 0.5×sample 또는 cond<2 estimator는 조건수 무관 배제.
**분류: ACCEPT (자기 반증·수정 완료)**. min-cond 목적이 over-shrinkage를 보상하는 함정을 정확히 포착. 최종 Σ는 sample 상관구조(0.191)를 보존(LW 0.189)하며 cond 98.7<500.
**근거**: method_log[sample cond 120/offdiag 0.191, ledoit_wolf cond 98.7/offdiag 0.189/δ0.451/degenerate FALSE, gerber_rmt cond 353.8]. 수정 전 LW cond 1.0/PC1 0.025 → 수정 후 cond 98.7/PC1 0.213.

## Concern R2 [MEDIUM] — 17% NA-fill(mean-impute)이 상관을 눌러 위험 과소평가?
**적대 제기**: 추정행렬 NA 17%를 column-mean으로 채움 — 신규상장 종목의 결측월에 상수(평균) 주입은 그 구간 분산·상관을 0쪽으로 눌러 idio-vol 과소·상관 과소 유발 가능. optimizer가 위험을 낙관.
**진단**: (a) mean-impute는 해당 셀을 잔차 0으로 만들어 **분산을 낮추는 방향** — 즉 보수적이지 않고 낙관적. 단 (b) LW δ=0.451 shrinkage가 constant-corr target(0.189)로 끌어 과소상관을 부분 보정. (c) 정량: NA 종목은 2010+ 상장분에 집중, 242월 중 대부분 실측월 보유(median 266월 실측). 40종 중 최소 25월 실측(min col_cov=25)은 소수. (d) full-window vs recent-60m 상관구조 robustness = **0.78 상관** — mean-fill이 구조를 왜곡했다면 이 정합이 깨졌을 것.
**분류: PARTIAL**. mean-fill이 낙관 방향 편의를 넣는 것은 사실이나, LW shrinkage + 높은 실측 커버리지 + robustness 0.78이 왜곡을 제한적으로 유지. 개선 여지: EM/pairwise-complete 또는 신규종목 window-truncation. **capital-grade off the table**인 probe에서 clean-enough Σ로 충분(과잉엔지니어링 회피). risk_summary에 na_fill_rate=0.170 명시로 optimizer가 인지.
**자기합리화 검사**: "보수적이면 OK" 미사용 — 오히려 낙관 편의임을 명시. 실측(robustness 0.78·δ0.451)이 근거.

## Concern R3 [MEDIUM] — 20년 full-window가 2008 vintage 공동움직임을 현재에 혼입(regime-mixing)?
**적대 제기**: 2006-2026 전기간 Σ는 GFC·EuroDebt 고상관 국면과 최근 저상관 국면을 평균 — 현재(2026) 리밸 결정에 stale co-movement 주입. C1 위반은 아니나 estimation-relevance 문제.
**진단**: expanding-window는 PIT-safe(C1 충족·look-ahead 없음). regime-mixing은 정확성 우려이지 위반 아님. 정량: full offdiag 0.189 vs recent-60m 0.250 — 최근이 **더 높음**. 즉 full-window는 최근 상관을 **과소**평가(다시 낙관 방향). 이를 상쇄하려 regime-conditional 진단 별도 산출: crisis avg corr 0.131 vs normal 0.139(월간, 벤치 하위20% tercile) + regime_correlation.parquet 제공 → optimizer가 crisis-aware 원하면 소비 가능.
**분류: REBUTTAL (근거有)**. full-window Σ는 PIT-정당(C1)하며 robustness 0.78로 안정. 최근 상관 과소분은 regime_correlation 진단으로 명시 전달 — silent override 아님. 학술: expanding-window 표준(Pfaff FRM Ch8). L-code: [[reference-book-benchmark-alignment-realized-ym]] 정합(월간 정렬). 3축: (C1 expanding) + (robustness 0.78) + (regime 진단 별도 제공).

## Concern R4 [INFO] — market var share 0.681 > 0.40 (RF-R1) = 진짜 리스크인가 아티팩트인가
**적대 제기**: top common risk(market) 68% > 40% RF-R1 HIGH — Σ 오추정?
**진단**: KR long-only 40종의 market β 평균 0.777, PC1 0.213(상관 기준)은 **구조적**(시장성분 지배는 measurement-graduation §6 확립된 진실 — long-only β≈0.92, gross 상관 0.78). RF-R1은 KR long-only의 알려진 특성이지 추정오류 아님. exposure bound는 optimizer scope(위임).
**분류: REBUTTAL**. RF-R1 flag는 정직히 등재하되 "structural KR long-only, not estimation error"로 라벨. §6 정합.

## Escalate trigger 점검
- HIGH 1건(R1, 수정완료) / MEDIUM 2 / INFO 1 — HIGH<5 / AX hard FAIL 0 / PIT C1 위반 0 / **Σ PD violation 없음**(PSD=TRUE, cond 98.7) → **자동 escalate 불요**. Q-Lead 정상 핸드오프.

## 처리 결과 (반영)
1. degenerate LW 선택 버그 수정 — 표준 constant-corr LW + degeneracy guard. 최종 Σ cond 98.7·PSD·상관보존.
2. na_fill_rate 0.170 + regime_correlation.parquet를 risk_package에 명시(낙관편의·regime-mixing을 optimizer에 투명 전달).
3. RF-R1(market 68%)은 structural KR long-only 라벨로 등재(추정오류 아님).
4. Σ + tail + stress + crowding 진단만 산출. alpha·weight 불변(경계 준수).

## 회피표현 자기검사
"미미/관행/보수적이면 OK" 미사용. mean-fill을 낙관편의로 명시(보수 위장 안 함). 실측(cond 98.7·δ0.451·robustness 0.78·offdiag 0.189) 근거만.
