#!/usr/bin/env Rscript
# test_rf_audit_tg_brief.R — 감사 지적 통지는 요약이다 (도훈 지시 2026-09-07 "텔레 보내는 양식 자체를 수정해줘")
#   양방향: 양성(요약이 짧고 축·항목·포인터를 담는다) + 위반 주입(구판처럼 원문을 실으면 상한을 넘는다).
#   격리 픽스처만 쓴다 — 운영 감사 파일·저널 무접촉.
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
invisible(capture.output(suppressMessages(
  source(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R"), local = globalenv()))))

## 픽스처 = 실사고 형태(0806.2606): 축 6개 중 portfolio 만 기각 · 항목은 [축][소제목] 접두 + 긴 원문 인용
long_q <- paste(rep("논문 §4.1.1 의 H100 = 'matched T deciles held long and B deciles sold short' 라고 적혀 있고 구현의 실현 북은 다리당 0.757 이다", 4), collapse = " ")
aud <- list(
  verdict = "misdeclared",
  undeclared_changes = list(
    paste0("[portfolio] [다리 총노출] ", long_q),
    paste0("[portfolio] [재정규화 부재] ", long_q)),
  signal_mismatch = list(
    paste0("[signal] \uc544\ud0a4\ud14d\ucc98\ub294 recurrence \ub97c \uba85\uc2dc\ud558\ub294\ub370 \uad6c\ud604\uc740 \uc21c\uc218 \ud53c\ub4dc\ud3ec\uc6cc\ub4dc\ub2e4. ", long_q),
    paste0("[signal] [\ud45c\uc801 winsorize] ", long_q),
    paste0("[signal] [\uc774\uc775 \uc785\ub825 \uc5f4] ", long_q)),
  axis_verdicts = list(
    list(axis = "signal", verdict = "adapted"), list(axis = "timing", verdict = "faithful"),
    list(axis = "universe", verdict = "adapted"), list(axis = "portfolio", verdict = "misdeclared"),
    list(axis = "cost", verdict = "faithful"), list(axis = "undeclared", verdict = "adapted")))

cat("=== A. 양성 — 요약이 짧고 필요한 것을 담는다 ===\n")
b <- rf_audit_tg_brief(aud, audit_path = "04_Research/strategies/RP_FIXT/fidelity_audit.json")
cat("  (길이", nchar(b), "자)\n")
if (nchar(b) <= 520L) ok(sprintf("A1 상한 이내 (%d자)", nchar(b))) else ng("A1 상한 초과", as.character(nchar(b)))
if (grepl("기각 portfolio", b, fixed = TRUE)) ok("A2 기각을 만든 축을 첫 줄에 지목") else ng("A2 기각 축이 안 보인다")
if (grepl("통과 5개", b, fixed = TRUE)) ok("A3 통과 축은 수로만 — 이름 나열로 길어지지 않는다") else ng("A3 통과 축 집계 없음")
if (grepl("다리 총노출", b, fixed = TRUE) && grepl("재정규화 부재", b, fixed = TRUE))
  ok("A4 감사자가 단 소제목을 그대로 라벨로 쓴다") else ng("A4 소제목 유실 — 원문에서 잘렸다")
if (!grepl("matched T deciles", b, fixed = TRUE)) ok("A5 원문 인용은 통지에 안 싣는다") else ng("A5 원문 인용이 실렸다")
if (grepl("fidelity_audit.json", b, fixed = TRUE)) ok("A6 전문 포인터가 있다(원문은 지워지지 않았다)") else ng("A6 포인터 없음")
n_bul <- length(gregexpr("\u2022", b)[[1]])
if (n_bul <= 4L) ok(sprintf("A7 항목 %d줄 (상한 4)", n_bul)) else ng("A7 항목이 상한을 넘었다")
if (grepl("외 1건", b, fixed = TRUE)) ok("A8 잘린 항목 수를 밝힌다 — 침묵 절단 아님") else ng("A8 잘린 건수 미표기")
## 미신고가 앞선다 — 기각을 만드는 것이 먼저 읽혀야 한다
i_u <- regexpr("미신고", b, fixed = TRUE); i_m <- regexpr("불일치", b, fixed = TRUE)
if (i_u[1] > 0 && (i_m[1] < 0 || i_u[1] < i_m[1])) ok("A9 미신고(기각 원인)가 불일치보다 앞") else ng("A9 정렬이 뒤집혔다")

cat("=== B. 위반 주입 ===\n")
## B1 구판 = 재구현 feedback 을 그대로 싣는 판. 같은 입력에서 상한을 크게 넘는다(= 이 검사에 검출력이 있다).
fb <- rf_audit_disposition(aud, 0L)$feedback
if (nchar(substr(fb, 1, 1500)) > 520L) ok(sprintf("B1 구판 본문은 상한 초과 (%d자) — 요약이 실제로 문제를 푼다", nchar(substr(fb, 1, 1500)))) else
  ng("B1 구판도 짧다 — 픽스처가 결함을 못 가른다")
## B2 항목 0건
b0 <- rf_audit_tg_brief(list(verdict = "faithful", undeclared_changes = list(), signal_mismatch = list(),
                             axis_verdicts = aud$axis_verdicts), audit_path = "x.json")
if (grepl("지적 항목 없음", b0, fixed = TRUE)) ok("B2 항목 0건도 침묵하지 않는다") else ng("B2 빈 요약")
## B3 축 판정 부재(구판 단일 감사자 산출) — 축 줄 없이도 죽지 않는다
b3 <- rf_audit_tg_brief(list(verdict = "misdeclared", undeclared_changes = list("[x] [소제목] 본문"),
                             signal_mismatch = list(), axis_verdicts = list()), audit_path = "x.json")
if (nzchar(b3) && grepl("소제목", b3, fixed = TRUE) && !grepl("축 0개", b3, fixed = TRUE))
  ok("B3 axis_verdicts 부재에도 항목 요약은 나온다") else ng("B3 축 부재에서 깨진다", b3)
## B4 접두 없는 항목(자유 서술) — 첫 절로 자르고 말줄임을 남긴다
b4 <- rf_audit_tg_brief(list(verdict = "misdeclared", undeclared_changes = list(long_q),
                             signal_mismatch = list(), axis_verdicts = list()), audit_path = NULL)
if (grepl("\u2026", b4, fixed = TRUE) && nchar(b4) < 200L) ok("B4 접두 없는 긴 항목은 첫 절 + 말줄임") else
  ng("B4 절단 표식이 없거나 너무 길다", as.character(nchar(b4)))
## B5 포인터 없으면 그 줄이 없다(빈 경로를 문자열로 흘리지 않는다)
if (!grepl("전문:", b4, fixed = TRUE)) ok("B5 경로 미지정 시 포인터 줄 생략") else ng("B5 빈 포인터가 실렸다")
## B6 rf_audit_read 가 axis_verdicts 를 실어 오는가(요약의 첫 줄이 그 값에 달려 있다)
tmp <- file.path(tempdir(), sprintf("aud_%d.json", Sys.getpid()))
writeLines(jsonlite::toJSON(list(verdict = "misdeclared", undeclared_changes = list("[a] [b] c"),
                                 signal_mismatch = list(), axis_verdicts = aud$axis_verdicts),
                            auto_unbox = TRUE), tmp)
rr <- rf_audit_read(tmp)
if (length(rr$axis_verdicts) == 6L) ok("B6 rf_audit_read 가 axis_verdicts 를 보존") else
  ng("B6 축 판정이 read 에서 소실 — 요약 첫 줄이 죽는다")
unlink(tmp, force = TRUE)

cat("=== C. 배선 — 소비자가 요약을 쓰는가 ===\n")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"), encoding = "UTF-8", warn = FALSE)
src <- sub("#.*$", "", src)
if (any(grepl("rf_audit_tg_brief(", src, fixed = TRUE))) ok("C1 검증기가 요약 함수를 부른다") else ng("C1 미배선")
if (!any(grepl("disp$feedback %||% \"\"), 1, 1500", src, fixed = TRUE)))
  ok("C2 구판(원문 1500자 절단)이 남아 있지 않다") else ng("C2 구판 경로 잔존")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_audit_tg_brief","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
