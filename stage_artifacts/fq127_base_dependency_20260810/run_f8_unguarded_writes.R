## FQ-127 F8 — 억제 플래그가 **쓰기를 실제로 막는가** (실행 없이, 구조로)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  ★실행 위험 회피: "dry_run 이 억제하는가" 를 **실행으로** 확인하면, 억제가 안 될 경우
##    **바로 그 부작용을 내가 일으킨다**(axiom inject·registry 쓰기 등). 실행하지 않는다.
##  ★F5 의 교훈 분리: 실패한 건 **메시지 매칭**(부정어·혼재 어휘)이었고,
##    '플래그가 조건으로 쓰이는가' 는 **AST 구조 질문**이라 신뢰 가능했다.
##    ⇒ 여기서는 **쓰기 호출**이 플래그 가드 **안**에 있는지만 본다. 문구는 안 읽는다.
##  판정 대상: 억제 플래그를 선언한 파일에서 **가드 밖 쓰기 호출**
##    (writeLines/write_json/fwrite/saveRDS/write.csv/file.copy/file.rename/unlink/dir.create
##     + `cat(..., file=)`). 있으면 **플래그가 그 쓰기를 못 막는다** = 실질 결함.
##  ★위양성 원인 미리 인정: ①플래그가 애초에 그 쓰기와 무관할 수 있다(다른 목적 인자)
##    ②최상위 스크립트의 무조건 초기화 쓰기 ⇒ **표본 출력 필수**, 수치는 상한으로만.
##  판정: U1_REAL(가드밖 쓰기 보유 파일 >= 3) / U2_FEW(1~2) / U3_NONE(0)
##  ★양성 대조: `close_round.R` 은 쓰기가 `if (isTRUE(write_marker))` 안에 있으므로 **깨끗해야** 한다.
##  ★read-only. 실행 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(CODE_ROOT)
OUT <- "stage_artifacts/fq127_base_dependency_20260810"

FLAG_PAT  <- "^(dry_run|dryrun|write_marker|no_write|write|apply|commit|persist|do_write)$"
WRITE_FNS <- c("writeLines","write_json","fwrite","saveRDS","write.csv","write.table",
               "file.copy","file.rename","unlink","dir.create","file.remove","file.append")
.EMPTY_AT <- function(c, i) is.symbol(c[[i]]) && !nzchar(as.character(c[[i]]))
## ★1차 결과의 오탐은 **명확히 배제 가능한 부류**였다(F5 의 부정어 오탐과 다르다):
##   `dir.create(...)`(디렉터리 생성) · 락 파일 쓰기(`LOCK`/`lock` 경로) — 억제 대상 작업이 아니라
##   **실행 인프라**다. 드라이런에서도 만들어지는 게 정상.
##   ⇒ 이 두 부류만 제외한다. (그 외는 남긴다 — 넓게 잡고 표본으로 확인하는 원칙 유지)
.is_infra_write <- function(e) {
  fn <- as.character(e[[1]])[1]
  if (fn %in% c("dir.create")) return(TRUE)
  s <- paste(deparse(e), collapse = " ")
  grepl("LOCK|lock_root|lockfile|\\.lock", s)
}
is_write_call <- function(e) {
  fn <- as.character(e[[1]])[1]
  hit <- (fn %in% WRITE_FNS) || (fn == "cat" && !is.null(names(e)) && any(names(e) == "file"))
  hit && !.is_infra_write(e)
}
files <- list.files("02_Infrastructure", pattern="\\.R$", full.names=TRUE, recursive=TRUE)
cat(sprintf("[스캔] %d 파일 (실행 없음 — 구조만)\n", length(files)))
rows <- list()
for (f in files) {
  ex <- tryCatch(parse(f, keep.source=FALSE), error=function(e) NULL); if (is.null(ex)) next
  flags <- character(0)
  wf <- function(e) {
    if (is.call(e) && length(e) >= 3 && as.character(e[[1]])[1] %in% c("<-","=") &&
        is.call(e[[3]]) && identical(as.character(e[[3]][[1]])[1], "function")) {
      fm <- names(as.list(e[[3]][[2]])); if (length(fm)) flags <<- union(flags, fm[grepl(FLAG_PAT, fm)])
    }
    if (is.recursive(e)) for (i in seq_along(e)) { if (.EMPTY_AT(e,i)) next; wf(e[[i]]) }
  }
  for (e in ex) wf(e)
  if (!length(flags)) next
  out_n <- 0L; in_n <- 0L; samp <- character(0)
  wu <- function(e, inside) {
    if (is.call(e)) {
      if (as.character(e[[1]])[1] == "if" && length(e) >= 2) {
        cond <- paste(deparse(e[[2]]), collapse=" ")
        gd <- any(vapply(flags, function(fl) grepl(paste0("\\b", fl, "\\b"), cond), logical(1)))
        walk_cond <- e[[2]]
        for (i in 3:length(e)) { if (i > length(e) || .EMPTY_AT(e,i)) next; wu(e[[i]], inside || gd) }
        wu(walk_cond, inside); return(invisible(NULL))
      }
      if (is_write_call(e)) {
        if (inside) in_n <<- in_n + 1L else {
          out_n <<- out_n + 1L
          if (length(samp) < 2L) samp <<- c(samp, substr(gsub("\\s+"," ", paste(deparse(e), collapse=" ")), 1, 88))
        }
      }
    }
    if (is.recursive(e)) for (i in seq_along(e)) { if (.EMPTY_AT(e,i)) next; wu(e[[i]], inside) }
  }
  for (e in ex) wu(e, FALSE)
  if (in_n + out_n == 0L) next
  rows[[length(rows)+1L]] <- data.table(file=sub("^02_Infrastructure/","2I/",f),
    flags=paste(flags, collapse=","), writes_guarded=in_n, writes_unguarded=out_n,
    sample=if (length(samp)) samp[1] else "")
}
R <- rbindlist(rows, fill=TRUE)
cat(sprintf("플래그+쓰기 보유 파일 %d\n", nrow(R)))
## 양성 대조 먼저 — close_round 는 가드 안에 있어야 한다
cr <- R[grepl("close_round\\.R$", file)]
ctl_ok <- nrow(cr) == 1L && cr$writes_unguarded == 0L && cr$writes_guarded > 0L
cat(sprintf("[양성대조] close_round.R — 가드내 %s · 가드밖 %s → %s\n",
            if (nrow(cr)) cr$writes_guarded else NA, if (nrow(cr)) cr$writes_unguarded else NA, ctl_ok))
if (!ctl_ok) { cat("⇒ 양성대조 실패 — 스캐너 불신, 수치 보고 중단\n")
  write_json(list(verdict="CONTROL_FAILED", control=cr), file.path(OUT,"f8_result.json"),
             pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(save="no") }
BAD <- R[writes_unguarded > 0][order(-writes_unguarded)]
cat(sprintf("\n★가드 **밖** 쓰기 보유: %d / %d\n", nrow(BAD), nrow(R)))
if (nrow(BAD)) print(head(BAD[, .(file, flags, writes_guarded, writes_unguarded)], 10))
cat("\n=== [검증] 가드밖 쓰기 실물 표본 4 ===\n")
for (i in seq_len(min(4L, nrow(BAD)))) cat(sprintf("  [%s] %s\n", BAD$file[i], BAD$sample[i]))
cat("\n=== [검증·음성] 전부 가드 안 — 표본 3 ===\n")
GD <- R[writes_unguarded == 0]
for (i in seq_len(min(3L, nrow(GD)))) cat(sprintf("  [%s] flags=%s · 가드내 쓰기 %d\n", GD$file[i], GD$flags[i], GD$writes_guarded[i]))
verdict <- if (nrow(BAD) >= 3L) "U1_REAL" else if (nrow(BAD) >= 1L) "U2_FEW" else "U3_NONE"
cat(sprintf("\n판정: %s\n", verdict))
cat("⚠상한이다 — 플래그가 그 쓰기와 무관하거나(다른 목적 인자) 최상위 초기화 쓰기일 수 있다. 표본 확인 필수\n")
fwrite(R, file.path(OUT,"f8_write_guard.csv"))
write_json(list(verdict=verdict, control_ok=ctl_ok, n_files=nrow(R), n_unguarded=nrow(BAD), unguarded=BAD),
           file.path(OUT,"f8_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
