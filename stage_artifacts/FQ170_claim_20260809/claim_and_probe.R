#!/usr/bin/env Rscript
# =============================================================================
# claim_and_probe.R — FQ-170 점유 + P0 입력 실측 (착수 전 관문 준비)
# FQ-170: 형태별 소비면 대응 실측 — HUMP 재료(Q01_EB)의 상단절단(D8~D9)이 실제 작동하는가
# 발행자 = WT-D20260809_003. 착수 프로토콜 = owner 를 CLAIMED 로 먼저 갱신.
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
OUT <- file.path(PROJ, "stage_artifacts/FQ170_claim_20260809")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
sink(file.path(OUT, "p0_claim.log"), split = TRUE)

## ── 1. CLAIM (정본 writer 경유) ───────────────────────────────────────
source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-170"); stopifnot(length(i) == 1)
own <- Q$entries[[i]]$owner
if (grepl("^CLAIMED", as.character(own)[1] %||% "")) {
  cat("[claim] 이미 점유됨:", as.character(own)[1], "— 중복 착수 중단\n"); sink(); quit(save="no")
}
`%||%` <- function(a,b) if (is.null(a)) b else a
Q$entries[[i]]$owner <- sprintf("CLAIMED Q-Lead session ba4a1c30 %s (폐지줍기 아크 수렴 후 자율 배분 — 도훈 '자가발전형 진행' 지시)",
                                format(Sys.time(), "%Y-%m-%d %H:%M"))
res <- write_frontier_queue(Q)
cat("[claim] FQ-170 점유 완료. n=", res$n, "\n", sep="")

## ── 2. 입력 실측 (가정 금지 — merged_panel.rds 스키마) ────────────────
p <- file.path(PROJ, "stage_artifacts/WT_D20260809_003/merged_panel.rds")
stopifnot(file.exists(p))
MP <- readRDS(p)
cat("\n[입력] class:", paste(class(MP), collapse=","), "\n")
if (is.data.frame(MP)) {
  MP <- as.data.table(MP)
  cat("  dim:", nrow(MP), "x", ncol(MP), "\n  cols:", paste(names(MP), collapse=", "), "\n")
  dcol <- intersect(c("ym","Date","date"), names(MP))[1]
  cat("  date col:", dcol, " range:", as.character(range(MP[[dcol]])), "\n")
  # 재료 식별 컬럼
  for (cn in intersect(c("material","signal","factor","name"), names(MP)))
    cat("  ", cn, ":", paste(head(unique(MP[[cn]]), 8), collapse=", "), "\n")
  cat("  head:\n"); print(head(MP, 3))
} else if (is.list(MP)) {
  cat("  names:", paste(names(MP), collapse=", "), "\n")
  for (nm in head(names(MP), 6)) {
    x <- MP[[nm]]
    cat(sprintf("   $%s: %s %s\n", nm, paste(class(x), collapse=","),
                if (is.data.frame(x)) paste(dim(x), collapse="x") else if (is.atomic(x)) length(x) else ""))
    if (is.data.frame(x)) cat("     cols:", paste(head(names(x), 15), collapse=", "), "\n")
  }
}

## 부속 산출물 (형태 라운드가 남긴 판정)
av <- file.path(PROJ, "stage_artifacts/WT_D20260809_003/alpha_validation.json")
if (file.exists(av)) {
  cat("\n[alpha_validation.json 요지]\n")
  cat(substr(paste(readLines(av, warn=FALSE), collapse=" "), 1, 1200), "\n")
}
sink()
