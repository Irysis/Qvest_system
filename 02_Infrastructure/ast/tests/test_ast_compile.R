#==============================================================================
# test_ast_compile.R — AST v1.1 컴파일러 단위 테스트 (합성 소형 패널)
#
# 범위: 연산자별 known-value + AS_OF 정렬(가용시각 위반 배제) + 검증기 + manifest.
# ⚠ 기존 factor DB parity 대조는 본 단계에서 하지 않음 (Q4 재빌드 진행 중 —
#    Phase 2 통합 에이전트 소관, 임무 S2b 명시 제외).
#
# 실행: cd 02_Infrastructure/ast && Rscript -e "source('tests/test_ast_compile.R')"
#==============================================================================

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/ast/ast_compile.R"))

#------------------------------------------------------------------------------
# 테스트 하네스
#------------------------------------------------------------------------------
.RESULTS <- new.env(); .RESULTS$rows <- list()

chk <- function(name, cond) {
  ok <- isTRUE(cond)
  .RESULTS$rows[[length(.RESULTS$rows) + 1L]] <- list(name = name, ok = ok)
  cat(sprintf("[%s] %s\n", if (ok) "PASS" else "FAIL", name))
  invisible(ok)
}

chk_err <- function(name, expr, pattern = NULL) {
  e <- tryCatch({ force(expr); NULL }, error = function(err) err)
  ok <- !is.null(e)
  if (ok && !is.null(pattern)) ok <- grepl(pattern, conditionMessage(e), fixed = TRUE)
  if (!ok && !is.null(e)) cat(sprintf("  (err msg: %s)\n", conditionMessage(e)))
  chk(name, ok)
}

num_eq <- function(a, b, tol = 1e-10) {
  if (length(a) != length(b)) return(FALSE)
  same_na <- is.na(a) == is.na(b)
  ok <- ifelse(is.na(a) | is.na(b), same_na, abs(a - b) < tol)
  all(ok)
}

# 소형 패널 생성기: 단일/다중 ticker, avail_ts 기본 = Date
mkp <- function(dates, ticker, values, avail = NULL) {
  d <- as.Date(dates)
  dt <- data.table(Date = d, Ticker = ticker, value = values)
  dt[, avail_ts := if (is.null(avail)) d else as.Date(avail)]
  setorder(dt, Ticker, Date)
  dt[]
}

D <- function(s) as.Date(s)
d10 <- as.Date("2026-01-01") + 0:9      # 10 연속일 (합성 — 거래일 개념 불요)

#------------------------------------------------------------------------------
# T1~T5: 횡단면 연산자 known-value
#------------------------------------------------------------------------------
cat("\n== 횡단면 연산자 ==\n")

x1 <- rbind(mkp("2026-01-05", "AAA", 10), mkp("2026-01-05", "BBB", 20), mkp("2026-01-05", "CCC", 30))
r1 <- op_cs_rank(x1)
chk("T1a CS_RANK (10,20,30) -> (0, .5, 1)",
    num_eq(r1[order(Ticker)]$value, c(0, 0.5, 1)))

x1n <- rbind(mkp("2026-01-05", "AAA", 10), mkp("2026-01-05", "BBB", NA_real_), mkp("2026-01-05", "CCC", 30))
r1n <- op_cs_rank(x1n)
chk("T1b CS_RANK NA 보존 + non-NA만 랭크 (10,NA,30) -> (0,NA,1)",
    num_eq(r1n[order(Ticker)]$value, c(0, NA, 1)))
chk("T1c CS_RANK 출력범위 [0,1]",
    r1n[!is.na(value), all(value >= 0 & value <= 1)])
r1s <- op_cs_rank(mkp("2026-01-05", "AAA", 7))
chk("T1d CS_RANK n=1 -> 0.5", num_eq(r1s$value, 0.5))

x2 <- rbind(mkp("2026-01-05", "AAA", 1), mkp("2026-01-05", "BBB", 2), mkp("2026-01-05", "CCC", 3))
chk("T2a CS_ZSCORE (1,2,3) -> (-1,0,1)",
    num_eq(op_cs_zscore(x2)[order(Ticker)]$value, c(-1, 0, 1)))
x2c <- rbind(mkp("2026-01-05", "AAA", 5), mkp("2026-01-05", "BBB", 5), mkp("2026-01-05", "CCC", 5))
chk("T2b CS_ZSCORE sd=0 -> NA", all(is.na(op_cs_zscore(x2c)$value)))

x3 <- rbindlist(lapply(1:5, function(i) mkp("2026-01-05", sprintf("T%02d", i), i)))
r3 <- op_cs_winsorize(x3, p = 0.25)
chk("T3 CS_WINSORIZE p=.25 (1..5) -> (2,2,3,4,4)",
    num_eq(r3[order(Ticker)]$value, c(2, 2, 3, 4, 4)))

x4 <- rbind(mkp("2026-01-05", "AAA", 2), mkp("2026-01-05", "BBB", 4), mkp("2026-01-05", "CCC", 9))
chk("T4 CS_DEMEAN (2,4,9) -> (-3,-1,4)",
    num_eq(op_cs_demean(x4)[order(Ticker)]$value, c(-3, -1, 4)))

x5 <- rbind(mkp("2026-01-05", "AAA", 1), mkp("2026-01-05", "BBB", 3),
            mkp("2026-01-05", "CCC", 10), mkp("2026-01-05", "DDD", 20))
g5 <- rbind(mkp("2026-01-05", "AAA", "GA"), mkp("2026-01-05", "BBB", "GA"),
            mkp("2026-01-05", "CCC", "GB"), mkp("2026-01-05", "DDD", "GB"))
r5 <- op_cs_neutralize(x5, g5)
chk("T5a CS_NEUTRALIZE 그룹 demean (1,3|10,20) -> (-1,1,-5,5)",
    num_eq(r5[order(Ticker)]$value, c(-1, 1, -5, 5)))
g5m <- rbind(mkp("2026-01-05", "AAA", "GA"), mkp("2026-01-05", "BBB", "GA"),
             mkp("2026-01-05", "CCC", "GB"))   # DDD 그룹 결측
r5m <- op_cs_neutralize(x5, g5m)
chk("T5b CS_NEUTRALIZE 그룹 결측 -> NA", is.na(r5m[Ticker == "DDD"]$value))

#------------------------------------------------------------------------------
# T6~T13: 시계열 연산자 known-value (+ shift 방향)
#------------------------------------------------------------------------------
cat("\n== 시계열 연산자 ==\n")

s5 <- mkp(d10[1:5], "AAA", c(1, 2, 3, 4, 5))

r6 <- op_ts_lag(s5, 1L)
chk("T6a TS_LAG k=1 방향: value[t] = x[t-1] -> (NA,1,2,3,4)",
    num_eq(r6$value, c(NA, 1, 2, 3, 4)))
chk("T6b TS_LAG avail_ts emission-time: 행 자신의 avail 유지 (lag 소거 차단)",
    all(r6$avail_ts == s5$avail_ts))

chk("T7 TS_DELTA k=1 (1..5) -> (NA,1,1,1,1)",
    num_eq(op_ts_delta(s5, 1L)$value, c(NA, 1, 1, 1, 1)))

chk("T8 TS_MEAN w=3 (1..5) -> (NA,NA,2,3,4)",
    num_eq(op_ts_mean(s5, 3L)$value, c(NA, NA, 2, 3, 4)))

chk("T9 TS_STD w=3 (1..5) -> (NA,NA,1,1,1)",
    num_eq(op_ts_std(s5, 3L)$value, c(NA, NA, 1, 1, 1)))

s10 <- mkp(d10[1:4], "AAA", c(3, 1, 2, 5))
r10 <- op_ts_rank(s10, 3L)
chk("T10a TS_RANK w=3: 창(3,1,2) 내 2 -> 0.5 / 창(1,2,5) 내 5 -> 1",
    num_eq(r10$value, c(NA, NA, 0.5, 1)))
r10t <- op_ts_rank(mkp(d10[1:3], "AAA", c(5, 5, 5)), 3L)
chk("T10b TS_RANK 전값 동률 -> 0.5", num_eq(r10t$value, c(NA, NA, 0.5)))

s11 <- mkp(d10[1:4], "AAA", c(4, 2, 7, 1))
chk("T11a TS_MIN w=2 -> (NA,2,2,1)", num_eq(op_ts_min(s11, 2L)$value, c(NA, 2, 2, 1)))
chk("T11b TS_MAX w=2 -> (NA,4,7,7)", num_eq(op_ts_max(s11, 2L)$value, c(NA, 4, 7, 7)))
chk("T11c TS_SUM w=2 -> (NA,6,9,8)", num_eq(op_ts_sum(s11, 2L)$value, c(NA, 6, 9, 8)))

xa <- mkp(d10[1:5], "AAA", c(1, 2, 3, 4, 5))
ya <- mkp(d10[1:5], "AAA", c(2, 4, 6, 8, 10))     # y = 2x
yb <- mkp(d10[1:5], "AAA", c(5, 4, 3, 2, 1))      # y = -x + 6
yc <- mkp(d10[1:5], "AAA", c(7, 7, 7, 7, 7))      # 상수
r12a <- op_ts_corr(xa, ya, 3L)
chk("T12a TS_CORR w=3 완전 양상관 -> 1", num_eq(r12a$value, c(NA, NA, 1, 1, 1)))
r12b <- op_ts_corr(xa, yb, 3L)
chk("T12b TS_CORR 완전 음상관 -> -1", num_eq(r12b$value, c(NA, NA, -1, -1, -1)))
r12c <- op_ts_corr(xa, yc, 3L)
chk("T12c TS_CORR 상수측 sd=0 -> NA", all(is.na(r12c$value)))

# TS_BETA(x,y): x = 2y + 3 정확 -> 기울기 2
yd <- mkp(d10[1:5], "AAA", c(1, 2, 3, 4, 5))
xd <- mkp(d10[1:5], "AAA", 2 * c(1, 2, 3, 4, 5) + 3)
r13 <- op_ts_beta(xd, yd, 3L)
chk("T13 TS_BETA w=3: x=2y+3 -> 2", num_eq(r13$value, c(NA, NA, 2, 2, 2)))

#------------------------------------------------------------------------------
# T14~T19: 산술/조건 연산자
#------------------------------------------------------------------------------
cat("\n== 산술/조건 연산자 ==\n")

pa <- mkp(d10[1:2], "AAA", c(1, 2))
pb <- mkp(d10[1:2], "AAA", c(10, 20))
PN <- function(p) list(kind = "panel", value = p)
CN <- function(v) list(kind = "const", value = v)

chk("T14a ADD panel+panel", num_eq(.arith2(PN(pa), PN(pb), `+`)$value, c(11, 22)))
chk("T14b SUB panel-const", num_eq(.arith2(PN(pa), CN(0.5), `-`)$value, c(0.5, 1.5)))
chk("T14c SUB const-panel (순서)", num_eq(.arith2(CN(10), PN(pa), `-`)$value, c(9, 8)))
chk("T14d MUL panel*const", num_eq(.arith2(PN(pa), CN(3), `*`)$value, c(3, 6)))

pnum <- mkp(d10[1:2], "AAA", c(1, 2))
pden <- mkp(d10[1:2], "AAA", c(0, 4))
r15 <- .arith2(PN(pnum), PN(pden), op_div_fn(1e-12))
chk("T15 DIV 0-분모 -> NA (Inf 금지), 정상 -> 0.5", num_eq(r15$value, c(NA, 0.5)))

pl <- mkp(d10[1:3], "AAA", c(exp(1), 0, -3))
chk("T16a LOG: (e,0,-3) -> (1,NA,NA)", num_eq(op_log(pl)$value, c(1, NA, NA)))
chk("T16b SQRT: (4,-1) -> (2,NA)",
    num_eq(op_sqrt(mkp(d10[1:2], "AAA", c(4, -1)))$value, c(2, NA)))
chk("T16c SIGN: (-2,0,7) -> (-1,0,1)",
    num_eq(op_sign(mkp(d10[1:3], "AAA", c(-2, 0, 7)))$value, c(-1, 0, 1)))
chk("T16d ABS: (-3) -> 3", num_eq(op_abs(mkp(d10[1], "AAA", -3))$value, 3))

chk("T17 CLIP [-1,1]: (-5,0.5,3) -> (-1,0.5,1)",
    num_eq(op_clip(mkp(d10[1:3], "AAA", c(-5, 0.5, 3)), -1, 1)$value, c(-1, 0.5, 1)))

pc <- mkp(d10[1:3], "AAA", c(1, -1, NA))
r18 <- op_if_else(PN(pc), CN(10), CN(20))
chk("T18 IF_ELSE cond(1,-1,NA), a=10, b=20 -> (10,20,NA)",
    num_eq(r18$value, c(10, 20, NA)))

px <- mkp(d10[1:2], "AAA", c(7, 8))
pw <- mkp(d10[1:2], "AAA", c(1, 0))
chk("T19 WHERE cond(1,0) -> (7,NA)", num_eq(op_where(px, pw)$value, c(7, NA)))

#------------------------------------------------------------------------------
# T20~T21: 검증기 — 𝒪 밖 연산자 / LEAD / 음수 lag / escape 계약
#------------------------------------------------------------------------------
cat("\n== 검증기 ==\n")

LIB <- ast_load_library()
leaf_px <- list(type = "leaf", source = "rawdata", field = "Close")

chk_err("T20a 𝒪 밖 연산자 TS_SKEW 거부",
        ast_validate(list(type = "op", op = "TS_SKEW", args = list(leaf_px)), LIB), "𝒪 밖")
chk_err("T20b LEAD 하드 거부 (라이브러리 조회 전)",
        ast_validate(list(type = "op", op = "LEAD", args = list(leaf_px)), LIB), "LEAD/FUTURE")
chk_err("T20c FUTURE_MEAN 하드 거부",
        ast_validate(list(type = "op", op = "FUTURE_MEAN", args = list(leaf_px)), LIB), "LEAD/FUTURE")
chk_err("T20d TS_LAG k=-1 (lead 등가) 거부",
        ast_validate(list(type = "op", op = "TS_LAG", args = list(leaf_px),
                          params = list(k = -1)), LIB))
chk_err("T20e TS_LAG k=0 거부 (min 1)",
        ast_validate(list(type = "op", op = "TS_LAG", args = list(leaf_px),
                          params = list(k = 0)), LIB))
chk_err("T20f CS_WINSORIZE p=0.6 상한 위반",
        ast_validate(list(type = "op", op = "CS_WINSORIZE", args = list(leaf_px),
                          params = list(p = 0.6)), LIB))
chk_err("T20g AS_OF extra_lag_days=-1 거부",
        ast_validate(list(type = "op", op = "AS_OF", args = list(leaf_px),
                          params = list(extra_lag_days = -1)), LIB))
chk_err("T20h 미선언 파라미터 오타 가드 (TS_MEAN win=)",
        ast_validate(list(type = "op", op = "TS_MEAN", args = list(leaf_px),
                          params = list(win = 3)), LIB), "미선언 파라미터")
chk_err("T20i arity 불일치 (ADD 인자 1개)",
        ast_validate(list(type = "op", op = "ADD", args = list(leaf_px)), LIB), "arity")
chk_err("T20j 전 인자 상수 거부",
        ast_validate(list(type = "op", op = "ADD",
                          args = list(list(type = "const", value = 1),
                                      list(type = "const", value = 2))), LIB), "상수")
chk_err("T20k VINTAGE 는 직접 리프만",
        ast_validate(list(type = "op", op = "VINTAGE",
                          args = list(list(type = "op", op = "ABS", args = list(leaf_px))),
                          params = list(tag = "pinA")), LIB), "직접 리프")
chk_err("T20l 미지 리프 source 거부",
        ast_validate(list(type = "leaf", source = "my_csv", field = "x"), LIB), "미등재")
chk("T20m 정상 AST 통과",
    !is.null(tryCatch({ ast_validate(list(type = "op", op = "CS_RANK", args = list(leaf_px)), LIB); TRUE },
                      error = function(e) NULL)))

esc_bad <- list(type = "leaf", class = "STORED_SCORE", field = "insider_score",
                contract = list(store_build_hash = "abc"))
chk_err("T21a STORED_SCORE provenance 3필드+parity 누락 거부",
        ast_validate(esc_bad, LIB), "계약 필드 누락")
esc_ok <- list(type = "leaf", class = "STORED_SCORE", field = "insider_score",
               contract = list(store_build_hash = "abc", generator_code_path = "x.R",
                               generated_at = "2026-07-25", production_parity_verified = TRUE,
                               avail_offset_days = 0))
chk("T21b STORED_SCORE 계약 완비 통과",
    !is.null(tryCatch({ ast_validate(esc_ok, LIB); TRUE }, error = function(e) NULL)))
chk_err("T21c MODEL_SCORE 학습창 계약 누락 거부",
        ast_validate(list(type = "leaf", class = "MODEL_SCORE", field = "lgbm_score",
                          contract = list(model_sha = "z")), LIB), "계약 필드 누락")

#------------------------------------------------------------------------------
# T22~T26: AS_OF 정렬 (가용시각 위반 데이터가 조인에서 배제되는지) — 핵심
#------------------------------------------------------------------------------
cat("\n== AS_OF 정렬 (컴파일러-소유 조인) ==\n")

mk_provider <- function(panels) {
  function(leaf, ctx) {
    key <- leaf$field
    if (!is.null(leaf$vintage)) key <- paste0(key, "@", leaf$vintage)
    p <- panels[[key]]
    if (is.null(p)) stop("test provider: 미지 리프 ", key)
    copy(p)
  }
}

# T22: 지연 가용 관측 배제. fund: (01-05 obs, avail 01-06, v=100) / (01-10 obs, avail 01-20, v=200)
fund <- rbind(mkp("2026-01-05", "AAA", 100, avail = "2026-01-06"),
              mkp("2026-01-10", "AAA", 200, avail = "2026-01-20"))
prov22 <- mk_provider(list(fund = fund))
ast22 <- list(type = "leaf", source = "rawdata", field = "fund")  # source 는 형식 통과용 — provider 가 합성 공급
r22 <- ast_compile(ast22, eval_dates = D(c("2026-01-15", "2026-01-25")), provider = prov22)
v22 <- r22$panel[order(Date)]$value
chk("T22a AS_OF: eval 01-15 -> avail 01-20 관측 배제, 01-06 가용분(100) 선택",
    num_eq(v22[1], 100))
chk("T22b AS_OF: eval 01-25 -> avail 01-20 가용분(200) 선택",
    num_eq(v22[2], 200))

# T23: 횡단면 연산의 가용시각 상향 전파 — 한 종목 지연이 전 단면 avail 을 끌어올림
cs_leaf <- rbind(mkp("2026-01-10", "AAA", 1, avail = "2026-01-10"),
                 mkp("2026-01-10", "BBB", 2, avail = "2026-01-20"))
prov23 <- mk_provider(list(cs = cs_leaf))
ast23 <- list(type = "op", op = "CS_RANK",
              args = list(list(type = "leaf", source = "rawdata", field = "cs")))
r23 <- ast_compile(ast23, eval_dates = D(c("2026-01-15", "2026-01-25")), provider = prov23)
chk("T23a CS avail 전파: eval 01-15 (BBB 미가용) -> 단면 랭크 전체 NA",
    all(is.na(r23$panel[Date == D("2026-01-15")]$value)))
chk("T23b CS avail 전파: eval 01-25 -> (0,1) 산출",
    num_eq(r23$panel[Date == D("2026-01-25")][order(Ticker)]$value, c(0, 1)))

# T24: 이종 주기 이항 조인 = AS_OF LOCF (+ staleness 상한)
feb <- seq(D("2026-02-01"), D("2026-02-28"), by = "day")
daily_p <- mkp(feb, "AAA", rep(1, length(feb)))
monthly_p <- rbind(mkp("2026-01-31", "AAA", 10), mkp("2026-02-28", "AAA", 20))
prov24 <- mk_provider(list(d = daily_p, m = monthly_p))
ast24 <- list(type = "op", op = "ADD",
              args = list(list(type = "leaf", source = "rawdata", field = "d"),
                          list(type = "leaf", source = "rawdata", field = "m")))
r24 <- ast_compile(ast24, eval_dates = feb, provider = prov24)
p24 <- r24$panel[order(Date)]
chk("T24a 이종주기 ADD: 2/1~2/27 = 1+10(1월말 LOCF) = 11",
    num_eq(unique(p24[Date < D("2026-02-28")]$value), 11))
chk("T24b 이종주기 ADD: 2/28 = 1+20(당일 가용) = 21",
    num_eq(p24[Date == D("2026-02-28")]$value, 21))
r24s <- ast_compile(ast24, eval_dates = feb, provider = prov24, join_max_staleness_days = 10)
p24s <- r24s$panel[order(Date)]
chk("T24c staleness 10d: 2/11부터 1월말 값 만기 -> NA",
    all(is.na(p24s[Date >= D("2026-02-11") & Date < D("2026-02-28")]$value)))
chk("T24d staleness 10d: 2/1~2/10 = 11 유지 + 2/28 = 21",
    num_eq(unique(p24s[Date <= D("2026-02-10")]$value), 11) &&
    num_eq(p24s[Date == D("2026-02-28")]$value, 21))

# T25: AS_OF extra_lag_days — 명시 보수화
asof_leaf <- mkp("2026-01-10", "AAA", 55)
prov25 <- mk_provider(list(al = asof_leaf))
ast25 <- list(type = "op", op = "AS_OF",
              args = list(list(type = "leaf", source = "rawdata", field = "al")),
              params = list(extra_lag_days = 5))
r25 <- ast_compile(ast25, eval_dates = D(c("2026-01-12", "2026-01-16")), provider = prov25)
v25 <- r25$panel[order(Date)]$value
chk("T25 AS_OF +5d: eval 01-12 -> NA (가용 01-15 전), 01-16 -> 55",
    is.na(v25[1]) && num_eq(v25[2], 55))

# T26: VINTAGE 태그가 provider 에 전달되는지 (핀 스냅샷 선택)
prov26 <- mk_provider(list("px@pinA" = mkp("2026-01-05", "AAA", 111),
                           "px" = mkp("2026-01-05", "AAA", 999)))
ast26 <- list(type = "op", op = "VINTAGE",
              args = list(list(type = "leaf", source = "rawdata", field = "px")),
              params = list(tag = "pinA"))
r26 <- ast_compile(ast26, eval_dates = D("2026-01-06"), provider = prov26)
chk("T26 VINTAGE tag=pinA -> 핀 패널(111) 로드 (현행 999 아님)",
    num_eq(r26$panel$value, 111))

# T26b: TS_LAG 의 AS_OF lag 소거 차단 (emission-time 의미론 회귀 테스트)
lagser <- mkp(d10[1:5], "AAA", c(1, 2, 3, 4, 5))
prov26b <- mk_provider(list(s = lagser))
ast26b <- list(type = "op", op = "TS_LAG",
               args = list(list(type = "leaf", source = "rawdata", field = "s")),
               params = list(k = 1))
r26b <- ast_compile(ast26b, eval_dates = d10[3], provider = prov26b)
chk("T26b TS_LAG AS_OF 소거 차단: eval=t3 신호 = x[t2]=2 (x[t3]=3 아님)",
    num_eq(r26b$panel$value, 2))

#------------------------------------------------------------------------------
# T27~T29: manifest / ast_features / 불변식
#------------------------------------------------------------------------------
cat("\n== manifest / ast_features ==\n")

# IF_ELSE(SIGN(TS_MEAN(ret,5)), CS_RANK(TS_MEAN(DIV(px, TS_LAG(px,1)),3)), 0)
leafP <- function(f) list(type = "leaf", source = "rawdata", field = f)
ast27 <- list(type = "op", op = "IF_ELSE", args = list(
  list(type = "op", op = "SIGN", args = list(
    list(type = "op", op = "TS_MEAN", args = list(leafP("ret")), params = list(window = 5)))),
  list(type = "op", op = "CS_RANK", args = list(
    list(type = "op", op = "TS_MEAN", params = list(window = 3), args = list(
      list(type = "op", op = "DIV", args = list(
        leafP("px"),
        list(type = "op", op = "TS_LAG", args = list(leafP("px")), params = list(k = 1)))))))),
  list(type = "const", value = 0)
))
ana27 <- ast_validate(ast27, LIB)
f27 <- ana27$features
chk("T27a node_count = 11", f27$node_count == 11L)
chk("T27b max_depth = 6", f27$max_depth == 6L)
chk("T27c conditional_op_count = 1", f27$conditional_op_count == 1L)
chk("T27d window_variety = 2 ({5,3})", f27$window_variety == 2L)
chk("T27e free_param_count = 4 (w5, w3, k1, const)", f27$free_param_count == 4L)
chk("T27f distinct_field_count = 2 ({ret, px})", f27$distinct_field_count == 2L)
chk("T27g escape_leaf_count = 0", f27$escape_leaf_count == 0L)
chk("T27h restatement_exposure = 2 (rawdata 기본 true)", f27$restatement_exposure == 2L)
hist27 <- ana27$history
px_id <- .leaf_id(leafP("px")); ret_id <- .leaf_id(leafP("ret"))
chk("T27i 소요 히스토리: px = 3 (w3-1 + k1), ret = 4 (w5-1)",
    hist27[[px_id]] == 3L && hist27[[ret_id]] == 4L)

# escape 리프 포함 features + 컴파일 manifest
ast28 <- list(type = "op", op = "CS_RANK", args = list(esc_ok))
prov28 <- mk_provider(list(insider_score = mkp(rep("2026-01-05", 2), c("AAA", "BBB"), c(0.2, 0.9))))
r28 <- ast_compile(ast28, eval_dates = D("2026-01-06"), provider = prov28)
mf <- r28$manifest
chk("T28a manifest escape_leaf_count = 1 + type STORED_SCORE",
    mf$ast_features$escape_leaf_count == 1L &&
    identical(mf$ast_features$escape_leaf_types[[1]], "STORED_SCORE"))
chk("T28b manifest operator_counts CS_RANK = 1", mf$operator_counts$CS_RANK == 1L)
chk("T28c manifest 리프 n_rows_loaded 기록 = 2", mf$leaves[[1]]$n_rows_loaded == 2L)
chk("T28d 출력 패널 표준형 (Date,Ticker,value) + grid 셀 수 일치",
    identical(names(r28$panel), c("Date", "Ticker", "value")) && nrow(r28$panel) == 2L)
chk("T28e manifest as_of 통계 (n_nonna=2)", mf$as_of$n_nonna == 2L)
chk("T28f manifest boundary = 자체합성 금지 명시",
    grepl("canonical_screen_bt", mf$boundary, fixed = TRUE))

# T29: 패널 불변식 — (Date,Ticker) 중복 / avail_ts < Date 거부
dup <- rbind(mkp("2026-01-05", "AAA", 1), mkp("2026-01-05", "AAA", 2))
prov29 <- mk_provider(list(dup = dup))
chk_err("T29a 리프 (Date,Ticker) 중복 거부",
        ast_compile(list(type = "leaf", source = "rawdata", field = "dup"),
                    eval_dates = D("2026-01-06"), provider = prov29), "중복")
bad_av <- mkp("2026-01-05", "AAA", 1, avail = "2026-01-04")   # 관측일보다 이른 가용
prov29b <- mk_provider(list(bad = bad_av))
chk_err("T29b avail_ts < Date (라벨 방향 오류) 거부",
        ast_compile(list(type = "leaf", source = "rawdata", field = "bad"),
                    eval_dates = D("2026-01-06"), provider = prov29b), "avail_ts < Date")

# T29c: universe 그리드 지정 시 그 그리드로만 산출
prov29c <- mk_provider(list(u = rbind(mkp("2026-01-05", "AAA", 1), mkp("2026-01-05", "BBB", 2))))
r29c <- ast_compile(list(type = "leaf", source = "rawdata", field = "u"),
                    eval_dates = D("2026-01-06"),
                    universe = data.table(Date = D("2026-01-06"), Ticker = "AAA"),
                    provider = prov29c)
chk("T29c universe 그리드 제한: AAA 1행만", nrow(r29c$panel) == 1L && r29c$panel$Ticker == "AAA")

#------------------------------------------------------------------------------
# 결과 집계
#------------------------------------------------------------------------------
res <- rbindlist(.RESULTS$rows)
n_pass <- res[ok == TRUE, .N]; n_fail <- res[ok == FALSE, .N]
cat(sprintf("\n===== AST 컴파일러 테스트: %d/%d PASS", n_pass, nrow(res)))
if (n_fail > 0L) {
  cat(sprintf(" — FAIL %d건:\n", n_fail))
  print(res[ok == FALSE])
  stop("[test_ast_compile] FAIL 존재")
} else {
  cat(" (전건 통과) =====\n")
}
