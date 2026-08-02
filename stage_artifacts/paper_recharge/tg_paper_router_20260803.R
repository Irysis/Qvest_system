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
      body   = "VoltRank_MC: vol-rank Markov 전이 -> 저변동 예측 long\nDB 신규: D01/R12와 다른 전이 예측 프레임"
    ),
    list(
      header = "optimizer 큐",
      body   = "2607.01705 MACD=Kalman latent drift 추정치\nalpha 고정 A/B 대상 (paper_research_dispatch.R)"
    ),
    list(
      header = "risk 큐 (3편)",
      body   = "CD-DFM(2607.24410) 특성->공분산\nLatent-SV(2607.25459) Transformer 표현\nLong-mem GARCH(2607.25189) 2D Markov"
    ),
    list(
      header = "regime 큐 (2편)",
      body   = "CSAD 군집지표(2607.27063) KR 오버레이 소재\n추세추종 스펙트럼(2607.19497) 저주파 질량"
    ),
    list(
      header = "next_probe",
      body   = "NP1: low-vol + 모멘텀/퀄리티 복합신호\nNP2: vol_bin 전이 엔트로피 -> 국면 보조지표"
    )
  )
)

cat("\n[paper_router_20260803] telegram sent OK\n")

# =============================================================
# tier-2 팩터 심층 재검 결과 브리핑 (20260803)
# =============================================================
tg_agent_brief(
  agent      = "AlphaSearch",
  title      = "팩터 심층 재검 (tier-2) — 20260803",
  relaxed    = TRUE,
  force      = TRUE,
  lock_scope = "factor_recheck_tier2_20260803",
  glossary   = TRUE,
  sections   = list(

    list(type = "summary",
         body = paste0(
           "추세추종·MACD 논문 2편 전문 정독(총 175k자). ",
           "승격 0건 — 종목 랭킹 신호 부재 또는 중복. 다음 가설 3건 발굴."
         )),

    list(type    = "bullet",
         emoji   = "\U0001f4d6",
         heading = "쉬운 설명",
         items   = c(
           "시도: tier-1이 판단보류(uncertain)로 남긴 논문 2편을 전문 정독해 종목별 투자 신호 유무 확인",
           "방법: 단일자산 이론인지 vs 종목 횡단면 랭킹 신호인지, 정보계수/다중검정 t값 실증 여부 검사",
           "결과: 1편=단일 선물자산 추세 이론, 1편=순수 수학 이론(실증 0건) & 레지스트리 중복",
           "의미: 실제 자본 배정 불가. 단 이론에서 장기기억 팩터 가설 3건 도출해 큐 등재 예정"
         )),

    list(type    = "kv",
         emoji   = "\U0001f4ca",
         heading = "판정 결과",
         kv      = list(
           "입력" = "2건",
           "승격" = "0건",
           "기각(infeasible)" = "1건",
           "중복(redundant)"  = "1건"
         )),

    list(type    = "bullet",
         emoji   = "\U0001f4cb",
         heading = "논문별 판정",
         items   = c(
           "[기각] 2607.19497 ARFIMA_TrendPersist: 단일 선물자산 CTA 이론. ARFIMA=샤프지수 공식 이론 예시. 종목별 정보계수 전무",
           "[중복] 2607.01705 MACD_CS: Kalman 필터->MACD-type 신호 수학 도출(실증 0건). M19_MACD 기등재 — 동일 계열"
         )),

    list(type    = "bullet",
         emoji   = "\U0001f52e",
         heading = "발굴 가설 (FQ 후보)",
         items   = c(
           "FQ-①: ARFIMA d 횡단면 — 종목별 분수적분 계수 d 추정, 장기 추세지속성 랭킹. Lo(1991) 기반",
           "FQ-②: Hurst 지수(H) 횡단면 — H>0.5=추세지속, OHLCV만으로 R/S 분석 가능. 미등재 신호",
           "FQ-③: MACD 최적 스팬 — 종목별 Kalman kappa 추정 후 스팬 최적화, M19_MACD 고정값 대비 차별화"
         ))
  )
)

cat("\n[factor_recheck_tier2_20260803] telegram sent OK\n")
