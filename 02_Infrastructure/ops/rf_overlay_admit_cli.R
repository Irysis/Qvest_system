#!/usr/bin/env Rscript
# rf_overlay_admit_cli.R — 등재기 CLI 래퍼 (v10.2 2026-09-03 · v10.4 2026-09-17 source 추가)
# ★왜 파일인가: Rscript -e 에 개행이 들어가면 Windows 에서 rc=139 로 죽는다(실측·기억카드).
#   레인이 여러 줄 -e 를 넘겼다가 정확히 그 자리에서 죽었고, 인프라 오류인데 arm 이 지워졌다.
# 사용: Rscript rf_overlay_admit_cli.R <kind> <action> <state> <model> [n_siblings] [source]
#   source = 방출 출처. 6번째 인자 > 환경변수 QVEST_ARM_SOURCE > 기본 overlay_propose.
#   ★4·5인자 호출은 그대로 돈다(구판 호환). 레인 밖 등재(세션 수동·B5 설계 레인)는 자기 이름을 달아야
#     일간 상한(rf_overlay_propose.sh)이 남의 방출을 레인 몫으로 세지 않는다.
# 종료: 0 등재 · 3 거부(probe/basis) · 그 밖 = 인프라 오류(레인은 arm 을 지우지 않는다)
suppressPackageStartupMessages(library(jsonlite))
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 4L) { cat("usage: <kind> <action> <state> <model> [n_siblings] [source]\n"); quit(status = 2L) }
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_admit.R")))
ns <- if (length(a) >= 5L) suppressWarnings(as.integer(a[5])) else 1L
if (!is.finite(ns) || ns < 1L) ns <- 1L
src <- if (length(a) >= 6L && nzchar(a[6])) a[6] else Sys.getenv("QVEST_ARM_SOURCE", "")
if (!nzchar(src)) src <- "overlay_propose"
r <- rf_overlay_admit(a[1], target = list(action = a[2], state = a[3]),
                      n_siblings = ns, generator_model = a[4], root = ROOT, source = src)
quit(status = if (isTRUE(r$ok)) 0L else 3L)
