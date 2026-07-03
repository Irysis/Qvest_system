# Self-Adversarial Challenge — WT-D20260701_002 Judge (AX-008 source #2, Opus 4.8 native)

**verdict finalize 직전 devil's advocate. Codex Round 대체(v8.2).**

## 자기비평 3건

### C-1 DSR / selection-type (sweep vs chain)
- **약점 제기**: dossier가 T=8/16/32/64 + regime map + combine + trend-only 다변형 탐색을 명시. measurement-graduation §3상 sweep(argmax/threshold-pick)이면 DSR≥0.5 HARD.
- **자가반박**: 채택안 = T=16 **논문 원계수**(0.13+0.79σ²−0.17ϕ+0.09ϕ²) = *사전약정 외부 앵커*. sweep argmax는 오히려 trend-only T=16(ΔSR +0.330, t +3.08) / faith T=8(+0.254)로 *더 좋음* — 연구자는 best를 안 고르고 pre-registered 논문 앵커를 택함 = chain/사전약정 signature. 게다가 이건 standalone alpha가 아니라 **book-marginal 오버레이 교체** — 권위 게이트 = paired-NW-t(개선분) + diff oos_retention이지 standalone DSR 아님. DSR은 standalone 다중검정 개념이라 "이 오버레이가 incumbent 오버레이를 이겼나"에 어색하게 매핑.
- **판정**: DSR = **advisory + haircut 명시 요구**(blocking HARD 아님). chain 자격 부분충족(mechanism 기록 ✓, 호라이즌 전대역 통과 ✓ = cherry-pick cliff 아님).

### C-2 개선분이 generic trend 대비 얇음
- **약점 제기**: tsmom SR 1.771 = faith 1.878의 94%. 논문④ 계수가 plain trend 대비 +6%뿐. 그냥 tsmom 배포가 낫지 않나?
- **자가반박**: 게이트는 faith-vs-**AR-incumbent**(paired-t +2.04)지 faith-vs-tsmom 아님. faith·tsmom 둘 다 AR 이김. honest caveat이 메커니즘을 "generic 비대칭 추세 de-risk, AR층보다 나음"으로 정확히 reframe(논문④ 고유 alpha 아님). verdict가 논문④로 과잉귀속만 안 하면 valid.
- **판정**: **residual risk / attribution note**(FAIL 아님). verdict에서 attribution 정정 의무.

### C-3 2008 GFC 회귀 (tail protection 하향?)
- **약점 제기**: 개선안이 오버레이 존재이유인 systemic crash에서 *더 나쁨*(17.5% vs AR 9.3%). crash-detector를 trend-follower로 바꾸는 = tail 보호 downgrade.
- **자가반박**: (a) 전기간 MDD는 faith가 *낮음*(21.2 vs 23.3%) — AR 우위는 GFC 단일 에피소드에 국한, faith 추세 de-risk이 return path 더 넓게 커버. (b) GFC 보호 유지하는 combine-min(DD 6.6%)은 OOS 불안정으로 정당하게 폐기됨. (c) strict domination 아닌 **조건부 tradeoff**. AX-001 v2(조건부 방어 평가)상 aggregate 위험조정 개선 + 1 crisis 에피소드 손실 = 정당한 surface 대상.
- **판정**: **governor-결정 residual risk로 명시 surface 의무**. 조용히 통과 불가.

## 자율분류: **PARTIAL**
핵심 verdict(admission-ready = JUDGE_PASSED) 유지하되 2개 필수조건:
1. DSR haircut 인정 + attribution 정정(generic trend, 논문④ 아님)
2. GFC tail 회귀를 governor+도훈 결정용 residual risk로 surface

AX hard-fail 0 / PIT C1 hard 위반 0 / HIGH≥5 아님 → **Q-Lead auto-escalate 불요**.

## AX-008 Triangulation (2/3 이상 PASS 필수)
- **Forge** (contract 측정): PASS — metric_type=backtested, audit WARN 4(holdings=NULL 유래 정상), Critical 0.
- **Self-Adversarial** (본 note): PARTIAL-PASS (조건부).
- **Architect**: N/A(오버레이 교체, 인프라 변경 없음) — 미소집.
→ 2-source PASS 충족 (Forge + Self-Adversarial). AX-008 satisfied.
