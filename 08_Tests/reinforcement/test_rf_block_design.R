#!/usr/bin/env Rscript
#==============================================================================
# test_rf_block_design.R — 교훈이 다음 블록 **설계**로 흐르는가 (도훈 지시 ④ · 2026-09-04)
#
# 배경: 블록 끝 기전 에이전트가 처방을 냈지만 읽는 자가 없었다. entry 안의 LLM 설계 지점은
#   B1 하나이고 그건 맨 처음에 돈다 — 교훈이 아직 없을 때. 나머지는 규칙 선정이라 처방이
#   어디에도 안 갔다(생산자만 있고 소비자가 없는, 이 저장소의 반복 병).
# 구조: 블록마다 설계 LLM 을 새로 붙이지 않고, **이미 도는 기전 에이전트**가 다음 블록
#   설계까지 낸다 — 추가 호출 0회이고 **처방과 설계가 같은 산출물**이라 어긋날 자리가 없다.
#
# 이 검사가 지키는 것: ①카탈로그 밖 항목 거부 ②중복 거부 ③B4 는 설계 대상 아님(LOO 계약)
#   ④설계가 러너 셀로 변환 ⑤집행 판정이 실제로 갈린다(executed/partial/ignored)
#   ⑥설계 없으면 규칙 폴백 — 조용한 통과 없음.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

cat("=== A. 카탈로그 — 정본에서 읽는가 ===\n")
CAT <- list()
for (b in RFBD_BLOCKS) { CAT[[b]] <- rfbd_catalog(b, ROOT)
  if (length(CAT[[b]])) ok(sprintf("A %s 카탈로그 %d종", b, length(CAT[[b]]))) else ng(sprintf("A %s 카탈로그 0종", b)) }
if (!length(rfbd_catalog("B4", ROOT))) ok("A B4 는 카탈로그가 없다 — 설계 대상 아님(LOO 계약)") else
  ng("A B4 에 카탈로그가 생겼다", "부분집합을 흔들면 귀속이 깨진다")

cat("\n=== B. 검증 — 정상 설계는 통과 (음성 대조) ===\n")
w2 <- vapply(CAT$B2, function(x) as.character(x$id), character(1))
d_ok <- list(block = "B2", cells = list(
  list(pick = w2[1], label = "a", why = "r"), list(pick = w2[2], label = "b", why = "r")))
if (isTRUE(rfbd_verify(d_ok, "B2", ROOT))) ok("B1 정상 설계 통과") else ng("B1 정상 설계 기각", as.character(rfbd_verify(d_ok, "B2", ROOT)))

cat("\n=== C. 위반 주입 ===\n")
d1 <- list(cells = list(list(pick = "NO_SUCH_ARM_XYZ", label = "x")))
if (!isTRUE(rfbd_verify(d1, "B2", ROOT))) ok("C1 카탈로그 밖 항목 기각") else ng("C1 없는 항목 통과")
d2 <- list(cells = list(list(pick = w2[1], label = "a"), list(pick = w2[1], label = "b")))
if (!isTRUE(rfbd_verify(d2, "B2", ROOT))) ok("C2 같은 항목 두 칸 기각(칸 낭비)") else ng("C2 중복 통과")
d3 <- list(cells = list(list(pick = w2[1])))
if (!isTRUE(rfbd_verify(d3, "B2", ROOT))) ok("C3 label 없는 칸 기각") else ng("C3 label 없이 통과")
d4 <- list(cells = list())
if (!isTRUE(rfbd_verify(d4, "B2", ROOT))) ok("C4 cells 0건 기각") else ng("C4 빈 설계 통과")
d5 <- list(cells = lapply(seq_len(20L), function(i) list(pick = w2[i], label = "x")))
if (!isTRUE(rfbd_verify(d5, "B2", ROOT, max_cells = 15L))) ok("C5 상한 초과 기각") else ng("C5 상한 초과 통과")

cat("\n=== D. 소비 — 설계가 러너 셀 형태로 나오는가 ===\n")
TB <- "TEST_BD_ENTRY"
dir.create(dirname(rfbd_path(ROOT, TB, "B2")), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(c(rfbd_path(ROOT, TB, "B2"), rfbd_path(ROOT, TB, "B5"), rfbd_path(ROOT, TB, "B3")), force = TRUE), add = TRUE)
write(toJSON(d_ok, auto_unbox = TRUE, null = "null"), rfbd_path(ROOT, TB, "B2"))
cl <- rfbd_cells(ROOT, TB, "B2")
if (length(cl) == 2L) ok("D1 셀 2개 생성") else ng("D1 셀 개수", as.character(length(cl)))
if (identical(cl[[1]]$code, "B2_6") && identical(cl[[2]]$code, "B2_7"))
  ok("D2 코드가 격자 번호를 유지(B2_6..)") else ng("D2 코드 규칙", cl[[1]]$code)
if (identical(cl[[1]]$weighting$kind, "catalog") && identical(as.character(cl[[1]]$weighting$arm), w2[1]))
  ok("D3 비중 축이 규칙 선정기와 같은 형태") else ng("D3 축 형태")
o5 <- vapply(CAT$B5, function(x) as.character(x$id), character(1))
write(toJSON(list(block = "B5", cells = list(list(pick = o5[1], label = "o"))), auto_unbox = TRUE, null = "null"),
      rfbd_path(ROOT, TB, "B5"))
c5 <- rfbd_cells(ROOT, TB, "B5")
if (identical(as.character(c5[[1]]$overlay$arm_id), o5[1])) ok("D4 오버레이 축 형태") else ng("D4 오버레이 형태")
u3 <- vapply(CAT$B3, function(x) as.character(x$id), character(1))
write(toJSON(list(block = "B3", cells = list(list(pick = u3[1], label = "u"))), auto_unbox = TRUE, null = "null"),
      rfbd_path(ROOT, TB, "B3"))
c3 <- rfbd_cells(ROOT, TB, "B3")
if (!is.null(c3[[1]]$universe$kind)) ok("D5 유니버스 축 형태(격자 정의를 그대로)") else ng("D5 유니버스 형태")
if (is.null(rfbd_cells(ROOT, "NO_SUCH_ENTRY", "B2"))) ok("D6 설계 없으면 NULL — 규칙 폴백") else ng("D6 폴백")

cat("\n=== E. 집행 판정 — 고리를 닫는가 ===\n")
# ★시나리오마다 **다른 디렉터리**를 쓴다. 같은 이름을 쓰면 세 픽스처가 서로를 덮고,
#   R 은 셋을 먼저 다 만들므로 마지막 것만 남는다 — 오늘 아침 spec 경로 충돌과 같은 병이다.
.mk_i <- 0L
mkatt <- function(codes, arms) {
  .mk_i <<- .mk_i + 1L
  td <- file.path(tempdir(), sprintf("bd_%d_%d", Sys.getpid(), .mk_i))
  dir.create(td, showWarnings = FALSE, recursive = TRUE)
  lapply(seq_along(codes), function(i) {
    sp <- file.path(td, sprintf("s_%s.json", codes[i]))
    write(toJSON(list(weighting = list(kind = "catalog", arm = arms[i])), auto_unbox = TRUE, null = "null"), sp)
    list(n = i, cell_code = codes[i], essence = list(cell_code = codes[i], spec = sp)) })
}
a_all  <- mkatt(c("B2_6", "B2_7"), c(w2[1], w2[2]))
a_half <- mkatt(c("B2_6", "B2_7"), c(w2[1], w2[3]))
a_none <- mkatt(c("B2_6", "B2_7"), c(w2[4], w2[3]))
r1 <- rfbd_action_status(ROOT, TB, "B2", a_all)
if (identical(r1$status, "executed")) ok("E1 설계대로 돌면 executed") else ng("E1 executed", r1$status)
r2 <- rfbd_action_status(ROOT, TB, "B2", a_half)
if (identical(r2$status, "partial")) ok("E2 절반만 돌면 partial") else ng("E2 partial", r2$status)
r3 <- rfbd_action_status(ROOT, TB, "B2", a_none)
if (identical(r3$status, "ignored")) ok("E3 하나도 안 돌면 ignored ★처방이 무시된 것을 잡는다") else ng("E3 ignored", r3$status)
r4 <- rfbd_action_status(ROOT, "NO_SUCH_ENTRY", "B2", a_all)
if (identical(r4$status, "no_design")) ok("E4 설계가 없던 블록은 no_design(무시와 구분)") else ng("E4 no_design", r4$status)

cat("\n=== F. 배선 (주석 제외) ===\n")
co <- function(f) paste(sub("#.*$", "", readLines(file.path(ROOT, f), warn = FALSE)), collapse = "\n")
par <- co("02_Infrastructure/ops/reinforce_auto_parallel.R")
mlib <- co("02_Infrastructure/ops/rf_lcode_mechanism_lib.R")
sh <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism.sh"), warn = FALSE), collapse = "\n")
if (grepl("rfbd_cells", par, fixed = TRUE)) ok("F1 러너가 설계를 소비") else ng("F1 러너 미소비")
if (grepl('is.null(.blk_design[["B2"]])', par, fixed = TRUE) &&
    grepl('is.null(.blk_design[["B5"]])', par, fixed = TRUE))
  ok("F2 설계가 있으면 규칙 픽커를 안 부른다(이중 선정 차단)") else ng("F2 이중 선정")
if (grepl("rfbd_catalog", mlib, fixed = TRUE)) ok("F3 기전 재료에 다음 블록 카탈로그") else ng("F3 카탈로그 미제공")
if (grepl("rfbd_verify", mlib, fixed = TRUE)) ok("F4 저장 전 검증") else ng("F4 검증 없이 저장")
if (grepl("prior_action_status", mlib, fixed = TRUE)) ok("F5 집행 판정을 L-code 에 남긴다") else ng("F5 집행 판정 미기록")
if (grepl("next_block_design", sh, fixed = TRUE)) ok("F6 프롬프트가 설계를 요구") else ng("F6 프롬프트 미요구")
if (grepl("LOO 가 계약", sh, fixed = TRUE) || grepl("LOO 가 계약", mlib, fixed = TRUE))
  ok("F7 B4 는 설계 대상 아님을 프롬프트/재료가 명시") else ng("F7 B4 예외 미명시")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_block_design","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
