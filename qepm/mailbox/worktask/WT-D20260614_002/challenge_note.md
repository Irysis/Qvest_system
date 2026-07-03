# Alpha Challenge Note — WT-D20260614_002 CORE_COMPOSITE

**Agent**: alpha-research (Q-Lead spawn)
**Codex Critic Round**: GPT-5.5 xhigh — stance **REVISE** (veto_flag=false)
**Resolution**: 3 ACCEPT + 1 PARTIAL + 2 REBUTTAL + 1 rationalization self-audit. No Silent Override (Charter §8).

---

## Codex weakest_assumption (Codex 자기 진술)
> "A standalone-failed, single-snapshot core composite can become valuable through overlay or blend marginal IR solely because measured active correlation to the incumbent is 0.265."

→ 부분 타당. 본 package는 'corr 0.265 → 자동 가치'를 주장하지 않음. 주장은 (a) 'corr 1.0 동일스트림' 전제 **반박** (b) standalone 자본 부적격 **확정** (c) overlay/blend 가치는 **risk/optimizer가 판정할 미래 가설**(라벨)이지 alpha 산출 결론 아님.

---

## Concern Disposition (9개 중 실질 6 + self-audit)

### [C1] single-snapshot alpha_scores — **ACCEPT**
- 인정: 역할 prompt는 multi-sig-date panel 기대. draft alpha_scores.parquet은 as_of 2026-05-31 단일.
- 조치: `stage_artifacts/WT-D20260614_002/alpha_ic_panel_walkforward.parquet` 생성 — **256개월(2005-01~2026-04) walk-forward 월별 IC panel** (in-universe K200∪KQ150, PIT forward returns). alpha_scores.parquet은 의사결정 snapshot(정상), 검증 panel 별도 첨부.

### [C2] not graduation-ready — **REBUTTAL (동의·수정불요)**
- Codex가 본 package의 자체 finding을 재진술. package는 이미 `verdict=STANDALONE_GRADUATION_FAIL` + weaknesses_carry에 PORT_t 1.694<2.95 / oos −0.516 / calmar 0.356 명시.
- 이는 alpha-research 역할의 **실패 정직보고**(AX-000 정합)이지 약신호 promote 아님. 수정 불요.

### [C3] weak mechanism (no ablation) — **ACCEPT (핵심)**
- 인정: AXIS-MOM-WEAK flag를 ablation 없이 주장했음.
- 조치: leave-one-family ablation 256개월 실행 (IC-basis):
  | set | meanIC | vs FULL |
  |---|---|---|
  | FULL (10f) | 0.0265 | — |
  | drop_quality | **0.0074** | **−72%** (지배 동인) |
  | drop_momentum | 0.0262 | ~0 (**noise 확정**) |
  | drop_value | 0.0310 | +17% (한계 음) |
  | DQV6 (6f, no mom) | 0.0262 | ~FULL |
  | best Q04 alone | 0.0221 | − |
- **결론**: 10팩터 EW는 compact DQV6를 IC로 능가 못함. momentum 3팩터 = dilution. Factor-Zoo 축소(research_philosophy ①) 권고. [학술: Harvey-Liu-Zhu 2016 / KR momentum 취약은 메모리 L-code 기록 정합]

### [C4] universe not closed — **PARTIAL**
- 인정: top-30 @2026-05 중 **16/30(64%)만 K200∪KQ150** (AS-mode universe='ALL'이 mid/small ~36% 누출). n=30 vs deployment max 25.
- 조치: universe audit 첨부. n=30→25 = **역할분리**(alpha는 top-universe 전수 score 생성[Charter hard_constraints_awareness], 25-cap + in-univ restrict는 Optimizer enforce). deployment restrict 의무 명시.

### [C5] path-to-value relies on weights/cov absent — **REBUTTAL (역할경계)**
- weights.csv / covariance.parquet / risk_package / optimization_package는 **risk/optimizer agent 산출물**이며 alpha-research에 **hook-금지**(agent_role_guard, strict_prohibitions 1~3, 시스템 prompt §15). alpha가 생성 시 AX-002 위반.
- 'overlay/blend marginal IR로 가치 가능'은 measurement-graduation §3에 정의된 `screen_route` mechanism 라벨(미래작업)이지 alpha 산출 주장 아님. AX-008 triangulation은 forge/judge 책임.

### [C6] no sector/size-neutral IC test — **ACCEPT**
- 조치: **sector-neutral IC retention 79.4%** (raw meanIC 0.0265 → SN 0.0211), RF-A4 30% threshold 크게 상회 → PASS. 알파는 섹터 베팅 아닌 종목선택력.
- size-neutral은 mcap 단일 control로 sector-neutral과 高중복 → sector-neutral로 대표(보수적). crowding은 risk-research 영역(중복 산출 금지).

### [self-audit] rationalization_red_flags — **1건 보완**
- Codex flag: "screen_route candidate" / "OVERLAY_CANDIDATE" / "blend marginal IR" / "real diversification potential" / "Conservative: use authoritative net_ir".
- self-check 결과: 앞 4개는 헌법 정의 mechanism(measurement-graduation §3) 또는 정량 근거(active corr 0.265)로 회피표현 아님.
- ★단 **"Conservative: use authoritative net_ir"** (alpha 스케일링 주석)는 soft self-rationalization 소지 인정 → 보완: alpha_vector는 Grinold IC×σ×z 스케일(IC_MEAN 0.0384, σ 0.12 calibration 가정)이며 절대 alpha 수준은 **진단 보조이지 admission 수치 아님**. admission 권위 = forge portfolio_alpha_t 1.694.

---

## Escalation Protocol check
- HIGH severity concerns: 4 (C1/C2/C3/C4) < 5 → escalate trigger 미발동
- AX axiom hard FAIL: AX-007 1건(single-sleeve top20 mechanism) — 단 본 alpha는 multi-axis composite로 AX-007 EXCLUSION 예외(>50 분산 아니나 multi-sleeve 후보) → hard FAIL ≥3 미달
- PIT C1(lockbox/lookahead): 위반 없음 (C13/C14/C15 PASS) → escalate 불요
- Codex stance=REVISE (REJECT 아님) + rebuttal ALL 아님(혼합) → 자동 Q-Lead escalate 미발동
- **결론**: Q-Lead escalate 불요. 정상 finalize.

---

## Final verdict
**STANDALONE_GRADUATION_FAIL** (정직 확정) + **신호력 존재**(SR 0.848, sector-neutral IC PASS) → screen_route = OVERLAY_CANDIDATE / blend.
핵심 산출: ① 'corr 1.0' 반박(active 0.265) ② mechanism 정량화(quality 지배/momentum noise) ③ Factor-Zoo 축소 권고. risk/optimizer로 진행.
