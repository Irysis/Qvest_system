# Self-Adversarial Challenge — RAMP R6: trailing PORT_t 기질 선별 + Boruta arm P

- **작성**: 2026-07-11 Q-Lead (RAMP orchestrator, Opus 4.8 native adversarial round — v8.2 Codex Round 대체, AX-008 3-source 중 1)
- **대상 산출**: `outputs/ramp/r6_portt_boruta_{prereg,gates,paired,summary}_20260711.*` · 패널 `r6_factor_deployzone_active.parquet` · L-RAMP-20260711_200226 · 판정 "KILL=FALSE(선별-정렬 축 미소진) + graduation=FALSE(screen-tier) + Boruta 음(kill_boruta=TRUE)"
- **사전등록**: `outputs/ramp/r6_portt_boruta_prereg_20260711.json` (config_hash `측정 전 동결`, PREREG byte-identical 재-hash) · runner `02_Infrastructure/ramp/run_ramp_r6_portt_boruta.R`
- **pin identity**: base_all11_W36 fresh == R4 base_W36_EW **bit-identical (max|Δ|=0.00e+00)** → 비교 basis 오염 없음.

## 핵심 판정 (사전등록 그대로)
- **KILL = FALSE** (kill_pure=FALSE ∧ kill_boruta=TRUE). max paired(P-pure vs base_all11)=**+2.25**(≥2.0 문턱) → 첫 조건(전 config <2.0) 미충족 → 선별-정렬 축 **미소진**.
- **graduation = FALSE**: best Ppure_W36_K20 cap-w PORT_t=2.61(<2.95)·oos_retention −0.08(<0.7)·calmar 0.45(<0.64). DSR 1.95만 통과. 0/6 arm HARD 통과.
- 기질 교체(P-pure vs base) +1.57/**+2.25**/+1.26/**+2.12** · 선별 격리(P-pure vs ctrl_all102) +2.06/**+3.01**/+1.49/+2.43 · Boruta 한계(P-boruta vs P-pure) **−2.58/−3.25**.

R4/R5(relevance 계열)이 base 대비 flat~유의음(−2.51~+0.18)이던 것과 달리, **realized-PORT_t 기질 교체는 첫 양(+) 선별 신호**다. 이 "부활신호 부분 성공" 주장 자체를 적대적으로 검증한다.

## 스스로 제기한 약점 (≥3) — ACCEPT / PARTIAL / REBUTTAL

### W1. "P-pure 개선 = 선별 효과가 아니라 102개별-vs-11군 granularity 차이" **[REBUTTAL]**
- 제기: P-pure(102 개별팩터 top-K)를 base_all11(11 군 composite)과 비교하면 substrate 입자도가 달라 개선이 선별이 아니라 개별화 부산물일 수 있다.
- 검증: **ctrl_all102**(동일 102 개별팩터, 선별無 EW)를 별도 control로 측정 → ctrl_all102_W36 cap-w PORT_t=**0.24 < base 1.02** (개별화는 오히려 손해 — 잡음팩터 희석). P-pure는 **동일 substrate ctrl_all102를 +3.01(W36K20) 초과** = 순수 선별 효과, 입자도 confound 제거. P-pure vs base(+2.25)는 선별이 granularity 페널티까지 넘은 것 → 선별 효과는 오히려 **과소평가**.
- 분류 **REBUTTAL**: confound가 결과를 만든 게 아님. ctrl_all102 격리로 선별 효과 순수 측정 완료. 오히려 헤드라인에 보수적.

### W2. "선별 신호가 실재한다 = 자본 가치가 있다" **[ACCEPT]**
- 제기: 개선이 pre-2017 집중이고 post-2017 절대 SR은 여전히 음이면, "신호 실재"는 자본으로 이어지지 않는다.
- 검증(pre/post-2017 분해, `_r6_prepost_split.R`): P-pure vs base paired **pre +2.05 / post +1.27**(K20W36) — post 양이나 sub-유의. vs ctrl_all102 **pre +3.99 / post +0.61**. 절대 post-2017 SR: 선별이 base −0.56 → **−0.11**로 끌어올리나 **여전히 음**. oos_retention −0.08(<0.7) HARD FAIL이 이를 정확히 포착.
- 분류 **ACCEPT**: 선별 레버는 실재하나 그 부가가치는 substrate가 강했던 pre-2017에 집중. post-2017 return-derived decay(전이 벽)는 선별로 극복 불가 = graduation 차단의 정확한 기전. **"screen-tier(신호 실재·자본 미달)"로 표기, "near-graduation" 프레이밍 금지**(2.61은 pre-2017 견인 point-estimate). 보고에 병기 완료.

### W3. "PORT_t rank 자기상관 0.86/0.92 = robust 예측력" **[PARTIAL]**
- 제기: 자기상관이 이렇게 높으면 선별이 매 재선별마다 사실상 같은 팩터(Value)를 고르는 near-static tilt이지 adaptive rotation이 아니다.
- 검증: 풀 family 빈도 = **Value 0.31~0.35 지배**, LowRisk 0.03~0.04. 즉 "PORT_t 상위 선별" ≈ "Value로 집중"(top-25 active 역사 최강 = Value). 높은 persistence는 예측력의 근거이자 동시에 **선별이 sticky-value tilt임의 증거**.
- 분류 **PARTIAL ACCEPT**: 자기상관은 선별 예측력을 실증(random factor-momentum과 구분 — 그래서 ctrl 대비 +3.01)하나, 기전은 "adaptive rotation"이 아니라 **trailing-조건부 sticky Value/Quality 집중**. 이는 W2와 정합(Value가 pre-2017 강세→post-2017 감쇠). "정교한 국면적 로테이션 발견"으로 과대주장 금지. 보고에 "sticky value tilt" 명시.

### W4. "factor-momentum crash risk 미점검" (스펙 요구 자가점검) **[PARTIAL]**
- 제기: trailing 성과 선별 = 팩터 모멘텀 → value/factor crash(2020 growth 급등 등) 시 급락 위험.
- 검증: best P-pure calmar 0.45(MDD-기반, base 0.28보다 개선이나 <0.64 게이트)·turnover 9.3(base 11보다 낮음 — sticky). post-2017 SR −0.11은 이미 최근 Value-불리 국면 반영. 별도 극단월 forensic은 미실행(잔여)이나 calmar+post17 음이 crash-취약을 대리 포착.
- 분류 **PARTIAL**: crash risk는 calmar/post17로 간접 확인(개선했으나 미달). 전용 factor-crash 이벤트 스터디는 잔여 — 단 graduation 이미 FALSE라 판정 영향 없음.

### W5. "Boruta 음(−2.58/−3.25)은 K 축소가 최적 미만이라서" **[REBUTTAL]**
- 제기: Boruta가 풀 20→confirmed(7~16)로 줄여 분산이 준 것뿐일 수 있다.
- 검증: R4에서 이미 "Boruta relevance 목적함수 과선별→손해"가 확립(paired −2.02~−2.51). R6에서 PORT_t-선별된 Value-풀 위에서도 Boruta는 Value 추가집중 → −2.58/−3.25로 **R4 기전 재현**. 즉 Boruta의 음 기여는 K-축소 아티팩트가 아니라 relevance-목적 과집중의 일반 성질.
- 분류 **REBUTTAL**: Boruta 음 기여는 robust·기전 일관. kill_boruta=TRUE는 정직한 계열(Boruta-on-any-pool) 소진.

### W6. "grade C·'미소진' = 자기합리화(과대 등급)" **[검출·기각]**
- 제기: graduation FALSE인데 C(F 아님)로 등급하고 "축 미소진"으로 프레이밍 = 실패를 성공으로 포장?
- 검증: kill(paired≥2.0)은 sha256 사전동결 문턱 — K20 2 config가 +2.25/+2.12로 객관적으로 초과 → kill_pure=FALSE는 사후해석 아닌 preregistered 사실. F는 kill/실패용(R4)이며 R6은 측정된 양(+) 선별 효과 + ctrl 격리 실증 → C(screen-tier)가 정확 범주. **단 "vindicated"는 선별 레버로 한정**(base 초과), graduation 경로로는 명시적 FALSE. 양쪽 정밀 병기.
- 분류 **기각(자기합리화 아님)**: 등급·프레이밍 모두 사전등록 문턱 + ctrl 격리 + HARD FALSE의 정직 조합.

## 스펙 필수 자가점검 3종 결론
1. **trailing PORT_t rank 지속성** — 자기상관 0.86(W36)/0.92(W60). 지속성 실재 → 선별 예측력의 기전(ctrl 대비 +3.01의 근거). 단 W3: 높은 지속성 = sticky Value 집중(adaptive rotation 아님).
2. **풀 cap-tier/방어형 쏠림** — Value 0.31~0.35 지배, LowRisk 0.03~0.04. R4 relevance-Boruta의 방어(LowRisk 0.95) 과선별과 **정반대** — PORT_t 기질은 역사 최강 top-25 active(=Value)로 집중. cap-tier 별도 분해는 잔여(size_dt 필요)이나 Value 집중 = KR 소형가치 틸트 시사(AX-003 value 감쇠 정합).
3. **P-pure 개선 시 factor-momentum crash risk** — 개선은 pre-2017 집중·post-2017 절대 SR 음(−0.11)·calmar 0.45(<0.64). crash-취약 간접 확인. graduation FALSE로 판정 영향 없음.

## 자기합리화 detect
- 문턱 이동 없음: kill(paired≥2.0)·HARD 3종(2.95/0.7/0.64)·DSR(family n_trials=16) 전부 측정 전 sha256 동결. best 2.61이 2.95 미달 = 사전등록대로 graduation FALSE.
- 반대방향(거짓 성공) 점검: Ppure_W36_K20 2.61을 "near-graduation"으로 승격할 유인 차단 — oos −0.08·calmar 0.45·post17 음이 명확 미달, 개선은 pre-2017 견인. screen-tier 정직 표기.
- 과대 판결 점검: "선별 축 미소진"은 선별 레버(vs base 초과)에 한정 — substrate decay 벽은 binding으로 별도 명시. INV-7 frontier(선별 축 open) vs settled(Boruta-on-pool 음) 분리.

## 최종 분류
**PARTIAL ACCEPT** — 판정(KILL=FALSE 선별축 미소진 + graduation FALSE screen-tier + Boruta 음)은 사전등록·pin bit-identical·ctrl 격리·pre/post 분해로 견고. 단 (a) 선별 신호는 pre-2017 집중·post 절대 SR 음(자본 미달, W2), (b) 기전은 adaptive rotation 아닌 sticky Value 집중(W3), (c) factor-crash 전용 forensic 잔여(W4)를 반드시 병기. 적대 라운드가 판정을 뒤집지 못했고(REBUTTAL 2·PARTIAL 3·기각 1) 스코프를 정밀화했다: **realized-PORT_t 기질 교체 = RAMP 최강 선별 레버(base·ctrl 초과)이나, return-derived substrate의 post-2017 전이 벽이 자본 졸업을 막는 binding 제약**. 선별 축은 open(INV-7 frontier), Boruta-on-PORT_t-pool은 음-소진.
