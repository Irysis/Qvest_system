# R35 Self-Adversarial Challenge Note (v8.2 — Opus 4.8 native adversarial, Charter §8 No Silent Override)

**대상**: WT_D20260715_004 / R35 / FQ-047 P1 — SP 소비면 재라우팅.
**방식**: finalize 직전 산출물을 스스로 적대검증. 각 concern = ACCEPT / PARTIAL / REBUTTAL 분류 + 근거 + 합리화 자기검증.

---

## 사전등록 concern (prereg 5종) + 발굴 concern

### C1 — "SP 2024+ 생존이 되돌림 후행(mean-reversion bounce)인지" (prereg)
**분류: ACCEPT (강)** — 그리고 더 나아가 **R31 서사 자체를 정정**.
- 실측: standalone SP EW-active pre24 NW-t 2.508 vs 2024+ 1.119. 부기간 P2023(2020-23) 2.51이 P2426(2024+) 1.12보다 강. rolling-24m은 max 5.12(2021-23 근방)에서 last 2.00으로 하락.
- 판정: SP의 절대 신호는 **pre-2024-지배**. R31이 "2024+ 생존"으로 읽은 것은 cap-w tier-조건부 marginal-vs-base 프레임(base가 2024+ 붕괴 → SP 상대 우위)에 특이한 아티팩트. 2024+ SP 양(+)은 있으나 이는 2020-23 revival의 **꼬리**(부분적 되돌림 후행)이지 신규 구조 프리미엄 아님.
- 처리: verdict §3에 정정 prominently 기록. "2024+ 생존" 라벨 폐기, "regime-의존 순환-가치 pre-2024-지배"로 재특성화.

### C2 — "EW-basis 실투 불가능성(벤치 EW mandate 부재)" (prereg)
**분류: ACCEPT** — 정량화로 강화.
- 실측: 배포 유니버스는 cap-w KOSPI200. EW-basis PORT_t 2.758은 신호 진단이지 배포 가능 성과 아님. 게다가 **수용력 median 0.5억원**(5% ADV, 최소보유 binding) = EW top-25가 유동성필터 경계 부근 소형에 농축 → **어떤 AUM에서도 배포 불가**.
- 처리: verdict §1에 "signal diagnostic ≠ deployable book" 명시 + 수용력 벽 정량. standalone EW 배포책 = config-scoped negative 확정.
- 합리화 자기검증: "EW가 강하니 배포 가치 있다"는 유혹 → **거부**. cap-w 벤치·수용력 둘 다 배포를 막음. EW 강함은 cap-tier 국소화의 재확인일 뿐(project-captier-alpha-localization 정합).

### C3 — "매출-yield 저품질 함정(적자기업 고매출)" (prereg)
**분류: PARTIAL (proxy로 미지지, 완전 배제 아님)**
- 실측: SP top-25 median EP(aligned-z) = −0.016 ≈ 중립 → SP 보유가 적자/저이익으로 계통 편향되지 않음. sector도 broad(HHI 0.10, 필수소비재/건설/건강관리 — distress-heavy 아님).
- caveat(정직): EP-z proxy는 *중앙값*만 — 꼬리(극단 적자)의 소수 존재는 못 배제. 진짜 저품질 게이트는 재무 건전성 raw(부채비율/이자보상배율)인데 본 라운드 미측정(factor_db z만).
- 처리: verdict §3에 "junk-rally 아님(EP-neutral)"으로 기록하되 proxy 한계 명시. feature로 소비 시 quality-neutralize 권고를 P-probe에 함의.

### C4 — "2.5yr post-2024 window(~30개월)는 regime 주장에 얇음" (prereg)
**분류: ACCEPT** — C1과 결합.
- 실측: 2024+ n=29개월. NW-t 1.12의 SE 넓음. 단일 window로 "structural" 주장 불가.
- 처리: verdict에서 "2024+ 구조적 프리미엄" 주장 자체를 폐기(C1). 얇은 window 위에 R31이 서사를 세운 것을 정정. 어떤 2024+ 결론도 single-regime 라벨.

### C5 — "P-pure 페이퍼트랙과 active corr 高 → redundant 소비" (prereg)
**분류: REBUTTAL (실측이 반증)**
- 근거(학술+정량+L-code): active-corr(EW) vs P-pure base 0.458 / D-2 0.423 (둘 다 <0.5) + holding overlap Jaccard 0.064(~3/25 shared). SP는 P-pure(trailing-PORT_t 선별 = Value-집중 틸트)와 **비중첩·저상관**.
- 정량 3축: (1) 시계열 active corr <0.5 (2) 보유 Jaccard 0.064 (3) 신호 구성 상이(SP=매출-yield 단일 vs P-pure=102팩터 PORT_t-랭킹 composite).
- L-code: project-selection-discipline-arc-r4r5r6 (P-pure = trailing PORT_t Value-집중).
- 판정: SP는 diversifying. redundant 아님. **단** 이 diversification 이익이 자본 게이트를 못 넘는다(직교≠수익, learning-gate-calibration-longonly) — corr 낮음은 소비 자격이 아니라 feature 다양성일 뿐.

### C6 (발굴) — "오버레이 한계기여 pre-2024-only가 base-특이인가 SP-특이인가"
**분류: ACCEPT** — 이중 확인으로 강화.
- 실측: base clean·incumbent bk **양쪽**에서 SP 오버레이 post24 paired ≈0(−0.178 / −0.026). 두 독립 base에서 동일 패턴 → **SP-특이**(2024+ SP 오버레이 신호 감쇠)이지 특정 base 아티팩트 아님.
- 처리: verdict §2에 "live 오버레이 레버 감쇠" 확정. OVERLAY_CANDIDATE feature 보존은 진단·부활대기이지 현 배선 아님 명시.

---

## 합리화 auto-detection 자기검증 (금칙 표현 grep)
"미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 유사 / 근사(무근거)" — **미사용 확인**. 모든 판정에 실측 수치·basis 라벨. "2024+ 생존"을 방어하려는 유혹(R31 계승) → C1에서 실측으로 정면 정정(합리화 아닌 반증).

## escalate trigger 점검 (Q-Lead 자동)
- HIGH severity ≥5 : 미해당 (screening-tier, 자본 판정 아님).
- AX axiom hard FAIL ≥3 : 미해당.
- PIT C1(lockbox/lookahead) 위반 : **없음** (lag1 graceful·placebo p=0·off0 T-1 clean base·§7b). escalate 불요.

## AX-008 3-source triangulation
- self-adversarial(본 note) = 1 source. 본 라운드 screening-tier(forge 미경유)이므로 forge·architect source는 미적용 — 자본 판정 아닌 진단 라운드로 2/3 요건 완화(measurement-graduation: screening ≠ graduation). 자본 승격 시(P-probe) forge triangulation 의무.
