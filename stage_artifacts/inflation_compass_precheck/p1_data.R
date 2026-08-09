## 인플레 신호 원천 실측 — 무엇이 이미 있고 무엇을 새로 받아야 하는가
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(arrow) })
say <- function(fmt,...) cat(sprintf(paste0("[IC1] ",fmt,"\n"),...))

f <- ".cache/fred_macro.parquet"
say("=== FRED 캐시 ===")
say("존재 %s · %.1f MB", file.exists(f), if (file.exists(f)) file.size(f)/1e6 else 0)
if (file.exists(f)) {
  F <- as.data.table(read_parquet(f))
  say("행 %s · 컬럼 %d", format(nrow(F),big.mark=","), ncol(F))
  say("컬럼 전수: %s", paste(names(F), collapse=", "))
  dc <- intersect(c("Date","date"), names(F))[1]
  if (!is.na(dc)) say("기간 %s ~ %s (고유 %d)", min(F[[dc]]), max(F[[dc]]), uniqueN(F[[dc]]))
  ## long 포맷이면 series 목록
  sc <- intersect(c("series","series_id","id","name","variable"), names(F))[1]
  if (!is.na(sc)) {
    say("--- series 목록 ---")
    print(F[, .N, by=c(sc)][order(-N)])
  }
}

say("")
say("=== ECOS 캐시 ===")
for (p in c(".cache/ecos_bond_rates.parquet", ".cache/ecos_krw_usd.parquet")) {
  if (!file.exists(p)) { say("%s 부재", p); next }
  E <- as.data.table(read_parquet(p))
  say("%s : %s행 · 컬럼 %s", basename(p), format(nrow(E),big.mark=","), paste(names(E), collapse=","))
  sc <- intersect(c("series","item","code","name","ITEM_NAME1"), names(E))[1]
  if (!is.na(sc)) say("   항목: %s", paste(head(unique(E[[sc]]), 12), collapse=" | "))
}

say("")
say("=== 이익성장 계열 팩터 (registry) ===")
suppressPackageStartupMessages(library(jsonlite))
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
blob <- sapply(reg, function(g) paste(unlist(g), collapse=" | "))
kw <- c("growth","Growth","이익성장","EPS","Revenue","OperatingProfit")
hit <- names(which(sapply(blob, function(b) any(sapply(kw, function(k) grepl(k, b, fixed=TRUE))))))
say("성장/이익 관련 팩터 %d건 (전체 %d)", length(hit), length(reg))
cats <- sapply(hit, function(k) { v <- reg[[k]]$category; if (is.null(v)) "?" else v })
print(sort(table(cats), decreasing=TRUE))
say("예시: %s", paste(head(hit, 14), collapse=", "))
