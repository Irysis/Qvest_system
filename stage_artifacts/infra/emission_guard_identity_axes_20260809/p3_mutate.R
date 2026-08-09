## P3 — 돌연변이 주입기 (검사기 검출력 실증용)
##   emission_guard.R 의 축 하나를 무력화한 뒤 검사가 **빨개지는지** 본다.
##   초록이 돌연변이에도 초록이면 그 케이스는 공허하다.
##   ★사용 후 반드시 백업에서 복원한다(호출 스크립트가 책임).
args <- commandArgs(trailingOnly = TRUE)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
G <- file.path(ROOT, "02_Infrastructure/factor_db/emission_guard.R")
txt <- readLines(G, warn = FALSE)

mut <- args[1]
sub1 <- function(from, to) {
  i <- grep(from, txt, fixed = TRUE)
  if (length(i) != 1L) stop(sprintf("돌연변이 지점이 %d건 (1건이어야 함): %s", length(i), from))
  txt[i] <<- sub(from, to, txt[i], fixed = TRUE)
}

if (mut == "kill_D") {
  # 축 D 판정을 상시 거짓으로 (죽은 배출을 못 보게)
  sub1("dD[, dead := n_rows > 0L & n_cov == 0L]", "dD[, dead := FALSE]")
} else if (mut == "kill_T") {
  # 동률 문턱을 도달 불가로 (준-죽은 배출을 못 보게)
  sub1("tie_warn = 0.99, tie_watch = 0.95,", "tie_warn = 2.00, tie_watch = 2.00,")
} else if (mut == "kill_I_rank") {
  # ★랭크 대신 원값으로 상관 — 단조변환 중복만 놓쳐야 한다 (비트동일은 계속 잡힘)
  sub1("if (any(k)) r[k] <- rank(v[k], ties.method = \"average\")", "if (any(k)) r[k] <- v[k]")
} else if (mut == "kill_I_decl") {
  # 선언 대조 제거 — 경보가 소음으로 폭발해야 한다
  sub1("det[, declared := pair_key %in% dedup_pairs]", "det[, declared := FALSE]")
} else if (mut == "kill_exempt") {
  # 면제 무력화 — 시장레벨 15종이 오발화해야 한다
  sub1("dead_decl <- intersect(dead_all, decl_axis(\"D\"))", "dead_decl <- character(0)")
} else if (mut == "kill_unmeasured") {
  # 못 재는 상태를 'OK' 로 내려앉히기 — U 축이 잡아야 한다
  sub1("verdict = \"UNMEASURED\"))", "verdict = \"OK\"))")
} else if (mut == "kill_liveness") {
  # 계측 사망 감지 제거 — Z4 가 잡아야 한다
  sub1("if (degenerate) {", "if (FALSE) {")
} else {
  stop("알 수 없는 돌연변이: ", mut)
}
writeLines(txt, G)
cat(sprintf("[p3] 돌연변이 주입: %s\n", mut))
