# 딥리서치 결과 심층 리뷰 — PG2 강화 (2026-07-02)

**대상**: deep-research 워크플로우 wf_6d49769d-0b1 (2회 실행: 초회 Verify 전멸 → 한도리셋 후 resume 완주). synthesis JSON: `stage_artifacts/paper_recharge/deepresearch_pg2_synthesis_20260702.json`
**목적**: 결과를 단순 전달이 아니라 *비판적으로 검토* — 근거 품질·내부정합·PG2 함의·함정.

---

## 1. 리서치 자체의 품질 평가 (메타)

| 축 | 평가 |
|---|---|
| 검증 무결성 | 14-vote 세트 중 **confirmed 15건 전부 3-0 만장**(초회 run) → synthesis 6 findings로 병합. **refuted 0**. verbatim 원문 대조(primary PDF). = 확정분은 견고. |
| 검증 공백 | **unverified 7건** (vol-managed 계열) — 초회는 지출한도, resume는 서버 rate-limit로 3-vote 전멸. 그중 **가장 PG2-결정적인 "vol-managed MARKET 포트 비용후 생존" 코롤러리가 미검증**(β≈0.99 북에 가장 유리한 근거인데 확인 못 함). |
| 소스 등급 | JFE·FAJ 톱저널, Harvey팀. 높음. 단 전부 US/선진 20개국(**KR 부재**), 대부분 long-short 지수타이밍. |

**메타 결론**: 확정 findings는 신뢰 가능하나, **"vol overlay가 시장레벨에선 살아남는다"는 우리 북에 가장 우호적인 명제는 검증 실패로 미확정** — 이걸 근거로 쓰면 안 됨(caveat 준수).

---

## 2. 두 개의 상반 신호 (핵심 구조)

### (A) 긍정: turning-point 4-state 레짐 오버레이 = W1 최고-EV 레버 (high conf)
- 4-state(Bull/Correction/Bear/Rebound = 12M·1~2M 부호조합), Bear만 음의 기대수익이고 단일신호로 탐지 불가. dynamic ex-ante speed-blend가 post-GFC 추세손실 회복(3.4% vs 0.3%), OOS 92% 효율.
- **PG2 함의(비판적)**: 헤드라인은 매력적이나 **KR 이전성이 4중으로 약함** — ① KR 최근접 아시아 2국(日·香港)이 dynamic 실패 5개국 ② KR 표본 부재 ③ 지수타이밍≠종목선택 ④ dynamic alpha 유의성 5% 단측·gross. **결정적: 우리 R3가 이미 KR 클린 실측에서 BBT 4-state를 죽였다.** → "최고-EV"는 글로벌 얘기, KR에선 **저-prior**.

### (B) 부정: vol-managed overlay 계열 = 강한 부정 prior (high conf)
- vol-managed는 unmanaged를 체계적으로 못 이김(53/103, 유의 8건뿐). 실시간 combination은 72/103서 열위. **기전 = 구조적 파라미터 불안정**(Bai-Perron: no-break 0건, 41/103이 3+ breaks, 평균 2.37 vs 표준 1.44).
- **PG2 함의(비판적)**: 이게 **우리 Layer4(faith=vol 기반 스칼라 오버레이) 제거를 외부 독립 근거로 정확히 뒷받침**. 특히 구조불안정 기전이 우리 clean-round 붕괴(faith 2.116→1.787)를 설명한다. 리서치의 설계 시사 = **연속추정 스칼라-vol scaler보다 이산 관측가능-상태 스위치(turning-point)가 우월** — 왜 faith가 실패했는지의 근본 이유 제공.

---

## 3. 내부 정합성 — 리서치의 자기모순 아닌 긴장
리서치는 스스로 **INTERNAL OVERRIDE**를 findings #3에 넣었다: "논문-클린 메커니즘도 PG2 클린 패널 + lag-stress 게이트를 통과해야 하며, R3에서 BBT/semivol 전 변형이 +1M lag에서 0.35-0.4 SR 붕괴했다"(우리 노트를 인용). 즉 **리서치가 자기 top 추천(state-switch)에 자기 반증(R3)을 스스로 부착**했다. 정직한 구조.

**단 내가 잡은 리서치의 미세 공백**: R3에서 죽인 G1_bbt_pure는 **정적 4-state β맵**(Bull1.0/Corr0.7/Bear0.4/Rebound1.0)이지, 논문의 **dynamic ex-ante speed-blend(a_Co/a_Re 추정)**가 아니다. 즉 우리는 논문 메커니즘의 *단순화판*을 falsify했다. 리서치 open Q#1이 정확히 이걸 물음("R3 붕괴가 순수 panel-align 버그였나, 메커니즘이 KR에 정말 없나"). → **완전한 falsification 아님**, 그러나 재도전 prior는 낮음(아래).

---

## 4. 제거 결정과의 관계 (이번 결정에 대한 리서치의 판정)
**리서치는 Layer4 제거를 강화한다**:
- vol-managed 부정 prior + 구조불안정 기전 = faith(scalar-vol overlay) 제거의 독립 외부근거.
- 단 caveat: DeMiguel et al(JF 2024) JOINT multifactor vol-timing은 OOS 생존 → "vol timing is dead"는 과대. 부정은 **per-portfolio/single-factor overlay 한정**. faith는 정확히 그 범주(단일 스칼라) → 제거 타당.
- 미확정 리스크: vol-managed MARKET 생존 코롤러리(β≈0.99 북에 유리)가 검증 실패 → **"시장레벨이라 faith가 살 수도 있다"는 반론은 근거 없음(미검증)이라 제거를 막지 못함**. 오히려 우리 실측(clean faith 1.787<1.897)이 우선.

---

## 5. 리서치 open questions에 대한 내 답 (4건)
1. **turning-point가 PG2 클린패널+lag-stress 통과하나?** — 미검증(정적판만 R3서 사망). 재도전은 dynamic 메커니즘 충실 구현 필요하나 **W2/W3보다 후순위**(KR 이전성 4중 약점).
2. **정적 4-state vs dynamic — KR엔?** — 리서치 근거상 dynamic이 日·香港서 실패 → **KR은 정적 스위치가 안전**(만약 재도전 시). 단 정적도 R3서 mid-pack.
3. **vol-managed MARKET 생존이 β≈0.99 북에 이전되나?** — **미검증(3/3 error)**. 재검증 전 가중 금지. 우리 실측이 이미 faith<no_faith라 실무 무의미.
4. **W1 vs W2/W3/W4 EV 비교** — 리서치+내부 종합: **W1(turning-point) 저-prior(KR 이전 약점+R3 사망), W2(earnings@3M) 실측 유의개선 확보(P1 PORT_t 2.20), W3(insider) 미탐색 신규정보원.** → **EV 순위 W2 ≈ W3 > W1**. W1은 제거로 종결, 재도전은 dynamic 충실판 clean 실측 시에만.

---

## 6. 실무 take-aways (액션)
1. **제거 결정 강화됨** — 리서치가 독립 근거 제공(vol-managed 부정 + 구조불안정 기전). 진행.
2. **W1 오버레이 신규 사냥 = 저-prior로 격하** — turning-point조차 KR 저이전. 오버레이 각도는 "R05×m4 게이트 정밀화(soft-prob, 미완)"로만 좁힘. 신규 스칼라-vol 오버레이 금지(부정 prior 확립).
3. **다음 EV = W2(earnings book-marginal) + W3(DART insider)** — 리서치가 명시적으로 W1보다 우위로 지목.
4. **검증 공백 2건 재검증 큐**(비-blocking): vol-managed MARKET 생존 + analyst-revision drift(W2 근거) — 한도 여유 시 deep-research 재-resume.

## 참조
- synthesis: `stage_artifacts/paper_recharge/deepresearch_pg2_synthesis_20260702.json`
- 로드맵: `04_Research/pg2_reinforcement_roadmap_20260702.md`
- 제거 결정: `qepm/mailbox/worktask/WT-D20260702_002/layer4_removal_decision.json`
