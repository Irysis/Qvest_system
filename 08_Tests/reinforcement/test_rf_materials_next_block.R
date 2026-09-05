#==============================================================================
# test_rf_materials_next_block.R — 기전 재료의 "다음 블록" 이 **러너가 실제로 가는 축**인가
#   (2026-09-05 · 양방향)
#
# 왜 생겼나: rf_block_lcode.R 의 발행기는 2026-09-05 에 rf_next_block 으로 고쳤는데,
#   **같은 결함이 재료 생성기에 하나 더 있었다**(rf_lcode_mechanism_lib.R:106).
#   entry$block_order 를 읽는 것까지는 같고, 그 필드가 **없을 때** 정적 목록
#   c("B1","B2","B3","B5","B4") 로 떨어졌다 — 재도출을 안 했다.
#
#   그 부재 창이 정확히 이 코드가 도는 창이다: 러너는 `used >= 5 && !length(pending)` 인
#   **다음 배치 직전**에야 block_order 를 쓰는데(reinforce_auto_parallel.R:207-222),
#   블록 경계 재료 생성기는 그보다 **먼저** 돈다(같은 파일 181 · 998).
#
#   실측(RP_20260904_163647_18444_rescued_rulefast_promo2 · B1 완료 시점):
#     block_order  : 비어 있음  ->  정적 목록의 [2] = "B2"
#     재료가 준 것 : rfbd_catalog("B2")  = 비중(weighting) 카탈로그
#     러너가 간 곳 : B5(risk_overlay)   (재도출 B1>B5>B2>B3>B4 ·
#                    "CAGR 0.207 >= 0.16 충족 · Calmar 0.364 < 0.64 미달 -> 위험 축을 2번째로")
#   설계자는 **가지 않을 블록**의 칸을 짜고 그 설계는 집행되지 않는다. 조용한 실패다 —
#   B2 도 B5 도 그럴듯한 이름이라 재료를 읽어서는 안 잡힌다.
#
# ★양방향: 양성 대조(적응 축 + 그 축의 카탈로그를 낸다) + 위반 주입(구판 정적 목록
#   리졸버를 소비 지점에 꽂으면 붉어진다). 위반 주입이 없으면 ① 은 "무엇을 잡는지" 를
#   스스로 증명하지 못한다 — 초록이 상시면 침묵과 구분되지 않는다.
#
# 부작용 없음: 원장·L-code·기전 로그에 쓰지 않는다(rf_notify_table / .mx_log 를 스텁으로
#   가로채고, 재료는 tempfile 로만 쓴다).
#
# 코드 루트: 기본 = QM_ROOT. worktree 판을 재려면 QVEST_CODE_ROOT 로 가리킨다
#   (데이터 루트는 QM_ROOT 고정 — 코드 루트는 데이터 루트가 아니다).
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = ROOT)
CODE <- Sys.getenv("QVEST_CODE_ROOT", ROOT)
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  writeLines(paste("  FAIL ", m, if (nzchar(d)) paste("-", d) else "")) }
fin <- function() { writeLines(""); writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
  cat(sprintf('{"test":"rf_materials_next_block","pass":%d,"fail":%d,"total":%d,"skipped":0}\n',
              PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL > 0L) 1L else 0L) }
skip <- function(why) { writeLines(paste("  SKIP ", why))
  cat('{"test":"rf_materials_next_block","pass":0,"fail":0,"total":0,"skipped":1}\n')
  quit(status = 0L) }

.owd <- getwd()   # 라이브러리가 로드 시 setwd(ROOT) 한다 — 배터리의 cwd 를 되돌려 준다
suppressMessages(source(file.path(CODE, "02_Infrastructure/ops/rf_lcode_mechanism_lib.R")))
suppressMessages(source(file.path(CODE, "02_Infrastructure/reinforcement/rf_block_design.R")))
suppressMessages(try(source(file.path(CODE, "02_Infrastructure/ops/rf_block_lcode.R")), silent = TRUE))
setwd(.owd)

# ★리졸버 부재는 **측정된 실패**여야 한다 — 그냥 부르면 R 이 에러로 죽고, 죽은 실행은
#   JSON 요약 줄을 안 내서 배터리 파서에게 '실패' 가 아니라 '없음' 으로 보인다.
#   없는 것은 grep 에도 안 걸리고 크래시로도 안 세어진다(2026-09-05 러너 이중화 교훈).
if (!exists("rf_next_block", mode = "function")) {
  ng("rf_next_block 부재 — 재료 생성기가 아직 정적 목록으로 다음 블록을 집는다"); fin()
}

PROG <- fromJSON(file.path(CODE, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
IDS  <- vapply(PROG$blocks, function(b) as.character(b$id),   character(1))
AXS  <- vapply(PROG$blocks, function(b) as.character(b$axis), character(1))
RISK <- IDS[AXS == "risk_overlay"][1]; COMB <- IDS[AXS == "combination"]
BID  <- IDS[1]        # 첫 블록 = 실측 사례의 자리(B1)
SNXT <- IDS[2]        # 선언 순서의 다음 = 구판이 내던 답(B2)

# ── ⓪ 전제 — 두 순서가 갈리지 않으면 이 검사는 공허하다 ──────────────────────
#   격자를 재편해 선언 순서가 이미 위험 축을 2번째로 두면 아래 단정은 "고쳤다" 가 아니라
#   "원래 같다" 를 재는 것이 된다. 통과로 위장시키지 않고 skip 으로 드러낸다.
if (is.na(RISK) || identical(SNXT, RISK))
  skip(sprintf("선언 순서가 이미 위험 축을 2번째로 둔다(%s) - 갈릴 여지 없음",
               paste(IDS, collapse = ">")))
if (!(RISK %in% RFBD_BLOCKS) || !(SNXT %in% RFBD_BLOCKS))
  skip("두 축 중 하나가 설계 대상 블록이 아니다 - 카탈로그 대조 불가")
ok(sprintf("⓪ 전제 - 선언 %s (%s 다음 %s) vs 위험 축 %s: 갈릴 여지 있음",
           paste(IDS, collapse = ">"), BID, SNXT, RISK))

# 카탈로그가 실제로 갈리는지도 전제다 — 같으면 "어느 것을 줬나" 를 못 가른다
.cid <- function(b) vapply(rfbd_catalog(b, CODE), function(x) as.character(x$id), character(1))
ID_R <- setdiff(.cid(RISK), .cid(SNXT)); ID_S <- setdiff(.cid(SNXT), .cid(RISK))
if (!length(ID_R) || !length(ID_S))
  skip("두 블록 카탈로그가 서로 배타적인 id 를 안 가진다 - 대조 불가")

# ── 픽스처 (실재하지 않는 base_id — 원장·L-code·설계 캐시 무매치로 결정론) ────
FIX   <- "RP_TEST_MATERIALS_NEXT_FIXTURE"
ADAPT <- c(BID, RISK, setdiff(IDS[-1L], c(RISK, COMB)), COMB)
#   ★표의 셀 코드와 attempts 의 cell_code 는 생산에서 같은 출처(essence$cell_code)라
#     항상 일치한다 — 픽스처도 그 배치를 지킨다(어긋나면 lcm_materials 의 ide[[cd]] 가
#     "subscript out of bounds" 로 죽어 결함이 아니라 픽스처를 재게 된다).
mk <- function(cg, cl, blk = BID) lapply(1:5, function(i)
  list(n = i, grade = c("B", "C", "C", "C", "C")[i], cell_code = sprintf("%s_%d", blk, i),
       essence = list(cell_code = sprintf("%s_%d", blk, i),
                      port_t = c(2.280, 1.000, 0.800, 0.396, 0.700)[i],
                      cagr = cg, calmar = cl, mdd = 0.57, oos_retention = -0.239)))
# 적응 규칙을 켜는 실측값 = 실제 사례 그대로 (CAGR 0.207 >= 0.16 · Calmar 0.364 < 0.64)
e_dec  <- list(base_id = FIX, base_artifacts = "", paper_key = "FIXTURE", base_grade = "C",
               attempts = mk(0.207, 0.364))                                    # 미등록 창
e_led  <- c(e_dec, list(block_order = as.list(ADAPT)))                          # 원장 등록
e_flat <- list(base_id = FIX, base_artifacts = "", paper_key = "FIXTURE", base_grade = "C",
               attempts = mk(0.100, 0.300))                                    # 규칙 미발화

TAB0 <- data.table(n = 1:5, code = sprintf("%s_%d", BID, 1:5),
                   grade = c("B", "C", "C", "C", "C"),
                   port_t = c(2.280, 1.000, 0.800, 0.396, 0.700), inherited = FALSE,
                   sr = 0.9, cagr = 0.207, mdd = 0.57, calmar = 0.364, oos = -0.239)

# ── 재료를 실제로 생성한다 — 원장/로그 무변경 ────────────────────────────────
#   rf_notify_table 은 lcm_materials 가 `source(..., local = TRUE)` 로 **자기 프레임에**
#   정의하므로 바깥 스텁으로는 못 가린다. source 자체를 가로채 그 프레임에 덮어쓴다.
#   같은 자리에서 rf_next_block 도 갈아끼울 수 있다 = 위반 주입 지점.
run_materials <- function(entry, block = BID, inject = NULL, tab = TAB0) {
  out <- tempfile(fileext = ".txt"); on.exit(unlink(out, force = TRUE), add = TRUE)
  env <- new.env(parent = globalenv())
  env$ROOT    <- CODE                       # 코드 루트 = 재는 대상(데이터 루트와 구분)
  env$.mx_log <- function(...) invisible(NULL)
  env$source  <- function(file, local = FALSE, ...) {
    pf <- parent.frame()
    base::source(file, local = pf, ...)
    if (grepl("rf_auto_notify", file, fixed = TRUE))
      assign("rf_notify_table",
             function(bid) list(entry = entry, tab = tab, used = 5L, maxa = 25L), envir = pf)
    if (!is.null(inject) && grepl("rf_block_lcode", file, fixed = TRUE))
      assign("rf_next_block", inject, envir = pf)
    invisible(NULL)
  }
  f <- lcm_materials; environment(f) <- env
  f(entry$base_id, block, out)
  readLines(out, warn = FALSE)
}
head_of <- function(L) { h <- grep("^## 다음 블록", L, value = TRUE); if (length(h)) h[1] else "" }
hits    <- function(ids, body) any(vapply(ids, function(i) grepl(i, body, fixed = TRUE), logical(1)))

# ── ① 미등록 창에서 적응 축을 지목한다 ★실측 사례가 정확히 이 창이다 ─────────
L1 <- tryCatch(run_materials(e_dec),
               error = function(e) { writeLines(paste("  [materials]", conditionMessage(e)))
                                     character(0) })
if (length(L1) && grepl(sprintf("다음 블록 = %s\\b", RISK), head_of(L1)))
  ok(sprintf("① 미등록 창 재도출 - 재료가 %s 를 지목 (구판은 %s)", RISK, SNXT)) else
  ng("① 미등록 창에서 적응 축을 못 읽는다", if (length(L1)) head_of(L1) else "재료 없음")

# ── ② 지목만으로는 부족하다 — **그 축의 카탈로그**를 줘야 설계가 성립한다 ────
#   실측 사고의 실제 피해가 여기였다: 재료가 rfbd_catalog("B2") 를 넘겼다.
b1 <- paste(L1, collapse = "\n")
if (hits(ID_R, b1) && !hits(ID_S, b1))
  ok(sprintf("② 카탈로그도 %s 것이다 (%s 전용 id 0건)", RISK, SNXT)) else
  ng("② 카탈로그가 어긋난다", sprintf("%s전용=%s %s전용=%s",
                                      RISK, hits(ID_R, b1), SNXT, hits(ID_S, b1)))

# ── ③ 원장에 등록된 순서가 이긴다 (덮어쓰기 금지라 이게 사실이다) ────────────
L3 <- tryCatch(run_materials(e_led), error = function(e) character(0))
if (length(L3) && grepl(sprintf("다음 블록 = %s\\b", RISK), head_of(L3)))
  ok(sprintf("③ 원장 block_order 우선 - %s", RISK)) else
  ng("③ 원장 순서 미반영", if (length(L3)) head_of(L3) else "재료 없음")

# ── ④ 과교정 금지 — 규칙이 안 서면 선언 순서 그대로 ──────────────────────────
L4 <- tryCatch(run_materials(e_flat), error = function(e) character(0))
if (length(L4) && grepl(sprintf("다음 블록 = %s\\b", SNXT), head_of(L4)))
  ok(sprintf("④ 규칙 미발화 시 선언 순서 유지 - %s", SNXT)) else
  ng("④ 과교정 - 규칙이 안 섰는데 순서가 바뀌었다", if (length(L4)) head_of(L4) else "재료 없음")

# ── ⑤ 격자 소진 — 마지막 블록 뒤는 "설계를 내지 마라" ────────────────────────
LAST  <- ADAPT[length(ADAPT)]
TAB_L <- copy(TAB0)[, code := sprintf("%s_%d", LAST, 1:5)]
e_last <- c(list(base_id = FIX, base_artifacts = "", paper_key = "FIXTURE", base_grade = "C",
                 attempts = mk(0.207, 0.364, LAST)), list(block_order = as.list(ADAPT)))
L5 <- tryCatch(run_materials(e_last, block = LAST, tab = TAB_L),
               error = function(e) { writeLines(paste("  [materials]", conditionMessage(e)))
                                     character(0) })
if (length(L5) && any(grepl("다음 블록: 없음\\(마지막 블록\\)", L5)))
  ok("⑤ 마지막 블록 뒤 = 설계 없음") else
  ng("⑤ 마지막 블록 뒤에 설계 대상이 있다", if (length(L5)) head_of(L5) else "재료 없음")

# ── ⑥ 위반 주입 — 구판(정적 목록) 리졸버를 소비 지점에 꽂으면 ①②가 붉어져야 한다 ──
#   여전히 적응 축이 나오면 ①② 는 아무것도 안 재는 단정이다.
old_resolver <- function(entry, bid, prog, root = CODE) {   # 구판 재현 (2026-09-05 이전)
  .ord <- as.character(unlist(entry$block_order %||% list()))
  if (!length(.ord)) .ord <- IDS                            # ← 정적 목록 폴백 = 그 결함
  .k <- match(bid, .ord)
  list(id = if (!is.na(.k) && .k < length(.ord)) .ord[.k + 1L] else NULL,
       order = .ord, src = "program")
}
L6 <- tryCatch(run_materials(e_dec, inject = old_resolver), error = function(e) character(0))
b6 <- paste(L6, collapse = "\n")
if (length(L6) && grepl(sprintf("다음 블록 = %s\\b", SNXT), head_of(L6)) && hits(ID_S, b6))
  ok(sprintf("⑥ 위반 주입 - 구판 리졸버는 %s 와 그 카탈로그를 낸다 (①② 가 실제로 갈린다)", SNXT)) else
  ng("⑥ 위반 주입이 안 잡힌다 - ①② 는 죽은 단정이다",
     if (length(L6)) head_of(L6) else "재료 없음")

# ── ⑦ 배선 — 신판 호출이 **있고** 구판 정적 목록이 **없다** (주석 제외) ──────
#   ★한 방향만 보면 못 잡는다: 구판 제거만 재면 신판 부재를 놓치고(없는 것은 grep 에
#     안 걸린다), 신판 존재만 재면 구판이 남아 둘이 갈린 채 공존한다(러너 이중화 전례).
src <- paste(sub("#.*$", "",
                 readLines(file.path(CODE, "02_Infrastructure/ops/rf_lcode_mechanism_lib.R"),
                           warn = FALSE)), collapse = "\n")
has_new <- grepl("rf_next_block(E, block_id", src, fixed = TRUE)
has_old <- grepl("E$block_order %||% c(", src, fixed = TRUE)
if (has_new && !has_old) ok("⑦ 배선 - 재료 생성기가 리졸버를 부르고 정적 목록 폴백이 없다") else
  ng("⑦ 배선", sprintf("신판=%s 구판잔존=%s", has_new, has_old))

fin()
