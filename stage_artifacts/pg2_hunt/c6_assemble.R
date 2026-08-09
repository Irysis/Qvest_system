## c6 — journal 의 샤드별 results_csv 를 하나의 전수표로 조립
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[c6] ", fmt, "\n"), ...)); flush.console() }
`%||%` <- function(a,b) if (is.null(a)) b else a

p <- file.path("C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot",
               "832fa2fc-c147-4788-b363-4b17e97ed23e/subagents/workflows/wf_8c401997-47a/journal.jsonl")
L <- readLines(p, warn = FALSE)
say("journal %d줄", length(L))
acc <- list(); nsh <- 0L
for (l in L) {
  j <- tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j) || is.null(j$result)) next
  r <- j$result
  csv <- as.character(r$results_csv %||% "")[1]
  if (!nzchar(csv)) next
  nsh <- nsh + 1L
  d <- tryCatch(fread(text = csv), error = function(e) NULL)
  if (is.null(d) || !nrow(d)) { say("  샤드 %d: CSV 파싱 실패 (길이 %d)", nsh, nchar(csv)); next }
  say("  샤드 %d: %d행 · 컬럼 %s", nsh, nrow(d), paste(names(d), collapse=","))
  acc[[length(acc)+1L]] <- d
}
if (!length(acc)) { say("★조립 가능한 CSV 0건 — 종합 대기"); quit(status=0) }

## 컬럼명이 샤드마다 다를 수 있으므로 표준화
norm <- function(d) {
  n <- tolower(names(d))
  pick <- function(cands) { i <- which(n %in% cands)[1]; if (is.na(i)) NA_character_ else names(d)[i] }
  data.table(
    factor    = as.character(d[[pick(c("factor","factor_name","name"))]] %||% NA),
    cor_un    = suppressWarnings(as.numeric(d[[pick(c("cor_uncond","cor_un","cor_uncond_"))]] %||% NA)),
    ir_un     = suppressWarnings(as.numeric(d[[pick(c("ir_uncond","sleeve_ir_uncond"))]] %||% NA)),
    d_un      = suppressWarnings(as.numeric(d[[pick(c("dir_uncond","d_uncond","dir_un"))]] %||% NA)),
    cor_pk    = suppressWarnings(as.numeric(d[[pick(c("cor_park","cor_parked"))]] %||% NA)),
    ir_pk     = suppressWarnings(as.numeric(d[[pick(c("ir_park","ir_parked","sleeve_ir_park"))]] %||% NA)),
    d_pk      = suppressWarnings(as.numeric(d[[pick(c("dir_park","d_park","dir_parked"))]] %||% NA)),
    best_d    = suppressWarnings(as.numeric(d[[pick(c("best_dir","best_delta_ir","best_d"))]] %||% NA)),
    best_arm  = as.character(d[[pick(c("best_arm","arm"))]] %||% NA))
}
A <- rbindlist(lapply(acc, norm), fill = TRUE)
A <- A[!is.na(factor) & nzchar(factor)]
say("=== 조립 %d행 (샤드 %d개) ===", nrow(A), nsh)

## 요구조건 지도로 부족분 재계산 (에이전트 값을 신뢰하지 않고 메인에서 재산출)
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
inc <- bm_load_incumbent(); m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w = 0.20) {
  f <- function(x) {
    mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i)
    v  <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
    mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho)) return(NA_real_)
  if (f(15) < 0) NA_real_ else tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_)
}
A[, need_un := vapply(cor_un, need_ir, numeric(1))]
A[, need_pk := vapply(cor_pk, need_ir, numeric(1))]
A[, short_un := need_un - ir_un]
A[, short_pk := need_pk - ir_pk]
A[, short_best := pmin(short_un, short_pk, na.rm = TRUE)]

say("=== ★전수 분포 ===")
for (nm in c("cor_un","ir_un","d_un","cor_pk","ir_pk","d_pk")) {
  v <- A[[nm]]; v <- v[is.finite(v)]
  if (!length(v)) next
  say("  %-8s n=%3d · 중앙 %+8.4f · [%+.4f, %+.4f] · 양수 %.1f%%",
      nm, length(v), median(v), min(v), max(v), 100*mean(v>0))
}
say("  ★ΔIR>=0.05 통과: 무조건부 %d · 파킹 %d (전체 %d팩터)",
    sum(A$d_un >= 0.05, na.rm=TRUE), sum(A$d_pk >= 0.05, na.rm=TRUE), nrow(A))
say("  ★부족분(재산출) 중앙 %.4f · 최소 %.4f", median(A$short_best, na.rm=TRUE), min(A$short_best, na.rm=TRUE))

say("=== ★근접 12건 (부족분 오름차순) ===")
T <- A[is.finite(short_best)][order(short_best)][1:min(12,.N)]
say("  %-32s %8s %8s %8s %9s", "factor", "상관", "IR", "필요IR", "부족분")
for (i in seq_len(nrow(T))) {
  pk <- is.finite(T$short_pk[i]) && (!is.finite(T$short_un[i]) || T$short_pk[i] <= T$short_un[i])
  say("  %-32s %+8.3f %+8.3f %8.3f %+9.3f%s", substr(T$factor[i],1,32),
      if (pk) T$cor_pk[i] else T$cor_un[i], if (pk) T$ir_pk[i] else T$ir_un[i],
      if (pk) T$need_pk[i] else T$need_un[i], T$short_best[i], if (pk) " [parked]" else " [uncond]")
}
fwrite(A, file.path(OUT, "c6_full_table.csv"))
say("=== c6 완료 → c6_full_table.csv (%d팩터) ===", nrow(A))
