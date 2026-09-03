#!/usr/bin/env Rscript
# rf_overlay_admit_cli.R — 등재기 CLI 래퍼 (v10.2 2026-09-03)
# ★왜 파일인가: Rscript -e 에 개행이 들어가면 Windows 에서 rc=139 로 죽는다(실측·기억카드).
#   레인이 여러 줄 -e 를 넘겼다가 정확히 그 자리에서 죽었고, 인프라 오류인데 arm 이 지워졌다.
# 사용: Rscript rf_overlay_admit_cli.R <kind> <action> <state> <model> [n_siblings]
# 종료: 0 등재 · 3 거부(probe/basis) · 그 밖 = 인프라 오류(레인은 arm 을 지우지 않는다)
suppressPackageStartupMessages(library(jsonlite))
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 4L) { cat("usage: <kind> <action> <state> <model> [n_siblings]\n"); quit(status = 2L) }
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_admit.R")))
ns <- if (length(a) >= 5L) suppressWarnings(as.integer(a[5])) else 1L
if (!is.finite(ns) || ns < 1L) ns <- 1L
r <- rf_overlay_admit(a[1], target = list(action = a[2], state = a[3]),
                      n_siblings = ns, generator_model = a[4], root = ROOT)
quit(status = if (isTRUE(r$ok)) 0L else 3L)
