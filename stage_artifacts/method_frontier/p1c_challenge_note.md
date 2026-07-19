# FQ-057 NP4-P1c — Self-Adversarial Challenge Note

**Round**: FQ-057-NP4-P1c (risk-research lane, independent round, not WT) — P1 FORM-proxy caveat(C3) 해소
**metric_type**: risk_forecast_accuracy_diagnostic — capital/graduation/weight claim 없음
**pin_tag**: fq057_20260718_171024 (P1 상속)
**verdict**: SPLIT 부분 확증 — (b) KEEP EWMA-direct 강건 유지 / (a) ADOPT lw_nls 는 방향+총분산 채널 유지·TE-채널 유의성 소실(FORM-proxy 아티팩트)

Opus 4.8 native adversarial reasoning. finalize 직전 약점 ≥3 제기 → ACCEPT/PARTIAL/REBUTTAL 분류 + 근거 + 합리화 자기검증.

---

## C1 [ACCEPT→강화] small-n: recent-60m 무판정 + 단일-book 일반성
**self-concern**: 판정 근거의 상당부가 full-range(n=185)에 의존하는데, 실 배포 book 은 2026-06 이후만 라이브다. recent-60m(n=71)에선 DM |t|가 대부분 <2(무판정)이고, 단일 book·단일 신호(score_eff)·단일 벤치라 일반성이 약하다.

**처리**: ACCEPT (설계에 반영·강화).
- 인정: recent-60m 은 검정력 부족으로 방향만 읽는다(fullinv TE a +0.42/b +0.29, overlaid TE a -1.05/b -0.20 = 전부 tie). 무판정으로 정직 기록.
- 그러나 판정의 핵심(a TE-tie / b KEEP)은 full-range·recent 양창에서 방향 일관: TE a-채널은 full(-0.73/-1.47)·recent(+0.42/-1.05) 모두 non-significant, total a-채널은 full(-4.0)·recent(-2.9) 모두 유의. 창 선택이 결론을 만들지 않음(양창 정합).
- 강화: 일반성 한계를 next_probe P1c-i(active 집중도 스펙트럼 × lw_nls TE-edge 규칙화)로 armed. "(a) TE-tie"는 '실 book 에선 linear LW TE 무해'의 실측이지 lw_nls 무용 증거 아님(never-worse) — 과대해석 방지 명시.
- 합리화 자기검증: "small-n이라 무시"로 넘기지 않고 양창 방향-정합 + 무판정 셀 명시 라벨.

## C2 [PARTIAL] production parity — 직접 실행 아닌 patch-verified 패널 소비
**self-concern**: §7b는 incumbent base = production 코드 직접 파생을 요구한다. 나는 score_eff 를 cleanT1 **저장 패널**에서 읽었다(직접 `_recompute_alpha_asof.R` 재실행 아님). 저장 패널 look-ahead 사고(project-stored-panel-samemonth-lookahead) 재발 위험 아닌가.

**처리**: PARTIAL.
- 인정: 268m 전 구간을 production 코드로 재실행하지 않았다(단일월 forward 코드를 60m walk-forward로 재실행하는 비용 회피).
- REBUTTAL 근거: cleanT1 은 §7b 예외조항이 명시 허용하는 **production_parity_verified 라벨** 보유 — 그 라벨의 근거가 바로 production `_recompute_alpha_asof.R` 직접실행(junction sandbox, 실 트리 무변경) 대비 spearman 0.975~0.997(4 sample months 2006/2013/2020/2026) + score_vs_recon max_abs_diff 0. 즉 이 패널은 "parity 검증 후 소비 가능" 조건을 이미 통과한 base다. 가중은 production forward_weights `.tilt/.norm` **verbatim port**(결정론적)라 추가 vintage 리스크 없음.
- look-ahead 방어: cleanT1 은 R28/R29가 정확히 그 동월 look-ahead(off+1)를 검거하고 만든 **off=0 clean(T-1)** 패널이다(구 저장 268m이 same-month, cleanT1이 그 수정본). 사고의 해법이지 재발이 아님.
- PARTIAL 잔여: 4-month spot parity 는 전 구간 exact-parity 는 아님 → limitation·next_probe(전 구간 production 직접실행 재확인)로 라벨.
- 합리화 자기검증: "parity 라벨 있으니 OK"로 뭉개지 않고 라벨의 실측 근거(spearman·max_abs_diff·off-scan)를 인용.

## C3 [PARTIAL] elig-restriction 이 실 book 선택을 왜곡 — "실 book 아님" 재현?
**self-concern**: P1c의 목적은 "실 book active"인데, 나는 선택을 elig(complete-60m)로 제한했다. production 은 무제한 유니버스에서 top-20을 고른다. 그럼 이것도 또 하나의 proxy 아닌가 — P1 caveat를 완전히 해소 못한 것.

**처리**: PARTIAL.
- 인정: elig-restriction 은 production 무제한 top-20과 완전 동일 아님(complete-60m 필터 추가).
- REBUTTAL 근거: (i) **필연** — Σ 이차형식 w'Σw 는 종목이 Σ coverage(60m)에 있어야 정의됨. 홀딩이 elig 밖이면 예측분산 산출 불가. 위험-forecast 진단의 구조적 요건이지 임의 왜곡 아님. (ii) **경미** — overlap 실측 중앙값 18/20(min 13, ≥17 in 81% months). 2종 median 차이. (iii) P1 proxy 대비 **진짜 변경**(신호 mom→score_eff, 가중 cap-w→LinearTilt)은 그대로 반영 — 이게 P1 caveat의 본질(선택신호+가중 form). elig-restriction 은 그 위의 2차 근사.
- PARTIAL 잔여: complete-60m 로 탈락하는 young 상장(고TE 가능)이 실 book엔 들되 elig엔 없음 → 실 book TE 를 소폭 과소반영 가능. 방향(a TE-tie)엔 보수적(고TE 종목 포함 시 오히려 집중↑ → lw_nls edge↑ 방향이라 tie 판정이 관대). limitation 명시.

## C4 [REBUTTAL] "(a) 부분 divergence"를 과장 — lw_nls 는 여전히 이겼다(total)?
**self-concern**: verdict가 "P1 (a) TE-채널은 아티팩트"라 했지만, 총분산에선 실 book도 lw_nls 가 -4.0로 이겼다. 그럼 P1 (a) ADOPT 는 사실상 유지인데 divergence 를 과장해 P1을 부당하게 깎는 것 아닌가.

**처리**: REBUTTAL (부분 PARTIAL — verdict에 반영됨).
- REBUTTAL: verdict는 이미 "direction_holds=TRUE, total_channel_significance_holds=TRUE, operational_recommendation=STANDS"로 명시 — 과장 아니라 **정밀 분해**. 깎는 게 아니라 P1의 어느 부분이 proxy-특정인지 국소화: P1이 **PRIMARY로 선언한 축이 TE**(prereg primary_target=te_variance, headline DM-t -3.06=TE)인데, 그 축의 유의성이 실 book에서 소실됨 = 정직한 정정 대상. total 은 P1도 "강화일 뿐 필수 아님"이라 했으니, primary 축 소실은 실질 caveat.
- PARTIAL: 그래서 "SPLIT_NOT_CONFIRMED"(기계판정)를 "부분 확증"으로 서술 — (b) 확증 + (a) 방향/운영 존속을 함께 기록해 균형. 운영 소비는 안 바뀜(lw_nls 유지)이나 **정당화 근거가 TE→total로 이동**은 WT-시점 오귀속 방지에 중요.
- 합리화 자기검증: "divergence"를 "폐기"로 부풀리지 않음 — never-worse·total-지배를 대등 비중으로 기록.

## C5 [PARTIAL] (b) overlaid-full 의 -2.025 를 tie로 처리한 판단
**self-concern**: overlaid_full TE 에서 lw_nls-vs-EWMA-direct DM-t = -2.025 ≤ -2 → 규칙상 lw_nls_better(=b 뒤집힘)인데, 나는 "비강건"이라며 KEEP 유지로 서술했다. cherry-picking 아닌가.

**처리**: PARTIAL.
- 인정: -2.025 는 사전등록 임계(-2)를 근소 통과 → 기계적으론 (b) divergence. metrics.json split_verdict_recent/full 에 그대로 DIVERGE_lwnls_beats_ewma 로 기록(은폐 없음).
- REBUTTAL: 4셀(fullinv/overlaid × full/recent) 중 3셀 tie(-1.256/+0.286/-0.197), 유일 예외가 overlaid-full -2.025. recent-60m overlaid 는 -0.197(정반대)로 **미재현** = 경계·비강건 실측. 단일 창×단일 변형의 -2.0은 다중 셀 관점에서 우연 범위. → "KEEP 유지(보수적)"가 방어적 결론. λ 튜닝은 EWMA 유리 방향이라 KEEP 더 강건(P1 C6 정합).
- 합리화 자기검증: 임계 통과 셀을 숨기지 않고 명시 + 왜 비강건인지(3/4 tie·recent 미재현) 실측 논거. "경계라 무시"가 아니라 다중-셀 robustness 판단.

---

## 합리화 auto-detection
"미미/관행/보수적이면 OK/영향 없음" 사용 여부:
- C1 "small-n 무시" → 양창 방향-정합 + 무판정 라벨로 대체 ✓
- C2 "parity 라벨 있으니 OK" → spearman·max_abs_diff·off-scan 실측 인용 ✓
- C5 "경계라 무시" → 3/4 tie·recent 미재현 다중-셀 논거 ✓
합리화 회피 표현 없음.

## Escalation 판정
- HIGH ≥5? 없음. AX axiom hard FAIL? 없음. PIT hard violation? 없음(예측=t 이하, 실현=t+1, 05_Production read-only, PIT-clean).
- Σ PD violation? **lw_nls PSD rate 100%** — 위반 없음. linear LW/ewma_struct 특이성은 진단 대상(판정 재료).
- → Q-Lead escalate 불필요. 정상 finalize. 단 posterior 문구 정정(P1c-iii)은 Q-Lead 반영 대상(오소비 방지).

## AX-008 Verification Triangulation
self-adversarial(본 note) = 3-source 중 1. measurement diagnostic(자본 아님)이라 forge/judge full-pipeline 부적용 → Forge-급 독립검증 대체 = **capw_mom_proxy in-run P1 완전 재현**(a DM-t -3.057=P1 -3.0569 / b -1.236=P1 -1.2363 + Σ cond 1.00/98.14/Inf bit-일치) = P1 산출에 대한 독립 재현 검증 + **양 실 book 변형(fullinv/overlaid) 교차 동일 결론**(a TE-tie·b hold) = 내부 2-fold 독립확증. 2/3 충족.
