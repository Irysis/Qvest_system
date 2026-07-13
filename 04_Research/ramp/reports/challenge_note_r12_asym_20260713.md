# Self-Adversarial Challenge — RAMP R12: 비대칭·이질 construction chain (FQ-025)

- **작성**: 2026-07-13 Q-Lead (RAMP orchestrator, Opus 4.8 native adversarial round — v8.2 Codex Round 대체, AX-008 3-source 중 1)
- **대상 산출**: `outputs/ramp/r12_asym_{prereg,gates,paired,conc,summary}_20260713.*` · runner `02_Infrastructure/ramp/run_ramp_r12_asym.R` · L-code `L-RAMP-20260713_100000`(emit 후 확정)
- **사전등록**: `r12_asym_prereg_20260713.json` (config_hash `85d9c45646a8bb3a`, 측정 전 sha256 동결). **selection_type=chain**(sweep 아님 — 각 arm이 R11 next_probe F-1/B-1/V-1에 1:1 대응)
- **base parity**: R12 base cap-w PORT_t 2.6124 vs R6 저장 2.6124 → |Δ|=1.39e-5 (bit-consistent)
- **OOS 노출 관리**: R11 OOS 수치는 arm 선택 입력으로 미사용(가설 동기로만). R12 IS-only 승자 = R12 자체 IS paired-t.

## 측정 요약 (cap-w authoritative)

| arm | 기전(R11 진단 대응) | cap-w PORT_t | EW-uni | oos | calmar | post17SR | TO | paired full (IS / OOS) |
|---|---|---|---|---|---|---|---|---|
| base (EW×EW) | — | 2.612 | 3.919 | −0.076 | 0.450 | −0.105 | 9.27 | — |
| **armF-1 비대칭 퇴출** | 진입 반기·퇴출 분기 즉시 | **2.937** | 4.344 | **+0.048** | 0.500 | +0.035 | 9.23 | **+1.819** (+0.410 / +2.159) |
| armB-1 비대칭 밴드 | 진입 엄격20·퇴출 즉시25 | 2.522 | 3.729 | −0.021 | 0.442 | −0.085 | 6.48 | −0.321 (−1.258 / +0.737) |
| armV-1 창 이질 | 36m∪60m 합집합 | 2.348 | 3.782 | −0.093 | 0.426 | −0.177 | 9.06 | −0.702 (−0.903 / −0.135) |
| ctrl armF cad3 (진단) | R11 full 재선별 | 2.852 | — | +0.121 | 0.471 | — | 9.28 | (대조군, 판정 arm 아님) |

- **1차 IS-only 승자** = armF-1 (IS paired **+0.410** = P-pure 계보 **첫 양의 IS paired**. R11 전 arm IS 음수였음). chain 규율: OOS 미조회·R11 OOS 미입력.
- **판정 config_scoped_negative=TRUE**: max full paired **+1.819 < 2.0** · HARD 3종 **0/5** · best oos **+0.048 << 0.7** target.
- **계보 최고 갱신**: armF-1 cap-w 2.937(계보 최고 — R10 W-stock 2.930·R11 armV 2.895 초과, 자본문턱 2.95까지 **0.013**) · paired full +1.819(계보 최고 — R11 max +0.582의 3.1배). 단 종결 아님 = 유의(2.0)·HARD 미달.

## 스스로 제기한 약점 (≥3) — ACCEPT / PARTIAL / REBUTTAL

### C① [task 지정] "armF-1 퇴출 가속 = 사실상 cadence3(armF full 재선별)과 동일 효과" **[REBUTTAL — 차별성 실증]**
- 제기: 퇴출을 분기로 당기고 빈 슬롯을 차순위 충원하면 결국 매 분기 top-K를 재구성하는 armF(cadence3)와 같아지고, R11 armF의 재발견에 불과하다.
- 검증(4중 대조): (a) **pool churn 낮음** — base 0.050 < F-1 **0.057** < armF **0.069**(연속 배포월 기준). F-1은 grey-zone(rank 21~30) incumbent를 유지하고 명확 감쇠(rank>30 또는 trailing-t<0)만 배출 → armF full 재선별보다 스텝 작음. (b) **F-1↔armF pool Jaccard 0.906**(90% 유사하나 동일 아님 — 10%가 유지된 incumbent). (c) **stock TO 더 낮음** — base 9.27 · F-1 **9.23** · armF 9.28(F-1이 최소). (d) **cap-w 더 높음** — F-1 **2.937 > armF 2.852**: 적은 churn·낮은 회전으로 **높은** cap-w = "퇴출 규율 > 전면 재선별 규율"(cap-w 축). → armF의 재발견 아니라 **더 효율적인 변형**.
- **정직 caveat (PARTIAL)**: pool 90% 중첩은 높다 = F-1은 "가벼운 손질 armF"이지 근본적으로 다른 construction 아님. 차별성 실재하나 modest. 또한 **oos 개선은 F-1(+0.048) < armF(+0.121)** — 퇴출만으로는 armF의 oos 이득을 완전 복제 못 함(진입측 전면 갱신이 감쇠 국면 oos에 추가 기여). "퇴출만 빨라도 충분"은 cap-w엔 참·oos엔 부분참.
- 분류 **REBUTTAL**: factor-momentum/armF 재발견 반증(churn↓·Jaccard 0.906·TO↓·cap-w↑). 단 90% 중첩·oos 부분복제는 caveat.

### C② [task 지정] "armB-1 엄격 진입이 유효 종목수 미달·집중을 만든다" **[REBUTTAL — 집중 무·실패는 신호]**
- 제기: 진입 rank<=20만 신규허용하면 25종을 못 채워 소수 종목 집중(HHI↑·eff-N↓)이 생기고, B-1의 부진은 집중 부작용의 산물이다.
- 검증: **집중 없음** — n_hold(mean) **24.9**·min **20**·short_months **7/220**(3.2%)·eff-N **24.95**(base 25.00)·HHI **0.0401**(base 0.0400)·maxw 0.040. "기존 보유 유지분 충원" 규칙 + 잔류존(rank 21~25)이 봉투 ≤25 유지하며 미달을 흡수 → 집중 부작용 거의 무. B-1의 부진(paired −0.321)은 **집중 아티팩트 아니라 신호** — paired **IS −1.258**(in-sample서도 손해)이 핵심: 즉시 퇴출(rank>25)이 경계의 신호명을 매도. R11 진단(P-pure top-25 경계 churn=신호)과 정합.
- **부수 정보(양성)**: B-1(비대칭)은 R11 armB(대칭 [25,35])보다 **개선** — oos −0.121→**−0.021**·cap-w 2.414→**2.522**·TO 6.81→6.48. 비대칭 방향은 옳으나(대칭보다 나음) 여전히 base 미달(net-neg).
- 분류 **REBUTTAL**: C②의 집중 가설 falsified(eff-N 24.95·HHI≈base). B-1 부진=경계 신호 매도(IS도 손해)이지 under-hold 아님.

### C③ [task 지정] "armV-1 창 이질 코호트의 실제 다양성이 R11 armV보다 큰가" **[ACCEPT — 다양성 실현·but 역효과]**
- 제기: 36m+60m 창 이질이 3M-offset(R11 armV, Spearman 0.923·Jaccard 0.671)보다 진짜 다양성을 확보하는가, 아니면 명목뿐인가.
- 검증: **다양성 실현** — 36∪60 Jaccard **0.491**(R11 0.671 대비 훨씬 낮음=더 다양) · trailing_t Spearman **0.797**(R11 0.923 대비 낮음) · union size mean **27.1**(단일 20 대비 확대). 관측창 이질화가 offset보다 실질 다양성 큼(목표 달성). **그러나 다양성이 역효과** — cap-w **2.348 < base 2.612 < R11 armV 2.895**: 60m 안정창이 **감쇠 팩터를 오래 붙든 stale 후보를 합집합에 주입** → 신호 희석. "더 다양 ≠ 더 좋음"의 깨끗한 반례. R11 armV(3M-offset, 고상관)가 오히려 cap-w 높았던 이유 = 두 코호트가 동일 최신 신호를 공유해 stale 주입 없음.
- 분류 **ACCEPT(twist)**: V-1은 다양성 목표를 달성(Jaccard 0.491)했으나 그 다양성이 cap-w를 해침 = V-1 가설(이질→개선) FALSIFIED, 다양성 메커니즘은 작동. 합집합 아닌 방향(교집합·비대칭 가중)이 next_probe.

### C④ "armF-1 cap-w 2.937 = 자본문턱 2.95까지 0.013 — 졸업 임박인가" **[REBUTTAL — 결속 벽은 oos]**
- 제기: cap-w가 2.95를 0.013 남기고 육박 = 한 라운드만 더 하면 졸업.
- 검증: **결속 실패 축은 cap-w 아니라 oos_retention** — F-1 oos **+0.048 vs target 0.7**(15배 부족). graduation은 HARD 3종 **전부** 필요(PORT_t 2.95 ∧ oos 0.7 ∧ calmar 0.64). cap-w 근접은 실재(계보 최고)이나 oos·calmar(0.500<0.64)는 멀다. cap-w 축은 R10~R12서 2.85→2.90→2.94로 포화 근접 = **더 밀 여지 작음**. "0.013 남음"은 축 오독 — 벽은 post-2017 감쇠/oos(cap-tier 국소화×cap-w, R7/R8 확증).
- 분류 **REBUTTAL**: 졸업 임박 프레임 거부. cap-w near-miss는 방향성, 결속 벽=oos(15배 부족).

### C⑤ "armF-1 full paired +1.819 < 2.0 — 문턱 직전 = 실개선인가 near-miss 행운인가" **[PARTIAL ACCEPT]**
- 제기: +1.819는 2.0 미달·문턱 근접 = 유의 주장 불가·행운일 수 있다.
- 검증: R11 arm들과 **질적 차이** — F-1은 IS paired **+0.410(양)** ∧ OOS paired **+2.159(유의)** 둘 다 양(R11 armF/V는 IS 음·OOS만 양=OOS-luck 프로파일). 양방향 양성 = R11 OOS-집중보다 **강건**. 단 full **+1.819 < 2.0** = 사전등록 "meaningful" 문턱 미달. 방향성·계보 최강이나 유의 미달.
- 분류 **PARTIAL ACCEPT**: 개선 실재·양방향 양성(R11보다 강건)이나 +1.819<2.0 = 유의 미달 정직 병기.

### C⑥ "세 독립 construction 축(R10 비중 2.930·R11 vintage 2.895·R12 비대칭퇴출 2.937)이 전부 cap-w ~2.9 천장 = R12는 4번째 축서 같은 벽 재확인(낭비)" **[REBUTTAL — 정보값 + 축 전환 확정]**
- 제기: 비중·vintage·비대칭퇴출이 모두 cap-w ~2.9서 멈추면 R12는 새 정보 없이 같은 벽을 재확인.
- 검증: **정보값 2중**: (a) cap-w 천장이 2.85→2.90→**2.937**로 기어올랐고 F-1이 계보 **첫 양의 IS paired** = 비대칭 퇴출은 단순 재확인 아닌 **최강 construction 레버**(진행 실재). (b) 그럼에도 **결속 벽=oos_retention(0.048 vs 0.7) construction-invariant** 확증 → "다음 무엇" 확정: cap-w 축은 포화(더 construction 무익), **생산적 프론티어는 oos/감쇠 축(F-2 감쇠속도 선별)과 재료 축(R9 DART insider)**. 벽의 construction-invariance는 방향 확정이지 종결 아님.
- 분류 **REBUTTAL**: 4축 동일 cap-w 천장 = 벽 construction-invariant 확증 + 축 전환(construction→감쇠/재료) 확정. 낭비 아님.

### C⑦ "R11 trailing_t 캐시 재사용 = vintage 오염 가능성" **[REBUTTAL]**
- 제기: TT_ALL을 R11 캐시서 재사용했으니 vintage 불일치·parity 오염 위험.
- 검증: base parity **Δ=1.39e-5**(R6 저장 2.6124와 bit-consistent) · anchors_exit(cadence3) ⊂ R11 TT_ANCHORS(완전포함, "R11 재사용 74 anchors" 로그) · vintage_pin `r6_session_20260711` 동일 · sel_traj 36+60 동일 캐시. 오염 없음.
- 분류 **REBUTTAL**: parity bit-consistent·anchor 완전포함·pin 동일.

## 자기합리화 detect
- **거짓 성공 차단**: armF-1 cap-w 2.937(계보 최고·문턱 0.013 근접)를 '졸업 임박'으로 승격 **금지** — oos +0.048<<0.7·calmar 0.500<0.64·paired +1.819<2.0·HARD 3종 0/5·config_scoped_negative=TRUE 명시. 계보-최고 near-miss는 방향성이지 자본 자격 아님.
- **문턱 이동 없음**: IS_FRAC 0.65·paired 2.0·HARD 3종·EXIT_RANK_BAR 30·B1 [20,25] 전부 prereg(config_hash 85d9c45646a8bb3a) 측정 전 동결. base parity Δ=1.4e-5.
- **chain 규율 준수**: 승자 지목 IS-only(OOS 미조회·R11 OOS 미입력) · 2차 결합 없음(1차만, 사전등록) · DSR 진단용(chain→게이트 부적용, n_trials lineage=21).
- **과대판결 차단**: (C②) B-1 '경계 신호 매도' 결론은 이 substrate 한정. (C③) V-1 '이질 역효과'는 합집합-config 한정(교집합·비대칭 가중 미검증). armF-1 'exit>refresh'는 cap-w 축 한정(oos엔 부분참).

## 다음-반복 가설 (실패 기전 → 다음에 무엇을 다르게, arm별 ≥2 — 종결 어휘 금지)
- **armF-1 (비대칭 퇴출, 계보 최강 레버)** — 기전: 비대칭 퇴출이 cap-w 최고(2.937)·첫 양 IS paired이나 oos는 armF full(+0.121)에 못 미침(+0.048) = 퇴출만으론 감쇠-국면 oos 이득 부분복제.
  - **F-1a 퇴출-트리거 × 감쇠속도(F-2 융합)**: rank/부호 대신 **trailing-t 기울기(최근 3~6m Δt)**로 퇴출 — 레벨 높으나 빠르게 식는 팩터 선제 배출. F-1(+0.048)과 armF(+0.121)의 oos 격차가 "진입측 갱신이 잡는 감쇠"를 지목 = 감쇠속도 퇴출이 full 재선별 없이 그 이득 포획 가설.
  - **F-1b 퇴출문턱 sweep + 재진입 확인 (oos 축 직타)**: cap-w 포화(2.94)이므로 EXIT_RANK_BAR(25/28/30/35) IS-only sweep의 목표를 **oos_retention 최대화**로 재설정(결속 축 직접 공략) + 재진입 시 상위 재확인 게이트.
- **armB-1 (비대칭 밴드)** — 기전: 즉시 퇴출이 경계 신호명 매도로 IS도 손해(대칭보다 낫지만 net-neg).
  - **B-1a 기여-기반 퇴출(B-2 승계)**: 퇴출을 composite rank 아니라 **종목 개별 trailing-alpha 기여**로 — 경계서 신호명 보유·잡음명 배출 분리(rank-밴드의 무차별 매도 해소).
  - **B-1b B-1 밴드 × F-1 pool 스택**: B-1을 base 아니라 **armF-1 pool(계보 최강)** 위에 적용 — 밴드 손실(−0.321)이 pool 우위(+1.819)에 흡수되는지. (chain: F-1 IS 승자 확정 후 2차 결합 대상)
- **armV-1 (창 이질)** — 기전: 합집합 이질이 다양성은 얻으나(Jaccard 0.491) 60m stale 주입으로 cap-w 역효과.
  - **V-1a 교집합 + 비대칭 가중**: 합집합 대신 **36m∩60m(fresh∧stable core)** 또는 36m 주·60m를 tie-break/안정 overlay로 하방 가중 — stale 주입 차단하며 안정성만 취함.
  - **V-1b 60m를 감쇠속도-필터 pool로 대체**: 60m의 문제=안정하나 stale → "레벨 高 ∧ 감쇠속도 低" pool(F-2 아이디어)로 60m 교체 = 안정성 이득·staleness 제거.
- **메타(축 전환)**: cap-w 축 포화(2.94 근접) 확정 → 생산적 프론티어 = **oos/감쇠 축**(F-1a/F-1b/V-1b 감쇠속도 계열)과 **재료 축**(R9 DART insider 비-수익 패널, FQ-001, insider backfill 완료 후). construction 미세조정은 cap-w 한계효익 소진 지대.

## 최종 분류
**PARTIAL** — chain은 규율대로 완주(base parity Δ1.4e-5·IS-only 승자·R11 OOS 미입력·prereg 동결·2차 결합 없음). 라운드 target(비대칭/이질 construction으로 oos·cap-w를 유의까지)은 **계보 최강 방향성 개선 실측**(armF-1 cap-w 2.937 계보 최고·paired full +1.819 계보 최고·첫 양의 IS paired +0.410)이나 **net-불충분**(full paired +1.819<2.0·HARD 3종 0/5·oos +0.048<<0.7) = **config-scoped negative**(진입-반기/퇴출-분기·비대칭 밴드 [20,25]·36∪60 합집합 config 집합 한정). 적대 라운드가 판정을 못 뒤집고 scope 정밀화: **(C①)** armF-1은 armF 재발견 아님(churn↓·Jaccard 0.906·TO↓·cap-w↑ = exit>refresh, 단 90% 중첩·oos 부분복제 caveat); **(C②)** B-1 엄격 진입은 under-hold/집중 아님(eff-N 24.95·HHI≈base) — 부진=경계 신호 매도(IS도 손해)이나 R11 대칭밴드보다 개선; **(C③)** V-1 창 이질은 실제 다양성 달성(Jaccard 0.491<0.671)이나 60m stale 주입으로 cap-w 역효과(이질≠개선); **(C④/C⑥)** cap-w 축 포화 ~2.94·결속 벽=oos_retention(0.048 vs 0.7) construction-invariant. 메타: 비대칭 퇴출이 construction 레버 중 최강(cap-w 계보 최고·첫 양 IS)이나 결속 벽이 cap-w 아닌 oos임을 4축서 확증 = **프론티어를 construction 미세조정(포화)에서 감쇠속도 선별(F-1a/F-1b/V-1b)·재료 축(R9)으로 전환하라는 방향 표시**이지 종결이 아니다. cap-tier 국소화×cap-w 벽은 본 라운드가 못 풂(사전 명시) = construction-invariant 진단. return-derived substrate 위 construction 튜닝은 R4~R12 config-scoped negative — 프론티어(감쇠속도 선별·교집합 이질·재료 R9) 열림.

## No-Silent-Override 기록
도훈 판정프레임 교정(2026-07-13) 적용: negative = "config-scoped negative + 프론티어 표시"로만 서술, "소진/폐쇄/dead-end" 종결 어휘 미사용. 각 arm 실패 기전에서 next_probe ≥2 도출(위 절). 측정 설계(3 arm·prereg config_hash 85d9c45646a8bb3a) 불변 — 판정/보고 규약만 교정 프레임 준수.
