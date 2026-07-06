# Self-Adversarial Challenge — WT-D20260706_009 (Net Share Issuance capital-discipline)

**Agent**: alpha-research (QEPM)  ·  **Date**: 2026-07-06  ·  **Verdict**: CLEAN_NEGATIVE (active-benchmark wall confirmed)
**Method**: Opus 4.8 native adversarial reasoning (v8.2 — Codex Critic Round 대체). AX-008 3-source 중 1개.

Finalize 직전, alpha_package를 스스로 적대적으로 검증. 각 concern을 ACCEPT / PARTIAL / REBUTTAL로 분류 + 근거.
근거 3축(canonical 실측 PORT_t / decile·bucket / sub-period·breadth) + 학술(Daniel-Titman 2006, Pontiff-Woodgate 2008) + L-code([[reference-kr-2025-megacap-semi-regime]], [[project-dart-insider-exec-nonreturn-frontier]], measurement-graduation §6 "직교≠수익").

---

## Concern 1 (mandate i) — split/무상증자 오염: 순수 발행/소각만인가?
**분류: REBUTTAL (오염 아님, 근거 정량 제시)**
- `ISSD` raw shares에서 단일분기 |Δlog|>0.35 (SPLIT_THRESH) = 액면분할/무상증자로 판정, cumsum-jump 제거로 split-adjusted 시계열 구성.
- 정량 근거 3축:
  1. split quarters flagged = 5,445 / 301,866 = **1.80%** (합리적 — 실제 KR 분할/무증 빈도 수준).
  2. **rank-IC adj=4.30 vs raw(no-adj)=4.41** — 거의 동일 → 신호는 split이 아니라 실제 issuance/retirement에서 발생.
  3. **top-25 픽 adj vs raw 92.1% 중첩** — split 제거가 소수 종목만 교체, 신호 구조 불변.
- CEI(composite equity issuance, Daniel-Titman) 별도 산출 = 본질적 split-proof(ME·return 둘 다 조정) 교차검증: rank-IC t=2.30, PORT_t 全 음 → shares-based와 방향 일치(둘 다 deployment 실패)로 split 아티팩트 배제.
- **결론**: 오염 없음. 순수 financing-side 신호. self-rationalization("미미") 미사용 — 정량 3축.

## Concern 2 (mandate ii) — large-cap 신호가 mega-cap 소수종목 우연인가?
**분류: REBUTTAL (breadth 충분, 우연 아님)**
- large-cap RETIRE 버킷: **85 distinct tickers, 7.5 names/month, 246 months** — breadth 건전.
- 최빈 대형주 retirer = KT&G(A033780)·미래에셋(A006800)·KT(A030200)·삼성전자(A005930)·KB금융(A105560) 등 = 실제 KR 자사주 소각 상습 기업 → 경제적 mechanism 실재.
- large-cap RETIRE(long) 버킷 raw fwd = **2.30%/월 vs ISSUE 0.77%** — 대형주에서도 신호 실재.
- **단, actionable 아님**: large-cap rank-IC t=2.41 < SMALL t=4.57 → 신호는 오히려 소형주에서 더 강함. large-cap top-25 PORT_t = 0.09~0.17 (dead). 우연은 아니나 대형주 배포 엣지 부재.

## Concern 3 (mandate iii) — EW-생존이 소형주 틸트 아티팩트인가?
**분류: ACCEPT (핵심 부정 사유 — 벽 안)**
- POST2017 dual-bench: **cap-w PORT_t = −0.58 (음) / EW PORT_t = +1.58 (양)**. VALUEUP2024: cap-w −1.02 / EW +1.92.
- 재프레임 판별: cap-w 음 + EW만 양 = **"벤치아티팩트가 아니라 small/mid-vs-megacap 틸트"** — 신호는 EW-평균종목을 이기나 cap-w 지수(mega-cap 지배)를 못 이김.
- 즉 이 신호는 insider 유형(large-cap-relevant, cap-w 생존)이 **아니다**. thesis(감쇠벽 밖) **반증**.
- top-25 픽 median size-pctile 71%(중대형)이나 cap-w 대비 음 → mega-cap 앵커 부재가 바인딩. measurement-graduation §6 "cap-w authoritative" 정합.
- **결론**: EW 생존은 실재하나 배포-관련(cap-w) 게이트 미통과 = 벽 안. 이것이 CLEAN_NEGATIVE 근거.

## Concern 4 (mandate iv) — value-up era(2024+) 신호가 단기 과적합인가?
**분류: PARTIAL (과적합 아니나 무의미 — window 짧고 cap-w 음)**
- 2024+ RETIRE 버킷 breadth = 96 distinct tickers / 30 months → 종목 과적합 아님(broad).
- 그러나 **cap-w PORT_t = −1.02 (음)** → value-up이 자본배분 규율을 강화했다는 thesis가 배포 기준 성립 안 함.
- EW +1.92는 30개월 short-window로 정보량 낮음(HARD 게이트 판정 불가 규모). 과적합이라기보다 **cap-w 기준 신호 부재**.

## 추가 자가제기 (agent-originated ≥1)
### Concern 5 — rank-IC t=4.30이 illiquid microcap 아티팩트인가?
**분류: REBUTTAL**
- adv20≥2e8 유동성 필터 적용 후 rank-IC t=**4.35** (필터 전 4.30과 동일) → microcap 유동성 아티팩트 아님. 신호 자체는 견고.

### Concern 6 — 신호가 sparse(72% zero)해 top-25 스크린이 zero-signal 종목으로 희석되는가?
**분류: ACCEPT (구조적 한계 인정)**
- nsi_shares 72.3% exactly-zero, 실제 retirer 3.8%뿐. RETIRERS-only(retire_score>0.002) 스크린도 PORT_t 全 음(FULL cap-w −0.27) → 희석 제거해도 배포 실패. 신호 sparsity가 top-25 long-only 이식성의 구조적 벽(long-short가 자연 표현이나 KR no-short mandate).

---
## 종합 처리
- ACCEPT 3 (C3 핵심·C4·C6) + REBUTTAL 3 (C1·C2·C5) + PARTIAL 1(C4 overlap).
- **HIGH severity ≥5 아님 / AX axiom hard FAIL 아님 / PIT C1 위반 아님** → Q-Lead auto-escalate trigger 미발동.
- 최종 판정 = **CLEAN_NEGATIVE**: net-issuance는 (a) 학술대로 실재하는 횡단면 프리미엄(rank-IC t=4.30, RETIRE 2.04%/월, 직교 0.064)이나 (b) top-25 long-only cap-w PORT_t 全 <2.95 (best 0.08), value-up era cap-w 음 → **IC→PORT_t 전이 벽 + cap-w mega-cap 앵커 부재**. thesis(감쇠벽 밖 = large-cap-relevant) 반증(cap-w 음, EW만 양 = small/mid 틸트).
- self-rationalization grep("미미/관행/보수적/대부분동일") 미사용 확인.
- forge 승격 **권고 안 함** (cap-w PORT_t 0.08 ≪ 2.95, MILESTONE 아님). screen-route = DPL_FEATURE (financing-side 직교 피처로 DPL 연료 가치, measurement-graduation §5).
