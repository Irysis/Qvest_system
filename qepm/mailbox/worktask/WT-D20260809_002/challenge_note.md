# challenge_note — WT-D20260809_002 (tail-targeted regime overlay)

Self-Adversarial Challenge (v8.2, AX-008 3-source 중 1). finalize 직전 자가 적대검증.
분류: ACCEPT(명백한 위반 → spec 수정) / PARTIAL(부분 인정 → 보완) / REBUTTAL(명시 근거로 반박).

---

## C1. "관문이 막았다면서 소비를 측정했다" — PARTIAL ACCEPT

**공격**: P4 에서 G1 자격 관문 BLOCK 을 선언해놓고 P5-4/P5-6/P6-a 에서 라벨 오버레이의 수익·낙폭을
실제로 측정했다. 규율 4("자격 없는 정의로는 소비하지 마십시오")를 스스로 어긴 것 아닌가.

**처리**: 부분 인정. 규율 4의 목적은 *무판별 라벨의 소비 결과를 그 소비면에 대한 증거로 승격하는 것*을
막는 데 있다. 본 라운드는 (i) 모든 사후 수치에 `metric_type=canonical_screen_diag` 를 붙였고
(ii) `preregistration.json::primary.launched=false` 로 book-marginal 판정을 발행하지 않았으며
(iii) 가중 규칙 2종 부호 일치 축을 **미충족으로 그대로 보고**했다.
그럼에도 "관문 통과 후 측정"과 "관문 차단 후 진단"의 경계는 문서로만 서 있고 기계로 강제되지 않는다 —
이 라운드가 negative 였기에 문제가 드러나지 않았을 뿐이다.

**보완 조치**: `alpha_validation.json` 의 해당 절 제목을 `increment_on_incumbent_diagnostic` /
`dual_basis_and_drawdown` 으로 명시하고 `capital_claim=false` · `graduation_claim=false` 를 명문화.
**next_probe 로 이월**: label_eligibility_gate 의 BLOCK 이후 실행 경로에 `diag_only=TRUE` 플래그를
강제하는 배관이 없다(현행 `assert_label_eligible` 는 stop() 뿐이라 진단 경로가 아예 없음 → 우회 유인).

---

## C2. "에피소드 제거 강건성이 오히려 좋아진 것은 기계적 인공물이다" — ACCEPT

**공격**: P8-1 에서 GFC·COVID·아시아위기를 전부 빼자 lift 가 2.671 → 3.218 로 **올랐다**. 신호가
강해진 게 아니라 분모(base rate)가 같이 줄어든 산술 효과 아닌가.

**처리**: 인정. 실측으로 확인 — `all_three` 제거 시 recall 0.1748 → 0.1486 (내려감), base 0.0654 →
0.0462 (더 많이 내려감) ⇒ 비율인 lift 가 오른다. 즉 **"제거하면 개선"은 잘못된 읽기**다.

**정정된 주장**: 올바른 판독은 "어느 단일 에피소드를 빼도 **유의성이 유지된다**"(최악 p=3.0e-04,
아시아위기 제거)이지 "빼면 강해진다"가 아니다. `alpha_package.challenge_flags` 및
`alpha_validation.mechanism_decomposition.episode_robustness` 를 이 표현으로 유지하고,
lift 상승을 신호 강화로 해석하는 문장은 쓰지 않았다.

---

## C3. "패널 regime 컬럼 = look-ahead 라는 주장의 근거가 부족하다" — PARTIAL ACCEPT

**공격**: 배포 패널의 `regime`(BULL/NORMAL/CAUTION/CRISIS)과 `unified_regime_signal` 의
`Category`(RISK_ON/NEUTRAL/CAUTION/CRISIS)는 **라벨 체계가 다르다**. 둘의 멤버십 겹침을 재지 않고
"패널 regime 은 동월 정보를 담는다"고 말한 것은 근거 부족 아닌가.

**처리**: 부분 인정. 실제로 측정한 것은 **한 가지뿐**이다 — 패널 `regime` ON 월의 홀딩월 시장수익이
−5.70%(OFF +1.68%)인 반면 **직전 관측월**은 +4.48%(OFF +0.77%)라는 시간 서명. 하락 신호가 상승 뒤에
켜지는 이 배치는 사전 관측 가능한 신호로는 설명되지 않는다. 두 라벨의 멤버십 대응은 **재지 않았고
주장하지도 않았다**.

**중요한 것은 반대 방향의 확인**: 배포 스케일(`beta_R05 × m4`)의 축소월은 그 서명이 **없다**
(홀딩월 −0.66%pt / 직전월 +0.04%pt). 즉 **incumbent book 이 오염됐다는 주장은 하지 않으며, 오히려
반대 증거를 제시했다**. 서술을 "패널의 regime 컬럼은 서술 주석이며 book 을 구동하는 신호가 아니다"로
한정했다(멤버십 동일성 주장 없음).

---

## C4. "필요 lift 역산(10.8~16.2x)은 근사이므로 결론을 지탱 못한다" — REBUTTAL

**공격**: P6-b/P7-3 의 역산은 발화집합을 "꼬리월(평균 −14.19%) + 나머지(+4%)"의 단순 혼합으로 모형화하고
sd 를 라벨 ON 월 sd 로 고정했다. 실제 조건화는 비꼬리월의 평균도 바꾼다. 근사에 기대 5~6배 부족이라고
단정할 수 있는가.

**반박 근거 3축**:
1. **부호 논증은 근사와 무관하다** — 필요한 것은 `E[ret_orig | 발화] < 0` 이다(노출 축소가 이득이 되려면
   발화월 평균이 음수여야 함). 실측 `E[ret_orig | 라벨ON] = +0.0401/월`. 이것은 근사가 아니라 직접 실측이며,
   근사가 다루는 것은 "얼마나 부족한가"이지 "부족한가"가 아니다.
2. **독립 상한이 같은 방향** — 근사를 전혀 쓰지 않는 오라클 측정이 천장을 직접 준다: 완전 예지로도
   incumbent 위 paired t=+3.18 / ΔIR=+0.125 / ΔMDD=−2.09%pt. 실측 라벨은 t=−1.84.
   근사 없이도 "레버의 상금 자체가 작다"가 성립한다.
3. **깊이 불변성** — paired t 가 깊이 0.25/0.50/0.70 에서 −1.418 로 **동일**(선형 스케일의 수학적 귀결).
   튜닝 여지가 원리적으로 없다는 점이 근사와 독립으로 확인된다.

**문헌 정합**: Brunnermeier-Pedersen(2009)의 funding spiral 은 *분산* 상태를 예측하지 방향을 예측하지 않는다.
선형 노출 레버가 조건부 평균만 수확한다는 것은 정의이지 실증 추정이 아니다.
**L-code 정합**: [[project-regime-label-response-depth-20260808]] 의 "overlay MDD 개선의 83%가 타이밍,
m4 한계기여 −0.00%pt" 와 본 라운드의 "라벨 오버레이 ΔMDD = 0.00%pt"가 독립 경로로 일치.

---

## C5. "E7 vintage 미검증을 '안전한 방향'이라 넘긴 것은 합리화다" — PARTIAL ACCEPT

**공격**: `production_parity_verified=false` 인 저장 패널을 쓰면서 "판정이 negative 라 안전 방향"이라고
쓴 것은 `.claude/rules/pit.md` 가 금지한 합리화 어휘군(방향 논증 없이 위반을 용인하는 표현)의 변형 아닌가.

**자가 합리화 검증**: 문장을 재검사했다. 논증 구조는 "라벨이 in-sample 적합으로 **과대평가**됐을 수 있는데
그 낙관적 라벨로도 레버가 실패했다 ⇒ clean 라벨이면 더 실패한다"이다. 이는 편향의 **부호가 결론과
반대**임을 정량 근거(라벨 최대 가능 낙관 편향은 lift 를 키우는 방향, 레버 실패는 lift 부족이 아니라
`E[ret|ON]` 부호에서 오므로 편향이 커져도 부호가 뒤집히지 않음)와 함께 짚은 것이다.
크기가 작다는 주장이 아니라 **부호가 반대**라는 주장이다.

**단 조건부다**: 이 논증은 **negative 결론에만** 적용된다. 자격 수치(lift 2.671)를 **positive 근거로
승격하는 순간 무효**가 된다. NP-1(monitoring)·NP-2(위험모델)은 라벨의 자격을 positive 로 소비하므로
**vintage 확보가 선행 조건**이다 — `next_probe NP-4` 로 명시 등재했고, `self_pit_check.verdict` 를
`clean` 이 아니라 **`warn_restatement`** 로 낮췄다.

---

## C6. "primary 를 안 돌렸으면 브리핑 요구를 미충족한 것이다" — ACCEPT (미충족을 미충족으로 보고)

**공격**: 브리핑은 (b) primary paired t·ΔIR·부호 일치와 (c) 가중 규칙 2종 결과를 요구했다.
가중 규칙 2종(rank-tilt + EW)은 측정되지 않았다.

**처리**: 인정하고 **충족한 척 하지 않는다**. `preregistration.json::primary.launched=false` +
`weighting_rules_required` 미충족을 명문 기록. 사유는 G1 관문 차단이며, 추가로 구조적 사유가 있다:
본 라운드의 레버는 **종목 선별을 전혀 바꾸지 않고**(alpha_inheritance_cor = 1.0) 집계 노출만 스케일한다.
가중 규칙은 스케일에 대해 곱셈적으로 상쇄되므로 rank-tilt/EW 두 규칙에서 paired t 의 **부호가 갈릴 수
있는 구조 자체가 없다** — 이 축이 판별력을 갖는 경우(FQ-122 실측)는 선별이 바뀌는 라운드다.
⇒ 미측정이되, 미측정이 판정을 바꿀 여지도 없음을 근거와 함께 기록.

---

## C7. "배포창 자격 미달을 이유로 막아놓고 전표본 자격으로 라벨을 옹호하는 것은 이중잣대다" — REBUTTAL

**공격**: 배포창에서 6/6 INELIGIBLE 이면 라벨은 자격이 없다. 그런데 전표본 ELIGIBLE 을 근거로
"라벨은 진짜 꼬리 검출기"라고 결론냈다. 유리한 창을 골랐다.

**반박 근거**:
1. **검정력 실측이 두 창의 지위를 다르게 만든다** — 배포창 `<−10%` 셀의 검출력은 lift 2.7 에서 **0.32**
   (4000 sim). 즉 배포창은 lift 2.7 짜리 진짜 신호를 **3분의 2 확률로 놓치도록 설계된 검정**이다.
   전표본은 n_on 103 으로 p=3.15e-06 을 낸다. 같은 "INELIGIBLE" 라벨이 아니다.
2. **점추정이 서로 정합** — 배포창 2.135 / 전표본 2.671 / post-2004 2.061 / pre-2004 1.809.
   창 간 부호·크기 충돌이 없다. 창-정합 후 대비를 주장했다(08-08 자가정정 규약).
3. **보수적 처분을 실제로 했다** — 자격이 애매한 쪽으로 결론을 기울이지 않았다. 관문은 **차단**으로 처리해
   primary 를 launch 하지 않았고, 라벨 옹호는 소비 승격이 아니라 **next_probe 라우팅**(무비용 경보·
   위험모델 입력)으로만 이어진다. 자본 주장 0건.

---

## C8. 자가 합리화 어휘 스캔

`.claude/rules/pit.md` 금지 표현군 + `answer-principles.md` 회피 표현군(크기 축소형 · 관행 원용형 ·
사전 반영 주장형 · 정도 모호형)을 대상으로 산출물 3종(`alpha_package.json` / `alpha_validation.json` /
본 문서)의 **판정 근거 문장**을 자가 스캔 — 해당 0건.
근사인 곳은 근사라고 명시 라벨(C4 대상)했고, 미측정은 `NOT_TESTED` / `launched=false` 로 명시 라벨했다.
불확실성은 수치로 표기했다(검출력 0.32, 유효 독립단위 19%, `production_parity_verified=false`).

---

## 자동 escalate 판정

| trigger | 실측 | 발동 |
|---|---|---|
| HIGH severity >= 5 | ACCEPT 2 / PARTIAL 3 / REBUTTAL 2 — HIGH 0 (전부 방법 한계·표현 정정) | 아니오 |
| AX axiom hard FAIL >= 3 | 0 (AX-001 조건부 병기 완료, AX-002 우회 없음, AX-000 종결어휘 미사용) | 아니오 |
| PIT C1 (lockbox·lookahead) 위반 | 0 — assert_overlay_pit PASS / lag1 통과 / strict A/B 는 **naive 정렬의 look-ahead 를 검출해 판정에서 배제**(위반이 아니라 검출 성공) | 아니오 |

**Q-Lead escalate 불필요.** 단 아래 2건은 거버넌스 항목으로 보고 대상:
- 브리핑이 인용한 lift 3종이 동월 정렬 산물이었다(수치 교체 필요).
- 브리핑의 "FQ-143" 이 원장에서 무관한 항목(CV_Vol)이다(발번 정정 필요).
