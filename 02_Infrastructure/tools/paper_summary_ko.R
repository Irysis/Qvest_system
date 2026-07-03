# paper_summary_ko.R — 논문 1편 → 한글 한줄요약 (≤20자)
# 텔레그램 양식 v2 (도훈 mandate 2026-06-13): 영어 제목 표 폐지, 1논문 1한글요약.
# 우선순위: ① 소스 CSV summary_ko (큐레이션) ② 제목 키워드 → 한글 사상 ③ "퀀트 일반 연구"
# 사용처: paper_recharge_daily.R (텔레그램 섹션 빌드). 자기완결 — 외부 의존 없음.

.PAPER_KO_MAP <- list(
  c("idiosyncratic",                                          "고유변동성"),
  c("implied volatility",                                     "내재변동성"),
  c("risk parity",                                            "리스크패리티"),
  c("low[- ]?risk|low[- ]?beta|low[- ]?vol|defensive|betting against", "저위험·방어"),
  c("drawdown",                                               "낙폭관리"),
  c("trend[- ]?following|\\btrend\\b",                        "추세추종"),
  c("momentum",                                               "모멘텀"),
  c("reversal",                                               "반전효과"),
  c("\\bvalue\\b|book[- ]?to[- ]?market",                     "밸류"),
  c("quality|profitab",                                       "퀄리티"),
  c("machine learning|\\bml\\b|boosting|random forest|lasso|ridge", "머신러닝"),
  c("deep learning|neural|autoencoder|transformer",           "딥러닝"),
  c("reinforcement",                                          "강화학습"),
  c("chatgpt|language model|\\bllm\\b|\\bnlp\\b",             "언어모델"),
  c("regime|switching",                                       "국면전환"),
  c("asset pricing|\\bsdf\\b|stochastic discount|risk premi", "자산가격결정"),
  c("cross[- ]?section",                                      "횡단면수익"),
  c("earnings|pead|post[- ]?earnings|announcement",           "실적발표 반응"),
  c("analyst|consensus|belief",                               "애널리스트 전망"),
  c("liquidity",                                              "유동성"),
  c("crowding",                                               "혼잡도"),
  c("\\btail\\b",                                             "꼬리위험"),
  c("uncertainty|interval|conformal",                         "불확실성 정량화"),
  c("allocation",                                             "자산배분"),
  c("portfolio",                                              "포트폴리오 구성"),
  c("factor",                                                 "팩터"),
  c("anomal",                                                 "이상현상"),
  c("volatility",                                             "변동성"),
  c("forecast|predict",                                       "수익률 예측"),
  c("option",                                                 "옵션"),
  c("credit",                                                 "신용위험"),
  c("spillover",                                              "전이효과"),
  c("missing",                                                "결측치 처리"),
  c("quantile",                                               "분위회귀"),
  c("\\bagent",                                               "AI 에이전트"),
  c("\\betf\\b|\\bfund\\b|prospectus",                        "펀드 운용 구조"),
  c("network|graph",                                          "네트워크 분석")
)

paper_summary_ko <- function(title, summary_ko = "") {
  trunc20 <- function(x) {
    x <- gsub("\\s+", " ", trimws(as.character(x)), perl = TRUE)
    if (nchar(x) > 20L) paste0(substr(x, 1L, 19L), "…") else x
  }
  s <- if (is.null(summary_ko) || length(summary_ko) == 0L || is.na(summary_ko)) "" else trimws(as.character(summary_ko))
  if (nzchar(s)) return(trunc20(s))
  t <- tolower(as.character(if (is.null(title) || length(title) == 0L || is.na(title)) "" else title))
  hits <- character(0)
  for (m in .PAPER_KO_MAP) {
    if (length(hits) >= 2L) break
    if (grepl(m[1], t, perl = TRUE)) hits <- c(hits, m[2])
  }
  out <- if (length(hits)) paste(unique(hits), collapse = "·") else "퀀트 일반 연구"
  trunc20(out)
}
