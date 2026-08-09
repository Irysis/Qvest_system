## s1 [정정] — 완성 전략 풀 인벤토리 + 중복 제거
## ★초판 결함: 월-다중 가드 `.N > 3` 가 **일간 NAV 를 전부 죽였다**(월 ~20관측 → NA).
##   38후보 중 3건만 추출됨. 일간은 **월말 NAV → 월수익**으로 변환해야 한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
say("=== 기준 === PG2 %d개월", nrow(inc))
cand <- unlist(lapply(c("04_Research/strategies", "06_Registry", "qepm/registry", ".cache",
                        "04_Research", "stage_artifacts"),
  function(r) if (dir.exists(r)) list.files(r, pattern="(period_returns|nav)\\w*\\.(csv|parquet|rds)$",
    recursive=TRUE, full.names=TRUE, ignore.case=TRUE) else character(0)))
cand <- unique(cand[file.size(cand) > 2000])
say("=== 후보 파일 %d개 ===", length(cand))

strat_of <- function(p) {
  parts <- strsplit(gsub("\\\\","/",p), "/")[[1]]
  i <- grep("^STR_|^FR_|^RAMP_|^WT[-_]", parts)
  if (length(i)) parts[i[1]] else basename(dirname(dirname(p)))
}
acc <- list(); nf <- c(read=0L, nodate=0L, noval=0L, short=0L, nooverlap=0L)
for (f in cand) {
  d <- tryCatch({ if (grepl("parquet$", f)) as.data.table(read_parquet(f))
    else if (grepl("rds$", f)) { x <- readRDS(f); if (is.data.frame(x)) as.data.table(x) else NULL }
    else fread(f) }, error=function(e) NULL)
  if (is.null(d) || !nrow(d)) { nf["read"] <- nf["read"]+1L; next }
  nm <- tolower(names(d))
  dc <- names(d)[which(nm %in% c("date","period"))[1]]
  if (is.na(dc)) { nf["nodate"] <- nf["nodate"]+1L; next }
  dv <- suppressWarnings(as.Date(as.character(d[[dc]])))
  if (all(is.na(dv))) { nf["nodate"] <- nf["nodate"]+1L; next }
  rc <- names(d)[which(nm %in% c("ret_net","ret","return","period_return"))[1]]
  nc <- names(d)[which(nm %in% c("nav","nav_value","value"))[1]]
  D <- data.table(date = dv)[, m := mi(date)]
  S <- NULL
  if (!is.na(rc)) {
    D[, v := suppressWarnings(as.numeric(d[[rc]]))]
    D <- D[is.finite(v)][order(date)]
    ## 월 관측이 1개면 그대로 월수익, 여러 개면 **일간 수익 → 월 복리**가 아니라
    ## ★계약 규율상 자체합성 금지이므로 **NAV 가 있을 때만** 월말 비율로 만든다.
    per <- D[, .N, by = m][, median(N)]
    if (is.finite(per) && per <= 1.5) S <- D[, .(r = v[.N]), by = m]
  }
  if (is.null(S) && !is.na(nc)) {
    D[, v := suppressWarnings(as.numeric(d[[nc]]))]
    D <- D[is.finite(v) & v > 0][order(date)]
    ME <- D[, .(nav = v[.N]), by = m][order(m)]          # ★월말 NAV
    if (nrow(ME) > 12) S <- data.table(m = ME$m[-1], r = ME$nav[-1]/head(ME$nav,-1) - 1)
  }
  if (is.null(S)) { nf["noval"] <- nf["noval"]+1L; next }
  S <- S[is.finite(r)]
  if (nrow(S) < 60) { nf["short"] <- nf["short"]+1L; next }
  ov <- length(intersect(S$m, inc$m))
  if (ov < 60L) { nf["nooverlap"] <- nf["nooverlap"]+1L; next }
  acc[[length(acc)+1L]] <- list(id = strat_of(f), file = f, n = nrow(S), ov = ov, S = S)
}
say("  추출 성공 **%d** · 실패 분해: %s", length(acc),
    paste(sprintf("%s=%d", names(nf), nf), collapse=" · "))
if (!length(acc)) { say("  ★0건 — 규칙 재설계 필요"); quit(status=0) }
IDX <- rbindlist(lapply(acc, function(x) data.table(id=x$id, file=x$file, n=x$n, ov=x$ov)))
say("  고유 전략 ID **%d** · 계열 %d", uniqueN(IDX$id), nrow(IDX))

say("=== ★중복 제거 (수익 계열 상관) ===")
SER <- lapply(acc, function(x) x$S)
common <- Reduce(intersect, lapply(SER, function(s) s$m))
say("  공통 월 %d개", length(common))
if (length(common) >= 60) {
  MAT <- do.call(cbind, lapply(SER, function(s) s[match(common, m), r]))
  colnames(MAT) <- make.unique(IDX$id)
  CM <- suppressWarnings(cor(MAT, use="pairwise.complete.obs"))
  dup <- which(abs(CM) > 0.999 & upper.tri(CM), arr.ind = TRUE)
  say("  |r|>0.999 쌍 **%d건**", nrow(dup))
  if (nrow(dup)) for (i in seq_len(min(nrow(dup), 8)))
    say("    %-28s ≡ %-28s r=%+.6f", rownames(CM)[dup[i,1]], colnames(CM)[dup[i,2]], CM[dup[i,1],dup[i,2]])
  keep <- integer(0)
  for (j in seq_len(ncol(CM))) {
    if (!length(keep)) { keep <- j; next }
    if (max(abs(CM[j, keep]), na.rm=TRUE) < 0.99) keep <- c(keep, j)
  }
  say("  ⇒ **유효 독립 %d / %d** (|r|<0.99 기준)", length(keep), ncol(CM))
  say("  독립 집합: %s", paste(substr(colnames(CM)[keep],1,26), collapse=", "))
  saveRDS(list(idx=IDX, ser=SER, keep=keep, names=colnames(CM)), file.path(OUT,"s1_inventory.rds"))
} else {
  say("  ★공통 월 부족 — 쌍별 비교로 전환 필요")
  saveRDS(list(idx=IDX, ser=SER), file.path(OUT,"s1_inventory.rds"))
}
say("=== s1 완료 ===")
