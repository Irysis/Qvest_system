## 인플레이션 나침반(도훈 아이디어) 사전 확인 — 착수 전 read-only
## 순서: ①in-flight/선행연구 ②데이터 가용 ③검정력 산술
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(jsonlite); library(data.table); library(arrow) })
say <- function(fmt,...) cat(sprintf(paste0("[IC0] ",fmt,"\n"),...))

## ── ① 선행연구 / in-flight (도훈 지시: 배분 전 확인) ─────────────────────────
say("=== ① 선행연구 · in-flight ===")
flat <- function(x) unlist(lapply(x, function(y) paste(unlist(y), collapse=" | ")))
hi <- tryCatch(flat(fromJSON("06_Registry/hypothesis_index.json", simplifyVector=FALSE)), error=function(e) character(0))
q  <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
qb <- sapply(q$entries, function(e) paste(unlist(e), collapse=" "))
kw <- c("인플레","inflation","breakeven","기대인플","CPI","섹터 로테이션","sector rotation","T5YIE")
for (k in kw) {
  say("  %-16s hypothesis_index %3d건 · queue %3d건", k,
      sum(sapply(hi, function(s) grepl(k, s, fixed=TRUE))),
      sum(sapply(qb, function(s) grepl(k, s, fixed=TRUE))))
}
say("  ★양성 대조(반드시 >0): 'PORT_t' queue %d건", sum(sapply(qb, function(s) grepl("PORT_t", s, fixed=TRUE))))

## ── ② 데이터 가용 ───────────────────────────────────────────────────────────
say("")
say("=== ② 데이터 가용 (실측) ===")
R <- as.data.table(read_parquet(".cache/rawdata.parquet"))
say("  rawdata: %s행 · Date 고유 %d(일간) · 기간 %s~%s",
    format(nrow(R),big.mark=","), uniqueN(R$Date), min(R$Date), max(R$Date))
say("  Sector 고유 %d · Sector_Lv2 고유 %d · 결측 %.1f%%",
    uniqueN(R$Sector), uniqueN(R$Sector_Lv2), 100*mean(is.na(R$Sector)))
R[, inuniv := (!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]
say("  유니버스 내 Sector 분포(상위 8):")
print(head(R[inuniv==TRUE & !is.na(Sector), .N, by=Sector][order(-N)], 8))

say("")
say("  --- 매크로 캐시 ---")
for (p in c(".cache/fred", ".cache/ecos", ".cache/macro", ".cache/regime")) {
  say("  %-18s exists=%s%s", p, dir.exists(p),
      if (dir.exists(p)) sprintf(" (%d files)", length(list.files(p))) else "")
}
ff <- list.files(".cache", pattern="fred|ecos|cpi|macro", ignore.case=TRUE, full.names=FALSE)
say("  .cache 내 매크로 관련 파일: %s", if (length(ff)) paste(head(ff,10),collapse=", ") else "(없음)")

## ── ③ 검정력 산술 — 4국면 분할이 가능한가 ──────────────────────────────────
say("")
say("=== ③ 4국면 분할의 검정력 (착수 전 필수) ===")
src <- "02_Infrastructure/contracts/required_effect_size.R"
if (file.exists(src)) {
  source(src)
  n_tot <- 280L
  say("  전표본 n=%d 가정", n_tot)
  r_full <- required_effect(n = n_tot, design = "full")
  say("  전표본 횡단면        : 필요 연 %.2f%%", r_full$required_annual*100)
  for (frac in c(0.40, 0.25, 0.10, 0.05)) {
    r <- required_effect(n = n_tot, design = "interaction", regime_frac = frac)
    say("  국면 비중 %4.0f%% (상호작용): 유효n %6.1f · 필요 연 %6.2f%%",
        frac*100, r$effective_n, r$required_annual*100)
  }
  say("  ★논문도 '진짜 스태그플레이션 표본이 적다'고 명시 — 희소 국면일수록 필요치가 폭증한다.")
} else say("  ★required_effect_size.R 부재")
