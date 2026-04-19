# v54 Freeze Period Enforcement

## 1. 개요

v54 Freeze Period는 Session 67 Day 1 진단 결과(SR 1.193, 목표 2.0 대비 -40%)에 기반한
**4주 프로세스 혁신 동결** 기간이다. Alpha-First Rebalance를 위해 프로세스 churn을 기계적으로
차단하고, 백테스트 실행과 전략 연구에 자원을 집중한다.

**원칙**: "엄밀함은 사라지지 않고 이동한다" (Harness Engineering v52) -- 프롬프트 권고가 아닌
Hook으로 강제.

## 2. 기간

| 항목 | 값 |
|------|-----|
| 시작일 | 2026-04-18 (Session 67 Day 1) |
| 종료 예정 | 2026-05-15 (Session 72 평가) |
| 대상 세션 | Session 68 ~ Session 71 |
| 평가 기준 | SR >= 1.50 (gap <= 0.5) |

## 3. 동결 규칙

### 3.1 Admission Rule 동결
- **현 버전**: v3.5.1
- **상태**: 수정/확장/amendment 금지
- **예외**: 하드 블로커(전략이 물리적으로 실행 불가) 발생 시 Q-Lead 승인 후 수정
- **Hook**: `v54_freeze_admission_rule_guard.sh` (PreToolUse[Write|Edit], L3 hard block)

### 3.2 Governor Rev 동결
- **현 버전**: rev8-A-revised_v2 Scenario C
- **상태**: 새 rev 파일 생성 금지. Scenario C 실행만 허용
- **예외**: Q-Lead 승인 (FREEZE_OVERRIDE)
- **Hook**: `v54_freeze_governor_rev_guard.sh` (PreToolUse[Write], L3 hard block)

### 3.3 금요일 실행 전용
- **적용**: KST 기준 매주 금요일 종일
- **차단**: 새 프로세스 파일 (governance_doc, admission_rule, rev*, phase_plan 등) 생성
- **허용**: 백테스트 실행, factor_engine.R/run_all.R 작성, L-code 적립, 허들 판정
- **Hook**: `v54_freeze_friday_exec_only.sh` (PreToolUse[Write], L3 hard block)

## 4. Hook 인프라

### 4.1 등록 현황

| # | Hook | 이벤트 | Tier | 대상 |
|---|------|--------|------|------|
| 18 | v54_freeze_admission_rule_guard.sh | PreToolUse[Write\|Edit] | L3 | Admission Rule 파일 |
| 19 | v54_freeze_governor_rev_guard.sh | PreToolUse[Write] | L3 | Governor rev 파일 |
| 20 | v54_freeze_friday_exec_only.sh | PreToolUse[Write] | L3 | 금요일 프로세스 파일 |

### 4.2 공통 구조

모든 v54 Freeze Hook은 동일한 구조를 따른다:

```
1. ERR trap (안전 fallback: allow)
2. Freeze 기간 확인 (KST 기준 날짜 비교)
3. 도구 정보 파싱 (python3 JSON)
4. 대상 파일 패턴 매칭
5. 허용 예외 확인 (allowlist + FREEZE_OVERRIDE)
6. 차단 + 로그 기록
```

### 4.3 로그 파일

- 통합 로그: `/tmp/v54_freeze_guard.log`
- 기록 내용: 타임스탬프 + BLOCK/OVERRIDE + 파일 경로
- 스냅샷에서 집계하여 텔레그램 보고

## 5. Override 절차

Freeze 기간 중 긴급 수정이 필요한 경우:

1. **Q-Lead에게 보고**: 변경 사유 + 영향 범위 설명
2. **Q-Lead 판단**: 하드 블로커 여부 확인
3. **승인 시**: 파일에 주석 추가
   - R 파일: `# FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true`
   - JSON 파일: `"_freeze_override": "FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true"`
   - Markdown: `<!-- FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true -->`
4. **재시도**: Hook이 override 주석을 감지하여 허용
5. **로그**: `/tmp/v54_freeze_guard.log`에 OVERRIDE 기록

## 6. Friday Alpha Snapshot

### 6.1 실행 주기

매주 금요일 18:00 KST (crontab: UTC 09:00 Friday)

### 6.2 수집 지표

| 지표 | 소스 | 목적 |
|------|------|------|
| SR / CAGR / MDD | `.cache/portfolio_gap_vector.json` | 포트폴리오 현황 |
| Gap (SR/CAGR/MDD) | portfolio_gap_vector.json | 목표 대비 격차 |
| Governor rev count | `qepm/mailbox/governor/outbox/*rev*` | rev churn 모니터링 |
| S0 hit rate (7d) | `stage_artifacts/S0_VERDICT_*.json` | 가설 품질 추적 |
| Freeze violations | `/tmp/v54_freeze_guard.log` | 동결 준수 상태 |

### 6.3 산출물

- **텔레그램 발송**: [Q-Lead] Friday Alpha Snapshot (한글 + 이모지 + 섹션)
- **JSON 저장**: `06_Registry/snapshots/friday_alpha_snapshot_YYYY-MM-DD.json`
- **dry-run**: `FRIDAY_SNAPSHOT_DRYRUN=1` env 설정 시 텔레그램 skip

### 6.4 crontab 등록 (Q-Lead 승인 필요)

```bash
# KST 18:00 = UTC 09:00 금요일
0 9 * * 5 cd /mnt/c/Users/User/OneDrive/바탕\ 화면/Quant_Module_Moltbot && bash 02_Infrastructure/ops/friday_alpha_snapshot.sh >> /tmp/friday_snapshot.log 2>&1
```

## 7. Freeze 해제 조건 (Session 72 평가)

### 7.1 해제 기준

| 조건 | 임계값 | 판단 |
|------|--------|------|
| SR >= 1.50 | gap <= 0.5 | v54 체제 정식 전환 |
| SR < 1.50 | gap > 0.5 | 근본 재진단 (Scout sourcing 전면 개편 검토) |

### 7.2 해제 절차

1. Session 72 시작 시 `friday_alpha_snapshot.sh` 실행 → 최종 상태 확인
2. SR >= 1.50 달성 시:
   - CLAUDE.md v54 Freeze Period 규칙 "정식 전환" 상태로 업데이트
   - Hook의 FREEZE_END 날짜를 제거하거나 연장
3. SR < 1.50 미달 시:
   - Architect 스폰 → Scout sourcing 재설계 제안
   - Freeze 연장 또는 대안 구조 결정

### 7.3 Hook 자동 비활성화

모든 v54 Hook은 `FREEZE_END` 날짜를 초과하면 자동으로 `echo '{}'; exit 0` (통과) 처리.
별도 해제 작업 없이 기간 만료 시 자동 비활성화.

## 8. Cross-Reference

- **CLAUDE.md**: "v54 Freeze Period (2026-04-18 ~ Session 72, Level 0)" 섹션
- **settings.json**: Hook 등록 (PreToolUse entries #18~#20)
- **Hook 파일**: `02_Infrastructure/hooks/v54_freeze_*.sh` (3건)
- **Snapshot**: `02_Infrastructure/ops/friday_alpha_snapshot.sh`
- **Snapshot 저장소**: `06_Registry/snapshots/`

## 변경 이력

| 날짜 | 변경 | 작성자 |
|------|------|--------|
| 2026-04-19 | 초기 작성. Hook 3종 + Snapshot 시스템 설계 | Architect (Session 68) |
