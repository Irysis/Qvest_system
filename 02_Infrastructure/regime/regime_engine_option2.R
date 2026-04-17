# regime_engine_option2.R — Alias for regime_engine_daily.R (v7.1)
# 이 파일은 기존 전략(STR_1039,1044,1047,1048,1051,1055-1058)과
# r4_regime_payoff.R이 참조하는 호환성 alias입니다.
source(file.path(dirname(sys.frame(1)$ofile), "regime_engine_daily.R"))
