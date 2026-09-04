#!/usr/bin/env Rscript
#==============================================================================
# test_rf_mechanism_tone.R — 기전 서술이 데스크가 읽는 물건인가 (도훈 2026-09-04)
#
# 배경: 기전 서술에 비표준 한글 조어가 쌓였다. 실측(기전 텍스트 38건 · 9,001자):
#   분자 9 · 분모 9 · 밴드 13 · 그릇 7 · 청정 3 · 한 점 4.
#   도훈 지적 두 번 — "청정맴버십 이런 단어는 퀀트계에서 안쓰잖아",
#   "그릇, 청정같은 한글단어들 너무 많은데".
#
# ★프롬프트만으로는 안 된다 — LLM 이 안 지키면 그대로 나간다. 그래서 산출물을 잰다.
#   이 검사는 **차단이 아니라 계측**이다: 빈도를 세고 추세를 남긴다. 차단하면 기전이
#   통째로 안 나오고, 그건 조어보다 나쁘다(오늘 텔레그램에서 배운 것 — 상한이 발송을
#   통째로 막았다).
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

# 금지 조어 ↔ 표준 대응 (프롬프트의 표와 같은 정본이어야 한다)
BAN <- c("분자", "분모", "밴드", "그릇", "청정", "한 점")
STD <- c("PORT_t", "MDD", "Sharpe", "Calmar", "CAGR", "OOS", "IC", "IR", "turnover")

cat("=== A. 프롬프트가 대응표를 갖는가 ===\n")
psrc <- paste(readLines("02_Infrastructure/ops/rf_lcode_mechanism.sh", warn = FALSE), collapse = "\n")
if (grepl("비유를 쓰지 마라", psrc, fixed = TRUE)) ok("A1 비유 금지 절") else ng("A1 절 부재")
miss <- BAN[!vapply(BAN, function(w) grepl(w, psrc, fixed = TRUE), logical(1))]
if (!length(miss)) ok(sprintf("A2 금지어 %d종 전부 표에 있다", length(BAN))) else
  ng("A2 표 누락", paste(miss, collapse = ","))
if (grepl("프런트 퀀트 데스크", psrc, fixed = TRUE)) ok("A3 독자 지정") else ng("A3 독자 미지정")
if (grepl("생존편향 없는 유니버스", psrc, fixed = TRUE))
  ok("A4 '청정 멤버십' 의 표준 대체어 명시 ★도훈 실측 지적") else ng("A4 대체어 없음")

cat("\n=== B. 산출물 계측 — 조어 빈도 추세 ===\n")
fs <- list.files("stage_artifacts/l_code/reinforcement", pattern = "[.]json$", full.names = TRUE)
.txt <- function(p) {
  d <- tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(d)) return("")
  v <- c(as.character(d$mechanism %||% ""), as.character(d$next_block_design %||% ""))
  na <- d$next_block_actions
  if (!is.null(na)) v <- c(v, if (is.data.frame(na)) as.character(na$action) else
                              unlist(lapply(na, function(x) as.character(x$action %||% ""))))
  v <- c(v, as.character(unlist(d$avoid %||% list())))
  paste(v[nzchar(v)], collapse = " ")
}
if (!length(fs)) { cat("  SKIP L-code 없음\n") } else {
  info <- file.info(fs); fs <- fs[order(info$mtime)]
  tx <- vapply(fs, .txt, character(1)); keep <- nzchar(tx); fs <- fs[keep]; tx <- tx[keep]
  n_ch <- sum(nchar(tx))
  cnt <- vapply(BAN, function(w) sum(vapply(gregexpr(w, tx, fixed = TRUE),
                function(m) if (m[1] == -1L) 0L else length(m), integer(1))), integer(1))
  cat(sprintf("  대상 %d건 · %d자\n", length(tx), n_ch))
  for (w in BAN) cat(sprintf("    %-6s %3d  (만자당 %.1f)\n", w, cnt[[w]], 1e4 * cnt[[w]] / max(1, n_ch)))
  per10k <- 1e4 * sum(cnt) / max(1, n_ch)
  cat(sprintf("  합계 %d회 · 만자당 %.1f\n", sum(cnt), per10k))
  ok(sprintf("B1 계측 성립 (기준선 만자당 %.1f — 다음 판과 비교할 값)", per10k))
  # 표준 용어는 실제로 쓰이는가 (음성 대조 — 조어만 세면 '아무 말도 안 함'이 최적해가 된다)
  sc <- sum(vapply(STD, function(w) sum(vapply(gregexpr(w, tx, fixed = TRUE),
              function(m) if (m[1] == -1L) 0L else length(m), integer(1))), integer(1)))
  cat(sprintf("  표준 용어 %d회 · 만자당 %.1f\n", sc, 1e4 * sc / max(1, n_ch)))
  if (sc > sum(cnt)) ok("B2 표준 용어가 조어보다 많다") else
    ng("B2 조어가 표준 용어보다 많다", sprintf("%d vs %d", sum(cnt), sc))
  # 최근 3건 — 프롬프트 수리 후 산출이 들어오면 여기서 갈린다
  k <- max(1L, length(tx) - 2L)
  rc <- sum(vapply(BAN, function(w) sum(vapply(gregexpr(w, tx[k:length(tx)], fixed = TRUE),
            function(m) if (m[1] == -1L) 0L else length(m), integer(1))), integer(1)))
  rn <- sum(nchar(tx[k:length(tx)]))
  cat(sprintf("  최근 %d건: 조어 %d회 · 만자당 %.1f\n", length(tx) - k + 1L, rc, 1e4 * rc / max(1, rn)))
}

cat("\n=== C. 경계 — 계측이지 차단이 아니다 ===\n")
lib <- paste(readLines("02_Infrastructure/ops/rf_lcode_mechanism_lib.R", warn = FALSE), collapse = "\n")
if (!grepl("분자|그릇|청정", lib))
  ok("C1 병합기가 조어로 기전을 **기각하지 않는다** — 차단하면 기전이 통째로 사라진다") else
  ng("C1 병합기에 조어 차단이 들어갔다", "오늘 텔레그램에서 상한이 발송을 통째로 막았다")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_mechanism_tone","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
