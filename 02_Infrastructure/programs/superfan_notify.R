## superfan_notify.R — 구성요소 Superfan 감시기의 텔레그램 발신(도훈 2026-10-16 '평소엔 조용히 모니터링하다 문제가 생기면 알려 줌' ·
##   무인 감시 ① 1시간 결정론 감시 + ③ 감시기 직접 알림 승인 — '1번은 내가 조치할 테니 나머지 2,3,4 실행')
##   입력 = superfan_watch.py 가 쓴 payload JSON(구성요소별 새 '실패' 이상 · mute = 23~07시 무음) · 구성요소마다 1통(정본 발송기 tg_agent_brief).
##   출력 = 'SFN<TAB>구성요소<TAB>ok|fail' 줄 — 감시기는 ok 인 구성요소만 '알림 완료'로 표식한다(실패면 다음 시간에 다시).
##   LLM 을 부르지 않는다(비용 0). 진단 · 수리는 Q 가 세션에서(전담 Superfan) — 알림은 '무엇이 · 언제 · 몇 번'만.
## 실행: Rscript superfan_notify.R <payload.json>      (QVEST_TG_DRY_RUN=1 이면 발송 없이 본문만)
suppressPackageStartupMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
a <- commandArgs(trailingOnly = TRUE)
if (!length(a) || !file.exists(a[1])) { cat("SFN\t-\tfail\n"); quit(status = 1L) }
P <- fromJSON(a[1], simplifyVector = FALSE)
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))))
hm <- function(s) if (is.null(s) || !nzchar(s)) "?" else sub("^\\d{4}-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}).*$", "\\1-\\2 \\3:\\4", s)
for (g in P$groups) {
  nm <- trimws(sub("\\(.*$", "", g$name %||% g$component))
  items <- vapply(g$anomalies, function(x) sprintf("%s — %d회 · 처음 %s · 마지막 %s%s", substr(gsub("\\s+", " ", x$text %||% ""), 1, 180), as.integer(x$count %||% 1L),
                                                   hm(x$first_seen), hm(x$last_seen), if (isTRUE(as.integer(x$reopened %||% 0L) > 0L)) " · 재발" else ""), character(1))
  keys <- paste(vapply(g$anomalies, function(x) as.character(x$key %||% ""), character(1)), collapse = ",")
  ## ★정본 발송기의 bullet 은 항목 ≥ 2(BULLET_MIN) — 이상 1건짜리 알림은 bullet 이면 거부돼 가동(10-16) 뒤 한 통도 나가지 않았다
  ##   (판단 Superfan T1 C-20261017-036 · 건식 재현). 1건이면 text 절(relaxed 라 길이 상한 면제 · 최소 30자는 항목 문구가 넘는다).
  what <- if (length(items) >= 2L) list(heading = "무엇이", type = "bullet", items = items) else list(heading = "무엇이", type = "text", body = items[1])
  r <- tryCatch(tg_agent_brief(agent = "Monitoring", title = sprintf("[Superfan·%s] 실패 이상 %d건", nm, length(items)),
                               sections = list(what,
                                               list(heading = "다음", type = "text",
                                                    body = "Q 가 세션에서 이 구성요소의 전담 Superfan 으로 원인을 진단하고 고칩니다. 도훈님 조치가 필요하면 진단 뒤 따로 알립니다.")),
                               footer = "결정론 감시기(1시간 · LLM 비용 0) — 같은 이상은 다시 보내지 않고, 재발하면 1통 더 보냅니다",
                               mute = isTRUE(P$mute), relaxed = TRUE, force = TRUE, decode_jargon = FALSE, glossary = FALSE,
                               lock_scope = sprintf("superfan_%s_%s", g$component, substr(as.character(openssl::md5(keys)), 1L, 10L))),
                error = function(e) list(ok = FALSE, err = conditionMessage(e)))
  if (!isTRUE(r$ok) && !is.null(r$err)) message("[superfan_notify] ", g$component, " 발신 오류: ", r$err)
  cat(sprintf("SFN\t%s\t%s\n", g$component, if (isTRUE(r$ok)) "ok" else "fail"))
}
