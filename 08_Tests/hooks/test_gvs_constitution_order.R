#!/usr/bin/env Rscript
#==============================================================================
# test_gvs_constitution_order.R — Step 0 조준기 우선순위의 CLAUDE.md 정본 파생 검증
#
# 배경 (2026-08-17 폐쇄루프 감사):
#   gap_vector_steering.R::GV_STEERING_DIRECTIONS 의 priority 가 하드코딩이라
#   v8.4 재편(2026-08-13, 비-return 주력 해제)을 38일간 못 받았다. 그 결과
#   steer_gap_vector() → .cache/portfolio_gap_vector.json::sleeve_needs → Gap-Directed
#   Step 0 가 **도훈이 08-09 에 닫은 lane 을 1순위로 겨눴다**.
#   같은 계통이 axiom_context_inject.sh 에도 있었다(같은 날 수리, test_frontier_axes_derive.sh).
#
# 양방향(한쪽만 재면 검사 사망과 정상이 겉보기가 같다):
#   [A] 정상 파생 — 정본 ①②③④ 순서가 priority 1..4 로 반영
#   [B] 자동 강등 — 정본이 레버로 안 세는 open 방향은 demoted_by_constitution
#   [C] 위반 주입(마커 제거) — 정적 priority 유지 + 경고, 죽지 않음(회귀 없음)
#   [D] 박제 아님 — 정본 순서를 바꾸면 파생 순위도 따라 바뀐다
#   [E] closed 불변 — 이미 판정된 방향은 강등 로직이 건드리지 않는다
#==============================================================================
suppressWarnings(suppressMessages({
  ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  source(file.path(ROOT, "02_Infrastructure/portfolio/gap_vector_steering.R"))
}))

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", m)) }
ng <- function(m) { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s\n", m)) }
`%||%` <- function(a, b) if (is.null(a)) b else a

cat("== [A] 정상 파생 — 정본 순서가 priority 로 ==\n")
d <- gv_apply_constitution_order(root = ROOT)
if (identical(d$asymmetry_distribution_target$priority, 1L))
  ok("v8.4 ① 비대칭 표적이 priority 1") else
  ng(sprintf("비대칭이 1순위 아님 (prio=%s) — 정본 ① 반영 실패", d$asymmetry_distribution_target$priority))
if (isTRUE(d$screen_tier_recovery$priority < d$overlay_refinement$priority))
  ok("②screen-tier 가 ③overlay 보다 앞") else ng("정본 ②③ 순서 미반영")
if (identical(d$asymmetry_distribution_target$constitution, "listed_current"))
  ok("정본 열거 표식(listed_current) 부착") else ng("정본 열거 표식 부재")

cat("== [B] 자동 강등 — 정본 미열거 open 방향 ==\n")
if (identical(d$non_return_datasource$status, "demoted_by_constitution"))
  ok("비-return 이 정본 미열거로 자동 강등") else
  ng(sprintf("비-return status=%s — v8.4 주력 해제가 조준기에 미반영", d$non_return_datasource$status))
if (isTRUE(d$non_return_datasource$priority > d$asymmetry_distribution_target$priority))
  ok("강등분이 주력보다 뒤 순위") else ng("강등분이 아직 앞 순위")

cat("== [E] closed 불변 ==\n")
if (identical(d$dpl_feature$status, "closed") &&
    identical(d$core_alpha_standalone$status, "closed"))
  ok("closed 2종은 강등 로직 비대상") else ng("closed 방향이 변조됨")

cat("== [C] 위반 주입 — 마커 제거 시 정적 유지 + 경고 ==\n")
TMP <- file.path(ROOT, ".cache", "_test_gvs_root")
unlink(TMP, recursive = TRUE); dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
cm <- readLines(file.path(ROOT, "CLAUDE.md"), warn = FALSE, encoding = "UTF-8")
writeLines(gsub("FRONTIER_AXES_START", "FRONTIER_AXES_XXXXX", cm), file.path(TMP, "CLAUDE.md"),
           useBytes = TRUE)
warned <- FALSE
d2 <- withCallingHandlers(
  gv_apply_constitution_order(root = TMP),
  warning = function(w) { warned <<- TRUE; invokeRestart("muffleWarning") })
if (warned) ok("마커 부재 시 경고 발화") else ng("마커 부재가 조용히 통과 — 침묵 실패")
if (identical(d2$non_return_datasource$status, "open"))
  ok("정적 priority/status 그대로 유지 (회귀 없음)") else
  ng("폴백인데 강등이 적용됨 (거짓 성공)")

cat("== [D] 박제 아님 — 정본 순서 변경이 전파 ==\n")
# ★조작 선행검증 의무: 치환이 실제로 먹었는지 **먼저** 확인한다.
#   초판이 이 검증을 빼먹어 bold 마커(**)를 뺀 패턴으로 치환에 실패했고,
#   파일이 안 바뀌었으니 순위도 그대로였는데 그걸 '전파 실패(=박제)'로 오귀속했다.
#   음성 대조는 자기 조작이 유효함을 먼저 증명해야 결론을 낼 자격이 생긴다.
i_lv <- grep("조건-안 레버만 프론티어", cm)[1]
orig <- cm[i_lv]
swapped_line <- sub("① \\*\\*비대칭 표적\\*\\*(.+?) ② screen-tier 재고 회수\\(overlay 큐\\)",
                    "① screen-tier 재고 회수(overlay 큐) ② **비대칭 표적**\\1",
                    orig, perl = TRUE)
if (identical(swapped_line, orig)) {
  ng("[선행검증] 정본 줄 치환 실패 — 이 축은 판정 불가(테스트 패턴이 원문과 어긋남)")
} else {
  ok("[선행검증] 정본 줄 치환이 실제로 적용됨")
  cm2 <- cm; cm2[i_lv] <- swapped_line
  writeLines(cm2, file.path(TMP, "CLAUDE.md"), useBytes = TRUE)
  d3 <- suppressWarnings(gv_apply_constitution_order(root = TMP))
  if (isTRUE(d3$screen_tier_recovery$priority < d3$asymmetry_distribution_target$priority))
    ok("정본에서 순서를 바꾸니 파생 순위도 바뀜 (하드코딩 아님)") else
    ng(sprintf("정본 변경 미전파 — 어딘가 아직 박제 (screen=%s asym=%s)",
               d3$screen_tier_recovery$priority, d3$asymmetry_distribution_target$priority))
}
unlink(TMP, recursive = TRUE)

cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", PASS, FAIL))
if (FAIL > 0L) quit(status = 1L)
