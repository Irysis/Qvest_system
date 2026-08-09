## FQ-138 P0b — ★신호 컬럼 정체 확인 (추측 금지)
## panelx_A 에 수치 컬럼 11개가 있다. 원 측정(WT-D20260803_008, IC +0.1445)이 **어느 것**을 썼나.
## 잘못 고르면 재현 실패이며, 그것을 '신호 소멸' 로 오독하게 된다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p0b] ", fmt, "\n"), ...)); flush.console() }

B <- "04_Research/method_frontier/fq002_contract_magnitude"
PA <- as.data.table(read_parquet(file.path(B, "panelx_A.parquet")))
say("=== 1. panelx_A 구조 실측 ===")
say("  %d행 · 컬럼 %s", nrow(PA), paste(names(PA), collapse=", "))
say("  ym 범위 %s ~ %s · 고유 %d", min(PA$ym), max(PA$ym), uniqueN(PA$ym))
for (k in c("scope","metric_type","window_m")) if (k %in% names(PA)) {
  tb <- table(PA[[k]])
  say("  %-12s 분포: %s", k, paste(sprintf("%s=%d", names(tb), as.integer(tb)), collapse=" · "))
}
say("  월별 종목수 중앙 %.0f", median(PA[, .N, by = ym]$N))

say("=== 2. 수치 컬럼별 분포 (어느 것이 '계약금액/시총' 형태인가) ===")
num <- names(PA)[vapply(PA, is.numeric, logical(1))]
for (k in num) {
  v <- PA[[k]]; v <- v[is.finite(v)]
  if (!length(v)) { say("  %-14s 전건 결측", k); next }
  say("  %-14s n=%5d · 중앙 %10.4f · p95 %10.4f · 최대 %12.2f · 0 비율 %.2f",
      k, length(v), median(v), quantile(v,.95), max(v), mean(v == 0))
}

say("=== 3. ★원 라운드 스크립트에서 신호 컬럼 역추적 ===")
cand_dirs <- c("04_Research/method_frontier/fq002_contract_magnitude",
               "stage_artifacts", "qepm/mailbox/worktask")
hits <- character(0)
for (d in cand_dirs) {
  if (!dir.exists(d)) next
  f <- list.files(d, recursive = TRUE, full.names = TRUE, pattern = "\\.R$|\\.json$")
  f <- f[grepl("fq125|fq138|wt008|WT-D20260803_008|stage1|contract", f, ignore.case = TRUE)]
  hits <- c(hits, f)
}
say("  관련 파일 %d건", length(hits))
for (x in head(hits, 14)) say("    %s", x)

say("=== 4. 그 파일들이 panelx_A 의 어느 컬럼을 참조하나 ===")
cnt <- setNames(integer(length(num)), num)
for (x in hits) {
  tx <- tryCatch(paste(readLines(x, warn = FALSE), collapse = "\n"), error = function(e) "")
  for (k in num) if (grepl(paste0("\\b", k, "\\b"), tx)) cnt[k] <- cnt[k] + 1L
}
o <- order(-cnt)
for (i in o) if (cnt[i] > 0) say("  %-14s 참조 %d개 파일", names(cnt)[i], cnt[i])
say("  ★참조 0인 컬럼: %s", paste(names(cnt)[cnt == 0], collapse=", "))
say("=== 5. 판정 ===")
say("  ★참조가 가장 많은 컬럼이 원 신호일 개연이 높다. 단 **그것만으로 확정하지 말고**")
say("    실제 코드 문맥(score <- ...)을 확인할 것.")
