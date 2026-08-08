## \b 단어경계 실패 재현 시험 — 금칙⑦ 등재 자격 판단용. 1건 실측으로 규칙을 늘리지 않는다.
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[wb] ",fmt,"\n"),...))
say("R %s · TRE/PCRE 동작 시험", getRversion())
say("locale: %s", Sys.getlocale("LC_CTYPE"))

cases <- list(
  list(nm="순수 ASCII",              s="MarketCap / Revenue. Price relative.",          p="Revenue"),
  list(nm="한글 뒤",                 s="MarketCap / Revenue. 가격 대비 매출 비율이다.", p="Revenue"),
  list(nm="한글 앞",                 s="매출 대비 가격. MarketCap / Revenue.",           p="Revenue"),
  list(nm="한글 사이",               s="앞 Revenue 뒤",                                  p="Revenue"),
  list(nm="이모지 포함",             s="star Revenue check",                              p="Revenue"),
  list(nm="한글+숫자 혼합",          s="V08 = MarketCap/Revenue (2026년 실측)",          p="Revenue"),
  list(nm="다른 토큰(팩터코드)",     s="신호 = D03_EWMA 와 Q01_EB 조합",                 p="D03_EWMA"),
  list(nm="다른 토큰 ASCII only",    s="signal = D03_EWMA and Q01_EB combo",             p="D03_EWMA")
)
cases[[5]]$s <- paste0("\u2605 Revenue \u2713")   # 이모지/기호

say("%-22s | %-6s %-6s %-6s | 진단", "케이스", "fixed", "TRE", "perl")
for (c in cases) {
  f <- grepl(c$p, c$s, fixed=TRUE)
  t <- tryCatch(grepl(paste0("\b",c$p,"\b"), c$s), error=function(e) NA)
  p <- tryCatch(grepl(paste0("\b",c$p,"\b"), c$s, perl=TRUE), error=function(e) NA)
  diag <- if (isTRUE(f) && !isTRUE(t)) "★TRE 실패" else if (isTRUE(f) && !isTRUE(p)) "★perl 실패" else if (isTRUE(f)) "일치" else "부재"
  say("%-22s | %-6s %-6s %-6s | %s", c$nm, f, t, p, diag)
}
say("--- useBytes 우회 가능 여부 ---")
s <- "MarketCap / Revenue. 가격 대비 매출."
say("useBytes=TRUE  : %s", grepl("\bRevenue\b", s, useBytes=TRUE))
say("perl+useBytes  : %s", grepl("\bRevenue\b", s, perl=TRUE, useBytes=TRUE))
say("Encoding(s)    : %s · nchar %d · bytes %d", Encoding(s), nchar(s), nchar(s, type="bytes"))
