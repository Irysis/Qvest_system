# STR_1631 VD+ 프로덕션 운용 매뉴얼
# 승격일: 2026-04-09 | 버전: 1.0

## 전략 요약

| 항목 | 값 |
|------|-----|
| 전략 ID | STR_1631_SYN_05_2002_VDplus |
| 백테스트 기간 | 2003-01 ~ 2026-03 (23년) |
| CAGR | 19.14% |
| Sharpe | 1.243 |
| MDD | 25.43% |
| Sortino | 1.772 |
| Calmar | 0.752 |
| Turnover | 301.2%/yr |
| N Holdings | 20 |
| Rebalance | 격월 (bimonthly) |

## 전략 구조

```
Layer 1: Factor Scoring
  C19 Composite = IC-weighted(C01_SUE + C09_ESBR + C06_EPS1M + C07_TPGap)
  IC weights: expanding window, 격월 갱신

Layer 2: Universe Filter (SYN_05)
  LIQ >= 200M KRW (20d avg trading value, t-1 month)
  MAX21d <= 80th percentile (t-1 month)
  Analyst coverage >= 3

Layer 3: Stock Weighting
  60% HRP (Gerber + RMT denoised covariance)
  40% Score Tilt (C19 score 비례)

Layer 4: Rebalancing
  격월 (홀수월/짝수월 — config에서 설정)
  Buffer zone: keep_n=35, entry_n=20

Layer 5: Regime Overlay (VD+)
  MRS < 20 (Normal): 100% equity
  MRS 20-50 (Caution): exposure 축소 시작
  MRS >= 50 (Crisis, 3일+ 지속): 40% factor + 30% inverse ETF + 30% cash
  DD Brake: 10% drawdown → exposure 50%, 25% recovery → 복귀
```

## 일간 운용 프로세스

### 매일 (자동)
```
00:03  daily_refresh.sh (crontab)
       → RAWDATA, Benchmark, Factor DB 갱신
       → MRS 재계산 (regime_engine_daily.R)

이후   Q-Lead 확인:
       1. generate_mrs_dashboard() → MRS 현재값 + 국면 확인
       2. MRS 국면 전환 여부 체크
       3. DD brake 트리거 여부 체크
```

### MRS 국면 전환 시 (즉시 실행)
```
Normal → Caution (MRS >= 20):
  → 모니터링 강화, 아직 매매 불필요

Caution → Crisis (MRS >= 50, 3일 연속):
  → 즉시 실행:
    1. 보유 주식 60% 매도
    2. KODEX 인버스 (252670) 30% 매수
    3. 나머지 30% 현금 보유
  → 텔레그램 알림 발송

Crisis → Normal (MRS < 20, 5일 연속):
  → 즉시 실행:
    1. KODEX 인버스 전량 매도
    2. 다음 리밸런싱 시 정상 포트폴리오 재구축
  → 텔레그램 알림 발송
```

### DD Brake (즉시 실행)
```
포트폴리오 고점 대비 -10% drawdown 도달:
  → equity exposure 50% 축소 (나머지 현금)

고점 대비 -25% 도달:
  → 전량 청산 → 전략 재검토

Drawdown 회복 (고점 대비 -5% 이내):
  → 정상 exposure 복귀
```

### 격월 리밸런싱 (D-2 ~ D+1)
```
D-2 (월말 2거래일 전):
  1. data-refresh 실행 (최신 데이터 확인)
  2. Factor DB 갱신 확인

D-1 (월말 1거래일 전):
  1. pm_run() 실행 → 매매안 생성
  2. 텔레그램으로 매매안 발송
  3. 매매안 검토 (종목 수, 회전율, 이상 종목)

D+1 (월초 첫 거래일):
  1. 시가 또는 VWAP으로 매매 실행
  2. 실행 확인 후 포트폴리오 업데이트
  3. 실행 보고 텔레그램 발송
```

## 인버스 ETF

| 상품 | 코드 | 용도 |
|------|------|------|
| KODEX 인버스 | 252670 | Crisis 배분 (30%) |
| 비권장: KODEX 200선물인버스2X | 253250 | 일간 리셋 + 변동성 drag |

## 리스크 관리 규칙

### Hard Stop
- 실투 시작 후 6개월 내 SR < 0 → 전략 재검토
- 실투 MDD > 30% → 즉시 중단 + Judge 검증
- 3회 연속 리밸런싱에서 BM 대비 underperform → 원인 분석

### 모니터링 지표 (주간)
| 지표 | 정상 | 주의 | 위험 |
|------|------|------|------|
| MRS | < 20 | 20-50 | >= 50 |
| DD from peak | < 5% | 5-10% | > 10% |
| 월간 SR (rolling 12m) | > 0.8 | 0.5-0.8 | < 0.5 |
| Turnover | < 40%/리밸 | 40-60% | > 60% |

## 비용 구조 (실투)

| 항목 | 예상 |
|------|------|
| 증권거래세 | 0.23% (매도 시) |
| 위탁수수료 | ~0.015% (온라인) |
| 편도 총비용 | ~0.245% |
| 왕복 (매수+매도) | ~0.26% |
| 백테스트 가정 | 0.15% 편도 |
| 실투 추가 비용 | ~0.11%/편도 |
| 예상 실투 SR | 1.0 ~ 1.1 (백테스트 1.243 대비 -10~15%) |

## 인프라 체크리스트

- [ ] daily_refresh.sh crontab 동작 확인
- [ ] generate_mrs_dashboard() 정상 실행
- [ ] 텔레그램 bot 연결 확인
- [ ] pm_run() 매매안 생성 테스트
- [ ] KODEX 인버스 (252670) 매매 가능 확인
- [ ] 증권 계좌 자금 확인

## 파일 경로

| 파일 | 위치 |
|------|------|
| 전략 코드 | 04_Research/strategies/STR_1631_SYN_05_2002/ |
| VD+ overlay | 04_Research/strategies/STR_1631_PG2_MDD_OPT/ |
| Regime engine | 02_Infrastructure/regime/regime_engine_daily.R |
| Portfolio manager | 02_Infrastructure/portfolio/ |
| 이 매뉴얼 | 02_Infrastructure/docs/STR_1631_VDplus_operation_manual.md |

## 변경 이력
- 2026-04-09: 초판 작성 (Session 56)
