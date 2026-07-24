# AST 계층 도입 설계안 v1.0 — 편입 검토 판정 (2026-07-25)

**의뢰**: 도훈 — "이 지시사항 검토해보고 Qvest 시스템에 편입할지말지 결정해봐"
**방법**: 4-agent 검증 워크플로우(wf_f40cca21-a26) — 설계안의 전제를 실제 저장소와 대조 실측 (A: 기존 PIT 메타 인프라 중복 / B: alpha 산출물 AST 표현가능성 / C: PIT 실사고 4건 회고 적용 / D: Phase 2 표본 현실성). 전 근거 파일:라인 실측.

---

## 판정: **수정 채택 (AST v1.1 — Qvest-정합판으로 편입)**

설계안의 방향(표현공간 통제 + 사전 PIT + 구조특징 사전분포)은 Qvest의 실사고 이력과 정확히 맞물리는 실가치가 있다. 단 **원안 그대로는 3곳에서 실측과 충돌**하므로 아래 수정 6건을 반영한 형태로만 편입한다.

---

## 1. 실측이 지지하는 것 (채택 근거)

- **restatement_prone / vintage_available 리프 필드 = 순수 신규 가치.** grep 전무. QuantiWise 재무 xlsx는 다운로드 시점 스냅샷 + Ticker×Period×Item 1행 dedupe로 **정정 전 원본값이 소실**되며(parse_fundamental_xlsx.R:349-358), Factor_Date는 실제 공시접수일이 아닌 합성 고정 offset. 설계안 §3의 "restatement+무vintage = 원리적 구제 불가" 경고는 Qvest 실태에 정확히 해당하고, 이 노출의 명시적 표시는 governor 입력으로 실가치가 있다.
- **선언→컴파일→구조적 PIT 골격의 선례가 이미 성공 가동 중.** add_factor 7-template(flat) + 빌더 pre-slice([sig_d−1400d, sig_d])가 축소판을 실증(add_factor.R:23-26). 설계안은 이것의 compositional 확장으로 자연스럽다 — 대체가 아니라 확장.
- **구조특징 축은 완전 신규.** node_count/free_param_count/conditional_op_count 류 인프라 0건. 현행 과적합 방어는 시행횟수 기반(DSR·n_trials)뿐 — "설계 복잡도" 축은 실제 공백.
- **mechanism 3필드(주체/마찰/경로)·falsification 필수화·regime_scope**: 현행에는 economic_rationale enum + 사후 검정만 존재 — **산출 계약의 필수 구조 필드화**는 신규 가치이며, alpha 설계 실력 업그레이드라는 본래 목적에 직결.

## 2. 실측이 반박하는 것 (수정 사유)

- **① AST-단일 인터체인지 = 실측 불가.** 2026-07 실물 alpha_package 46건 분포: DB 팩터 참조 ~9 + 수식형 ~27(AST 표현 가능)이나 **ML 모델 스코어 8~9 + LLM 채점 1 + 특수연산 2는 환원 불가**, 최신 cohort(07-18)는 7건 중 5건이 ML — 분포가 AST-가능 쪽에서 멀어지는 추세. 일부는 '팩터식→종목스코어' 형상 자체가 아님(timing-overlay). 헌장(alpha_research_init.md — 방법론 완전 자율 명문)과도 충돌. v8.3 주력(비-return·텍스트/포렌식)은 LLM 채점·파서 등 비-AST 리프를 늘리는 방향.
- **② 신규 리프 주석 테이블 = 3중 SOT.** factor_registry.json 373엔트리에 lag_rule/data_source/update_freq가 **이미 선언**돼 있으나 코드 소비자 0곳(순수 문서)이고, 실강제는 파싱 계층 하드코딩(분기 +45d·DART 연간 익년 3/31) — 별도 테이블 신설 시 [registry 문자열]+[하드코딩]+[신규 테이블] 3중화. C14 Usable_Date는 완전 배선 상태라 신규 기여 없음. **부수 발견: C4 텍스트('annual 5월') vs 구현('DART 연간 3/31') 불일치** — codify 전 도훈 결정 필요.
- **③ verify() 정적 판정 단독의 기대 회수 = 실사고 4건 중 1건.** 회고 실측: 사고2(저장 패널 동월 vintage)만 FAIL_LOOKAHEAD 정통 히트(그것도 canonical 소스 리프 강제 + 파생 패널 금지 전제). 사고1(BearProb)·사고3(faith)은 조인/라벨-정렬 구현 결함 — 리프 가용시각 시야 밖. 사고4(Cycle 50)는 backward label — availability 전파 무신호. **가치의 본체는 verify() 판정표가 아니라 3중 구조 예방**: (i) 리프 로드를 canonical vintage-aware 소스로 강제(파생 패널 리프 금지 = §7b 기계화) (ii) **조인/정렬을 컴파일러가 AS_OF 규율로 생성**(백테=배포 단일 경로 — 사고1·3 유형 예방, 사고3의 배포 코드 `Date<AS_OF`가 clean했던 반사실이 직접 증거) (iii) 𝒪 표현공간 한정(사고4의 shift(-H,"lead") double-negation이 문법적으로 불가). 이 재해석 하에 최대 4/4 커버.
- **④ 4건 전부 표준 통계검증(placebo·OOS·DSR·subperiod)을 통과하고 동적 도구(lag1·strict A/B·vintage-swap·β-스캔·육안)로만 검거됨** — 설계안 §4의 "judge 검증 유지" 원칙은 필수이며 정적 층은 보완이지 대체가 아님을 실측이 재확인.

## 3. 편입 수정 6건 (AST v1.1)

| # | 원안 | 수정 |
|---|---|---|
| M1 | AST = alpha↔forge 단일 인터체인지 | **AST-우선 + escape 리프 4종**: `MODEL_SCORE`(학습 스코어, 학습창 PIT 계약 동반) · `STORED_SCORE`(`production_parity_verified` 라벨 의무 — §7b 기계화) · `LLM_SCORE` · `SPECIAL_OP`(TE/Kalman 등). formulaic lane(현 산출 ~6할)은 AST 의무. timing-overlay 표면은 명시 범위 제외. escape 비중만큼 Phase 2 커버리지 절단을 계약에 명시 |
| M2 | 신규 리프 주석 테이블 | **factor_registry lag_rule의 기계가독 승격(단일 SOT 유지)** + `restatement_prone`/`vintage_available` 필드 신규 추가. 파싱 하드코딩과의 정합 검증을 등록 시 강제. 선행: C4 '5월 vs 3/31' 도훈 결정 |
| M3 | Phase 1 = verify() 정적검증 | **3중 구조 예방으로 재정의**: canonical 리프 강제 + 컴파일러-소유 AS_OF 조인 생성 + 𝒪 한정. verify()는 그 위의 마무리 층. 동적 검정(lag1·strict A/B·vintage-swap·validate_label_direction) 병행 유지 명문화 |
| M4 | 로깅은 신규 JSON | **essence_score() 내부 append-only 사이드카(JSONL, 06_Registry/)** — backtest_registry는 죽은 스트림 실측(3개월 22행·최근 30일 0행), essence_score는 전 graduation 판정 경유라 capture 구조 보장 + oos_retention_splits 유실 문제 동시 해소. decay 종속변수는 기존 oos_retention v2·decay-pattern 라벨 재사용(재구축 금지) |
| M5 | judge 4축 12점 반려 게이트 | mechanism 3필드·falsification·regime_scope의 **Hook 기계 강제**(신규 훅 1개 — 3의무: env-경유·조기-exit·additionalContext 준수)는 채택. Claude 4축 중 **축 1(메커니즘 구체성)·축 4(국면 경계)만 신설**하고 **screening-tier advisory** — 축 2·3의 PIT/성과 판정은 Gate A~F와 중복이라 미신설. graduation HARD 3종·cap-w 권위 불변 |
| M6 | Phase 2 분석 | N=30 도달 실측 추정 = 로깅 개시 후 2~4주(전 후보 AST-lane 가정, escape 비중만큼 연장. 기존 533 기록은 구조특징 결측으로 소급 불가). **N<30 분석 금지 원칙 그대로 채택** + active_regime 라벨 동반 |

## 4. 도입 순서 (수정판 — 원안 Step 재배열)

```
Step 0  선행 결정 (도훈): C4 annual availability = 3/31(현 구현) vs 5월(텍스트) 확정
Step 1  factor_registry 기계가독 승격 + restatement/vintage 필드 + escape 리프 계약 정의
        (𝒪 최소집합은 원안 채택 — LEAD 부재 원칙 포함)
Step 2  alpha 출력 스키마 3층화(가설 구조필드 필수화 포함) + forge AST→R 컴파일러
        ★ 컴파일러가 조인/정렬을 AS_OF 규율로 소유 (M3 — 회수의 본체)
Step 3  PIT 정적검증 삽입 (alpha 직후) + judge 신규 훅(기계 강제 4종)
        ─── 손익분기 (원안과 동일 위치, 단 M3 포함 조건) ───
Step 4  essence_score 사이드카 로깅 개시 (분석은 N≥30 후)
Step 5~6  복잡도 사전분포 주입 · 커버리지 지도 (원안대로 후순위)
```

## 5. 소비면·부활조건 (연속성)

- **소비면**: 본 판정 → ① AST v1.1 설계 SOT 작성(승인 시 `02_Infrastructure/docs/qvest_ast_v1_1_sot.md`) ② C4 불일치는 즉시 도훈 결정 큐 ③ escape 리프 중 `STORED_SCORE` parity 라벨은 §7b 기계화라 AST와 무관하게 선행 구현 가치 있음 ④ 실사고 회고 산출(정적 vs 동적 검거 지도)은 pit.md 참고자료로 교차 등재.
- **부활 조건(원안 기각분)**: AST-단일 인터체인지는 ML lane 비중이 구조적으로 축소되거나(현 추세는 역) MODEL_SCORE 리프의 PIT 계약이 학습창까지 정적 검증 가능해지면 재검토. judge 12점 HARD화는 축 1·4 advisory의 판별력이 (IS,OOS) 표본으로 실증된 후 재검토.
- **next_probe**: ① Step 0 결정 회부(C4 값) ② 승인 시 AST v1.1 SOT 작성 + Step 1 착수 ③ 미승인 시에도 M4 사이드카 로깅(구조특징 제외한 (IS,OOS,regime) 적립)은 독립 가치로 선행 가능.

## 6. 한계 (설계안 §10 동의 + 추가)

원안 §10 전부 유효. 추가 2건: ① escape 리프 비중이 커질수록 이 계층의 통제력·사전분포 커버리지가 비례 감소 — 분기별 escape 비중 모니터링 필요. ② 리프 메타 진실성이 단일 실패점이라는 원안 경고는 사고2 회고에서 실증(파생 패널 메타 오기재 시 정적검증 오통과) — judge 경험적 검증 병행은 HARD 원칙.

**원 데이터**: 워크플로우 저널 `wf_f40cca21-a26/journal.jsonl` + 세션 스크래치패드 ast_a~d.
