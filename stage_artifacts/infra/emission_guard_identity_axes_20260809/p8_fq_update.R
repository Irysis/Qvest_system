## P8 — FQ-214 갱신 (등재 후 확정된 사실 2건 반영)
##   ① 축 D 의 판별력은 빌더 Coverage 계약에서 **빌린 것**인데 그 계약을 고정하는
##      검사가 저장소에 0건이었다 → 축 C 로 고정(정적+행동+E2E). 돌연변이 실증.
##   ② 배선 비용 실측: 증분 월 1회 +4.09s(축 I 격자가 92%), 440개월 전면 재빌드 +30분.
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
source("02_Infrastructure/ops/frontier_queue_io.R")
say <- function(fmt, ...) cat(sprintf(paste0("[p8] ", fmt, "\n"), ...))

TARGET <- readLines("stage_artifacts/infra/emission_guard_identity_axes_20260809/FQ_ID.txt", warn = FALSE)[1]
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
k <- which(ids == TARGET)
if (length(k) != 1L) stop("대상 항목 ", TARGET, " 을 정확히 1건 찾지 못함: ", length(k))
n_before <- length(ids)

Q$entries[[k]]$wall_check <- paste0(Q$entries[[k]]$wall_check, " ",
  "★등재 후 확정(자가 적대검증에서 발견): 축 D 는 sd 를 직접 재지 않고 빌더가 ",
  "`sd(winsorized raw)<1e-12 → Z 전건 NA → Coverage := !is.na(Raw_Value) & !is.na(Z_Score)` 로 ",
  "**이미 번역해 둔 것**을 읽는다 — 즉 판별력이 빌린 것이다. 그런데 그 상류 계약을 고정하는 검사가 ",
  "08_Tests 전체에 **0건**이었다. Coverage 는 2026-06-10 에 `!is.na(Raw_Value)` 단독에서 현 정의로 바뀐 이력이 있고, ",
  "되돌리는 돌연변이를 넣으면 축 D 가 실데이터에서 침묵하는데 **Coverage=FALSE 를 직접 심는 위반 주입은 전부 초록으로 남는다** ",
  "(실측: C1/C2 만 빨개지고 V3b 등 주입 축은 통과) — 검사가 살아 있는 채로 눈이 머는 자리. ",
  "축 C(정적 + .standardize_factors 격리 실행 + end-to-end)로 고정했다. ",
  "비용 실측: 증분 월 빌드 1회 +4.09s(중앙, 3회 반복 · 331팩터×3952종목), 그중 축 I 랭크상관 격자가 92%(3.78s). ",
  "440개월 전면 재빌드면 +30분 — 부담 시 `run_identity=FALSE` 레버가 이미 있다(기본 TRUE, 증분 경로 권장).")

Q$entries[[k]]$source_refs <- paste0(Q$entries[[k]]$source_refs,
  " · 검사 8축 43케이스(P/V/N/G/X/Z/U/C/S/W) · 돌연변이 8종 전부 검출",
  "(kill_D 5 · kill_T 2 · kill_I_rank 2 · kill_I_decl 2 · kill_exempt 1 · kill_unmeasured 1 · kill_liveness 1 · 빌더 Coverage 구정의 2)",
  " · 전체 배터리 1233 pass / 0 fail")
Q$updated <- format(Sys.Date(), "%Y-%m-%d")
write_frontier_queue(Q)

Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], character(1))
if (length(ids2) != n_before) stop("★항목 수 변동: ", n_before, " → ", length(ids2))
hit <- Q2$entries[[which(ids2 == TARGET)]]
say("재읽기 확인 OK — %s · 항목 %d (불변) · wall_check %d자 · 축 C 문구 도달: %s",
    TARGET, length(ids2), nchar(hit$wall_check),
    grepl("빌린 것", hit$wall_check, fixed = TRUE))
say("형식 정본 유지: %s", frontier_queue_format_ok())
