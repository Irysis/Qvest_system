## WT-D20260809_004 (FQ-173) — A0 원천 데이터 실측 (read-only)
## 규약: 입력 형태를 가정하지 않는다 — 첫 출력은 행수·관측단위·범위 실측
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
say <- function(fmt, ...) cat(sprintf(paste0("[A0] ", fmt, "\n"), ...))

## ── 1. rawdata 실측 ──────────────────────────────────────────────────────────
say("=== 1. rawdata ===")
rp <- ".cache/rawdata.parquet"
say("exists=%s size=%.1fMB", file.exists(rp), file.size(rp)/1e6)
R <- as.data.table(read_parquet(rp))
say("행 %s · 컬럼 %d", format(nrow(R), big.mark=","), ncol(R))
say("컬럼 전수: %s", paste(names(R), collapse=", "))
say("Date class=%s · 고유 %d · 범위 %s ~ %s", class(R$Date)[1], uniqueN(R$Date),
    as.character(min(R$Date)), as.character(max(R$Date)))
say("Ticker 고유 %d", uniqueN(R$Ticker))
## 관측 단위 판정: 연속 Date 간격
dd <- diff(sort(unique(R$Date)))
say("Date 간격 중앙값 %.1f일 → 관측단위 = %s", median(as.numeric(dd)),
    if (median(as.numeric(dd)) <= 3) "일간" else "월간+")

## ── 2. FRED ──────────────────────────────────────────────────────────────────
say("")
say("=== 2. FRED ===")
fp <- ".cache/fred_macro.parquet"
say("exists=%s", file.exists(fp))
if (file.exists(fp)) {
  FR <- as.data.table(read_parquet(fp))
  say("행 %s · 컬럼 %s", format(nrow(FR), big.mark=","), paste(names(FR), collapse=","))
  print(utils::head(FR, 3))
  sc <- intersect(c("series","series_id","id","name","variable"), names(FR))[1]
  if (!is.na(sc)) {
    tb <- FR[, .(N=.N, from=min(get(intersect(c("Date","date"), names(FR))[1])),
                 to=max(get(intersect(c("Date","date"), names(FR))[1]))), by=c(sc)]
    print(tb[order(-N)])
  }
}
say(".cache FRED 관련 파일: %s",
    paste(list.files(".cache", pattern="fred", ignore.case=TRUE), collapse=", "))

## ── 3. ECOS / KR CPI ─────────────────────────────────────────────────────────
say("")
say("=== 3. ECOS ===")
ec <- list.files(".cache", pattern="ecos|cpi|CPI", ignore.case=TRUE, full.names=TRUE)
say("파일: %s", paste(basename(ec), collapse=", "))
for (p in ec) {
  E <- tryCatch(as.data.table(read_parquet(p)), error=function(e) NULL)
  if (is.null(E)) { say("  %s : read 실패", basename(p)); next }
  say("  %s : %d행 · 컬럼 %s", basename(p), nrow(E), paste(names(E), collapse=","))
  print(utils::head(E, 2))
}

## ── 4. factor registry — 이익성장 후보 3종 ───────────────────────────────────
say("")
say("=== 4. factor registry (C01_SUE / C02_EPS_Chg_1m / M26_Revenue_Mom) ===")
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
say("registry 총 %d건", length(reg))
for (k in c("C01_SUE","C02_EPS_Chg_1m","M26_Revenue_Mom")) {
  if (!is.null(reg[[k]])) {
    e <- reg[[k]]
    say("  %s : %s", k, paste(sprintf("%s=%s", names(e), sapply(e, function(v) paste(unlist(v), collapse="/"))), collapse=" · "))
  } else say("  %s : registry 부재", k)
}
## 공식 중복 검색 (C14=M26 선례)
say("")
say("--- 중복 검색: formula/description 문자열 유사 ---")
blob <- sapply(reg, function(g) paste(unlist(g), collapse=" | "))
for (k in c("C01_SUE","C02_EPS_Chg_1m","M26_Revenue_Mom")) {
  if (is.null(reg[[k]])) next
  f <- reg[[k]]$formula
  if (is.null(f)) { say("  %s formula 없음", k); next }
  hits <- names(which(sapply(blob, function(b) grepl(f, b, fixed=TRUE))))
  say("  %s formula='%s' → 동일 formula 보유 팩터: %s", k, f, paste(hits, collapse=", "))
}
