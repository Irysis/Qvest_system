---
name: production-management
description: "프로덕션 포트폴리오 운용 스킬 — 리밸런싱, MRS 모니터링, DD brake, 매매안 생성, 인버스 전환. pm_run() 호출 시 적용."
---

## 프로덕션 포트폴리오 운용 규칙

### 적용 대상
05_Production/에 승격된 전략의 실투 운용. 현재: STR_1631 VD+ (1-1.STR_1631_VDplus_CoreAlpha)

### 일간 모니터링 (매일 수행)

**1. MRS 확인**
```r
source(file.path(INFRA_DIR, "reports/mrs_dashboard.R"))
result <- generate_mrs_dashboard(send_telegram = TRUE)
# result$current_mrs, result$current_phase
```
- MRS < 20 (Normal): 정상 운용
- MRS 20-50 (Caution): 모니터링 강화
- MRS >= 50 (3일 연속 Crisis): **즉시 인버스 전환** (아래 참조)

**2. DD Brake 확인**
```r
# 포트폴리오 고점 대비 drawdown 계산
current_dd <- (peak_nav - current_nav) / peak_nav
```
- DD >= 10%: exposure 50% 축소 (나머지 현금)
- DD >= 25%: 전량 청산 → 전략 재검토
- DD < 5% (회복): 정상 exposure 복귀

### MRS 국면 전환 (즉시 실행 — 격월 리밸런싱 기다리지 않음)

**Normal → Crisis (MRS >= 50, 3일 연속)**
1. 보유 주식 60% 매도
2. KODEX 인버스 (252670) 30% 매수
3. 나머지 30% 현금 보유
4. 텔레그램 알림 발송
```r
tg_agent_brief(agent = "Q-Lead", title = "CRISIS 전환 실행",
  sections = list(
    list(type = "summary",
         body = "시장 국면 점수 50+ 3일 연속. 인버스 30% + 현금 30% 즉시 실행."),
    list(type = "kv", emoji = "\U0001F6A8", heading = "변경",
         kv = list("주식 매도" = "60%", "KODEX 인버스" = "30%", "현금" = "30%")))
```

**Crisis → Normal (MRS < 20, 5일 연속)**
1. KODEX 인버스 전량 매도
2. 다음 격월 리밸런싱 시 정상 포트폴리오 재구축
3. 텔레그램 알림 발송

**인버스 ETF**: KODEX 인버스 (252670) 권장. KODEX 200선물인버스2X (253250) 금지 (일간 리셋 + 변동성 drag).

### 격월 리밸런싱 프로세스

**D-2 (월말 2거래일 전)**
1. data-refresh 실행
```bash
bash 02_Infrastructure/ops/daily_refresh.sh
```
2. Factor DB 갱신 확인
3. MRS 현재 국면 확인

**D-1 (월말 1거래일 전)**
1. pm_run() 실행 → 매매안 생성
```r
source(file.path(INFRA_DIR, "portfolio/pm_run.R"))
pm_result <- pm_run("STR_1631_VDplus")
```
2. 매매안 검토: 종목 수, 회전율, 이상 종목
3. 텔레그램으로 매매안 발송 (SOT: `.claude/skills/qvest-telegram/SKILL.md`)
```r
tg_agent_brief(agent = "Q-Lead", title = "격월 매매안",
  sections = list(
    list(type = "summary", body = format_trade_summary_oneline(pm_result)),
    list(type = "table", emoji = "📊", heading = "매매안",
         df = format_trade_df(pm_result, ncol_max = 3))))
```

**D+1 (월초 첫 거래일)**
1. 시가 또는 VWAP으로 매매 실행
2. 실행 확인 후 포트폴리오 업데이트
3. 실행 보고 텔레그램 발송

### 비용 관리

| 항목 | 백테스트 | 실투 |
|------|---------|------|
| 편도 수수료 | 15bps | ~24.5bps (거래세 23bp + 위탁 1.5bp) |
| 슬리피지 | 0 | 10~30bps (종목 유동성 따라) |
| 인버스 ETF | 이상적 | 추적오차 + 롤오버 연 1~2% |
| **실투 SR 할인** | 1.243 | **예상 1.0~1.1 (-10~15%)** |

### Hard Stop 규칙

| 조건 | 조치 |
|------|------|
| 실투 6개월 내 SR < 0 | 전략 재검토 |
| 실투 MDD > 30% | 즉시 중단 + Judge 검증 |
| 3회 연속 BM 대비 underperform | 원인 분석 |
| MRS 데이터 소스 장애 | FRED 대체 소스 확인 또는 수동 국면 판단 |

### 주간 모니터링 체크리스트

| 지표 | 정상 | 주의 | 위험 |
|------|------|------|------|
| MRS | < 20 | 20-50 | >= 50 |
| DD from peak | < 5% | 5-10% | > 10% |
| Rolling 12m SR | > 0.8 | 0.5-0.8 | < 0.5 |
| 리밸런싱 회전율 | < 40% | 40-60% | > 60% |
| 인버스 ETF 괴리율 | < 0.5% | 0.5-1% | > 1% |

### 텔레그램 보고 (자동)

**일간**: MRS 알림 (국면 전환 시만)
**격월**: 리밸런싱 매매안 + 실행 보고
**주간**: 포트폴리오 성과 요약 (SR/DD/종목)
**즉시**: DD brake 트리거, Crisis 전환, Hard stop

### 관련 인프라

| 파일 | 용도 |
|------|------|
| `02_Infrastructure/portfolio/pm_run.R` | 매매안 생성 |
| `02_Infrastructure/portfolio/promote_to_production.R` | 프로덕션 승격 |
| `02_Infrastructure/regime/regime_engine_daily.R` | MRS 계산 |
| `02_Infrastructure/reports/mrs_dashboard.R` | MRS 대시보드 + 텔레 발송 |
| `02_Infrastructure/telegram/telegram_notify.R` | 텔레그램 API |
| `02_Infrastructure/docs/STR_1631_VDplus_operation_manual.md` | 운용 매뉴얼 |
| `05_Production/1-1.STR_1631_VDplus_CoreAlpha/` | 프로덕션 코드 |

### Tail Risk 모니터링 (신규 — Pfaff Ch.7/8)
```r
source(file.path(INFRA_DIR, "portfolio/tail_risk_engine.R"))
source(file.path(INFRA_DIR, "regime/regime_garch.R"))

# 일간 EVT-VaR 모니터링
tail_risk <- compute_evt_var(recent_60d_returns, p = 0.99)
if (tail_risk$var_evt > VAR_LIMIT) → exposure 축소 alert

# DCC-GARCH 상관 감시
dcc <- fit_dcc_garch(sleeve_returns)
# 최근 상관 - 6개월 평균 상관 > 0.3 → diversifier 실효성 경고

# CDaR 실시간 추적
cdar <- compute_cdar(portfolio_nav, alpha = 0.95)
if (cdar$cdar > 0.25) → 리밸런싱 검토
```

### 금지사항

- 05_Production/ 직접 수정 금지 (promote_to_production()만 허용)
- 백테스트 파라미터 사후 변경 금지
- MRS threshold(20/50) 임의 변경 금지 (regime_engine_daily.R 정본만)
- DD brake 파라미터(10/25) 임의 변경 금지
- 리밸런싱 일정 건너뛰기 금지
