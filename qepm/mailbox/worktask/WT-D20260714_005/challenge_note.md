# R29 (FQ-044) Self-Adversarial Challenge Note

**규약**: v8.2 Self-Adversarial (Opus 4.8 자체 적대검증, finalize 직전). AX-008 3-source 중 1개. No Silent Override (Charter §8).
**분류**: ACCEPT(위반 수정) / PARTIAL(부분 인정+보완) / REBUTTAL(학술+L-code+정량 3축).

## C1 (task-required) — clean 재구축 자체의 parity 검증 (R28 recon recipe 의존 리스크)
**concern**: clean base가 R28 recon(parity 0.913)에 의존 → recon fidelity 부족이 판정을 오염시키는가.
**분류: ACCEPT (파이프라인 독립 검증으로 해소).**
- R27 exact 재현(STORED 패널 base[non-recon] + pure_factor_scores value): paired **3.738**(R27 3.807) · IS 3.107(3.171) · HO 4.357(4.300) · dIR 0.458(0.481). 노이즈 내 정확 재현 → **파이프라인 유효**.
- vintage 격리는 **controlled recon off+1 vs off0**(동일 파이프라인, factor_db 월만 교체)로 수행 — R28 C5 rebuttal 계승(버그면 양쪽 상쇄). off+1→off0 base swap 단독으로 paired 2.23→1.02(stored)·2.59→1.33(ic).
- ★ recon parity 잔차(3.738 stored → 2.226 recon-off+1)는 **vintage 아님 recon-fidelity**로 명시 격리 — 판정은 recon-내부 controlled 비교(off+1 vs off0)에 근거, stored의 정확 3.807은 파이프라인 검증용으로만 소비. clean 판정(1.02~1.72)은 recon parity 부호를 바꾸지 않음(전 clean cell < 2.0, LA cell 전부 > 2.0 — vintage 효과가 parity 노이즈 지배).

## C2 (task-required) — Z6가 clean에서 죽으면 R27 placebo(p=0)/lag1(2.98) 통과를 어떻게 설명 (기전 정합성)
**분류: REBUTTAL (완전 정합, 모순 없음).**
- R27 placebo/lag는 **VALUE 신호 무결성**만 시험: shuffle → paired 음수 붕괴(=value 실재), value 1개월 shift 생존(=value PIT-safe). **그 두 결론 R29에서 유지** — vz_pfs = factor_db T-1 clean **cor 1.0000**(정량 3축 ①). value self-seam 0.985(②). R29 primary lag1 = 1.530(value shift 생존, R27 방향 재현 ③).
- R27이 시험하지 **않은** 것 = BASE 패널 vintage. R28이 base=same-month 검거([[project-riskoverlay-multilayer-bearprob]] 계열 — placebo/OOS가 못 잡는 vintage look-ahead는 controlled A/B만 판별). 학술: Newey-West paired-t는 신호 유의성 측정이지 vintage 진단 아님(측정 무결성 = measurement-graduation §1).
- ★기전 정량: look-ahead base가 value 오버레이 dIR을 **~2배 증폭**(clean 0.153 vs LA 0.345). value는 진짜·clean인데 그 한계 paired 기여가 LA base 위에서 부풀려 측정됨 → "clean에서 죽음"과 "placebo/lag 통과" 동시 성립. 모순 아님.

## C3 (task-required) — holdout 창(2024-07~2026-03) melt-up 편중
**분류: PARTIAL (인정 + 판정 무의존으로 완화).**
- holdout은 KR mega-cap 반도체 melt-up 편중([[reference-kr-2025-megacap-semi-regime]]) → cap-w top-25 국면 특이 가능.
- 완화: primary 판정은 **IS(0.918)·HO(1.075)·full(1.243) 전부 < 2.0 일관** → holdout 국면 아티팩트 아님. R27 HO 4.357의 강세가 오히려 melt-up 편승 의심 대상이었고(R27 verdict 자인), clean base에서 HO도 1.08로 소멸 → **melt-up 편중이 R27 HO를 부풀렸을 가능성까지 clean이 억제**. 판정은 IS-primary(0.92)로 holdout 무의존.

## C4 (자발) — "value dead" over-claim 방지 (fail 방향 framing 규율)
**분류: ACCEPT (config-scoped negative framing 엄수, 종결 어휘 금지).**
- clean paired 미달은 "value=dead/소진/dead-end"가 **아니다**. 정량 반증: clean에서도 variant PORT_t 3.06→3.85(+), dIR +0.153(+), EW-uni pt **6.39**(강). value 신호 실재·clean.
- 정확 framing: **cap-w top-25 paired NW-t 기준 config-scoped negative** + cap-tier 국소화 프론티어(EW-uni 6.39 >> cap-w 3.85). next_probe P1(cap-tier-conditional 소비)로 프론티어 열림 표시. answer-principles 리서치 연속성(종결 어휘 금지) 준수.

## C5 (자발) — LA-value(vz_off1) 음수 paired가 off1 추출 버그인가 (primary 오염 리스크)
**분류: REBUTTAL (primary 무관 + 버그 아님).**
- clean_base+LA_val paired −3.27은 **어느 판정 cell에도 미사용**(vz_off1 = look-ahead 입력, production 경로 아님, decomposition 완전성용).
- 버그 아님 정량 3축: off0/off1 coverage 거의 동일(IS 60495 vs 60431; HO 5649 vs 5656) · 양쪽 2026-06까지 finite · off1−off0 mean abs diff 0.131. 음수는 inconsistent-vintage blend(clean base + 동월 value) 아티팩트 — 진단 curiosity.
- ★primary(vz_off0)는 vz_pfs와 **cor 1.0000**이고 vz_pfs가 R27 3.807을 재현 → primary value 정확성 독립 확증. off1 오딧이 off0 오염 불가.

## C6 — self-rationalization auto-scan
"미미/관행/실무적/보수적이면 OK/대부분 동일/영향미미" grep → **미사용**. 모든 수치 실측 보고(paired 1.02~3.74, cor 1.0000/0.985, inflation 2.08×, dIR 0.153/0.345). 회피표현 0.

## Self-Adversarial 종합
- HIGH severity: **0건 신규 발동** (R28 look-ahead escalate는 R29가 확정·검증 완료 = de-escalate to CONFIRMED). PIT 위반 = historical 저장 패널 한정, live forward는 clean.
- escalate trigger 점검: AX axiom hard FAIL 0 / PIT C1 위반(live) 0 / HIGH severity <5 → escalate 불요. 단 **판정 자체가 book pinned 6.130 clean-basis 재산출 필요를 노출** → FQ-044 후속(P2) + 도훈 결정 재료로 surface(escalate 아닌 정보 보고).
- verdict 방향: 적대검증이 (a) clean FAIL 강화(vintage swap controlled) (b) "value dead" over-claim 억제(clean dIR+·EW-uni 6.39) (c) 파이프라인 검증(R27 3.738 재현) 3중 수행.

## AX-008 Triangulation
- self-adversarial: PASS (본 note).
- 측정 무결성: weighted_screen_bt/canonical_screen_bt contract(build_benchmark_compare NW lag-3) = forge 동일 함수. R28 산출(recon_panels/screen_inputs) 재사용. PASS.
- 2/3 충족.
