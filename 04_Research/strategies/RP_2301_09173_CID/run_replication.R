# run_replication.R — 1계층 충실구현 드라이버 (RP_2301_09173_CID · 2026-09-02)
#   실행: cd 04_Research/strategies/RP_2301_09173_CID && Rscript -e 'source("run_replication.R")'
#   논문: Pinchuk (2023) arXiv:2301.09173 — CID(cross-industry dispersion) beta, 5분위 VW 롱숏
suppressWarnings(suppressMessages(library(data.table)))
ROOT <- Sys.getenv("QM_ROOT", "")
if (!nzchar(ROOT)) ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
if (!nzchar(ROOT)) ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"   # CLAUDE.md Key Paths 정본
source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))

res <- run_paper_replication(
  strategy_name = "CID_beta_LS_Pinchuk2023",
  strategy_idea = paste0(
    "산업간 수익률 분산(CID, 48산업 VW 월간 |R_ind-R_mkt| 평균)의 AR 잔차 충격에 대한 ",
    "종목 24개월 베타로 5분위 정렬 — 저베타(Q1) 매수·고베타(Q5) 매도, 전월말 시총가중, 월간 리밸. ",
    "논문(US 1963-2018): Q1-Q5 월 49bps(t=3.19), CAPM 알파 52bps. 유일한 변경 = 유니버스 K200∪KQ150."),
  factor_engine_path = file.path(ROOT, "04_Research/strategies/RP_2301_09173_CID/engine.R"),
  # ★논문 명시값 그대로: 5분위(long_frac=short_frac=0.20) · 시총가중(전월말) · 월간.
  #   n_max = 1000 — 충실구현 단계는 종목수 상한 없음(lean-loop 축 2층 · alpha-search SKILL 제1원칙).
  #   러너 기본 25 는 실투형 축(강화부터)이라 여기서 해제한다. 실현 n_max 는 산출물에 남는다.
  portfolio_spec = list(construction = "quantile_long_short", weighting = "vw",
                        long_frac = 0.20, short_frac = 0.20, rebalance = "monthly",
                        n_max = 1000L),
  source_paper = list(url = "https://arxiv.org/abs/2301.09173", paper_key = "2301.09173",
                      paper_id = "2301.09173",
                      title = "Pinchuk (2023) Labor Income Risk and the Cross-Section of Expected Returns"),
  commission_paper = NULL)   # 논문 비용 무명시 → gross 병기, 등급은 15bps 판

saveRDS(res, "last_result.rds")
cat("\n[driver] DONE — grade:", res$grade, " out_dir:", res$out_dir, "\n")
