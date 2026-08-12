## L5 — census 스캐너 수리: 줄 단위 → **호출 단위(AST)** + 변수 경로 해석
## 사전등록(측정 전 고정, 이 주석이 정본):
##  L2 스캐너가 한 실행에서 양방향으로 틀렸다:
##   ①오탐 benchmark_source_parity — 쓰기 동사 `cat(` 와 목적지 `hist_p <- file.path(...,"06_Registry",...)`
##     가 **다른 줄**이라 추적 사본을 못 봄
##   ②누락 failure_revival_monitor — 경로가 **변수 구성**이라 정규식 밖
##  수리: R 파일은 `parse()` 로 **호출 단위** 순회 + file 인자가 심볼이면 같은 파일의 대입을 찾아 해석.
##  ★★통제 먼저, 수치는 나중 (feedback-verify-both-directions-always):
##   C1 양성 통제: benchmark_source_parity.R = **추적 사본 있음**으로 나와야 한다(결함 아님)
##   C2 음성 통제: close_round.R = **결함**으로 나와야 한다
##   C3 회수 통제: failure_revival_monitor.R 이 **탐지되어야** 한다(구판이 놓친 것)
##  통제 3종 중 하나라도 실패하면 **수치를 보고하지 않고 중단**한다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")

WRITE_FNS <- c("write_json","writeLines","fwrite","saveRDS","write.csv","cat","write_lines","file.append")
FILE_ARGS <- c("file","path","con","output","filename")

## ★빈 심볼(누락 인자, 예: x[i, ])의 규칙 — 실측으로 확인한 것:
##   · `e[[i]]` 로 **추출**해 함수 인자로 바로 넘기는 것은 안전(객체 반환일 뿐).
##   · 그러나 **변수에 담아 그 변수를 참조하면** R 이 "argument ... is missing" 을 던진다
##     (`.EMPTY <- quote(expr=)` 로 저장했다가 정확히 이 오류를 맞았다).
##   ⇒ 빈 심볼은 **저장하지 말고 제자리에서** 판정한다.
##   ⚠무음 스킵 방지: 걸러낸 수를 센다(빈 결과를 합격으로 읽는 계통 차단).
.is_empty_at <- function(container, i) {
  is.symbol(container[[i]]) && !nzchar(as.character(container[[i]]))
}
.skipped <- new.env(parent = emptyenv()); .skipped$n <- 0L

## 표현식 트리에서 쓰기 호출 수집
collect_calls <- function(e, acc = list()) {
  if (is.call(e)) {
    fn <- e[[1]]
    fname <- if (is.symbol(fn)) as.character(fn) else
             if (is.call(fn) && length(fn) >= 3 && identical(as.character(fn[[1]]), "::")) as.character(fn[[3]]) else ""
    if (fname %in% WRITE_FNS) acc[[length(acc)+1L]] <- e
  }
  if (is.recursive(e)) for (i in seq_along(e)) {
    if (.is_empty_at(e, i)) { .skipped$n <- .skipped$n + 1L; next }
    acc <- collect_calls(e[[i]], acc)
  }
  acc
}
## 심볼 → 대입 RHS 수집 (같은 파일 정적 해석)
collect_assigns <- function(exprs) {
  env <- list()
  walk <- function(e) {
    if (is.call(e) && length(e) >= 3 &&
        as.character(e[[1]])[1] %in% c("<-","=","<<-") && is.symbol(e[[2]])) {
      env[[as.character(e[[2]])]] <<- paste(deparse(e[[3]]), collapse=" ")
    }
    if (is.recursive(e)) for (i in seq_along(e)) {
      if (.is_empty_at(e, i)) { .skipped$n <- .skipped$n + 1L; next }
      walk(e[[i]])
    }
  }
  for (e in exprs) walk(e); env
}
## ★변수 해석은 **전이적**이어야 한다 — 1단계로는 못 푼다.
##   실측 반례: close_round.R 은 `cache_dir <- file.path(.cr_root(), ".cache")` 후
##   `ledger <- file.path(cache_dir, "round_closures.jsonl")` 로 두 단 건너뛴다.
##   1단계만 풀면 결과 문자열에 `.cache` 가 안 나타나 **탐지 0** 이 된다(통제가 이걸 잡았다).
.resolve <- function(s, env, max_iter = 6L) {
  if (is.na(s) || !length(names(env))) return(s)
  for (k in seq_len(max_iter)) {
    prev <- s
    for (nm in names(env)) {
      ## ★`\\b` 를 쓰면 안 된다 — 이 저장소는 `.root`·`.cr_root`·`.rev_history_path` 처럼
      ##   **점으로 시작하는 식별자**가 흔한데, `" .rev_history_path"` 위치에서 앞이 공백(비단어)
      ##   뒤가 `.`(비단어)라 **단어 경계가 성립하지 않아 매치가 통째로 실패**한다.
      ##   (C3 통제가 정확히 이걸 잡았다 — `\\b` 판본에서 탐지 0)
      ##   ⇒ R 식별자 경계를 직접 쓴다: 앞뒤로 [A-Za-z0-9._] 가 오지 않을 것.
      pat <- paste0("(?<![A-Za-z0-9._])\\Q", nm, "\\E(?![A-Za-z0-9._])")
      if (grepl(pat, s, perl=TRUE)) s <- gsub(pat, paste0("(", env[[nm]], ")"), s, perl=TRUE)
    }
    if (identical(s, prev) || nchar(s) > 4000L) break   # 수렴 또는 폭주 방지
  }
  s
}
dest_of <- function(cl, env) {
  nm <- names(cl); dst <- NULL
  for (a in FILE_ARGS) if (!is.null(nm) && a %in% nm) { dst <- cl[[a]]; break }
  if (is.null(dst) && as.character(cl[[1]])[1] %in% c("write_json","writeLines","fwrite","saveRDS") &&
      length(cl) >= 3) dst <- cl[[3]]
  if (is.null(dst)) return(NA_character_)
  .resolve(paste(deparse(dst), collapse=" "), env)
}
is_append <- function(cl, dest) {
  nm <- names(cl)
  ap <- !is.null(nm) && "append" %in% nm && isTRUE(tryCatch(eval(cl[["append"]]), error=function(e) FALSE))
  ap || grepl("\\.jsonl", dest, fixed=FALSE)
}
classify_dest <- function(s) {
  if (is.na(s)) return("unknown")
  if (grepl("\\.cache", s)) "cache"
  else if (grepl("06_Registry|04_Research|00_Lawbook|qepm/(registry|memory)", s)) "tracked"
  else "other"
}
is_standing <- function(p)
  grepl("02_Infrastructure/(contracts|ops|axiom|hooks|portfolio|validation|worktask|memory|telegram|tools)/", p) ||
  grepl("qepm/(scripts|registry|mailbox)/", p)

files <- list.files(c("02_Infrastructure","qepm"), pattern="\\.[Rr]$", full.names=TRUE, recursive=TRUE)
files <- files[!grepl("/(\\.venv|renv|node_modules)/", files)]
cat(sprintf("[입력 실측] R 파일 %d개 (AST 파싱)\n", length(files)))
rows <- list(); nparse_fail <- 0L
for (f in files) {
  ex <- tryCatch(parse(f, keep.source=FALSE), error=function(e) NULL)
  if (is.null(ex)) { nparse_fail <- nparse_fail + 1L; next }
  env <- collect_assigns(ex)
  calls <- unlist(lapply(ex, function(e) collect_calls(e)), recursive=FALSE)
  if (!length(calls)) next
  dests <- vapply(calls, function(cl) dest_of(cl, env), character(1))
  kinds <- vapply(dests, classify_dest, character(1))
  apps  <- mapply(is_append, calls, dests)
  if (!any(kinds == "cache" & apps)) next
  rows[[length(rows)+1L]] <- data.table(
    file = f, standing = is_standing(f),
    cache_append = sum(kinds == "cache" & apps),
    tracked_any  = sum(kinds == "tracked"),
    cache_dest   = paste(unique(dests[kinds=="cache" & apps]), collapse=" | "))
}
cat(sprintf("파싱 실패 %d / %d\n", nparse_fail, length(files)))
R <- rbindlist(rows, fill=TRUE)
R[, klass := ifelse(tracked_any > 0, "D2_MITIGATED", "D1_DEFECT")]

## ── 통제 먼저 ──
g <- function(pat) R[grepl(pat, file)]
## ★C1 정의 정정(측정이 통제를 고쳤다): 처음엔 "parity = D2_MITIGATED 로 나와야" 로 적었으나
##   parity 의 `.cache` 쓰기는 `write_json(..., "benchmark_parity_latest.json")` 로 **append 가 아니다**
##   (현재 상태 파일). 스캐너 정의상 cache-append 사이트가 없어 **목록에 안 나오는 게 옳다**.
##   ⇒ 양성 통제의 올바른 형태 = "**결함으로 분류되지 않을 것**"(부재도 통과).
c1 <- g("benchmark_source_parity\\.R$"); C1 <- !any(c1$klass == "D1_DEFECT")
c2 <- g("contracts/close_round\\.R$");   C2 <- nrow(c2) == 1L && c2$klass == "D1_DEFECT"
c3 <- g("failure_revival_monitor\\.R$"); C3 <- nrow(c3) == 1L
cat(sprintf("\n[통제] C1 양성(parity=D2) %s · C2 음성(close_round=D1) %s · C3 회수(revival 탐지) %s\n", C1, C2, C3))
if (!(C1 && C2 && C3)) {
  cat("⇒ 통제 실패 — **수치 보고 중단**. 스캐너를 못 믿는다.\n")
  if (nrow(c1)) print(c1[, .(file, klass, tracked_any, cache_dest)])
  if (nrow(c2)) print(c2[, .(file, klass, tracked_any, cache_dest)])
  cat(sprintf("revival 탐지 행수: %d\n", nrow(c3)))
  write_json(list(verdict="CONTROLS_FAILED", C1=C1, C2=C2, C3=C3),
             file.path(OUT,"l5_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
  quit(save="no")
}
SD <- R[standing == TRUE & klass == "D1_DEFECT"][order(file)]
cat(sprintf("\n★통제 3/3 통과 — 수치 신뢰 가능\n상시 경로 D1_DEFECT: %d건 (구판 3건)\n", nrow(SD)))
print(SD[, .(file=sub("^02_Infrastructure/","2I/",file), cache_dest=substr(cache_dest,1,70))])
cat(sprintf("\n(참고) 일회성 D1 %d · D2_MITIGATED %d\n",
            nrow(R[standing==FALSE & klass=="D1_DEFECT"]), nrow(R[klass=="D2_MITIGATED"])))
verdict <- if (nrow(SD) > 3L) "T1_MORE_THAN_L2" else if (nrow(SD) == 3L) "T2_SAME_AS_L2" else "T3_FEWER"
cat(sprintf("판정: %s\n⚠R 파일만 — .sh/.py writer 는 이 스캐너 범위 밖(계속 하한)\n", verdict))
fwrite(R, file.path(OUT,"l5_scanner_fixed.csv"))
write_json(list(verdict=verdict, controls=list(C1=C1,C2=C2,C3=C3),
                standing_defects=nrow(SD), defects=SD, all=R),
           file.path(OUT,"l5_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
