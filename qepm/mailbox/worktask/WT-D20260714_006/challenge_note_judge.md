# Judge Self-Adversarial Challenge — WT-D20260714_006 (B2_value_nonmega_conditional)

**v8.2 Self-Adversarial (Codex Round 대체, Opus 4.8 native). judge_verdict finalize 직전 자가 적대검증.**
**AX-008 Verification Triangulation: Forge(실측 확증) + Self-Adversarial(본 노트) = 2/3 PASS (Architect 미소집).**
날짜 2026-07-14 / 판정 초안: **JUDGE_FAILED (graduation FAIL, 자본 NO-GO) / essence Grade B (Component) / screening-tier retain**

핵심 실측 (forge-authoritative 계약값): PORT_t(NW lag-3) 2.7388 <2.95 · oos_retention(lockbox 실 OOS 주입) **−1.191** <0.5 무조건 FAIL · Calmar(계약 daily) 0.3784 <0.64 · Sharpe 0.922 · CAGR 21.3% · MDD 56.4% · net_IR 0.599 · TO 8.90 · DSR(N=41 deflate) 0.729.

---

## 자가제기 약점 (6건)

### J1. Grade B가 관대한가 — MDD 56.4% + lockbox active 완전 역전인데 F가 아닌가?
**분류: ACCEPT (판정 영향 없음 확인)**
- Grade 권위 = essence_score. hard_fail 추론은 MDD 깊이 단독이 아닌 구조적 낙폭(catastrophic ≥70% / severe45 에피소드 ≥15 / severe55 ≥6 / 점유 ≥25%) — 실측 severe45=4, severe55=2, 점유 0.63% → structural 아님, `tail_review=TRUE` 라벨.
- Grade B = "Component (PORT_t≥2.0 ∧ net_IR>0.2, A 미달)" — 블렌드 재료 가치 표시일 뿐 자본 편입 아님. 판정(REJECT)은 Grade와 무관하게 HARD 3종 전패로 확정. verdict에 tail_review + lockbox active inversion 명기로 처리.

### J2. chain 자격요건 ②(IS-only 변형선택) 미충족 — B1/B2 선택이 full-period AND-게이트(2024+ 겹침 포함) → sweep 재분류해야 하는 것 아닌가?
**분류: PARTIAL (flag 기록 + sensitivity 실행)**
- 정당 지점: B1 vs B2 판별이 full-period paired(홀드아웃 겹침 기간 포함)로 이뤄짐 — chain ②의 IS-only 원칙에 부분 미충족. 단 (a) 명시 holdout(2024-07+) dIR은 선택에 사용되지 않았고 음수(−0.022)임에도 B2가 정직 보고됨, (b) n_trials 소수(4)·사전등록 sha256 존재.
- **sweep 재분류 sensitivity 실행 완료**: essence_score(selection_type="sweep") → Grade B 불변, DSR 0.729 ≥ 0.5로 게이트로도 통과. method_shopping penalty(optimizer 8 family × 0.05 = 0.40) 적용 시 DSR_adj 0.329 <0.5 — 그러나 REJECT는 HARD 3종에서 이미 확정이라 verdict 불변. judge_verdict에 chain-qualification flag + 양측 수치 기록.

### J3. forge run_all.R의 손계산 monthly 집계(prod/cumprod, 수동 SR 함수) — backtest-contract 자체합성 금지 위반 아닌가?
**분류: PARTIAL (라벨 경고 부착)**
- 권위 지표는 전부 계약 경로(build_bt_result daily) 산출이며 judge는 계약값만 채택 — 판정 오염 없음. 손계산치는 SR Provenance Mandate 병기용.
- 단 `forge_realized.mdd 0.4467`(monthly 손계산)과 계약 MDD 0.5641(daily)의 괴리가 후속 인용 혼동 위험 → judge_verdict에 "인용은 계약 daily 기준" 경고 명기. 위반 판정까지는 아님(provenance 병기 + 계약 우선 구조 유지).

### J4. lockbox 실 OOS 주입(oos_retention −1.19)이 v2 splits(−0.25)와 크게 다른데 어느 쪽이 권위인가?
**분류: REBUTTAL (mandate 명시)**
- judge mandate: "lockbox 실 OOS는 oos_is_ratio_override 주입" — lockbox(2024-01+) 실측 active IR 비율(−1.0906/+0.9155)이 배포 관점의 진짜 OOS. v2 splits는 참고 병기. **두 값 모두 <0.5 무조건 FAIL 영역** — 게이트 결론 동일, 상충 없음.

### J5. dual-basis(v8.3 M2): EW-uni PORT_t 6.588 생존 — 이 기각이 cap-w 벤치 아티팩트 아닌가?
**분류: PARTIAL (기각 유지 + 라벨 병기 의무 이행)**
- EW-uni full-period 생존(6.588)은 실재 — 기각 사유에 "cap-w 벤치 구성 미스매치 가능" 라벨 병기 + screen_route=OVERLAY_CANDIDATE(value_z non-mega slotting feature 보존) 재분류 부기.
- 단 기각 자체는 유지: (a) cap-w HARD 판정 권위 불변(v8.3 M2 명문), (b) EW-uni에서도 oos 0.512 <0.7, (c) lockbox 기간 active 역전은 배포 basis 실측(스타일 감쇠는 벤치 선택과 무관하게 2024+ 실현), (d) incumbent와 active corr 0.98 → book-marginal ~0은 벤치 무관.

### J6. AX-001 v2 오적용 여부 — 방어형 조건부 평가를 전기간 지표로 기각한 것 아닌가?
**분류: REBUTTAL**
- 본 후보는 방어형 팩터가 아니라 core book + value 틸트(공격형 스타일 변형). crisis_alpha 청구 없음 → 전기간/OOS 평가 적법. AX-001 v2 해당 없음.

---

## 분류 요약

| ID | 약점 | 분류 | 처리 |
|---|---|---|---|
| J1 | Grade B 관대 의혹 | ACCEPT | essence 권위 + tail_review 명기, REJECT 불변 |
| J2 | chain ② 미충족 → sweep 재분류 | PARTIAL | sensitivity 실행(B 불변·DSR 게이트 통과), flag 기록 |
| J3 | forge 손계산 병기 | PARTIAL | 계약값만 권위 채택 + 인용 경고 |
| J4 | oos override vs v2 splits | REBUTTAL | mandate 명시, 양측 다 FAIL 영역 |
| J5 | EW-uni 생존 = 벤치 아티팩트 의혹 | PARTIAL | 기각 유지 + 미스매치 라벨 + screen_route 병기 |
| J6 | AX-001 v2 오적용 | REBUTTAL | 방어형 아님 — 해당 없음 |

**Q-Lead escalate trigger**: HIGH 0 (<5) · AX axiom hard FAIL 0 (<3) · PIT C1 hard violation 0 → **escalate 불요**.

## 결론
REJECT(graduation FAIL) 판정은 6건 적대검증 전부에서 생존. Grade B(Component)·screening-tier retain·dual-basis 라벨 병기로 finalize.
