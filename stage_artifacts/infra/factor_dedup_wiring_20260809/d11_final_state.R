#==============================================================================
# d11_final_state.R — 최종 상태를 **디스크에서** 확인 (선언에서 파생 금지)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
P <- c(file.path(ROOT, "02_Infrastructure/factor_db/factor_registry.json"),
       file.path(ROOT, ".cache/factor_db/factor_registry.json"))
h <- vapply(P, function(p) unname(tools::md5sum(p)), character(1))
cat(sprintf("[d11] 2벌 md5: %s / %s → %s\n", substr(h[1],1,12), substr(h[2],1,12),
            if (h[1] == h[2]) "정합" else "★불일치"))

reg <- fromJSON(P[1], simplifyVector = FALSE)
roles <- vapply(reg, function(e) {
  r <- e$dedup$role; if (is.null(r)) NA_character_ else as.character(r)[1] }, character(1))
cat(sprintf("[d11] registry %d종 | dedup %d | canonical %d / alias %d / redundant %d\n",
            length(reg), sum(!is.na(roles)), sum(roles %in% "canonical"),
            sum(roles %in% "alias"), sum(roles %in% "redundant")))

cat("\n[d11] 이번 라운드 7종 최종 상태:\n")
for (f in c("C01_SUE","C09_Earnings_Surprise_Sq","C10_SUE_Persistence",
            "C04_ESBR","C13_Revision_Breadth_3m",
            "C11_Earnings_Streak","M25_Earnings_Mom_Streak")) {
  d <- reg[[f]]$dedup
  cat(sprintf("  %-26s role=%-9s cluster=%-9s %s%s\n", f, d$role, d$cluster,
              if (!is.null(d$canonical)) paste0("-> ", d$canonical) else "",
              if (!is.null(d$defect)) "  [defect: inert_window 기록됨]" else ""))
}

# alias 전건 무결성 재확인 (양방향 + 체인 없음)
al <- names(roles)[roles %in% "alias"]
bads <- character(0)
for (a in al) {
  cn <- reg[[a]]$dedup$canonical
  if (is.null(cn) || is.null(reg[[cn]])) { bads <- c(bads, paste0(a, ": canonical 부재")); next }
  if (identical(reg[[cn]]$dedup$role, "alias")) bads <- c(bads, paste0(a, ": 체인"))
  if (!(a %in% unlist(reg[[cn]]$dedup$aliases))) bads <- c(bads, paste0(a, ": 역참조 없음"))
}
cat(sprintf("\n[d11] alias %d종 무결성: %s\n", length(al),
            if (!length(bads)) "전건 OK (canonical 실재·체인 없음·양방향 일치)"
            else paste(bads, collapse = " | ")))

# 큐 확인
source(file.path(ROOT, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
cat(sprintf("[d11] 큐 항목 %d | FQ-218 %s | FQ-219 %s\n", length(ids),
            "FQ-218" %in% ids, "FQ-219" %in% ids))
