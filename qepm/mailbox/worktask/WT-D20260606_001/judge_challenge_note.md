# Judge Challenge Note — WT-D20260606_001 (Codex Critic Round)

**Charter §8 No Silent Override.** Codex (gpt-5.5, high reasoning) stance = **APPROVE_CONDITIONAL**, verdict_correctness = **CORRECT_WITH_REVISIONS**, ax_violations = **[]**, 3 concerns (1 MEDIUM + 2 LOW). All 8 listed agreements confirm the substantive verdict. No REVISE/REJECT — this is a confirming critique requesting framing precision only.

**Escalation check**: HIGH severity ≥ 5? NO (0 HIGH). AX hard FAIL ≥ 3? NO (0). PIT C1 lockbox/lookahead violation? NO (Gate A C1-C14 PASS; C15 is procedural/sanctioned-path, Codex C3 agrees). **No Q-Lead auto-escalate triggered.** The verdict itself IS a graduation block (JUDGE_FAILED) — that is reported to Q-Lead as the deliverable, not an escalation.

---

## C1 (MEDIUM) — Book-level Grade B vs sleeve-level failure partially conflated — **ACCEPT**
**Codex**: Grade B (book) and "sleeve adds no incremental return / should not graduate" should be explicitly separated; Grade B is not positive evidence for the new sleeve.

**Disposition**: ACCEPT. Codex is right that the two must not be read as one claim. The draft already states this (Gate C "PASS-but-NON-DECISIVE", attribution `factor_vs_selection`, Ground 3) but I sharpen it in the final:
- **Grade B = blended-book measurement outcome under essence_score contract, DOMINATED by the frozen R05 leg (0.85).** It is NOT positive evidence for the new residual-mom sleeve.
- The new sleeve's own admission case is blocked by: incremental book-vs-R05 return NEGATIVE IS (-1.85%/yr, t-2.17) / FLAT OOS (t+0.09), and ΔIR not robust (+0.059/-0.006).
- **3축 근거**: (정량) incremental t -2.17 IS / +0.09 OOS from forge_package; (계약) essence_score.R reads bt_result of the BOOK (0.85 R05 + 0.15 sleeve), so B describes the book; (구조) AX-007 — single sleeve is the unit, but R05 dominance means book metrics ≠ sleeve metrics.

## C2 (LOW) — 2024-01 lockbox negative active SR = corroborating, not sole hard gate (n=29 short) — **ACCEPT**
**Codex**: The binding hard fail is the 65/35 contract retention (0.216); the 2024-01 lockbox (-0.149, n=29) is corroborative stress, not an independent statistical disqualifier given the short OOS window.

**Disposition**: ACCEPT. Statistically correct — n=29 months is a thin OOS window for a standalone significance claim. The **binding, contract-authoritative gate is the 65/35 active retention = 0.216** (essence_score.R default split, which I independently reproduced from bt_result.rds). The 2024-01 lockbox -0.149 is the true-deployment-boundary CORROBORATION (and it matches forge's -0.149 exactly), but it is framed as confirming stress evidence, not the sole decisive number. Both are << 0.7; the verdict does not hinge on the short window.
- **3축 근거**: (정량) 65/35 retention 0.216 over OOS 2018-08..2026-05 (94 months) vs lockbox 29 months; (학술) Bailey-López de Prado — short-window OOS SR is high-variance; (계약) essence_score.R uses 65/35 as the authoritative split unless `oos_is_ratio_override` is injected.

## C3 (LOW) — C15 block must stay explicitly procedural, not performance-validity/lookahead — **ACCEPT**
**Codex**: Keep C15 as an auditability/reproducibility (sanctioned-path) block; avoid any wording that reads as invalidating the measured numbers.

**Disposition**: ACCEPT — this is exactly my draft position (Gate_A_PIT C15: "SANCTIONED-PATH violation, NOT a PIT-correctness/lookahead violation … Measured numbers are NOT invalidated by C15"). I reinforce the label in the final: **C15 = auditability/reproducibility graduation precondition (load_month_factors rebuild + C14 cert), NOT a performance-validity or lookahead block.** The numbers stand; the path must be remediated before graduation.
- **3축 근거**: (정량) byte-identical Z_Score cache, IC computed by alpha script from forward realized returns (no connector IC/Usable_Date path used); (rule) `.claude/rules/pit.md` C15 + `factor-db.md` C15 (sanctioned path = load_month_factors); (process) alpha challenge_note C1 PARTIAL ACCEPT + status.json blocker explicitly name the rebuild as a graduation precondition.

---

## rebuttal_required (5 items) — disposition
1. "Confirm essence_score uses ACTIVE OOS-retention not total" — **CONFIRMED**. Judge read essence_score.R lines 84-93: retention computed on `a <- ret_net - benchmark_ret` (active series), 65/35 split. Total-series retention (0.757/1.293) is NOT the gate. Independently reproduced.
2. "Binding fail = 65/35; lockbox = corroborative" — **DONE** (C2 above).
3. "Document C15 remediation required even if byte-identical" — **DONE** (C3 above; final Gate A + graduation Ground 2).
4. "Separate book vs sleeve evidence (PORT_t 4.90 ≠ residual-mom validation)" — **DONE** (C1 above; final Gate C + attribution).
5. "Confirm no additional AX-001 v2 / AX-007 / AX-008 / builder-PIT violations" — **CONFIRMED**: AX-001 v2 N/A (not a defense/conditional-metric claim; momentum sleeve, no crisis-alpha claim — risk explicitly says NOT defensive). AX-007 re-confirmed (single-sleeve top20 ceiling) but the WT targets the multi-sleeve EXCLUSION path, so not a fresh violation — just unproven. AX-008 satisfied (Forge + Codex + Judge independent; Judge re-computed, not rubber-stamped; 3/3 concur). Builder-level M08 PIT recheck = an OUTSTANDING precondition (Codex alpha C7, alpha challenge_note C7 REBUTTAL "PROBABLE PASS builder-unverified") — flagged, not a confirmed violation. No NEW AX/PIT violation introduced.

## 자기합리화 자동 검출 (grep: 미미/관행적/실무적/보수적이면/대부분 결과 동일)
- No rationalization phrases in the verdict. The verdict is a FAIL (no incentive to rationalize toward pass). "NEGLIGIBLE" appears only when quoting forge's CAGR/vol SR divergence (scoped correctly per forge C7). Clean.

## No Silent Override 준수 확인
- 3 concerns 전부 명시 분류 (ACCEPT 3 / PARTIAL 0 / REBUTTAL 0). 5 rebuttal_required 전부 응답. 침묵 무시 0건. Codex APPROVE_CONDITIONAL → framing 정밀화만 반영, 실질 verdict 불변 (JUDGE_FAILED / Grade B / graduation BLOCKED).
