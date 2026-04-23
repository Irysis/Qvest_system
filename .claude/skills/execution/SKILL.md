---
name: execution
description: QEPM Execution Agent skill. Deployment WT의 optimization_package 수신 후 trade_list + TWAP/VWAP schedule + impact estimate + realized slippage logging. target_weights 수정 절대 금지.
---

# Execution Skill — v6.1 R8

## 언제 사용
- Deployment WT가 OPTIMIZER_DONE 도달 후
- optimization_package.json이 infeasibility_report == null
- rebalance_date 임박 시

## 구동 흐름
1. optimization_package.json 로드
2. current_holdings.csv 로드 (현 포지션)
3. buy/sell 계산: `Δw = target_w - current_w` → shares 변환
4. 주문별 ADV ratio 계산
5. schedule 결정 (TWAP / VWAP / POV / rollback)
6. impact 추정 (linear × sqrt blend)
7. execution_package.json 저장
8. 실집행 후 realized_slippage_{date}.csv 기록

## 금지
- target_weights 수정 → Optimizer 영역
- alpha 재해석 → Alpha 영역
- 신규 종목 추가 → Forge/Judge 영역

## 관련 파일
- `.claude/agents/execution.md`
- `02_Infrastructure/prompts/execution_init.md`
- `qepm/mailbox/execution/{inbox,done}`
