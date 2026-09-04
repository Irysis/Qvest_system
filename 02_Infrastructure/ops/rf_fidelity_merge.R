#!/usr/bin/env Rscript
#==============================================================================
# rf_fidelity_merge.R — 축별 감사 결과를 **하나의 판정으로 병합** (도훈 2026-09-04)
#
# 왜 R 이 병합하나: LLM 판정자를 하나 더 세우면 그 판정자가 다시 분류한다 — 팬아웃으로
#   없앤 병이 마지막 단계에서 되살아난다. 병합 규칙은 결정론이므로 코드가 진다.
#   (이 저장소 규약과 같다: "R 이 등재한다. LLM 은 카탈로그를 못 쓴다".)
#
# 산출: <wdir>/fidelity_audit.json — **구판과 같은 스키마**다. 하류(rf_fidelity_audit_lib.R
#   verify · rf_audit_disposition · 재구현 피드백)는 한 줄도 안 바뀐다.
#   추가로 axis_verdicts 를 싣는다 — **무엇을 안 봤는지가 남는 자리**가 이것이다.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.args <- commandArgs(trailingOnly = TRUE)
WDIR <- .args[1] %||% ""
AXP  <- .args[2] %||% file.path(Sys.getenv("QM_ROOT", getwd()), "06_Registry/rf_fidelity_axes.json")
if (!nzchar(WDIR) || !dir.exists(WDIR)) { cat("merge: wdir 없음\n"); quit(status = 0) }

AXES <- tryCatch(fromJSON(AXP, simplifyVector = FALSE)$axes, error = function(e) NULL)
if (is.null(AXES) || !length(AXES)) { cat("merge: 축 등록부를 못 읽었다\n"); quit(status = 1) }

RANK <- c(faithful = 0L, unverifiable = 1L, adapted = 2L, misdeclared = 3L)
.chr <- function(x) vapply(x %||% list(), function(y) as.character(y)[1], character(1))

# ★채움 항목 차단 — 항목 **전체**가 비발견 문장일 때만 걸러낸다.
#   실측(2026-09-04 1403.8125): 첫 판은 "없다|없음" 을 **포함하면** 버렸고, 그 바람에
#   156~331자짜리 실질 발견 4건이 전부 사라졌다 — "논문 3.2절은 … 명시하지 않는다.
#   FIDELITY.changed 에도 없다." 는 발견의 **정상 서술**이다. 계기가 재야 것을 안 재고
#   재기 쉬운 것을 재 형태다. 이제 길이 가드 + 전체 일치로만 걸러낸다.
.filler <- function(s) {
  t <- trimws(gsub("[[:space:]]+", " ", s))
  nchar(t) <= 40L & grepl(paste0("^[-*• ]*(미신고 ?변경|신호 ?불일치|불일치|변경 ?사항|해당 ?사항|해당)? ?",
                              "(없음|없다|없습니다|N/?A|none|no [a-z]+)[.。]?$"),
                       t, ignore.case = TRUE)
}

rows <- list(); mergedU <- character(0); mergedS <- character(0); evid <- character(0)
for (ax in AXES) {
  k <- ax$key
  f <- file.path(WDIR, sprintf("fidelity_axis_%s.json", k))
  A <- if (file.exists(f)) tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(A)) {
    # ★축이 조용히 빠지지 않는다 — 이게 팬아웃의 요점이다
    rows[[length(rows) + 1L]] <- list(axis = k, required = isTRUE(ax$required), model = ax$model,
      verdict = "unverifiable", admissible = FALSE,
      reason = if (file.exists(f)) "축 산출물 파손" else "축 미산출(레인 실패·타임아웃)",
      confidence = "", checked = "", counterexample = "")
    next
  }
  v <- as.character(A$verdict %||% "unverifiable")[1]
  if (!v %in% names(RANK)) v <- "unverifiable"
  u <- .chr(A$undeclared_changes); s <- .chr(A$signal_mismatch)
  u <- u[nzchar(u) & !.filler(u)]; s <- s[nzchar(s) & !.filler(s)]
  ev <- as.character(A$evidence %||% "")[1]
  adm <- TRUE; rsn <- ""
  if (identical(v, "misdeclared")) {
    # 근거 없는 기각은 감사가 아니라 잡음이다 — 판정을 끌고 가지 못하게 막는다
    if (!nzchar(ev)) { adm <- FALSE; rsn <- "misdeclared 인데 원문 근거가 없다" }
    else if (!length(u) && !length(s)) { adm <- FALSE; rsn <- "misdeclared 인데 실제 지적 항목이 0건(채움 문장 제외 후)" }
  }
  if (adm) {
    if (length(u)) mergedU <- c(mergedU, sprintf("[%s] %s", k, u))
    if (length(s)) mergedS <- c(mergedS, sprintf("[%s] %s", k, s))
    if (nzchar(ev)) evid <- c(evid, sprintf("[%s] %s", k, ev))
  }
  rows[[length(rows) + 1L]] <- list(axis = k, required = isTRUE(ax$required), model = ax$model,
    verdict = v, admissible = adm, reason = rsn,
    confidence = as.character(A$confidence %||% "")[1],
    checked = as.character(A$checked %||% "")[1],
    counterexample = as.character(A$counterexample %||% "")[1],
    n_findings = length(u) + length(s))
}

.eff <- function(r) if (isTRUE(r$admissible)) r$verdict else "unverifiable"
effs <- vapply(rows, .eff, character(1))
reqok <- vapply(rows, function(r) isTRUE(r$required) && !identical(.eff(r), "unverifiable"), logical(1))
nreq  <- sum(vapply(rows, function(r) isTRUE(r$required), logical(1)))

# ── 종합 판정 ────────────────────────────────────────────────────────────────
#  · 발견 하나는 나머지 축의 "이상 없음" 으로 희석되지 않는다 (최악 채택)
#  · faithful 은 **required 축이 전부 원문을 읽었을 때만** 낼 수 있다 —
#    안 읽고 낸 faithful 이 이 감사의 최악 실패 모드다
FIN <- if (any(effs == "misdeclared")) "misdeclared" else
       if (any(effs == "adapted"))     "adapted"     else
       if (sum(reqok) == nreq)         "faithful"    else "unverifiable"

confs <- vapply(rows, function(r) if (identical(.eff(r), "misdeclared")) r$confidence %||% "" else "", character(1))
flags <- character(0)
if (identical(FIN, "misdeclared") && all(confs[nzchar(confs)] == "low"))
  flags <- c(flags, "유일한 지적 축의 confidence 가 low — 재구현 전에 사람이 볼 값어치가 있다")
if (sum(reqok) < nreq)
  flags <- c(flags, sprintf("required 축 %d/%d 만 원문 확인 — 나머지는 판정 근거가 없다", sum(reqok), nreq))
ninadm <- sum(!vapply(rows, function(r) isTRUE(r$admissible), logical(1)))
if (ninadm > 0L) flags <- c(flags, sprintf("불채택 축 %d건(근거 없는 기각 또는 미산출)", ninadm))

out <- list(
  verdict = FIN,
  undeclared_changes = as.list(mergedU),
  signal_mismatch    = as.list(mergedS),
  evidence           = paste(evid, collapse = " / "),
  confidence = if (identical(FIN, "faithful") && sum(reqok) == nreq) "high"
               else if (identical(FIN, "unverifiable")) "low" else "medium",
  note = sprintf("축 팬아웃 %d개(판독형 opus %d · 대조형 sonnet %d) — 발견 %d건. %s",
                 length(rows),
                 sum(vapply(rows, function(r) identical(r$model, "opus"), logical(1))),
                 sum(vapply(rows, function(r) identical(r$model, "sonnet"), logical(1))),
                 length(mergedU) + length(mergedS),
                 paste(effs, collapse = "/")),
  mode = "fanout",
  axis_verdicts = rows,      # ★무엇을 안 봤는지가 남는 자리
  flags = as.list(flags),
  merged_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))

p <- file.path(WDIR, "fidelity_audit.json")
write(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), p)
cat(sprintf("merge: %s | 축 %d (%s) | 발견 %d | flags %d\n",
            FIN, length(rows), paste(effs, collapse = ","),
            length(mergedU) + length(mergedS), length(flags)))
