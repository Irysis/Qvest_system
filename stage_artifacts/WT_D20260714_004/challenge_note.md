# R28 (FQ-041) Self-Adversarial Challenge Note

**규약**: v8.2 Self-Adversarial (Opus 4.8 자체 적대검증, finalize 직전). AX-008 3-source 중 1개. No Silent Override (Charter §8).
**분류**: ACCEPT(위반 수정) / PARTIAL(부분 인정+보완) / REBUTTAL(학술+L-code+정량 3축).

## C1 (task-required) — 재구축이 production frozen과 bit-정합인가 (parity 실패 시 판정 발화 금지)
**concern**: 7팩터 재구축 vs 저장 score_eff parity 미달이면 판정 발화 금지.
**분류: ACCEPT (parity gate 명시 통과 경로 확립 + 미달 basis는 판정에서 격리).**
- 실측: off=+1(same-month) stored-theta parity **median cor 0.913**(R26 fid 0.914 재현), off=0(T-1) 0.612.
- stored-panel basis 판정(off=+1)은 ≥0.90 gate 통과 → 발화 자격. off=0(clean)은 **다른(1개월 이른) vintage의 독립 측정**이지 stored 재현 실패 아님(production _recompute와 동일 convention). 따라서 "off=0에서 stored를 재현했다"는 주장 안 함 — off=0은 apples-to-apples paired diff(6F vs 7F 동일 vintage)로만 소비. **parity 실패 basis로 stored 재현 주장 발화 금지 준수.**
- ★부수 발견: parity가 off=+1에서만 높다는 사실 자체가 stored 패널 = same-month vintage 증거(판정 2).

## C2 (task-required) — C06 제거가 Core sleeve 내부 가중 재분배를 수반 (재분배 방식 = 자유도)
**분류: PARTIAL (재분배 방식 고정 + robustness 이중화).**
- 6F 재구축은 stored theta에서 C06만 빼고 **잔여 3F(C01/C02/C04) sum-normalize**(단일 규칙, argmax 없음). 이는 production `_recompute`의 theta 정규화(`tc/sum(abs(tc))`)와 동일 연산 — 임의 자유도 아님.
- 잔여 인정: renorm은 여전히 하나의 선택. **보완**: theta 2-mode 병기 — (a) stored-theta renorm (b) ic-theta 재계산(production 실제 경로). 두 mode 결론 일치(clean paired IS 0.85 / 0.30, 둘 다 sub-significant) → 재분배 방식에 결론 robust.
- ★R26 recon(remove-only, no-renorm)과 다른 renorm 방식이 R26 holdout 붕괴(-0.60)를 재현하지 않음(clean HO +1.13) → R26 붕괴가 recon-proxy 아티팩트였음을 노출(재분배 방식이 결론 방향은 안 바꾸나 magnitude 노이즈 실재 — PARTIAL 근거).

## C3 (task-required) — holdout 창이 melt-up 국면 편중
**분류: PARTIAL (인정 + 복수 창·복수 basis로 완화).**
- holdout 2024-07~2026-04(21m)은 KR mega-cap 반도체 melt-up 편중([[reference-kr-2025-megacap-semi-regime]]) → cap-w top-25 성과가 국면 특이할 수 있음.
- 완화: 판정은 holdout 단독 아닌 **IS(247m) + holdout 병행 + full**. C06 clean paired가 IS(0.85)·HO(1.13)·full(1.09) 모두 sub-2.0로 일관 → 국면 아티팩트 아님. dual-basis(cap-w + EW-uni)도 병기. holdout은 falsification 확인용(primary는 IS).

## C4 — look-ahead 판정 2가 over-claim인가 (deployed book 자본 판정에 영향)
**분류: ACCEPT (신중 framing + escalate, 단정 아닌 검증권고).**
- 3축 근거(parity 0.913=same-month / factor_db 내부 Date=M-end / controlled PORT_t 2.1×)는 강하나, **"panel 구성 look-ahead" vs "measurement 매핑 look-ahead" 귀속은 미확정** — 어느 쪽이든 admission PORT_t(5.324) 부풀림은 동일.
- ★반증 nuance 명시: stored 패널 clean-forward(M+1) rank-IC t=5.92 > contemporaneous(M) 4.74 = **알파 자체는 진짜 forward 예측력 보유**. look-ahead는 top-25 cap-w PORT_t magnitude 부풀림에 국한. live/forward는 PIT-clean.
- 조치: 단정("PIT 위반 확정") 대신 **judge/PIT-agent 검증 권고 + live NAV corroborate** escalate. self-adversarial이 오히려 over-claim을 억제(magnitude만, 알파 진위 아님).

## C5 — off=0(clean) PORT_t 3.06이 과소평가(내 recon 버그)인가
**분류: REBUTTAL.**
- off=0/off=+1은 **동일 factor_db 파일을 월만 shift**(fdp0 vs fdp1), theta·universe·liq·winsor·align 전부 동일 → controlled. off=0 = production `_recompute` verbatim convention(`format(AS_OF-1,"%Y%m")`). 버그면 off=+1도 동일 버그(상쇄) → 상대 비교 유효.
- 정량 3축: off=0 ic-theta(3.25)와 stored-theta(3.06) 근접(다른 theta인데 일치) · EW-uni(3.77) 정합 · IC t(clean forward 5.92) 정합. L-code: [[reference-book-benchmark-alignment-realized-ym]] 1개월 정렬 이슈 선례.

## C6 — self-rationalization auto-scan
"미미/관행/실무적/보수적이면 OK/대부분 동일" grep → **미사용**. 모든 수치 보고(paired 0.85·3.34, inflation 2.08×, IC t 4.74/5.92). 회피표현 0.

## Self-Adversarial 종합
- HIGH severity: **1건 발동 (look-ahead 판정 2 → Q-Lead/도훈 escalate, PIT 검증 권고)**. C06 본 질문은 clean 미달 = negative(위반 아님).
- escalate trigger: PIT lookahead 의심 → 발동. 단 "확정" 아닌 "judge/PIT 검증 권고"로 신중.
- verdict 방향: 적대검증이 (a) C06 negative 강화(R26 IS-positive = look-ahead 아티팩트 노출) (b) look-ahead over-claim 억제(알파 진위 nuance) 둘 다 수행.

## AX-008 Triangulation
- self-adversarial: PASS (본 note).
- 측정 무결성: weighted_screen_bt/canonical_screen_bt contract(build_benchmark_compare NW lag-3) 실측 = forge 동일 함수. PASS.
- 2/3 충족.
