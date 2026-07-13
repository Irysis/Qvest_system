# R16 Self-Adversarial Challenge — 거래량/마이크로스트럭처 팩터 (FQ-029)

**작성**: 2026-07-13 · alpha-research (Opus 4.8 native adversarial) · prereg_sha256 8e9258a7…
**대상**: VSHK_P / TOD_DT / AMT_ASY / VPRC_CORR / ILLIQ_VOL (5종, AMH_D gate-drop)
**판정**: CONFIG_SCOPED_NEGATIVE (standalone capital) — 실선택 신호 존재하나 sub-gate, frontier 열림

---

## Concern 1 — placebo p_one<0.001 을 "신호 실재/자본급"으로 오독 (devil's advocate)
**제기**: 4/5 팩터가 placebo one-sided p<0.001 → "유의한 알파"로 광고 가능한가?
**분류: ACCEPT (framing 교정 의무)**
- null 분포가 mean −1.3(sd ~0.5)에 중심 — 랜덤 EW top-25가 cap-w 벤치 대비 구조적으로 음(소형주-vs-메가벤치 drag). 따라서 p_one<0.001 = "랜덤 선택보다 유의하게 나음"(선택 비랜덤성)이지 "양의 알파"가 아니다.
- **two-sided p = 0.52~0.98**(통상적 유의성 부재) + cap-w PORT_t 실측 0.44~1.16(전부 ≪2.95) + DSR 0.471<0.5.
- 처리: 보고 전면에서 **cap-w PORT_t / HARD 3종을 authoritative로 리드**, placebo는 "선택 정보 존재(비랜덤)"으로만 라벨. 자본급 주장 0건 명시.

## Concern 2 — 사전등록 부호와 상반된 결과의 사후 재해석 (C13 sign-flip 위험)
**제기**: VSHK_P(+등록)의 rank-IC가 t−3.01로 유의 음, AMT_ASY(+)·TOD_DT(−)도 wrong-signed. 이를 "short-side/exclusion feature"로 재라우팅하면 부호 뒤집어 성공 위장하는 것 아닌가?
**분류: PARTIAL (관측은 유지, 자본 주장 불가)**
- long-leg 판정은 등록 부호 그대로 **FAIL 보고**(VSHK_P long PORT_t 0.44, IC wrong-signed → long 무익). 부호 flip으로 long 팩터를 통과시키지 않음.
- "VSHK_P의 유의한 −IC(t−3.01) = 지속-거래량 종목이 체계적 underperform"은 **관측 사실**(AX-007 short-leg flavor, C24/C25 mean-reversion과 정합). 이를 exclusion overlay next_probe로 표시하는 것은 라우팅 관측이지 graduation 주장 아님 — capital-grade 0 불변. C13은 신호 부호정렬 실측을 금하지 않음(등록 후 flip해 재측정 금지를 지킴: 재측정 안 함).

## Concern 3 — VPRC_CORR EW-post2017 생존이 소형주 β 아티팩트/구성-특이 노이즈 아닌가
**제기**: VPRC_CORR EW post17 t=1.90·oos 1.60은 유일 EW-생존이나 **rank_ic ≈ 0(0.0015, t 0.28)** — 횡단 신호 부재. top-25 tail/구성에서만 나오는 값이면 진짜 팩터가 아니라 소형주 틸트 노이즈일 수 있다.
**분류: ACCEPT (온보딩 열기 하향)**
- rank_ic-null은 "cross-sectional 팩터"라기보다 극단 구성 효과 의심을 지지. EW-uni 1.85 < 2.0(비유의 informal bar)·자본 게이트(cap-w 0.86) 미달.
- 처리: VPRC_CORR add_factor 온보딩을 **확신 권고 → feature 보존 + next_probe(EW-relative basis 재측정)** 로 하향. cap-tier 국소화(92.6% OTHER) 재확인 = FQ-008/FQ-015 EW-생존군과 동형(벤치 미스매치). D3형 결정 재료지 자본 아님.

## Concern 4 — PIT/look-ahead 결함 가능성
**제기**: 월말 신호가 동월 수익을 참조하는 누출은 없는가(오버레이 C5 재발)?
**분류: REBUTTAL (clean, 근거 제시)**
- 신호 계산창 = d0(월말) 종가까지 일별 데이터, holding = d0→d1(다음 월말). 신호는 **홀딩월 시작 전**에 완결(오버레이 아님, 선택 신호). liq 필터 = 20d ADV through d0(C10 t-1 만족). rolling 전부 NA-strict frollmean(full-sample 통계 0, C1). shift(1) lag 명시. 부호 실측: VSHK_P −IC·VPRC null 등 = 만약 동월 누출이면 전 팩터 강한 양 IC로 나왔을 것(누출 징후 부재).
- 정량 3축: (1) cap-w PORT_t 전 팩터 <1.2 (2) EW 4/5 post2017 음 (3) placebo null −1.3 = 구조 drag 실재 → 누출로 부풀려진 흔적 없음.

---

## Self-rationalization auto-detection
"미미/관행/실무/보수적이면 OK/대부분 동일" 사용 여부 스캔 → **미사용**. 판정은 실측 수치(cap-w PORT_t, DSR 0.471, placebo two-sided)로만 기술. 회피어 없음.

## Q-Lead 자동 escalate 판정
- HIGH severity ≥5? **NO** (0건 — clean negative screening)
- AX axiom hard FAIL ≥3? **NO**
- PIT C1(lockbox/lookahead) 위반? **NO** (Concern 4 REBUTTAL clean)
→ **escalate 불요**. 예상 범위 내 config-scoped negative + 재라우팅 관측.

## AX-008 Verification Triangulation
self-adversarial = 3-source 중 1. 본 screening은 forge 미완주(자본 주장 없음)라 2/3 PASS 요건은 capital claim에만 적용 — capital claim 0이므로 삼각검증 게이트 비발화. 재라우팅 next_probe가 자본 후보로 승격 시 forge+architect 소환 의무.
