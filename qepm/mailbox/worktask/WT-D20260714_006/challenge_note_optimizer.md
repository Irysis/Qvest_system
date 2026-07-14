# Optimizer Self-Adversarial Challenge — WT-D20260714_006 (B2_value_nonmega_conditional)

**v8.2 Self-Adversarial (Codex Round 대체, Opus 4.8 native). finalize 직전 약점 자가제기 → 분류 → 처리.**
**AX-008 3-source 중 1개 (Forge·Architect와 함께 2/3 PASS 요구).**
날짜 2026-07-14 / method_selected = EW_top25_bandbuffer_B40 / verdict = SCREENING-TIER (자본 부적격).

---

## 자가제기 약점 (6건)

### C1. method_selected가 net_IR argmax를 뒤집었다 (EW_buf40 1.065 < EW_buf30 1.120 < SOFTMAX 1.167). "screening-tier 서사"에 맞추려 cherry-pick 아닌가?
**분류: REBUTTAL (부분 PARTIAL)**
- SOFTMAX/LINTILT/RANK: 전기간 net_IR 최고이나 **holdout paired 전부 음수**(-0.92/-1.28/-1.55) + oos 0.19~0.24 = **IS-overfit**. Cycle2/DeMiguel mandate("sizing이 SR을 robust 개선했는지 EW 대비 정량비교, 개선 없으면 정직보고")에 따라 disqualify — 서사가 아니라 skill의 명시 규율.
- EW_buf30(1.120) vs buf40(1.065): buf30 turnover 10.81 = hard cap 11.0 대비 **headroom 1.7%**(운영 breach 리스크) + oos 0.173 < buf40 0.181. buf40은 turnover 안전마진(8.91) + oos 우위, net_IR 희생 0.055(미미). Implementation Discipline(⑥) + No-Silent-Override 정합.
- **PARTIAL 인정**: buf40 vs buf30은 순수 net_IR이면 buf30. buf40 채택은 turnover-safety + oos 우선 판단 — 명시 기록함(selection_qualifiers). judge가 재량 판단 가능.

### C2. CAPW_buf40이 oos_retention 0.648(유일 [0.5,0.7) band)·holdout +2.02로 가장 OOS-robust인데 배제했다. OOS 최강을 버린 것 아닌가?
**분류: REBUTTAL**
- CAPW 배포 = **최고알파 A073240(α2.77)@0.5% + mega 3종(삼성/하이닉스/SK스퀘어) 60%**(각 0.20 cap) = **non-mega value 알파의 완전 반전**. B2 논지("non-mega tier value")를 weighting 단계에서 파괴 = closet-index(§6 benchmark-aware construction 교훈).
- CAPW의 oos 0.648은 **알파가 아니라 mega-cap-β artifact** — 2024+ mega-cap 반도체 레짐(reference-kr-2025-megacap-semi-regime)을 cap-w가 올라탄 것. book-marginal |corr|=0.98 >> 0.30 → §3 band 조건부 PASS의 증거요건도 실패.
- ∴ CAPW = **알파 screening 규격(paired 2.378 AND-게이트 재현·검증)으로 보고**하되 배포 부적격. 정직하게 method_comparison·infeasibility.graduation_assessment.caveat에 명시.

### C3. band-buffer B∈{30,35,40,45}×{EW,CAPW} = 8-config sweep 후 선택 = DSR selection 아닌가?
**분류: PARTIAL (ACCEPT-기록)**
- 전략(B2 signal)은 alpha가 chain으로 고정. band-buffer B는 **optimizer 구현 knob이고 primary driver = HARD turnover 제약(feasibility)**. 채택도 net_IR-argmax가 아니라 turnover-safety+oos.
- 단 B=40이 sweep을 본 뒤 결정된 것은 사실 → n_config 8 기록(method_shopping_log), capital 주장 아님(전 config oos<0.7 FAIL)이므로 DSR capital 게이트 미발동. **투명 기록으로 처리** — verdict(자본 부적격) 불변이라 selection bias가 결론을 바꾸지 않음.

### C4. sr_overlay_assumed 1.8은 측정이 아니라 추정이다 (실제 overlay β-schedule 미적용).
**분류: ACCEPT (라벨 명시)**
- overlay(AR_on_M4_R05) β-schedule이 optimizer 입력에 없음 → 후보에 실제 적용 불가. infeasibility.sr_2_5_target.sr_overlay_basis에 **"ESTIMATE (측정 아님)"** 명기 + 근거(98% corr × incumbent 정정후 SR 1.84).
- 오히려 보수적으로도 과대추정 위험: **최근 24m active SR -0.178은 value-vs-mega STYLE rotation 감쇠이지 market crash 아님** → market-timing overlay가 구제 못 함. 즉 1.8도 낙관. SR 2.5 도달불가 결론은 추정 오차에 robust.

### C5. PIT — schedule이 2026-03까지인데 lockbox 2023-12-22 strict. look-ahead 아닌가?
**분류: REBUTTAL**
- lockbox 2023-12-22 = **signal 구성 cutoff**(B2 config theta 0.7/0.3·tier gating이 ≤2023-12-22로 frozen). post-lockbox(2024-01~2026-03) = **genuine OOS/holdout**(IS_END 2024-06-30). walk-forward는 factor_db T-1 off0(production_parity_verified) → 각 시점 미래참조 없음.
- 이것이 holdout 측정의 설계 그 자체(paired_ho·oos 산출 근거). alpha/risk 핸드오프와 동일 규약. overlay_pit_guard 대상(리스크 오버레이) 아님 — 본 후보는 오버레이 미적용 bare.

### C6. turnover 규약이 round-trip이 맞나? (×12/×2 실수 사례 재발 방지)
**분류: ACCEPT (검증 완료)**
- constraint_defaults.json `turnover_hard_fail_annual: 11.0` = **"1100%(11.0/yr round-trip)"** 명시. weighted_screen_bt `traded_t = sum|w_t - w_{t-1}|`(매수+매도 양측) `* 12` = round-trip annual. 선택 TO 8.914 = round-trip. **×12-only 아님, ×2 중복 아님** — 계약 함수 단일 경로 사용, 자체합성 없음.

---

## 분류 요약

| ID | 약점 | 분류 | 처리 |
|---|---|---|---|
| C1 | net_IR argmax 역전 | REBUTTAL+PARTIAL | Cycle2 IS-overfit 배제 근거 + buf40 turnover-safety 명시, judge 재량 |
| C2 | CAPW OOS-최강 배제 | REBUTTAL | 알파반전·closet-index §6, screening 규격으로 보고 |
| C3 | band-buffer sweep | PARTIAL/ACCEPT | n_config 8 기록, capital 미주장이라 DSR 미발동 |
| C4 | overlay SR = 추정 | ACCEPT | ESTIMATE 라벨 + 보수성 명시 |
| C5 | schedule > lockbox | REBUTTAL | lockbox=구성cutoff, post=OOS(설계) |
| C6 | turnover 규약 | ACCEPT | round-trip 검증 완료 |

**Q-Lead escalate trigger 점검**: Hard Constraint 위반 0 (25종/Σw=1/[0,0.20]/long-only/TO 8.91<=11 전부 충족). RF-O9 single-snapshot 아님(268-date). HIGH red_flag triggered 0. AX hard FAIL 0. → **escalate 불요**.

**walk-forward 절대 ACCEPT 항목(Iter1-4 systemic)**: weights.csv as_of_date 시계열 268-date ✓, schedule_density 1.0 ✓ — 위반 없음.

## 결론
weight 최적화는 FEASIBLE(제약 전부 충족). 그러나 후보는 **SCREENING-TIER(자본 부적격)** — 전기간 IR 1.065는 IS/pre-2015 견인, 최근 24m active SR -0.178, oos_retention 0.181(<0.5 무조건 FAIL), book-marginal ~0(98% corr). **SR 2.5 도달 불가**(단독/overlay/book-marginal 전 경로). No silent override — 제약 완화 없이 정직 판정. alpha(holdout dIR -0.022) + risk(98% corr, book-marginal ~0) 정직 prior를 optimizer 실측이 최종 확증.
