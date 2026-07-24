# Caching + Model Routing Discipline (Level 0)

**발효**: Session 68 Day 2 도입 / Session 75 v6.4 rule 분리 / **2026-07-24 Fable 5 전면 개정** (구 5분 TTL·Opus 통일·TeamCreate·Codex 절 폐기 — 구판 역사는 git)

## 모델 라우팅 (2026-07-24 Fable 5 정합 개정)

- **세션 모델 = Claude Fable 5** (`claude-fable-5`, Mythos-class — Opus 4.8 상위 tier).
- **에이전트 frontmatter `model` 핀 = 전면 제거** (2026-07-24 실측 11종 제거): 핀 부재 = 세션 모델 상속(공식 스펙 기본값 inherit). 구 `model: opus`는 "자동 최신"이 아니라 **Opus 4.8 고정**이라, Fable 5 세션에서 spawn 에이전트가 메인보다 하위 모델로 강등되던 결함.
- **폴백 정책 (도훈 2026-07-14, memory: feedback-model-fallback-fable-opus)**: Fable 5 한도/스폰 실패 시 Agent tool 호출에 `model: "opus"` 명시 재시도. 상태가 FS(mailbox/stage_artifacts) 외부화라 모델 전환 무손실.
- 구 "전 모델 통일 최신 Opus" 정책(2026-04-30 Block A — Forge Sonnet fabrication L-249 재발방지)의 취지는 **"세션 모델 미만 강등 핀 금지"** 원칙으로 계승.
- **effort 배치 (유효값 low/medium/high/xhigh/max)**: judge/governor/dispatch-orchestrator/ramp-orchestrator = `xhigh`(판정-critical), alpha-research/alpha-search/forge/risk-research/optimizer-research = `high`(Fable 5 기본 권고 정합). 미지정 = 세션 상속.

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
