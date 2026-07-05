# Self-Adversarial Challenge — WT-D20260705_003 (Alpha Research)
**Agent**: QEPM Alpha Research (Opus 4.8 native adversarial, v8.2 — Codex Round 대체)
**Date**: 2026-07-05
**Signal under test**: Forward-consensus LEVEL composite (fwd_opyield + fwd_eyield + fwd_syield, EW z) + singles
**AX-008 role**: 3-source verification 중 self-adversarial (1/3). Forge/Architect는 후속.

## Concerns raised (≥3, devil's advocate)

### C1 [ACCEPT] — rank-IC를 realized alpha로 오독하는 함정
- **주장**: rank-IC Harvey-t 5.09 (fwd_opyield), post-2017 IC +0.046 (감쇠 없음)은 매우 강해 보인다. 이것을 "배포 가능 알파"로 읽으면 오독.
- **검증**: canonical_screen_bt (top-25 EW long-only, 15bps) 실측 결과 realized PORT_t는 full-sample(corrupted bench 포함) +1.38, subperiod로 보면 2005-2016 +3.24 → 2017+ (clean 2017-2024) +0.25~−0.13로 **rank-IC의 안정성이 realized top-25 포트로 전이되지 않음**. measurement-graduation §2 정확히 그 벽.
- **분류**: ACCEPT. rank-IC는 advisory로만 보고, **PORT_t를 판정 권위로 채택**. alpha_package에 둘을 명시 구분.

### C2 [ACCEPT] — 벤치마크 오염이 subperiod 부호를 왜곡
- **주장**: 초기 subperiod에서 2017+ PORT_t −1.31로 "강한 부호 반전"으로 보였으나, 이는 결론 조작 위험.
- **검증**: benchmark.parquet + RAWDATA BM_Ret 양쪽 모두 **2025년부터 오염**(월수익 +22%/+27%/+35% = KOSPI200 불가능, 202601 close 768→202605 1342). 2017+ 창(n=114)의 tail 18개월이 corrupted BM. 오염 tail 제거 시(≤2024-12) 2017-2024 PORT_t가 −1.13 → **+0.25**(composite)로 정정 — 부호 반전 아니라 **감쇠(flat)**가 정직한 표현.
- **분류**: ACCEPT. 오염 은폐 금지 (AX-000). authoritative 측정은 clean bench(≤2024-12)로 고정, 2025+는 "측정 불가"로 flag. 부호 반전 주장 철회, "modern-regime 감쇠"로 정정.

### C3 [ACCEPT] — fwd_eyield/opyield는 그냥 forward-value(AX-003 재현) + 소형주 틸트
- **주장**: eps_1y/price, op_profit/mktcap = earnings/price ratio = value의 forward 판본. AX-003(KR value 24/24 post-2015 감쇠) 재현일 뿐. 소형주 틸트가 alpha를 설명.
- **검증**: top-25 composite 평균 log10(Size) 11.77 < universe 12.01 (**소형주 틸트 확인**). 감쇠 시그니처(2005-2016 강 → 2017+ flat)가 KR value decay + microcap 유동성 프리미엄(2010-21 강, 2022+ 사멸, KNS/superfactor findings와 동일)과 정합. tp_implied만 value와 저상관(z-cor 0.08)이나 그것도 2017+ 감쇠 동일.
- **분류**: ACCEPT (정직 라벨). 이 signal은 "forward-value + 소형주 틸트"이며, INV-7상 forward-*수준*은 별개 축 재도전으로 정당했으나 **실측 결과 value-family 감쇠를 재현**. hypothesis 가드가 요구한 정직 라벨을 부여: value/quality 재현이면 그렇게 라벨.

### C4 [PARTIAL] — full-sample PORT_t +3.51은 2.95 통과인데 왜 FAIL?
- **주장**: clean 전기간 z_composite PORT_t +3.51 > 2.95 HARD bar 통과. 왜 졸업 불가?
- **검증**: graduation은 3-HARD AND. ① PORT_t +3.51 PASS ② **oos_retention +0.253 << 0.7** (measurement-graduation §3: <0.5 = 무조건 FAIL) ③ **calmar +0.276 << 0.64** (MDD 58.7%). PORT_t는 2005-2016 dominant. oos_retention 0.25 = 활성 Sharpe가 OOS(recent)에서 붕괴 = 과적합/감쇠 게이트 정확히 발화.
- **분류**: PARTIAL. PORT_t 단독 통과는 인정하나, 3-HARD 중 2개 결정적 FAIL로 자본 졸업 불가. 이것이 게이트의 정확한 작동 (2005-2016 fit이 recent로 미전이).

### C5 [ACCEPT] — book-marginal ΔIR이 진짜 타겟인데, 그게 통과하나?
- **주장**: hypothesis 진짜 타겟 = standalone 졸업 아니라 book-marginal ΔIR≥0.05 vs STR_1715. 그건 통과 가능성 별개.
- **검증**: blend(STR_1715 active + composite active) full clean 창: incumbent IR 1.378 → w=0.20 blend IR 1.465, **ΔIR +0.087 (>0.05 통과처럼 보임)**. 그러나 **[2017-2024 modern]: incumbent 1.133 → blend w=0.20 IR 1.125, ΔIR −0.008 (음)**. 즉 book-marginal 이득도 전적으로 2005-2016 산물, modern regime에서는 book을 오히려 해침.
- **분류**: ACCEPT. full-sample ΔIR +0.087은 backward-looking 착시. forward 관점(modern regime)에서 composite는 book에 net-negative. book-marginal admission도 부적격.

### C6 [ACCEPT] — tp_implied = 인큐번트 C06_TP_Gap 직접 중복
- **주장**: target_price/close−1 = STR_1715 core sleeve의 C06_TP_Gap과 사실상 동일 변수. "미탐색 축" 주장 훼손.
- **검증**: reference_str1715_structure 확인 — STR_1715 Core "4F Consensus" = {C01_SUE, C02_EPS_Chg_1m, C04_ESBR, **C06_TP_Gap**}. tp_implied는 C06과 formula 동일. 나머지 signal(fwd_opyield/eyield/syield)은 forward *level* yield로 incumbent revision 계열과 구분되나, tp_implied는 중복.
- **분류**: ACCEPT. tp_implied는 "미탐색" 아님 — incumbent 중복으로 명시 flag. composite에서 제외 검토했으나(comp2), comp2 PORT_t는 더 낮음. tp_implied는 factor_specs에 redundancy_cluster_id=incumbent_C06_TP_Gap로 라벨.

## Self-rationalization auto-detection
- 사용 회피 표현 스캔: "미미/관행적/실무적/보수적이면 OK/대부분 동일" — **미사용**. 모든 감쇠·부호·오염을 정량 수치로 명시.
- 유일 위험 표현: full-sample PORT_t +3.51을 "통과"로 프레이밍할 유혹 → C4/C5에서 oos_retention·modern-regime ΔIR로 반박, backward-fit 착시임을 명시.

## Escalation trigger 판정
- HIGH severity concerns: C1/C2/C3/C5 (4건). AX axiom hard FAIL: 없음(AX-003은 Distilled, 재현이나 위반 아님). PIT C1(lockbox/lookahead): 위반 없음(asof merge + forward return + t-1).
- **Q-Lead escalate 불필요** (HIGH ≥5 아님, axiom hard FAIL ≥3 아님, PIT C1 위반 아님). 정상 negative-result 보고 경로.

## 최종 반영
- Verdict: **SCREEN-TIER / FAIL for capital** — rank-IC 신호력 실재(Ht 5.09)이나 (a) realized top-25 PORT_t가 2017+ 감쇠, (b) oos_retention 0.25 << 0.7 auto-fail, (c) calmar 0.28 << 0.64, (d) book-marginal ΔIR modern-regime 음(−0.008), (e) forward-value + 소형주 틸트 = AX-003 감쇠 재현.
- risk-research 진행 권고 안 함. screen-route = DPL_FEATURE (rank-IC 신호력은 DPL 입력 피처로만 유효).
