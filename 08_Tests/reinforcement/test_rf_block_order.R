#==============================================================================
# test_rf_block_order.R — 블록 순서 적응 계약 (v10.2 2026-09-03 · C층)
#
# ★적응 탐색은 정직 비용을 동반한다. 그래서 세 가지를 함께 잰다:
#   ① 규칙이 결정론적인가(같은 입력 → 같은 출력) ② 사전등록이 덮어쓰기를 막는가
#   ③ 적응 사실이 기록되는가(Judge 6축이 사후에 볼 수 있어야 한다)
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages({ library(jsonlite); source("02_Infrastructure/reinforcement/rf_lesson.R") })
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(paste("  OK   ", m), fill = TRUE) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  cat(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else ""), fill = TRUE) }

PROG <- fromJSON("06_Registry/reinforce_program.json", simplifyVector = FALSE)
IDS  <- vapply(PROG$blocks, function(b) as.character(b$id), character(1))
AXS  <- vapply(PROG$blocks, function(b) as.character(b$axis), character(1))
RISK <- IDS[AXS == "risk_overlay"]; COMB <- IDS[AXS == "combination"]
mk <- function(cg, cl) list(attempts = list(list(essence = list(port_t = 1.5, cagr = cg, calmar = cl))))

# ── ① 진리표 4방향 — 적응은 "수익 충족 ∧ 위험 미달" 일 때만 ─────────────────
a <- rf_block_order_decide(mk(0.20, 0.30), PROG)   # 충족 · 미달 → 적응
b <- rf_block_order_decide(mk(0.10, 0.30), PROG)   # 미충족 · 미달 → 기본
c <- rf_block_order_decide(mk(0.20, 0.70), PROG)   # 충족 · 충족 → 기본
d <- rf_block_order_decide(mk(0.10, 0.70), PROG)   # 미충족 · 충족 → 기본
if (isTRUE(a$adaptive) && !isTRUE(b$adaptive) && !isTRUE(c$adaptive) && !isTRUE(d$adaptive))
  ok("① 진리표 4방향 — 수익 충족 ∧ 위험 미달 에서만 적응") else
  ng("① 적응 조건 오작동", sprintf("%s/%s/%s/%s", a$adaptive, b$adaptive, c$adaptive, d$adaptive))

# ② 적응 시 **분모를 치는 축들**이 앞으로 온다 — 그리고 그 안에서 구조적 방어가 오버레이보다 먼저.
#   ★2026-09-21 계약 변경: 구판은 "위험 축(risk_overlay)이 2번째" 였다. 그런데 오버레이는 137칸을
#     태우고 적대검증 pass 0(fail 11 · not_candidate 31) — 우선 슬롯을 전멸 확인된 축이 독점하면
#     "구속 축을 먼저 치라"는 규칙의 취지가 예산 낭비로 뒤집힌다. B7(structural_defense)은 같은
#     분모를 치되 타이밍 주장이 없어 T3 플라시보 대상이 아니다. B5 는 빠지지 않고 뒤로만 간다.
.axs  <- vapply(PROG$blocks, function(b) as.character(b$axis %||% ""), character(1))
.ids  <- vapply(PROG$blocks, function(b) as.character(b$id %||% ""), character(1))
.DEN  <- c(.ids[.axs == "structural_defense"], .ids[.axs == "risk_overlay"])   # 분모 축(기대 순서)
.got  <- a$order[seq_along(.DEN) + 1L]
if (isTRUE(a$adaptive) && identical(.got, .DEN))
  ok(sprintf("② 적응 순서 — 분모 축 %s 가 B1 직후·그 순서로 (%s)",
             paste(.DEN, collapse = ">"), paste(a$order, collapse = ">"))) else
  ng("② 분모 축 배치가 계약과 다르다",
     sprintf("기대 %s · 실제 %s", paste(.DEN, collapse = ">"), paste(a$order, collapse = ">")))

# ②b [음성 대조] 구조적 방어가 **오버레이보다 뒤**면 실패여야 한다 — 검사가 순서를 실제로 재는가
.d_i <- match(.ids[.axs == "structural_defense"][1], a$order)
.r_i <- match(.ids[.axs == "risk_overlay"][1],       a$order)
if (is.finite(.d_i) && is.finite(.r_i) && .d_i < .r_i)
  ok(sprintf("②b 구조적 방어(%d번째)가 오버레이(%d번째)보다 앞", .d_i, .r_i)) else
  ng("②b 전멸 확인된 축이 우선권을 되가져갔다", sprintf("defense %s · overlay %s", .d_i, .r_i))

# ③ 결합 블록은 언제나 마지막 — 다른 축 승자를 조합하는 블록이라 순서가 고정이다
if (identical(a$order[length(a$order)], COMB[1]) && identical(b$order[length(b$order)], COMB[1]))
  ok("③ 결합 블록은 항상 마지막") else ng("③ 결합 블록 위치가 흔들린다")

# ④ 전체 순열 — 블록이 사라지거나 늘면 격자가 깨진다
if (setequal(a$order, IDS) && length(a$order) == length(IDS))
  ok(sprintf("④ 전체 순열 유지 (%d블록)", length(IDS))) else
  ng("④ 블록 손실/중복", paste(setdiff(IDS, a$order), collapse = ","))

# ⑤ 결정론 — 같은 입력이 같은 출력을 낸다(규칙이지 재량이 아니다)
if (identical(rf_block_order_decide(mk(0.20, 0.30), PROG)$order, a$order))
  ok("⑤ 결정론 — 같은 진단 → 같은 순서") else ng("⑤ 같은 입력에 다른 순서")

# ⑥ 문턱을 정본에서 읽는가 — 재보정이 규칙에 따라와야 한다
if (grepl("0.16", a$reason, fixed = TRUE) && grepl("0.64", a$reason, fixed = TRUE))
  ok("⑥ 사유에 정본 문턱(0.16·0.64)이 박힌다") else
  ng("⑥ 문턱이 사유에 안 보인다 — 하드코딩 의심", substr(a$reason, 1, 80))

# ── ⑦⑧ 사전등록 — 덮어쓰기 금지 + 적응 표시 ────────────────────────────────
suppressMessages(source("02_Infrastructure/reinforcement/reinforce_ledger.R"))
TMP <- file.path(tempdir(), sprintf("rf_bo_%d", Sys.getpid()))
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
invisible(rf_open_entry(1L, "RP_BO", "C", root = TMP))
r1 <- tryCatch({ rf_record_block_order(1L, "RP_BO", a$order, a$reason, adaptive = TRUE, root = TMP); "ok" },
               error = function(e) conditionMessage(e))
r2 <- tryCatch({ rf_record_block_order(1L, "RP_BO", IDS, "덮어쓰기 시도", root = TMP); "no_stop" },
               error = function(e) conditionMessage(e))
if (identical(r1, "ok") && grepl("덮어쓰기 금지", r2))
  ok("⑦ 사전등록 1회 · 재기록 거부(사후 선택 방지)") else
  ng("⑦ 덮어쓰기가 허용된다", substr(paste(r1, r2), 1, 80))

.e <- Filter(function(x) identical(x$base_id, "RP_BO"), rf_load(1L, root = TMP)$entries)[[1]]
if (isTRUE(.e$search_adaptive) && length(.e$block_order) == length(IDS) && nzchar(.e$block_order_reason))
  ok("⑧ 적응 사실·순서·사유가 원장에 남는다(Judge 6축 감사 가능)") else
  ng("⑧ 기록 누락", sprintf("adaptive=%s n=%d", .e$search_adaptive, length(.e$block_order)))
unlink(TMP, recursive = TRUE, force = TRUE)

# ── ⑨ 러너 배선 — 규칙만 있고 안 물리면 순서는 그대로다 ────────────────────
rp <- tryCatch(paste(readLines("02_Infrastructure/ops/reinforce_auto_parallel.R", warn = FALSE),
                     collapse = "\n"), error = function(e) "")
if (grepl("rf_block_order_decide(", rp, fixed = TRUE) &&
    grepl("rf_record_block_order(", rp, fixed = TRUE) && grepl(".blk_order", rp, fixed = TRUE))
  ok("⑨ 러너가 결정·기록·재배열 셋 다 배선") else ng("⑨ 러너 미배선")

cat("", fill = TRUE)
cat(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL), fill = TRUE)
cat(sprintf('{"test":"rf_block_order","pass":%d,"fail":%d,"total":%d}', PASS, FAIL, PASS + FAIL), fill = TRUE)
if (FAIL > 0L) quit(status = 1L)
