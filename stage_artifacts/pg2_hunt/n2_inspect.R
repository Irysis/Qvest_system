## n2 — n1 섹션2 가 0행이었던 원인 규명 (날짜 컬럼 검출 실패)
## ★0 을 "자산 없음" 으로 읽지 않는다. 실제 스키마를 본다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[n2] ", fmt, "\n"), ...)); flush.console() }

roots <- c(".cache", "02_Infrastructure/data", "04_Research/method_frontier", "06_Registry")
allf <- unlist(lapply(roots, function(r)
  if (dir.exists(r)) list.files(r, pattern="\\.(parquet|rds|csv)$", recursive=TRUE, full.names=TRUE) else character(0)))
pick <- function(pat) {
  h <- allf[grepl(pat, basename(allf), ignore.case=TRUE)]
  h <- h[file.size(h) > 20000]
  h[order(-file.size(h))]
}
targets <- c(head(pick("insider"), 4), head(pick("flow|smartmoney"), 4), head(pick("contract"), 2))
say("검사 대상 %d개", length(targets))

for (f in targets) {
  say("=== %s (%.1fMB) ===", basename(f), file.size(f)/1e6)
  d <- tryCatch({
    if (grepl("parquet$", f)) as.data.table(read_parquet(f))
    else if (grepl("rds$", f)) { x <- readRDS(f); if (is.data.frame(x)) as.data.table(x) else NULL }
    else fread(f, nrows = 50000)
  }, error = function(e) { say("  ★읽기 실패: %s", conditionMessage(e)); NULL })
  if (is.null(d)) next
  say("  %d행 x %d열", nrow(d), ncol(d))
  say("  컬럼: %s", paste(head(names(d), 22), collapse=", "))
  ## 날짜 후보 = 이름에 date/dt/ym 이 있거나, Date 클래스이거나, 8자리 숫자 문자열
  cls <- vapply(d, function(x) class(x)[1], "")
  dcand <- names(d)[grepl("date|dt|ym|month|period", names(d), ignore.case=TRUE) |
                    cls %in% c("Date","IDate","POSIXct")]
  say("  날짜 후보 컬럼: %s", if (length(dcand)) paste(dcand, collapse=", ") else "★없음")
  for (c0 in head(dcand, 4)) {
    v <- d[[c0]]
    say("    %-22s cls=%-8s 예시 %s", c0, class(v)[1],
        paste(head(as.character(v[!is.na(v)]), 3), collapse=" | "))
  }
  ## 종목 컬럼
  tcand <- names(d)[grepl("ticker|code|corp|stock|isin|symbol", names(d), ignore.case=TRUE)]
  say("  종목 후보: %s", if (length(tcand)) paste(head(tcand,5), collapse=", ") else "★없음")
  ## 신호값 후보 (수치형)
  num <- names(d)[vapply(d, is.numeric, TRUE)]
  say("  수치 컬럼 %d개: %s", length(num), paste(head(num, 10), collapse=", "))
}
say("=== n2 완료 ===")
