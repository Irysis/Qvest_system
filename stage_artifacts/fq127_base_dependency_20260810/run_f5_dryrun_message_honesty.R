## FQ-127 F5 — 드라이런 메시지 정직성 계통 점검
## 사전등록(측정 전 고정, 이 주석이 정본):
##  F1 에서 `close_round` 의 요약 마지막 줄이 `write_marker` 와 **무관하게** 항상
##  "마커 발행 → Stop 게이트 자동 통과" 를 주장하는 것을 발견했다 — 드라이런에서
##  **일어나지 않은 일을 사실로 보고**했다('빈 결과 = 합격' 의 메시지 층 판본).
##  ⇒ `dry_run`/`write_marker`/`apply` 류 **억제 플래그를 가진 다른 계약**도 같은지 본다.
##  판별(AST, 텍스트 아님 — 오늘 텍스트 탐지로 두 번 실패했다):
##   ①파일이 억제 플래그 인자를 선언하는가(formals)
##   ②그 플래그가 **조건으로 쓰이는** 지점이 있는가(쓰기 억제는 되는가)
##   ③**행위 주장 출력**(cat/message 의 문자열에 '발행/기록/저장/완료/appended/written' 등)이
##     그 플래그 **조건 밖**에 있는가 ← 있으면 드라이런에서 거짓 보고
##  ★플래그 이름은 파일마다 다르므로 formals 에서 **발견**하고, 하드코딩하지 않는다.
##  판정:
##   T1_SYSTEMIC : 플래그 보유 파일 중 거짓보고 의심 >= 3 → 계통, 룰 레벨 규약 필요
##   T2_FEW      : 1~2
##   T3_ISOLATED : 0 → close_round 단독 사고
##  ⚠**의심 목록이지 확정이 아니다** — 조건 밖 출력이 무해할 수 있다(예: 시작 배너). 표본 출력 필수.
##  ★read-only.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(CODE_ROOT)
OUT <- "stage_artifacts/fq127_base_dependency_20260810"

FLAG_PAT <- "^(dry_run|dryrun|write_marker|no_write|write|apply|commit|persist|do_write)$"
ACT_PAT  <- "발행|기록|저장|완료|등재|append|written|writing|saved|committed|persisted|갱신"
.EMPTY_AT <- function(c, i) is.symbol(c[[i]]) && !nzchar(as.character(c[[i]]))

files <- list.files("02_Infrastructure", pattern="\\.R$", full.names=TRUE, recursive=TRUE)
cat(sprintf("[스캔] %d 파일\n", length(files)))
rows <- list(); nfail <- 0L
for (f in files) {
  ex <- tryCatch(parse(f, keep.source=FALSE), error=function(e) NULL)
  if (is.null(ex)) { nfail <- nfail + 1L; next }
  flags <- character(0); has_cond <- FALSE; acts_outside <- 0L; act_samples <- character(0)
  ## ① formals 에서 플래그 발견
  walk_fn <- function(e) {
    ## ★`function(a,b) body` 는 `` `function` `` **호출**이고 인자 목록은 **e[[3]][[2]]**(pairlist)에 있다.
    ##   초판은 `as.list(e[[3]])` 의 이름을 봤는데 그건 list(`function`, pairlist, body, srcref) 라
    ##   names 가 NULL → **577 파일 전건 0** 이 나왔다. 0 을 정지 신호로 본 덕에 잡혔다(오늘 3번째).
    if (is.call(e) && length(e) >= 3 && as.character(e[[1]])[1] %in% c("<-","=") &&
        is.call(e[[3]]) && identical(as.character(e[[3]][[1]])[1], "function")) {
      fm <- names(as.list(e[[3]][[2]]))
      if (length(fm)) flags <<- union(flags, fm[grepl(FLAG_PAT, fm)])
    }
    if (is.recursive(e)) for (i in seq_along(e)) { if (.EMPTY_AT(e,i)) next; walk_fn(e[[i]]) }
  }
  for (e in ex) walk_fn(e)
  if (!length(flags)) next
  ## ②③ 플래그가 조건으로 쓰이는지 + 행위 주장 출력이 그 조건 **밖**인지
  walk_use <- function(e, inside) {
    if (is.call(e)) {
      fn <- as.character(e[[1]])[1]
      if (fn == "if" && length(e) >= 2) {
        cond <- paste(deparse(e[[2]]), collapse=" ")
        guarded <- any(vapply(flags, function(fl) grepl(paste0("\\b", fl, "\\b"), cond), logical(1)))
        if (guarded) has_cond <<- TRUE
        for (i in 3:length(e)) { if (i > length(e) || .EMPTY_AT(e,i)) next
          walk_use(e[[i]], inside || guarded) }
        walk_use(e[[2]], inside); return(invisible(NULL))
      }
      if (fn %in% c("cat","message","warning")) {
        s <- paste(deparse(e), collapse=" ")
        ## ★초판 오탐: `cat(x, file=..., append=TRUE)` 는 **메시지가 아니라 파일 쓰기**인데
        ##   ACT_PAT 의 'append' 에 걸렸다(검증 표본 4건 중 3건이 이 유형).
        ##   file= 인자가 있으면 사람용 출력이 아니므로 제외한다.
        is_write <- !is.null(names(e)) && any(names(e) == "file")
        if (grepl(ACT_PAT, s) && !inside && !is_write) {
          acts_outside <<- acts_outside + 1L
          if (length(act_samples) < 2L) act_samples <<- c(act_samples, substr(gsub("\\s+"," ",s), 1, 96))
        }
      }
    }
    if (is.recursive(e)) for (i in seq_along(e)) { if (.EMPTY_AT(e,i)) next; walk_use(e[[i]], inside) }
  }
  for (e in ex) walk_use(e, FALSE)
  rows[[length(rows)+1L]] <- data.table(file=sub("^02_Infrastructure/","2I/",f),
    flags=paste(flags, collapse=","), guarded=has_cond, acts_outside=acts_outside,
    sample=if (length(act_samples)) act_samples[1] else "")
}
R <- rbindlist(rows, fill=TRUE)
cat(sprintf("파싱 실패 %d · 플래그 보유 파일 **%d**\n", nfail, nrow(R)))
## ★양성 대조: close_round.R 은 `write_marker` 를 가지므로 **반드시 잡혀야** 한다.
##   안 잡히면 스캐너가 죽은 것이므로 수치를 보고하지 않는다(오늘 반복 규약).
if (!nrow(R) || !any(grepl("close_round\\.R$", R$file))) {
  cat("⇒ **양성 대조 실패** — close_round.R(write_marker 보유)이 안 잡혔다. 스캐너 사망, 수치 보고 중단\n")
  write_json(list(verdict="SCANNER_DEAD", n_with_flags=nrow(R)),
             file.path(OUT, "f5_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
  quit(save="no")
}
cat("  [양성대조] close_round.R 포착 ✓\n")
SUS <- R[guarded == TRUE & acts_outside > 0][order(-acts_outside)]
cat(sprintf("\n★조건 밖 행위-주장 출력 보유(**의심**): %d\n", nrow(SUS)))
if (nrow(SUS)) print(head(SUS[, .(file, flags, acts_outside)], 10))
cat("\n=== [검증] 의심 표본 4 — 조건 밖 출력 실물 ===\n")
for (i in seq_len(min(4L, nrow(SUS)))) cat(sprintf("  [%s] %s\n", SUS$file[i], SUS$sample[i]))
cat("\n=== [검증·음성] 플래그 있고 조건 밖 출력 0 — 표본 3 ===\n")
CL <- R[guarded == TRUE & acts_outside == 0]
for (i in seq_len(min(3L, nrow(CL)))) cat(sprintf("  [%s] flags=%s\n", CL$file[i], CL$flags[i]))
verdict <- if (nrow(SUS) >= 3L) "T1_SYSTEMIC" else if (nrow(SUS) >= 1L) "T2_FEW" else "T3_ISOLATED"
cat(sprintf("\n판정: %s\n", verdict))
cat("⚠**의심 목록이지 확정이 아니다** — 조건 밖 출력이 시작 배너처럼 무해할 수 있다. 개별 확인 필요\n")
fwrite(R, file.path(OUT, "f5_dryrun_scan.csv"))
write_json(list(verdict=verdict, n_files=length(files), n_parse_fail=nfail,
                n_with_flags=nrow(R), n_suspect=nrow(SUS), suspects=SUS),
           file.path(OUT, "f5_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
