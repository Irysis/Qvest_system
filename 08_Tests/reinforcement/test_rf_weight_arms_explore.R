#!/usr/bin/env Rscript
#==============================================================================
# test_rf_weight_arms_explore.R — B2 비중 선정의 탐색 슬롯 (2026-09-05)
#
# 실사고: rf_weight_arms.R 헤더는 "계열당 1개씩, **미측정 우선**" 이라 적어 뒀는데 코드는 고정 prio
#   표로만 정렬했다. 표에 없는 계열은 prio 9 로 밀리고, 명시된 7계열이 5칸을 다 채워
#   generated_shrinkage_lift(Ledoit-Wolf 등 9종)가 **원리상 도달 불가**였다 —
#   실측: 전 이력 418 셀 중 shrinkage 측정 0건, 계열 순위 11 중 8위.
#   같은 날 B2 가 "공분산 추정오차가 비중을 왜곡"(minvar 1.506 · hrp 1.986 vs ivol 2.394 · cvar 2.526)을
#   실측했는데, 그 처방인 shrinkage 가 한 번도 안 걸린 상태였다.
#
# 판정 축:
#   E1 미측정 계열이 n=5 안에 도달한다 ★실사고 — 픽스처 원장(미측정 계열 있음) 위에서(11-11 재조준)
#   E1b 탐색 슬롯 기록 = 미측정 계열만 · E1c 같은 선정의 착취 슬롯 · 중복 · 칸 수
#   E6 반대 방향 — 전 계열 측정 픽스처면 탐색 슬롯 0 · prio 순서 그대로
#   E2 prio 계열(낙폭 축)이 통째로 밀려나지 않는다 — 최소 1칸 (전부-탐색 역효과 차단)
#   E3 계열 중복 없음 (기존 계약)
#   E4 "측정됨" 판정이 **등급 난 칸**이다 — spec 존재로 세지 않는다(다운로드≠적재)
#   E5 돌연변이 통제 — 구 규칙(prio 단독)이면 shrinkage 가 5칸 밖이다
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
suppressMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
## 검사 대상 소스(기본 = 운영 파일). 양성 대조(돌연변이 사본)를 돌릴 때만 QV_TEST_RFW_ARMS_SRC 로 바꾼다.
SRC_ARMS <- Sys.getenv("QV_TEST_RFW_ARMS_SRC", file.path(ROOT, "02_Infrastructure/ops/rf_weight_arms.R"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
invisible(capture.output(suppressMessages(source(SRC_ARMS, local = globalenv()))))
.RFW_ROOT_PROD <- .RFW_ROOT

a <- tryCatch(rf_pick_weight_arms(5L), error = function(e) { ng("선정기 실행", conditionMessage(e)); NULL })
if (is.null(a) || !length(a$cells)) { cat("선정 결과 없음 — 중단\n"); quit(status = 1) }
## ★정규식 대신 문자열 분해 — heredoc 이 백슬래시를 접어 R 이 죽는다(오늘 세 번째).
fams <- vapply(a$cells, function(x) {
  lb <- as.character(x$label)
  k <- max(gregexpr("(", lb, fixed = TRUE)[[1]])
  if (k > 0) substr(lb, k + 1L, nchar(lb) - 1L) else lb
}, character(1))
ids  <- vapply(a$cells, function(x) as.character(x$weighting$catalog_id %||% ""), character(1))
cat("선정:", paste(sprintf("%s[%s]", ids, fams), collapse = " · "), "\n")

cat("=== 1. 탐색 도달 (픽스처 원장 · 11-11 재조준) ===\n")
## 운영 원장 L1 에서는 shrinkage 계열이 이미 측정됐다(설계상 측정되면 탐색 슬롯이 사라진다 — 자기 제한).
##   그래서 운영 상태로는 E1 의 전제('미측정 계열이 있다')가 없다(nightly_triage_20261111 (a) 9행).
##   E1 을 그 전제를 직접 만든 픽스처 원장 위에서 잰다 — 09-05 실사고 상태 재현: prio 7계열은 측정됨,
##   prio 밖 계열(shrinkage 포함)은 미측정. shrinkage 에는 spec 은 있고 등급(port_t)이 없는 죽은 칸을 하나 둔다(E4 규약 — 죽은 칸은 측정이 아니다).
##   카탈로그는 운영 것을 읽기만 한다(픽스처 루트의 weight_catalog.R = 운영 파일을 source 하는 한 줄).
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/portfolio/weight_catalog.R"), local = globalenv()))))
A2 <- as.data.table(weight_catalog_arms(quiet = TRUE))
if ("probe_ok" %in% names(A2)) A2 <- A2[probe_ok %in% c(TRUE, NA)]
if ("status" %in% names(A2))   A2 <- A2[!status %in% c("retracted", "withdrawn", "failed")]
A2 <- A2[!label %in% c("equal", "ew", "equal_weight")]
ALL_FAMS <- sort(unique(A2$family))
PRIO7 <- c("tail_aware","entropy","risk_parity","risk_based","optimizer","classical","score_blend")
SHR <- "generated_shrinkage_lift"
if (!(SHR %in% ALL_FAMS) || !all(PRIO7 %in% ALL_FAMS)) { ng("E0 카탈로그에 shrinkage · prio 계열이 없다 — 픽스처 전제 붕괴", paste(ALL_FAMS, collapse = ",")); quit(status = 1) }
FIXES <- character(0)
mk_fix <- function(measured, dead = character(0)) {
  fx <- gsub("\\\\", "/", tempfile("rfw_fix_")); FIXES <<- c(FIXES, fx)
  for (d in c("02_Infrastructure/portfolio", "06_Registry", ".cache", "specs")) dir.create(file.path(fx, d), recursive = TRUE)
  writeLines(sprintf('source("%s")', gsub("\\\\", "/", file.path(ROOT, "02_Infrastructure/portfolio/weight_catalog.R"))),
             file.path(fx, "02_Infrastructure/portfolio/weight_catalog.R"))
  att <- list(); i <- 0L
  for (f in c(measured, dead)) {
    i <- i + 1L; sp <- file.path(fx, "specs", sprintf("spec_%02d.json", i))
    writeLines(toJSON(list(weighting = list(kind = "catalog", catalog_id = A2[family == f]$catalog_id[1])), auto_unbox = TRUE), sp)
    att[[i]] <- list(essence = list(spec = sp, port_t = if (f %in% dead) NA else 2.0))
  }
  writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, entries = list(list(base_id = "FIX", attempts = att))),
                    auto_unbox = TRUE, na = "null", pretty = TRUE), file.path(fx, "06_Registry/reinforce_ledger_l1.json"))
  fx
}
pick_on <- function(fx) {
  .RFW_ROOT <<- fx; on.exit(.RFW_ROOT <<- .RFW_ROOT_PROD)
  r <- tryCatch(rf_pick_weight_arms(5L), error = function(e) NULL)
  fm <- if (is.null(r)) character(0) else vapply(r$cells, function(x) {
    lb <- as.character(x$label); k <- max(gregexpr("(", lb, fixed = TRUE)[[1]])
    if (k > 0) substr(lb, k + 1L, nchar(lb) - 1L) else lb }, character(1))
  lg <- file.path(fx, ".cache/reinforce_auto_log.jsonl")
  ev <- if (file.exists(lg)) lapply(readLines(lg, warn = FALSE, encoding = "UTF-8"), fromJSON) else list()
  ex <- Filter(function(e) identical(e$event, "family_explore_slots"), ev)
  list(fams = fm, explore = if (length(ex)) strsplit(as.character(ex[[length(ex)]]$fams), ",", fixed = TRUE)[[1]] else character(0))
}
F1 <- pick_on(mk_fix(measured = PRIO7, dead = SHR))
cat("픽스처(prio 7 측정 · shrinkage 죽은 칸):", paste(F1$fams, collapse = " · "), "| 탐색 슬롯:", paste(F1$explore, collapse = ","), "\n")
if (SHR %in% F1$fams) ok("E1 미측정 계열(generated_shrinkage_lift)이 5칸 안에 ★실사고 — 죽은 칸은 측정으로 안 센다") else
  ng("E1 shrinkage 가 여전히 도달 불가", paste(F1$fams, collapse = ","))
if (SHR %in% F1$explore && all(F1$explore %in% setdiff(ALL_FAMS, PRIO7))) ok(sprintf("E1b 탐색 슬롯 %d칸 = 미측정 계열만(%s)", length(F1$explore), paste(F1$explore, collapse = ","))) else
  ng("E1b 탐색 슬롯 기록이 없거나 측정된 계열이 탐색으로 들어갔다", paste(F1$explore, collapse = ","))
if (sum(F1$fams %in% PRIO7) >= 1L && !anyDuplicated(F1$fams) && length(F1$fams) == 5L) ok(sprintf("E1c 같은 선정에서 prio 계열 %d칸 생존 · 중복 없음 · 5칸", sum(F1$fams %in% PRIO7))) else
  ng("E1c 픽스처 선정에서 착취 슬롯 · 중복 · 칸 수 위반", paste(F1$fams, collapse = ","))

cat("=== 1r. 반대 방향 — 전부 측정됐으면 탐색 슬롯이 없다(자기 제한 복귀) ===\n")
F2 <- pick_on(mk_fix(measured = ALL_FAMS))
pk2 <- copy(A2); setorderv(pk2, c("family", "est_cost_min"), c(1L, 1L), na.last = TRUE); pk2 <- pk2[, .SD[1L], by = family]
pv <- c("tail_aware" = 1, "entropy" = 2, "risk_parity" = 3, "risk_based" = 4, "optimizer" = 5, "classical" = 6, "score_blend" = 7)
pk2[, .p := pv[family]]; pk2[is.na(.p), .p := 9]; setorderv(pk2, c(".p", "est_cost_min"), c(1L, 1L), na.last = TRUE)
want2 <- head(pk2$family, 5L)
cat("픽스처(전 계열 측정):", paste(F2$fams, collapse = " · "), "| 탐색 슬롯:", paste(F2$explore, collapse = ","), "\n")
if (!length(F2$explore) && identical(F2$fams, want2) && !(SHR %in% F2$fams)) ok("E6 전부 측정 → 탐색 슬롯 0 · prio 순서 그대로(shrinkage 5칸 밖)") else
  ng("E6 전부 측정됐는데 탐색 슬롯이 남거나 prio 순서가 아니다", sprintf("got=%s want=%s explore=%s", paste(F2$fams, collapse = ","), paste(want2, collapse = ","), paste(F2$explore, collapse = ",")))

cat("=== 2. 착취 슬롯 보존 ===\n")
PRIO <- c("tail_aware","entropy","risk_parity","risk_based","optimizer","classical","score_blend")
if (sum(fams %in% PRIO) >= 1L) ok(sprintf("E2 prio 계열 %d칸 생존", sum(fams %in% PRIO))) else
  ng("E2 prio 계열이 전부 밀려났다 — 전부-탐색 역효과")

cat("=== 3. 계열 중복 ===\n")
if (!anyDuplicated(fams)) ok("E3 계열 중복 없음") else ng("E3 같은 계열 중복 선정", paste(fams, collapse = ","))

cat("=== 4. 측정 판정 축 ===\n")
src <- paste(readLines(SRC_ARMS, encoding = "UTF-8", warn = FALSE), collapse = "\n")
if (grepl("reinforce_ledger_l1.json", src, fixed = TRUE) && grepl("es$port_t", src, fixed = TRUE))
  ok("E4 원장 essence 기준(등급 난 칸)") else ng("E4 spec 존재로 센다 — 죽은 칸이 측정됨으로 읽힌다")
if (!grepl('list.files(file.path(.RFW_ROOT, ".cache/rf_parallel")', src, fixed = TRUE))
  ok("E4b spec 파일 스캔 잔존 없음") else ng("E4b 구 spec 스캔이 남아 있다")

cat("=== 5. 돌연변이 통제 (구 규칙 재현) ===\n")
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/portfolio/weight_catalog.R"), local = globalenv()))))
A <- as.data.table(weight_catalog_arms(quiet = TRUE))
setorderv(A, c("family", "est_cost_min"), c(1L, 1L), na.last = TRUE)
pk <- A[, .SD[1L], by = family]
prio <- c("tail_aware" = 1, "entropy" = 2, "risk_parity" = 3, "risk_based" = 4,
          "optimizer" = 5, "classical" = 6, "score_blend" = 7)
pk[, .p := prio[family]]; pk[is.na(.p), .p := 9]
setorderv(pk, c(".p", "est_cost_min"), c(1L, 1L), na.last = TRUE)
old5 <- head(pk, 5L)$family
if (!any(grepl("shrinkage", old5))) ok("E5 구 규칙에서는 shrinkage 가 5칸 밖 — 픽스처가 결함을 가른다") else
  ng("E5 구 규칙에서도 들어온다 — 판별력 없음")

unlink(FIXES, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_weight_arms_explore","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
