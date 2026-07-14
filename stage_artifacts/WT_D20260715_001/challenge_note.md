# R32 Self-Adversarial Challenge Note (Forge, Opus 4.8 native adversarial — v8.2 Codex Round 대체)

WT-D20260715_001 / FQ-048 / 밸류 추가가 실제 PG2 북(M4xR05 오버레이 적용)의 최종 배포 성과를 강화하는가.
AX-008 3-source: Forge 실측(본 note) + Self-Adversarial(본 note) + Architect(미소집 — 아래 §4 판정) → 2/3.

## Challenge 1 — arm0가 production 실북과 정합하는가 (§7b parity). ★가장 중요.
**제기**: arm0 base(clean recon N20 λ1.5 tilt on 0_ic_S7)가 production `ret_orig`와 정합하지 않으면 3-arm 비교의 기준점이 무효.
**측정**: Pearson corr **0.762** · SR_recon **0.961** vs SR_prod **1.536** · mean monthly diff **-1.35%p** (production이 월 1.35%p 높음).
**진단 (핵심 발견)**: 이 divergence는 arm0 recon의 버그가 아니라 **production 역사 `ret_orig` 시리즈 자체의 same-month vintage 부풀림**이다 —
- 근거 ①: clean recon overlay-applied PORT_t **3.455**(base pre-overlay range 3.06~3.25)는 R28/R29 judge-급 확정 clean base(cap-w top-25 3.058/ic 3.247, N20 tilt은 소폭 高)와 **정확 정합**. 즉 clean recon = R29 확립 clean 진실.
- 근거 ②: production noL4 book pinned PORT_t **6.214** / SR_geo 1.898 ÷ clean recon 3.455 / 1.089 ≈ **1.80~2.08×** = R28/R29가 통제실험으로 확정한 same-month vintage 부풀림 계수(**2.08×**)와 일치.
- 근거 ③: `0_ic_S7` = production `_recompute_alpha_asof.R` score와 **spearman 1.000 exact**(p2_prod_parity.rds, max_absdiff 0) — 신호는 production 그 자체. divergence는 return 시리즈 vintage에서만 발생(신호 아님).
**판정**: production 라이브 실주문 경로(T-1)는 clean(R29 확립)이나, **역사 panel-lineage `ret_orig` NAV 시리즈는 vintage 부풀림 잔존**. §7b mandate("production 코드 파생 clean 신호")를 엄격 준수 → **clean recon(0_ic_S7 T-1)이 올바른 arm0 base**. corr 0.762는 (a) panel-lineage frozen 홀딩 vs 월별 재도출 + (b) production ret_orig vintage 부풀림의 합. **STOP 아님**: clean recon은 정상 작동(부호 정합·PORT_t가 R29 clean 진실과 일치). 단 ★도훈 결정 재료: 현직 book pinned 6.130/6.214는 clean-basis 재산출 필요(FQ-044 P2 기확인, 별도 judge 라운드) — 본 R32가 그 재산출의 3-arm 확장 실증.
**한계**: 3-arm 비교는 clean recon basis에서 내부 일관(동일 신호·동일 construction·동일 오버레이) → 밸류 효과 판정은 유효. production pinned NAV와의 절대수준 비교는 vintage 격차로 무의미(라벨).

## Challenge 2 — 오버레이가 밸류 방어성을 상쇄하는가 증폭하는가 (방향 귀속).
**제기**: 밸류의 defensive tilt(저β)와 오버레이의 현금조절(저노출)이 같은 국면에 겹치면 오버레이가 밸류 방어 효과를 마스킹(중복 de-risk) → 밸류 추가 무의미할 수 있음. 반대로 상호 보완이면 증폭.
**측정**: down-market(bench<-3%, n=53) mean return: baseline **-4.81%** → B2 **-4.48%** → Z6 **-4.44%**. down-capture(vs bench): 0.693 → 0.645 → 0.640. β(overlay): 0.767 → 0.747 → 0.724.
**판정**: **오버레이는 밸류 방어성을 상쇄하지 않는다 — 방향 정합(보완)**. 오버레이 적용 후에도 밸류가 down-capture를 0.693→0.640으로 추가 개선(β -0.03). 즉 밸류 방어분은 오버레이 현금분과 별개 채널(밸류=종목선택 저β, 오버레이=매크로 현금)로 additive. **단 MDD/Calmar 개선의 지배분은 방어가 아니라 pre-2024 알파**(CAGR 0.253→0.317 = 방어라면 CAGR 하락해야 하나 상승 = 알파 성분). down-capture 개선(0.05)은 실재하나 소폭. → 밸류의 위험축 기여 = 소폭 genuine defense + 큰 pre-2024 알파(후자는 2024+ 역전, Challenge 3).

## Challenge 3 — MDD/Calmar 개선이 표본-특이(단일 에피소드)인가.
**제기**: 밸류의 Calmar 0.72→1.14 개선이 2020 COVID 등 단일 drawdown 에피소드에서만 발생하면 배포 신뢰 불가.
**측정**: MDD date — arm0 2023-09 / arm1 2023-09 / arm2 **2007-12**(서로 다른 에피소드). COVID(2020) dd: arm0 -0.246 / arm2 -0.273(밸류가 COVID엔 오히려 소폭 악화). MDD 개선은 곡선 전반 분산(arm2 최악낙폭이 2007로 이동 = 특정 에피소드 아님).
**★그러나 진짜 표본-의존은 시간축**: value marginal paired-t **pre-2024 +4.24 → post-2024 -1.26(B2) / -1.64(Z6)**. post-2024 book active: baseline +85bps → B2 +14bps → Z6 **-22bps**. OOS retention v2: 0.244 → 0.195 → **0.142**(밸류가 retention 악화). **판정**: 개선은 단일 drawdown 에피소드 특이는 아니나(공간 분산), **시간-특이(pre-2024 집중, 2024+ 완전 역전)**. = value 아크 R26~FQ-046의 "2024+ value-vs-mega 스타일 역전"(lockbox OOS -1.191) 정면 재현. 위험축 full-period 개선은 실재하나 **최근 2년 소진 + 자본게이트(OOS 0.7) 3 arm 전부 미달**.

## §4 Architect source (AX-008 3rd source) 판정
Architect 미소집(구조/인프라 변경 없음 — 순수 측정 라운드). 3-source 중 Forge 실측 PASS + Self-Adversarial 3건 완료 = **2/3 충족**(AX-008 최소요건). 벤치·look-ahead·oos 통계 3렌즈는 본 note가 자체 커버(Challenge 1 vintage 진단 = look-ahead 렌즈, Challenge 3 oos 렌즈).

## 종합
밸류 추가는 **clean recon basis PG2 북의 전기간 위험조정 성과를 강화(Calmar 0.72→1.14·MDD -7pp·dIR +0.27)하나, 강화의 지배분이 2024+ 역전된 pre-2024 알파에 기인**하고 최근(2024+) 밸류 marginal은 음전환(paired-t -1.3)·OOS retention 3 arm 전부 <<0.7 → **자본 게이트 NO-GO(FQ-046 REJECT 재확인·심화)**. 신규 정보: ① construction 의존성(N20 tilt에선 밸류가 cap-w top-25보다 크게 기여 — cap-w PORT_t 2.74 vs N20 tilt 4.53) ② 오버레이×밸류 방어 채널은 보완(상쇄 아님) ③ production pinned NAV vintage 부풀림 2× 재확인(도훈 결정 재료).
