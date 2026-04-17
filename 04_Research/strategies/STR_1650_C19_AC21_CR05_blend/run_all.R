cat("=== STR_1650: C19+AC21+CR05 Score Blending (Consensus+Accrual+Crowding) ===\n")
## 핵심아이디어: 3-factor composite — earnings consensus + accrual quality + crowding reversal
## 근거: Sloan(1996) accrual anomaly, Lou&Polk(2022) crowding, 상관분석 rho≈0 확인
## S1 순수 팩터 신호 (overlay 없음), Z_Score_Aligned 사용 (C13), load_month_factors() 경유 (C15)

t0 <- Sys.time()

# strategy 디렉토리 기준으로 factor_engine.R 소싱
.strat_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
source(file.path(.strat_dir, "factor_engine.R"))

elapsed <- difftime(Sys.time(), t0, units = "secs")
cat(sprintf("\n[run_all] STR_1650 total elapsed: %.1f seconds.\n", elapsed))
cat("=== END STR_1650 ===\n")
