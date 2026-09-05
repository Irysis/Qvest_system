#==============================================================================
# test_rf_block_lcode_next.R — 블록 L-code 의 "다음 격자 축" 이 **러너가 실제로 가는 축**인가
#   (2026-09-05 · 양방향)
#
# 왜 생겼나: 발행기는 다음 블록을 `prog$blocks` 의 **선언 순서**에서 집었는데, 러너는
#   `rf_block_order_decide()` 가 entry 마다 정한 **적응 순서**로 돈다. 두 순서가 갈리는
#   조건(수익 축 충족 · 위험 축 미달)이 흔해서 실측으로 어긋났다:
#     entry RP_20260904_163647_18444_rescued_rulefast_promo2 · B1 · L-RF-20260904_223318
#     L-code  : "다음 격자 축 B2(weighting)"
#     적응순서: B1>B5>B2>B3>B4  (사유: CAGR 0.207 >= 0.16 · Calmar 0.364 < 0.64)
#   부팅 `Last:` 줄이 next_probe[0] 을 그대로 echo 하므로 **세션이 보는 계기가 틀린 축을
#   가리켰다**. 조용한 실패다 — 두 문자열 다 그럴듯해서 읽어서는 안 잡힌다.
#
# ★양방향: 양성 대조(적응 축을 낸다) + 위반 주입(구판 선언순서 리졸버를 꽂으면 붉어진다).
#   위반 주입이 없으면 ⑥ 은 "무엇을 잡는지" 를 스스로 증명하지 못한다.
# 부작용 없음: 원장·L-code 파일에 쓰지 않는다(emit_lcode 를 스텁으로 가로챈다).
#
# 코드 루트: 기본 = QM_ROOT. worktree 판을 재려면 QVEST_CODE_ROOT 로 가리킨다
#   (데이터 루트는 QM_ROOT 고정 — 코드 루트는 데이터 루트가 아니다).
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = ROOT)
CODE <- Sys.getenv("QVEST_CODE_ROOT", ROOT)
suppressMessages({ library(jsonlite); library(data.table) })
suppressMessages(source(file.path(CODE, "02_Infrastructure/ops/rf_block_lcode.R")))

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  writeLines(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else "")) }

# ★리졸버 부재는 **측정된 실패**여야 한다 — 그냥 부르면 R 이 에러로 죽고, 죽은 실행은
#   JSON 요약 줄을 안 내서 배터리 파서에게 '실패' 가 아니라 '없음' 으로 보인다.
#   없는 것은 grep 에도 안 걸리고 크래시로도 안 세어진다(2026-09-05 러너 이중화 교훈).
if (!exists("rf_next_block", mode = "function")) {
  writeLines("  FAIL  rf_next_block 부재 — 발행기가 아직 선언 순서에서 다음 블록을 집는다")
  writeLines(""); writeLines("합계: 통과 0 · 실패 1")
  cat('{"test":"rf_block_lcode_next","pass":0,"fail":1,"total":1,"skipped":0}\n')
  quit(status = 1L)
}

PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
IDS  <- vapply(PROG$blocks, function(b) as.character(b$id),   character(1))
AXS  <- vapply(PROG$blocks, function(b) as.character(b$axis), character(1))
RISK <- IDS[AXS == "risk_overlay"][1]; COMB <- IDS[AXS == "combination"]
BID  <- IDS[1]          # 첫 블록 = 실측 사례의 자리(B1)
SNXT <- IDS[2]          # 선언 순서의 다음 = 구판이 내던 답

# ── ⓪ 전제 — 두 순서가 갈리지 않으면 이 검사는 공허하다 ──────────────────────
#   격자를 재편해 선언 순서가 이미 위험 축을 2번째로 두면 아래 단정은 "고쳤다" 가 아니라
#   "원래 같다" 를 재는 것이 된다. 통과로 위장시키지 않고 skip 으로 드러낸다.
if (is.na(RISK) || identical(SNXT, RISK)) {
  writeLines(sprintf("  SKIP  선언 순서가 이미 위험 축을 2번째로 둔다(%s) — 갈릴 여지 없음",
                     paste(IDS, collapse = ">")))
  cat('{"test":"rf_block_lcode_next","pass":0,"fail":0,"total":0,"skipped":1}\n'); quit(status = 0L)
}
ok(sprintf("⓪ 전제 — 선언 %s (%s 다음 %s) vs 위험 축 %s: 갈릴 여지 있음",
           paste(IDS, collapse = ">"), BID, SNXT, RISK))

# ── 픽스처 (실재하지 않는 base_id — .cache/rf_block_design 무매치로 결정론) ───
FIX   <- "RP_TEST_LCODE_NEXT_FIXTURE"
ADAPT <- c(BID, RISK, setdiff(IDS[-1L], c(RISK, COMB)), COMB)
# 적응 규칙을 켜는 실측값 = 실제 사례 그대로 (CAGR 0.207 >= 0.16 · Calmar 0.364 < 0.64)
mk <- function(cg, cl) lapply(1:5, function(i)
  list(n = i, grade = c("B", "C", "C", "C", "C")[i],
       essence = list(cell_code = sprintf("%s_%d", BID, i),
                      port_t = c(2.280, 1.000, 0.800, 0.396, 0.700)[i],
                      cagr = cg, calmar = cl, mdd = 0.57, oos_retention = -0.239)))
e_led  <- list(base_id = FIX, base_artifacts = "", block_order = as.list(ADAPT),
               attempts = mk(0.207, 0.364))
e_dec  <- list(base_id = FIX, base_artifacts = "", attempts = mk(0.207, 0.364))  # 미등록 창
e_flat <- list(base_id = FIX, base_artifacts = "", attempts = mk(0.100, 0.300))  # 규칙 미발화

# ── ① 원장에 등록된 순서가 이긴다 (덮어쓰기 금지라 이게 사실이다) ────────────
r1 <- rf_next_block(e_led, BID, PROG, root = ROOT)
if (identical(r1$id, RISK) && identical(r1$src, "ledger"))
  ok(sprintf("① 원장 block_order 우선 — %s (src=ledger)", r1$id)) else
  ng("① 원장 순서 미반영", sprintf("id=%s src=%s", r1$id %||% "NULL", r1$src))

# ── ② 등록 전 창에서 재도출한다 ★실측 사례가 정확히 이 창이다 ────────────────
#   러너는 `used >= 5` 인 **다음 배치 직전**에 등록하는데 L-code 는 블록 경계에서
#   그보다 **먼저** 나간다. 구판은 이 창에서 선언 순서로 떨어져 B2 를 적었다.
r2 <- rf_next_block(e_dec, BID, PROG, root = ROOT)
if (identical(r2$id, RISK) && identical(r2$src, "decide"))
  ok(sprintf("② 미등록 창 재도출 — %s (src=decide · 구판은 %s)", r2$id, SNXT)) else
  ng("② 미등록 창에서 적응 순서를 못 읽는다", sprintf("id=%s src=%s", r2$id %||% "NULL", r2$src))

# ── ③ 과교정 금지 — 규칙이 안 서면 선언 순서 그대로 ──────────────────────────
r3 <- rf_next_block(e_flat, BID, PROG, root = ROOT)
if (identical(r3$id, SNXT)) ok(sprintf("③ 규칙 미발화 시 선언 순서 유지 — %s", r3$id)) else
  ng("③ 과교정 — 규칙이 안 섰는데 순서가 바뀌었다", r3$id %||% "NULL")

# ── ④ 격자 소진 — 마지막 블록 뒤는 없다(그래야 '소진' 문장이 붙는다) ─────────
r4 <- rf_next_block(e_led, ADAPT[length(ADAPT)], PROG, root = ROOT)
if (is.null(r4$id)) ok("④ 마지막 블록 뒤 = NULL (격자 소진 문장으로 넘어간다)") else
  ng("④ 마지막 블록 뒤에 다음이 있다", r4$id)

# ── ⑤ 순서가 이 블록을 안 담으면 선언 순서로 떨어진다 ────────────────────────
r5 <- rf_next_block(list(base_id = FIX, block_order = list("BX", "BY")), BID, PROG, root = ROOT)
if (identical(r5$src, "program") && identical(r5$id, SNXT))
  ok("⑤ 낯선 순서 → 선언 순서 폴백 (src=program)") else
  ng("⑤ 폴백 실패", sprintf("id=%s src=%s", r5$id %||% "NULL", r5$src))

# ── ⑥ **발행되는 문장**을 잰다 — 리졸버가 맞아도 문장이 안 쓰면 계기는 그대로 틀리다 ──
#   emit_lcode / rf_notify_table 을 발행기의 closure 에 꽂아 가로챈다(원장·파일 무변경).
.tab <- data.table(n = 1:5, code = sprintf("%s_%d", BID, 1:5),
                   grade = c("B", "C", "C", "C", "C"),
                   port_t = c(2.280, 1.000, 0.800, 0.396, 0.700), inherited = FALSE,
                   sr = 0.9, cagr = 0.207, mdd = 0.57, calmar = 0.364, oos = -0.239)
emit_probe <- function(entry) {
  cap <- new.env(parent = emptyenv())
  env <- new.env(parent = globalenv())
  env$rf_notify_table <- function(base_id) list(entry = entry, tab = .tab, used = 5L, maxa = 25L)
  env$emit_lcode <- function(..., next_probe = NULL) { cap$np <- next_probe; list(l_code = "L-TEST") }
  f <- rf_emit_block_lcode; environment(f) <- env
  invisible(f(entry$base_id, 5L, root = CODE, dry_run = TRUE))
  as.character(cap$np %||% character(0))
}
np <- tryCatch(emit_probe(e_dec),
               error = function(e) { writeLines(paste("  [emit]", conditionMessage(e))); character(0) })
if (length(np) && grepl(sprintf("다음 격자 축 %s\\(", RISK), np[1]))
  ok(sprintf("⑥ 발행 문장이 적응 축을 지목 — %s", substr(np[1], 1, 64))) else
  ng("⑥ 발행 문장이 적응 축을 안 지목", if (length(np)) substr(np[1], 1, 80) else "next_probe 없음")

# ── ⑦ 위반 주입 — 구판(선언 순서) 리졸버를 꽂으면 ⑥ 이 붉어져야 한다 ─────────
#   여전히 적응 축이 나오면 ⑥ 은 아무것도 안 재는 문장이다.
.real <- rf_next_block
rf_next_block <<- function(entry, bid, prog, root = ROOT) {   # 구판 재현(선언 순서 k+1)
  .ids <- vapply(prog$blocks, function(b) as.character(b$id), character(1))
  .k <- match(bid, .ids)
  list(id = if (!is.na(.k) && .k < length(.ids)) .ids[.k + 1L] else NULL, order = .ids, src = "program")
}
np_bad <- tryCatch(emit_probe(e_dec), error = function(e) character(0))
rf_next_block <<- .real
if (length(np_bad) && grepl(sprintf("다음 격자 축 %s\\(", SNXT), np_bad[1]))
  ok(sprintf("⑦ 위반 주입 — 구판 리졸버는 %s 를 적는다(⑥ 이 실제로 갈린다)", SNXT)) else
  ng("⑦ 위반 주입이 안 잡힌다 — ⑥ 은 죽은 단정이다",
     if (length(np_bad)) substr(np_bad[1], 1, 80) else "next_probe 없음")

# ── ⑧ 배선 — 신판 호출이 **있고** 구판 계산이 **없다** ───────────────────────
#   ★한 방향만 보면 못 잡는다: 구판 제거만 재면 신판 부재를 놓치고(없는 것은 grep 에
#     안 걸린다), 신판 존재만 재면 구판이 남아 둘이 갈린 채 공존한다(러너 이중화 전례).
srcf <- paste(readLines(file.path(CODE, "02_Infrastructure/ops/rf_block_lcode.R"), warn = FALSE),
              collapse = "\n")
has_new <- grepl("rf_next_block(S$entry", srcf, fixed = TRUE)
has_old <- grepl("k <- match(bid, ids)", srcf, fixed = TRUE)
if (has_new && !has_old) ok("⑧ 배선 — 발행기가 리졸버를 부르고 구판 위치계산이 없다") else
  ng("⑧ 배선", sprintf("신판=%s 구판잔존=%s", has_new, has_old))

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
cat(sprintf('{"test":"rf_block_lcode_next","pass":%d,"fail":%d,"total":%d,"skipped":0}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
