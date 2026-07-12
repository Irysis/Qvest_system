# Self-Adversarial Challenge — RAMP R7: 선별 라벨 basis 교체(E1) + R6-best dual-basis 재분류(E2)

- **작성**: 2026-07-12 Q-Lead (RAMP orchestrator, Opus 4.8 native adversarial round — v8.2 Codex Round 대체, AX-008 3-source 중 1)
- **대상 산출**: `outputs/ramp/r7_ewbasis_{prereg,gates,paired,e2_reclass,summary}_20260712.*` · `r7_ewbasis_e2_captier_bymonth_20260712.parquet` · runner `02_Infrastructure/ramp/run_ramp_r7_ewbasis.R` · L-RAMP-20260712_161537
- **사전등록**: `r7_ewbasis_prereg_20260712.json` (config_hash `192bc9400eda1ca1`, 측정 전 sha256 동결) · KILL rule = (A) 4 config 전부 paired(E1 vs capw-repro)<2.0 AND (B) EW-real(EW-uni≥2.95 ∧ EW-oos≥0.7) 후보 0 → 라벨 basis 축 소진
- **vintage 무오염 실증**: capwrepro_W36_K20 == R6 Ppure_W36_K20 **bit-identical**(pin capwt Δ=0.000·EWuni Δ=0.000) · sel_repro K20 anchors 70개 불일치 0 · cap-w BM Jul-12 vs 패널 Jul-11 max|Δ|=0.00e+00(nonzero 0/256 — April-gap 백필이 패널기간 BM 불변) · 1-factor parity V02_EP 재구성 cap-w PORT_t=2.0470 vs R6 fac_full 2.0470(Δ=6e-06)

## 핵심 판정 (사전등록 그대로)
- **E1 KILL_axis = TRUE**: (A) max paired(E1 라벨교체 vs capw-repro)=+1.23<2.0 (4 config: −0.05/−0.74/+1.23/−0.77) ∧ (B) EW-real 후보 0 → 라벨 basis 축 소진. best E1 Epure_EW_W36_K20 cap-w PORT_t=1.99(R6 best 2.61에서 **하락**).
- **E2 = screen-tier 잔류**: cap-w authoritative HARD 3종 미달 불변(capwt 2.61<2.95·oos −0.08<0.7·calmar 0.45<0.64). EW-basis서 post-2017 SR −0.11→+0.49·oos −0.08→0.51·EWuni PORT_t 3.92(canonical diag 독립확증 3.9185·oos 0.506·post17 t 1.48)이나 **EW-oos 0.51<0.7 → EW-real=FALSE(near 0.5만)**. cap-tier OTHER(멤버 cap rank 31+) 비중 90.6%·gross 기여 86%.
- **graduation=FALSE**. 자본 게이트 cap-w authoritative 불변.

## 스스로 제기한 약점 (≥3, 스펙 필수 3종 포함) — ACCEPT / PARTIAL / REBUTTAL

### W1. "E1 유일 양(+) config(W60_K10 +1.23)은 소형주 틸트 강화의 부산물" (스펙 ① — 배포성) **[PARTIAL]**
- 제기: EW 라벨이 소형주-premium이 강했던 in-sample 국면으로 더 틸트해 약한 config만 밀어올린 부산물일 수 있다.
- 검증: (a) 유일 양 config는 4개 중 **가장 약한** W60_K10(capw 1.45→1.83)뿐 — 나머지 3개 flat~음(−0.05/−0.74/−0.77), 최강 W36_K20는 오히려 2.61→1.99 하락 = **robust 개선 아님, 사전등록 kill 문턱(2.0) 미달**. (b) 선별 차이 실재(K20 Jaccard cap-w∩EW 0.71~0.74, ~27% 상이)하나 Value 집중 불변(0.31→0.29 / 0.35→0.35) = 라벨 교체가 sticky-Value tilt를 못 흔듦. (c) 배포성: 전략 전체가 이미 소형(OTHER 90.6%)이며 canonical 유동성 floor(ADV≥2e8) 통과 = 담기는 종목은 K200∪KQ150 **지수편입 소형주(마이크로캡 아님)**이나, cap rank 31+ 90% 집중은 대형자금 **수용력 제약**.
- 분류 **PARTIAL**: +1.23은 레버 아님(비-robust·sub-threshold) — REBUT. 단 소형주 90% 수용력 caveat는 ACCEPT(어떤 arm이든, 졸업 무관하나 배포 시 실재 제약). 보고에 병기.

### W2. "EW-유니버스 수익의 생존편향·멤버십 시점 정합" (스펙 ② — 데이터 무결성) **[REBUTTAL]**
- 제기: EW 벤치가 마이크로캡을 포함하거나 미래 멤버십을 참조하면 EW-uni 헤드라인이 오염된다.
- 검증: `build_monthly_forward_returns`의 returns_dt는 **K200∪KQ150 멤버 제한**(월평균 312종목: 2005년 200→2026년 348, K200/KQ150 플래그 기준) — full rawdata 1962종목 아님. **EW(all in returns_dt)==EW(member-only) 상관 1.0000·max|Δ|=0**(returns_dt 자체가 멤버-only이므로 자명). 멤버십은 결정시점 월말(.me ≤ signal_date)의 K200/KQ150 플래그 = **PIT forward-safe**(미래 멤버십 미참조). 두 독립 EW 구성(gates 수동 ewb + canonical diag univ_prefilter=score 유니버스)이 PORT_t 3.92/3.9185로 **교차일치**. 결측수익 종목은 그 달 EW 벤치서 제외(canonical note) = 진단에 보수(하방) 방향.
- 분류 **REBUTTAL**: 멤버 패널 PIT·이중구성 일치·마이크로캡 배제 확인. 생존편향은 표준 지수-멤버 패널 수준(미래참조 없음).

### W3. "E2 EW-real 프레임 = 자본 게이트 우회" (스펙 ③) **[REBUTTAL]**
- 제기: EW-uni PORT_t 3.92>2.95를 "EW기준 졸업"으로 포장해 cap-w HARD FAIL을 우회할 유인.
- 검증: (a) EW는 **명시적 진단 basis**(v8.3 M2, HARD 게이트 비바인딩) — cap-w(bench_dt) authoritative가 판정 권위, 그 3종(2.61/−0.08/0.45) 전부 FAIL. (b) 더 약한 EW-real 문턱(EW-uni≥2.95 ∧ **EW-oos≥0.7**)조차 미충족 — EW-oos 0.51<0.7 → EW-real=FALSE(near 0.5만). (c) D3형(벤치-상대 배포성 결정)은 **도훈 결정 재료이지 자동 자본 아님** — 게다가 이번엔 그 재료 자격(EW-real)에도 미달 → null-to-marginal 종결. 어떤 경로로도 자본 편입 없음.
- 분류 **REBUTTAL**: cap-w authoritative 불변 + EW-real 조차 미달 + D3≠졸업 3중 방벽. 우회 프레임 성립 안 함.

### W4. "KILL_axis 문턱이 사후 조정됐나 (자기합리화)" **[기각]**
- 제기: (A) paired<2.0 · (B) EW_REAL 2.95/0.7 문턱을 결과 보고 맞췄을 수 있다.
- 검증: prereg JSON(config_hash 192bc9400eda1ca1)이 arm 측정 **이전**에 sha256 동결·기록(prereg 16:10 → arm 측정 이후). PAIRED_KILL=2.0·EW_REAL_PT=2.95·EW_REAL_OOS=0.7 전부 코드 상단 상수. 실측 max paired +1.23·EW-real 0 = 문턱 대비 명확 미달(경계 tipping 아님).
- 분류 **기각**: 사전동결 문턱의 정직 적용.

### W5. "'감쇠=cap-w 아티팩트' 과대주장" **[PARTIAL]**
- 제기: cap-w post17 −0.11 vs EW post17 +0.49 gap으로 "부진은 벤치 탓일 뿐"이라 결론지으면 과대.
- 검증: EW post17 SR +0.49는 양이나 **NW-t=+1.48(sub-2, 비유의)**·EW-oos 0.51(<0.7). 즉 EW-basis서 post-2017 알파는 **방향은 실재하나 여전히 sub-threshold** → "감쇠는 벤치 탓일 뿐"은 과대, "**상당분**이 cap-w 벤치 미스매치 아티팩트(mega-cap 편중)이나 EW-basis서도 D3 미달"이 정확.
- 분류 **PARTIAL ACCEPT**: lesson/보고에 "상당분(partly)·EW서도 sub-D3" 캘리브레이션 유지. "전부 아티팩트" 금지.

### W6. "cap-tier MEGA/MID/OTHER 정의 타당성" **[REBUTTAL]**
- 제기: OTHER 90.6%가 마이크로캡이면 배포 불가·측정 무의미.
- 검증: diag_cap_tier 랭킹은 **size_dt(=K200∪KQ150 멤버 312/mo) 내 상대랭킹** — OTHER=멤버 cap rank 31+ = **소형 지수편입주**(마이크로캡 아님·유동성 floor 통과). 정의 타당하며, OTHER가 여전히 liquid 지수멤버라는 점은 국소화 결론을 **강화**(알파=벤치 저비중 tier, project-captier-alpha-localization 정합).
- 분류 **REBUTTAL**: 정의 건전·결론 강화.

## 자기합리화 detect
- 문턱 이동 없음: kill(A paired 2.0·B EW-real 2.95/0.7)·HARD 3종·DSR(family n_trials=20) 전부 측정 전 sha256 동결. 실측 미달이 사전등록대로.
- 거짓 성공 점검: EW-uni 3.92를 "EW 졸업"으로 승격할 유인 차단 — EW-oos 0.51<0.7로 EW-real조차 FALSE, cap-w authoritative FAIL 불변.
- 과대 판결 점검: "라벨 basis 축 소진"은 **라벨 basis 하위축**에 한정(선별-정렬 대(大)축 자체는 R6서 최강 레버 확립, 여기선 그 refinement 1갈래만 종결). 잔존 frontier(PORT_t-정렬 × 비-수익 패널)는 open으로 명시(INV-7).

## 스펙 필수 자가점검 3종 결론
1. **E1 개선 = 소형주 부산물?** — 유일 양 config(+1.23)은 비-robust·sub-threshold(kill 미달). 소형 90% 수용력 caveat 병기(배포 시 실재, 졸업 무관).
2. **EW 유니버스 무결성** — 멤버 패널(312/mo)·PIT 멤버십·이중구성 일치·마이크로캡 배제. 생존편향 없음.
3. **EW-real ≠ 게이트 우회** — cap-w authoritative FAIL 불변 + EW-real조차 미달(EW-oos 0.51<0.7) + D3≠졸업. 3중 방벽.

## 최종 분류
**PARTIAL ACCEPT** — 판정(E1 라벨 basis 축 KILL + E2 screen-tier 잔류·감쇠 상당분 cap-w 아티팩트)은 사전등록·vintage bit-identical·1-factor parity·이중 EW구성 일치로 견고(REBUTTAL 3·PARTIAL 2·기각 1). 적대 라운드가 판정을 뒤집지 못했고 스코프를 정밀화했다: **(a) E1 +1.23은 레버 아님(비-robust); (b) E2 post-decay는 상당분 cap-w 벤치 아티팩트이나 EW-basis서도 sub-D3(EW-oos 0.51<0.7·post17 t 1.48); (c) 소형주 90% 수용력 caveat.** 메타 결론: **병목은 선별 '라벨 basis'가 아니라 substrate의 cap-tier 국소화(소형지수주 알파) × cap-w 벤치 미스매치** — 라벨 교체는 '어떤 팩터'를 바꾸지 top-25의 cap-tier 구성을 못 바꿔 벽이 불변. long-only 횡단선택으로 cap-w 트랩 탈출 불가(project-captier-alpha-localization) 재확인. 선별-정렬 대축의 잔존 frontier = PORT_t-정렬 × 비-수익 패널(DART insider 등, FQ-001 연계).
