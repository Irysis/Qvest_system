## 50_tg_send.R — K200 위험 예측 정확도 연구 보고 1통(tg_agent_brief 단일 진입 · SKILL qvest-telegram §0)
## 본문 = output/report_message.json(41_report_message.py 가 산출 수치로 만든다 · 손으로 수치를 쓰지 않는다)
## 실행(프로젝트 루트에서): Rscript --no-save 04_Research/01_reports/k200_risk_accuracy_20261113/scripts/50_tg_send.R        (미리보기)
##                        Rscript --no-save 04_Research/01_reports/k200_risk_accuracy_20261113/scripts/50_tg_send.R send   (발송)
source("02_Infrastructure/ops/morning_steps/_root.R")
suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R"))
suppressMessages(library(jsonlite))
A <- commandArgs(trailingOnly = TRUE)
SEND <- "send" %in% A
if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
D <- "04_Research/01_reports/k200_risk_accuracy_20261113"
M <- fromJSON(file.path(D, "output/report_message.json"), simplifyVector = FALSE)
secs <- lapply(M$sections, function(s) {
  if (identical(s$type, "bullet")) s$items <- unlist(s$items)
  s
})
charts <- unlist(M$charts)
charts <- stats::setNames(file.path(D, unname(charts)), names(charts))
stopifnot(all(file.exists(charts)))
r <- tg_agent_brief(agent = "Q-Lead", title = M$title, sections = secs, footer = M$footer, charts = charts,
                    relaxed = TRUE, glossary = FALSE, decode_jargon = FALSE, force = TRUE, mute = !isTRUE(M$push))
cat("[tg] ok =", isTRUE(r$ok %||% TRUE), " send =", SEND, "\n")
