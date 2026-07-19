# FQ-063 Self-Adversarial Challenge Note (v8.2 — Opus 4.8 자체 적대검증)

**라운드**: lw_nls 기반 비중결정 방법 선택이 canonical PORT_t로 유의한가 (method-frontier, optimizer-research)
**판정**: `config_scoped_negative` — best-of-sweep(A_CVaR 0.906)이 baseline(LinearTilt 1.756, prodLT20 2.082) 미달. 27셀 graduation HARD 0/27·DSR 0.247 FAIL.
**AX-008**: 3-source(Forge·Self-Adversarial·Architect) 중 self-adversarial 1축.

finalize 직전 스스로 devil's advocate로 약점 8건 제기 → ACCEPT / PARTIAL / REBUTTAL 분류.

---

## C1 (ACCEPT→PARTIAL) — Mode A Σ=lw_nls는 p<n라 sample과 tie, "lw_nls 테스트"가 아니다
**self-concern**: Mode A는 25×25(p=25<n=60) Σ=lw_nls를 쓰는데 P1c에서 lw_nls≈sample(TE tie)로 확립됨. 그러면 mode A는 lw_nls의 고유가치를 시험한 게 아니라 고정(≈sample) Σ 위 *비중-방법*만 비교한 것 아닌가.
**분류: PARTIAL (정확한 지적, 설계 의도로 흡수)**. Mode A의 역할은 "lw_nls 테스트"가 아니라 **NP4가 MVO 한 방법만 측정한 것을 8-방법으로 완결**하는 축이다(사전등록 명시). lw_nls의 퇴화교정이 물리는 영역은 **Mode B(p>n)** 이고, 거기서도 전부 미달했다. 두 축(방법 완결성 + estimator 교정)이 같은 결론. 한계로 verdict §limitations에 명시.

## C2 (ACCEPT) — Mode B pure_risk는 알파를 버리니 PORT_t 낮은 게 당연(strawman 아닌가)
**self-concern**: 위험선택(GMV/MaxDiv/HRP)은 정의상 알파를 안 쓰니 PORT_t 낮은 건 자명. 이걸로 "방법 소진"을 주장하면 허수아비.
**분류: ACCEPT (부분 인정) + 보완측정으로 무력화**. pure_risk가 낮은 건 예상대로다. 그러나 **alpha_combined 변형**(위험선택 25종 × LinearTilt 재적용)이 정확히 "위험기반 *선택* + 알파 *가중*이 알파-선택을 이기는가"를 시험했고, 그것도 best 0.076(HRP_lwlin_alpha)·lw_nls best 0.051 ≪ baseline 1.756. 도훈 질문("위험모델로 비중결정 모델을 고르면")의 핵심은 alpha_combined인데 그게 실측으로 미달. strawman 아님.

## C3 (REBUTTAL) — 알파가 post-2017 감쇠(baseline 1.76<2.95)라 "약한 목표를 이긴다"는 것
**self-concern**: baseline PORT_t 1.76은 이미 graduation 미달. 약한 알파를 못 이긴 건 알파 탓이지 방법 탓 아닐 수 있다.
**분류: REBUTTAL**. (학술) 판정은 **RELATIVE**(방법 부가가치)이지 절대 graduation 아님. (정량) 약한 알파일수록 좋은 Σ/위험방법이 개선할 *여지*가 큰데도(신호 대비 노이즈 비중↑) 어느 방법도 baseline을 초과 못했다 — 오히려 위험방법일수록 더 나빠짐(GMV_lwnls_pure -1.05). (L-code) NP4가 12-1 모멘텀(더 죽은 알파)에서도 동일 NULL. 약-알파 caveat이 method selection을 구제하지 못함이 **양방향 실측**.

## C4 (ACCEPT) — sweep 24셀 argmax인데 DSR 적용 안 하면 다중검정 편향
**self-concern**: 27셀 중 best를 골랐으니 승자편향. DSR 없이 "best 0.906"을 인용하면 부정직.
**분류: ACCEPT (mandatory)**. sweep형 selection이므로 DSR HARD 적용(§measurement-graduation). n_trials=24, sr*=0.1145, **DSR_best 0.247 < 0.5 = FAIL**. 다만 best(0.906)가 애초 baseline(1.756) 미달이라 DSR은 moot(초과 자체가 없음)이나 게이트는 준수. 정직 기록.

## C5 (PARTIAL) — Mode B 카디널리티(full해→top25 재해)는 휴리스틱, 정확 cardinality min-var 아님
**self-concern**: 25종 제약 min-var은 NP-hard. full-universe 해에서 top-25 뽑아 재해하는 방식이 진짜 최적 25-종 위험포트를 놓쳤을 수 있다.
**분류: PARTIAL**. 인정: 정확 cardinality 최적화는 미구현. 그러나 (1) alpha_combined가 위험-선택에 최선의 기회(알파 재가중)를 줘도 미달, (2) 정확 cardinality min-var이어도 여전히 **알파-무관 선택**이라 결론(음수 PORT_t) 불변, (3) lwlin 퇴화(GMV=MaxDiv 동일)는 카디널리티와 무관한 μI 붕괴. verdict §limitations 명시.

## C6 (ACCEPT/note) — sample p>n은 특이행렬, ridge 정규화하면 "sample"이 아니다
**self-concern**: sample cov(p=300>n=60)는 특이 → make_pd ridge 추가 = 사실상 shrunk-GMV. "sample arm"이 진짜 sample이 아님.
**분류: ACCEPT (투명 기록)**. sample이 대형-Σ 위험선택에 **부적격**(특이 → 해 불능)이라는 것 자체가 findng(shrinkage 필요성의 방증). ridge-sample도 음수 PORT_t라 결론 불변. cell registry에 sample=ridge-regularized 표기.

## C7 (REBUTTAL) — TO>11(mode A 전체)면 mode A 방법 전부 disqualify, mode B 저-TO가 승자여야
**self-concern**: 초기 run_02 버그가 실제로 TO-valid 셀만 best로 골라 B_MaxDiv_lwnls_alpha(0.05)를 "winner"로 오선정. TO 규율대로면 mode A(baseline 포함 TO~15)는 다 탈락 아닌가.
**분류: REBUTTAL**. TO~15/yr은 **월간 top-25 리밸 스케줄 속성**(baseline LinearTilt도 15.2) — 방법-판별자가 아니다. 저-TO mode B 위험방법(1.4~4.9)은 안정적이나 PORT_t 음수 = "낮은 회전으로 꾸준히 나쁨". binding 게이트는 TO가 아니라 **PORT_t**. 버그 수정(best=최고 PORT_t, TO 별도 보고) 후 재측정. 정직: 버그를 자체 적발·수정 기록.

## C8 (ACCEPT/finding) — 최대 레버가 top-20 vs top-25(비중방법 아님)면 라운드 프레임이 어긋남
**self-concern**: prodLT20(2.082) vs LinearTilt-25(1.756) = +0.33이 어떤 비중-방법 차이보다 크다. 그럼 "비중 방법" 라운드인데 정작 중요한 건 선택 개수?
**분류: ACCEPT (핵심 finding으로 승격)**. 이것이 바로 결론을 강화한다 — **사이징(비중 방법)이 아니라 선택 breadth/집중(Grinold IR=IC√breadth)이 지배**. ⑤비중 층 소진의 기전 설명이자, ①재료(선택할 신호원) 병목 귀속의 재확인. verdict §mechanism_diagnosis.breadth_over_sizing.

---

## 자동 Q-Lead escalate trigger 점검
- Hard Constraint 위반(max_names/max_w/Σw/turnover round-trip>1100%): **없음** (max25/box/Σw=1 전 셀 stopifnot PASS, round-trip TO 최대 ~44%<1100%).
- HIGH ≥5 / AX axiom hard FAIL ≥3: 없음.
- RF-O9 single-snapshot: **없음** — weights.parquet 197 as_of_date 시계열 schedule.
→ **escalate 불요**. capital_claim=FALSE 진단 라운드.

## 종합
8 self-concern → ACCEPT 3 / PARTIAL 3 / REBUTTAL 2. 어느 것도 verdict(config_scoped_negative)를 뒤집지 못함. C2/C3 REBUTTAL(alpha_combined 실측·양방향 약-알파)이 "허수아비/약한목표" 반론을 정량 무력화. C1/C5/C6 PARTIAL은 한계로 정직 기록. **판정: best-of-sweep는 baseline 미달 — lw_nls 기반 비중결정 방법 선택은 ⑤비중 층에서 유의한 성과-축 부가가치 없음(전방법 실측, NP4 강화).**
