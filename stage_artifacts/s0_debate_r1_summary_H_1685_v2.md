# H_1685 v2 R1 Transcript Summary

R1 Total: 65/100

## 5인 주장 요약


### codex_critic (score: 7/20)

**주장 1**: KOSDAQ fundamentals are aligned by fiscal period instead of actual disclosure timestamp, so the regime/alpha stack indirectly uses not-yet-public data during backtest ranking.

**주장 2**: The composite remains effectively linear-dominant (M01-like). During a Korea small/mid-cap factor unwind, the dominant sleeve drives synchronized losses and overwhelms diversification claims.

**주장 3**: The weakest assumption is that regime adaptation can reduce drawdown without diluting core alpha. If this assumption is wrong -> overlay noise suppresses valid signals -> trading becomes procyclical (

**concern**: REJECT pending redesign. [Fact] H_1690 is linked to a failure chain (STR_1439, H_1677, H_1676, H_1685, H_1687). [Inference] Gate-15 variance_ratio and linear-dominance checks are required but not shown as passed, so L-code conflicts remain active. [Inference] Regime adaptation has only conditional L

**conditions**: 5건


### risk_manager (score: 14/20)

**주장 1**: Kill Scenario 1 (CRISIS regime 외국인 exodus 시 잔차 붕괴 비대칭): v2 residualization은 평균 |corr(resid, -z_I)| = 0.194로 H_1674 독립성을 확보했으나, p95 |corr| = 0.4469는 약 13건 극단 월이 존재함을 드러낸다. stress_factor_ic_analysis.csv 실증에서 INV02_Foreign_NetBuy_60d crisis_ratio = 0.364 (위기 시 63% 붕괴), INV01_20d crisis_ratio = 1.093 (소폭 개선)으로 lookback에 따라 위기 행태가 극적으로 달라진다. 핵심 위험: expanding OLS beta_t는 전체 기간 평균적 관계를 학습하므로, 2008 GFC/2020 COVID처럼 외국인-개인 관계가 구조적으로 전환 (regime break)되는 구간에서 beta_t가 과거 정상기 패턴에 고착되어 잔차에 위기 시 외국인 exodus 신호가

**주장 2**: Kill Scenario 2 (미래참조 경로 - expanding beta_t 조기 수렴 및 C1 검증 한계): expanding-window pooled OLS beta_t는 burn-in 60개월 이후 매월 수십만 관측치가 누적되므로, 실질적으로 t=120 이후 beta_t 변동폭이 극히 작아진다 (law of large numbers). 이는 장점(안정성)이자 치명적 약점이다. 2000-2010 전반기 외국인-개인 관계 구조가 2020년대 한국시장 구조 변화 (passive ETF 급증, 동학개미, 외국인 KOSDAQ 확대)를 전혀 반영하지 못한다. beta_t가 사실상 상수로 수렴하면 residual = z_F - c * z_I (c=상수)가 되어, 시간에 따른 관계 변화를 포착 못하는 구조적 한계가 발생한다. 이것이 backtest에서는 안정적으로 보이지만 실시간 운용에서는 structural break 누적 위험이다. Rolling 3Y OLS beta와 expanding

**주장 3**: L-106/L-156 v2 교차 적용 - p95 tail 0.447과 TDC cluster 위험: L-106은 시장 beta 0.85~0.93이 portfolio-level 상관을 지배함을 실증했고, L-156 v2는 pairwise TDC > 0.4이면 위기 시 sleeve 간 동조 drawdown이 구조적임을 확인했다. v2 residualization이 H_1674와의 평균 상관을 0.194로 줄였지만, p95 |corr| = 0.4469는 L-156 v2 TDC gate 0.4 기준을 초과하는 극단 월이 존재함을 의미한다. 이 극단 월이 CRISIS regime과 시간적으로 겹치면 (예: 2008-09~2009-03, 2020-02~2020-04), 바로 그 diversification이 가장 필요한 시점에서 H_1685와 H_1674의 tail dependence가 급등하는 역설이 발생한다. compute_copula_tdc() regime-conditional 측정에서 C

**concern**: expanding OLS beta_t의 비대칭 적응 실패: beta_t는 정상기 수십만 관측에 의해 지배되므로, 위기 시 외국인-개인 관계의 구조적 전환 (foreign exodus + retail surge)을 반영하는 데 수개월~수년이 소요된다. 이로 인해 CRISIS regime 진입 직후 1~6개월간 residual은 사실상 '과거 정상기 관계에 기반한 잔차'로서, 위기 시 외국인 행태 변화를 포착하지 못하고 오히려 역방향 포지션을 유도할 수 있다. MRS 63.1 CRISIS 현재 시점에서 이 신호 기반 전략의 즉시 투입은 바로 이 비대칭 적응 실패 구간에 해당할 가능성이 높다.

**conditions**: 4건


### governor (score: 15/20)

**주장 1**: PG0 gap + role admission 관점에서 v2는 v1 16점 대비 구조적으로 개선된 hypothesis입니다. v1 corr 0.897 (H_1674와 수학적 duplicate) 결함이 residualization으로 수식상·실증상 해소되었고(mean |corr| 0.194, median 0.168, 255개월 실증), channel preservation 0.895로 Choe-Kho-Stulz 2005 외국인 정보 우위 축 본체가 유지됩니다. investor_flow family 첫 diversifier axis 확보는 rev7_v3_v1 Phase_3 (STR_1631/H_1688/STR_1656/STR_1679v3/H_1682/H_1689/H_1690 7축) 이후 8번째 cross-channel 독립 alpha로 SR boost roadmap (target 2.0)에 정합합니다.

**주장 2**: Role Honesty Audit 관점에서 diversifier 위장 위험은 v1 대비 감소했습니다: H_1674 (core_alpha, 개인 contrarian raw)와 v2 (foreign residualized) 사이 sub-family 분리 + 수식적 orthogonality 보장. Residual signal은 fundamental/consensus/ML/distress/quality/momentum/defense 기존 7개 family와 전혀 다른 거래행동 차원으로 원천 독립. Family saturation 측면에서 investor_flow 2건 (core_alpha + diversifier) 구성은 consensus 기존 STR_1631 1건보다 balanced family architecture를 제공합니다. 다만 precedent 부재 + tail dependence (p95 0.447) 경계 필요.

**주장 3**: Implementation feasibility는 가장 큰 우려입니다: INV13 신규 factor registry 등록 + compute_investor.R expanding β accumulator 확장 + C11 거래주체 T+1 timing 검증 + burn-in 60개월 data loss + p95 극단 월 regime-conditional TDC 별도 검증. 구조적으로 필요한 5개 선결 조건 중 lookahead_detector INV13 4종 패턴은 초안 수준, factor_registry INV13 entry는 미등록, β_t accumulator builder 성능 구현은 미검증. rev7_v3_v1 Phase_1 편입 schedule 관점에서 H_1690 Forge S1 4-variants (V1~V4) + H_1682 Primary Contingency A/B/C + STR_1684 V1 3건 병행 중이므로 INV13 신규 구현은 Phase_2 이후 편입이 현실적이

**concern**: implementation_feasibility 1점 감점의 근원은 v1 대비 구현 복잡도 증가입니다. v1 (raw z_F - z_I divergence)는 기존 INV-series 단순 승계로 compute_investor.R 30줄 확장이면 충분했으나, v2는 expanding-window pooled OLS β accumulator (cum_SxY/cum_Sxx shift(1L), burn-in 60m) + 월별 cross-sectional z-score + residualization 3단계 로직 추가로 60~80 LOC 확장이 필요하고 builder 성능 최적화 (monthly 재계산 방지)까지 요구됩니다. Forge v2 현재 STR_1682/1683/1684 3-parallel + H_1690

**conditions**: 3건


### quant (score: 13/20)

**주장 1**: β_t 방향성 발견 (v1 debate 미포착): expanding OLS β_t = -0.36 (음수). 이는 잔차가 z_F - (-0.36)×z_I = z_F + 0.36×z_I, 즉 z_F와 z_I의 가중합임을 의미. v2 설계에서 'H_1674와의 orthogonalization'을 목표로 했으나, 실제로는 OLS 잔차가 수식상 z_I를 0.36배 양방향으로 추가하는 구조. ICIR 관점에서: IC(residual) = IC(z_F) + 0.36×IC(z_I_raw). IC(z_I_raw) < 0 (개인 매수 = 역방향 signal)이므로 IC(residual) = IC(z_F) - 0.36×|IC(z_I_raw)| ≈ 0.052 - 0.037 = 0.015 monthly. ICIR(annualized) = 0.015 / IC_sd × sqrt(12). IC_sd 0.04~0.08 범위에서 ICIR 0.65~1.30 추정 — 0.20 gate 통과 확실. 단, R²(z_F ~

**주장 2**: 2020-2026 구간 orthogonality 열화 실측: D_2020-2026(75개월) mean|corr vs H1674| = 0.2437 — 전체 255개월 0.1938은 PASS이나 최근 6년은 FAIL(>0.20 gate). 이 기간 months >0.30 = 32%, >0.40 = 10.7%. 극단 월: 2020-03(COVID 패닉, corr=0.667), 2022-03(러시아 침공, corr=0.609), 2021-03(경기 반등, corr=0.528). 패턴 분석: 한국시장 급락기에 외국인과 개인이 동시 매도('동반 이탈') → 외국인-개인 flow 공분산 방향이 평상시와 달리 동기화 → residual이 H_1674(개인 contrarian)와 양의 상관으로 전환. MRS 63.1 CRISIS 현재 상태는 2020-2026 구간 성격과 유사 → 단기 orthogonality 가정 압박. S3에서 regime-conditional TDC 검증 필수(L-156 v2 

**주장 3**: 21d lookback 회전율 Hard Fail 위험 정량 추정: H_1674 v1에서 21d lookback → 연간 회전율 2,082%(Hard Fail) 실증. H_1685 v2 잔차는 channel preservation corr = 0.895(z_F_raw)로 z_F_21d 구조를 그대로 계승. 인접 월 공유 거래일: 21d 기준 ~15/21일 = 71%, 랭크 자기상관 ~0.65~0.75 예상. Top 20 포트폴리오(전체 2,000종목 중 1%)에서 이 자기상관으로 연간 회전율 1,200~2,000% 예상 → 600% Hard Fail 거의 확실. 반면 63d lookback: 공유 42/63일 = 67%, 회전율 400~600%(경계선), 126d lookback: 공유 105/126일 = 83%, 회전율 250~400%(PASS). S1 착수 전 63d/126d 병렬 sensitivity 의무화. 21d 단독으로 S1 실행 시 Hard Fail 위험.

**concern**: 가장 중요한 정량 우려: 2020-2026 구간(75개월) mean|corr| = 0.2437으로 이미 0.20 gate 초과 실측. 이는 현재 시장 국면(MRS 63.1 CRISIS)이 H_1685 v2의 orthogonality 전제가 가장 취약한 구간과 일치함을 의미. expanding OLS β_t가 -0.36으로 안정적이지만, 위기 구간에서 실제 corr(z_F, z_I)가 음수에서 양수로 전환되면 β_t 추정이 평균 근방을 유지하더라도 당기 잔차의 H_1674 상관이 급등. 즉, 잔차화 구조 자체는 PIT 적합하나 regime-dependent orthogonality 보장 실패 — 위기 국면에서 diversifier 역할이 무력화될 수 있음. 21d lookback Hard Fail 확실성(>8

**conditions**: 3건


### academic (score: 16/20)

**주장 1**: Peer-review 축은 v1과 동일하게 만점(4점)을 유지합니다. v2의 residualization 재설계는 학술적 토대를 약화시키지 않고, 오히려 Fama-MacBeth (1973) JPE + Daniel-Grinblatt-Titman-Wermers (1997) JF + Brennan-Chordia-Subrahmanyam (1998) JFE + Jegadeesh-Titman (1993) JF 등 methodological 정전 4편을 추가로 지지 논문에 편입할 여지를 만듭니다. Primary는 여전히 Choe-Kho-Stulz (2005) RFS이며 설계 철학이 Choe-Kho-Stulz의 원본 질문(한국에서 외국인이 정보 우위를 갖는가)을 residual space에서 정식화한 것이므로 학술적 계보가 v1보다 오히려 명료합니다. RFS 1편 + JFE 2편 + NBER WP 1편 + 한국재무학회지 1편 + (methodology) JPE 1편 + JF 2편 + JFE 1편 

**주장 2**: Mechanism_align 축은 v1 R2에서 quant의 corr 0.897 실측으로 1점 감점한 구간을 v2에서 만점(4점)으로 복원합니다. v1 R2의 핵심 감점 이유였던 'divergence 신호가 H_1674와 algebraically 동일' 문제가 v2 residualization으로 수식 수준에서 해소되었고, Scout의 실측(255개월, mean|corr| 0.194, median 0.168, channel preservation 0.895)이 이를 확증합니다. v2 residualization은 Fama-MacBeth (1973) cross-sectional regression residual 사용, Daniel-Grinblatt-Titman-Wermers (1997) characteristic-matched residual, Brennan-Chordia-Subrahmanyam (1998) risk-adjusted residual 등 1970~1990년대 학술 정전

**주장 3**: Korea_evidence와 time_decay 두 축은 v2에서도 구조적 우려가 해소되지 않아 v1 R1과 동일 점수(3점/2점)를 유지합니다. Korea_evidence: Choe-Kho-Stulz (2005) + Kho-Kim (2007) + 고영훈·안일찬 (2018) 3편 국내 direct 실증은 확보되나, 2020~2026 post-COVID 동학개미 구조 대변화 이후 residual signal의 predictability를 검증한 최신 한국 peer-reviewed 실증이 여전히 s0_record에 제시되지 않습니다. v2는 21d primary + 63d sensitivity를 S2 profiling으로 이관했지만 '2020-2026 sub-period 재현 실증'은 여전히 gap입니다. Time_decay: Choe-Kho-Stulz 2005 post-publication 20년 경과 + McLean-Pontiff (2016) JF 프레임 58% decay 중앙값 +

**concern**: v2의 가장 중대한 잔여 우려는 'residualization이 mechanism 수학은 치유했으나 time decay 학술 증거 공백은 치유하지 못했다'는 점입니다. v2 expanding-window OLS + channel preservation 0.895 + 실측 corr 0.194는 설계 수준에서 매우 훌륭하며 Fama-MacBeth 정전 계보로 peer_review·mechanism_align 두 축을 강화합니다. 그러나 Choe-Kho-Stulz (2005) RFS와 Grinblatt-Keloharju (2000) JFE가 모두 20~25년 경과 논문이라는 사실은 residualization으로 완화되지 않으며, 한국시장의 2020년대 구조 변화(패시브 자금 비중 30%+ 상승, 동학개미 일평균

**conditions**: 4건
