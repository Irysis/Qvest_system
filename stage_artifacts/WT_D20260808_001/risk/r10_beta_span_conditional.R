# =============================================================================
# r10_beta_span_conditional.R
#   질문1 결정 시험: D03/Q01 의 '국면-조건부 IC' 가 현행 위험모델의 β 항으로
#   설명되는가(=Σ 에 이미 있음), 아니면 β 통제 후에도 잔존하는가(=결손).
#   방법: 월별 횡단면에서 신호를 X_BETA(및 X_BETA+X_SIZE+X_IVOL)에 직교화한 뒤
#         동일한 연속 조건화 회귀를 반복. 분할 없음.
#   ★alpha 재해석 아님 — 위험모델 완전성(span) 판정용. metric_type = risk_estimate
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt,...) cat(sprintf(paste0("[r10] ",fmt,"\n"),...))

E  <- as.data.table(read_parquet(file.path(OUT,"exposure_panel.parquet"))); E[,Date:=as.Date(Date)]
AS <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_001/alpha_scores.parquet")); AS[,Date:=as.Date(Date)]
R7 <- readRDS(file.path(OUT,"r7_risk.rds")); PB <- as.data.table(R7$PB)
D <- merge(E[, .(Date,Ticker,Ret_1m,X_BETA,X_SIZE,X_IVOL,X_LIQ)],
           AS[, .(Date,Ticker,D03_EWMA,Q01_EB)], by=c("Date","Ticker"))
D <- D[is.finite(Ret_1m)]
say("입력 병합 rows=%d 월 %d (%s~%s) 관측단위 월간 | X_BETA 관측 %.3f",
    nrow(D), uniqueN(D$Date), as.character(min(D$Date)), as.character(max(D$Date)), mean(is.finite(D$X_BETA)))

orth <- function(y, X) {   # 횡단면 잔차화 (결측은 NA 유지)
  ok <- is.finite(y) & Reduce(`&`, lapply(X, is.finite))
  out <- rep(NA_real_, length(y))
  if (sum(ok) < 20) return(out)
  M <- do.call(cbind, lapply(X, function(z) z[ok]))
  f <- stats::lm.fit(cbind(1, M), y[ok])
  out[ok] <- f$residuals; out
}
ic_of <- function(sigcol, ctrl) {
  Z <- copy(D)
  if (length(ctrl)) {
    Z[, sg := orth(get(sigcol), lapply(ctrl, function(c) get(c))), by=Date]
  } else Z[, sg := get(sigcol)]
  Z[is.finite(sg), .(ic = if(.N>=30) cor(sg, Ret_1m, method="spearman", use="complete.obs") else NA_real_,
                     n=.N), by=Date]
}
run <- function(sigcol, ctrl, lab) {
  icm <- merge(ic_of(sigcol, ctrl), PB[, .(Date=date, bm)], by="Date")
  icm <- icm[is.finite(ic)]
  f <- stats::lm(ic ~ bm, data=icm); s <- summary(f)$coefficients
  say("  %-46s n=%3d | IC평균 %+.4f | 절편 %+.4f (t %5.2f) | bm기울기 %+.4f (t %6.2f) | R2 %.3f",
      lab, nrow(icm), mean(icm$ic), s[1,1], s[1,3], s[2,1], s[2,3], summary(f)$r.squared)
  list(n=nrow(icm), ic_mean=mean(icm$ic), slope=s[2,1], slope_t=s[2,3],
       intercept=s[1,1], intercept_t=s[1,3], r2=summary(f)$r.squared)
}
say("[연속 조건화 IC ~ 벤치수익 — 통제 단계별]")
res <- list(
  d03_raw   = run("D03_EWMA", character(0),                       "D03 원신호 (통제 없음)"),
  d03_b     = run("D03_EWMA", c("X_BETA"),                        "D03 ⊥ X_BETA"),
  d03_bsi   = run("D03_EWMA", c("X_BETA","X_SIZE","X_IVOL"),      "D03 ⊥ X_BETA+X_SIZE+X_IVOL"),
  d03_full  = run("D03_EWMA", c("X_BETA","X_SIZE","X_IVOL","X_LIQ"),"D03 ⊥ BETA+SIZE+IVOL+LIQ"),
  q01_raw   = run("Q01_EB",   character(0),                       "Q01 원신호 (통제 없음)"),
  q01_b     = run("Q01_EB",   c("X_BETA"),                        "Q01 ⊥ X_BETA"),
  q01_bsi   = run("Q01_EB",   c("X_BETA","X_SIZE","X_IVOL"),      "Q01 ⊥ X_BETA+X_SIZE+X_IVOL"),
  q01_full  = run("Q01_EB",   c("X_BETA","X_SIZE","X_IVOL","X_LIQ"),"Q01 ⊥ BETA+SIZE+IVOL+LIQ")
)
say("[요약 — 조건부 기울기의 β-통제 후 잔존율]")
say("  D03: 원 %+.4f (t %.2f) → ⊥β %+.4f (t %.2f) 잔존 %.2f → ⊥β,SIZE,IVOL %+.4f (t %.2f) 잔존 %.2f",
    res$d03_raw$slope, res$d03_raw$slope_t, res$d03_b$slope, res$d03_b$slope_t,
    res$d03_b$slope/res$d03_raw$slope, res$d03_bsi$slope, res$d03_bsi$slope_t,
    res$d03_bsi$slope/res$d03_raw$slope)
say("  Q01: 원 %+.4f (t %.2f) → ⊥β %+.4f (t %.2f) 잔존 %.2f → ⊥β,SIZE,IVOL %+.4f (t %.2f) 잔존 %.2f",
    res$q01_raw$slope, res$q01_raw$slope_t, res$q01_b$slope, res$q01_b$slope_t,
    res$q01_b$slope/res$q01_raw$slope, res$q01_bsi$slope, res$q01_bsi$slope_t,
    res$q01_bsi$slope/res$q01_raw$slope)
saveRDS(res, file.path(OUT,"r10_span.rds"))
say("저장 완료")
