## test_round_kit_shard.R — 칸 평가 분할(rk_shard · 2026-10-15) 성질 검사(양방향) + 병렬 실행기 정적 점검
##   ① 몫끼리 겹치지 않고 합치면 전부(순서 보존) ② 인자 없으면 전부 ③ 형식 오류는 거부(위반 주입) ④ 평가 스크립트가 cells-only 에서만 분할
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
cells <- lapply(sprintf("C%02d", 1:21), function(z) list(code = z))
code <- function(x) vapply(x, function(z) z$code, character(1))
for (K in c(1L, 2L, 4L, 6L, 21L, 25L)) {
  parts <- lapply(seq_len(K), function(i) code(rk_shard(cells, sprintf("--shard=%d/%d", i, K))))
  allc <- unlist(parts)
  chk(sprintf("K=%d 몫 합 = 전부 · 겹침 0 · 몫 크기 차 ≤ 1", K),
      setequal(allc, code(cells)) && !anyDuplicated(allc) && (max(lengths(parts)) - min(lengths(parts))) <= 1L,
      paste(lengths(parts), collapse = ","))
}
p2 <- code(rk_shard(cells, "--shard=2/4"))
chk("몫 안 순서 = 원래 칸 순서(교차 배정 · 2/4 = C02 · C06 · …)", identical(p2, code(cells)[seq(2, 21, by = 4)]), paste(p2, collapse = ","))
chk("인자 없음 → 전부(종합 평가 경로)", identical(code(rk_shard(cells, character(0))), code(cells)))
for (bad in c("--shard=0/4", "--shard=5/4", "--shard=a/b", "--shard=2", "--shard=1/0"))
  chk(sprintf("형식 오류 거부: %s(위반 주입)", bad), inherits(tryCatch(rk_shard(cells, bad), error = function(e) e), "error"))
## 평가 스크립트 배선 — cells-only 일 때만 분할 · 종합 판정은 전부(소스 텍스트로 · 좌표가 아니라 문장)
for (f in c("04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/evaluate.R",
            "04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map/evaluate.R",
            "04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz/evaluate.R")) {
  s <- paste(readLines(file.path(ROOT, f), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  chk(sprintf("%s — CELLS <- if (CELLS_ONLY) rk_shard(…) else pre$cells", basename(dirname(f))),
      grepl("CELLS <- if (CELLS_ONLY) rk_shard(", s, fixed = TRUE) && grepl("else pre$cells", s, fixed = TRUE))
}
sh <- paste(readLines(file.path(ROOT, "04_Research/programs/_lib/eval_parallel.sh"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("실행기 — --cells-only --shard=$i/$K 로 띄우고 wait 뒤 종합 평가", grepl("--cells-only --shard=$i/$K", sh, fixed = TRUE) && grepl("wait", sh, fixed = TRUE))
cat(sprintf("\n== round_kit_shard: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_kit_shard","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
