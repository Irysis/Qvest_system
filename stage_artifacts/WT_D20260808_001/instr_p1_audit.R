## INSTR-P1 — required_effect / verdict_with_power 호출부 감사
## 목적: sd_monthly 에 **arm 자신의 계열 sd** 를 넣은 곳이 WT-001 뿐인지, 계통인지.
## ★자동 분류하지 않는다 — 호출 줄을 그대로 출력해 사람이 판단한다
##   (2026-08-08 감사 도구가 같은 축에서 4회 오답한 직접 교훈).
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[p1] ",fmt,"\n"),...))

files <- list.files(".", pattern="\\.R$", recursive=TRUE, full.names=TRUE)
files <- files[!grepl("/\\.git/|/renv/", files)]
say("스캔 대상 .R 파일: %d", length(files))

## ★양성 대조: 계약 파일 자신은 반드시 잡혀야 한다
CONTRACT <- "./02_Infrastructure/contracts/required_effect_size.R"
say("양성 대조 파일 존재: %s", file.exists(CONTRACT))

hits <- list()
for (f in files) {
  ln <- tryCatch(readLines(f, warn=FALSE), error=function(e) character(0))
  if (!length(ln)) next
  idx <- which(grepl("required_effect(", ln, fixed=TRUE) |
               grepl("verdict_with_power(", ln, fixed=TRUE))
  ## 주석 줄 제외 (호출이 아니라 서술)
  idx <- idx[!grepl("^\\s*#", ln[idx])]
  if (length(idx)) hits[[f]] <- data.frame(line=idx, text=trimws(ln[idx]), stringsAsFactors=FALSE)
}
say("호출 포함 파일: %d", length(hits))
if (!file.exists(CONTRACT) || is.null(hits[[CONTRACT]]))
  say("★★양성 대조 실패 — 계약 파일이 안 잡혔다. 스캐너를 믿지 말 것.")

say("=== 호출 줄 전량 (정의부/테스트 제외 표기) ===")
for (f in names(hits)) {
  tag <- if (grepl("contracts/required_effect_size\\.R$", f)) "[정의]"
         else if (grepl("^\\./08_Tests/", f)) "[테스트]"
         else "[호출]"
  for (i in seq_len(nrow(hits[[f]]))) {
    txt <- hits[[f]]$text[i]
    ## sd_monthly 를 명시 전달했는지 여부만 기계 표기 (판단은 사람이)
    sd_flag <- if (grepl("sd_monthly", txt, fixed=TRUE)) "sd명시" else "      "
    say("%-8s %-6s %-58s :%-4d %s", tag, sd_flag,
        substr(sub("^\\./","",f), 1, 58), hits[[f]]$line[i], substr(txt, 1, 150))
  }
}
