#==============================================================================
# test_rf_materials_cell_lookup.R — lcm_materials() 의 칸 서술 조회가 **없는 이름에
#   죽지 않는가** (2026-09-05 · 양방향)
#
# 왜 생겼나: 구판은 처치 서술을
#     tr <- as.character(dsc[[cd]] %||% ide[[cd]] %||% "")
#   로 읽었다. `dsc` 는 list(rf_cell_desc)라 없는 이름에 NULL 을 돌려주지만, `ide` 는
#   setNames(vapply(...)) 로 만든 **이름 있는 원자 벡터**다. 원자 벡터의 `[[` 는 없는
#   이름에 NULL 이 아니라 `subscript out of bounds` 를 **던진다** — %||% 는 NULL 만
#   받으므로 저자가 의도한 "" 폴백이 원리상 도달 불가였다.
#
# 왜 안 보였나 — 두 코드 원천이 갈린다(실측 2026-09-05 reinforce_ledger_l1.json):
#     ide 이름 : a$cell_code %||% a$essence$cell_code        (등록 코드)
#     표  코드 : es$cell_code %||% sprintf("n%02d", a$n)     (측정 코드, rf_notify_table)
#   두 식은 499 시도 중 53건에서 갈렸다(09-05 09:30 스냅샷 460 시도 기준 51건 — 원 신고와
#   동일). 그 중 표에 실제로 뜨는 칸(essence$port_t 보유)이 8건. 오늘 안 죽는 이유는
#   갈린 코드들이 격자 안 코드라 `dsc` 가 먼저 답하기 때문이고, 격자 **밖** 코드
#   (B4_16~B4_20 · B5_21~B5_25 등 구번호 70칸)는 `ide` 하나가 떠받치고 있었다.
#   ⇒ dsc 가 한 칸만 놓치면 materials 생성이 통째로 죽고, rf_lcode_mechanism.sh:47 은
#     그것을 `materials_failed` 한 라벨로만 적고 exit 0 한다 — 크래시가 "재료 없음"으로
#     위장된다(라벨 하나가 여러 원인을 덮는 그 계통).
#
# ★양방향: 양성 대조(불일치·부재에서 완주) + 위반 주입(구판 조회를 **살아 있는 함수에**
#   꽂으면 붉어진다). 주입이 없으면 ①~④ 는 무엇을 재는지 스스로 증명하지 못한다.
# 부작용 없음: 원장·L-code·로그에 쓰지 않는다(rf_notify_table·rf_cell_desc·.mx_log·source
#   를 함수의 closure 에 꽂아 가로챈다 — 픽스처는 전부 메모리다).
#
# 코드 루트: self 최우선(--file= 로 자기 트리 도출) → QVEST_CODE_ROOT → QM_ROOT.
#   worktree 에서 돌린 초록이 main 을 재는 일을 막는다(코드 루트는 데이터 루트가 아니다).
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
LIB_REL <- "02_Infrastructure/ops/rf_lcode_mechanism_lib.R"
.self <- {
  .a <- commandArgs(FALSE); .f <- sub("^--file=", "", .a[grepl("^--file=", .a)])
  if (length(.f)) dirname(dirname(dirname(.f[1]))) else NA_character_
}
CODE <- Sys.getenv("QVEST_CODE_ROOT", "")
if (!nzchar(CODE)) {
  CODE <- if (!is.na(.self) && file.exists(file.path(.self, LIB_REL))) .self else ROOT
}

suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  writeLines(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else "")) }
fin <- function() {
  writeLines(""); writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
  cat(sprintf('{"test":"rf_materials_cell_lookup","pass":%d,"fail":%d,"total":%d,"skipped":0}\n',
              PASS, FAIL, PASS + FAIL))
  if (FAIL > 0L) quit(status = 1L) else quit(status = 0L)
}

# ── 라이브러리 적재 (lib 최상위가 setwd 한다 — cwd 복원) ─────────────────────
.cwd <- getwd()
suppressMessages(source(file.path(CODE, LIB_REL)))
setwd(.cwd)
if (!exists("lcm_materials", mode = "function")) {
  writeLines("  FAIL  lcm_materials 부재 — 라이브러리가 안 실렸다")
  FAIL <- 1L; fin()
}

# ── ⓪ 언어 사실(양성 대조) — 이 부류가 실재하는가 ────────────────────────────
#   list 는 NULL, 이름 있는 원자 벡터는 예외. 이게 아니면 아래 단정은 공허하다.
.l <- list(a = "x"); .v <- setNames(c("x"), c("a"))
.r_list <- tryCatch({ if (is.null(.l[["zz"]])) "NULL" else "value" }, error = function(e) "throw")
.r_vec  <- tryCatch({ if (is.null(.v[["zz"]])) "NULL" else "value" }, error = function(e) "throw")
if (identical(.r_list, "NULL") && identical(.r_vec, "throw")) {
  ok("⓪ 언어 사실 — list[[없는이름]]=NULL · 원자벡터[[없는이름]]=예외 (%||% 가 못 받는다)")
} else {
  ng("⓪ 언어 사실이 전제와 다르다 — 이 검사의 전제가 무너졌다",
     sprintf("list=%s vec=%s", .r_list, .r_vec))
}

# ── 픽스처 (전부 메모리 · 실재 base_id 아님) ─────────────────────────────────
FIX <- "RP_TEST_MATERIALS_LOOKUP_FIXTURE"
MEAS <- "B4_98"   # 측정 코드 = 표의 행 코드. 격자 밖이라 rf_cell_desc 가 모른다(70칸의 형태)
REG  <- "B4_24"   # 등록 코드 = 구판 ide 키. 둘이 갈린 실측 부류(B4_24 -> B5_17 등)
IDEA <- "결합 24 — 등록 코드와 측정 코드가 갈린 칸"
DSCT <- "모멘텀+저변동 | 동일가중 | K200∪KQ150"

mk_tab <- function(cd) data.table(n = 1L, code = cd, grade = "C", port_t = 0.400,
                                  inherited = FALSE, sr = 0.30, cagr = 0.050,
                                  mdd = 0.500, calmar = 0.100, oos = 0.200)
mk_ent <- function(reg, meas) list(
  base_id = FIX, paper_key = "PK_FIXTURE", base_grade = "C",
  block_order = list("B1", "B2", "B3", "B5", "B4"),   # B4 = 마지막 → 설계 분기 미진입
  attempts = list(list(n = 1L, cell_code = reg, idea = IDEA,
                       essence = list(cell_code = meas, port_t = 0.400))))

#' 함수의 closure 에 스텁을 꽂아 실행한다 — 원장·파일·로그 무변경.
#'   fn 을 바꿔 끼울 수 있게 인자로 받는다(⑦ 위반 주입이 같은 경로를 쓴다).
probe <- function(fn, ent, tab, dsc_map, block = "B4") {
  env <- new.env(parent = globalenv())
  env$source   <- function(...) invisible(NULL)   # 함수 안 local source 중화
  env$ROOT     <- tempdir()                       # l_code glob 무매치 → 결정론
  env$.mx_log  <- function(...) invisible(NULL)   # 실로그 오염 금지
  env$`%||%`   <- `%||%`
  env$rf_notify_table <- function(base_id) list(entry = ent, tab = tab, used = 1L, maxa = 25L)
  env$rf_cell_desc    <- function(base_id) dsc_map
  env$RFBD_BLOCKS        <- c("B1", "B2", "B3", "B5")
  env$rfbd_catalog       <- function(b, r) list()
  env$rfbd_action_status <- function(...) NULL
  env$rfbd_standing_picks <- function(...) character(0)
  # ★main 이식(2026-09-23) — worktree 원판은 다음 블록을 정적 목록(E$block_order)으로 골랐지만
  #   main 은 그 뒤 리졸버(rf_block_lcode.R::rf_next_block)로 옮겼다. 위에서 source 를 중화했으므로
  #   리졸버도 여기서 대역을 세운다 — 원장 등록 순서(src=ledger)만 읽는 실물과 같은 의미.
  #   이 대역이 없으면 ①~⑦ 이 조회 결함이 아니라 "could not find function rf_next_block" 을 잰다.
  #   다음 블록 판정 자체의 검사는 test_rf_materials_next_block.R 몫이다(여기서 재지 않는다).
  env$rf_next_block <- function(entry, bid, prog, root = NULL) {
    ord <- as.character(unlist(entry$block_order %||% list()))
    k <- match(bid, ord)
    list(id = if (!is.na(k) && k < length(ord)) ord[k + 1L] else NULL, order = ord, src = "ledger")
  }
  f <- fn; environment(f) <- env
  out <- file.path(tempdir(), sprintf("rf_mat_probe_%d.txt", as.integer(Sys.getpid())))
  on.exit(unlink(out, force = TRUE), add = TRUE)
  # 행 형식 = code | grade | PORT_t | CAGR | Calmar | MDD | 처치 (7필드).
  #   ★마지막 '|' 로 자르지 말 것 — 처치 서술 자체가 '|' 로 축을 나눈다(팩터|비중|유니버스).
  #   그렇게 자르면 dsc 우선 단정이 마지막 축 이름만 보고 붉어진다(2026-09-05 실측).
  .treat_of <- function(ln) {
    p <- strsplit(ln, " | ", fixed = TRUE)[[1]]
    if (length(p) < 7L) "" else trimws(paste(p[7:length(p)], collapse = " | "))
  }
  tryCatch({
    f(FIX, block, out)
    ln <- grep(sprintf("^%s ", tab$code[1]), readLines(out, warn = FALSE), value = TRUE)
    list(ok = TRUE, line = if (length(ln)) ln[1] else "",
         treat = if (length(ln)) .treat_of(ln[1]) else NA_character_)
  }, error = function(e) list(ok = FALSE, line = "", treat = NA_character_,
                              msg = conditionMessage(e)))
}

# ── ① 실측 부류 — 등록≠측정 · dsc 미보유에서 **완주**한다 ───────────────────
r1 <- probe(lcm_materials, mk_ent(REG, MEAS), mk_tab(MEAS), list())
if (isTRUE(r1$ok)) {
  ok(sprintf("① 등록(%s)≠측정(%s) · dsc 미보유에서 완주 — 처치 '%s'",
             REG, MEAS, substr(r1$treat %||% "", 1, 40)))
} else {
  ng("① 구판 부류에서 여전히 죽는다", r1$msg %||% "")
}

# ── ② 두 지도 모두 부재 → "" 로 떨어진다(저자가 의도한 폴백) ─────────────────
#   표와 attempts 가 어긋난 경우(코드가 어느 지도에도 없다). 죽지 않고 빈칸이어야 한다.
r2 <- probe(lcm_materials, mk_ent(REG, MEAS), mk_tab("B4_97"), list())
if (isTRUE(r2$ok) && identical(r2$treat, "")) {
  ok("② 두 지도 모두 부재 → 처치 빈칸(예외 아님)")
} else if (isTRUE(r2$ok)) {
  ng("② 부재인데 빈칸이 아니다", sprintf("처치='%s'", r2$treat %||% "NA"))
} else {
  ng("② 부재에서 죽는다 — %||% 폴백이 여전히 도달 불가", r2$msg %||% "")
}

# ── ③ 기존 동작 보존 — dsc 가 있으면 dsc 가 이긴다 ──────────────────────────
r3 <- probe(lcm_materials, mk_ent(REG, MEAS), mk_tab(MEAS), setNames(list(DSCT), MEAS))
if (isTRUE(r3$ok) && identical(r3$treat, DSCT)) {
  ok("③ dsc 우선 보존 — 격자 서술이 이긴다")
} else {
  ng("③ dsc 우선이 깨졌다", sprintf("처치='%s'", r3$treat %||% (r3$msg %||% "NA")))
}

# ── ④ 기존 동작 보존 — dsc 미보유 시 시도 서술(idea)이 나온다 ───────────────
#   폴백을 "" 로만 만들면 조용해지지만 정보가 사라진다. 이름이 있을 때는 값이 나와야 한다.
if (isTRUE(r1$ok) && identical(r1$treat, IDEA)) {
  ok("④ ide 폴백 보존 — 이름이 있으면 시도 서술이 나온다")
} else {
  ng("④ ide 폴백이 값을 잃었다", sprintf("처치='%s'", r1$treat %||% "NA"))
}

# ── ⑤ 키 공간 정렬(배선) — 두 파일이 **같은 코드 식**을 쓰는가 ──────────────
#   여기서 갈리면 ①의 부류가 되살아난다. 구판 키 식 잔존도 함께 본다(양방향).
KEY <- 'cell_code %||% sprintf("n%02d", a$n)'
OLDKEY <- 'a$cell_code %||% (a$essence$cell_code'
.rd <- function(p) paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
lib_src <- .rd(file.path(CODE, LIB_REL))
nty_src <- .rd(file.path(CODE, "02_Infrastructure/ops/rf_auto_notify.R"))
.k_lib <- grepl(KEY, lib_src, fixed = TRUE)
.k_nty <- grepl(KEY, nty_src, fixed = TRUE)
.k_old <- grepl(OLDKEY, lib_src, fixed = TRUE)
if (.k_lib && .k_nty && !.k_old) {
  ok("⑤ 키 정렬 — lcm_materials 와 rf_notify_table 이 같은 코드 식을 쓴다(구판 키 잔존 0)")
} else {
  ng("⑤ 키 식이 갈렸다 — 표에 있는데 지도에 없는 코드가 다시 생긴다",
     sprintf("lib=%s notify=%s 구판잔존=%s", .k_lib, .k_nty, .k_old))
}

# ── ⑥ 배선 양방향 — 구판 조회 부재 **AND** 가드 존재 ────────────────────────
#   ★한 방향만 보면 못 잡는다: 구판 제거만 재면 신판 부재를 놓친다(없는 것은 grep 에
#     안 걸린다). 파일 텍스트가 아니라 **적재된 함수**를 본다 — 주석은 실행이 아니다.
fsrc <- paste(deparse(lcm_materials, width.cutoff = 500L), collapse = "\n")
has_old <- grepl("ide[[cd]]", fsrc, fixed = TRUE)
has_new <- grepl(".look1(ide, cd)", fsrc, fixed = TRUE)
if (has_new && !has_old) {
  ok("⑥ 배선 — 가드된 조회가 있고 원자벡터 [[ 조회가 없다")
} else {
  ng("⑥ 배선", sprintf("가드=%s 구판잔존=%s", has_new, has_old))
}

# ── ⑦ 위반 주입 — 살아 있는 함수에 구판 조회를 꽂으면 ② 가 붉어져야 한다 ────
#   여전히 완주하면 ②는 아무것도 안 재는 단정이다(죽은 표적의 초록 = 커버리지 구멍).
NEWX <- ".look1(dsc, cd) %||% .look1(ide, cd)"
OLDX <- "dsc[[cd]] %||% ide[[cd]]"
if (!grepl(NEWX, fsrc, fixed = TRUE)) {
  ng("⑦ 위반 주입 표적 부재 — 주입할 자리를 못 찾았다(검사가 죽었다)", NEWX)
} else {
  bad_src <- sub(NEWX, OLDX, fsrc, fixed = TRUE)
  bad_fn  <- tryCatch(eval(parse(text = bad_src)), error = function(e) NULL)
  if (!is.function(bad_fn)) {
    ng("⑦ 위반 주입 재파싱 실패 — 주입 경로가 깨졌다")
  } else {
    r7 <- probe(bad_fn, mk_ent(REG, MEAS), mk_tab("B4_97"), list())
    if (!isTRUE(r7$ok) && grepl("subscript out of bounds", r7$msg %||% "", fixed = TRUE)) {
      ok("⑦ 위반 주입 — 구판 조회는 subscript out of bounds 로 죽는다(② 가 실제로 갈린다)")
    } else if (!isTRUE(r7$ok)) {
      ng("⑦ 위반 주입이 다른 이유로 죽었다 — ② 가 재는 축이 아니다", r7$msg %||% "")
    } else {
      ng("⑦ 위반 주입이 안 잡힌다 — ② 는 죽은 단정이다", sprintf("처치='%s'", r7$treat %||% "NA"))
    }
  }
}

fin()
