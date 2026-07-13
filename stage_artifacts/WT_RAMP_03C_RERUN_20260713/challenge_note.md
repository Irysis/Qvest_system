# Self-Adversarial Challenge — RAMP_03C 재실행 (FQ-020)

**규약**: v8.2 Self-Adversarial (Opus 4.8 native). finalize 직전 약점 ≥3 자가제기 → ACCEPT/PARTIAL/REBUTTAL. 자기합리화 detect.
**필수 3표면**: ① 원 config 복원 충실도 ② 경계값 통과=벤치버그 아티팩트 격리 ③ 2017+ decay 노출.

---

## W1 [표면①] 원 config 복원이 틀려서 전략을 *과소평가*했을 수 있다
`_wgt.R`(실제 cap-w 스크립트)이 소실 — mom6 집계·0.5/0.5 가중·cap-weight 정의를 L-code 산문에서 역추론했다. 다른 `_wgt.R`이면 결과가 달라질 수 있다.
- **검증**: (a) cap-w PORT_t가 **원 2.98과 정확히 일치**(proxy full) — construction이 원과 다른 방향이었다면 이런 우연 일치는 어렵다. (b) mom6 재-z 대안(ALT) = 3.03/0.41/0.43 → **동일 판정**(oos·calmar 여전히 붕괴). (c) 3가중(EW/score/cap-w) 모두 산출 → 원 g-비교 pattern의 절대수치가 아닌 *구조*를 교차확인.
- **판정: PARTIAL.** 집계·가중 해석 모호성은 **판정 불변**으로 bracket됨(ALT robust). 단 **164mo 정확 월-집합은 미복원**(모호점 #2, book 2.64 재현 실패로 확정) — 이 잔여 불확실성은 ACCEPT하되, full·t164 양창 모두 FAIL이라 결론 불변.

## W2 [표면②] PORT_t 2.98 "재현"은 벤치버그·창이 다른 우연 — 통제된 복제 아님
원은 (버그기 벤치, 164mo)서 2.98, 나는 (교정 proxy, **full 255mo**)서 2.98. **다른 조건서 같은 수 = 우연**일 수 있고, 이를 "충실 재현"으로 포장하면 자기합리화다.
- **자가 인정**: 맞다. proxy-full 2.98은 **동일 조건 복제가 아니다**(창 다름). 동일 조건 근접(proxy t164)은 **2.69**. 그래서 verdict에서 "우연 정확 일치"로 명시하고 판정 근거로 삼지 않았다.
- **경계값=벤치버그 아티팩트 격리**: proxy 2.98 vs **교정 IKS200 2.65** = 같은 포트·같은 창인데 **벤치 basis만 바꿔 +0.03 통과가 −0.33 미달로 반전**. 즉 원 "+0.03 통과"는 **벤치 basis에 취약한 경계 아티팩트**임을 격리 실증. ⚠ 단 원 RAMP는 IKS를 안 썼으므로(rawdata proxy) "IKS001 벤치버그"는 RAMP에 직접 적용 안 됨 — 원의 실제 basis(proxy)로도 oos·calmar가 FAIL이라 벤치버그 여부와 무관하게 졸업 불가.
- **판정: REBUTTAL(자기합리화 아님).** 2.98을 통과 근거로 쓰지 않았고, 오히려 벤치-취약성·창-불일치를 판정에 불리하게 반영.

## W3 [표면③] oos_retention 붕괴(1.19→0.38)가 창을 full로 바꾼 탓 아닌가 (2017+ decay confound)
원 oos 1.19는 최근 164mo서 나온 값. 내가 full 255mo(2008 포함)로 바꿔서 oos가 낮아진 것일 수 있다.
- **검증**: **t164(최근창)도 oos 0.36**(proxy)/0.22(iks) — 1.19과 여전히 격차 절대적. 창을 원과 맞춰도 1.19 재현 안 됨. → **1.19는 창 탓이 아니라 벤치버그기 산물.**
- **decay 실증**: pre-2017 PORT_t 2.96 → post-2017 **1.11**(proxy), 2.84→**0.76**(iks). actSR 0.92→0.37. **cohort-wide 2017+ 감쇠가 oos 붕괴의 직접 기전**(decay-pattern, overfit 아님). oos_retention = OOS(=최근=post-2017=약함)/IS 비율이므로 필연적으로 낮음.
- **판정: ACCEPT(decay 노출 실재) + REBUTTAL(창 confound 아님).** 원 1.19는 재현 불가 아티팩트로 확정.

## W4 [자기합리화 detect] pre-registered "FAIL 예상"에 맞추려 측정을 fail로 구성했나 (confirmation bias)
- **반례 자가제출**: (a) PORT_t 2.98을 **숨기지 않고** 정확 일치로 보고(pass 신호 인정). (b) EW/score-tilt PORT_t **4.25/4.26**(강한 통과)를 보고 — fail만 골라내지 않음. (c) calmar은 **벤치독립**(own NAV)이라 벤치 선택으로 조작 불가한데도 0.42로 미달. (d) 판정 붕괴의 주역 oos·calmar는 3가중·2벤치 전반 **내부 일관**(0.22~0.60).
- **판정: REBUTTAL.** 측정은 even-handed. FAIL은 예상 부합이나 **예상 때문이 아니라 실측 때문**.

## W5 [수치 견고성] oos v2가 IS-SR>0.05 필터·소수 split로 노이즈일 수 있다
- **검증**: pre/post 분해(actSR 0.92→0.37)가 3-split oos와 독립적으로 감쇠를 확증. essence_score 계약 경로(자체합성 0). splits 안정.
- **판정: REBUTTAL.**

---

## 종합
- **필수 3표면 전부 커버**: ①PARTIAL(집계 robust·164mo 잔여 불확실 ACCEPT, 판정 불변) ②REBUTTAL(벤치-취약성 격리 실증, 2.98 미근거화) ③ACCEPT+REBUTTAL(decay 실재·창 confound 아님).
- **자기합리화 detect 결과 = clean**(W4): pass 신호(2.98, EW 4.25) 은폐 없음, 벤치독립 calmar도 미달.
- **최종 판정 유지: DEMOTED(재현 실패).** 잔여 미해결 = 원 164mo 정확 월-집합(소실, 복원 불가) — 단 full·t164·2벤치 모두 FAIL이라 결론에 영향 없음.
