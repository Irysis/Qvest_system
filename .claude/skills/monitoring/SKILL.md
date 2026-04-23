---
name: monitoring
description: QEPM Monitoring Agent skill. Admitted Deployment WT 대상 월간 drift 감지. Realized vs Predicted α/TE + crowding drift + signal decay + regime shift alert. 전략 수정/weight 변경 금지.
---

# Monitoring Skill — v6.1 R9

## 언제 사용
- 매월 1일 Cron 자동
- Q-Lead 세션 종료 Stop hook
- 사용자 온디맨드 요청

## 구동 흐름
1. `book_state.json` 로드 → admitted_ids 순회
2. 각 WT의 optimization_package (predicted) 로드
3. `.cache/realized_returns/{wt_id}_{month}.parquet` 로드
4. 5 metric 계산 (alpha_ratio / te_ratio / crowding_drift / ic_decay / regime_shift)
5. threshold 초과 시 alert 플래그
6. monitoring_report_{YYYYMM}.json 저장
7. Telegram 발송

## 금지
- 전략 수정 / weight 변경 / WT 생성
- 합리화 ("일시 drift", "곧 돌아올 것")

## 관련 파일
- `.claude/agents/monitoring.md`
- `02_Infrastructure/prompts/monitoring_init.md`
- `qepm/mailbox/monitoring/{inbox,reports,done}`
