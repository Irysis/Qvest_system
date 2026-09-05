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
#   E1 미측정 계열이 n=5 안에 도달한다 ★실사고
#   E2 prio 계열(낙폭 축)이 통째로 밀려나지 않는다 — 최소 1칸 (전부-탐색 역효과 차단)
#   E3 계열 중복 없음 (기존 계약)
#   E4 "측정됨" 판정이 **등급 난 칸**이다 — spec 존재로 세지 않는다(다운로드≠적재)
#   E5 돌연변이 통제 — 구 규칙(prio 단독)이면 shrinkage 가 5칸 밖이다
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
suppressMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_weight_arms.R"), local = globalenv()))))

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

cat("=== 1. 탐색 도달 ===\n")
if (any(grepl("shrinkage", fams))) ok("E1 generated_shrinkage_lift 가 5칸 안에 ★실사고") else
  ng("E1 shrinkage 가 여전히 도달 불가")

cat("=== 2. 착취 슬롯 보존 ===\n")
PRIO <- c("tail_aware","entropy","risk_parity","risk_based","optimizer","classical","score_blend")
if (sum(fams %in% PRIO) >= 1L) ok(sprintf("E2 prio 계열 %d칸 생존", sum(fams %in% PRIO))) else
  ng("E2 prio 계열이 전부 밀려났다 — 전부-탐색 역효과")

cat("=== 3. 계열 중복 ===\n")
if (!anyDuplicated(fams)) ok("E3 계열 중복 없음") else ng("E3 같은 계열 중복 선정", paste(fams, collapse = ","))

cat("=== 4. 측정 판정 축 ===\n")
src <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_weight_arms.R"), encoding = "UTF-8", warn = FALSE), collapse = "\n")
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

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_weight_arms_explore","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
