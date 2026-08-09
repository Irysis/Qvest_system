## r4 — 40계열의 **계약 준수 census**: 어느 전략이 하네스를 거쳤는가
## r3 확정: STR_1675 계열은 C15 우회 + 10-component 부재 → AX-002 로 자본 승격 불가.
## ⇒ 나머지 중 **계약 경로를 거친 계열**이 있으면 그것이 진짜 후보다.
## 판정 기준(선언적):
##   A. `04_backtest_results/` 아래 10-component 존재 (00_manifest ~ 10_audit)
##   B. audit 산출물의 status
##   C. load_month_factors 사용 여부 (C15) — run_all.R 이 있으면
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[r4] ", fmt, "\n"), ...)); flush.console() }
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
IDX <- INV$idx
C7  <- fread(file.path(OUT,"s7_census.csv"))

TEN <- c("00_manifest","01_strategy_spec","02_nav","03_period_returns","04_holdings",
         "05_benchmark_returns","06_metrics","07_benchmark_compare","08_rolling_metrics",
         "09_drawdowns","10_audit")
rows <- list()
for (j in INV$keep) {
  nm <- INV$names[j]; f <- gsub("\\\\","/", IDX$file[j])
  d  <- dirname(f)                      # 산출 디렉토리
  base <- dirname(d)                    # 전략 루트 추정
  ## 10-component 탐색 (파일이 있는 디렉토리 + 형제 04_backtest_results)
  cands <- unique(c(d, file.path(base, "04_backtest_results"),
                    list.files(base, pattern="backtest_result", full.names=TRUE, include.dirs=TRUE)))
  cands <- cands[dir.exists(cands)]
  hit <- 0L; where <- NA_character_; audit <- NA_character_
  for (cd in cands) {
    ff <- list.files(cd)
    h <- sum(vapply(TEN, function(t) any(grepl(paste0("^", t), ff)), TRUE))
    if (h > hit) { hit <- h; where <- cd }
  }
  if (is.finite(hit) && hit >= 8 && !is.na(where)) {
    af <- list.files(where, pattern="^10_audit", full.names=TRUE)[1]
    if (!is.na(af)) {
      A <- tryCatch(fread(af), error=function(e) NULL)
      if (!is.null(A) && nrow(A)) {
        sc <- names(A)[grepl("status|result|pass", names(A), ignore.case=TRUE)][1]
        audit <- if (!is.na(sc)) paste(names(sort(table(A[[sc]]), decreasing=TRUE))[1],
                                       sprintf("(%d행)", nrow(A))) else sprintf("%d행", nrow(A))
      }
    }
  }
  ## C15 확인
  ra <- list.files(base, pattern="^run_all\\.R$", recursive=TRUE, full.names=TRUE)[1]
  c15 <- NA_character_
  if (!is.na(ra)) {
    L <- tryCatch(readLines(ra, warn=FALSE), error=function(e) character(0))
    has_lmf <- any(grepl("load_month_factors", L))
    has_od  <- any(grepl("open_dataset\\(", L)) && any(grepl("factor_db|factor_db_daily", L))
    c15 <- if (has_lmf && !has_od) "경유" else if (has_od && !has_lmf) "★직접" else
           if (has_lmf && has_od) "혼재" else "미상"
  }
  rows[[length(rows)+1L]] <- data.table(id=nm, ten=hit, audit=audit, c15=c15,
                                        has_runall = !is.na(ra))
}
R <- rbindlist(rows, fill=TRUE)
R <- merge(R, C7[, .(id, rho, ir, short, park_ok, lineage)], by="id", all.x=TRUE)
setorder(R, -ten, short)
say("=== ★계약 준수 census (%d계열) ===", nrow(R))
say("  %-32s %5s %-14s %-8s %8s %8s %8s", "strategy","10-c","audit","C15","rho","IR","부족")
for (i in seq_len(min(20, nrow(R))))
  say("  %-32s %5d %-14s %-8s %+8.3f %+8.3f %+8.3f", substr(R$id[i],1,32), R$ten[i],
      substr(R$audit[i] %||% "없음",1,14), R$c15[i] %||% "미상",
      R$rho[i], R$ir[i], R$short[i])
`%||%` <- function(a,b) if (is.null(a)||is.na(a)) b else a
say("=== ★분해 ===")
say("  10-component >= 8 인 계열: **%d / %d**", sum(R$ten >= 8), nrow(R))
say("  audit 산출물 보유       : **%d**", sum(!is.na(R$audit)))
say("  C15 경유(load_month_factors): **%d** · ★직접: %d · 혼재 %d · 미상 %d",
    sum(R$c15 == "경유", na.rm=TRUE), sum(R$c15 == "★직접", na.rm=TRUE),
    sum(R$c15 == "혼재", na.rm=TRUE), sum(is.na(R$c15) | R$c15 == "미상"))
V <- R[ten >= 8 & lineage == FALSE]
say("=== ★계약 준수 ∧ 비계보 계열 = **%d건** ===", nrow(V))
if (nrow(V)) {
  setorder(V, short)
  for (i in seq_len(nrow(V)))
    say("  %-32s 10-c %d · C15 %-6s · rho %+.3f · IR %+.3f · 부족 %+.3f · 파킹가능 %s",
        substr(V$id[i],1,32), V$ten[i], V$c15[i] %||% "미상", V$rho[i], V$ir[i], V$short[i], V$park_ok[i])
  say("  ★이 중 파킹 적용 가능하고 C15 우회가 아닌 계열이 **진짜 후보**다.")
} else say("  ★★계약 준수 ∧ 비계보 계열 **0건** — 전략 풀 전체가 하네스 밖이다")
fwrite(R, file.path(OUT,"r4_contract_census.csv"))
say("=== r4 완료 ===")
