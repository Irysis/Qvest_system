# AX-code 배선 구현 플랜
# 2026-04-10 | Qvest Architect

## 1. 현황 진단

### 1.1 존재하는 것 (설계 완료)
| 항목 | 경로 | 상태 |
|------|------|------|
| 설계 문서 | `00_Lawbook/Axiom_아키텍처/r7_axiom_design.md` | 5축 승격 기준, 생명주기 관리, R 코드 완비 |
| axiom_core.json | `.cache/axiom_core.json` | AX-000, AX-001 존재, **JSON 구문 오류** |
| axiom_signals.json | `.cache/axiom_signals.json` | 정상 동작 (reuse_penalty 등 4종) |
| axiom-io 스킬 | `.claude/skills/axiom-io.md` | read/write/승격 인터페이스 정의 |
| axiom_memory_interface.R | `02_Infrastructure/memory/axiom_memory_interface.R` | sg_read/write_axiom_signals() 구현 완료 |
| Judge Axiom 모니터링 | `qepm/mailbox/judge/outbox/axiom_monitoring_2026-03-21.json` | R7 승격 pathway 기록 |
| pipeline_trigger.sh | `02_Infrastructure/hooks/pipeline_trigger.sh` | PG2/PG3 완료 시 axiom distill 트리거 |
| Scout 프롬프트 | `02_Infrastructure/prompts/scout_init.md` | sg_read_axiom_signals() 호출 가이드 |
| Governor 프롬프트 | `02_Infrastructure/prompts/governor_init.md` | sg_sync_methodology_memory() 가이드 |
| Q-Lead 프롬프트 | `02_Infrastructure/prompts/qlead_init.md` | axiom_candidate inbox 처리 우선순위 |

### 1.2 끊어진 것 (배선 필요)
| 끊어진 지점 | 문제 | 영향 |
|-------------|------|------|
| **axiom_core.json JSON 오류** | AX-000 닫는 bracket 후 AX-001이 배열 밖에 위치. AX-002 미등록 | R 파싱 시 에러 발생 |
| **CLAUDE.md Axioms 섹션 비어있음** | `## Axioms (auto-injected -- agent premises)` 아래 내용 0줄 | 모든 에이전트가 AX-code를 전제로 인식하지 못함 |
| **Judge/Forge 프롬프트에 AX-code 참조 없음** | judge_init.md, forge_init.md에 axiom 언급 0건 | Judge가 AX-001(Defense 조건부 평가)을 심사 기준으로 인식 못함 |
| **axiom_enforcement_hook 미구현** | Hook 목록에 axiom 관련 hook 없음 | AX-code 위반을 기계적으로 탐지/차단할 수 없음 |
| **qepm/memory/axioms/ 디렉토리 미생성** | active/, candidates/, deprecated/ 없음 | r7_axiom_design.md의 디렉토리 구조와 불일치 |
| **r7_axiom.R 미구현** | `qepm/R/memory/r7_axiom.R` 없음 | scan_axiom_candidates(), promote_to_axiom() 호출 불가 |

---

## 2. 구현 항목 (6건, 우선순위 순)

### Task 1: axiom_core.json 수정 (JSON 오류 + AX-002 추가)
- **파일**: `.cache/axiom_core.json`
- **문제**: 16행에서 배열 `]` 닫은 후 AX-001 객체가 배열 밖에 위치
- **수정 내용**:
  1. AX-000과 AX-001을 axioms 배열 안에 올바르게 배치
  2. AX-002 추가: "규칙 안에서 찾아낸 성과가 진짜 성과"
  3. meta.version을 "1.2"로 갱신

**수정 후 구조:**
```json
{
  "axioms": [
    { "id": "AX-000", ... },
    { "id": "AX-001", ... },
    { "id": "AX-002", ... }
  ],
  "meta": { "version": "1.2" }
}
```

### Task 2: CLAUDE.md Axioms 섹션 기재
- **파일**: `CLAUDE.md` (265행 `## Axioms` 이하)
- **추가 내용**: AX-000~002 각각 1블록씩 주입
- **포맷**: r7_axiom_design.md의 inject_axiom() 출력 형식 준수
- AX-000: 불변/정신 원칙 (Level 0, 모든 에이전트)
- AX-001: Defense 조건부 평가 (Level 0, 심사 기준)
- AX-002: 제약 내 성과 = 진짜 성과 (Level 0, 연구 윤리)

**주입 형식 (각 AX-code당):**
```
### AX-XXX: [statement]
- 등급: IMMUTABLE | 적용: [에이전트 목록]
- 출처: [origin]
- 강제: [enforcement 규칙]
- 확정: [날짜] | L-code: [참조]
```

### Task 3: Axiom 디렉토리 구조 생성
- **경로**: `qepm/memory/axioms/`
- **생성할 하위 디렉토리**:
  - `active/` -- AX-000.json, AX-001.json, AX-002.json 배치
  - `candidates/` -- 승격 대기 후보
  - `deprecated/` -- 폐기 Axiom 보존
  - `review_log/` -- 정기 검토 기록
- **active/ 파일**: axiom_core.json의 각 항목을 r7_axiom_design.md 스키마로 확장
  - AX-000은 정신 원칙이므로 evidence 축 대신 "philosophical" 타입
  - AX-001은 이미 L-112 기반 evidence 존재 (Ang & Bekaert 2002, Asness 2019)
  - AX-002는 도훈님 선언 기반, PIT enforcement와 연계

### Task 4: axiom_enforcement_hook.sh 설계 + 등록
- **파일**: `02_Infrastructure/hooks/axiom_enforcement_hook.sh`
- **이벤트**: PostToolUse[Write] (stage_artifacts, hurdle_result 작성 시 트리거)
- **검증 로직**:

```
[AX-001 강제] Defense 역할 전략의 hurdle_result.json 또는 s6_*.json 작성 시:
  - role = "defense" 또는 "Defense" 확인
  - 전기간 SR/CAGR만으로 FAIL 판정했는지 탐지
  - 조건부 메트릭(crisis_sr, crisis_alpha, bad_ic, mdd_contribution) 부재 시 경고
  - 판정: allow + warning (soft block) -- "AX-001 위반 의심: Defense 전략에 조건부 평가 누락"

[AX-002 강제] 모든 전략 코드 작성 시:
  - C1~C15 PIT 패턴과 연계 (기존 forge_code_guard.sh에 위임)
  - 별도 로직 불필요 (기존 Hook 재사용)

[AX-000 강제] 모든 REJECT/FAIL 판정 시:
  - hurdle_result.json에 "grade":"F" 또는 s7_*.json에 "verdict":"REJECT" 작성 시
  - L-000 인용 의무 알림 (soft reminder)
```

- **settings.json 등록** (PostToolUse[Write] 추가):
```json
{
  "matcher": "Write",
  "hooks": [{
    "type": "command",
    "command": "bash \"$DIR/02_Infrastructure/hooks/axiom_enforcement_hook.sh\" 2>>/tmp/axiom_hook.log || true"
  }]
}
```

### Task 5: 에이전트 프롬프트 주입
- **대상 프롬프트 4개**:

| 프롬프트 | 추가 내용 | 이유 |
|----------|----------|------|
| `judge_init.md` | AX-001 조건부 평가 규칙 + AX-000 인용 의무 | Judge가 Defense 심사 시 조건부 메트릭 필수 확인 |
| `forge_init.md` | AX-001 Defense 전략 코드에 조건부 메트릭 계산 의무 | Forge가 Defense 전략 구현 시 crisis_sr 등 산출 |
| `scout_init.md` | AX-002 제약 내 성과 원칙 + AX-000 강화 | Scout이 제약 회피 유혹에 빠지지 않도록 |
| `risk_manager_init.md` | AX-001 tail_risk와 defense 연계 | Risk Manager가 defense 역할 검증 시 조건부 기준 적용 |

**주입 패턴** (각 프롬프트에 섹션 추가):
```markdown
## Active Axioms (자동 주입 전제)
- **AX-000**: 한계란 없다. REJECT/FAIL 판정 후 반드시 인용.
- **AX-001**: Defense는 조건부 성과로 평가. 전기간 SR 기준 금지.
- **AX-002**: 규칙 안에서 찾아낸 성과가 진짜 성과. PIT 우회 금지.
```

### Task 6: axiom_memory_interface.R 확장
- **파일**: `02_Infrastructure/memory/axiom_memory_interface.R`
- **추가 함수**:

```r
# 1. sg_load_active_axioms() -- active/ 디렉토리에서 전체 Axiom 로드
sg_load_active_axioms <- function() {
  axiom_dir <- file.path(PROJECT_ROOT, "qepm", "memory", "axioms", "active")
  # ... JSON 파일 순회 로드
}

# 2. sg_check_axiom_compliance(result, axiom_id) -- 결과가 Axiom과 일치하는지
sg_check_axiom_compliance <- function(result, axiom_id = "AX-001") {
  # AX-001: defense 전략이면 조건부 메트릭 존재 확인
  # 위반 시 warning 반환
}

# 3. sg_inject_axiom_to_claude_md(axiom) -- CLAUDE.md에 Axiom 주입
sg_inject_axiom_to_claude_md <- function(axiom) {
  # r7_axiom_design.md의 inject_axiom() 구현
}
```

---

## 3. 의존성 그래프

```
Task 1 (JSON 수정) ──┐
                      ├── Task 3 (디렉토리 + active/ JSON) ── Task 6 (R 함수 확장)
Task 2 (CLAUDE.md)  ──┘                                            │
                                                                    v
Task 5 (프롬프트 주입) ←──────────────────────────── Task 4 (Hook 설계)
```

- Task 1, 2: 병렬 가능 (독립적)
- Task 3: Task 1 완료 후 (올바른 JSON이 active/에 복사)
- Task 4, 5: 독립 가능하나 Task 5는 Hook 이름 확정 후 참조
- Task 6: Task 3 완료 후 (디렉토리 존재 전제)

---

## 4. 검증 계획

| 검증 항목 | 방법 | 성공 기준 |
|----------|------|----------|
| axiom_core.json 유효성 | `jsonlite::fromJSON(".cache/axiom_core.json")` | 에러 없이 3건 로드 |
| CLAUDE.md 인식 | 새 세션 시작 후 "AX-001이란?" 질문 | 에이전트가 정확히 답변 |
| active/ 디렉토리 | `list.files("qepm/memory/axioms/active/")` | AX-000.json, AX-001.json, AX-002.json |
| Hook 동작 | Defense 전략 hurdle_result 작성 시 경고 발생 | AX-001 위반 warning 로그 |
| 프롬프트 주입 | `grep "AX-001" 02_Infrastructure/prompts/judge_init.md` | 매치 1건+ |
| R 함수 | `sg_load_active_axioms()` 호출 | 3건 반환 |

---

## 5. 실행 계획 (예상 소요)

| 단계 | 예상 시간 | 비고 |
|------|----------|------|
| Task 1 + Task 2 (병렬) | 5분 | JSON 수정 + CLAUDE.md 편집 |
| Task 3 | 10분 | 디렉토리 생성 + AX JSON 파일 3개 작성 |
| Task 4 | 15분 | Hook 스크립트 + settings.json 등록 |
| Task 5 | 10분 | 4개 프롬프트 편집 |
| Task 6 | 10분 | R 함수 3개 추가 |
| 검증 | 5분 | JSON parse + grep + 함수 호출 |
| **합계** | **~55분** | |

---

## 6. 위험 요소

1. **CLAUDE.md 과잉 비대화**: Axiom 블록이 길어지면 context window 낭비
   - 완화: 각 AX-code 3줄 이내로 압축. 상세는 active/ JSON 참조
2. **Hook 오탐**: Defense가 아닌 전략에 AX-001 경고 발생
   - 완화: role 필드 정확히 파싱, "defense" 매칭만 트리거
3. **기존 Hook 충돌**: PostToolUse[Write]에 이미 3개 Hook 존재
   - 완화: axiom_enforcement_hook.sh는 soft warning만 (allow 반환)
4. **AX-000 "한계란 없다"의 기계적 강제 한계**: 정신 원칙은 Hook으로 강제 불가
   - 완화: REJECT/FAIL 시 L-000 인용 알림만 (reminder, not block)

---

## 7. AX-002 상세 정의 (신규)

```json
{
  "id": "AX-002",
  "name": "규칙 안에서 찾아낸 성과가 진짜 성과",
  "text": "PIT, 유동성, 종목수, 비용 등 모든 제약을 준수한 상태에서 달성한 성과만이 의미 있다. 제약을 느슨하게 해서 높인 SR/CAGR은 환상이다. 제약이 불편하면 제약을 우회하지 말고 제약 안에서 더 나은 alpha를 찾아라.",
  "grade": "IMMUTABLE",
  "level": 0,
  "origin": "Session 57, 도훈님 선언. PIT Enforcement 철학의 Axiom화.",
  "l_code": "AX-002",
  "applies_to": ["Scout", "Forge", "Judge", "Governor", "Q-Lead"],
  "enforcement": "PIT 위반 합리화 탐지 시 AX-002 인용. C1~C15 우회 시도 차단.",
  "created_at": "2026-04-10"
}
```

---

## 8. 승인 대기

도훈님 검토 후 `proceed` 지시 시 Task 1~6 순차/병렬 실행합니다.
- 수정 사항/우선순위 변경 시 이 문서 갱신 후 진행.
