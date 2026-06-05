# dogfood_reclassify.R — 기존 negative 공리 r7/INV-7 재분류 (v8.0 Phase 6 dogfooding)
#
# AX-003/004/005/007은 N=2~3 전략 실패로 "구조적 불가"를 단정한 섣부른 negative 일반화(도훈 지적).
# INV-7: 불변 법칙 아닌 provisional failure-ledger로 강등 + 재도전 트리거 + 소표본 명시.
# AX-003은 statement가 cluster 초안("[초안]...확정 필요") 잔존 → r7 정형으로 정제(INV-6).
# 추측 폐기 아님 — epistemic_status 강등 + 재도전 조건 명시(기존 EXCLUSION = 재도전 트리거).
suppressPackageStartupMessages({ library(jsonlite) })
root <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
ad <- file.path(root, "qepm", "memory", "axioms", "active")

.patch <- function(id, stmt = NULL) {
  p <- file.path(ad, paste0(id, ".json"))
  if (!file.exists(p)) { cat("skip(not found)", id, "\n"); return(invisible()) }
  ax <- fromJSON(p, simplifyVector = FALSE)
  n <- length(ax$supporting_l_codes %||% list())
  ax$epistemic_status <- "provisional"
  ax$retry_trigger <- "새 construction/ML/regime/multi-sleeve 출현 시 kr-inverse-pattern-miner 역가설 재도전"
  ax$evidence_strength_note <- sprintf("N=%d supporting L-code 기반 — 구조적 불가 단정 아닌 잠정 실패기록(INV-7). 기존 EXCLUSION = 재도전 트리거.", n)
  if (!is.null(stmt)) {
    ax$statement <- stmt; ax$canonical_statement <- stmt; ax$text <- stmt
    ax$needs_refinement <- NULL
  }
  write_json(ax, p, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("patched %s (N=%d, provisional)%s\n", id, n, if (!is.null(stmt)) " + statement 정제" else ""))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

ax3 <- paste0("KR value factor(EP/accrual) standalone long-only는 잠정적으로 Grade F — ",
  "최근 10년 value premium 약화 + 단독 구현 시 quality/growth mix 부재. ",
  "단 N=2 전략(STR_1654/1663) 기반 provisional: multi-factor blend·overlay는 scope 밖이며, ",
  "새 construction/regime 출현 시 재도전(역가설) 대상.")

.patch("AX-003", ax3)
.patch("AX-004")
.patch("AX-005")
.patch("AX-007")
cat("[dogfood] 4 negative 공리 → provisional failure-ledger 재분류 완료\n")
