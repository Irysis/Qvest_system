## test_superfan_watch.R — 구성요소 Superfan 감시기(programs/superfan_watch.py · 2026-10-16) — 임시 정의 · 임시 로그 · 임시 상태로만(운영 무접촉)
##   ① 로그 규칙: 새 줄 감지 · 증분(재스캔 무중복) · 같은 증상 묶기(count) · 다른 증상 = 새 키 ② 블록 제외(trigger=test) · exclude ③ 사건 시각 —
##   문턱보다 오래된 사건은 세지 않음 · 처음 스캔의 시각 모르는 줄 무시 · 만료 ④ freshness · expect_today · json_field(정상 복귀 = 자동 해소)
##   ⑤ ack → 재발 시 재개방 ⑥ 잘림(크기 < 오프셋) ⑦ 같은 로그를 두 구성요소가 따로 본다 ⑧ 정의 검증(위반 주입) ⑨ 부팅 꼬리 · 깨진 상태 '?(…)'
##   ⑩ 세션 재개 Resume 줄 배선 ⑪ 운영 정의(06_Registry/superfan_components.json) 검증 통과 ⑫ 양성 대조 — 사건 시각 필터를 끈 사본은 옛 사건을 센다
##   ⑬ 무인 알림(스텁 발신기) ⑭ 양성 대조 — 정본 발신기 건식(이상 1건 · 2건) · 수리 전 판 빨강(10-17 T1 C-036)
##   ⑮ v10.2 구성요소 4종(11-10) — 상설 판(사건 나이 · 판 승계 · 해시 사슬 + 양성 대조) · 강화 사슬(열린 걸음 · 닫힌 사슬) · 판 표식(원장 누락 · 접두어 id) ·
##      판단 원장(그 뒤 커밋 · git 실패 · 커밋 0) · 새 종류 정의 검증(문턱 근거 · 어휘 · 필수 필드)
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

## ④-b 해소 뒤 재발 = 새 일화 → 재개방(2026-11-10 — 상태형 규칙은 새 로그 줄이 없어 재발이 'seen' 으로 묻혔다) + 확인한 상태가 이어지면 그대로
jsA <- function() Filter(function(a) identical(a$rule, "js"), st()$anomalies)
writeLines('{"status":"failed"}', JS)
ev <- run("scan")
j1 <- jsA()
chk("④-b 해소 뒤 같은 상태 재발 → open · reopened 1(새 키 아님)", length(j1) == 1L && identical(j1[[1]]$status, "open") && j1[[1]]$reopened == 1L,
    if (length(j1)) paste(j1[[1]]$status, j1[[1]]$reopened) else "none")
chk("④-b 재발이 사건 줄로 남는다(알림 대상이 된다)", any(grepl("reopened js", ev$out, fixed = TRUE)), paste(ev$out, collapse = " | "))
invisible(run("scan"))
chk("④-b 재발이 이어지는 동안은 다시 재개방하지 않는다(reopened 그대로 1)", jsA()[[1]]$reopened == 1L && identical(jsA()[[1]]$status, "open"))
invisible(run("ack", "--key", jsA()[[1]]$key, "--kind", "known", "--note", shQuote("알려진 상태")))
invisible(run("scan"))
chk("④-b 확인(acked)한 상태가 이어지면 acked 유지(정상 복귀 없이 재개방 안 함)", identical(jsA()[[1]]$status, "acked") && jsA()[[1]]$reopened == 1L, jsA()[[1]]$status)
writeLines('{"status":"ok"}', JS); invisible(run("scan"))
writeLines('{"status":"failed"}', JS); invisible(run("scan"))
chk("④-b 확인 → 정상 복귀 → 재발 → 재개방(reopened 2)", identical(jsA()[[1]]$status, "open") && jsA()[[1]]$reopened == 2L, paste(jsA()[[1]]$status, jsA()[[1]]$reopened))
## ④-c 양성 대조 — 수리 전 조건으로 되돌린 사본은 해소 뒤 재발을 놓친다
src_b <- readLines(TOOL, warn = FALSE, encoding = "UTF-8")
tgt_b <- '    if a["status"] == "resolved" or (a["status"] in ("acked", "expired") and from_new_lines):'
hit_b <- which(src_b == tgt_b)
mut_b <- src_b; if (length(hit_b) == 1L) mut_b[hit_b] <- '    if a["status"] in ("acked", "expired", "resolved") and from_new_lines:'
MTB <- file.path(TMP, "superfan_watch_mut_reopen.py"); writeLines(mut_b, MTB, useBytes = TRUE)
writeLines('{"status":"ok"}', JS); invisible(run("scan", tool = MTB))
writeLines('{"status":"failed"}', JS); invisible(run("scan", tool = MTB))
chk("④-c 치환 성사(1곳) · 수리 전 조건이면 해소 뒤 재발이 resolved 로 묻힌다 — ④-b 가 이것을 잡는다",
    length(hit_b) == 1L && identical(jsA()[[1]]$status, "resolved") && jsA()[[1]]$reopened == 2L, paste(length(hit_b), jsA()[[1]]$status, jsA()[[1]]$reopened))
writeLines('{"status":"ok"}', JS); invisible(run("scan"))     # 뒤 검사를 위해 정상으로 되돌림

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

## ⑭ 양성 대조 — 정본 발신기(superfan_notify.R → tg_agent_brief) 건식(QVEST_TG_DRY_RUN=1 · 발송 없음)으로 이상 1건 · 2건 payload 가 둘 다 ok ·
##   수리 전 판(git b234afb11 의 superfan_notify.R)은 1건 payload 를 fail 로 낸다(⑬ 의 스텁 발신기는 이 결함을 원리상 못 본다 — 판단 Superfan T1 C-20261017-036)
NOTI <- file.path(ROOT, "02_Infrastructure/programs/superfan_notify.R")
pay <- function(n) { p <- file.path(TMP, sprintf("pay%d.json", n))
  an <- lapply(seq_len(n), function(i) list(key = sprintf("k%d", i), rule = "errs", text = sprintf("Error in probe_%d(x) : 정본 발신기 건식 양성 대조 항목 %d", i, i),
                                           count = 1L, first_seen = "2026-10-17T19:00:00", last_seen = "2026-10-17T19:00:00", reopened = 0L))
  jsonlite::write_json(list(at = "2026-10-17T19:00:00", mute = TRUE, groups = list(list(component = "alpha", name = "A", anomalies = an))), p, auto_unbox = TRUE); p }
noti <- function(script, p) { Sys.setenv(QVEST_TG_DRY_RUN = "1", QM_ROOT = ROOT); on.exit(Sys.unsetenv("QVEST_TG_DRY_RUN"))   # Windows 에선 system2 의 env 인자가 Rscript 에 안 먹는다 — 자식은 Sys.setenv 를 물려받는다
  suppressWarnings(system2("Rscript", c("--no-environ", shQuote(script), shQuote(p)), stdout = TRUE, stderr = FALSE)) }
o1 <- noti(NOTI, pay(1L)); o2 <- noti(NOTI, pay(2L))
chk("⑭ 정본 발신기 건식 — 이상 1건 · 2건 payload 둘 다 'SFN alpha ok'", any(o1 == "SFN\talpha\tok") && any(o2 == "SFN\talpha\tok"), paste(c(o1, o2), collapse = " | "))
OLDN <- file.path(TMP, "superfan_notify_old.R")
okold <- tryCatch(identical(system2("git", c("-C", shQuote(ROOT), "show", "b234afb11:02_Infrastructure/programs/superfan_notify.R"), stdout = OLDN, stderr = FALSE), 0L), error = function(e) FALSE)
o0 <- if (isTRUE(okold)) noti(OLDN, pay(1L)) else character(0)
chk("⑭ 수리 전 판(b234afb11) 빨강 — 이상 1건 payload = 'SFN alpha fail'", isTRUE(okold) && any(o0 == "SFN\talpha\tfail"), paste(o0, collapse = " | "))

## ⑮ v10.2 구성요소 4종(2026-11-10) — 새 규칙 종류 jsonl_ledger(chain · event_age · pending) · ledger_covers · ledger_activity
##    규칙마다 양방향: 위반 주입 → 발화 · 정상 → 무음 · 대상 없음 → 무음. 임시 등록부 · 임시 상태 · 임시 원장만(운영 무접촉 · 발신기 미호출)
REG2 <- file.path(TMP, "components_v102.json"); WST2 <- file.path(TMP, "watch_v102.json"); V <- file.path(TMP, "v102")
dir.create(V)
Sys.setenv(QVEST_SUPERFAN_REGISTRY_PATH = REG2, QVEST_SUPERFAN_WATCH_PATH = WST2, QVEST_SUPERFAN_NOW = "2026-10-16 12:00")
SRC <- "근거 문구(시험)"
JLF <- file.path(V, "jl.json"); VLF <- file.path(V, "vintage.json")
reg2 <- list(schema = "superfan_components_v1", default_max_event_age_h = 48, components = list(
  list(id = "sb", name = "상설", dossier = "d.md", rules = list(
    list(id = "scan_stale", kind = "jsonl_ledger", check = "event_age", files = list(file.path(V, "sa/programs/*/*/standing_ledger.jsonl")),
         events = list("scan", "measure"), edition_field = "edition", max_age_h = 26, max_age_h_source = SRC, severity = "warn"),
    list(id = "ledger_chain", kind = "jsonl_ledger", check = "chain", files = list(file.path(V, "sa/programs/*/*/standing_ledger.jsonl")),
         schema = "rc_standing_ledger_v1", severity = "fail"))),
  list(id = "rc", name = "사슬", dossier = "d.md", rules = list(
    list(id = "step_stalled", kind = "jsonl_ledger", check = "pending", files = list(file.path(V, "progs/*/*/chain_steps.jsonl")),
         open_event = "step_open", close_event = "step_result", match_field = "k", terminal_event = "chain_closed",
         max_age_h = 6, max_age_h_source = SRC, severity = "warn"))),
  list(id = "fv", name = "판 표식", dossier = "d.md", rules = list(
    list(id = "unrecorded_repair", kind = "ledger_covers", summaries = list(file.path(V, "logs/factor_subset_repair_*.json")), exclude = list("\\.prev_"),
         ok_field = "result", ok_values = list("성공"), id_field = "decision",
         time_from = list(stamp_field = "stamp", stamp_format = "%Y%m%d_%H%M%S", plus_seconds_field = "seconds"),
         ledger = VLF, ledger_list = "entries", ledger_time_field = "completed_at", ledger_id_fields = list("id", "decision"), severity = "warn"))),
  list(id = "jl", name = "판단 원장", dossier = "d.md", rules = list(
    list(id = "ledger_stale", kind = "ledger_activity", file = JLF, git_repo = ROOT, max_age_h = 26, max_age_h_source = SRC, severity = "warn")))))
wreg2 <- function(x = reg2) writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE), REG2)
wreg2()
md5s <- function(s) { f <- tempfile(); con <- file(f, "wb"); writeBin(charToRaw(enc2utf8(s)), con); close(con); h <- unname(tools::md5sum(f)); unlink(f); h }
wjl <- function(path, recs, schema) {   # round_core 원장과 같은 줄 형식(공통 머리 + 앞 줄 md5 사슬 · LF · UTF-8)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE); prev <- "genesis"; L <- character(0)
  for (r in recs) { s <- as.character(jsonlite::toJSON(c(list(schema = schema, prev = prev), r), auto_unbox = TRUE)); L <- c(L, s); prev <- md5s(s) }
  con <- file(path, "wb"); writeBin(charToRaw(enc2utf8(paste0(paste(L, collapse = "\n"), "\n"))), con); close(con)
}
st2 <- function() { p <- Sys.getenv("QVEST_SUPERFAN_WATCH_PATH"); if (file.exists(p)) jsonlite::fromJSON(p, simplifyVector = FALSE) else list(anomalies = list()) }
opn <- function(comp, rule = NULL) Filter(function(a) identical(a$status, "open") && identical(a$component, comp) && (is.null(rule) || identical(a$rule, rule)), st2()$anomalies)
sc2 <- function(...) invisible(run("scan", ...))

## 대상 없음 → 네 구성요소 모두 무음
r0 <- sc2()
chk("⑮ 대상 없음(원장 · 요약 · 판단 원장 파일 0) → rc 0 · 네 구성요소 무음", r0$rc == 0L && !length(opn("sb")) && !length(opn("rc")) && !length(opn("fv")) && !length(opn("jl")),
    paste(r0$out, collapse = " | "))

## 상설 판 — event_age(판 승계) · chain
SB <- "rc_standing_ledger_v1"
S01 <- file.path(V, "sa/programs/P1_RETURN/P1S01_x/standing_ledger.jsonl"); S02 <- file.path(V, "sa/programs/P1_RETURN/P1S02_x/standing_ledger.jsonl")
wjl(S01, list(list(at = "2026-10-01T09:00:00+0900", edition = 1L, event = "scan")), SB)          # 옛 판 — 오래됐지만 새 판이 있으니 보지 않는다
wjl(S02, list(list(at = "2026-10-15T08:00:00+0900", edition = 2L, event = "enqueue", code = "a"),
              list(at = "2026-10-16T10:00:00+0900", edition = 2L, event = "scan")), SB)
sc2()
chk("⑮ 상설 정상(새 판 2시간 전 스캔 · 옛 판은 승계로 제외) → 무음 · 사슬 정상", !length(opn("sb")), paste(vapply(opn("sb"), `[[`, "", "text"), collapse = " | "))
wjl(S02, list(list(at = "2026-10-13T08:00:00+0900", edition = 2L, event = "enqueue", code = "a"),
              list(at = "2026-10-14T08:00:00+0900", edition = 2L, event = "scan"),
              list(at = "2026-10-15T08:00:00+0900", edition = 2L, event = "reported", kind = "daily_summary")), SB)
sc2()
o <- opn("sb", "scan_stale")
chk("⑮ 상설 위반 — 마지막 scan · measure 52시간 전(보고 사건은 세지 않음) → 경고 1 · 새 판 파일", length(o) == 1L && grepl("P1S02", o[[1]]$text) && identical(o[[1]]$severity, "warn"),
    paste(vapply(o, `[[`, "", "text"), collapse = " | "))
L2 <- readLines(S02, encoding = "UTF-8")
wjl(S02, c(lapply(L2, function(s) { x <- jsonlite::fromJSON(s, simplifyVector = FALSE); x$schema <- NULL; x$prev <- NULL; x }),
           list(list(at = "2026-10-16T11:00:00+0900", edition = 2L, event = "measure", code = "a"))), SB)
sc2()
chk("⑮ 상설 측정이 돌면(1시간 전 measure) → 자동 해소", !length(opn("sb", "scan_stale")) &&
      all(vapply(Filter(function(a) identical(a$rule, "scan_stale"), st2()$anomalies), function(a) identical(a$status, "resolved"), TRUE)))
chk("⑮ 사슬 정상 원장(4줄) → 해시 사슬 이상 없음", !length(opn("sb", "ledger_chain")))
L3 <- readLines(S02, encoding = "UTF-8"); L3[2] <- sub("\"scan\"", "\"scan_edited\"", L3[2], fixed = TRUE)
con <- file(S02, "wb"); writeBin(charToRaw(enc2utf8(paste0(paste(L3, collapse = "\n"), "\n"))), con); close(con)
sc2()
oc <- opn("sb", "ledger_chain")
chk("⑮ 상설 원장 중간 줄 변조 → 해시 사슬 끊김(실패 · 줄 3)", length(oc) == 1L && identical(oc[[1]]$severity, "fail") && grepl("줄 3", oc[[1]]$text, fixed = TRUE),
    paste(vapply(oc, `[[`, "", "text"), collapse = " | "))
## 양성 대조 — prev 대조를 끈 감시기 사본(소스 텍스트 치환)은 같은 변조를 놓친다
src_c <- readLines(TOOL, warn = FALSE, encoding = "UTF-8")
tgt_c <- '                if x is None or x.get("prev") != prev or (r.get("schema") and x.get("schema") != r["schema"]):'
hit_c <- which(src_c == tgt_c); mut_c <- src_c; if (length(hit_c) == 1L) mut_c[hit_c] <- "                if x is None:"
MTC <- file.path(TMP, "superfan_watch_mut_chain.py"); writeLines(mut_c, MTC, useBytes = TRUE)
WSTM <- file.path(TMP, "watch_mut.json"); Sys.setenv(QVEST_SUPERFAN_WATCH_PATH = WSTM)
invisible(run("scan", tool = MTC)); om <- opn("sb", "ledger_chain")
Sys.setenv(QVEST_SUPERFAN_WATCH_PATH = WST2)
chk("⑮ 양성 대조 — 치환 성사(1곳) · prev 대조를 끈 사본은 변조를 놓친다(원본은 잡음)", length(hit_c) == 1L && !length(om) && length(oc) == 1L, sprintf("hit=%d mut_open=%d", length(hit_c), length(om)))

## 강화 사슬 — pending(열린 걸음 정체) · 닫힌 사슬 = 무음
CS <- file.path(V, "progs/P4_ASSEMBLY/P4C01_x/chain_steps.jsonl"); SC <- "rc_p4_chain_steps_v1"
base <- list(list(at = "2026-10-15T09:00:00+0900", event = "chain_registered", chain_id = "P4C01_x"))
wjl(CS, c(base, list(list(at = "2026-10-16T03:00:00+0900", event = "step_open", k = 1L))), SC)
sc2()
o <- opn("rc", "step_stalled")
chk("⑮ 사슬 위반 — 걸음 k=1 이 판정 없이 9시간(문턱 6) → 경고", length(o) == 1L && grepl("k=1", o[[1]]$text, fixed = TRUE), paste(vapply(o, `[[`, "", "text"), collapse = " | "))
wjl(CS, c(base, list(list(at = "2026-10-16T03:00:00+0900", event = "step_open", k = 1L), list(at = "2026-10-16T09:00:00+0900", event = "step_result", k = 1L, decision = "reject"),
                     list(at = "2026-10-16T11:00:00+0900", event = "step_open", k = 2L))), SC)
sc2()
chk("⑮ 사슬 정상 — k=1 판정됨 · k=2 는 1시간 전 열림 → 무음(해소)", !length(opn("rc", "step_stalled")))
wjl(CS, c(base, list(list(at = "2026-10-15T01:00:00+0900", event = "step_open", k = 1L), list(at = "2026-10-15T20:00:00+0900", event = "chain_closed"))), SC)
sc2()
chk("⑮ 닫힌 사슬(chain_closed)의 열린 걸음 → 무음", !length(opn("rc", "step_stalled")))

## 팩터 DB 판 표식 — ledger_covers
LG <- file.path(V, "logs"); dir.create(LG)
vled <- function(entries) jsonlite::write_json(list(schema = "factor_db_vintage_v1", entries = entries), VLF, auto_unbox = TRUE)
summ <- function(name, stamp, result, decision = NULL, seconds = 600) {
  x <- list(schema = "factor_subset_repair/v1", stamp = stamp, result = result, seconds = seconds); if (!is.null(decision)) x$decision <- decision
  jsonlite::write_json(x, file.path(LG, name), auto_unbox = TRUE) }
vled(list(list(id = "REPAIR-A", completed_at = "2026-10-15T10:00:00+0900", scope = "all", decision = "REPAIR-A · 도훈")))
summ("factor_subset_repair_20261014_090000.json", "20261014_090000", "성공", "REPAIR-OLD")      # 원장 마지막 완료보다 앞 — 무음
summ("factor_subset_repair_20261016_080000.json", "20261016_080000", "실패", "REPAIR-FAILED")   # 실패 — 무음
sc2()
chk("⑮ 판 표식 정상 — 원장보다 새 '성공' 요약 없음(옛 요약 · 실패 요약만) → 무음", !length(opn("fv")))
summ("factor_subset_repair_20261016_090000.json", "20261016_090000", "성공", "REPAIR-B")
summ("factor_subset_repair_20261016_090000.prev_20261016_100000.json", "20261016_090000", "성공", "REPAIR-B")   # 이전 판 사본 — 제외
sc2()
o <- opn("fv")
chk("⑮ 판 표식 위반 — 원장보다 새 수리 '성공' · 원장에 결정 id 없음 → 경고 1(이전 판 사본 제외)", length(o) == 1L && grepl("REPAIR-B", o[[1]]$text, fixed = TRUE),
    paste(vapply(o, `[[`, "", "text"), collapse = " | "))
vled(list(list(id = "REPAIR-A", completed_at = "2026-10-15T10:00:00+0900", scope = "all", decision = "REPAIR-A"),
          list(id = "REPAIR-B-ENTRY", completed_at = "2026-10-16T08:30:00+0900", scope = "all", decision = "REPAIR-B · FACTOR-X")))   # 요약(09:10)보다 앞 — 시각이 아니라 id 로 해소
sc2()
chk("⑮ 원장에 한 줄(결정 id = decision 칸) 넣으면 → 해소", !length(opn("fv")))
vled(list(list(id = "REPAIR-A", completed_at = "2026-10-15T10:00:00+0900", scope = "all", decision = "REPAIR-A"),
          list(id = "REPAIR-BB", completed_at = "2026-10-14T09:10:00+0900", scope = "all", decision = "REPAIR-BB")))   # 접두어만 같은 id — 일치로 치지 않는다
sc2()
chk("⑮ 접두어만 같은 id(REPAIR-BB)는 일치가 아니다 → 다시 경고", length(opn("fv")) == 1L)
unlink(file.path(LG, "factor_subset_repair_20261016_090000.json")); summ("factor_subset_repair_20261016_093000.json", "20261016_093000", "성공", NULL)
sc2()
o <- opn("fv")
chk("⑮ 결정 id 없는 '성공' 요약(원장보다 새) → 경고 · 앞 이상은 해소", length(o) == 1L && grepl("결정 id", o[[1]]$text, fixed = TRUE), paste(vapply(o, `[[`, "", "text"), collapse = " | "))

## 판단 원장 — ledger_activity(그 뒤 커밋 · git 실패 = 무음)
jl <- function(at) jsonlite::write_json(list(schema = "q_judgment_ledger_v1", judgments = list(list(id = "J-1", at = "2026-09-01T09:00:00+0900")),
                                             reviews = list(), challenges = list(list(id = "C-1", at = "2026-09-02T09:00:00+0900", responses = list(list(at = at))))),
                                        JLF, auto_unbox = TRUE)
jl("2026-10-01T09:00:00+0900"); sc2(); o <- opn("jl")
chk("⑮ 판단 원장 위반 — 마지막 기록(중첩 응답 시각까지) 15일 전 · 그 뒤 실제 저장소 커밋 있음 → 경고", length(o) == 1L && grepl("2026-10-01T09:00", o[[1]]$text, fixed = TRUE) &&
      grepl("커밋 [0-9]+건", o[[1]]$text), paste(vapply(o, `[[`, "", "text"), collapse = " | "))
jl("2026-10-16T11:00:00+0900"); sc2()
chk("⑮ 판단 원장 정상(1시간 전 기록) → 무음 · 해소", !length(opn("jl")))
jl("2026-10-01T09:00:00+0900"); bad2 <- reg2; bad2$components[[4]]$rules[[1]]$git_repo <- file.path(TMP, "no_such_repo"); wreg2(bad2); sc2()
chk("⑮ git 실패(저장소 없음) → 무음", !length(opn("jl")))
wreg2(); jl("2027-01-01T09:00:00+0900"); Sys.setenv(QVEST_SUPERFAN_NOW = "2027-01-05 12:00"); sc2()
chk("⑮ 오래됐지만 그 뒤 커밋 0 → 무음(쉰 것)", !length(opn("jl")))
Sys.setenv(QVEST_SUPERFAN_NOW = "2026-10-16 12:00")

## 정의 검증 — 새 종류의 위반 주입
bad3 <- reg2; bad3$components[[1]]$rules[[1]]$max_age_h_source <- NULL; wreg2(bad3)
chk("⑮ 문턱 근거(max_age_h_source) 없음 → validate 실패", run("validate")$rc != 0L)
bad3 <- reg2; bad3$components[[1]]$rules[[1]]$check <- "magic"; wreg2(bad3)
chk("⑮ jsonl_ledger check 어휘 밖 → validate 실패", run("validate")$rc != 0L)
bad3 <- reg2; bad3$components[[2]]$rules[[1]]$match_field <- NULL; wreg2(bad3)
chk("⑮ pending 필수 필드 없음 → validate 실패", run("validate")$rc != 0L)
wreg2()

Sys.unsetenv(c("QVEST_SUPERFAN_REGISTRY_PATH", "QVEST_SUPERFAN_WATCH_PATH", "QVEST_SUPERFAN_NOW", "QVEST_SESSION_RESUME_PATH", "QVEST_JUDGMENT_LEDGER_PATH"))
unlink(TMP, recursive = TRUE)
cat(sprintf("\n== superfan_watch: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"superfan_watch","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
