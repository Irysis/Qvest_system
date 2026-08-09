## m5 — ①침묵했던 귀무 창 게이트를 **올바른 필드명**으로 실측
##      ②침묵 기전을 계약으로 못박는다: 길이 0 인자 → sprintf 가 character(0) → cat 이 줄을 삭제
## ★기전: nl$observed 는 존재하지 않는 필드(실제 = stat_window / delta) → NULL
##   NULL - NULL = numeric(0) → sprintf(fmt, numeric(0)) = character(0) → cat() 무출력.
##   **오류 아님·경고 아님·줄 전체 증발**. "측정했는데 산출물엔 없다" 계통의 가장 조용한 판본.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[m5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
inc <- bm_load_incumbent(); inc[, m := mi(date)]
INV <- readRDS(file.path(OUT,"s1_inventory.rds")); RATE <- 0.3562
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
MO <- U[!is.na(.dd)][order(.dd)][, .(rss = last(Regime_Score_smooth)), by=.(m = mi(.dd))]
LB <- data.table(m = MO$m + 1L, on = MO$rss >= quantile(MO$rss, 1-RATE, na.rm=TRUE))[!is.na(on)]

say("=== ① 귀무 창 게이트 실측 (올바른 필드) ===")
say("  %-30s %5s %9s %9s %8s %7s", "strategy","n","stat_win","delta","백분위","inside")
res <- list()
for (nm in c("STR_1698_WT008_M08_Swap", fread(file.path(OUT,"s8_parked.csv"))$id[1:4])) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) next
  X <- merge(inc[, .(m, date, benchmark_ret)], INV$ser[[j]][, .(m, r)], by="m")[order(m)]
  W <- merge(X, LB, by="m")[order(m)]; if (nrow(W) < 60) next
  nl <- subsample_null(x = W$r, y = W$benchmark_ret, subset = W$on,
                       stat = function(a,b) cor(a,b), n_draw = 1000)
  say("  %-30s %5d %+9.4f %+9.4f %7.1f%% %7s", substr(nm,1,30), nl$n,
      nl$stat_window, nl$delta, 100*nl$percentile, nl$inside)
  res[[nm]] <- nl
}
ins <- vapply(res, function(z) isTRUE(z$inside), logical(1))
say("  ⇒ inside %d/%d — %s", sum(ins), length(ins),
    if (all(ins)) "**ON 창이 우연히 특별한 구간이 아님(정상)**" else "★일부 ON 창이 극단 = 구간 의존 의심")

say("=== ② 침묵 기전 재현 + 계약 가드 ===")
demo <- function(x) length(sprintf("[t] v=%.3f", x))
say("  sprintf 길이: 정상값 %d줄 · numeric(0) **%d줄** ← 줄 증발", demo(1.23), demo(numeric(0)))
say("  cat(character(0)) 출력 바이트 = %d (오류·경고 없음)",
    nchar(paste(capture.output(cat(sprintf("[t] %.2f", numeric(0)))), collapse="")))
GUARD <- file.path(ROOT, "02_Infrastructure/contracts/report_guard.R")
writeLines(c(
'## report_guard.R — 보고 줄의 **무음 증발** 차단 (2026-08-09 실사고)',
'## 기전: 존재하지 않는 리스트 필드 → NULL → 산술 결과 numeric(0) →',
'##   sprintf(fmt, numeric(0)) = character(0) → cat() 이 **줄 전체를 출력하지 않는다**.',
'##   오류도 경고도 없다. "쟀는데 산출물엔 없다" 의 가장 조용한 판본.',
'##   실사고: 귀무 창 게이트가 두 스크립트 연속 침묵 — nl$observed 는 없는 필드였다.',
'## ★규약: 측정 스크립트의 보고 함수는 반드시 이 가드를 경유한다.',
'say_guarded <- function(fmt, ..., prefix = "", strict = TRUE) {',
'  a <- list(...)',
'  bad <- which(vapply(a, function(z) length(z) == 0L, logical(1)))',
'  if (length(bad)) {',
'    msg <- sprintf("%s보고 인자 %s 가 길이 0 — 줄이 증발할 뻔했습니다 (fmt: %s)",',
'                   prefix, paste(bad, collapse=","), substr(fmt, 1, 60))',
'    if (isTRUE(strict)) stop(msg) else { warning(msg); return(invisible(FALSE)) }',
'  }',
'  cat(sprintf(paste0(prefix, fmt, "\\n"), ...)); flush.console(); invisible(TRUE)',
'}',
'## 리스트 필드 접근 가드 — 오타/개명된 필드를 NULL 로 흘리지 않는다',
'field <- function(x, nm) {',
'  if (!nm %in% names(x))',
'    stop(sprintf("필드 \'%s\' 부재. 실제 필드: %s", nm, paste(names(x), collapse=",")))',
'  x[[nm]]',
'}',
'message("[report_guard.R] Loaded — say_guarded() / field()")'), GUARD)
say("  계약 작성: %s", sub(paste0(ROOT,"/"), "", GUARD))
say("=== m5 완료 ===")
