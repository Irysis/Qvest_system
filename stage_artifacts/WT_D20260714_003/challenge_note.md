# R27 Self-Adversarial Challenge (v8.2 — Charter §8 No Silent Override)

finalize 직전 alpha_package를 스스로 적대 검증 (Opus 4.8 native adversarial). AX-008 3-source 중 1 (Forge/Architect 미가동 — screening 단계, dossier에서 triangulation 완성).

**대전제**: 본 라운드는 R26 부정판정을 **REVERSE하는 positive** — positive는 negative보다 높은 입증부담. 아래 각 concern은 "이 positive를 어떻게 깰 수 있나"로 공격.

---

## Concern 1 [HIGH] — ym-merge 정정 = p-hacking 또는 look-ahead 도입 아닌가? (사전등록 이탈)
**공격**: 사전등록은 R26 SCdt(exact-Date) 재사용을 함의했다. 실행 중 value 병합을 ym-정렬로 바꿔 paired 1.87→2.68로 통과시킨 것은 결과를 본 뒤의 배관 변경(사후 선택) 아닌가? 달력 월말(04-30) value를 거래일 월말(04-29) 포트에 쓰면 1일 미래참조 아닌가?

**분류: REBUTTAL** (근거 3축 충족)
- **학술/규약**: 월말-signal 정렬은 표준 PIT 규약. 달력 월말 label의 value z는 04-30이 비거래일(그래서 04-29가 last-trading-day)이라 04-29 종가 + 45d-lag 재무만 사용 — 미래 데이터 없음. gap 분포 실측: 163월 gap=0(달력=거래일 일치), 92월 gap −1~−4(전부 비거래일). 
- **L-code 선례**: R26 Extension B recon이 **이미 ymL 병합**을 썼고 채택됨 — ym-정렬은 본 파이프라인의 확립 규약. exact-Date가 오히려 비표준(우연한 R26 scriptC 실수).
- **정량 3축**: ① bug 재현 — exact-Date V14 w0.30 = 1.868 (R26 1.87 정확 재현) → R26 저평가가 병합 결함임을 결정적 입증. ② **lag-stress** — value를 1개월 과거로 shift(달력/거래일 논쟁과 무관하게 명백 PIT-safe)해도 paired **2.982** ≥ 2.0. 즉 판정은 병합 해석에 **불변**. ③ placebo p=0.000. 
- **결론**: 정정은 결과-지향 선택이 아니라 documented 배관 결함 수정. 양쪽(exact/ym) 투명 병기 + lag1 보험. self-rationalization 아님(수치·재현·robustness로 방어).

## Concern 2 [MEDIUM] — holdout 4.30 = 2024-26 KR value 반등 편승 아닌가?
**공격**: holdout 창(2024-07~2026-03)은 KR 가치주 반등기. HO paired 4.30은 국면 편승이지 persistent 신호 아닐 수 있다.

**분류: PARTIAL ACCEPT**
- 인정: HO 4.30은 favorable-regime 팽창 有 — headline로 인용 금지.
- 반박: **IS paired 3.171**(2005-2024, 반등 제외)이 이미 게이트 통과. **post2017 marginal t 4.08**(EW-uni post2017 5.61) — book-marginal value 기여가 2017+ 전반에 강함(2024-26만 아님). → 신호는 반등-only 아닌 persistent. 보고는 IS+post2017을 persistent 근거로, HO는 붕괴-부재(과적합 검거 통과) 확인용으로만 사용.

## Concern 3 [MEDIUM] — slot-carve 기회비용: value 슬롯이 더 나은 Core/Defense를 밀어내는가? (사전등록 #1)
**공격**: slot-carve N_val=8은 score_eff rank 18-25 종목을 value로 강제 교체. 밀려난 종목이 더 좋으면 순 손해.

**분류: ACCEPT (기전으로 해소)**
- 실측: N_val=8(S2/S4) added value fwd이 bumped 대비 edge −0.006~−0.017/yr(raw return 열위). 그럼에도 paired 통과(2.36-2.59)는 **diversification(cor_active 0.82)** 기여 — raw return 아닌 risk-adjusted(dIR). 
- 결정적: **z-blend(3.81) > slot-carve(2.59)** = 연속 tilt가 강제 displacement보다 우위. 따라서 채택안은 z-blend(Z6)로 기회비용 이슈 자체를 회피. Q-Lead sleeve 가설은 이 기전으로 FALSIFIED.

## Concern 4 [MEDIUM] — N_val/w grid = 추가 자유도(sweep overfit)? (사전등록 #3)
**공격**: 10 arm 열거 후 best 선택 = sweep. Z6이 우연히 이긴 것 아닌가?

**분류: REBUTTAL**
- IS-only argmax 선택(Z6, IS 3.171) + holdout 1회. DSR sweep n_trials_cum=30 기록(DSR=1.0, base SR 높아 통과 — binding은 paired).
- **pervasiveness**: 10 arm 중 **7개**가 paired≥2.0(z-blend 5/6 + slot-carve 2/4, 양 형태·양 def·다양 w). 단일 config 요행이 아니라 value 축 전반의 효과 → overfit-to-one 반대 증거. lag1/placebo가 신호 실재 재확인.

## Concern 5 [MEDIUM] — KR value 전수감쇠 prior와 모순 아닌가?
**공격**: reference-kr-value-factor-decay = KR value 24/24 post-2015 감쇠. 어떻게 value가 통과하나? 감쇠 무시한 것 아닌가?

**분류: REBUTTAL (기전 구분)**
- prior는 **standalone value factor return** 감쇠. 본건은 **book-marginal orthogonal value tilt**(book이 순수 value 노출 0). standalone 감쇠 ≠ marginal 기여 감쇠(book에 value 축 부재 시). 
- 정량: **post2017 marginal t 4.08** — 감쇠기(2017+)에도 book-marginal value 기여 강건. DIST-QPM-006(V02 standalone 실패)도 standalone 명시 — 본건 구성 상이.

---

## Self-rationalization auto-check
"미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" 사용 여부 스캔 → **미사용**. 모든 concern은 정량(paired/lag/placebo/재현) 또는 명시 라벨로 처리. Concern 2/3은 부분 인정(ACCEPT/PARTIAL) — 무비판 방어 아님.

## Escalation triggers
HIGH severity 1건(Concern 1, REBUTTAL 충족) < 5 · AX hard FAIL 0 · PIT C1 위반 0(lag1 robust) → **자동 escalate 미해당**. 단 **positive가 prior verdict를 reverse**하므로 도훈 결정 재료로 prominent 보고 + QEPM dossier 승격 권고(forge-authoritative 확정 필수 — screening≠graduation).

## 결론
book-marginal SCREENING PASS는 3중 검증(bug재현·lag-robust·placebo)으로 견고. 단 **자본 판정 아님** — forge build_bt_result HARD 3종(PORT_t 2.95·oos 0.7·calmar 0.64)이 dossier에서 authoritative. book_state 무변경.
