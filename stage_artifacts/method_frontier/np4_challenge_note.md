# FQ-057 NP4 — Self-Adversarial Challenge Note (v8.2)

라운드: MVO Σ-입력 swap paired A/B (lw_linear vs lw_nls) · optimizer-research lane
작성: 2026-07-18 (finalize 직전) · 사전등록 `np4_preregistration.json` (불변) · pin `fq057_20260718_171024`

## 자가 제기 약점 및 분류

### C1. 알파 선택 의존성 — 죽은 알파 위에서의 Σ 검정력 (PARTIAL)
12-1 모멘텀 단일 알파는 post-2017 양 arm 모두 사망(S1 A_post_t −0.25 / B_post_t −0.31). 평균-축 개선 검정력이 낮은 기질 위에서의 NULL이다.
**보완**: (a) verdict는 config-scoped로만 라벨 — "Σ 정보는 원리적으로 무가치" 주장 없음. (b) 단 위험-축 효과는 같은 기질에서 **검출됨**(실현 net vol 31.4%→30.0%, active vol 26.3%→25.5%) — 도구가 무검정력이 아니라, 이전이 위험-축에서 멈춘다는 것이 실측이다. (c) pre-2017(알파 생존 구간, A_pre_t 2.53) 부기간 paired도 −0.88로 개선 부재 — "알파가 살아있을 때도 Σ-swap이 평균을 못 움직였다"는 별도 근거.

### C2. μI-arm 해석 혼재 — 'Σ A/B'가 아니라 '알파비례 vs 상관인지 MVO' (ACCEPT, 해석 제약으로 수용)
S1에서 arm A(linear LW)는 p>n 퇴화로 사실상 ridge/알파-정렬 MVO다(경고 198/198 실측). 따라서 S1은 순수한 "나쁜 Σ vs 좋은 Σ"가 아니라 "상관구조 무시 vs 보존"의 A/B다.
**수용 논리**: 그것이 바로 현행(.get_cor_cov ledoit_wolf)의 실동작이므로, 운영 질문("incumbent 입력을 lw_nls로 바꾸면 좋아지는가")에는 정확히 답한다. 그리고 S2(p=50<n=60, 비퇴화 영역)가 이 혼재 없는 대조군인데 거기서도 paired −0.89 NULL — 해석 혼재가 결론을 바꾸지 않는다.

### C3. 60개월 윈도·λ=2.0 임의성 (REBUTTAL — 사전등록·관례·비-sweep 3축)
윈도/λ를 흔들면 결과가 달라질 수 있다는 지적.
**반박**: (a) 60m는 FQ-057 harness 규약 미러(paired 서열의 근거 유지) + Ledoit-Wolf horse-race 관례. (b) λ sweep은 2-arm 가설주도 사전등록 위반(sweep 재분류 유발) — 의도적으로 미실시. (c) 미검 축임은 limitations에 정직 기록. 판정은 이 config에 국한.

### C4. min_names=15 엔진 개입이 포트 형상 지배 (PARTIAL — 신규 발견으로 기록)
λ=2·이 알파 스케일에서 QP는 corner 해(소수 종목 bound)로 가고, min_names=15 fill + HHI projection이 최종 형상의 상당 부분을 결정(S2 mean_n 정확히 15.0 = fill 상시 바인딩). Σ의 역할이 기계적으로 희석된다.
**보완**: 측정 대상이 "registry에 배포된 그대로의 MVO"라는 점에서 운영 질문에는 유효하나, 일반화 한계로 verdict limitations에 명기. 파생 발견 2건(HHI max_names 누출·turnover_penalty 미배선)은 task 발행(task_1b9e50a3 / task_89b2050e).

### C5. NA→0 처리 27,705 셀 (PARTIAL)
전체 수익 행렬(전 종목×전 월)의 NA→0은 대부분 비보유/비멤버 월. 보유 종목은 60m 완전성 요건 통과분이라 익월 NA는 상폐 등 소수. 양 arm·벤치에 동일 적용 → paired diff에는 구조적 중립.
**보완**: 카운트를 metrics에 기록. 벤치 하방 편의 가능성은 양 arm active에 동일하게 걸려 paired 판정 불변.

### C6. HHI workaround의 사전등록 이탈 (ACCEPT — 문서화된 이탈, 완화 아님)
사전등록은 hhi_cap=0.10을 mvo_weights 인자로 명시했으나, 엔진 결함(C4의 누출) 때문에 support-제한 `.project_hhi` 후처리로 대체.
**수용 논리**: HHI≤0.10 의미는 보존(25-name support 내), 양 arm 완전 동일 적용, 본 노트·verdict에 공개 기록 — silent relaxation 아님. Hard Constraints(25종/long-only/[0,0.20]/Σw=1)는 매 리밸 stopifnot 감사 통과.

## Escalation 판정
- Hard Constraint 위반: 없음 (run_02 감사 792셀 전량 PASS · one-way 회전율 8.7~10.3/yr ≤ 11.0)
- RF-O9 single-snapshot: 해당 없음 (198 as_of 월간 walk-forward 시계열)
- HIGH ≥5 / AX hard FAIL ≥3: 미해당 → Q-Lead escalate 불요

## 결론
분류 집계: ACCEPT 2 (C2·C6) / PARTIAL 3 (C1·C4·C5) / REBUTTAL 1 (C3). verdict(NULL_config_scoped, 사전등록 매핑 그대로) 유지 — finalize 승인.
