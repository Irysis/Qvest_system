#!/usr/bin/env Rscript
# paper router v2 telegram summary — 20260803
suppressWarnings(suppressMessages({ library(jsonlite) }))

root_candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR",""), Sys.getenv("QM_ROOT",""), getwd()))
is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p,"02_Infrastructure/config.R"))
root <- Filter(is_root, root_candidates)[[1]]
source(file.path(root, "02_Infrastructure/config.R"))
source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent      = "AlphaSearch",
  title      = "논문 라우터 v2 — 리서치 소스 배분 + 팩터 마이닝 (20260803)",
  relaxed    = TRUE,
  force      = TRUE,
  lock_scope = "paper_router_20260803",
  sections   = list(
    list(
      header = "리서치 소스 배분 결과",
      body   = paste0(
        "오늘 분석 논문: 38편 (arXiv) + curated 0편 신규\n",
        "• alpha: 1편\n",
        "• optimizer: 1편\n",
        "• risk: 3편\n",
        "• regime: 2편\n",
        "• skip: 31편\n\n",
        "팩터후보 testable: 1건 | uncertain: 1건\n",
        "AUTORUN 대상: 1편 (VoltRank_MC)"
      )
    ),
    list(
      header = "AUTORUN — alpha-search 에이전트 스폰",
      body   = paste0(
        "[1/1] VoltRank_MC (arxiv:2607.27461)\n",
        "논문: \"Are Three Matrices All You Need To Beat the Market?\"\n",
        "신호: 변동성 순위 Markov 전이 → 저변동성 예측 종목 long\n",
        "근거: S&P500에서 vol-rank 1기간 예측 가능, Sharpe 1.08~1.44 실증\n",
        "alpha-search 에이전트 실행 중..."
      )
    ),
    list(
      header = "팩터후보 testable",
      body   = paste0(
        "VoltRank_MC (arxiv:2607.27461 · route=alpha)\n",
        "정의: 월별 20일 RV 순위 → 12M rolling Markov 전이행렬 → 예측순위 낮은 종목 long\n",
        "신규성: D01/R12 단순 저변동성과 달리 전이 예측 프레임\n",
        "KR 구현: RAWDATA 가격만 사용, PIT 클린"
      )
    ),
    list(
      header = "optimizer/risk/regime 큐",
      body   = paste0(
        "[optimizer] 2607.01705 \"Portfolio Optimization under Fast and Slow Latent Drift\"\n",
        "  → MACD = Kalman 필터 잠재 drift 추정치 도출. α̂ 고정 A/B 대상\n\n",
        "[risk] 2607.24410 \"The Fundamental Structure of Risk\" (CD-DFM 특성→공분산)\n",
        "[risk] 2607.25459 \"Emergent Latent-State Computation under SV\"\n",
        "[risk] 2607.25189 \"Long-memory GARCH via 2D Markov chain\"\n\n",
        "[regime] 2607.27063 China A주 군집지표 CSAD → KR 오버레이 가능\n",
        "[regime] 2607.19497 \"Science and Practice of Trend-Following\" → 저주파 스펙트럼 질량"
      )
    )
  )
)

cat("\n[paper_router_20260803] telegram sent OK\n")
