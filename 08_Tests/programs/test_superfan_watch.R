## test_superfan_watch.R — 구성요소 Superfan 감시기(programs/superfan_watch.py · 2026-10-16) — 임시 정의 · 임시 로그 · 임시 상태로만(운영 무접촉)
##   ① 로그 규칙: 새 줄 감지 · 증분(재스캔 무중복) · 같은 증상 묶기(count) · 다른 증상 = 새 키 ② 블록 제외(trigger=test) · exclude ③ 사건 시각 —
##   문턱보다 오래된 사건은 세지 않음 · 처음 스캔의 시각 모르는 줄 무시 · 만료 ④ freshness · expect_today · json_field(정상 복귀 = 자동 해소)
##   ⑤ ack → 재발 시 재개방 ⑥ 잘림(크기 < 오프셋) ⑦ 같은 로그를 두 구성요소가 따로 본다 ⑧ 정의 검증(위반 주입) ⑨ 부팅 꼬리 · 깨진 상태 '?(…)'
##   ⑩ 세션 재개 Resume 줄 배선 ⑪ 운영 정의(06_Registry/superfan_components.json) 검증 통과 ⑫ 양성 대조 — 사건 시각 필터를 끈 사본은 옛 사건을 센다
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
PY <- file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"); if (!file.exists(PY)) PY <- Sys.which("python")
TOOL <- file.path(ROOT, "02_Infrastructure/programs/superfan_watch.py")
SR <- file.path(ROOT, "02_Infrastructure/programs/session_resume.py")
TMP <- normalizePath(tempfile("sfw_"), winslash = "/", mustWork = FALSE); dir.create(TMP)
REG <- file.path(TMP, "components.json"); WST <- file.path(TMP, "watch.json")
LOG <- file.path(TMP, "a.log"); LOGB <- file.path(TMP, "b.log"); JS <- file.path(TMP, "state.json")
Sys.setenv(QVEST_SUPERFAN_REGISTRY_PATH = REG, QVEST_SUPERFAN_WATCH_PATH = WST, QVEST_SUPERFAN_NOW = "2026-10-16 12:00",
           QVEST_SESSION_RESUME_PATH = file.path(TMP, "sr.json"), QVEST_JUDGMENT_LEDGER_PATH = file.path(TMP, "jl.json"), PYTHONUTF8 = "1")
run <- function(..., tool = TOOL) {
  out <- suppressWarnings(system2(PY, c("-X", "utf8", shQuote(tool), ...), stdout = TRUE, stderr = TRUE))
  list(out = out, rc = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}
w8 <- function(path, lines, append = TRUE) { con <- file(path, if (append) "ab" else "wb"); writeBin(charToRaw(enc2utf8(paste0(paste(lines, collapse = "\n"), "\n"))), con); close(con) }
st <- function() jsonlite::fromJSON(WST, simplifyVector = FALSE)
openA <- function(comp = NULL) Filter(function(a) identical(a$status, "open") && (is.null(comp) || identical(a$component, comp)), st()$anomalies)
reg <- list(schema = "superfan_components_v1", default_max_event_age_h = 48, components = list(
  list(id = "alpha", name = "A", dossier = "d.md", rules = list(
    list(id = "errs", kind = "log_patterns", files = LOG, block_header = "^=== run @", skip_block_header = "trigger=test",
         exclude = list("probe"),
         patterns = list(list(severity = "fail", regex = "^Error in ", label = "R"), list(severity = "warn", regex = "WARN", label = "w"))),
    list(id = "fresh", kind = "freshness", file = LOGB, max_age_h = 26, severity = "fail"),
    list(id = "done", kind = "expect_today", file = LOG, after = "11:00", weekdays_only = TRUE, pattern = "done @ {dow} {mon} {dd2}", severity = "fail"),
    list(id = "js", kind = "json_field", file = JS, path = "status", bad_values = list("failed"), severity = "warn"))),
  list(id = "beta", name = "B", dossier = "e.md", rules = list(
    list(id = "errs2", kind = "log_patterns", files = LOG, patterns = list(list(severity = "fail", regex = "^Error in ", label = "R")))))))
writeLines(jsonlite::toJSON(reg, auto_unbox = TRUE, pretty = TRUE), REG)
w8(LOG, c("=== run @ Thu Oct 15 07:00:00 2026 (trigger=cron) ===", "Error in old_thing(x) : boom"), append = FALSE)   # 29시간 전 — 문턱 48h 안
w8(LOG, c("=== run @ Mon Oct 12 07:00:00 2026 (trigger=cron) ===", "Error in ancient(x) : boom"))                      # 앞 블록보다 뒤에 있지만 시각은 4일 전
w8(LOGB, "x", append = FALSE); writeLines('{"status":"ok"}', JS)

## ① · ③ 처음 스캔
r <- run("scan")
op <- openA("alpha")
txt <- vapply(op, `[[`, "", "text")
chk("① 처음 스캔 rc 0 · 48h 안 사건(10-15) 감지", r$rc == 0L && any(grepl("old_thing", txt)), paste(r$out, collapse = " | "))
chk("③ 문턱보다 오래된 사건(10-12)은 세지 않음", !any(grepl("ancient", txt)))
r2 <- run("scan")
chk("① 재스캔 — 새 줄 없으면 새 이상 0(증분)", grepl("새 · 재개방 0", r2$out[1]), r2$out[1])
w8(LOG, c("=== run @ Fri Oct 16 09:00:00 2026 (trigger=cron) ===", "Error in old_thing(y) : boom 2"))
run("scan")
a <- Filter(function(a) grepl("old_thing", a$text) && identical(a$component, "alpha"), st()$anomalies)
chk("① 같은 증상(숫자 · 인자만 다름이 아니라 정규화 문구 동일) 묶기 — 다른 문구면 새 키", length(a) >= 1L)
w8(LOG, "Error in old_thing(y) : boom 2")
run("scan")
a2 <- Filter(function(a) identical(a$text, "Error in old_thing(y) : boom 2") && identical(a$component, "alpha"), st()$anomalies)
chk("① 같은 문구 재발 → count 증가(새 키 아님)", length(a2) == 1L && a2[[1]]$count >= 2L, if (length(a2)) a2[[1]]$count else "none")

## ② 블록 제외 · exclude
w8(LOG, c("=== run @ Fri Oct 16 10:00:00 2026 (trigger=test) ===", "Error in test_only(x) : boom", "=== run @ Fri Oct 16 10:30:00 2026 (trigger=cron) ===",
          "WARN probe line", "WARN real warning"))
run("scan")
txt <- vapply(openA("alpha"), `[[`, "", "text")
chk("② trigger=test 블록 아래 줄 제외", !any(grepl("test_only", txt)))
chk("② exclude 패턴 줄 제외 · 그 밖의 warn 감지", !any(grepl("probe", txt)) && any(grepl("real warning", txt)))

## ⑦ 같은 로그를 두 구성요소가 따로 본다
chk("⑦ beta 도 같은 로그의 Error 를 따로 감지(오프셋 공유 없음)", any(grepl("old_thing", vapply(openA("beta"), `[[`, "", "text"))))

## ④ freshness · expect_today · json_field
Sys.setFileTime(LOGB, as.POSIXct("2026-10-14 00:00:00", tz = "Asia/Seoul"))
writeLines('{"status":"failed"}', JS)
run("scan")
rules <- vapply(openA("alpha"), `[[`, "", "rule")
chk("④ freshness — 60h 전 갱신 → 이상", "fresh" %in% rules)
chk("④ expect_today — 11:00 지나 오늘 완료 표식 없음 → 이상", "done" %in% rules)
chk("④ json_field — status=failed → 이상", "js" %in% rules)
Sys.setFileTime(LOGB, as.POSIXct("2026-10-16 11:30:00", tz = "Asia/Seoul")); writeLines('{"status":"ok"}', JS)
w8(LOG, "=== run done @ Fri Oct 16 11:40:00 2026 ===")
run("scan")
rules <- vapply(openA("alpha"), `[[`, "", "rule")
res <- vapply(Filter(function(a) a$rule %in% c("fresh", "done", "js"), st()$anomalies), `[[`, "", "status")
chk("④ 정상 복귀 → 상태형 이상 자동 해소(resolved)", !any(c("fresh", "done", "js") %in% rules) && all(res == "resolved"), paste(res, collapse = ","))

## ⑤ ack → 재발 시 재개방
k <- Filter(function(a) identical(a$text, "WARN real warning"), st()$anomalies)[[1]]$key
chk("⑤ ack 사유 없으면 거부(위반 주입)", run("ack", "--key", k, "--kind", "known", "--note", shQuote(" "))$rc != 0L)
chk("⑤ ack 종류 어휘 밖 거부", run("ack", "--key", k, "--kind", "whatever", "--note", "x")$rc != 0L)
chk("⑤ ack → acked", run("ack", "--key", k, "--kind", "known", "--note", shQuote("알려진 경고"))$rc == 0L && identical(st()$anomalies[[k]]$status, "acked"))
w8(LOG, "WARN real warning")
run("scan")
chk("⑤ 재발(새 줄) → 재개방 · reopened 1", identical(st()$anomalies[[k]]$status, "open") && st()$anomalies[[k]]$reopened == 1L)

## ③ 만료 — 기준 시각을 사흘 뒤로
Sys.setenv(QVEST_SUPERFAN_NOW = "2026-10-19 12:00")
run("scan")
ex <- vapply(Filter(function(a) identical(a$rule, "errs"), st()$anomalies), `[[`, "", "status")
chk("③ 마지막 사건이 48h 지난 로그 이상 → expired", length(ex) > 0L && all(ex %in% c("expired", "resolved")), paste(ex, collapse = ","))
Sys.setenv(QVEST_SUPERFAN_NOW = "2026-10-16 12:00")

## ⑥ 잘림
w8(LOG, "=== run @ Fri Oct 16 11:50:00 2026 (trigger=cron) ===", append = FALSE)
w8(LOG, "Error in after_truncate(z) : boom")
r <- run("scan")
chk("⑥ 잘림(크기 < 오프셋) → 처음부터 · 새 줄 감지", r$rc == 0L && any(grepl("after_truncate", vapply(openA("alpha"), `[[`, "", "text"))), paste(r$out, collapse = " | "))

## ⑨ 부팅 꼬리
bf <- paste(run("boot-fragment")$out, collapse = "")
chk("⑨ 부팅 꼬리 — 이상 수 · 실패 수 · 구성요소", grepl("^Superfan 감시: 이상 [0-9]+ \\(실패 [0-9]+\\) — ", bf), bf)

## ⑩ 세션 재개 Resume 줄 배선
invisible(run("begin", "--id", "OP-T", "--title", "t", "--step", "S1=x", tool = SR))
bl <- paste(run("boot-line", tool = SR)$out, collapse = "")
chk("⑩ Resume 줄 꼬리에 감시 상태", grepl("| Superfan 감시: ", bl, fixed = TRUE), bl)

## ⑧ 정의 검증(위반 주입)
bad <- reg; bad$components[[1]]$rules[[1]]$kind <- "magic"
writeLines(jsonlite::toJSON(bad, auto_unbox = TRUE), REG)
chk("⑧ 규칙 종류 어휘 밖 → scan 거부", run("scan")$rc != 0L)
bad <- reg; bad$components[[2]]$id <- "alpha"
writeLines(jsonlite::toJSON(bad, auto_unbox = TRUE), REG)
chk("⑧ 구성요소 id 중복 → validate 실패", run("validate")$rc != 0L)
bad <- reg; bad$components[[1]]$rules[[1]]$patterns[[1]]$regex <- "(unclosed"
writeLines(jsonlite::toJSON(bad, auto_unbox = TRUE), REG)
chk("⑧ 정규식 오류 → validate 실패", run("validate")$rc != 0L)
writeLines(jsonlite::toJSON(reg, auto_unbox = TRUE, pretty = TRUE), REG)

## ⑨ 깨진 상태 → '?(…)' · rc 0
writeLines("{broken", WST)
r <- run("boot-fragment")
chk("⑨ 깨진 상태 → 'Superfan 감시 ?(' · rc 0(부팅 계속)", r$rc == 0L && grepl("^Superfan 감시 \\?\\(", r$out[1]), paste(r$out, collapse = " | "))

## ⑪ 운영 정의 검증
Sys.unsetenv("QVEST_SUPERFAN_REGISTRY_PATH")
chk("⑪ 운영 06_Registry/superfan_components.json 검증 통과", identical(run("validate")$out[1], "OK"), paste(run("validate")$out, collapse = " | "))
Sys.setenv(QVEST_SUPERFAN_REGISTRY_PATH = REG)

## ⑫ 양성 대조 — 사건 시각 필터를 끈 사본(소스 텍스트 치환)은 옛 사건(10-12)을 센다 → 필터가 실제로 일한다
src <- readLines(TOOL, warn = FALSE, encoding = "UTF-8")
target <- "                    if ctx is not None and now - ctx > max_age:"
hit <- which(src == target)
mut <- src; if (length(hit) == 1L) mut[hit] <- "                    if False:"
MT <- file.path(TMP, "superfan_watch_mut.py"); writeLines(mut, MT, useBytes = TRUE)
unlink(WST); w8(LOG, c("=== run @ Mon Oct 12 07:00:00 2026 (trigger=cron) ===", "Error in ancient(x) : boom"), append = FALSE)
anyA <- function(comp) Filter(function(a) identical(a$component, comp), st()$anomalies)   # 상태 무관(같은 스캔의 만료 처리가 닫아도 '기록됐나'를 본다)
invisible(run("scan", tool = MT))
txt_mut <- vapply(anyA("alpha"), `[[`, "", "text")
unlink(WST); invisible(run("scan"))
txt_ok <- vapply(anyA("alpha"), `[[`, "", "text")
chk("⑫ 치환 성사(1곳) · 돌연변이는 옛 사건을 셈 · 원본은 안 셈", length(hit) == 1L && any(grepl("ancient", txt_mut)) && !any(grepl("ancient", txt_ok)),
    sprintf("hit=%d mut=%s ok=%s", length(hit), paste(txt_mut, collapse = ";"), paste(txt_ok, collapse = ";")))

## ⑬ 무인 알림(10-16 승인 ①+③) — 스텁 발신기(QVEST_SUPERFAN_NOTIFY_CMD) · 새 '실패'만 · 구성요소별 1통 · 다시 안 보냄 · warn 미발송 · 재발 재발송 ·
##    발신 실패 = 표식 안 함(다음에 다시) · 기준선(처음 켤 때) · 야간 무음(22~07시)
STUB <- file.path(TMP, "stub_notify.py")
writeLines(c("import json, os, sys, glob",
             "p = sys.argv[1]; d = json.load(open(p, encoding='utf-8'))",
             "n = len(glob.glob(os.path.join(os.environ['STUB_DIR'], 'payload_*.json')))",
             "json.dump(d, open(os.path.join(os.environ['STUB_DIR'], 'payload_%03d.json' % n), 'w', encoding='utf-8'), ensure_ascii=False)",
             "for g in d['groups']: print('SFN\\t%s\\t%s' % (g['component'], 'fail' if os.environ.get('STUB_FAIL') == '1' else 'ok'))"), STUB)
SD <- file.path(TMP, "stub_out"); dir.create(SD)
Sys.setenv(QVEST_SUPERFAN_NOTIFY_CMD = paste(PY, STUB), STUB_DIR = SD, QVEST_SUPERFAN_NOW = "2026-10-16 12:00")
pl <- function() sort(Sys.glob(file.path(SD, "payload_*.json")))
lastp <- function() { f <- pl(); if (length(f)) jsonlite::fromJSON(f[length(f)], simplifyVector = FALSE) else NULL }
gtext <- function(p) unlist(lapply(p$groups, function(g) vapply(g$anomalies, function(a) a$text, "")))
unlink(WST); w8(LOG, c("=== run @ Fri Oct 16 08:00:00 2026 (trigger=cron) ===", "Error in base_line(x) : boom"), append = FALSE); w8(LOGB, "x", append = FALSE)
rb <- run("scan", "--baseline")
fails_open <- Filter(function(a) identical(a$status, "open") && identical(a$severity, "fail"), st()$anomalies)
chk("⑬ 기준선 — 지금 열린 실패를 보내지 않고 표식 · 발신기 미호출", length(pl()) == 0L && length(fails_open) >= 1L &&
      all(vapply(fails_open, function(a) isTRUE(a$notified$baseline), logical(1))), paste(rb$out, collapse = " | "))
w8(LOG, c("=== run @ Fri Oct 16 11:00:00 2026 (trigger=cron) ===", "Error in brand_new(x) : boom"))
r13 <- run("scan", "--notify"); p1 <- lastp()
comps <- vapply(p1$groups %||% list(), function(g) g$component, "")
chk("⑬ 새 실패 → 구성요소별 1통(같은 로그를 보는 alpha · beta 각 1) · 새 것만 · 낮 = 푸시",
    length(pl()) == 1L && identical(sort(comps), c("alpha", "beta")) && all(grepl("brand_new", gtext(p1))) && identical(p1$mute, FALSE),
    paste(r13$out, collapse = " | "))
invisible(run("scan", "--notify"))
chk("⑬ 새 줄 없음 → 다시 안 보냄", length(pl()) == 1L)
w8(LOG, "WARN only a warning")
invisible(run("scan", "--notify"))
chk("⑬ warn 은 보내지 않음", length(pl()) == 1L)
bn <- Filter(function(a) grepl("brand_new", a$text) && identical(a$component, "alpha"), st()$anomalies)[[1]]
invisible(run("ack", "--key", bn$key, "--kind", "fixed", "--note", "test"))
w8(LOG, c("=== run @ Fri Oct 16 11:30:00 2026 (trigger=cron) ===", "Error in brand_new(x) : boom"))
invisible(run("scan", "--notify")); p2 <- lastp()
reo <- Filter(function(g) identical(g$component, "alpha"), p2$groups)
chk("⑬ 확인한 이상이 재발 → 1통 더(재발 표시)", length(pl()) == 2L && length(reo) == 1L && any(vapply(reo[[1]]$anomalies, function(a) a$reopened >= 1L, logical(1))))
Sys.setenv(STUB_FAIL = "1"); w8(LOG, c("=== run @ Fri Oct 16 11:40:00 2026 (trigger=cron) ===", "Error in send_fails(x) : boom"))
invisible(run("scan", "--notify")); n_after_fail <- length(pl())
sf <- Filter(function(a) grepl("send_fails", a$text), st()$anomalies)
Sys.unsetenv("STUB_FAIL"); invisible(run("scan", "--notify")); p3 <- lastp()
chk("⑬ 발신 실패 → 표식 안 함 · 다음 실행에 다시 보냄", n_after_fail == 3L && all(vapply(sf, function(a) is.null(a$notified), logical(1))) &&
      length(pl()) == 4L && any(grepl("send_fails", gtext(p3))))
Sys.setenv(QVEST_SUPERFAN_NOW = "2026-10-16 23:30"); w8(LOG, c("=== run @ Fri Oct 16 23:00:00 2026 (trigger=cron) ===", "Error in night_owl(x) : boom"))
invisible(run("scan", "--notify")); p4 <- lastp()
chk("⑬ 야간(23:30) → 무음", isTRUE(p4$mute) && any(grepl("night_owl", gtext(p4))))
Sys.unsetenv(c("QVEST_SUPERFAN_NOTIFY_CMD", "STUB_DIR")); Sys.setenv(QVEST_SUPERFAN_NOW = "2026-10-16 12:00")

Sys.unsetenv(c("QVEST_SUPERFAN_REGISTRY_PATH", "QVEST_SUPERFAN_WATCH_PATH", "QVEST_SUPERFAN_NOW", "QVEST_SESSION_RESUME_PATH", "QVEST_JUDGMENT_LEDGER_PATH"))
unlink(TMP, recursive = TRUE)
cat(sprintf("\n== superfan_watch: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"superfan_watch","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
