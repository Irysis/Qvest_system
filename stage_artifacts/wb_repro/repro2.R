## \b 재현 시험 v2 — v1 은 Bash heredoc 경유로 백슬래시가 한 겹 소비돼
## R 이 정규식 \b 가 아니라 백스페이스(0x08)를 받았다. 본 파일은 Write 도구로 직접 작성해 그 오염을 제거한다.
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[wb2] ",fmt,"\n"),...))
say("R %s · locale %s", getRversion(), Sys.getlocale("LC_CTYPE"))

## ★먼저 패턴 자체를 실측 인쇄한다 (오늘 규약: 입력을 가정하지 말고 본 것을 찍는다)
pat <- "\\bRevenue\\b"
say("패턴 문자수 %d · 바이트 %d · charToRaw: %s",
    nchar(pat), nchar(pat, type="bytes"),
    paste(as.character(charToRaw(pat)), collapse=" "))
say("  (정상이면 첫 바이트가 5c = 백슬래시. 08 이면 백스페이스 = 오염)")

cases <- list(
  list(nm="순수 ASCII",    s="MarketCap / Revenue. Price relative."),
  list(nm="한글 뒤",       s="MarketCap / Revenue. 가격 대비 매출 비율이다."),
  list(nm="한글 앞",       s="매출 대비 가격. MarketCap / Revenue."),
  list(nm="한글 사이",     s="앞 Revenue 뒤"),
  list(nm="기호 포함",     s="\u2605 Revenue \u2713"),
  list(nm="경계 없음(붙음)", s="XRevenueY"),
  list(nm="부재",          s="MarketCap only")
)
say("%-18s | %-6s %-6s %-6s", "케이스", "fixed", "TRE", "perl")
for (cc in cases) {
  f <- grepl("Revenue", cc$s, fixed=TRUE)
  t <- grepl(pat, cc$s)
  p <- grepl(pat, cc$s, perl=TRUE)
  say("%-18s | %-6s %-6s %-6s", cc$nm, f, t, p)
}
say("--- 판정 ---")
say("정상 기대: '경계 없음(붙음)' 만 fixed=TRUE 이면서 TRE/perl=FALSE.")
say("           나머지 매칭 케이스는 셋 다 TRUE 여야 한다.")
