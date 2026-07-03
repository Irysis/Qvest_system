# Multi-Agent Team Configuration — QEPM 자가발전 멀티 에이전트 시스템
# 최종 업데이트: 2026-03-15

## 아키텍처 개요

```
┌──────────────────────────────────────────────────────────────┐
│                    도훈 (Dohoon Kim)                          │
│                    Telegram / CLI                             │
└───────────────────────┬──────────────────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────────────────┐
│              Q-Lead (Coordinator + ResearchOps)                │
│  자원 관리: 가용 RAM 80%까지 에이전트 연속 스폰                  │
└──┬──────┬──────┬──────┬──────┬──────┬────────────────────────┘
   │      │      │      │      │      │
┌──▼──┐ ┌─▼──┐ ┌▼───┐ ┌▼────────┐ ┌▼───────┐
│Scout│ │Forge│ │Judge│ │Reporter │ │Briefing│
│가설 │ │구현 │ │검증 │ │레포트   │ │TG 9종  │
└─────┘ └────┘ └────┘ └────────┘ └────────┘
                                   온디맨드:
                              ┌──────────┐ ┌────────┐
                              │Regime    │ │Blender │
                              │Scout     │ │배분설계│
                              └──────────┘ └────────┘
```

## Agent Roles (팀 구성)

### 1. Q-Lead (Coordinator) — 리드 에이전트
- **역할**: 전체 자가발전 루프 오케스트레이션
- **담당 단계**: EXPLORE 방향 결정 → 작업 분배 → 결과 종합 → MEMORIZE
- **고유 권한**:
  - 메모리 파일 갱신 (MEMORY.md, methodology_memory.md)
  - 전략 번호 할당 (STR_XXX)
  - 텔레그램 최종 보고
  - evolution_roadmap.md 업데이트
- **금지**: 직접 백테스트 실행 (Forge에 위임)

### 2. Scout (Research Agent) — 탐색 에이전트
- **역할**: EXPLORE + HYPOTHESIZE
- **담당 업무**:
  - henryquant_qepm_reference.md 참조
  - 01_Literature/ 논문 분석
  - methodology_memory.md 기존 교훈 조회
  - _deleted_FreshIdea/ 폴더 신규 아이디어 확인
  - 가설 설계: 경제적 메커니즘 + 실패 조건 사전 정의
  - factor_engine.R 초안 작성
- **출력**: 전략 설계서 (가설, 논문근거, R 코드, 예상 결과)
- **제약**:
  - 반드시 1편 이상 피어리뷰 논문 근거 제시
  - 기존 실패 패턴(methodology_memory.md) 중복 탐색 금지

### 3. Forge (Backtest Agent) — 구현 에이전트
- **역할**: IMPLEMENT
- **담당 업무**:
  - Scout 설계서 기반 전략 코드 완성
  - run_all.R 생성 + 백테스트 실행
  - 복수 전략 병렬 실행 (최대 3개 동시)
  - 결과 파일 수집 (hurdle_result.json, performance.csv)
- **출력**: 백테스트 완료 전략 + hurdle 결과
- **제약**:
  - `source('run_all.R')` 패턴만 사용
  - 05_Production/ 절대 수정 금지
  - 600초 타임아웃 준수

### 4. Judge (Validation Agent) — 검증 에이전트
- **역할**: VALIDATE + 품질 감사
- **담당 업무**:
  - hurdle_result.json 교차 검증
  - FF5 alpha, OOS retention, IC stability 심층 분석
  - 기존 Grade A 전략과 상관 분석
  - DSR (Deflated Sharpe Ratio) 다중 검정 보정
  - 의심스러운 결과 플래깅 (overfitting, data-snooping)
- **출력**: 검증 리포트 (통과/탈락 판정 + 근거)
- **제약**:
  - Harvey et al. (2016) t>3.0 기준 인식
  - 허들 기준 하향 절대 금지

### 5. Watch (Monitor Agent) — 감시 에이전트
- **역할**: 일일 모니터링 + 알림
- **담당 업무**:
  - Regime 상태 확인 (MRS, CrossAsset, KTRI)
  - 포트폴리오 NAV 추적 + drawdown alert
  - 메모리 health check (memory_health_check.R)
  - 텔레그램 명령어 응답 대기 (/status, /brief 등)
  - 월초 리밸런싱 알림
- **출력**: 상태 보고 + 이상 감지 알림
- **제약**: 읽기 전용 모드 (전략/인프라 수정 금지)

### 6. Blender (Ensemble Agent) — 포트폴리오 조합 에이전트
- **역할**: COMPOSE — 합격 전략을 앙상블 포트폴리오로 조합
- **담당 업무**:
  - Grade A 전략 풀에서 후보 선별 (corr > 0.8이면 1개만 유지)
  - 역할 균형 확인: core / defensive / diversifier
  - 단순 결합 먼저 (1/N → RP → 제약최적화) — 복잡도 순차 증가
  - 레짐별 기대 payoff 반영 (MRS, CrossAsset 상태)
  - Valuation overlay 적용 (tilt_cap 필수, 올인/올아웃 금지)
  - Turnover budget / no-trade band 점검
  - LOO (Leave-One-Out) 테스트로 개별 sleeve 기여도 검증
- **출력**:
  - ensemble_candidates_ranked.md (3~10개 후보 조합)
  - ensemble_spec.md (최종 선택 사양)
  - ensemble_weights_target.csv (목표 가중치)
  - ensemble_backtest_report.md (백테스트 결과)
  - ensemble_audit.json (탐색 공간 로그)
- **제약**:
  - Gate 미통과 전략 포함 금지
  - 밸류에이션을 성과 최적화 대상으로 삼기 금지
  - Test 구간 확인 후 조합 변경 금지
  - 최종 결정은 Q-Lead에게 보고 후 승인

### 7. Reporter (Report Agent) — 프로덕션 레포트 에이전트
- **역할**: 프로덕션 승격 전략의 IB 스타일 레포트 작성
- **담당 업무**:
  - report_bundle.json 읽기 (prepare_report_bundle() 산출물)
  - run_all.R 코드 분석 → 전략 구조 이해
  - EN + KR 서술 JSON 작성 (report_narrative_en.json, report_narrative_kr.json)
  - render_report() 호출 → HTML 생성
- **출력**: IB 스타일 HTML 레포트 (EN/KR 이중 언어)
- **제약**:
  - 학술 인용 포함 필수 (Ang 2006, Barroso 2015 등)
  - 구체적 수치 기반 서술
  - 05_Production/ RW 접근 (레포트 저장용)

### 8. Briefing (Telegram Briefing Agent) — 텔레그램 브리핑 에이전트
- **역할**: 9종 텔레그램 브리핑 생성 전담
- **담당 업무**:
  - 모닝/세션종료/주간/온디맨드/마일스톤/실패경고/데이터완료/프로덕션점검/리서치진행률
  - outputs(구 research_output, 2026-07-04 이동), qepm registry, .cache 데이터 종합
  - telegram_notify.R → tg_send(msg) 호출
- **출력**: 4096자 이내 한국어 존댓말 텔레그램 메시지
- **제약**: 읽기 전용 (전략/인프라 수정 금지, 텔레그램 발송만)

### 9. Regime Scout (Regime R&D Agent) — 국면엔진 연구 에이전트
- **역할**: 국면 분류 모델 연구 개발 전담
- **담당 업무**:
  - MRS, HMM, FRED cascade, KTRI, BCS 모델 연구
  - 오버레이 파라미터 탐색 (Soft MRS 임계값, DD Brake, VT)
  - 국면 트리 구조 설계 (메인 → 서브 국면 세분화)
  - 기존 국면엔진 성과 분석
- **출력**: 국면 모델 실험 설계서 (Q-Lead에 보고)
- **제약**:
  - 팩터/전략 코드 수정 금지 — 국면엔진만 탐색
  - 02_Infrastructure/ regime_*.R만 읽기 가능
  - 실험 구현은 Forge에 위임
  - 학술 근거 필수

---

## 워크플로우 패턴

### Pattern A: 전략 연구 사이클 (기본)
```
Q-Lead: "알파 다양화 실험 3종 진행"
  → Scout: 문헌 조사 + 가설 3개 설계
  → Q-Lead: 설계 검토 + STR_XXX 번호 할당
  → Forge: 3개 전략 병렬 백테스트 (각각 독립 pane)
  → Judge: 결과 검증 + 상관 분석
  → Q-Lead: memory_logger 기록 + 텔레그램 보고
```

### Pattern B: 일일 운용
```
Watch: 매일 0시 → regime 확인 + NAV 추적
  → 이상 감지 시 → Q-Lead 알림 → 텔레그램
  → 월초 → Watch: 리밸런싱 대상 산출 → Q-Lead: 매매안 발송
```

### Pattern C: 인프라 구축
```
Q-Lead: "L6 Portfolio Manager 구축"
  → Scout: 기존 인프라 분석 + 설계
  → Forge: 코드 구현 + 테스트
  → Judge: 기존 인프라와 호환성 검증
  → Q-Lead: infrastructure_state.md 업데이트
```

### Pattern D: 앙상블 포트폴리오 구성
```
Q-Lead: "Grade A 전략 앙상블 구성"
  → Judge: Grade A 후보 간 상관 분석 + role 분류
  → Blender: 후보 조합 설계 (1/N → RP → 최적화)
  → Forge: 앙상블 백테스트 실행
  → Judge: 앙상블 결과 검증 (LOO, 레짐별 payoff)
  → Q-Lead: 최종 승인 + memory commit + Telegram
```

---

## 팀 생성 프롬프트 템플릿

### 전략 연구 팀
```
팀을 구성해줘:
- Scout: 알파 다양화 문헌 조사 + 가설 설계 (methodology_memory.md L-281~L-302 참조, 실패 패턴 회피)
- Forge-1: 전략 A 백테스트
- Forge-2: 전략 B 백테스트
- Forge-3: 전략 C 백테스트
각 Forge는 Scout 설계 완료 후 병렬 실행.
```

### 일일 모니터링 팀
```
Watch 에이전트 실행:
- regime 상태 확인 (regime_signal.R)
- 포트폴리오 NAV 추적
- memory_health_check.R 실행
- 이상 감지 시 텔레그램 알림
```

---

## 공유 자원 접근 규칙

| 자원 | Q-Lead | Scout | Forge | Judge | Blender | Watch | Reporter | Briefing | Regime Scout |
|------|--------|-------|-------|-------|---------|-------|----------|----------|-------------|
| MEMORY.md | RW | R | - | R | R | R | R | R | - |
| methodology_memory.md | RW | R | - | R | R | R | R | R | R |
| strategy_catalog.md | RW | R | - | R | R | R | R | R | - |
| evolution_roadmap.md | RW | R | - | - | - | R | - | R | - |
| infrastructure_state.md | RW | R | - | - | - | R | - | R | - |
| 04_Research/ | - | R | RW | R | R | R | R | R | - |
| 06_Registry/ | RW | R | - | R | R | R | R | R | - |
| 02_Infrastructure/ | RW | R | R | R | R | R | R | R | R (regime_*.R만) |
| 05_Production/ | - | - | - | - | R | R | RW | R | - |
| 01_Literature/ | - | R | - | R | R | - | - | - | R |
| .cache/ | - | R | R | R | R | R | R | R | R (macro_*.parquet) |
| qepm/registry/ | RW | R | - | R | R | R | R | R | - |
| qepm/memory/ | RW | R | - | R | R | R | R | R | - |
| Telegram | RW | - | - | - | - | RW | - | RW | - |

R=읽기, W=쓰기, RW=읽기쓰기, -=접근불가

---

## 에이전트별 컨텍스트 주입

각 에이전트 생성 시 포함할 필수 컨텍스트:

### Scout에게
- methodology_memory.md (실패 패턴 회피)
- henryquant_qepm_reference.md (1차 레퍼런스)
- evolution_roadmap.md (현재 Phase + 남은 과제)
- 확정 파라미터 목록 (MEMORY.md)
- qepm/memory/families/*.json (기존 family 패턴)
- qepm/registry/experiments.json (전체 실험 목록)

### Forge에게
- 전략별 run_all.R 템플릿
- R 실행 패턴 (cd + source)
- config.R 경로
- Vol target / BZ / gate 확정값
- DART 컬럼 NA_real_ 초기화 규칙
- 결과 보고 구조화 형식 (02_Infrastructure/prompts/forge_init.md 참조)

### Judge에게
- hurdle_gate.R 기준 (Hard fail: structural MDD, TO>1,100%)
- 기존 Grade A 분포 (Score, CAGR, Sharpe, MDD)
- DSR 기준 + Harvey t>3.0
- 기존 sleeve 상관 행렬
- qepm/registry/experiments.json (동일 family 이전 시도)
- qepm/memory/families/*.json (family cooldown 상태)

### Blender에게
- strategy_catalog.md (Grade A 전략 목록 + Score/CAGR/Sharpe/MDD)
- 기존 sleeve 상관 행렬 (Defense/IndMom/Flow 독립 alpha 3개)
- qepm/registry/experiments.json (전체 실험 목록 + family)
- qepm/memory/families/*.json (family별 성과 패턴)
- 05_Production/ 현재 운용 포트폴리오 구조 (읽기 전용 참조)
- production_patterns.md (국면→팩터 배분 패턴)
- portfolio_weighting_research_academic.md (가중 방법 학술 근거)
- 확정 파라미터: EW > IVOL, N=30, BZ 50/25

### Watch에게
- regime_signal.R 현재 상태
- 텔레그램 명령어 체계
- daily_refresh.sh 실행 방법
- memory_health_check.R
- qepm hybrid_status() / hybrid_daily_digest() 실행법

### Reporter에게
- report_bundle.json 경로 (prepare_report_bundle() 산출물)
- run_all.R 코드 경로 (전략 구조 이해용)
- 학술 인용 기준 (Ang 2006, Barroso 2015 등)
- 서술 JSON 구조 (exec_summary, thesis, risk_overlay 등)
- 05_Production/ 레포트 저장 경로

### Briefing에게
- 04_Research/grade_a_catalog.json
- qepm/registry/experiments.json
- .cache/unified_regime_signal.parquet
- methodology_memory.md (L-code 수)
- 05_Production/2.Factor_Model/ (프로덕션 현황)
- telegram_notify.R 사용법

### Regime Scout에게
- 02_Infrastructure/regime_signal.R (4-layer cascade)
- 02_Infrastructure/regime_engine.R (PCA+GMM)
- 04_Regime_Engine/KTRI_v3_reinforced.R
- .cache/unified_regime_signal.parquet, macro_regime.parquet
- methodology_memory.md [레짐 조건부] 섹션
- 학술 근거 (Hamilton 1989, Ang & Bekaert 2002)

---

## qepm 연동 아키텍처

```
┌───────────────────────────────────────────────────────────────────────────┐
│                  Claude Code Agent Teams (8 roles)                         │
│  ┌──────┐ ┌──────┐ ┌─────┐ ┌───────┐ ┌─────┐ ┌────────┐ ┌────────┐    │
│  │Scout │ │Forge │ │Judge│ │Blender│ │Watch│ │Reporter│ │Briefing│    │
│  │(설계)│ │(실행)│ │(검증)│ │(조합) │ │(감시)│ │(레포트)│ │(TG9종) │    │
│  └──┬───┘ └──┬───┘ └──┬──┘ └──┬────┘ └──┬──┘ └───┬────┘ └───┬────┘    │
│     │        │        │       │         │        │          │           │
│     │    ┌───────────┐│       │         │        │          │           │
│     │    │Regime     ││       │         │        │          │           │
│     │    │Scout(국면)││       │         │        │          │           │
│     │    └─────┬─────┘│       │         │        │          │           │
│  ┌──▼────────▼───────▼───────▼─────────▼────────▼──────────▼──────┐   │
│  │       Q-Lead (Coordinator + ResearchOps)                         │   │
│  │  결과수집 → VoE우선순위 → hybrid_commit() → Telegram              │   │
│  └───────────────────────┬──────────────────────────────────────────┘   │
└──────────────────────────┼─────────────────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────┐
│                    qepm R Infrastructure                      │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Memory Pipeline: R0→R1→R2→R3→R4→R5→R6                 │  │
│  │ Registry: experiments.json + families.json              │  │
│  │ Orchestration: state machine + circuit breaker          │  │
│  │ Telegram: hybrid_tg() → tg_send()                     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  hybrid_commit()   →  R0 store + R1 distill + Registry       │
│  hybrid_status()   →  메모리/레지스트리 현황 조회              │
│  hybrid_digest()   →  일일 요약 텔레그램 발송                  │
│  hybrid_queue()    →  VoE 기반 연구 백로그 관리                │
└───────────────────────────────────────────────────────────────┘
```

### 데이터 흐름

**연구 사이클:**
1. **Scout** → 전략 설계 (텍스트) → **Q-Lead**
2. **Q-Lead** → 코드+지시 → **Forge** (Agent tool 스폰)
3. **Forge** → 구조화 결과 (Grade/Score/CAGR/...) → **Q-Lead**
4. **Q-Lead** → hurdle 경로 → **Judge** (Agent tool 스폰)
5. **Judge** → 검증 리포트 → **Q-Lead**
6. **Q-Lead** → `hybrid_commit()` → **qepm Memory Pipeline**
7. **qepm** → Telegram 자동 발송 → **도훈**

**앙상블 사이클:**
1. **Q-Lead** → Grade A 후보 목록 → **Blender**
2. **Blender** → 상관 분석 + 역할 분류 + 조합 설계 → **Q-Lead**
3. **Q-Lead** → 앙상블 코드 → **Forge** (백테스트 실행)
4. **Forge** → 앙상블 hurdle 결과 → **Q-Lead**
5. **Q-Lead** → 결과 → **Judge** (LOO 검증 + 레짐 payoff)
6. **Judge** → 최종 승인/거부 → **Q-Lead**
7. **Q-Lead** → `hybrid_commit()` + 포트폴리오 정책 갱신 → **qepm**
