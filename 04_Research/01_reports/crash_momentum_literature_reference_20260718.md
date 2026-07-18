# Crash-aware Momentum 문헌 그라운딩 — WT-D20260718_001 레퍼런스

**작성**: 2026-07-18 밤 (Q-Lead, alpha-research 병행 중 비충돌 레퍼런스 산출)
**목적**: WT-D20260718_001(종목-레벨 하방위험 페널티 × momentum selection) 라운드의 외부 문헌 그라운딩. alpha 단계 canonical 측정의 **소비 아님** — judge/risk 단계 해석·재spawn 대비 참조 + Step 0 차별 보강.
**정직 라벨**: [검색확인] = 이 세션 paper-search 실검색 확인 / [지식] = 모델 지식 기반(정본이나 이 세션 미검색·인용 정확도 재확인 권장).

---

## 1. 정본 문헌 지도 (crash-risk 모멘텀 구성)

| 논문 | 핵심 구성 | KR long-only 적용성 |
|---|---|---|
| Barroso & Santa-Clara, "Momentum has its moments" (JFE 2015) **[검색확인]** | 실현변동성으로 모멘텀 노출을 **스케일링**(risk-managed momentum) → 크래시 제거·Sharpe ~2배. 예측가능한 시변 위험 이용. | **timing overlay 성격** — 시스템의 "long-only 유일 MDD 레버=overlay/timing" 실측과 정합. WT가 테스트하는 cross-sectional selection 페널티와는 **다른 축**. |
| Daniel & Moskowitz, "Momentum crashes" (JFE 2016) **[지식]** | 크래시 = panic state(bear+고변동)에서 **short leg 반등**이 주동인. 동적 모멘텀 가중(optionality 대응). | ★long-only 비적용 부분: KR은 short leg 부재 → 크래시 기전이 **다름**(보유 winner의 동반 급락). WT의 표적이 바로 이 long-side 각도. |
| Grundy & Martin (RFS 2001) **[지식]** | 모멘텀의 시변 factor exposure(과거 상승장서 고베타 winner 매수 → 반전 시 노출 역풍). | 고베타 winner 문제 = WT의 하방베타/tail-beta 페널티 표적과 직접 정합. |
| Ang, Chen, Xing, "Downside risk" (RFS 2006) **[지식]** | **하방베타(downside beta)** 가격결정 — 하방 공행 종목에 프리미엄. | 종목-레벨 하방베타 = WT 페널티 축(D04_Downside_Beta) 이론 근거. |
| Bali, Cakici, Whitelaw, "Maxing out"(JFE 2011) / lottery-demand **[지식]** | 극단 상방(MAX) 종목 저수익 — crash-prone 복권성. | fleet-1 P7(복권성 MAX)서 KR 약검증(t 1.02<null). WT는 반대 방향(하방위험 페널티)이라 구분. |

## 2. WT 라운드에의 함의 (Step 0 차별 보강)

1. **외부 크래시 기전 ≠ long-only 기전**: 문헌 주류(Daniel-Moskowitz)는 short-leg 반등 기전이라 KR long-only에 직접 이식 불가. long-only 모멘텀 크래시는 **winner 동반 급락**(FQ-058 실측: systematic common-factor) → WT의 종목-레벨 winner 페널티가 정확한 각도.
2. **overlay(timing) vs selection(cross-sectional) 구분**: Barroso-Santa-Clara의 성공은 timing 스케일링. 시스템은 timing overlay를 이미 book(R05 tail-risk)에 보유. WT의 **미검 각도 = cross-sectional selection 페널티**(같은 momentum 알파 내에서 crash-prone winner 감점) — overlay와 **직교 잠재**(별개 레버면 스택 가능, 중복이면 흡수).
3. **factor DB 사전구축 확인**: D04_Downside_Beta·D08_Tail_Beta·D25/D26_Tail_Beta·D43_Skewness·D45/R07_Downside_Dev·R13_NCSKEW·R14_DUVOL 전부 월간 factor DB 존재(`load_month_factors()`). ⚠R13_NCSKEW는 fdb_daily 단일월 증분서 bit-parity drift 이력 — 월간 full-rebuild vintage만 소비.

## 3. 판정 시 경계 (외부 성공 ≠ KR 자본급)
- Barroso-Santa-Clara Sharpe 2배는 **long-short·timing·미국**. KR long-only cross-sectional에 그대로 이식 미보장 — canonical cap-w PORT_t 2.95 게이트·dual-basis·AX-001 v2 조건부(crisis_alpha)로만 판정.
- 문헌이 timing으로 잡은 효과를 selection이 흡수하지 못하면(active corr 高), overlay와 중복 → screen-tier 라벨. 흡수 못 하고 직교면 → sleeve 스택 후보(단 PORT_t 통과 동시충족 필요).

## 4. 소비면
- **WT-D20260718_001 alpha/judge**: winner 페널티가 timing overlay와 직교인지 = 자본 기여 관문(§2.2). judge crowding/attribution 단계서 확인.
- **FQ-059(soft-membership)**: 하방위험 페널티 = soft-membership 경계 처리의 한 입력 후보(경계 winner 완충).
- **risk_package**: long-only momentum structural DD = systematic(FQ-058) → tail/crowding 진단에 winner 동반급락 노출 반영.

---
**출처**: paper-search(SSRN empty·GScholar Barroso-Santa-Clara 확인·arxiv 광범위매칭) · 모델 지식(§1 [지식] 항목) · factor_registry.json(§2.3) · stage_artifacts/method_frontier/fq058_verdict.json(§2.1).
