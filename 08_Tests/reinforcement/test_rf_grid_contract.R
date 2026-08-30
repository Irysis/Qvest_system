#==============================================================================
# test_rf_grid_contract.R — 격자 ↔ 원장 계약 (2026-08-30)
#
# 왜: 격자(reinforce_program.json)와 원장 검증기(reinforce_ledger.R)는 **다른 파일**인데
#   서로를 전제한다. 2026-08-30 B3 축이 risk_overlay → universe 로 바뀌었을 때 원장의
#   허용 축 목록이 안 따라와서 B3 5칸이 **등록 단계에서 거부**됐고(append_failed →
#   halt_no_jobs) 루프가 10/20 에서 영구 정지했다. 실행 로그에는 오류가 아니라
#   "할 일 없음" 으로 찍혀 정상 대기처럼 보였다.
# 부작용 없음.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }

g <- jsonlite::fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
ax <- unique(vapply(g$blocks, function(b) as.character(b$axis %||% ""), character(1)))
bad <- setdiff(ax, RF_KEYWORD_AXES_L1)
if (!length(bad)) {
  ok(sprintf("격자 축 %d종 전부 원장 허용 안에 있다 (%s)", length(ax), paste(ax, collapse = ", ")))
} else ng("격자 축이 원장에 없다", sprintf("%s — 그 블록은 등록 거부되고 루프가 멈춘다", paste(bad, collapse = ", ")))

# 위반 주입 — 없는 축을 하나 넣으면 반드시 잡혀야 한다(가드가 살아있는지)
if (length(setdiff(c(ax, "no_such_axis_zzz"), RF_KEYWORD_AXES_L1)) == 1L) {
  ok("위반 주입(가짜 축) 적발")
} else ng("위반 주입 미적발", "이 검사는 방어선이 아니다")

codes <- unlist(lapply(g$blocks, function(b) vapply(b$cells, function(c) as.character(c$code), character(1))))
if (length(codes) == length(unique(codes))) {
  ok(sprintf("셀 코드 %d개 중복 0", length(codes)))
} else ng("셀 코드 중복", "승자 판정이 코드 기반이라 중복은 조용히 엇갈린다")
n_exp <- as.integer(Sys.getenv("RF_GRID_N", "20"))
if (length(codes) == n_exp) ok(sprintf("격자 %d칸", n_exp)) else ng("격자 칸 수", length(codes))

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
if (FAIL > 0L) quit(status = 1L)
