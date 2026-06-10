# Caching Discipline (Level 0)

**Anthropic prompt cache 5분 TTL. 세션 토큰 비용 핵심 절감 레버.**
**Session 68 Day 2 도입 / Session 75 v6.4 rule 분리**

## 모델 라우팅 (Block A 도훈 결정 2026-04-30, 2026-06-10 현행화)

**최신 Opus [1M context] — 전 모델 통일** (2026-06-10 현재 Opus 4.8 [1M]):
- 모든 agent: Q-Lead / Judge / Risk Manager / Scout / Forge / Governor / Alpha-Research / Risk-Research / Optimizer-Research / Architect / Blender / Execution / Monitoring / Academic / Quant
- frontmatter `model: opus` alias = 자동 최신 Opus 가리킴 (버전 명시는 본 라인 1곳만 — 모델 교체 시 여기만 갱신)
- **격상 사유**: WT-D20260429_001 첫 정식 lifecycle에서 Forge Sonnet이 frequency mislabel fabrication (Sharpe 6.94× inflate) 산출 → Charter v1.4 §9 FABRICATION_SUSPECTED 첫 발동 (L-249).
- 이전 정책 (deprecated 2026-04-30): Sonnet 4.6 downgrade

## 캐시 히트 최대화

- **CLAUDE.md 상단 동결**: Level 0 규칙·Axiom·Gate는 불변. 수정은 별도 PR/lawbook amendment 필요. 안정된 prefix = 높은 cache hit.
- **Init prompts 공통 헤더**: `02_Infrastructure/prompts/*_init.md` 6종의 상단 80%는 공통 블록. Agent 스폰 시 prefix 캐시 공유.
- **TeamCreate teammate**: 4인 teammate가 같은 세션에서 공유된 prefix 반복 사용 → 첫 스폰 이후 캐시 히트로 절감.

## ScheduleWakeup 사용 규칙

- `delaySeconds ≤ 270` 권장 (5분 TTL 내 유지). **60~270초** = 캐시 유효
- `300~3600초` = cache miss 감수
- "1~5분 애매 구간 금지" — 270 아니면 1200+ 점프
- **절대 금지**: 짧은 sleep (300~500초) 여러 번 → 매번 cache miss 누적

## 메모리 autoload 최소화

세션 시작 시 MEMORY.md 인덱스의 "매 세션 로드" 그룹만:
- next_session_task
- methodology_active
- strategy_catalog
- evolution_roadmap
- production_patterns

feedback은 `feedback_INDEX.md` 1건만 autoload. 개별 `feedback_*.md`는 필요 시 Read.

methodology_archive.md (L-000 ~ L-129)는 온디맨드만. active에 없는 L-code 참조 필요 시 Read.

## Codex 결과 수신

- Codex verdict JSON 전체를 Claude context로 적재 금지
- `run_codex_critic*.sh`가 `jq`로 필요 필드만 반환
- 전체 JSON은 `/tmp/codex_*_result.json` 감사용 보존
- 필요 시 Q-Lead가 명시 Read

## 하네스 동결

이 section + Axioms + Safety Rules의 구조는 동결. 변경 시 prefix cache 무효화 → 전체 세션 재계산 비용 발생.
