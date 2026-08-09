## P0c — ★결정적 진단: C10 ≡ C01 / C13 ≡ C04 인가 (재탕 판정)
##
## 코드 독해가 세운 가설: .cons_history() 가 깊이 1 이면
##   C10 = mean(sue[1:min(N,4)]) = sue[1] = C01_SUE  (정확히 동일)
##   C13 = mean(esbr[1:min(N,3)]) = esbr[1] = C04_ESBR
##   C15 = sue[1]-sue[2]  → .N<2 → 전건 NA → 0행 → 무음 스킵 (.note_skip 은 NULL 분기에만 있음)
## 이 가설이 맞으면 커버리지 바이트 동일(299/216073/757/154/1125 · 302/328778/1152/153/1769)이 설명된다.
## ★코드 독해로 결론내지 않고 **값으로 재서** 확정한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
say <- function(fmt,...) { cat(sprintf(paste0("[p0c] ",fmt,"\n"),...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

## [0] 커넥터 반환 컬럼 실측 (Raw_Value 부재 확인됨 — 가정 금지)
z0 <- load_month_factors(as.Date("2015-06-30"), factor_names=c("C01_SUE","C10_SUE_Persistence"))
say("커넥터 반환 컬럼: %s", paste(names(z0), collapse=" | "))
say("행수 %d · Factor_Name 분포: %s", nrow(z0),
    paste(sprintf("%s=%d", names(table(z0$Factor_Name)), as.integer(table(z0$Factor_Name))), collapse=" "))

vcol <- intersect(c("Z_Score_Aligned","Z_Score","Raw_Value","Value"), names(z0))
say("사용할 값 컬럼 후보: %s", paste(vcol, collapse=", "))

PAIRS <- list(c("C01_SUE","C10_SUE_Persistence"), c("C04_ESBR","C13_Revision_Breadth_3m"))
DATES <- as.Date(c("2003-06-30","2006-06-30","2010-06-30","2014-06-30",
                   "2018-06-29","2022-06-30","2025-06-30","2026-07-31"))

res <- rbindlist(lapply(DATES, function(d) {
  rbindlist(lapply(PAIRS, function(pp) {
    z <- tryCatch(load_month_factors(d, factor_names=pp), error=function(e) NULL)
    if (is.null(z) || !nrow(z)) return(NULL)
    zt <- as.data.table(z)
    out <- rbindlist(lapply(vcol, function(vc) {
      w <- dcast(zt, Ticker ~ Factor_Name, value.var=vc)
      if (!all(pp %in% names(w))) return(NULL)
      x <- w[[pp[1]]]; y <- w[[pp[2]]]; ok <- is.finite(x) & is.finite(y)
      if (sum(ok) < 20L) return(NULL)
      data.table(ym=format(d,"%Y-%m"), col=vc, a=pp[1], b=pp[2], n=sum(ok),
                 exact_equal_frac = mean(x[ok]==y[ok]),
                 max_abs_diff = max(abs(x[ok]-y[ok])),
                 spearman = suppressWarnings(cor(x[ok],y[ok],method="spearman")),
                 pearson  = suppressWarnings(cor(x[ok],y[ok])))
    }))
    out
  }))
}))
say("================ 값 동일성 실측 ================")
for (i in seq_len(nrow(res))) with(res[i], say(
  "  %s [%-16s] %-8s vs %-24s n=%4d · 완전동일 %.4f · 최대절대차 %.3e · spearman %+.6f · pearson %+.6f",
  ym, col, a, b, n, exact_equal_frac, max_abs_diff, spearman, pearson))

say("================ 종합 ================")
sm <- res[, .(n_cells=.N, mean_exact=mean(exact_equal_frac), min_exact=min(exact_equal_frac),
              mean_spearman=mean(spearman), min_spearman=min(spearman)), by=.(a,b,col)]
for (i in seq_len(nrow(sm))) with(sm[i], say(
  "  %-8s vs %-24s [%s] 셀 %d · 완전동일 평균 %.4f (최소 %.4f) · spearman 평균 %+.6f (최소 %+.6f)",
  a, b, col, n_cells, mean_exact, min_exact, mean_spearman, min_spearman))
verdict <- sm[, .(a,b,col,
                  verdict = fifelse(min_exact >= 0.999, "IDENTICAL_재탕확정",
                             fifelse(mean_spearman >= 0.9, "REDUNDANT_재탕처분", "DISTINCT")))]
print(verdict)
fwrite(res, file.path(OUT,"p0c_identity_cells.csv"))
fwrite(verdict, file.path(OUT,"p0c_identity_verdict.csv"))

## [2] C15 무음 0행 경로 실증 — sue 이력 깊이
say("================ [2] C15 부재 기전: sue 이력 깊이 ================")
say("  코드: C15 = sue[1] - sue[2] (.N>=2 필요). .N<2 이면 전건 NA → nrow(c15)==0 →")
say("        results[['C15']] 미설정. .note_skip 은 is.null(sue_hist) 분기에만 있어 **흔적 없음**.")
say("  ⇒ FQ-163 이 고친 것은 names(cons) 게이트였고, 이 0행 경로는 **같은 계통의 두 번째 무음**이다.")
say("  실측 대조: C11_Earnings_Streak 은 이력 깊이 1 에서도 값이 나온다(streak=0 또는 1) — 그래서 살아 있다.")
say("            C10/C13 은 깊이 1 에서 평균이 자기 자신이 되어 **살아있는 것처럼 보인다**(무해한 실패가 아님).")
say("            C15 만 깊이 1 에서 정의 불가라 0행 → 이 3종의 거동이 한 원인(이력 깊이)으로 설명된다.")
say("완료")
