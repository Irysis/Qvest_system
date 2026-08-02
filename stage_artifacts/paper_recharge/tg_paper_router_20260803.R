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
  title      = "논문 라우터 v2 — 20260803 배분 결과",
  relaxed    = TRUE,
  force      = TRUE,
  lock_scope = "paper_router_20260803",
  sections   = list(
    list(
      header = "소스 배분 (38편)",
      body   = "alpha:1 / optimizer:1 / risk:3 / regime:2 / skip:31\ncurated 신규:0 (15편 기처리)"
    ),
    list(
      header = "AUTORUN 결과",
      body   = "VoltRank_MC (2607.27461) — Grade C FAIL\nPORT_t -1.88 / OOS 0.435 / MDD -58.4%\n기전: KR 저변동 예측 = 상승기 beta 압축"
    ),
    list(
      header = "testable 팩터후보",
      body   = "VoltRank_MC: vol-rank Markov 전이 → 저변동 예측 long\nDB 신규: D01/R12와 다른 전이 예측 프레임"
    ),
    list(
      header = "optimizer 큐",
      body   = "2607.01705 MACD=Kalman latent drift 추정치\nalpha 고정 A/B 대상 (paper_research_dispatch.R)"
    ),
    list(
      header = "risk 큐 (3편)",
      body   = "CD-DFM(2607.24410) 특성→공분산\nLatent-SV(2607.25459) Transformer 표현\nLong-mem GARCH(2607.25189) 2D Markov"
    ),
    list(
      header = "regime 큐 (2편)",
      body   = "CSAD 군집지표(2607.27063) KR 오버레이 소재\n추세추종 스펙트럼(2607.19497) 저주파 질량"
    ),
    list(
      header = "next_probe",
      body   = "NP1: low-vol + 모멘텀/퀄리티 복합신호\nNP2: vol_bin 전이 엔트로피 → 국면 보조지표"
    )
  )
)

cat("\n[paper_router_20260803] telegram sent OK\n")
