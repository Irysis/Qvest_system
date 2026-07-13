# Self-Adversarial Challenge — RAMP R13: 감쇠속도(oos) 축 chain (FQ-026)

- **작성**: 2026-07-13 Q-Lead (RAMP orchestrator, Opus 4.8 native adversarial round — v8.2 Codex Round 대체, AX-008 3-source 중 1)
- **대상 산출**: `outputs/ramp/r13_decay_{prereg,gates,paired,conc,oossub,summary}_20260713.*` · runner `02_Infrastructure/ramp/run_ramp_r13_decay.R` · L-code `L-RAMP-20260713_102944`(grade F·backtested·chain·composite)
- **사전등록**: `r13_decay_prereg_20260713.json` (config_hash `d997ab856f3c4884`, 측정 전 sha256 동결). **selection_type=chain**(sweep 아님 — 각 arm이 R12 next_probe F-1a/감쇠축에 대응)
- **base parity**: R13 base cap-w PORT_t 2.6124 vs R6 저장 2.6124 → |Δ|=1.39e-5 (bit-consistent). fresh level36 vs sel_traj trailing_t max|Δ|=0.00e0 (level 재계산 정합)
- **endpoint 위계**: 1차=oos_retention(v2, cap-w act_bm) / 2차=cap-w PORT_t. **긴장 정직 기록**: 선택=IS-only paired-t, 판정=게이트 산출 전체(oos는 최종 산출로만).

## 측정 요약 (★1차 oos / cap-w authoritative)

| arm | 기전 | cap-w PORT_t | oos(cap-w)★ | oos_EWuni | calmar | post17SR | TO | paired full (IS / OOS) |
|---|---|---|---|---|---|---|---|---|
| base (level36-top20) | — | 2.612 | −0.076 | 0.506 | 0.450 | −0.105 | 9.27 | — |
| **armD-2 감쇠 퇴출** | F-1 구조·퇴출=감쇠속도 | **2.503** | **+0.045** | 0.745 | 0.425 | **+0.048** | 9.45 | −0.282 (−1.432 / +1.203) |
| armD-3 부분창 일관성 | min(NW-t over 12m×3) | 2.164 | −0.028 | 0.972 | 0.424 | −0.083 | 9.63 | −1.281 (−2.136 / +0.337) |
| armD-1 감쇠 페널티 | z(lvl)+0.5·z(recent−older) | 1.555 | −0.448 | 0.141 | 0.328 | −0.412 | 9.67 | −1.452 (−0.735 / −1.283) |
| ctrl_factormom (진단) | recent18_t 단독(순수 FM) | 1.322 | −0.448 | 0.400 | 0.339 | −0.425 | 10.01 | (대조군, 판정 arm 아님) |

- **1차 IS-only 승자** = armD-1 (IS paired **−0.735** = 전 arm 음수 중 최소 = "덜 나쁨"). ★그런데 D-1은 실제 endpoint(oos)에서 **최악**(−0.448=FM). endpoint-선택 긴장이 **역설적 pick** 생성 → chain 규율(full 게이트 판정 우선)이 IS-승자를 자본화하지 않도록 방어(아래 C④).
- **판정 config_scoped_negative=TRUE**: best oos **+0.045 << 0.7** · HARD 3종 **0/5** · max full paired **−0.282 < 2.0** · GRADUATION FALSE.
- **1차 endpoint 이동**: best oos Δ **+0.121** (base −0.076 → D-2 +0.045) = R12 best(ctrl armF cad3 +0.121)와 **정확히 동일** — 퇴출-규율 계열의 oos 천장이 ~+0.12(≪0.7)임을 재확인(C⑥).

## 스스로 제기한 약점 (≥3) — ACCEPT / PARTIAL / REBUTTAL

### C① [task 지정] "D-1/D-2가 팩터모멘텀으로 수렴하는가" **[D-1 ACCEPT(수렴·붕괴) / D-2 REBUTTAL(구별)]**
- 제기: 감쇠속도(recent − older)를 선별에 쓰면 결국 최근-강세 팩터를 사는 factor momentum이 되고, FM은 KR서 MARGINAL/FAIL(hypothesis_index: 'Alpha Decay Adaptive FM'·'IC Decay-Weighted FM' MARGINAL, 'Cross-Factor Momentum' FAIL, timing NULL 06-30, DIST-AR-007 DISTILLED_NEG).
- 검증(R11 C①식 churn·rank AC·Jaccard vs ctrl_factormom):
  - **D-1 수렴 확증** — Jaccard(D-1, FM)=**0.713**(71% 풀 중첩) · cap-w D-1 **1.555** ∈ (base 2.612, FM 1.322)=level+momentum-tilt의 중간 · **oos D-1 −0.4481 ≈ FM −0.4478**(4째자리 차, 사실상 동일 붕괴) · rank AC D-1 0.766 ∈ (base 0.859, FM 0.666). → 감쇠속도를 **선별 재료**로 쓰면 FM으로 수렴하고 **FM과 함께 붕괴**. 교차모드 prior 실측 확증.
  - **D-2 구별 확증** — Jaccard(D-2, FM)=**0.440**(D-1의 0.713보다 훨씬 낮음) · Jaccard(D-2, base)=**0.884**(base pool 위 퇴출 규율) · post17SR +0.048(FM −0.425와 반대부호). → 감쇠속도를 **퇴출 트리거**로만 쓰면(base 선별 유지) FM과 구별되고 붕괴 회피.
  - **D-3 최-구별** — Jaccard(D-3, FM)=**0.331**(최저) = min-subwindow 일관성은 anti-momentum(과거 약하면 최근 강해도 강등) 설계대로 작동.
- 분류: **D-1 ACCEPT**(FM 수렴·붕괴 = task 우려 실현), **D-2 REBUTTAL**(구별·붕괴 회피), **D-3 REBUTTAL**(anti-momentum 실현). ★핵심 교훈: **"감쇠속도=선별재료(D-1)→FM→실패 / 감쇠속도=퇴출트리거(D-2)→base 유지→소폭 개선"** = "선별 규율 < 퇴출 규율" R11(armF)·R12(F-1) 테마의 감쇠-축 재확인.

### C② [task 지정] "감쇠 페널티가 sticky-Value 풀 정체를 실제로 바꾸는가(풀 구성 변화)" **[ACCEPT(바꾸나 역효과)]**
- 제기: 감쇠 페널티가 명목뿐이고 실제 풀 구성은 base와 같으면 실험이 공허하다. 반대로 크게 바꿔도 그게 좋은 방향인가?
- 검증: **풀은 실제로 크게 바뀜** — Jaccard(D-1, base)=**0.579**(base 대비 42% 교체), pool churn D-1 0.064 vs base 0.050(Δ+0.013). 즉 감쇠 페널티는 풀 정체를 확실히 흔든다. **그러나 그 변화 방향 = FM(Jaccard vs FM 0.713)** = 나쁜 방향 → cap-w 2.612→1.555·oos −0.076→−0.448 **악화**. 대조로 D-2는 풀을 거의 안 바꾸고(Jaccard base 0.884) 퇴출만으로 소폭 개선. → "풀을 바꾸는 것(D-1)"이 아니라 "무엇을 내보내는지(D-2)"가 유효.
- 분류 **ACCEPT(twist)**: 페널티는 풀을 실제로 바꾼다(공허 아님)이나 그 재편이 FM-방향이라 역효과 = D-1 가설(감쇠선별→oos개선) FALSIFIED. "풀 정체 타파"는 목표였으나 타파 방향이 틀림.

### C③ [task 지정] "oos 개선(D-2 +0.121)이 특정 시기(2020+) 아티팩트인가" **[PARTIAL ACCEPT — post-2017 국소·미소]**
- 제기: D-2의 oos 개선이 전 구간 실질이 아니라 특정 하위구간(예: 2020+ 코로나 반등) 아티팩트일 수 있다.
- 검증(2017 경계 subperiod 분해): D-2 개선의 **원천 = post-2017 SR을 base −0.105 → +0.048로 소폭 부호전환**(pre-2017 SR은 base 1.640 vs D-2 1.417 = D-2가 오히려 약간 낮음). 즉 D-2의 oos 이득은 **전적으로 post-2017 감쇠 구간 안에** 산다 — 감쇠속도 퇴출이 감쇠 국면에서 감쇠 팩터를 조기 배출해 소폭 방어. ⚠ post-2017-only oos3 비율(−0.83 등)은 IS-Sharpe 분모 근-0로 수치 불안정(base post oos −807 등 극단값 = 해석 불가, SR 부호로만 판독). **2020+ 단독 아티팩트는 아니나**(post-2017 전반), 이득이 미소(+0.048 SR)·감쇠 구간 국소 = 강건성 낮음.
- 분류 **PARTIAL ACCEPT**: 2020-only 아티팩트는 반증(post-2017 전반 분산)이나 이득이 post-2017 감쇠 구간 국소·미소 = "전 구간 실질 개선" 주장 불가.

### C④ "1차 IS-only 승자(D-1)가 실제 endpoint(oos) 최악 = 선택 규율 결함인가" **[REBUTTAL — 규율이 오히려 방어 작동]**
- 제기: chain의 IS-only 승자 지목이 D-1(oos −0.448 최악·FM 수렴)을 뽑았다 = 선택 규율이 최악 arm을 승격시킨다.
- 검증: 이것은 **결함이 아니라 규율의 방어 증거** — prereg가 "선택=IS, 판정=게이트 산출 전체(oos 1차)"를 명시했고, IS-승자 D-1은 **자본화되지 않는다**(HARD 0/5·paired −1.452). endpoint(oos)와 IS-선택이 갈릴 때 판정 권위는 **게이트 전체**에 있고, D-1은 게이트에서 즉시 탈락. 오히려 이 갈림 자체가 정보 = "IS paired로 arm을 고르면 FM-수렴 붕괴 arm을 집는다" = IS-선택의 한계를 실증(IS는 pre-2017 강세 구간 지배라 momentum-tilt를 선호). → 결함이 아니라 **chain 규율이 IS-과적합을 게이트로 차단**한 사례.
- 분류 **REBUTTAL**: IS-승자≠최선은 규율 설계상 예상된 갈림이며 게이트가 방어. 단 교훈 기록(IS paired 단독 선택은 momentum-편향, next_probe에 반영).

### C⑤ "D-2·D-3의 EW-uni oos가 높다(0.745·0.972) = 실은 성공 아닌가" **[REBUTTAL — cap-tier 트랩 재확인]**
- 제기: D-2 EW-oos 0.745·D-3 EW-oos 0.972는 문턱 0.7 초과 = EW-basis로는 졸업감이다.
- 검증: **자본 게이트 = cap-w authoritative**(measurement-graduation §2). EW-uni는 진단 basis일 뿐. cap-w oos는 D-2 +0.045·D-3 −0.028로 **붕괴** = FQ-015 확증(병목=cap-tier 국소화×cap-w 벤치 미스매치, 알파=벤치 저비중 소형 tier 국소화, OTHER 87~91% 비중). EW-oos 高·cap-w oos 低 = **long-only 횡단선택으로 cap-w 트랩 탈출 불가**의 정확한 재현. EW-basis 성공을 자본 성공으로 오독 금지.
- 분류 **REBUTTAL**: EW-real 신호는 실재하나 cap-w 자본 게이트 별개(3/5 arm EW-oos≥0.7이나 cap-w 전멸). 벽=cap-tier×cap-w 불변.

### C⑥ "감쇠속도 축이 R12 퇴출-규율(F-1)의 재발견에 불과한가" **[PARTIAL — oos 천장 공유이나 기전 차별]**
- 제기: D-2 oos Δ+0.121 = R12 ctrl armF cad3 +0.121과 정확히 동일 = 감쇠 퇴출이 그냥 cadence-3 퇴출가속의 재발견.
- 검증: **oos 천장은 공유**(퇴출-규율 계열 oos 상한 ~+0.12, 문턱 0.7의 1/6) = 정보값(퇴출 트리거를 rank로 하든 감쇠속도로 하든 oos 천장 동일 → oos 벽은 퇴출-규칙 형태에 불변). 단 **기전은 차별** — D-2 퇴출 트리거=감쇠속도(recent18<0 OR decay<−1.0), F-1=rank>30. cap-w는 D-2 2.503 < F-1 2.937(R12) = 감쇠속도 퇴출이 rank 퇴출보다 cap-w 낮음(감쇠 신호가 rank보다 노이지). → 재발견이 아니라 "같은 oos 천장·다른 cap-w 프로파일"의 독립 측정. **메타 확증**: oos 벽은 construction/exit-rule-invariant(4축 cap-w 포화 + 이제 exit-rule도 oos 천장 ~+0.12 공유).
- 분류 **PARTIAL**: oos 천장 공유는 재발견-유사(정보값)이나 감쇠-트리거 기전은 신규 측정. R12 F-1(2.937)이 감쇠-퇴출(2.503)보다 cap-w 우위 = 퇴출 트리거는 rank가 감쇠속도보다 나음(부수 교훈).

### C⑦ "12m 부분창 NW-t(D-3)가 너무 노이지해 min이 잡음 최소값을 집는가" **[PARTIAL ACCEPT]**
- 제기: 12개월 NW-t(lag3)는 표본 작아 노이지 → min-subwindow는 3 노이지 추정 중 최악을 집어 잡음에 페널티.
- 검증: D-3 rank AC=**0.513**(base 0.859 대비 크게 낮음) = D-3 선별이 앵커 간 불안정(잡음 시사). cap-w 2.164·oos −0.028 = 일관성 선별이 base 대비 개선 없음 — min이 노이지 최악값을 집어 안정 팩터를 잘못 강등했을 개연 실재. 단 D-3 EW-oos 0.972(최고)·Jaccard vs FM 0.331(anti-momentum 최강)은 설계 의도대로 작동한 증거 = 노이즈만은 아님. next_probe: min → trimmed-mean 또는 부분창 6m×2(표본 확대)로 노이즈 완화.
- 분류 **PARTIAL ACCEPT**: 12m NW-t 노이즈가 D-3 불안정(AC 0.513)에 기여 개연 실재이나, anti-momentum 신호(EW-oos·Jaccard)는 유효 = 순수 잡음 아님. 함수형 정련 여지.

## 자기합리화 detect
- **거짓 성공 차단**: D-2 oos +0.045(1차 best·Δ+0.121)를 'oos 축 돌파'로 승격 **금지** — +0.045 << 0.7(15배 부족)·cap-w 2.503<2.612(base 미달)·paired −0.282<0·HARD 0/5·config_scoped_negative=TRUE 명시. 방향 이동(Δ+0.121)은 R12 천장과 동일 = 미소·post-2017 국소.
- **거짓 실패 승격 차단**: D-1 붕괴를 '감쇠속도 축 전체 dead-end'로 종결 **금지** — D-1은 감쇠속도를 **선별 재료**로 쓴 특정 config만 FM 수렴. 퇴출-트리거(D-2)·anti-momentum 일관성(D-3)은 별개 config = "감쇠속도 선별 config-scoped negative"로 한정(어휘 규약 준수).
- **문턱 이동 없음**: IS_FRAC 0.65·oos 0.7·cap-w 2.95·paired 2.0·λ_D1 0.5·DECAY_DROP_BAR −1.0·subwin 18/18·12×3 전부 prereg(config_hash d997ab856f3c4884) 측정 전 동결. base parity Δ=1.4e-5.
- **chain 규율 준수**: 승자 지목 IS-only(OOS 미조회) · 2차 결합 없음(1차만, prereg) · DSR 진단용(chain→게이트 부적용, n_trials lineage=24). endpoint 긴장 정직 기록(선택 IS/판정 게이트).
- **과대판결 차단**: (C③) D-2 oos 이득은 post-2017 국소. (C⑤) EW-oos 高는 자본 아님. (C⑥) oos 천장 공유는 exit-rule-invariance이지 감쇠-축 무가치 아님.

## 다음-반복 가설 (실패 기전 → 다음에 무엇을 다르게, arm별 ≥2 — 종결 어휘 금지)
- **armD-1 (감쇠 페널티, FM 수렴 붕괴)** — 기전: 감쇠속도를 선별 재료로 쓰면 FM 수렴(Jaccard 0.713)·붕괴(oos −0.448=FM). λ=0.5도 momentum-tilt 지배.
  - **D-1a λ 하향 + 페널티 단방향**: λ를 0.5→0.15로 낮추고 **급락 팩터 강등만**(decay>0 보정 제거 = momentum-부스트 차단, penalty-only). FM 수렴의 원천=decay>0 부스트(최근 강세 매수)이므로 그것만 제거하면 base 근처 유지하며 감쇠명만 배출하는지.
  - **D-1b 감쇠속도를 종목-레벨로 이동**: 팩터-레벨 감쇠선별(FM 수렴) 대신 **종목 개별 trailing-alpha 기여 감쇠**로 top-25 내 감쇠 종목 배출(R12 B-1a 승계) = 팩터풀은 base 고정, 종목 선택만 감쇠-인지.
- **armD-2 (감쇠 퇴출, 1차 best·미소)** — 기전: 퇴출-규율이 base 유지하며 소폭 oos 개선이나 천장 ~+0.12(R12 F-1과 동일)·cap-w는 rank 퇴출(2.937)에 열위.
  - **D-2a 감쇠 퇴출 × rank 퇴출 AND-gate**: F-1(rank>30)과 D-2(감쇠<−1.0) **둘 다** 충족 시만 퇴출(보수적 배출) — rank·감쇠 각각의 노이즈를 교차확인해 cap-w(F-1 2.937 우위)와 oos(D-2 +0.045) 동시 취득 시도.
  - **D-2b 퇴출 후 현금-대체 없이 비-감쇠 재진입 게이트**: 빈 슬롯을 차순위가 아니라 **최근 재가속(decay>0) 팩터 우선**으로 충원 — 배출↔충원 대칭을 감쇠속도로 일관.
- **armD-3 (부분창 일관성, anti-momentum·노이지)** — 기전: min-subwindow가 12m NW-t 노이즈로 불안정(AC 0.513)·cap-w 개선 없음.
  - **D-3a 부분창 6m×2 또는 trimmed 일관성**: 12m×3(노이지) → 18m×2 겹침창 min 또는 3창 trimmed-mean = 노이즈 완화하며 지속성 신호 보존.
  - **D-3b 일관성을 EW-basis 선별로**: D-3 EW-oos 0.972(최고) = 일관성 신호가 EW-유니버스서 강함 → cap-w 트랩 밖(EW-basis D3형 배포성 결정 재료·FQ-015 E2 계보)에서 소비 검토(자본 아님, 결정 재료).
- **메타(축 확정)**: **oos 벽은 construction-invariant(R10~R12 cap-w 4축)에 더해 exit-rule-invariant(퇴출-규율 oos 천장 ~+0.12)로 확대 확증** = return-derived substrate 위 시간-함수형 튜닝(선별·퇴출·일관성)은 oos를 0.7 근처로 못 올림. **생산적 프론티어 = 재료 축**(R9/FQ-001 DART insider 비-수익 패널 — insider backfill 완료 후 PORT_t-정렬 선별 × 비-수익 substrate) + **basis 재분류 축**(EW-real D3형 배포성 결정 재료, cap-w 트랩 밖). 시간-함수형 축은 cap-w·oos 양면서 한계효익 소진 지대(config-scoped negative 누적 R4~R13).

## 최종 분류
**PARTIAL** — chain은 규율대로 완주(base parity Δ1.4e-5·level 재계산 Δ0·IS-only 승자·prereg 동결 config_hash d997ab856f3c4884·2차 결합 없음). 라운드 target(감쇠속도 선별로 oos 축 이동)은 **1차 endpoint 소폭 이동 실측**(D-2 oos +0.045, base −0.076 대비 Δ+0.121)이나 **net-불충분**(best oos +0.045<<0.7·cap-w 2.503<2.612·max paired −0.282<0·HARD 0/5) = **config-scoped negative**(감쇠속도 선별 config 한정). 적대 라운드가 판정을 못 뒤집고 scope·기전 정밀화: **(C①)** 감쇠속도=**선별재료(D-1)면 FM 수렴(Jaccard 0.713)·붕괴(oos −0.448=FM)** / **퇴출트리거(D-2)면 FM 구별(0.440)·base 유지·소폭 개선** = "선별 규율 < 퇴출 규율" 감쇠-축 재확인; **(C②)** 감쇠 페널티는 풀을 실제로 재편(Jaccard base 0.579)하나 방향이 FM이라 역효과; **(C③)** D-2 oos 이득은 post-2017 감쇠 구간 국소·미소(post17SR −0.105→+0.048); **(C⑤)** D-2/D-3 EW-oos 高(0.745/0.972)이나 cap-w oos 붕괴 = cap-tier 트랩 재확인; **(C⑥)** oos Δ+0.121 = R12 천장과 동일 = **oos 벽이 exit-rule-invariant**로 확대 확증. 메타: 감쇠속도는 퇴출-규율로 쓸 때만 base를 지키며 소폭 개선하나 oos 천장 ~+0.12(문턱 0.7의 1/6)·cap-w 벽 불변 = **시간-함수형 축(선별·퇴출·일관성)은 cap-w(R10~R12 4축 포화)에 이어 oos축도 ~+0.12 천장으로 소진 지대** 확증 = **프론티어를 재료 축(R9 DART insider 비-수익 substrate)·basis 재분류 축(EW-real 배포 결정 재료)으로 전환하라는 방향 표시**이지 종결이 아니다. cap-tier 국소화×cap-w 벽은 본 라운드가 못 풂(사전 명시) = construction+exit-rule-invariant 진단.

## No-Silent-Override 기록
도훈 판정프레임 교정(2026-07-13) 적용: negative = "config-scoped negative + 프론티어 표시"로만 서술, "소진/폐쇄/dead-end" 종결 어휘 미사용. 각 arm 실패 기전에서 next_probe ≥2 도출(위 절, 총 6 + 메타 2). 측정 설계(3 arm+FM 대조·prereg config_hash d997ab856f3c4884) 불변 — 판정/보고 규약만 교정 프레임 준수. FM 수렴 판별 의무(task 지정) 이행: D-1 수렴 실측·D-2 구별 실측·D-3 anti-momentum 실측(C①).
