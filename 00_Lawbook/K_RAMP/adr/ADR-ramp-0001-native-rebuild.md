# ADR-ramp-0001: RAMP을 원본 Qvest에 네이티브 재구축 (Qvest_Codex 경로 비의존)

Date: 2026-06-17
Status: Accepted

## Context
도훈이 K-RAMP 체계를 원본 Qvest(`Quant_Module_Moltbot`)에 4번째 모드로 구축 요청. K-RAMP 소스 통합본은 `Qvest_Codex/00_Lawbook/K_RAMP/`에 존재하고, Qvest_Codex에 이미 별도 K-RAMP 빌드(`02_Infrastructure/kramp/...`)가 있다. **원본은 Qvest_Codex와 완전 별개 시스템** — 경로 공유 금지(도훈 mandate).

## Decision
RAMP을 원본 Qvest 디렉토리(`02_Infrastructure/ramp/`·`04_Research/ramp/`·`06_Registry/ramp/`·`.claude/`)에 **네이티브 재구축**한다. K-RAMP 통합본은 `00_Lawbook/K_RAMP/`로 복사해 self-contained화. **어떤 RAMP 산출물도 `Qvest_Codex` 경로를 참조하지 않는다**. `AGENTS.md` 도입 금지(Qvest_Codex 산물). reuse-first: 기존 Qvest 계약(canonical_screen_bt/essence_score/regime/axiom) 재사용, GAP만 신규.

## Alternatives Considered
1. Qvest_Codex 빌드를 import/symlink — 기각(분리 위반).
2. K-RAMP 전용 monorepo 트리(python/kramp/, R/) 신설 — 기각(Qvest 디렉토리 재사용이 정합).

## Consequences
- (+) 분리 보장, reuse로 중복 최소, 기존 거버넌스/공리 엔진과 한 몸.
- (−/risk) "Codex" 역할을 Q-Lead+agents로 분산 — 가이드북의 단일 Codex 가정과 매핑 필요.

## Metrics affected
ACS, DGS, separation grep gate (empty).

## Rollback plan
`02_Infrastructure/ramp/`·`04_Research/ramp/`·`06_Registry/ramp/`·`.claude/{commands,skills,agents}/ramp*` 삭제 + CLAUDE.md/modes_sot 4-Mode 되돌림.

## Related Files
`02_Infrastructure/docs/rules/ramp.md`, `.claude/skills/ramp/SKILL.md`, `C:/Users/99922/.claude/plans/misty-imagining-feather.md`
