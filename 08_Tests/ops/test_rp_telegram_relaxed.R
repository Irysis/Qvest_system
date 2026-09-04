## 충실구현·이월 레인 텔레그램 — relaxed 계약 + 감사 지적은 text 섹션 (2026-09-04)
## 실사고: 충실도 기각 안내가 summary 에 500자 feedback 을 넣어 계약 [20,100] 에 걸려 3/3 유실(13:56·16:16·17:28).
##   선정 논문 안내는 영어 약어 ≥2 로 1건 유실. 강화 레인만 relaxed 였고 이 두 레인은 엄격 계약이었다.
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"), local = TRUE))
feedback <- paste(rep("MACD 는 쌍 3종인데 전조합 9종을 썼고 응답함수가 없다. ", 12), collapse = "")   # ≈500자
hdr <- list(type = "bullet", emoji = "🔍", heading = "현재 리서치 상황",
            items = c("단계: 1계층 무인 충실구현 — 적대적 충실도 감사", "판정: misdeclared · 지적 3건"))
send <- function(secs, relaxed) tryCatch({
  tg_agent_brief(agent = "AlphaSearch", relaxed = relaxed, glossary = FALSE, decode_jargon = FALSE, decode_mode = "off",
                 title = "[1계층] 충실도 감사 기각 — 재구현 (측정 등급 F)", sections = secs, dry_run = TRUE); "sent"
}, error = function(e) conditionMessage(e))

cat("=== A. 현행 구조 (summary 짧게 + text 지적) · relaxed ===\n")
new_secs <- list(hdr,
  list(type = "summary", emoji = "📌", body = "충실도 감사 기각 — misdeclared · 지적 3건 · 자동 재구현 1회"),
  list(type = "text", emoji = "📝", heading = "감사 지적사항", body = feedback))
r <- send(new_secs, TRUE)
if (identical(r, "sent")) ok("A relaxed + text 섹션 = 발송 가능") else ng("A 현행 구조가 막힘", substr(r, 1, 100))

cat("\n=== B. 위반 주입 — 구판 구조(summary 500자)는 relaxed 여도 막힌다 ===\n")
old_secs <- list(hdr, list(type = "summary", emoji = "📌", body = substr(feedback, 1, 500)))
r <- send(old_secs, TRUE)
if (grepl("must be [", r, fixed = TRUE)) ok("B summary 500자는 여전히 계약 위반 (검사가 병을 본다)") else ng("B 구판 구조가 통과", substr(r, 1, 100))

cat("\n=== C. 영어 약어 — 엄격이면 막히고 relaxed 면 통과 (선정 논문 안내) ===\n")
## 골격 가드(≥400 byte · 섹션 ≥2)는 relaxed 여도 산다 — 픽스처는 실제 이월 안내 크기로 만든다
abbr <- list(
  list(type = "bullet", emoji = "🎯", heading = "현재 리서치 상황",
       items = c("단계: 1계층 강화 프로세스 — 무인 러너", "대상: 직전 논문 소진(25회)",
                 "위치: 논문 큐 대기 60편 · 다음 1편 선정 완료", "직전 판정: 최고 등급 C · 다중검정 t값 1.472")),
  list(type = "bullet", emoji = "📄", heading = "선정 논문",
       items = c("AX-000 · RF-12 · STR_X 계열 근거", "C13 위반 없음 · PIT OK · DSR 미적용", "다음: QEPM 체인 착수 대기",
                 "제목: Maximum drawdown, recovery, and momentum — 논문 원문 링크 확보", "출처: arXiv 1403.8125")),
  list(type = "kv", emoji = "📊", heading = "큐 상태", kv = list("대기" = "60편", "강화 L1" = "1 active", "결합 후보" = "55")))
r_strict <- tryCatch({ tg_agent_brief(agent = "AlphaSearch", title = "[1계층] 강화 25회 소진 — 다음 논문 충실구현 대기",
                                      sections = abbr, dry_run = TRUE); "sent" }, error = function(e) conditionMessage(e))
r_relax  <- tryCatch({ tg_agent_brief(agent = "AlphaSearch", relaxed = TRUE, glossary = FALSE, decode_jargon = FALSE, decode_mode = "off",
                                      title = "[1계층] 강화 25회 소진 — 다음 논문 충실구현 대기",
                                      sections = abbr, dry_run = TRUE); "sent" }, error = function(e) conditionMessage(e))
if (grepl("약어", r_strict, fixed = TRUE)) ok("C 엄격 계약은 영어 약어를 막는다 (양성 대조)") else ng("C 엄격의 차단 사유가 약어가 아니다", substr(r_strict, 1, 90))
if (identical(r_relax, "sent")) ok("C relaxed 는 통과") else ng("C relaxed 가 막힘", substr(r_relax, 1, 100))

cat("\n=== D. 호출 지점이 전부 relaxed 인가 (재도출) ===\n")
cnt <- function(f) { s <- readLines(file.path(ROOT, f), warn = FALSE, encoding = "UTF-8")
  c(all = sum(grepl("tg_agent_brief(agent = ", s, fixed = TRUE)),
    rel = sum(grepl("tg_agent_brief(agent = ", s, fixed = TRUE) & grepl("relaxed = TRUE", s, fixed = TRUE))) }
for (f in c("02_Infrastructure/ops/rf_replication_verify.R", "02_Infrastructure/ops/reinforce_auto_next_paper.R")) {
  k <- cnt(f)
  if (k[["all"]] >= 1L && k[["all"]] == k[["rel"]]) ok(sprintf("D %s 호출 %d/%d relaxed", basename(f), k[["rel"]], k[["all"]])) else
    ng(sprintf("D %s", basename(f)), sprintf("relaxed %d / 호출 %d", k[["rel"]], k[["all"]]))
}
vs <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (!grepl("substr(.disp$feedback, 1, 500)", vs, fixed = TRUE)) ok("D summary 에 500자 feedback 을 넣던 줄이 없다") else ng("D 구판 summary 줄 잔존")
cat(sprintf("\n== test_rp_telegram_relaxed: %d pass · %d fail ==\n", P, F))
if (F > 0L) quit(status = 1L)
