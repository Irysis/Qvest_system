# V6 아키텍처 준수 체크리스트
# 최종 업데이트: 2026-03-26

> 모든 에이전트는 매 작업 전 이 체크리스트를 확인한다.
> 위반 시 Judge REJECT + Q-Lead 위반 로그 기록.

---

## A. Stage Gate 프로세스 (필수 순서)

### A1. S0 — 가설 기록 (Scout)
- [ ] `sg_init(factor_id, strategy_id)` 호출하여 트래커 생성
- [ ] `stage_artifacts/s0_record_{id}.json` 생성
  - [ ] factor_id, hypothesis (10자+), economic_rationale (10자+)
  - [ ] prior_art: "Existing" / "Variant" / "Novel"
  - [ ] source_reference (학술 논문 1편+)
  - [ ] expected_orthogonality
  - [ ] **V6 필수**: expected_role, why_now, overlay="none"
  - [ ] **V6 필수**: core_reference (Part A 참조번호)
  - [ ] **V6 필수**: lesson_check (관련 L-code 확인 결과)
- [ ] Scout가 `methodology_memory.md` 읽고 실패 팩터 재시도 아닌지 확인
- [ ] Scout가 `core_knowledge_base.md` Part A/B 읽고 학술 근거 확인
- [ ] `.cache/portfolio_gap_vector.json` 참조하여 gap-directed 설계
- [ ] `sg_transition(factor_id, "S1", artifact_path)` 호출

### A2. S1 — 팩터 구축 (Forge)
- [ ] `qepm/mailbox/forge/inbox/TODO_S1_{id}.json`에서 지시 수신
- [ ] run_all.R + factor_engine.R 작성 (표준 헤더 + preflight_check)
- [ ] **순수 팩터만**: DD/VT/Regime overlay 금지
- [ ] EW 30종목 + 15bps + 유동성 2억 필터
- [ ] `stage_artifacts/s1_construction_{id}.json` 생성
  - [ ] signal_file, coverage, period
  - [ ] pit_log: data_dates_verified, rolling_window_expanding_only, zscore_historical_only, connector_api_used
- [ ] 완료 시 `TODO_ → DONE_` rename
- [ ] `sg_transition(factor_id, "S2", artifact_path)` 호출

### A3. S2 — 독립 프로파일 (Forge)
- [ ] IC/ICIR/t-stat 계산
- [ ] `stage_artifacts/s2_profile_{id}.json` 생성
  - [ ] ic_ir, t_stat, monotonicity, turnover, quintile_spread
  - [ ] tag: "Strong" / "Moderate" / "Weak"
  - [ ] **V6 필수**: role_bias 태깅 (RoleBias_Core/Diversifier/Defense)
- [ ] `sg_transition(factor_id, "S3", artifact_path)` 호출
- [ ] Scout에 S3 분석 요청 (`TODO_S3_{id}.json` 생성)

### A4. S3 — 직교성 스캔 (Scout)
- [ ] `compute_factor_orthogonality()` 실행 (기존 팩터풀 대비)
- [ ] `stage_artifacts/s3_orthogonality_{id}.json` 생성
  - [ ] max_abs_corr_db, most_correlated_factor
  - [ ] independence_class: "independent" / "partial" / "redundant"
  - [ ] value_matrix_cell, n_compared (>=10)
  - [ ] **V6 필수**: novelty_score, candidate_role_hint
- [ ] `sg_transition(factor_id, "S4", artifact_path)` 호출

### A5. S4 — 통합 테스트 (Forge)
- [ ] KOSPI 듀얼 벤치마크 beat 판정
- [ ] `stage_artifacts/s4_integration_{id}.json` 생성
  - [ ] base_portfolio, base_sharpe, extended_sharpe
  - [ ] delta_sharpe, kospi_beat
  - [ ] best_combination, best_weighting, methods_tested
- [ ] **자동 분기**:
  - kospi_beat=TRUE AND delta_sharpe>0 → S6 (검증)
  - OTHERWISE → S5 (mutation)
- [ ] `sg_determine_role()` + `sg_role_admission()` 자동 호출
- [ ] S5 진입 시 `sg_generate_research_slate()` 자동 생성 (4슬롯 A/B/C/D)

### A6. S5 — 변형 실험 (Forge, Scout 설계)
- [ ] **Scout이 Research Slate 4슬롯에서 mutation 선택 + 설계** (Forge는 실행만)
- [ ] `stage_artifacts/s5_mutation_{id}.json` 생성
  - [ ] mutations_attempted >= 9
  - [ ] f_category_count >= 2
  - [ ] mutations 리스트 (category, description, result_delta_sharpe)
- [ ] DD/VT overlay는 이 단계에서만 허용 (DD 6~8/20~25)
- [ ] `sg_transition(factor_id, "S6", artifact_path)` 호출

### A7. S6 — 검증 (Judge)
- [ ] `sg_check_s6_entry(factor_id)` 반드시 첫 행동으로 호출
- [ ] S3 + S4 산출물 존재 확인 (없으면 즉시 차단)
- [ ] Gate 0-5 순차 검증
  - Gate 0: PIT (C1-C15)
  - Gate 1: 구현 (종목수, 커미션, 유동성)
  - Gate 2: 견고성 (OOS, rolling 3Y, stress)
  - Gate 3: 성과 (SR, CAGR, MDD)
  - Gate 4: 통계 (FF5 alpha t, 최근 3Y SR)
  - Gate 5: 다양성 (기존 Grade A 대비 상관)
- [ ] **V6 Role Honesty Audit**: 역할 위장 탐지
- [ ] `stage_artifacts/s6_validation_{id}.json` 생성

### A8. S7 — 최종 판정 (Judge)
- [ ] Grade A/B/C/F 판정
- [ ] **L-code 작성 필수** → `stage_artifacts/l_code_{id}.json`
  - [ ] strategy_id, grade, core_reference, lesson_text (100~500자), tags, created_at
- [ ] evolution_path 기록
- [ ] production_candidates 갱신 (Grade A 시)

---

## B. 에이전트 역할 분리

### B1. Q-Lead (오케스트레이터)
- [ ] 전략 코드 직접 작성 **금지** (run_all.R 생성/수정 금지)
- [ ] 백테스트 직접 실행 **금지**
- [ ] STR 번호 할당은 `allocate_str()` 통해서만
- [ ] S0~S7 산출물 직접 생성 **금지**
- [ ] `sg_can_advance()` 호출 후에만 디스패치
- [ ] 역할: 감독 + 브리핑 + 자원 관리 + hybrid_commit

### B2. Scout (가설 설계자)
- [ ] 코드 실행 **금지** (설계만)
- [ ] S0 가설 전 필수 읽기:
  - [ ] methodology_memory.md (L-code 교훈)
  - [ ] core_knowledge_base.md Part A (학술 근거)
  - [ ] core_knowledge_base.md Part B (한국시장 실증)
  - [ ] CLAUDE.md ## Axioms (공리 범위)
- [ ] S3 직교성 분석 담당
- [ ] S5 mutation 설계 담당 (Research Slate 4슬롯 선택)

### B3. Forge (실행자)
- [ ] Scout 설계 없이 자체 전략 생성 **금지**
- [ ] TODO_*.json에서만 작업 수신
- [ ] 완료 시 TODO_ → DONE_ rename
- [ ] S1, S2, S4, S5 artifact 생성 책임
- [ ] 표준 헤더 + preflight_check() 필수

### B4. Judge (검증자)
- [ ] sg_check_s6_entry() 반드시 첫 행동
- [ ] 허들 기준 하향 **금지**
- [ ] L-code 작성 **필수** (S6 완료 시)
- [ ] Role Honesty Audit **필수** (V6)

---

## C. Mailbox 시스템

- [ ] Scout inbox: `qepm/mailbox/scout/inbox/TODO_S3_*.json`, `TODO_S5_DESIGN_*.json`
- [ ] Forge inbox: `qepm/mailbox/forge/inbox/TODO_S1_*.json`, `TODO_S5_EXEC_*.json`
- [ ] Judge inbox: `qepm/mailbox/judge/inbox/TODO_S6_*.json`
- [ ] 완료 시 `TODO_ → DONE_` rename
- [ ] Q-Lead가 직접 에이전트에 코드 전달하는 방식은 **비정규** (mailbox 경유 필수)

---

## D. 텔레그램 규칙

- [ ] 모든 메시지에 이모지 필수
- [ ] [에이전트 태그] 필수: [Scout]/[Forge]/[Judge]/[Q-Lead]
- [ ] 한글 기본
- [ ] 차트 동반 필수 (백테스트 결과 시)
- [ ] 성과 포맷: Grade/Score/SR/CAGR/MDD + 강점/약점

---

## E. PIT Enforcement (Level 0)

- [ ] C1: full-sample 통계 → rolling/expanding만
- [ ] C2: same-day circular → t-1 lag
- [ ] C3: 같은 기간 집계→적용 금지
- [ ] C4: 재무제표 래깅 (연간 5월, 분기 45일)
- [ ] C5: overlay t-1 기준
- [ ] C6: survivorship bias
- [ ] C7: 자동 검출 (sd/mean/quantile)
- [ ] C8: FM weight same-day 금지
- [ ] C9: VT/DD same-day 금지
- [ ] C10: 유동성 필터 당일 거래량 금지
- [ ] C11: 데이터 시간축 검증 (FRED 시차 등)
- [ ] C13: Z_Score_Aligned만 사용 (수동 방향 반전 금지)
- [ ] C14: IC 접근 시 Usable_Date <= sig_date
- [ ] C15: Factor DB load_month_factors() 사용

---

## F. 교훈 적립 규칙

- [ ] 모든 백테스트 완료 후 L-code 작성 (Judge S7 단계)
- [ ] `stage_artifacts/l_code_{strategy_id}.json` 형식
- [ ] 100~500자. core_knowledge_base.md 대비 실증 비교 필수.
- [ ] tags: ALPHA_DECAY, GATE_FACTOR_ONLY, CRISIS_ALPHA, PIT_VIOLATION 등
- [ ] methodology_memory.md에 동기화 (Q-Lead 책임)

---

## G. 누락 인프라 현황

| 항목 | 상태 | 조치 |
|------|------|------|
| stage_gate_engine.R | ✅ 존재 | 정상 작동 검증 필요 |
| stage_artifact_schemas.R | ✅ 존재 | 7개 스키마 정의 완료 |
| factor_research_pipeline.R | ✅ 존재 | compute_factor_orthogonality() 포함 |
| v6 prompts (scout/forge/judge/qlead) | ✅ 존재 | 에이전트 스폰 시 사용 필수 |
| **core_knowledge_base.md** | ❌ 미존재 | **생성 필요** (Part A 학술 + Part B 실증) |
| mailbox 시스템 | ✅ 존재 | TODO/DONE 파일 관리 |
| .cache/stage_gate/ trackers | ✅ 존재 | 10+ 트래커 확인 |
