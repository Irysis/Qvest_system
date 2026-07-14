# Risk Agent — Self-Adversarial Challenge (v8.2, Codex Round 대체)

**WT**: WT-D20260714_006 / FQ-045 · candidate=B2_value_nonmega_conditional · incumbent=STR_1715_on_M4_R05_noLayer4_PG2
**as_of**: 2026-07-14 · **PIT lockbox**: 2023-12-22 strict · **pin**: R28_current_20260714
**작성**: risk-research (finalize 직전 적대 자가검증). AX-008 3-source 중 1개(Forge·Architect와 triangulation).

Σ 추정·tail·stress·crowding·style 산출을 스스로 적대적으로 공격하고 ACCEPT/PARTIAL/REBUTTAL로 분류한다.

---

## SC-1 [PARTIAL] FF5 불완전 — RMW/CMA 누락
**자기비평**: 과제는 "FF5+BAB+momentum" 명시. 나는 MKT/SMB/HML/WML/LOWVOL(BAB proxy)만 구축, 수익성(RMW)·투자(CMA)는 fundamentals 파싱 범위로 생략했다. FF5의 2축이 빠진 style 진단은 불완전.
**분류: PARTIAL.**
- 인정: FF5 전체는 아니다. 명시 라벨로 diagnostics.data_limitations에 기록(조용한 단순화 회피).
- 반론: 본 WT의 결정 지표는 "B2 vs 벤치(STR_1715) 잉여성"이며, 이는 **realized 수익률 상관(0.98 active)·신호 상관(0.93)으로 직접 실측** — factor set 완전성과 무관하게 성립. 변별점인 value 틸트는 HML로 완전 포착(B2 HML β 0.78 vs vanilla 0.54). 변동 지배축은 MKT(85% 분산). RMW/CMA 누락은 잉여성 결론에 immaterial.
**처리**: 유지 + 한계 라벨 명시. spec 수정 불요.

## SC-2 [REBUTTAL] Factor-model Σ 추천이 self-serving 아닌가
**자기비평**: 추천한 factor model이 cond 43.4로 "가장 좋게" 나온 건 구조를 강제해 idio 공동움직임을 과소평가한 결과일 수 있다. Sample을 배제한 근거가 편의적일 가능성.
**분류: REBUTTAL** (학술+정량+L-code 3축).
- 정량: 25종 중 **1종(LG CNS) pre-lockbox 관측 0** + 3종 <30개월. return-기반(Sample/LW/Gerber) 어느 것도 결측 없이 25×25를 못 만든다 — Sample(pairwise) cond 1.16e11 non-PSD, Gerber-RMT non-PSD, LW(hrp) degenerate over-shrink(cond=1.0). LW-const-corr(89.4)조차 zero-history LG CNS 미포함. **factor model만 PSD·전-25종·PIT 준수**.
- 학술: BARRA-style multi-factor risk model은 이질적 상장일·짧은 시계열 유니버스의 표준 해법(구조로 결측 보간).
- 방법 shopping log 5종 전수 기록(R2-C HARD, 상한 5 준수), selection_objective=condition_number(R4 HARD, return 미참조).
**처리**: 추천 유지. method_shopping_log에 각 후보 cond·PSD·기각사유 명시.

## SC-3 [ACCEPT] LG CNS(A064400) 위험 = 섹터-피어 proxy
**자기비평**: LG CNS는 2025-02 IPO, lockbox 전 수익률 0개. 그 B/D를 소프트웨어 피어(NC/KakaoPay) 평균으로 대체 — 실측 아닌 proxy. 이 종목 특이위험 추정은 신뢰도 낮음.
**분류: ACCEPT** (실제 데이터 공백).
**처리**: diagnostics.data_limitations + challenge_flags[2]에 명시. optimizer/forge에 "해당 종목 specific risk lower-confidence" 경고. No silent override. (Σ ill-posed은 아님 — 전체 cond 43.4 PSD 정상.)

## SC-4 [PARTIAL] TDC 소표본 — empirical vs Clayton 괴리
**자기비평**: headline TDC(mean pairwise lower 0.252)는 q=0.10 empirical, 쌍당 tail 관측 ~24개로 저파워. Clayton parametric은 0.846으로 크게 다르다. metric 선택이 결론(0.252<0.30)을 편의적으로 만든 것 아닌가.
**분류: PARTIAL.**
- 인정: tail 점추정은 저파워. 0.252를 정밀값으로 읽지 말 것.
- 반론: empirical이 primary인 이유 — Clayton은 moderate Kendall tau에서 lower TDC를 **구조적으로 과대**(모수 가정 아티팩트, Pfaff Ch.9). 방향성은 삼각 지지: EVT-GPD ξ≈-0.04(thin/near-exponential tail), Hill α 3.47(유한분산). 셋 다 "극단 cross-name tail clustering 증거 없음"으로 일치. 단 book-vs-market lower TDC 0.625는 높음(long-only 시장 동반급락 = 구조적)로 별도 명시.
**처리**: tail_risk.json에 empirical primary + Clayton 아티팩트 주석 + EVT/Hill 병기. "no evidence of extreme cross-name tail clustering"로 해석 한정.

## SC-5 [ACCEPT] Stress 2008/2011 coverage <85% = UNRELIABLE
**자기비평**: GFC 2008(72%)·EuDebt 2011(76%)은 다수 종목 미상장 → 부분-상장 아티팩트. realized -39.5%/-20.3%를 액면대로 쓰면 오도.
**분류: ACCEPT** (skill: coverage<85% UNRELIABLE 명시, hard-fail 금지).
**처리**: stress_tests에 coverage + reliable=FALSE + "UNRELIABLE" flag. beta-implied(-46.4%/-18.7%)를 별도 extrapolation으로 병기. reliable stress(COVID -17.3%, Rate2022 -21.9%)만 정책판정 근거. market_down_5 -5.54% > -8% → RF-R4 미발동, Rule-2 STOP 아님.

## SC-6 [PARTIAL] Regime crisis 상관 = 최근-120m 한정
**자기비평**: crisis 상관(+0.055 uplift)은 last-120m(2014-2023) 창에서만 — 진짜 GFC crisis 미포함(해당 종목 이력 없음). crisis 공동움직임 과소평가 가능.
**분류: PARTIAL.**
- 인정: 창 한계로 uplift 저평가 가능. regime_correlation.parquet에 window 라벨 명시.
- 반론: 전-기간 crisis 상관은 keep 종목 결측으로 산출 불가(NA). 최근창 crisis(COVID+2022) uplift +0.055는 유효 신호. 극단 crisis 공동움직임은 book-vs-market TDC 0.625 + beta 1.11로 이미 포착.
**처리**: window="last_120m_2014_2023" 명시 + 한계 라벨.

## SC-7 [REBUTTAL] Market 85% (RF-R1 HIGH) = 결함인가
**자기비평**: 시장 분산점유 85%는 RF-R1(>40%) HIGH 발동. Σ가 시장 위험을 과다 귀속했거나 book이 위험한 것 아닌가.
**분류: REBUTTAL.**
- 정량: EW-mean univariate market beta 1.11, 25종 long-only. 시스템적 85%/특이 15%는 집중 25종 KR long-only book에 타당.
- L-code/메모리: reference-orthogonality-gross-vs-active — long-only KR β≈0.92~1, 시장성분(PC1) 지배는 **구조**(공매도 불가로 제거 불가). 광범위 패밀리 PC1 0.76, 집중 25종은 더 높음.
- **AX-000 따름정리(제약=고정 축)**: 시장 지배를 "제약 완화(공매도 허용 등)"로 풀자고 제시하지 않음 — envelope-안 사실로 보고. RF-R1은 STOP 아닌 optimizer exposure-awareness 권고.
**처리**: RF-R1 triggered=TRUE로 보고하되 STRUCTURAL 라벨 + "not fixable via Sigma". weight 미제안(role boundary).

---

## 자기-합리화 auto-detection
"미미/관행적/보수적이면 OK" 사용 여부 self-scan → 미사용. "immaterial"(SC-1)은 정량근거(0.98 realized cor는 factor set 독립)로 뒷받침 — 회피표현 아님. 모든 한계는 명시 라벨.

## 자동 escalate trigger 점검
- HIGH ≥5? → RF HIGH triggered 1(RF-R1, structural). **미해당.**
- AX axiom hard FAIL ≥3? → 0. **미해당.**
- PIT hard violation? → 없음(strict lockbox 2023-12-22 준수, 모든 진단 post-lockbox 수익률 미사용). **미해당.**
- Σ PD violation? → 추천 factor-model Σ minEig 2.74e-3 > 0, PSD. **미해당.**
→ **Q-Lead escalate 불요.** blocking=FALSE.

## 결론
Σ well-posed(factor model cond 43.4 PSD, 전-25종), PIT-clean. 핵심 risk 발견 = **B2는 벤치(STR_1715) 대비 위험구조상 잉여**(realized active cor 0.98·crowding fingerprint 동일·signal cor 0.93) → book-marginal 위험분산 이득 ~0, alpha holdout dIR -0.022를 risk 각도에서 독립 확증. 데이터 공백(LG CNS·단이력 3종)·2008/2011 stress UNRELIABLE·FF5 부분셋은 정직 라벨로 surface. Rule-2 STOP 조건 미충족.
