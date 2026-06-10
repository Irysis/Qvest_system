# _run_batch_fresh.R — 신선 알파 배치 검증 러너 (순차). 향후 spec 추가만 하면 됨.
source("G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/run_alpha_search.R")
FE <- "G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search"

specs <- list(
  list(name = "VolPremium_GKM2001",
       idea = "고거래량 프리미엄(Gervais-Kaniel-Mingelgrin 2001): 비정상 거래량(Vol/MA20, t-1) 상위 decile long-only EW. 거래량 정량, visibility shock. NLP·대체데이터 무사용.",
       fe   = "fe_volpremium.R"),
  list(name = "RealizedSkew_low",
       idea = "실현 왜도(skewness preference): raw 일수익 252d 왜도 하위(negative skew) decile long-only EW. 가격 only, lottery 회피축. L-313 IdioSkew(잔차)와 구분(raw). NLP·대체데이터 무사용.",
       fe   = "fe_rskew.R")
)

for (s in specs) {
  cat("\n>>>>> ", s$name, " <<<<<\n")
  res <- tryCatch(
    run_alpha_search(
      strategy_name      = s$name,
      strategy_idea      = s$idea,
      factor_engine_path = file.path(FE, s$fe),
      weight_method      = "equal",
      start_date         = "2005-01-01",
      universe           = "K200_KQ150",
      factor_analysis    = TRUE
    ),
    error = function(e) { cat("[FAIL]", s$name, "::", conditionMessage(e), "\n"); NULL })
  if (!is.null(res))
    cat(sprintf("[batch] %s grade=%s score=%s excess=%s\n",
                s$name, res$grade, res$score, res$excess_cagr))
}
cat("\n[batch_fresh] done.\n")
