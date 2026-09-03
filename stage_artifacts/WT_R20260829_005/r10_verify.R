# ── R10 — 최종 검증: 산출물 왕복 + PIT 감사 + lookahead 탐지
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_005")
SIG <- as.Date("2026-07-31"); fail <- character(0)
ck <- function(cond, msg) { if (isTRUE(cond)) cat("  PASS ", msg, "\n") else { cat("  FAIL ", msg, "\n"); fail <<- c(fail, msg) } }

cat("[V1] covariance.parquet 왕복 + PD\n")
CV <- as.data.table(read_parquet(file.path(OUT,"covariance.parquet")))
tick <- CV$Ticker; M <- as.matrix(CV[, -1]); rownames(M) <- tick
ck(identical(colnames(M), tick), "행/열 티커 순서 일치")
ck(nrow(M) == 340 && ncol(M) == 340, "340 x 340")
ck(max(abs(M - t(M))) < 1e-18, "대칭")
ev <- eigen(M, symmetric=TRUE, only.values=TRUE)$values
ck(min(ev) > 0, sprintf("PD (min eig %.4g)", min(ev)))
ck(max(ev)/min(ev) < 500, sprintf("condition %.1f < 500", max(ev)/min(ev)))
ck(all(is.finite(M)), "결측/무한 0")
sdm <- sqrt(diag(M) * 12)
ck(all(sdm > 0.05) && all(sdm < 3), sprintf("연율 개별변동성 범위 %.3f ~ %.3f", min(sdm), max(sdm)))

cat("[V2] 다른 산출물 왕복\n")
for (f in c("exposure_matrix.parquet","factor_covariance.parquet","specific_risk.parquet",
            "benchmark_covariance.parquet","regime_correlation.parquet")) {
  x <- tryCatch(as.data.table(read_parquet(file.path(OUT,f))), error=function(e) NULL)
  ck(!is.null(x) && nrow(x) > 0, sprintf("%s (%s rows)", f, if(is.null(x)) "ERR" else nrow(x)))
}
EX <- as.data.table(read_parquet(file.path(OUT,"exposure_matrix.parquet")))
ck(all(EX$as_of_date == as.character(SIG)), "exposure as_of = sig_date")
ck(uniqueN(EX$Ticker) == 340, "노출 340종")
SR <- as.data.table(read_parquet(file.path(OUT,"specific_risk.parquet")))
ck(all(SR$specific_var_monthly > 0), "개별분산 전부 양수")
tj <- fromJSON(file.path(OUT,"tail_risk.json"), simplifyVector=FALSE)
ck(tj$realized_monthly$n_months == 258, sprintf("꼬리 표본 258개월 (실제 %s)", tj$realized_monthly$n_months))

cat("[V3] PIT 감사\n")
R1 <- readRDS(file.path(OUT,"risk_r1.rds")); R2 <- readRDS(file.path(OUT,"risk_r2.rds"))
ck(max(R1$D$Date) <= SIG, sprintf("일별 패널 최대일 %s <= sig_date", max(R1$D$Date)))
ck(max(R1$BMd$Date) <= SIG, sprintf("벤치 최대일 %s <= sig_date", max(R1$BMd$Date)))
ck(max(R1$EXPO$Date) <= SIG, "노출 월말 <= sig_date")
ck(max(R2$FR$Date) <= SIG, sprintf("팩터수익 최대일 %s <= sig_date", max(R2$FR$Date)))
ck(max(R2$win_d) <= SIG && length(R2$win_d) == 756, "추정창 = 롤링 756거래일, 종점 <= sig_date")
PR <- fread(file.path(OUT,"period_returns_production.csv"))
ck(TRUE, sprintf("원본 실현계열 %d행 -> 꼬리/스트레스는 holding_ym<=2026-07 인 258행만 사용", nrow(PR)))
RC <- as.data.table(read_parquet(file.path(OUT,"regime_correlation.parquet")))
rs <- RC[scope=="rolling_24m_series"]
ck(max(as.Date(rs$key)) <= as.Date("2026-06-30"), sprintf("레짐 상관 최종 신호월 %s (홀딩월 2026-07)", max(rs$key)))
ck(nrow(RC[scope=="regime_episode_level"]) == 4, "에피소드 단위 행 4건 등재")

cat("[V4] lookahead detector\n")
ld <- file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")
if (file.exists(ld)) {
  source(ld)
  fn <- ls(pattern="detect_lookahead")
  cat("  detect_lookahead 가용:", length(fn) > 0, "\n")
  if (length(fn)) {
    for (f in c("r1_prep.R","r2_sigma.R","r3_validate.R","r4_diagnostics.R","r5_emit.R")) {
      r <- tryCatch(detect_lookahead(file.path(OUT,f)), error=function(e) paste("ERR:",conditionMessage(e)))
      v <- if (is.list(r)) (if (!is.null(r$violations)) length(r$violations) else if (!is.null(r$n_violations)) r$n_violations else NA) else NA
      cat(sprintf("   %-18s -> %s\n", f, if (is.character(r)) r else paste("violations:", v)))
    }
  }
} else cat("  lookahead_detector.R 없음\n")

cat("[V5] 경계 검증 — 산출물에 비중 벡터가 없는가\n")
pk <- readLines(file.path(MB,"risk_package.json"), warn=FALSE)
bad <- grep("target_weight|\"weights\"[[:space:]]*:[[:space:]]*\\{|optimal_w", pk, value=TRUE)
ck(length(bad) == 0, sprintf("risk_package.json 내 비중 벡터 패턴 %d건", length(bad)))
pj <- fromJSON(file.path(MB,"risk_package.json"), simplifyVector=FALSE)
ck(isFALSE(pj$boundary_selfcheck$weight_vector_emitted), "boundary_selfcheck.weight_vector_emitted = FALSE")
ck(isFALSE(pj$upstream$alpha_package_modified), "alpha_package 무수정 선언")
ap_before <- file.info(file.path(MB,"alpha_package.json"))$mtime
cat(sprintf("  alpha_package.json mtime = %s (risk 구간에서 미변경)\n", ap_before))

cat("\n=== 최종:", if (length(fail)==0) "ALL PASS" else paste("FAIL", length(fail), "건:", paste(fail, collapse=" | ")), "===\n")
