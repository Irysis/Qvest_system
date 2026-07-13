# Self-Adversarial Challenge — WT-D20260713_002 (R18 accounting-forensic statistical factors)

Opus 4.8 native adversarial reasoning (v8.2 — no external Codex). finalize 직전 자기 적대검증.
AX-008 3-source(Forge/Self-Adversarial/Architect) 중 self-adversarial 축.

## 결과 요약 (실측, cap-w authoritative)
| factor | cap-w PORT_t | IS→OOS | EW-uni t | EW post2017 | placebo p | rank-IC t | verdict |
|---|---|---|---|---|---|---|---|
| F-A ModJones DiscAccr | 0.449 | 1.07→−0.57 | −0.33 | −1.05 | 0.035 | 0.60 | config-scoped NEG |
| F-B Benford FSD | 0.568 | 0.79→−0.14 | −0.30 | −0.33 | 0.160 | −1.00 | config-scoped NEG |

둘 다 HARD 3종(PORT_t 2.95 / oos 0.7 / calmar 0.64) 전부 미달. n_months=191.

## Concern 분류 (ACCEPT / PARTIAL / REBUTTAL — 근거 필수)

### C1 [필수·ACCEPT] F-A가 단순 accruals와 상관 높아 증분 없음
- **실측 근거**: FA_vs_AC13ref 횡단 monthly spearman **mean=0.991** (sd 0.006, n=192). AC13ref = 원본 Jones(ΔRev만) per-FY 잔차 — 내 F-A(수정 Jones, ΔRev−ΔREC)와 거의 완전 동일.
- **해석(정량, 합리화 아님)**: KR 대형주 횡단에서 ΔREC 조정항이 잔차 구조를 바꾸지 못함 = 수정 Jones ≈ 원본 Jones. 이는 "미미"라는 hand-wave가 아니라 corr 0.991 실측치. 게다가 factor DB의 AC13(pooled Jones)은 **이미 standalone LO top25 FAIL**(2026-06-06: PORT_t 0.227, oos −0.53, Grade F). 내 F-A PORT_t 0.449도 동일 계열 실패로 일관.
- **판정 ACCEPT**: F-A는 기존 AC13과 중복(redundancy_cluster=accrual_AC13) + 독립 증분 없음. standalone add_factor 부적격. 소비경로 = quality/accrual composite 보조 feature(DIST-QPM-003/006 이미 커버). alpha_package redundancy_cluster_id·challenge_flags에 명시.

### C2 [필수] F-B가 기업 규모/계정 수의 위장인지
- **실측 근거**: FB_vs_Size 횡단 corr **0.006** (n=192) → Size 무관. Size-partial(월별 Size 잔차화 후 재스크린) PORT_t = 0.449 ≈ raw 0.568 → Size 제거해도 불변.
- **판정 REBUTTAL(Size 위장 아님) + 그러나 factor 자체 NULL**: Benford FSD는 Size/계정수 프록시가 아님(자기적대 우려 해소). 그러나 이는 "clean signal"을 뜻하지 않음 — **placebo p=0.160**(PORT_t 0.568이 corp-shuffle 잡음 분포 안) + rank-IC t=−1.00(가설 부호 반대·무의미) → **F-B는 진짜 신호구조가 없는 clean null**. Size 아티팩트가 아니라 그냥 예측력 부재.

### C3 [필수·PARTIAL] KR 회계기준 변경(K-IFRS 2011)의 구조 단절
- **인지**: (a) K-IFRS 전면도입 2011 → 계정 정의·표시 단절, (b) 원천 소스 전환 QuantiWise(≤2015, raw 32항목)→DART(2016+, raw 24항목) → FSD 절대수준 이동, F-A의 항목 구성 변화.
- **완화**: 신호는 **월별 횡단 z-score**로 소비 → 절대수준 이동 제거(같은 달 내 동일 소스·기준 상대비교). 2017+ 분리(EW post2017: F-A −1.05, F-B −0.33)도 별도 부정.
- **판정 PARTIAL**: 구조단절은 실재하나 monthly-z가 상당부분 흡수. 단 2016 전환년의 소스-혼재는 잔존 caveat(대형주라 균일하나 완전 통제 아님). verdict(NEG) 불변 — 단절이 있었어도 EW-basis 전체가 음(−0.30/−0.33)이라 아티팩트로 살아날 여지 없음.

## 추가 devil's-advocate (자기제기 ≥3 충족)
- **D1 [ACCEPT] 벤치 아티팩트 방어**: dual-basis 의무 실행 — 둘 다 **EW-universe basis에서도 음**(F-A ew_t −0.33, F-B −0.30). ∴ post-2017 mega-cap cap-w 아티팩트로 기각되는 유형이 **아님**. 진짜 알파 부재(FQ-008 재분류군에 해당 안 됨). "cap-w 트랩" escape 불가.
- **D2 [PARTIAL] 커버리지 2009-06+ (2005+ 아님)**: frozen monthly_panel.rds 시작이 200906 → power 축소(191m). sibling R17과 동일 조건이라 비교가능성 위해 채택. IS(<2019) 114m에서도 PORT_t 1.07(F-A)로 이미 약함 → 2005 확장이 결론 뒤집을 EV 낮음(caveat만 기록).
- **D3 [REBUTTAL] MID-tier 국소 생존 가능성?**: cap-tier OTHER 비중 90-95%(소형 집중). "MID(11-30)에 신호 살아있을 수도" 가설 → EW-universe 전체가 이미 음이므로 tier 재배분으로도 부활 불가. cap-tier 국소화 트랩(project-captier-alpha-localization)과 정합하나, 여기선 소형tier조차 EW-basis 음 = tier 무관 부재.

## Self-rationalization auto-detection
- 회피표현("미미/관행적/보수적이면 OK/대부분 동일") 사용처 점검: "dREC immaterial"·"수정≈원본"은 **corr 0.991 정량 실측 기반** → 합리화 아님(라벨 근거 有). RE-VIEW 불요.
- placebo·EW-basis·Size-partial·incrementality corr = 3축 정량 근거 모두 확보 → 근거 강화 완료.

## Q-Lead escalate trigger 점검
- HIGH severity ≥5? **NO** (clean negative, 오탐 없음). AX axiom hard FAIL? **NO**. PIT C1(lockbox/lookahead) 위반? **NO** (Factor_Date<=sig_date + expand_hold +1m 보수 + 코호트-단위 FY 추정, 미래참조 없음). → **escalate 불요**.

## 최종
두 팩터 모두 **config-scoped negative + 프론티어 표시**(재시도금지 아님, INV-7). next_probe 각 ≥2 기록(alpha_validation.json). survivor 0 → add_factor 없음. 지식: F-A=AC13 중복 확증(수정 Jones KR 무증분) / F-B=Benford 첫 측정 clean null(대형주=최고감사 세그먼트, 조작분산 낮음 가설). 재료(재무제표 통계기법)는 소진 아님 — exclusion overlay·소형universe·quarterly FSD·composite forensic screen이 미탐 경로.
