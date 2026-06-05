#==============================================================================
# Forge Telegram Brief — WT-D20260527_001 STR_1719_WT001_DCA_v7
# v6.5 용어 규칙: 통상 영어 retain (Forge / Codex / Sharpe / MDD / TO / NW / DSR)
#==============================================================================

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

suppressMessages({library(jsonlite); library(data.table)})

pkg <- fromJSON("qepm/mailbox/worktask/WT-D20260527_001/forge_package.json")
s <- pkg$backtest_metrics

sections <- list(
  list(
    emoji = "📊",
    heading = "Backtest Metrics (2016-01 ~ 2024-01, 1986 거래일)",
    type = "kv",
    kv = list(
      "연복리수익률" = sprintf("%.2f%% (KOSPI200 %.2f%%, 알파 +%.2f%%)",
        s$cagr_pct, s$benchmark_cagr_pct, s$cagr_pct - s$benchmark_cagr_pct),
      "Sharpe 지수" = sprintf("%.4f (KOSPI200 %.4f)", s$sharpe, s$benchmark_sharpe),
      "최대낙폭" = sprintf("%.2f%% (KOSPI200 %.2f%%, 1.38배)",
        s$mdd_pct, s$benchmark_mdd_pct),
      "정보계수 IR" = sprintf("%.4f", s$information_ratio),
      "추적오차 TE" = sprintf("%.2f%%", s$tracking_error_pct),
      "베타" = sprintf("%.3f", s$benchmark_beta),
      "상승/하락 캡쳐" = sprintf("%.3f / %.3f", s$up_capture, s$down_capture),
      "벤치마크 적중률" = sprintf("%.3f", s$hit_ratio_vs_bm),
      "회전율 실현치" = "5.25/년 (2-side, Charter 6.0 cap 이하)",
      "최적화 방법" = "M06_MVO_Breadth (n=15, max_w 0.130)"
    ),
    notes = c(
      "PerformanceAnalytics 표준 함수만 사용 (Return.annualized / SharpeRatio.annualized / maxDrawdown / table.Drawdowns)",
      "Net-of-cost 15bps × |Δshares| × price (delta-share commission)"
    )
  ),
  list(
    emoji = "🚨",
    heading = "허들 게이트 결과",
    type = "bullet",
    items = c(
      "최대낙폭 허들: 실패 (59.74% > 45% 하드 한도)",
      "최대낙폭 시점: 2018-02-02 고점 → 2020-03-23 저점 (코로나-19), 회복 2021-03-18",
      "KOSPI200 동일기간 최대낙폭: 43.25% → 전략/벤치마크 비율 1.38배 (소형주 노출 영향)",
      "회전율 허들: 통과 (연 5.25 < 한도 6.0)",
      "하드 제약 (종목수/가중치/Σw=1/롱온리/비용): 모두 통과",
      "순수함수 경계: alpha/risk/opt/weights md5 시작=종료 일치 통과"
    )
  ),
  list(
    emoji = "⚔️",
    heading = "Codex 비평 라운드 1",
    type = "bullet",
    items = c(
      "Codex 입장: 거부 (높음 4건 + 중간 3건 우려사항)",
      "최약 가정: '백테스트 감사 경고만으로 진행 가능' — 최대낙폭 허들 위반 누락",
      "첫째 우려 (최대낙폭) 높음 → 전수용: 인테그리티 허들실패로 격상",
      "둘째 우려 (Lockbox 연장) 높음 → 반박: 룰북 도훈 결정 forge 단계 폐기",
      "셋째 우려 (다중 회귀모형) 높음 → 부분수용: Forge 역할 통합, Judge에서 Gate 실행",
      "넷째 우려 (메가 베이스라인) 높음 → 부분수용: 교차 작업 비교는 Judge 단계",
      "다섯/여섯/일곱째 (TO 단위 / 해시감사 / 경로) 중간 → 모두 전수용"
    )
  ),
  list(
    emoji = "🔗",
    heading = "Sharpe 출처 + 순수함수 결과",
    type = "bullet",
    items = c(
      sprintf("주측정 Sharpe (일별 주식수 기반): %.4f (운용등급 기준)", pkg$sr_realized_share_based),
      sprintf("팩터엔진 Sharpe (월별 이상화): %.4f", pkg$sr_factor_engine_continuous),
      sprintf("괴리 %.4f pp → 무시가능 밴드 (NEGLIGIBLE)",
              pkg$vs_factor_engine$divergence_factor_engine_vs_realized_pp),
      "주측정 기준: forge_realized_share_based (운용등급 PG2 grade)",
      "순수함수 경계: 4개 패키지 md5 시작=종료 일치 (alpha/risk/opt/weights)",
      "스케줄 밀도: 1.000 (97/97 시점 — 조작 없음)"
    )
  ),
  list(
    emoji = "➡️",
    heading = "삼각검증 결과 + 다음 단계",
    type = "bullet",
    items = c(
      "Forge 자체: 허들실패 인정 (최대낙폭 59.74% > 45% 허들)",
      "Codex 비평: 거부 (최대낙폭 + 다중 회귀모형 보류 + 베이스라인 보류)",
      "Forge + Codex 같은 결론 — 통과 2건 중 0건 (Architect 미투입)",
      "추천: Judge 단계로 진행 (허들실패 표시)",
      "Judge 옵션 가) 작업 종료 나) optimizer M11_CVaR 대체방안 다) alpha 방어형 재구성",
      "백테스트 계약 감사는 15/16 통과 (허들실패와는 별개)"
    )
  )
)

result <- tg_agent_brief(
  agent = "Forge",
  title = "WT-D20260527_001 Forge — STR_1719 DCA v7 통합완료 (MDD 허들 FAIL)",
  sections = sections,
  as_of = "2026-05-27",
  charts = c(
    "04_Research/strategies/STR_1719_WT001_DCA_v7/output/equity_curve.png",
    "04_Research/strategies/STR_1719_WT001_DCA_v7/output/drawdown_chart.png"
  ),
  footer = "순수함수 v6.1 R12 통과 / 백테스트계약 15-16 통과 / 최대낙폭 허들 실패 (Judge 격상)",
  emoji_min = TRUE
)

cat(sprintf("Telegram brief 전송: ok=%s\n", isTRUE(result$ok)))
