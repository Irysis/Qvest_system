# Caching + Model Routing Discipline (Level 0)

**발효**: Session 68 Day 2 도입 / Session 75 v6.4 rule 분리 / **2026-07-24 Fable 5 전면 개정** (구 5분 TTL·Opus 통일·TeamCreate·Codex 절 폐기 — 구판 역사는 git)

## 모델 라우팅 (**2026-08-29 도훈 지시 개정** — QEPM 전 구간 Opus 통일. 2026-08-08 "가설설계만 Fable" 재핀 대체)

### 현행 규칙 (QEPM 모드)

| 구간 | 에이전트 | 핀 | 근거 |
|---|---|---|---|
| **가설설계** | `alpha-hypothesis` | **`model: opus`** (현행 Opus 5) | Step 0 발굴 + ①메커니즘 →②가설 서술 →③반증 조건 →④국면 경계. ★2026-08-29 Fable→Opus 승격 |
| 그 외 **전 구간** | `alpha-research` · `risk-research` · `optimizer-research` · `forge` · `judge` (+ ondemand `architect` · `blender` · `book-tracker`) | **`model: opus`** (현행 Opus 5) | 구현·측정·판정 구간 |

- **★구간 분리는 유지한다 — 이제 근거가 모델이 아니라 역할이다**: 2026-08-08 분리의 동기는 "단일 에이전트에 모델을 부분 적용할 수 없다" 였고 2026-08-29 통일로 그 동기는 소멸했다. 그러나 분리는 남는다 — **설계자≠측정자 방화벽**이 스폰 경계로만 강제되기 때문이다(프롬프트 문구는 아무것도 강제하지 않는다). 6-agent 파이프라인 *구조*는 불변(alpha-hypothesis 는 alpha 내부 구간 분리이지 추가 심사 단계가 아님).
- **핸드오프 계약**: `alpha-hypothesis` → `qepm/mailbox/worktask/{WT_id}/alpha_hypothesis.json` → `alpha-research` 가 **승계(재작성 금지)** 후 ⑤ AST 구성부터. `verdict: "economic_void"` 면 하류 진행 금지·Q-Lead escalate. 부재 시 alpha-research 가 **동기** spawn(배경 실행 후 "대기 중" 종료 = 체인 절단).
- **alias 의미**: `opus` 는 tier alias로 **현행 최신 tier로 해석**된다(2026-08-29 기준 Opus 5). 구판(2026-07-24)이 `model: opus`를 "Opus 4.8 고정"으로 기록한 것은 *그 시점 최신 Opus tier가 4.8이었기 때문*이지 alias가 버전을 얼리기 때문이 아니다 — 다만 **tier 드리프트는 실사고 이력이 있으므로**, 세션 모델보다 낮은 tier로 해석될 소지가 보이면 재확인할 것.
- **다른 모드는 무핀 유지**: `alpha-search`(②) · `dispatch-orchestrator`(③) · `ramp-orchestrator`(④) · `strategy-implementer` 는 핀 없음 = 세션 모델 상속. 본 규칙은 **QEPM 모드 한정**.
- **폴백 정책 (도훈 2026-07-14, memory: feedback-model-fallback-fable-opus)**: ★2026-08-29 통일로 Fable 폴백 경로는 **무효**가 됐다(가설설계가 이미 opus). 상태가 FS(mailbox/stage_artifacts) 외부화라 모델 전환은 여전히 무손실이며, `alpha_hypothesis.json::model_tier` 에 실제 tier 를 기록하는 의무는 유지한다.
- 구 "전 모델 통일 최신 Opus" 정책(2026-04-30 Block A — Forge Sonnet fabrication L-249 재발방지)의 취지 **"세션 모델 미만 강등 핀 금지"** 는 계승 — 현행 핀 1종(opus)이라 강등 없음. 2026-08-29 통일은 사실상 그 구판 취지로의 복귀다.

### 대체된 구판 (역사)
- **2026-08-08 (도훈 지시)**: 가설설계 `alpha-hypothesis` 만 `model: fable`, 나머지 QEPM 전 구간 `opus`. → **2026-08-29 도훈 지시로 대체**(가설설계도 Opus 5). 근거: 설계 구간이 라운드 판정을 좌우하는 교란 포착(3축 교란·논문 효과크기 prior)을 실제로 만들어냈고, 그 판단 품질이 사이클 비용보다 우선한다.
- 세션 모델 = Fable 5 단일 상속 / 에이전트 `model` 핀 원칙 제거(11종) / 예외 2종(`execution`·`monitoring` opus) / "이 2종 외 신규 핀 추가 금지". → **2026-08-08 도훈 지시로 폐기**. 그 예외 2종은 이제 "QEPM 전체 opus" 규칙에 포섭돼 별도 예외가 아니다.
- **effort 배치 (유효값 low/medium/high/xhigh/max)**: judge/governor/dispatch-orchestrator/ramp-orchestrator = `xhigh`(판정-critical), alpha-hypothesis/alpha-research/alpha-search/forge/risk-research/optimizer-research = `high`. 미지정 = 세션 상속. (effort 는 model 핀과 독립 — 2026-08-08 재핀에서 불변)

## 캐시 히트 최대화 (Fable 5 세션 실측 기준)

- 이 환경의 prompt cache TTL = **1시간** (2026-07-24 실측 확인 — 구 "5분 TTL" 전제 폐기. 참고: 1h TTL은 API 일반론상 write premium 2x라 구판의 절감 산술은 성립하지 않음).
- **CLAUDE.md + 코어 룰 6종 = 안정 prefix**: 세션 중 수정은 이후 전체 캐시를 무효화하므로 자제. 개정은 세션 경계에서.
- Agent 스폰 prefix 공유: `02_Infrastructure/prompts/*_init.md` 공통 헤더 + `_shared_prefix.md` — 첫 스폰 이후 캐시 히트.

## ScheduleWakeup / 대기 규칙 (2026-07-24 개정)

- 구 "`delaySeconds ≤ 270` 권장 / 270 아니면 1200+ 점프" 규칙 **폐기** — 5분 TTL 산술의 산물로, 1시간 TTL에서는 근거가 소멸(60~3600s 전 구간 캐시 유효).
- 대기 주기는 캐시가 아니라 **기다리는 대상의 실제 변화 속도**로 결정: ① 외부 상태 폴링(CI/원격 큐) = 그 상태의 실제 갱신 주기 ② 하네스-추적 백그라운드 작업 = 폴링 금지(완료 통지 자동) + 폴백 하트비트 1200s+ ③ 무신호 idle = 1200~1800s.
- 캐시 유지 목적의 wakeup 남발 = 순수 낭비 (금지).

## 메모리 autoload

- `MEMORY.md` 인덱스는 매 세션 자동 로드 (선두 200줄 / 25KB 한도) — 메모리 1건 = 인덱스 1줄 유지, 본문은 topic 파일에.
- topic 파일(`memory/*.md`)은 온디맨드 Read만.

## 하네스 동결 (완화 개정)

- 코어 룰 6종 + CLAUDE.md의 **세션 내** 빈번 수정 자제는 유지 (캐시 안정 + 규범 안정).
- 단 "동결" ≠ 개정 금지 — stale 정합 수리는 세션 경계에서 정상 수행한다 (2026-07-24 Fable 5 개정이 선례. 구판의 "구조 동결" 절대 문구는 5분 TTL 시대 최적화였음).

## Change log

- 2026-07-24: Fable 5 전면 개정 — TTL 5분→1시간 실측 반영, 모델 라우팅 절 재작성(opus 핀 11종 제거 + 폴백 정책), ScheduleWakeup ≤270s 폐기, TeamCreate(v53 폐지)·Codex 결과 수신(v8.2 폐지) 절 삭제, 메모리 autoload 절을 현행 MEMORY.md 체계로 교체.
