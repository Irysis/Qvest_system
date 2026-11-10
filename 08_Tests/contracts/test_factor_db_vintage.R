#!/usr/bin/env Rscript
#==============================================================================
# test_factor_db_vintage.R — 팩터 DB 판 표식 계약(v10.2 · 수리 이전 측정을 기계가 가린다)
#   대상: 02_Infrastructure/contracts/factor_db_vintage.R · 정본 06_Registry/factor_db_vintage.json
#   본다: 측정 시각 판독(실행 id 우선 · 보유 재측정 시각은 쓰지 않는다) · 전체 범위 수리 앞뒤 · 팩터 목록 범위 수리(선언한 칸만 비켜 간다 ·
#         엔진 기저 · 선언 없음은 닿은 것으로) · 진행 중 수리 · 시각 모름 = NA · 원장 형식 위반 · 운영 원장의 현행 판정 · A 자격 관문 상시 보류.
#   격리: 임시 원장(path 인자)과 임시 폴더. 운영 원장은 읽기만.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)][1])
ROOT <- NA_character_
for (p in c(dirname(dirname(dirname(me))), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.na(p) || !nzchar(p)) next
  p <- gsub("\\\\", "/", p)
  if (file.exists(file.path(p, "02_Infrastructure", "contracts", "factor_db_vintage.R"))) { ROOT <- p; break }
}
if (is.na(ROOT)) stop("저장소 루트를 찾지 못했다")
E <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure", "contracts", "factor_db_vintage.R"), envir = E, keep.source = FALSE)
pass <- 0L; fail <- 0L
chk <- function(name, cond) {
  ok <- isTRUE(tryCatch(cond, error = function(e) { cat("     오류:", conditionMessage(e), "\n"); FALSE }))
  if (ok) pass <<- pass + 1L else fail <<- fail + 1L
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", name))
}
TD <- tempfile("fdv_test_"); dir.create(TD)
LP <- file.path(TD, "ledger.json")
wl <- function(entries) { writeLines(toJSON(list(schema = "factor_db_vintage_v1", entries = entries), auto_unbox = TRUE, null = "null"), LP); E$fdv_ledger(path = LP) }
L <- wl(list(list(id = "ALL-1", completed_at = "2026-11-10T01:38:00+09:00", scope = "all"),
             list(id = "SUB-1", completed_at = "2026-11-10T11:26:00+09:00", scope = list(factors = list("Q16_X", "R17_Y")))))
mk <- function(name, auth = NULL, spec = NULL) {
  d <- file.path(TD, name); dir.create(d, recursive = TRUE)
  if (!is.null(auth)) writeLines(toJSON(auth, auto_unbox = TRUE), file.path(d, "authoritative_remeasure.json"))
  if (!is.null(spec)) writeLines(toJSON(spec, auto_unbox = TRUE), file.path(d, "cell_spec.json"))
  d
}
st <- function(d) E$fdv_stale(d, ledger = L)

d_old <- mk("20261105_101010_111", list(run_id = "20261105_101010_111"))
chk("T01 전체 범위 수리보다 앞선 측정은 낡았다(두 수리 모두에 걸린다)", isTRUE(st(d_old)$stale) && setequal(st(d_old)$hits, c("ALL-1", "SUB-1")))
d_new <- mk("20261110_120000_222", list(run_id = "20261110_120000_222"))
chk("T02 마지막 수리 뒤 측정은 낡지 않았다", identical(st(d_new)$stale, FALSE) && !length(st(d_new)$hits))
d_mid <- mk("20261110_050000_333", list(run_id = "20261110_050000_333"))
chk("T03 두 수리 사이 측정 — 선언이 없으면(임의 코드 엔진) 팩터 목록 범위 수리에도 닿은 것으로 본다", isTRUE(st(d_mid)$stale) && identical(st(d_mid)$hits, "SUB-1"))
d_decl <- mk("20261110_050001_444", list(run_id = "20261110_050001_444"), list(factors = list(list(id = "M01_A"), list(id = "V10_B"))))
chk("T04 두 수리 사이 측정 — 팩터를 선언했고 겹치지 않으면 비켜 간다", identical(st(d_decl)$stale, FALSE) && identical(st(d_decl)$declared_factors, 2L))
d_hit <- mk("20261110_050002_555", list(run_id = "20261110_050002_555"), list(factors = list(list(id = "M01_A"), list(id = "Q16_X"))))
chk("T05 선언한 팩터가 수리 범위와 겹치면 낡았다", isTRUE(st(d_hit)$stale))
d_eng <- mk("20261110_050003_666", list(run_id = "20261110_050003_666"), list(base_signal = list(kind = "engine", path = "x/engine.R"), factors = list(list(id = "M01_A"))))
chk("T06 엔진 기저 칸은 선언이 있어도 닿은 것으로 본다(엔진이 읽은 팩터를 알 수 없다)", isTRUE(st(d_eng)$stale))
d_rem <- mk("x/20260905_095537_777/remeasure_a", list(run_id = "20260905_095537_777", remeasured_at = "2026-11-10T12:00:00+0900"))
chk("T07 보유에서 다시 잰 기록은 원 실행 시각으로 판정한다(재측정 시각이 수리 뒤여도 낡았다)", isTRUE(st(d_rem)$stale) && grepl("2026-09-05", st(d_rem)$measured_at))
d_path <- mk("stage/20261110_130000_888/sub")
chk("T08 권위 기록에 실행 id 가 없으면 폴더 경로의 실행 id 로 읽는다", identical(st(d_path)$stale, FALSE) && grepl("2026-11-10T13:00:00", st(d_path)$measured_at))
d_unk <- mk("no_time", list(strategy_id = "S"))
chk("T09 측정 시각을 알 수 없으면 NA(판정 불가)다 — 통과로 치지 않는다", is.na(st(d_unk)$stale))
L2 <- wl(list(list(id = "RUN-1", completed_at = NULL, scope = "all")))
chk("T10 완료 시각이 없는 수리(진행 중)는 범위에 닿는 측정을 전부 낡은 것으로 본다", isTRUE(E$fdv_stale(d_new, ledger = L2)$stale))
bad <- function(entries) inherits(try(wl(entries), silent = TRUE), "try-error")
chk("T11 원장 형식 위반(범위 어휘 밖 · 빈 팩터 목록 · 시각 형식 · id 없음)은 멈춘다",
    bad(list(list(id = "X", completed_at = "2026-11-10T01:00:00+09:00", scope = "some"))) &&
      bad(list(list(id = "X", completed_at = "2026-11-10T01:00:00+09:00", scope = list(factors = list())))) &&
      bad(list(list(id = "X", completed_at = "어제", scope = "all"))) && bad(list(list(completed_at = "2026-11-10T01:00:00+09:00", scope = "all"))))

## 운영 원장 — 형식 · 순서 · 현행 판정
LO <- E$fdv_ledger(ROOT)
ids <- vapply(LO$entries, function(e) e$id, character(1))
tms <- vapply(LO$entries, function(e) as.numeric(E$.fdv_time(e$completed_at)), numeric(1))
chk("T12 운영 원장: 세 수리(재무 v2 전체 재빌드 · 방향/저장 규약 · 총부채 0)가 완료 시각 순서로 있다",
    all(c("FUND-V2-FULL-REBUILD-20261109", "FACTOR-DIRECTION-STORAGE-REPAIR-20261109", "FACTOR-DB-TOTALDEBT-ZERO-REPAIR-20261110") %in% ids) &&
      all(is.finite(tms)) && !is.unsorted(tms))
tot <- LO$entries[[which(ids == "FACTOR-DB-TOTALDEBT-ZERO-REPAIR-20261110")]]
chk("T13 운영 원장: 총부채 수리의 범위 = 수리 명세의 영향 팩터 27개와 같다", {
  sp <- fromJSON(file.path(ROOT, "04_Research/01_reports/factor_db_debt_fix_20261110/repair_spec.json"), simplifyVector = FALSE)
  setequal(unlist(tot$scope$factors), unlist(sp$targets)) && length(unlist(tot$scope$factors)) == 27L })
real <- file.path(ROOT, "stage_artifacts/replication/20260905_095537_1276/remeasure_close_t1_5562284e")
if (dir.exists(real)) chk("T14 운영 원장: 9월에 잰 실측 산출물은 낡은 것으로 판정된다(재측정 전 소비 금지)", isTRUE(E$fdv_stale(real, ROOT)$stale)) else
  cat("  [skip] T14 실측 산출물 없음\n")
chk("T15 판 표식: 유효 시작 = 마지막 수리 완료 시각", identical(E$fdv_stamp(ROOT)$valid_from, format(max(as.POSIXct(tms, origin = "1970-01-01", tz = "Asia/Seoul")), "%Y-%m-%dT%H:%M:%S")))

unlink(TD, recursive = TRUE)
cat(sprintf("\n%s\n", toJSON(list(test = "test_factor_db_vintage", pass = pass, fail = fail), auto_unbox = TRUE)))
quit(status = if (fail > 0L) 1L else 0L)
