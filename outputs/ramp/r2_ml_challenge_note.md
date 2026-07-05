# RAMP R2 Track B — Self-Adversarial Challenge Note (v8.2)

**Task**: DIST-RAMP-006 미검증 프론티어 — 11 orthogonal 경제 sleeve + regime soft-membership 을
lightgbm 으로 비선형·국면조건부 결합 시 선형 select-stack(2.54)을 넘어 cap-w PORT_t≥2.95 달성하나?
**측정 결과**: cap-w PORT_t=1.418, oos_retention=-0.481, calmar=0.433, post2017 SR=+0.092. 게이트 3종 전부 FAIL.
**Verdict**: 동일 벽. 비선형·국면조건부도 선형을 못 넘음(window-matched tie).

---

## 자기 비평 (devil's advocate) — ≥3건

### C1. "R1 linear best 2.54 대비 ML 1.42 는 부당 비교 (윈도우 불일치)" — **ACCEPT (교정 반영)**
- R1 linear stack_EW 2.538 은 2005-2010 포함 전기간(256m). ML은 5yr expanding train 필요 → 2010-02+ 195m만 예측.
- **처리**: 동일 2010-02+ 윈도우로 linear 재측정 → **1.473**. ML 1.418 과 **tie(Δ=-0.055)**.
- 결론 불변: 헤드라인 비교(1.42 vs 2.54)는 오해소지 → window-matched(1.42 vs 1.47)가 authoritative. **비선형 개선 없음**은 오히려 더 명확.

### C2. "regime 피처가 full-sample MSM fit 이면 C1 look-ahead" — **REBUTTAL (근거)**
- 근거(코드 실증): ar_z = `run_ramp_ar_regime.R` L44 `p<-ar_val[1:i]` expanding z-score. cpz = `ramp_wire_canonical.R` L31 `p<-A$cp[1:i]` expanding. Absorption Ratio 자체 = Kritzman 63d 롤링(trailing).
- 두 regime 축 모두 expanding-only. 게다가 R2 model에서 **t-1 shift(1)** 추가 적용 → 동월 노출 없음.
- 잔여 caveat: msm `cp` NA-impute=full-sample mean이나 초기행만·lag1 후 무영향(cosmetic). AX-002 위반 아님.
- **정량 검증**: lag1 스트레스에서 base(1.42)가 window-matched linear(1.47)와 정합 → base가 누출로 부풀지 않음 확인.

### C3. "lgbm feature importance가 regime에 지배됨 = regime-timing(β)이지 종목선택 아님" — **PARTIAL (인정 + 완화)**
- importance 상위 4개가 regime(월-상수) 피처. 하지만 **월-상수 피처는 cross-sectional rank(top-25 선택)를 바꿀 수 없음** — 종목 차별화는 11 sleeve의 tree interaction에서만 발생.
- 즉 regime 피처의 역할 = sleeve 신호를 국면조건부로 게이팅(intended design). β-timing 아님(스코어는 종목 rank용, cash overlay 없음).
- 인정: 그럼에도 종목-선택 edge가 얇음 → net_sr 0.395, 선형과 tie. 국면 조건화가 신호를 강화 못함.

### C4. "ML lag1 급락(Δ-1.50)이 linear(Δ-0.54)보다 큼 = 누출" — **PARTIAL (누출 아님, 과적합 징후 인정)**
- 하드 누출이면 base가 clean re-measure 대비 부풀어야 함. window-matched linear가 1.47로 ML base 1.42를 검증 → base 정상.
- lag1 급락 차이 = ML 신호가 linear보다 월-특이적/저지속(annual retrain + 국면 transient 포착). **과적합 방향 징후**이나 자본 판정엔 무관(이미 게이트 FAIL).
- oos_retention -0.48(음)이 이를 독립 확증: OOS에서 IS 대비 신호 붕괴.

### C5. "post2017 SR=+0.092(양수)는 ML이 decay를 견딤 = 성공" — **REBUTTAL (수준 미달)**
- 인정: linear의 post2017 SR -0.257 대비 ML +0.092 는 decay 완화. rank-IC도 post2017 0.0295≈full 0.030(비감쇠).
- 그러나 +0.092 SR 은 자본급 아님(연 SR 0.09). full-period NW-t가 오히려 붕괴(1.42<linear 1.47 window-matched) — 초기 edge를 국면-heavy 모델이 희석.
- **NW-t 유의성**: 1.42 << 2.0. decay 완화는 통계적으로 미미(비유의). "견딘다"는 방향이지 자본 근거 아님.

---

## 분류 요약

| Concern | 분류 | 처리 |
|---|---|---|
| C1 윈도우 불일치 | ACCEPT | window-matched 재측정(1.47), 결론 강화 |
| C2 regime full-sample 누출 | REBUTTAL | expanding 코드 실증 + t-1 lag + base-검증 |
| C3 regime 지배=β-timing | PARTIAL | 월-상수는 rank 불변, intended gating, but edge 얇음 |
| C4 lag1 급락=누출 | PARTIAL | 누출 아님(base 검증), 과적합 징후 인정 |
| C5 post2017 양수=성공 | REBUTTAL | 방향은 맞으나 수준·유의성 미달(비자본) |

## Self-rationalization auto-check
- "미미/관행/보수적이면 OK" 사용 없음. post2017 +0.092 를 "decay 견딤"으로 과대포장하지 않고 NW-t 1.42<2.0·oos -0.48 로 반증.
- 정직 보고: 게이트 3종 FAIL, window-matched tie, 자본 부적격 — 그대로 확정.

## Q-Lead escalate trigger 점검
- HIGH severity ≥5? NO. AX axiom hard FAIL ≥3? NO. PIT C1(lockbox/lookahead) 위반? NO(expanding+lag1 검증).
- → escalate 불요. 정상 음성 결과로 종결.

## AX-008 Verification Triangulation
- self-adversarial(본 note) + Forge(canonical_screen_bt 실측 게이트) 2-source PASS(2/3 충족). Architect 미필요(음성 결과, 인프라 이슈 없음).
