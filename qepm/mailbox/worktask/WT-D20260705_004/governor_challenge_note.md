# Governor Self-Adversarial Challenge — WT-D20260705_004

**verdict finalize 직전 자기 적대검증** (v8.2 — Opus 4.8 native adversarial reasoning, 외부 Codex 없음).
**경량 근거**: verdict=GOVERNOR_REJECTED. REJECT는 book_state 쓰기 없음 = 자본 비가역 게이트 아님 → 경량 challenge 적용(measurement-graduation §4 정합).

## 입력 사실 (authoritative)
- judge: JUDGE_FAILED / graduation_capital / grade C. Gate C FAIL(PORT_t 0.970<2.95) + Gate F FAIL(oos_retention −0.604<0.7). graduation HARD 3/3 미달.
- forge (authoritative): PORT_t 0.9698 full / −0.7248 recent2017. graduation_gate verdict=FAIL.
- book_state: incumbent `STR_1715_on_M4_R05_noLayer4_PG2` / incumbent_book_ir 1.416 / n_admitted 1.
- before-hash: `fef4718d162605f722f36d47203f24f5f9a3c26f877e70f2369da1b22244b8c0`

## 자기 비평 3건 (devil's advocate) + 자율 분류

### C1 — Replacement vs Sequential Admission 룰 미스매치 위험 (Iter 5 사례 재현?)
- **비평**: 본 WT가 replacement 본질(incumbent 대체)이면 Sequential Admission gate(TDC/Pareto)가 아닌 직접 SR/CAGR/MDD/Harvey 비교 + DSR post-penalty가 적용되어야 한다. 잘못된 룰로 판정하면 Iter 5식 룰 미스매치.
- **분류: REBUTTAL**. 본 WT 본질 = incumbent(score_eff composite) 위에 **uncertainty-aware selection/sizing 차원 추가**(judge attribution: WT 기여도=uncertainty 차원, delta_PORT_t = −0.404 full / −0.472 recent). incumbent 대체가 아니므로 1차적으론 Sequential Admission 성격. **그러나 룰 논쟁이 verdict를 바꾸지 않는다** — 어떤 룰이든 **standalone graduation HARD 3종 전부 미달**(PORT_t 0.97·oos −0.604·calmar 0.418): Replacement 룰(직접 SR/Harvey 비교)로도 REJECT(PORT_t 0.97≪2.95), Sequential Admission 룰(book-marginal ΔIR)로도 standalone FAIL이라 book-marginal 진입 자체 불가. **Iter 5와 상이**: Iter 5는 룰 선택이 DEFER↔ADMIT을 결정했으나, 여기선 standalone FAIL이 압도적 = 룰-불변 REJECT.

### C2 — single-axis 압도적 우월 / Lockbox probe 예외 해당?
- **비평**: weighted_score<0.65인데 single axis(rank-IC t 4.11 / Harvey / DSR)가 압도적 우월하면 인정 권장. Lockbox 구조적 unavailable이면 probe phase 인정(DEFERRED 자동거부).
- **분류: ACCEPT (verdict 불변)**. rank-IC t 4.11은 advisory — long-only 실현 alpha(portfolio-alpha t=0.970)로 전이 실패했고, 이것이 정확히 본 WT가 공략하려던 "IC→PORT_t 전이 벽"에서 refuted된 지점. authoritative axis(PORT_t) 자체가 FAIL이므로 single-axis 우월 예외 미해당. Lockbox는 forge/judge에서 정상 측정됨(recent2017 OOS = frozen weights extension 동형, oos_authoritative_port_t −0.7248 실측, oos_chart 연속) → 구조적 unavailable 아님 = probe 예외 미해당. **DEFERRED 자동거부 조건 부재** = 정상 REJECT.

### C3 — book_state 무변경 실증 누락 위험 (감사 gap)
- **비평**: REJECT는 애초 book write 없다고 선언하나, "쓰지 않았다"를 실증 안 하면 감사 gap.
- **분류: ACCEPT (조치 이행)**. before-hash 캡처 + governor_package 작성 후 after-hash 재측정 → before==after 실증. book_state.json에 대한 Write/Edit 도구 호출 0건.

## escalate 판정
- HIGH 2 미만 · AX hard FAIL 0 · 룰 미스매치 실체 없음(룰-불변 REJECT) → **escalate=false**.
- Q-Lead escalate 트리거(Replacement vs Sequential Admission 혼동 / book-marginal<0.05 but single-axis robust 우월) 어느 것도 미해당.

## admission rule 적용 명시
- **적용 룰**: standalone graduation gate (measurement-graduation §3 HARD 3종). standalone FAIL이 압도적이라 Replacement/Sequential Admission 룰 논쟁 moot(룰-불변). book-marginal ΔIR 게이트는 standalone ADMIT 전제 미충족으로 진입 불가(§4).
- **PG1 verdict**: REJECT.
