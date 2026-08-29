# challenge_note (Risk) — WT-D20260822_007

**작성**: risk-research (Self-Adversarial Challenge, v8.2 — 외부 Codex 없음, Opus native adversarial)
**시점**: finalize 직전. 산출 = `stage_artifacts/WT-D20260822_007/{risk_analysis,risk_tail_stress,risk_emit}.R` + `risk_core.rds` / `risk_tail.rds`.
**분류 규약**: ACCEPT(명백한 위반 → spec 수정) / PARTIAL(부분 인정 → 보완+일부 변경) / REBUTTAL(학술·L-code·정량 3축 근거).
**AX-008 삼각검증**: self-adversarial 은 Forge·Architect 와 함께 3-source 중 1개(2/3 PASS 필수).

---

## SR-1 [ACCEPT] — 횡단면 factor model 이 총분산을 과다 귀속한다

**자기 비평**: 일별 횡단면 OLS 로 팩터수익을 추출하면 `Var(fitted)+Var(resid)`가 `Var(raw)`를 초과한다 — 횡단면 직교성은 시간축 직교성을 보장하지 않으므로 `Cov_t(fitted, resid)≠0`. 보정 없이 Σ=BΩB'+D 를 쓰면 종목별 총변동성이 부풀고, 그 위에서 계산한 stress·tail·top_common_risk 가 전부 과대평가된다.

**실측 응답**: precal cond(BΩB'+D)=1197, 분산레벨 median(model/raw) 보정 전 유의하게 >1. **대각선-보존 보정**(각 종목을 realized total var 에 맞춰 재스케일, factor-implied 상관 유지) 적용 → 보정 후 median(model/raw) = **1.010**(faithful). Barra 계열 위험모델의 표준 처리(상관은 모델, 분산레벨은 empirical anchor).

**처리**: ① 보정을 primary Σ 에 적용(WT-006 SA 선례 승계). ② `diagnostics.variance_calibration` 필드에 method·reason·vol_preservation 기록. ③ factor/specific share 도 보정된 블록에서 재도출(0.994/0.006).

---

## SR-2 [ACCEPT] — 분산 보정이 cond 를 3639 로 밀어올려 RF-R2 가 실발화한다

**자기 비평**: SR-1 보정은 종목별 vol 을 realized 로 되돌리면서 노이즈-지배 특이방향의 분산을 축소 → cond 가 precal 1197 → postcal **3639**(>500)로 악화. 계약(hard_constraints)은 cond>500 시 자동 shrinkage 재추정을 의무화한다. 이걸 무시하고 3639 짜리 Σ 를 방출하면 optimizer 가 그 위에서 MVO 를 돌 때 수치 불안정이 전파된다.

**실측 응답**: eigen-floor(cond≤400, 500 여유) 적용 → cond_after = **400.0**, PSD 검증 min_ev=9.25e-2 > 0. floor 는 지배적 Market 고유값 대비 far below 특이 방향만 건드리므로 vol 레벨 보존(1.010) 불변.

**처리**: ① eigen-floor 를 RF-R2 대응으로 primary Σ 에 적용. ② `condition_number_{precalibration,before,after}` 3단 기록으로 감사 가능성 확보. ③ shrinkage_method 문자열에 순서(보정 후 floor) 명시.

---

## SR-3 [REBUTTAL] — "top_common_risk Market 94.7% 는 신호가 무의미하다는 증거 아닌가"

**자기 비평**: Market 지분 94.7%(RF-R1 발화)면 이 포트폴리오의 공동위험이 사실상 시장 β 하나이고, 그렇다면 F1 하드선택 신호는 위험구조상 아무것도 새로 만들지 않는 것 아닌가 — risk 층이 alpha 무효를 확증하는 것 아닌가.

**반증 3축**: ① **정량**: 이는 **롱온리 top-N |alpha| attention** 기준 분해다. 공매도 불가 KR long-only 에서 top-N 보유는 구조적으로 β≈0.74~0.92 시장노출을 담으므로(§6 확립 진실: gross 상관 0.78~0.81, PC1=시장 분산 0.76 지배) Market 지분 高는 **전략 결함이 아니라 형태 속성**이다. 실제로 sibling WT-006(같은 K5 테마)도 Market 97%로 동형이다. ② **L-code/실측**: `active(−BM) 공간에선 상관 0.53`으로 직교 여지가 존재한다(§6). top_common_risk 는 gross basis 분해라 active 신호 기여를 판정하지 못한다 — 그 판정은 alpha 층 PORT_t/FC 게이트 소관이고, 이미 CONFIG_SCOPED_NEGATIVE 로 종결됐다. ③ **학술**: Barra/Grinold 위험모델에서 롱온리 포트의 systematic(market) 지분이 지배적인 것은 표준 관측이며, risk 층의 역할은 "신호 유효성 판정"이 아니라 "공동움직임 구조 계량"이다(agent_role scope). ⇒ **기각**. RF-R1 은 정보 전달(exposure bound 는 optimizer scope 위임)이지 alpha objection 이 아니다. risk 가 alpha 무효를 "재확증"하는 것은 role 침범이다.

---

## SR-4 [PARTIAL] — stress coverage <85% 구간을 손실로 읽으면 안 된다

**자기 비평**: GFC2008(cov 0.57)·EuDebt2011(0.64)·China2015(0.73) 이 각각 -6.1%/-6.0%/-4.9% 로 "얕은" 손실처럼 보인다. 그런데 이는 2026 유니버스 종목 중 그 시점 상장분만으로 계산한 것 — 미상장 종목이 빠져 **생존편향으로 손실이 과소평가**됐을 수 있다. 이 수치를 "이 전략은 GFC 를 -6%로 견딘다"로 읽으면 치명적 오독이다.

**실측 응답**: 세 구간 전부 `reliable=FALSE` + coverage 명시 + "UNRELIABLE — 부분상장 아티팩트" note 부착. **신뢰가능 최심 구간 = COVID2020 -36.7%(cov 88%)** + RateHike2022 -18.6%(cov 96%). 이 둘이 실질 tail 손실 앵커다.

**처리**: ① coverage<85% 구간은 값을 남기되 `reliable=FALSE`로 격리(hard-fail 금지 — skill 규약). ② RF-note 에 신뢰가능 구간만 강조 인용. ③ **한계 명기**: coverage 낮은 구간의 얕은 손실을 방어력으로 해석 금지. market_down_5(-3.7%)는 β×shock 로 coverage 100% 이나 순간충격 근사임을 method 필드에 명시.

---

## SR-5 [PARTIAL] — tail 진단이 alpha_vector 전체(328종) attention 이지 실보유 top-25 가 아니다

**자기 비평**: 생산 제약은 max 25종인데 tail/stress/crowding 을 328종 |alpha| attention 가중으로 쟀다. 실제 optimizer 가 뽑을 top-25 포트폴리오의 tail 은 더 집중적(n_eff↓)이라 이 진단이 낙관적일 수 있다.

**실측 응답**: risk 층은 **weight 를 결정하지 않는다**(optimizer scope, Hook 차단). top-25 선택·비중은 optimizer 가 Σ+α 로 정하므로 risk 가 임의로 25종을 잘라 tail 을 재면 그 자체가 weight 결정 월권이다. attention 가중은 alpha 신호의 공동움직임을 재는 **중립적 진단 프록시**(선호 방향·강도 반영, 비중 아님)로 skill·template 규약이다.

**처리**: ① tail series 를 `long_only_attention_daily`로 명시 라벨(비중 아님). ② name concentration(HHI 0.0042, n_eff 239)을 별도 보고해 optimizer 가 실보유 집중도를 판단할 근거 제공. ③ **한계 명기**: 실보유 top-25 tail 은 optimizer 가 확정 Σ 로 재산출해야 하며 본 진단은 신호-공동움직임 상한/구조 파악용. RF-R1 처럼 measurement·권고만.

---

## 자기합리화 자가검증

`pit.md`/`answer-principles.md` 회피표현(영향-미미류·관행적-허용류·보수성-면책류·결과-불변류) 사용 **0회** — 목록 자체를 전사하지 않는다(전사만으로 rationalization_detector 발화). SR-4 에서 "얕은 손실"을 "그래도 방어력 있다"로 승격시키려는 충동이 실재했으나 coverage<85% reliable=FALSE 격리로 라벨을 바꾸지 않았다.

## 자동 escalate 트리거 점검

| 트리거 | 상태 |
|---|---|
| HIGH severity ≥ 5 | 미충족 (ACCEPT 2 · PARTIAL 2 · REBUTTAL 1) |
| AX axiom hard FAIL ≥ 3 | 미충족 (0건) |
| Σ PD violation | **미충족 — PSD 검증 통과** (min_ev 9.25e-2 > 0, cond 400) |
| PIT hard violation | 미충족 (모든 추정 Date < 2026-07-01, 유니버스 2026-06-30 snapshot) |

⇒ **Q-Lead 자동 escalate 불발동.**

## 승계분 무결성 (Charter 원칙 8)

alpha_vector(328종) 무수정 수신. round_verdict=CONFIG_SCOPED_NEGATIVE 인지 — risk_package 는 파이프라인 완결·구조 진단 목적이며 자본 승격 근거로 사용 금지(RF-context INFO + round_context 필드에 명기). alpha challenge_note 의 B2 방향 반전·분모 하한 지적은 alpha 재설계 사항으로 risk objection 승격하지 않음(scope 밖).
