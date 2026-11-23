# test_research_brief_lines.R — 아침 1계층 상태 통의 '개별 연구' 줄(02_Infrastructure/ops/morning_steps/research_brief_lines.R) 모래상자 시험 (2026-11-24)
#   임시 루트에 등록부 · AI 팩터 연구 꼴 설정과 상태 파일 · status.json · README 를 만들어 줄을 잰다(운영 파일 · 발송 무접촉).
#   축: A aif 진행 — 단계 이름 · 상태 단어 · 단계 진행률 · 전체 진행률(= 그 연구의 R/aif_status.R::aif_overall 과 대조) · 세부 글 · 갱신 시각 ·
#       B 대기 — 대기 사유 + '★갱신 없음 n시간(멈춤 확인)' · C status_json — 끝 · 수치 든 세부 글 생략 · 다음 할 일 · D readme '상태:' 줄(별표 제거) ·
#       E 꺼진 항목 안 나옴 · F 모르는 종류 · 상태 파일 없음 = 그 줄만 판독 불가(다른 줄 유지) · G 등록 안 된 최근 폴더 알림(무시 목록 · 오래된 폴더 제외) ·
#       H 줄 160자 상한 · W 배선(l1_status_send.R 이 개별 연구 구획을 싣는다 · 운영 등록부 판독) ·
#       M1 수치 거르개 제거 → C 가 수치를 싣는다(검출) · M2 멈춤 표지 제거 → B 가 표지를 잃는다(검출) — 치환 성사 단정.
# 실행: Rscript 08_Tests/ops/test_research_brief_lines.R
suppressPackageStartupMessages(library(jsonlite))
.f <- gsub("\\\\", "/", sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (!grepl("^([A-Za-z]:)?/", .f)) .f <- file.path(gsub("\\\\", "/", getwd()), .f)
ROOT <- dirname(dirname(dirname(.f)))
SUT <- file.path(ROOT, "02_Infrastructure/ops/morning_steps/research_brief_lines.R")
AIF_STATUS_R <- file.path(ROOT, "04_Research/01_reports/ai_factor_research_20261122/R/aif_status.R")
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
chk <- function(name, ok, note = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat("  PASS ", name, "\n") } else { FAIL <<- FAIL + 1L; cat("  FAIL ", name, " ", note, "\n") }
}
wj <- function(x, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null"), p, useBytes = TRUE) }
ts <- function(t) format(t, "%Y-%m-%d %H:%M:%S")
NOW <- Sys.time()

T <- gsub("\\\\", "/", tempfile("rbtest_")); dir.create(T)
R <- file.path(T, "04_Research/01_reports")
cfg <- list(paths = list(out_cache = ".cache/aif_x"),
            progress = list(stages = list(list(key = "s1", name = "자료 준비", weight = 2),
                                          list(key = "s2", name = "수식 탐색", weight = 6),
                                          list(key = "s3", name = "보고", weight = 2))),
            followup = list(progress = list(stages = list(list(key = "f1", name = "위험 모형", weight = 4),
                                                          list(key = "f2", name = "결합", weight = 6)))))
wj(cfg, file.path(R, "aif_x/aif_config.json"))
st_main <- list(stage_key = "s2", stage_state = "running", stage_progress = list(s1 = 1, s2 = 0.5), detail = "ROLL8 2016년 진화 끝",
                updated_at = ts(NOW - 3600))
wj(st_main, file.path(T, ".cache/aif_x/status.json"))
st_fu <- list(stage_key = "f1", stage_state = "waiting", wait_reason = "메모리 대기", stage_progress = list(f1 = 0.3),
              updated_at = ts(NOW - 10 * 3600 - 120))
wj(st_fu, file.path(T, ".cache/aif_x/followup/status.json"))
wj(list(stage = "검증", state = "done", progress = 1, detail = "IC 0.051 · t=2.3", `next` = "보고서", updated_at = ts(NOW - 7200)),
   file.path(R, "sj/status.json"))
dir.create(file.path(R, "rd"), recursive = TRUE)
writeLines(c("# 시험 연구", "", "상태: **스모크 완료** · 전체 실행 대기", "본문"), file.path(R, "rd/README.md"), useBytes = TRUE)
dir.create(file.path(R, "ms"), recursive = TRUE)                               # 상태 파일 없음
for (d in c("new_research", "ign", "old")) { dir.create(file.path(R, d), recursive = TRUE); writeLines("x", file.path(R, d, "a.txt")) }
Sys.setFileTime(file.path(R, "old/a.txt"), NOW - 10 * 86400)
reg <- list(schema = "research_briefs_v1", stale_hours_running = 6,
            discover = list(root = "04_Research/01_reports", recent_days = 3, ignore = list(list(dir = "ign", why = "시험"))),
            items = list(
              list(id = "a1", name = "에이아이 1단계", kind = "aif_status", dir = "04_Research/01_reports/aif_x", track = "", active = TRUE),
              list(id = "a2", name = "에이아이 2단계", kind = "aif_status", dir = "04_Research/01_reports/aif_x", track = "followup", active = TRUE),
              list(id = "sj", name = "약속 상태 연구", kind = "status_json", dir = "04_Research/01_reports/sj", active = TRUE),
              list(id = "rd", name = "리드미 연구", kind = "readme_state", dir = "04_Research/01_reports/rd", active = TRUE),
              list(id = "off", name = "꺼진 연구", kind = "readme_state", dir = "04_Research/01_reports/rd", active = FALSE),
              list(id = "mk", name = "모르는 종류", kind = "mystery", dir = "04_Research/01_reports/rd", active = TRUE),
              list(id = "ms", name = "상태 없음", kind = "status_json", dir = "04_Research/01_reports/ms", active = TRUE)))
wj(reg, file.path(T, "06_Registry/research_briefs.json"))

run <- function(src = SUT) { e <- new.env(); sys.source(src, envir = e); e$research_brief_lines(T, now = NOW) }
L <- run()
cat(paste0("    | ", L), sep = "\n")
ln <- function(prefix) { x <- L[startsWith(L, prefix)]; if (length(x)) x[1] else "" }

cat("== A aif 진행\n")
a1 <- ln("에이아이 1단계: ")
exp_overall <- as.integer(round(100 * (2 * 1 + 6 * 0.5 + 2 * 0) / 10))
chk("A1 단계 이름 · 상태 단어 · 단계 진행률", grepl("수식 탐색 진행 중(단계 50%)", a1, fixed = TRUE), a1)
chk("A2 전체 진행률 = 가중 합", grepl(sprintf("전체 %d%%", exp_overall), a1, fixed = TRUE), a1)
if (file.exists(AIF_STATUS_R)) {
  ea <- new.env(); assign("%||%", function(a, b) if (is.null(a) || length(a) == 0L) b else a, envir = ea)
  sys.source(AIF_STATUS_R, envir = ea)
  ref <- as.integer(round(100 * ea$aif_overall(st_main, cfg, track = "")))
  chk("A3 전체 진행률 = 그 연구의 aif_overall(실제 함수)", grepl(sprintf("전체 %d%%", ref), a1, fixed = TRUE), sprintf("ref=%d · %s", ref, a1))
} else { SKIP <- SKIP + 1L; cat("  SKIP  A3 AIF 의 aif_status.R 없음:", AIF_STATUS_R, "\n") }
chk("A4 세부 글 · 갱신 시각 · 멈춤 표지 없음(1시간 전)", grepl("ROLL8 2016년 진화 끝", a1, fixed = TRUE) &&
      grepl(sprintf("갱신 %s", format(NOW - 3600, "%m-%d %H:%M")), a1, fixed = TRUE) && !grepl("갱신 없음", a1, fixed = TRUE), a1)

cat("== B 대기 · 멈춤 표지\n")
a2 <- ln("에이아이 2단계: ")
chk("B1 대기 · 대기 사유 · 단계 이름(2단계 목록)", grepl("위험 모형 대기(단계 30%)", a2, fixed = TRUE) && grepl("대기 사유 메모리 대기", a2, fixed = TRUE), a2)
chk("B2 10시간 갱신 없음 → ★갱신 없음 10시간(멈춤 확인)", grepl("★갱신 없음 10시간(멈춤 확인)", a2, fixed = TRUE), a2)

cat("== C status_json\n")
sj <- ln("약속 상태 연구: ")
chk("C1 끝 · 전체 100% · 다음 할 일", grepl("검증 끝", sj, fixed = TRUE) && grepl("전체 100%", sj, fixed = TRUE) && grepl("다음 보고서", sj, fixed = TRUE), sj)
chk("C2 수치 든 세부 글 생략(0.051 · t=2.3 안 나옴)", grepl("(수치가 든 세부 글 — 생략)", sj, fixed = TRUE) && !grepl("0.051", sj, fixed = TRUE), sj)
chk("C3 끝난 항목엔 멈춤 표지 없음", !grepl("갱신 없음", sj, fixed = TRUE), sj)

cat("== D readme\n")
rd <- ln("리드미 연구: ")
chk("D1 '상태:' 줄 · 별표 제거 · README 갱신 시각", grepl("리드미 연구: 스모크 완료 · 전체 실행 대기 · README 갱신 ", rd, fixed = TRUE), rd)

cat("== E · F 항목 실패 격리\n")
chk("E1 꺼진 항목 안 나옴", !any(grepl("꺼진 연구", L, fixed = TRUE)), paste(L, collapse = " | "))
chk("F1 모르는 종류 = 그 줄만 판독 불가", grepl("판독 불가(상태 원천 종류 'mystery' 모름)", ln("모르는 종류: "), fixed = TRUE), ln("모르는 종류: "))
chk("F2 상태 파일 없음 = 그 줄만 판독 불가 · 다른 줄 유지", startsWith(ln("상태 없음: "), "상태 없음: 판독 불가(") && nzchar(a1) && nzchar(sj) && nzchar(rd), ln("상태 없음: "))

cat("== G 등록 안 된 최근 폴더\n")
g <- ln("등록 안 된 최근 연구 폴더 ")
chk("G1 새 폴더만 알림(무시 목록 · 10일 지난 폴더 · 등록 폴더 제외)", grepl("1개: new_research(", g, fixed = TRUE) &&
      !grepl("ign", g, fixed = TRUE) && !grepl("old", g, fixed = TRUE) && !grepl("aif_x", g, fixed = TRUE), g)

cat("== H 길이\n")
chk("H1 모든 줄 ≤ 160자", all(nchar(L) <= 160L), paste(nchar(L), collapse = ","))

cat("== W 배선 · 운영 등록부\n")
ls_src <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/morning_steps/l1_status_send.R"), encoding = "UTF-8", warn = FALSE), collapse = "\n")
chk("W1 l1_status_send.R — research_brief_lines.R 를 sys.source · '개별 연구' 구획", grepl("research_brief_lines.R", ls_src, fixed = TRUE) &&
      grepl("sys.source(", ls_src, fixed = TRUE) && grepl("heading = \"개별 연구\"", ls_src, fixed = TRUE), "")
prod <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/research_briefs.json"), simplifyVector = FALSE), error = function(e) NULL)
kinds <- vapply(Filter(function(it) isTRUE(it$active), prod$items %||% list()), function(it) it$kind %||% "", "")
chk("W2 운영 등록부 판독 · 켜진 항목 ≥ 1 · 종류는 셋 중 하나", !is.null(prod) && length(kinds) >= 1L && all(kinds %in% c("aif_status", "status_json", "readme_state")),
    paste(kinds, collapse = ","))

cat("== M 돌연변이\n")
src <- readLines(SUT, encoding = "UTF-8", warn = FALSE)
mut <- function(from, to) {
  i <- which(src == from)
  if (length(i) != 1L) return(NULL)
  s2 <- src; s2[i] <- to; p <- file.path(T, "mut.R"); writeLines(s2, p, useBytes = TRUE); p
}
p1 <- mut(".rb_numeric_rx <- \"[0-9][.][0-9]|[0-9][[:space:]]*%|(^|[[:space:](=:])[+−-][0-9]\"", ".rb_numeric_rx <- \"(?!)\"")
if (is.null(p1)) chk("M1 치환 성사", FALSE, "수치 거르개 줄이 정확히 1개가 아님") else {
  L1 <- run(p1); s1 <- L1[startsWith(L1, "약속 상태 연구: ")][1]
  chk("M1 수치 거르개 제거 → C 가 0.051 을 싣는다(검출)", grepl("0.051", s1, fixed = TRUE), s1)
}
p2 <- mut("  if (is.finite(h) && h > hrs) sprintf(\" · ★갱신 없음 %d시간(멈춤 확인)\", as.integer(floor(h))) else \"\"",
          "  if (FALSE) \"\" else \"\"")
if (is.null(p2)) chk("M2 치환 성사", FALSE, "멈춤 표지 줄이 정확히 1개가 아님") else {
  L2 <- run(p2); s2 <- L2[startsWith(L2, "에이아이 2단계: ")][1]
  chk("M2 멈춤 표지 제거 → B 가 표지를 잃는다(검출)", !grepl("갱신 없음", s2, fixed = TRUE), s2)
}

unlink(T, recursive = TRUE)
cat(sprintf("\n[test_research_brief_lines] %d passed, %d failed, %d skipped\n", PASS, FAIL, SKIP))
cat(toJSON(list(test = "research_brief_lines", pass = PASS, fail = FAIL, skipped = SKIP, total = PASS + FAIL + SKIP), auto_unbox = TRUE), "\n")
quit(status = if (FAIL > 0L) 1L else 0L)
