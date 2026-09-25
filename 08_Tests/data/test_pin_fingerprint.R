## 데이터 컷오프·빈티지 지문 — pin_cache.R::pin_fingerprint(scheme pin_fp_v2) + run_paper_replication(data_cutoff)
##   (2026-09-24 · 플랜 P0-07 · 감사 D4-11·D8-03 · 수리 2026-09-25 적대검증 F1)
## 실사고: 강화 레인은 판본을 고정하지 않았다. 한 entry 의 칸이 서로 다른 데이터 종료일(end_date 혼재 entry 6 → 8)에서 측정되고,
##   승격은 부모 저장값(다른 판본 · 09-18 벤치 축 이관 전)과 자식 칸을 비교했다(measurement-graduation §7).
## F1(적대검증 BLOCKING): 1차 지문(v1)은 Close·Ret·K200·KQ150 **연도별 정렬 합**이었다 — 셀 엔진이 쓰는 Vol(유동성)·Size(B3 크기 칸)
##   개정과 합을 보존하는 맞교체(값 교환·편입 맞교체)를 'match' 로 적었다. v2 = 소비자 코드에서 재도출한 소비 열의 행 키 정렬 바이트 해시.
## 이 검사가 재는 것:
##   A. pin_fingerprint(합성 · 순수) — 같은 cutoff 두 번 비트 동일 · cutoff 뒤 행 추가/수정 불변 · 행 순서·열 순서 불변 ·
##      cutoff 이전 1행 수정(Close/Ret/멤버십/벤치) → 변화 + 대조가 부분·연도·열을 지목 · 팩터 DB 목록 · 완결 월말
##   F. F1 — Vol·Size 1바이트(최하위 비트) 변경 · Close 값 교환 · K200 편입 맞교체 · 상쇄 수정 · 종목 코드 개명(정렬 위치 동일) ·
##      같은 해 날짜 이동 · 문자 열 1자 → 전부 불일치 / 무변경(행·열 순서·수치 형) · 비소비 열(High) 변경 → 일치 · 키 중복 순서 불변
##   D. 소비 열 재도출 — 독립 구현과 교차 대조 · 사고 열(Vol·Size) 포함 · 코드 사본 양성 대조(소비자가 새 열을 읽으면 들어온다 ·
##      source 폐포 · 범위 밖 파일은 따라가지 않음 · 엔진 파일과 그 디렉터리 안 source) · 소비자 부재 = 멈춤(조용한 대체 없음)
##   B. 돌연변이 — cutoff 무시 · 값 정렬 해시(v1 류 다중집합) · 키 바이트 제거 · 행 정렬 제거 · 열 목록 고정(v1 4열) ·
##      문자열 상수 토큰 제거 · source 폐포 제거 · 키 중복 동률 깨기 제거 → 각 양성 대조 red
##   S. F2(2차 적대검증) — 엔진이 직접 읽는 패널(fundamental_merged·consensus/ 등)을 지문 밖 소비 원천으로 재도출(엔진 토큰 ∩ 캐시 데이터
##      항목) · 대조가 unverified(src:*) 로 드러냄 · 고정 소비자 토큰은 원천 아님(음성 대조) · digest 밖 · JSON 왕복 ·
##      돌연변이 3종(대조 무시 · 고정 소비자 토큰 포함 · 디렉터리 대소문자 무시) red
##   C. run_paper_replication(data_cutoff) 종단(자식 Rscript · 샌드박스 루트 · 합성 RAWDATA):
##      같은 cutoff 두 번 비트 동일 · cutoff 뒤 행 추가 사본에서 결과 불변 · 절단 없으면 달라짐(양성 대조) ·
##      기본(NULL) 경로 auth 에 P0-07 키 0 · auth 지문 = 독립 계산 지문(같은 엔진으로 재도출) · fail-closed(데이터가 cutoff 를 못 넘음)
##      — 돌연변이: 절단 제거(.rp_apply_data_cutoff 항등) → 불변성 red
## 격리: 운영 루트 무접촉(코드 루트는 읽기만). 자식은 R_ENVIRON_USER=<빈 파일>(~/.Renviron 이 QM_ROOT 를 운영으로 덮지 않게) ·
##   QM_ROOT/CLAUDE_PROJECT_DIR=샌드박스 · QVEST_RP_REGISTER=0 · QVEST_RP_NO_LCODE=1 · QVEST_NO_LEDGER_OPEN=1 · QVEST_RUN_CONTEXT=test ·
##   QVEST_RP_JLOG=샌드박스. 자식은 시작하자마자 QM_ROOT·PROJECT_ROOT 가 샌드박스인지 확인하고 아니면 측정 없이 멈춘다.
suppressMessages({ library(jsonlite); library(data.table); library(arrow) })
CODE <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")   # 검사 대상 코드 루트(읽기만)
P <- 0L; FL <- 0L; SK <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { FL <<- FL + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
sk <- function(m) { SK <<- SK + 1L; cat(sprintf("  SKIP %s\n", m)) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

PIN <- file.path(CODE, "02_Infrastructure/data/pin_cache.R")
RPR <- file.path(CODE, "02_Infrastructure/alpha_search/run_paper_replication.R")
FP_RE <- "^(pin_fingerprint|pin_complete_month_end|pin_fp_|\\.pin_fp_)"
## 소비자(원장·러너)와 같은 적재 — 파일 전체 source 없이 지문 정의만 parse→eval (config.R 부작용 없음)
load_fp <- function(src_text = NULL, path = PIN) {
  ex <- if (is.null(src_text)) parse(path, encoding = "UTF-8", keep.source = FALSE) else parse(text = src_text, keep.source = FALSE)
  env <- new.env(parent = baseenv())
  for (e in as.list(ex))
    if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]]) && grepl(FP_RE, as.character(e[[2]]))) eval(e, env)
  env
}
.def_from <- function(path, name, env = new.env(parent = globalenv())) {
  ex <- parse(file = path, encoding = "UTF-8", keep.source = FALSE)
  hit <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), name), as.list(ex))
  if (!length(hit)) return(NULL)
  eval(hit[[1]], envir = env); get(name, envir = env)
}
flip1 <- function(x) {   # double 1개의 최하위 바이트 1비트 뒤집기 = 1바이트 변경(1 ulp)
  b <- writeBin(as.double(x), raw(), size = 8L, endian = "little"); b[1] <- xor(b[1], as.raw(1L))
  readBin(b, "double", n = 1L, size = 8L, endian = "little")
}

## ── 합성 데이터: 영업일(월~금) × 종목 · 한 번 크게 만들고 잘라 쓴다(앞부분 값이 같은 사본) ──
##   열 = 소비자 코드가 읽는 열(Close·Ret·Open·K200·KQ150·Size·Vol·Sector) + 읽지 않는 열(High·Name — 음성 대조)
mk_panel <- function(end = as.Date("2008-12-31"), n_tk = 24L, seed = 11L) {
  set.seed(seed)
  days <- seq(as.Date("2003-01-02"), end, by = "day"); days <- days[!format(days, "%u") %in% c("6", "7")]
  tk <- sprintf("T%03d", seq_len(n_tk))
  R <- CJ(Ticker = tk, Date = days)
  R[, Ret := round(rnorm(.N, 3e-4, 0.02), 6)]
  R[, Close := round(10000 * cumprod(1 + Ret), 2), by = Ticker]
  R[, `:=`(Open = Close, K200 = as.numeric(Ticker <= "T012"), KQ150 = as.numeric(Ticker > "T012"),
           Size = round(1e11 * runif(.N, 0.5, 1.5)), Vol = round(1e5 * runif(.N, 0.5, 1.5)),
           Sector = sprintf("S%d", as.integer(substr(Ticker, 2, 4)) %% 4L), High = round(Close * 1.01, 2), Name = paste0("nm_", Ticker))]
  setorder(R, Date, Ticker)
  B <- R[, .(BM_Ret = round(mean(Ret), 8)), by = Date]
  B[, BM_Close := round(1000 * cumprod(1 + BM_Ret), 4)]
  B[, BM_Src := "fixture"]
  list(R = R[], B = B[])
}
FULL <- mk_panel()
CUT  <- as.Date("2008-08-31")
D1_END <- as.Date("2008-09-30"); D2_END <- as.Date("2008-12-31")
D1 <- list(R = FULL$R[Date <= D1_END], B = FULL$B[Date <= D1_END])
D2 <- list(R = FULL$R[Date <= D2_END], B = FULL$B[Date <= D2_END])

cat("=== A. pin_fingerprint (합성 · 순수) ===\n")
FP <- load_fp()
need <- c("pin_fingerprint", "pin_fingerprint_load", "pin_fingerprint_compare", "pin_complete_month_end", "pin_fp_consumers", "pin_fp_consumed_cols")
chk(all(vapply(need, exists, logical(1), envir = FP, inherits = FALSE)), "A0 지문 정의가 parse→eval 로 적재된다(config.R 무실행)",
    paste(setdiff(need, ls(FP, all.names = TRUE)), collapse = ","))
fpx <- function(R, B = D1$B, cut = CUT, F = FP, code = CODE, ...) F$pin_fingerprint(cut, raw = R, bm = B, code_root = code, ...)
f1 <- fpx(D1$R); f1b <- fpx(D1$R)
chk(identical(f1$status, "ok") && nzchar(f1$digest) && identical(f1$scheme, "pin_fp_v2"), "A1a 지문 status ok · digest 존재 · scheme pin_fp_v2",
    paste(f1$status, f1$digest, f1$scheme))
chk(identical(f1, f1b), "A1b 같은 데이터·같은 cutoff 두 번 = identical(비트 동일)")
f2 <- fpx(D2$R, D2$B)
chk(identical(f1$digest, f2$digest) && identical(f1$raw, { r <- f2$raw; r$observed_max_date <- f1$raw$observed_max_date; r }),
    "A2 cutoff 뒤 행 추가(09-30 → 12-31) — 지문 불변(관측 최대일만 다름)", paste(f1$digest, f2$digest))
chk(identical(f1$raw$max_date, "2008-08-29") && identical(f1$bm$max_date, "2008-08-29") && identical(f1$cutoff, "2008-08-31"),
    "A2b 지문 창 = cutoff 이하 마지막 영업일(2008-08-29)")
fw <- fpx(D1$R, cut = as.Date("2008-09-30"))
chk(isTRUE(f1$window_complete) && isFALSE(fw$window_complete) && is.na(fpx(D1$R, cut = NULL)$window_complete),
    "A2c window_complete — 데이터가 cutoff 를 넘으면 TRUE · 데이터 끝 = cutoff 면 FALSE(완결 미증명) · cutoff 없음 NA")
set.seed(3); o <- sample.int(nrow(D1$R)); ob <- sample.int(nrow(D1$B))
f3 <- fpx(D1$R[o], D1$B[ob])
chk(identical(f1$digest, f3$digest), "A3 행 순서 뒤섞기(RAWDATA·벤치) — 지문 불변(키 정렬)")
mod <- function(D, what, date, tk = "T005", delta = 1) {
  R <- copy(D$R); B <- copy(D$B)
  if (what %in% names(R)) R[Date == date & Ticker == tk, (what) := get(what) + delta]
  else B[Date == date, BM_Close := BM_Close + delta]
  list(R = R, B = B)
}
f4 <- fpx(mod(D1, "Close", as.Date("2006-03-15"))$R)
cmp4 <- FP$pin_fingerprint_compare(f1, f4)
chk(!identical(f1$digest, f4$digest) && identical(cmp4$status, "mismatch") && identical(cmp4$parts, "raw") && identical(cmp4$years, 2006L) &&
      identical(cmp4$cols, "raw:Close"),
    "A4 cutoff 이전 Close 1행 +1 — 지문 변화 · 대조 = mismatch/raw/2006/raw:Close",
    paste(cmp4$status, paste(cmp4$parts, collapse = ","), paste(cmp4$years, collapse = ","), paste(cmp4$cols, collapse = ",")))
f5 <- fpx(mod(D1, "Ret", as.Date("2008-08-29"), delta = 1e-4)$R)
chk(!identical(f1$digest, f5$digest) && identical(FP$pin_fingerprint_compare(f1, f5)$years, 2008L),
    "A5a cutoff 직전 영업일 Ret 1행 +1e-4 — 지문 변화(2008)")
f6 <- fpx(mod(D1, "K200", as.Date("2005-06-01"), delta = -1)$R)
chk(!identical(f1$digest, f6$digest), "A5b 멤버십(K200) 1행 해제 — 지문 변화(고정 축 유니버스)")
f7 <- fpx(D1$R, mod(D1, "BM", as.Date("2007-01-02"), delta = 0.5)$B)
cmp7 <- FP$pin_fingerprint_compare(f1, f7)
chk(identical(cmp7$status, "mismatch") && identical(cmp7$parts, "bm") && identical(cmp7$cols, "bm:BM_Close"),
    "A5c 벤치 1행 수정(09-18 축 이관 유형) — bm 부분 mismatch · bm:BM_Close", paste(cmp7$parts, cmp7$cols, collapse = ","))
f8 <- fpx(mod(D1, "Close", as.Date("2008-09-15"), delta = 999)$R, mod(D1, "BM", as.Date("2008-09-15"), delta = 9)$B)
chk(identical(f1$digest, f8$digest), "A6 cutoff 뒤 행 수정(RAWDATA·벤치) — 지문 불변")
## 팩터 DB 월 파일 목록(이름·크기) — 샌드박스 디렉터리
FD <- file.path(tempdir(), sprintf("pfp_fdb_%d", Sys.getpid())); dir.create(FD, showWarnings = FALSE)
for (ym in c("200806", "200807", "200808")) writeBin(as.raw(seq_len(100)), file.path(FD, sprintf("factor_db_%s.parquet", ym)))
writeBin(as.raw(1:3), file.path(FD, "factor_db_200808_PRE_rebuild.parquet"))            # 백업 이름 = 목록 밖
g1 <- fpx(D1$R, fdb_dir = FD)
writeBin(as.raw(seq_len(50)), file.path(FD, "factor_db_200809.parquet"))                  # cutoff 뒤 월 추가
g2 <- fpx(D1$R, fdb_dir = FD)
writeBin(as.raw(seq_len(101)), file.path(FD, "factor_db_200807.parquet"))                 # cutoff 이전 월 재빌드(크기 변화)
g3 <- fpx(D1$R, fdb_dir = FD)
chk(identical(g1$fdb$status, "ok") && g1$fdb$n_files == 3L && identical(g1$fdb$last_ym, "200808") && identical(g1$digest, g2$digest),
    "A7a 팩터 DB — cutoff 월까지 3파일 · 백업 이름 제외 · cutoff 뒤 월 추가에 불변")
chk(identical(FP$pin_fingerprint_compare(g1, g3)$parts, "fdb"), "A7b 팩터 DB — cutoff 이전 월 파일 재빌드(크기) → fdb mismatch")
chk(identical(FP$pin_fingerprint_compare(g1, f1)$status, "match") && identical(FP$pin_fingerprint_compare(g1, f1)$unverified, "fdb"),
    "A7c 한쪽만 팩터 DB 확인 가능 → 판정에서 빼고 unverified 로 드러낸다(일치로 세지 않는 부분 명시)")
fx <- fpx(D1$R, cut = as.Date("2008-07-31"))
chk(identical(FP$pin_fingerprint_compare(f1, fx)$status, "incomparable"), "A8a cutoff 가 다른 두 지문 = incomparable(판정하지 않는다)")
chk(identical(FP$pin_fingerprint_compare(f1, list(status = "absent"))$status, "unknown") &&
      identical(FP$pin_fingerprint_compare(NULL, f1)$status, "unknown"), "A8b 한쪽 지문 부재·비정상 = unknown(일치로 간주 안 함)")
jr <- fromJSON(toJSON(f1, auto_unbox = TRUE, null = "null", na = "null", digits = 6), simplifyVector = FALSE)   # 원장 왕복(.rf_write 와 같은 직렬화)
chk(identical(FP$pin_fingerprint_compare(jr, f1)$status, "match") && identical(FP$pin_fingerprint_compare(jr, f4)$years, 2006L) &&
      identical(FP$pin_fingerprint_compare(jr, f4)$cols, "raw:Close"),
    "A8c 원장 JSON 왕복(simplifyVector=FALSE) 지문도 대조 가능 — 연도·열 지목 유지")
fn <- fpx(D1$R, cut = NULL)
chk(identical(fn$raw$max_date, "2008-09-30") && is.na(fn$cutoff), "A8d cutoff NULL = 전 행(절단 없음)")
chk(inherits(tryCatch(fpx(D1$R, cut = "2008-13-45"), error = function(e) e), "error"), "A8e 해석 불가 cutoff = 멈춤(추정하지 않는다)")
fr <- fpx(D1$R, raw_cols = c("Close", "Ret"), bm_cols = "BM_Ret")
chk(identical(FP$pin_fingerprint_compare(f1, fr)$status, "incomparable") && identical(FP$pin_fingerprint_compare(f1, fr)$why, "raw_cols") &&
      identical(fr$cols_basis, "given"), "A8f 열이 다른 두 지문 = incomparable(raw_cols) · 호출자 지정 열 = cols_basis given")
cme <- FP$pin_complete_month_end
chk(identical(cme(as.Date(c("2026-09-01", "2026-09-23")), today = as.Date("2026-09-24")), as.Date("2026-08-31")) &&
      identical(cme(as.Date("2026-08-31"), today = as.Date("2026-09-01")), as.Date("2026-07-31")) &&
      identical(cme(as.Date("2026-09-23"), bm_dates = as.Date("2026-08-28"), today = as.Date("2026-09-24")), as.Date("2026-07-31")) &&
      identical(cme(as.Date("2026-10-05"), today = as.Date("2026-09-24")), as.Date("2026-08-31")) &&
      is.na(cme(as.Date(character(0)))),
    "A9 직전 완결 월말 — 데이터가 월말을 넘어선 달만(월말 당일 적재 = 전달) · 벤치 min · today 상한 · 빈 입력 NA")

cat("\n=== F. F1 — 소비 열 개정·합 보존 맞교체·키 이동 (v1 이 'match' 로 적던 유형) ===\n")
edit <- function(f) { R <- copy(D1$R); f(R); R }
cmpf <- function(R) FP$pin_fingerprint_compare(f1, fpx(R))
row_of <- function(R, d, tk) which(R$Date == as.Date(d) & R$Ticker == tk)
chk(all(c("Vol", "Size", "Close", "Ret", "K200", "KQ150") %in% f1$raw$cols), "F0 사고 열(Vol·Size) + 수익·멤버십 열이 소비 열에 있다",
    paste(f1$raw$cols, collapse = ","))
cF1a <- cmpf(edit(function(R) { i <- row_of(R, "2006-03-15", "T005"); set(R, i, "Vol", flip1(R$Vol[i])) }))
chk(identical(cF1a$status, "mismatch") && identical(cF1a$cols, "raw:Vol") && identical(cF1a$years, 2006L),
    "F1a Vol 1행 최하위 바이트 변경(1 ulp · 유동성 2e8 입력) → mismatch · raw:Vol · 2006", paste(cF1a$status, paste(cF1a$cols, collapse = ",")))
cF1b <- cmpf(edit(function(R) { i <- row_of(R, "2004-11-02", "T017"); set(R, i, "Size", flip1(R$Size[i])) }))
chk(identical(cF1b$status, "mismatch") && identical(cF1b$cols, "raw:Size"), "F1b Size 1행 1바이트 변경(B3 크기 칸 입력) → mismatch · raw:Size",
    paste(cF1b$cols, collapse = ","))
cF1c <- cmpf(edit(function(R) { i <- row_of(R, "2007-05-10", "T003"); j <- row_of(R, "2007-05-10", "T004")
  a <- R$Close[i]; set(R, i, "Close", R$Close[j]); set(R, j, "Close", a) }))
chk(identical(cF1c$status, "mismatch") && identical(cF1c$cols, "raw:Close"), "F1c 같은 날 두 종목 Close 교환(연 합 보존) → mismatch · raw:Close")
cF1d <- cmpf(edit(function(R) { i <- row_of(R, "2005-06-01", "T005"); j <- row_of(R, "2005-06-01", "T020")
  set(R, i, "K200", 0); set(R, j, "K200", 1) }))
chk(identical(cF1d$status, "mismatch") && identical(cF1d$cols, "raw:K200"), "F1d K200 편입 맞교체(하나 빠지고 하나 들어옴 · 합 보존) → mismatch · raw:K200")
cF1e <- cmpf(edit(function(R) { i <- row_of(R, "2006-02-01", "T001"); j <- row_of(R, "2006-09-01", "T002")
  set(R, i, "Close", R$Close[i] + 500); set(R, j, "Close", R$Close[j] - 500) }))
chk(identical(cF1e$status, "mismatch"), "F1e 같은 해 상쇄 수정(+500/−500 · 연 합 보존) → mismatch")
cF1f <- cmpf(edit(function(R) R[Ticker == "T005", Ticker := "T005x"]))
chk(identical(cF1f$status, "mismatch") && identical(cF1f$cols, "raw:keys"), "F1f 종목 코드 개명(정렬 위치 동일 · 값 순서 불변) → mismatch · raw:keys",
    paste(cF1f$cols, collapse = ","))
cF1g <- cmpf(edit(function(R) { i <- row_of(R, "2006-03-15", "T005"); set(R, i, "Date", as.Date("2006-03-18")) }))
chk(identical(cF1g$status, "mismatch") && identical(cF1g$years, 2006L), "F1g 같은 해 날짜 이동(1행 · 값 불변) → mismatch · 2006")
cF1h <- cmpf(edit(function(R) { i <- row_of(R, "2008-01-07", "T009"); set(R, i, "Sector", "S9") }))
chk(identical(cF1h$status, "mismatch") && identical(cF1h$cols, "raw:Sector"), "F1h 문자 소비 열(Sector) 1행 변경 → mismatch · raw:Sector")
na1 <- edit(function(R) { i <- row_of(R, "2008-01-07", "T009"); set(R, i, "Sector", NA_character_) })
em1 <- edit(function(R) { i <- row_of(R, "2008-01-07", "T009"); set(R, i, "Sector", "") })
chk(!identical(fpx(na1)$digest, fpx(em1)$digest), "F1i 문자 NA 와 빈 문자열은 다른 지문(길이 −1 표식)")
Rn <- copy(D1$R)[, K200 := as.integer(K200)]; setcolorder(Rn, rev(names(Rn)))
chk(identical(cmpf(Rn)$status, "match"), "F2a 무변경 — 열 순서 역전 + K200 정수형(값 동일) → match")
uncons <- setdiff(names(D1$R), c(f1$raw$cols, "Date", "Ticker"))   # 소비자 코드가 읽지 않는 열 — 재도출 결과에서 고른다
if (!length(uncons)) sk("F2b 합성 열이 전부 소비 열 — 음성 대조 생략") else {
  cF2b <- cmpf(edit(function(R) for (cn in uncons) {
    if (is.numeric(R[[cn]])) R[Date == as.Date("2006-03-15"), (cn) := get(cn) + 7] else R[Ticker == "T001", (cn) := paste0(get(cn), "x")] }))
  chk(identical(cF2b$status, "match"), sprintf("F2b 음성 대조 — 소비자 코드가 읽지 않는 열(%s) 변경은 match(전 열 해시가 아니다)",
                                               paste(uncons, collapse = "·")))
}
dupA <- rbind(D1$R, D1$R[Date == as.Date("2006-03-15") & Ticker == "T005"][, Vol := Vol + 1])
dupB <- rbind(D1$R[Date == as.Date("2006-03-15") & Ticker == "T005"][, Vol := Vol + 1], D1$R)
fdA <- fpx(dupA); fdB <- fpx(dupB)
chk(identical(fdA$digest, fdB$digest) && identical(fdA$raw$dup_keys, 1L) && !identical(fdA$digest, f1$digest),
    "F3 키 중복(같은 Date·Ticker 2행) — 입력 순서가 달라도 같은 지문 · dup_keys=1 · 중복 없는 판과 다름",
    paste(fdA$raw$dup_keys, fdA$digest == fdB$digest))

cat("\n=== D. 소비 열 재도출 (소비자 코드 → 열) ===\n")
CS <- FP$pin_fp_consumers(code_root = CODE)
## 독립 구현 — 구문 트리를 직접 걸어(getParseData 경로와 다른 코드) 호출 위치가 아닌 기호 + 문자 상수를 모은다
ind_tokens <- function(p) {
  ex <- parse(p, encoding = "UTF-8", keep.source = FALSE)
  acc <- character(0)
  grab <- function(e, fpos = FALSE) {
    if (is.character(e)) { acc <<- c(acc, e); return(invisible()) }
    if (is.symbol(e)) { if (!fpos) acc <<- c(acc, as.character(e)); return(invisible()) }
    if (is.call(e) || is.pairlist(e)) {
      l <- as.list(e)
      for (i in seq_along(l)) if (!identical(l[[i]], quote(expr = ))) grab(l[[i]], fpos = is.call(e) && i == 1L)
    }
    invisible()
  }
  for (e in as.list(ex)) grab(e)
  unique(acc)
}
schema <- names(D1$R)
ind <- sort(setdiff(intersect(schema, unique(unlist(lapply(file.path(CODE, CS$files), ind_tokens)))), c("Date", "Ticker")), method = "radix")
chk(identical(ind, f1$raw$cols), "D1a 소비 열 = 독립 구현(구문 트리 직접 보행 — 호출 위치 밖 기호 + 문자 상수) 재도출과 일치",
    sprintf("pin=%s ind=%s", paste(f1$raw$cols, collapse = ","), paste(ind, collapse = ",")))
chk(all(c("02_Infrastructure/alpha_search/run_paper_replication.R", "02_Infrastructure/replication/replication_harness.R",
          "02_Infrastructure/reinforcement/rf_cell_engine.R") %in% CS$files) && length(CS$files) == length(CS$md5) &&
      identical(f1$consumers$files, CS$files), "D1b 소비자 = 진입점 3 + source 폐포 · 지문에 파일·md5 기록",
    paste(CS$files, collapse = " | "))
## 코드 사본 양성 대조 — 폐포 파일만 임시 코드 루트로 복사(운영 코드 무수정)
TC <- file.path({ b <- tempdir(); if (nchar(b) > 100L) { b <- "C:/tmp"; dir.create(b, showWarnings = FALSE) }; b }, sprintf("pfp_code_%d", Sys.getpid()))
unlink(TC, recursive = TRUE)
for (f in CS$files) { dir.create(dirname(file.path(TC, f)), recursive = TRUE, showWarnings = FALSE); file.copy(file.path(CODE, f), file.path(TC, f)) }
CS_TC <- FP$pin_fp_consumers(code_root = TC)
chk(identical(CS_TC$files, CS$files) && identical(FP$pin_fp_consumed_cols(schema, CS_TC), f1$raw$cols),
    "D2a 사본 코드 루트 = 원 코드 루트와 같은 소비자·같은 열(사본이 공허하지 않다)")
CE <- file.path(TC, "02_Infrastructure/reinforcement/rf_cell_engine.R")
ce0 <- readLines(CE, encoding = "UTF-8", warn = FALSE)
writeLines(c(ce0, '.b7_probe_high <- DT[["High"]]   # 검사 주입 — 소비자가 새 열을 읽는다'), CE, useBytes = TRUE)
hi_edit <- edit(function(R) R[Date == as.Date("2006-03-15"), High := High + 7])
c_code <- FP$pin_fingerprint_compare(fpx(D1$R, code = TC), fpx(hi_edit, code = TC))
chk("High" %in% FP$pin_fp_consumed_cols(schema, FP$pin_fp_consumers(code_root = TC)) && identical(c_code$cols, "raw:High"),
    "D2b 셀 엔진 사본이 High 를 읽으면(문자열 상수 참조) High 가 소비 열이 되고 High 개정이 mismatch · raw:High",
    paste(c_code$status, paste(c_code$cols, collapse = ",")))
HP <- file.path(TC, "02_Infrastructure/reinforcement/rf_b7_probe_helper.R")
writeLines("rf_b7_probe_low <- function(DT) DT$Low", HP)
OP <- file.path(TC, "02_Infrastructure/b7_probe_outside.R"); writeLines("b7_probe_outside <- function(DT) DT$Market", OP)
writeLines(c(ce0, 'source(file.path(.RF_ROOT, "02_Infrastructure/reinforcement/rf_b7_probe_helper.R"))',
             'source(file.path(.RF_ROOT, "02_Infrastructure/b7_probe_outside.R"))'), CE, useBytes = TRUE)
cc3 <- FP$pin_fp_consumed_cols(c(schema, "Low", "Market"), FP$pin_fp_consumers(code_root = TC))
chk("Low" %in% cc3 && !("Market" %in% cc3),
    "D3 source 폐포 — 측정 계층 조수 파일(reinforcement/)이 읽는 Low 는 들어오고 · 범위 밖 파일(02_Infrastructure/ 최상위)의 Market 은 따라가지 않는다",
    paste(cc3, collapse = ","))
writeLines(ce0, CE, useBytes = TRUE)
ED <- file.path(TC, "eng"); dir.create(ED, showWarnings = FALSE)
EN <- file.path(ED, "engine_x.R"); writeLines(c("source('eng_helper.R')", "FACTORS <- RAWDATA[, .(Date, Ticker, Score = Float)]"), EN)
writeLines("eng_helper <- function(x) x$Market", file.path(ED, "eng_helper.R"))
cc4 <- FP$pin_fp_consumed_cols(c(schema, "Float", "Market"), FP$pin_fp_consumers(code_root = TC, engines = EN))
cc4n <- FP$pin_fp_consumed_cols(c(schema, "Float", "Market"), FP$pin_fp_consumers(code_root = TC))
fmiss <- fpx(D1$R, code = TC, engines = file.path(ED, "nope.R"))
chk(all(c("Float", "Market") %in% cc4) && !any(c("Float", "Market") %in% cc4n) && any(grepl("^engine_absent:", fmiss$why)),
    "D4 엔진 파일(+자기 디렉터리 안 source)이 읽는 열(Float·Market)은 engines 로 넘길 때만 들어온다 · 없는 엔진 = why engine_absent(조용한 누락 없음)",
    paste(cc4, collapse = ","))
TE <- file.path(TC, "empty_root"); dir.create(TE, showWarnings = FALSE)
e5 <- tryCatch(FP$pin_fp_consumers(code_root = TE), error = function(e) conditionMessage(e))
chk(is.character(e5) && grepl("소비자 코드 부재", e5), "D5 소비자 코드가 없는 루트 = 멈춤(열 목록으로 조용히 대체하지 않는다)")

cat("\n=== B. 돌연변이 (지문 정의 텍스트 교체 → 양성 대조 red) ===\n")
src <- paste(readLines(PIN, encoding = "UTF-8", warn = FALSE), collapse = "\n")
mut <- function(tag, from, to) {
  n <- lengths(regmatches(src, gregexpr(from, src, fixed = TRUE)))
  if (n != 1L) { ng(sprintf("%s 돌연변이 표적이 소스에 %d회(1회여야) — 검사 갱신 필요", tag, n)); return(NULL) }
  load_fp(sub(from, to, src, fixed = TRUE))
}
M1 <- mut("B1", "if (!is.na(cutoff)) keep <- keep & d <= cutoff", "invisible(NULL)")
if (!is.null(M1)) chk(!identical(fpx(D1$R, F = M1)$digest, fpx(D2$R, D2$B, F = M1)$digest), "B1 돌연변이(cutoff 무시) — A2 불변성이 깨진다(red)")
M2 <- mut("B2", ".pin_fp_md5_raw(.pin_fp_bytes(tab[[cn]][ri[j]]))", ".pin_fp_md5_raw(.pin_fp_bytes(sort(tab[[cn]][ri[j]], na.last = TRUE)))")
if (!is.null(M2)) {
  swapR <- edit(function(R) { i <- row_of(R, "2007-05-10", "T003"); j <- row_of(R, "2007-05-10", "T004")
    a <- R$Close[i]; set(R, i, "Close", R$Close[j]); set(R, j, "Close", a) })
  memR <- edit(function(R) { i <- row_of(R, "2005-06-01", "T005"); j <- row_of(R, "2005-06-01", "T020"); set(R, i, "K200", 0); set(R, j, "K200", 1) })
  base2 <- fpx(D1$R, F = M2)$digest
  chk(identical(fpx(swapR, F = M2)$digest, base2) && identical(fpx(memR, F = M2)$digest, base2),
      "B2 돌연변이(연도별 값 다중집합 해시 — v1 정렬 합 류) — F1c 교환·F1d 편입 맞교체를 놓친다(red)")
}
M3 <- mut("B3", "kh <- .pin_fp_md5_raw(do.call(c, lapply(kv, function(v) .pin_fp_bytes(v[j]))))", 'kh <- "nokeys"')
if (!is.null(M3)) chk(identical(fpx(D1$R, F = M3)$digest, fpx(edit(function(R) R[Ticker == "T005", Ticker := "T005x"]), F = M3)$digest),
                      "B3 돌연변이(키 바이트 제거) — F1f 종목 코드 개명을 놓친다(red)")
M4 <- mut("B4", 'o <- do.call(order, c(unname(kv), list(method = "radix")))', 'o <- order(kv[[1L]], method = "radix")')
if (!is.null(M4)) chk(!identical(fpx(D1$R, F = M4)$digest, fpx(D1$R[o], D1$B[ob], F = M4)$digest),
                      "B4 돌연변이(종목 키 정렬 제거 — 날짜만 정렬) — A3 행 순서 불변성이 깨진다(red)")
M5 <- mut("B5", 'sort(setdiff(intersect(as.character(schema), consumers$tokens), keys), method = "radix")',
          'intersect(c("Close", "Ret", "K200", "KQ150"), as.character(schema))')
if (!is.null(M5)) {
  volR <- edit(function(R) { i <- row_of(R, "2006-03-15", "T005"); set(R, i, "Vol", flip1(R$Vol[i])) })
  sizR <- edit(function(R) { i <- row_of(R, "2004-11-02", "T017"); set(R, i, "Size", flip1(R$Size[i])) })
  b5 <- fpx(D1$R, F = M5)$digest
  chk(identical(fpx(volR, F = M5)$digest, b5) && identical(fpx(sizR, F = M5)$digest, b5),
      "B5 돌연변이(열 목록 고정 = v1 4열) — F1a Vol·F1b Size 개정을 'match' 로 놓친다(red = 적대검증 F1 재현)")
}
M6 <- mut("B6", "tk <- unique(c(sy, st[nzchar(st)]))", "tk <- unique(sy)")
if (!is.null(M6)) {
  writeLines(c(ce0, '.b7_probe_high <- DT[["High"]]'), CE, useBytes = TRUE)
  chk(!("High" %in% M6$pin_fp_consumed_cols(schema, M6$pin_fp_consumers(code_root = TC))),
      "B6 돌연변이(문자열 상수 토큰 제거) — D2b 의 DT[[\"High\"]] 참조를 놓친다(red)")
  writeLines(ce0, CE, useBytes = TRUE)
}
M7 <- mut("B7", 'if (any(startsWith(tolower(q), paste0(scope, "/")))) queue <- c(queue, q)', "invisible(NULL)")
if (!is.null(M7)) {
  writeLines(c(ce0, 'source(file.path(.RF_ROOT, "02_Infrastructure/reinforcement/rf_b7_probe_helper.R"))'), CE, useBytes = TRUE)
  chk(!("Low" %in% M7$pin_fp_consumed_cols(c(schema, "Low"), M7$pin_fp_consumers(code_root = TC))),
      "B7 돌연변이(source 폐포 제거) — D3 조수 파일의 Low 를 놓친다(red)")
  writeLines(ce0, CE, useBytes = TRUE)
}
M8 <- mut("B8", "if (dup > 0L) {", "if (FALSE) {")
if (!is.null(M8)) chk(!identical(fpx(dupA, F = M8)$digest, fpx(dupB, F = M8)$digest), "B8 돌연변이(키 중복 동률 깨기 제거) — F3 순서 불변이 깨진다(red)")

cat("\n=== S. 지문 밖 소비 원천(2차 적대검증 F2) — 엔진이 직접 읽는 패널 ===\n")
## 합성 캐시 디렉터리(이름만 본다) — 해시 원천 3 + 엔진이 읽는 패널 2(파일·디렉터리) + 필터 문자열과 대소문자만 다른 디렉터리 + 비데이터
SC <- file.path(dirname(TC), sprintf("pfp_cache_%d", Sys.getpid())); unlink(SC, recursive = TRUE)
for (d in c("factor_db", "consensus", "dart", "notes")) dir.create(file.path(SC, d), recursive = TRUE, showWarnings = FALSE)
for (f in c("RAWDATA.parquet", "benchmark.parquet", "fundamental_merged.parquet", "factor_db/factor_db_200801.parquet",
            "consensus/eps.parquet", "dart/q.parquet")) writeBin(as.raw(1:4), file.path(SC, f))
writeLines("{}", file.path(SC, "notes.json")); writeLines("x", file.path(SC, "notes", "a.txt"))
## 고정 소비자 사본 — 셀 엔진이 패널 이름을 문자열로 담는다(기저 캐시 키 목록 류 · 원천으로 세면 안 되는 토큰)
for (f in CS$files) { dir.create(dirname(file.path(TC, f)), recursive = TRUE, showWarnings = FALSE); file.copy(file.path(CODE, f), file.path(TC, f), overwrite = TRUE) }
writeLines(c(ce0, '.b7_probe_aux <- c("fundamental_merged.parquet", "consensus")   # 검사 주입 — 고정 소비자의 캐시 도장 목록 흉내'), CE, useBytes = TRUE)
ENS <- file.path(ED, "engine_aux.R")
writeLines(c('.CACHE <- file.path(Sys.getenv("QM_ROOT"), ".cache")',
             '.fm <- arrow::read_parquet(file.path(.CACHE, "fundamental_merged.parquet"))',
             '.fm <- .fm[Source %in% c("DART", "XLSX")]',
             '.cs <- file.path(.CACHE, "consensus")',
             '.rw <- file.path(.CACHE, "RAWDATA.parquet")',
             'FACTORS <- RAWDATA[, .(Date, Ticker, Score = Close)]'), ENS)
fS <- fpx(D1$R, code = TC, engines = ENS, cache_dir = SC, fdb_dir = file.path(SC, "factor_db"))
fN <- fpx(D1$R, code = TC, cache_dir = SC, fdb_dir = file.path(SC, "factor_db"))
chk(identical(fS$sources$status, "ok") && identical(fS$sources$consumed, c("RAWDATA.parquet", "consensus", "fundamental_merged.parquet")) &&
      identical(fS$sources$covered, "RAWDATA.parquet") && identical(fS$sources$uncovered, c("consensus", "fundamental_merged.parquet")),
    "S1 소비 원천 = 엔진 토큰 ∩ 캐시 데이터 항목 — 패널 파일·디렉터리는 uncovered · RAWDATA 는 covered · 'DART' 필터 ≠ dart/ · 비데이터 제외",
    paste(fS$sources$consumed, collapse = ","))
chk("fundamental_merged.parquet" %in% FP$pin_fp_consumers(code_root = TC)$tokens && identical(fN$sources$status, "ok") &&
      !length(fN$sources$consumed),
    "S2 음성 대조 — 고정 소비자 토큰에 패널 이름이 있어도(캐시 키 목록 류) 엔진 없으면 소비 원천 0(상시 미확인 방지)")
chk(identical(fS$digest, fN$digest) && identical(fS$raw$cols, fN$raw$cols), "S3 소비 원천은 digest 밖 정보 필드 — 해시·열 불변")
cS <- FP$pin_fingerprint_compare(fN, fS)
chk(identical(cS$status, "match") && identical(cS$unverified, c("src:consensus", "src:fundamental_merged.parquet")),
    "S4 대조 — 해시 원천은 match 여도 지문 밖 원천을 unverified(src:*) 로 드러낸다(한쪽만 있어도)", paste(cS$unverified, collapse = ","))
jS <- fromJSON(toJSON(fS, auto_unbox = TRUE, null = "null", na = "null", digits = 6), simplifyVector = FALSE)
chk(identical(FP$pin_fingerprint_compare(jS, fN)$unverified, c("src:consensus", "src:fundamental_merged.parquet")),
    "S5 원장 JSON 왕복 지문도 지문 밖 원천을 잃지 않는다")
chk(identical(fpx(D1$R, code = TC, engines = ENS)$sources$status, "cache_dir_absent") &&
      identical(fpx(D1$R, raw_cols = f1$raw$cols, bm_cols = f1$bm$cols, cache_dir = SC)$sources$status, "not_derived"),
    "S6 캐시 디렉터리 없음 = cache_dir_absent · 열 지정(소비자 재도출 없음) = not_derived — 조용한 '0 원천' 아님")
MS1 <- mut("MS1", 'if (length(us)) unv <- c(unv, paste0("src:", us))', "invisible(NULL)")
if (!is.null(MS1)) chk(!length(MS1$pin_fingerprint_compare(fN, fS)$unverified), "MS1 돌연변이(대조가 소비 원천 무시) — S4 의 src:* 가 사라진다(red)")
MS2 <- mut("MS2", "tk <- as.character(consumers$engine_tokens)", "tk <- as.character(consumers$tokens)")
if (!is.null(MS2)) chk(length(fpx(D1$R, F = MS2, code = TC, cache_dir = SC, fdb_dir = file.path(SC, "factor_db"))$sources$uncovered) > 0L,
                       "MS2 돌연변이(고정 소비자 토큰까지 원천 재도출) — S2 음성 대조가 깨진다(상시 미확인 · red)")
MS3 <- mut("MS3", "dd[dd %in% tk]", "dd[tolower(dd) %in% tolower(tk)]")
if (!is.null(MS3)) chk("dart" %in% fpx(D1$R, F = MS3, code = TC, engines = ENS, cache_dir = SC, fdb_dir = file.path(SC, "factor_db"))$sources$consumed,
                       "MS3 돌연변이(디렉터리 대소문자 무시) — 'DART' 필터 문자열이 dart/ 를 원천으로 만든다(red)")
writeLines(ce0, CE, useBytes = TRUE)
unlink(SC, recursive = TRUE)
unlink(TC, recursive = TRUE)

cat("\n=== C. run_paper_replication(data_cutoff) 종단 (자식 Rscript · 샌드박스) ===\n")
AC <- .def_from(RPR, ".rp_apply_data_cutoff")
if (is.null(AC)) ng("C0 .rp_apply_data_cutoff 정의 부재") else {
  e1 <- tryCatch(AC(copy(D1$R)[Date <= CUT], copy(D1$B), CUT), error = function(e) conditionMessage(e))
  e2 <- tryCatch(AC(copy(D1$R), copy(D1$B)[Date <= CUT], CUT), error = function(e) conditionMessage(e))
  chk(is.character(e1) && grepl("넘어서지 않는다", e1) && is.character(e2) && grepl("넘어서지 않는다", e2),
      "C0a fail-closed — RAWDATA 또는 벤치가 cutoff 를 못 넘으면 멈춘다(완결 미증명)")
  a <- AC(copy(D1$R), copy(D1$B), "2008-08-31")
  chk(max(a$RAWDATA$Date) == as.Date("2008-08-29") && max(a$BM_DT$Date) == as.Date("2008-08-29") &&
        a$info$raw_rows_dropped == nrow(D1$R[Date > CUT]) && identical(a$info$raw_max_date_loaded, "2008-09-30"),
      "C0b 절단 — cutoff 이하만 · 버린 행 수·적재 최대일 기록")
  chk(inherits(tryCatch(AC(copy(D1$R), copy(D1$B), c("2008-08-31", "2008-07-31")), error = function(e) e), "error") &&
        inherits(tryCatch(AC(copy(D1$R), copy(D1$B), "nope"), error = function(e) e), "error"), "C0c cutoff 2개·해석 불가 = 멈춤")
}
fm <- names(formals(.def_from(RPR, "run_paper_replication") %||% function() NULL))
chk("data_cutoff" %in% fm && is.null(formals(.def_from(RPR, "run_paper_replication"))$data_cutoff),
    "C0d run_paper_replication(data_cutoff = NULL) 형식인자 · 기본 NULL")
DF <- .def_from(RPR, ".rp_data_fingerprint")
chk(is.function(DF) && "engine_path" %in% names(formals(DF)), "C0e .rp_data_fingerprint(engine_path) — 러너 지문도 엔진 열을 재도출한다")

## 경로 길이(MAX_PATH 259): 02_Infrastructure 최심 상대경로 약 115자 + 산출물 — tempdir 이 길면 짧은 기반으로
.base <- tempdir(); if (nchar(.base) > 100L) { .base <- "C:/tmp"; dir.create(.base, showWarnings = FALSE) }
SBX <- file.path(.base, sprintf("pfp_sbx_%d", Sys.getpid()))
unlink(SBX, recursive = TRUE); dir.create(SBX, recursive = TRUE)
t0 <- Sys.time()
okc <- file.copy(file.path(CODE, "02_Infrastructure"), SBX, recursive = TRUE)
for (d in c(".cache", "06_Registry", "stage_artifacts/replication", "fixtures")) dir.create(file.path(SBX, d), recursive = TRUE, showWarnings = FALSE)
if (!isTRUE(okc) || !file.exists(file.path(SBX, "02_Infrastructure/config.R"))) {
  ng("C 샌드박스 코드 복사 실패")
} else {
  cat(sprintf("  (샌드박스 코드 복사 %.1f초)\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  wp <- function(x, f) arrow::write_parquet(x, file.path(SBX, "fixtures", f))
  wp(D1$R, "RAW_D1.parquet"); wp(D1$B, "BM_D1.parquet"); wp(D2$R, "RAW_D2.parquet"); wp(D2$B, "BM_D2.parquet")
  ENG <- file.path(SBX, "fixtures", "engine_close_rank.R")
  writeLines(c("# 합성 엔진 — 월 마지막 관측일(데이터 안) 종가 순위. 절단이 없으면 진행 중인 달의 마지막 날이 '월말' 시그널이 된다.",
               "FACTORS <- local({",
               "  x <- RAWDATA[, .(Date, Ticker, Close)]",
               "  x[, ym := format(Date, '%Y-%m')]",
               "  me <- x[, .(Date = max(Date)), by = ym]",
               "  x <- merge(x, me, by = c('ym', 'Date'))",
               "  x[, .(Date, Ticker, Score = Close)]",
               "})"), ENG)
  DRV <- file.path(SBX, "fixtures", "driver.R")
  writeLines(c(
    "args <- commandArgs(TRUE); SBX <- args[1]; OUT <- args[2]; MODE <- args[3]",
    "np <- function(p) tolower(normalizePath(p, winslash = '/', mustWork = FALSE))",
    "if (!identical(np(Sys.getenv('QM_ROOT')), np(SBX)) || !identical(np(Sys.getenv('CLAUDE_PROJECT_DIR')), np(SBX))) {",
    "  saveRDS(list(guard = 'env_not_sandbox', qm = Sys.getenv('QM_ROOT')), OUT); quit(status = 7) }",
    "setwd(SBX)",
    "suppressWarnings(suppressMessages(source(file.path(SBX, '02_Infrastructure/alpha_search/run_paper_replication.R'))))",
    "if (!identical(np(PROJECT_ROOT), np(SBX))) { saveRDS(list(guard = 'project_root_not_sandbox', pr = PROJECT_ROOT), OUT); quit(status = 7) }",
    "if (identical(MODE, 'mutant_nocut')) .rp_apply_data_cutoff <- function(RAWDATA, BM_DT, data_cutoff) {",
    "  co <- as.Date(data_cutoff); list(RAWDATA = RAWDATA, BM_DT = BM_DT, cutoff = co,",
    "    info = list(data_cutoff = format(co), raw_rows_dropped = 0L, bm_rows_dropped = 0L, raw_max_date_loaded = '', bm_max_date_loaded = '')) }",
    "put <- function(tag) { for (k in c('RAW', 'BM')) {",
    "  dst <- file.path(SBX, '.cache', if (k == 'RAW') 'RAWDATA.parquet' else 'benchmark.parquet')",
    "  stopifnot(file.copy(file.path(SBX, 'fixtures', sprintf('%s_%s.parquet', k, tag)), dst, overwrite = TRUE)) } }",
    "run1 <- function(tag, cut) {",
    "  put(tag); Sys.sleep(1.2)",
    "  r <- run_paper_replication('PFP_E2E', 'pin fingerprint e2e fixture', file.path(SBX, 'fixtures', 'engine_close_rank.R'),",
    "         portfolio_spec = list(construction = 'top_n_long', n_long = 5L, n_max = 5L, weighting = 'ew', rebalance = 'monthly'),",
    "         universe = 'K200_KQ150', source_paper = list(url = 'https://example.org/pfp', title = 'fixture'),",
    "         commission_paper = 0.0015, start_date = '2005-01-01', send_telegram = FALSE, factor_analysis = FALSE,",
    "         data_cutoff = cut)",
    "  bt <- readRDS(file.path(r$out_dir, 'bt_result.rds'))",
    "  au <- jsonlite::fromJSON(file.path(r$out_dir, 'authoritative_remeasure.json'), simplifyVector = FALSE)",
    "  pr <- as.data.frame(bt$period_returns)[, c('date', 'ret_gross', 'ret_net')]",
    "  list(grade = r$grade, essence = r$essence, pr = pr, mr = au$measurement_regime, out_dir = r$out_dir) }",
    "res <- if (identical(MODE, 'real')) list(",
    "  c1 = run1('D1', '2008-08-31'), c1b = run1('D1', '2008-08-31'), c2 = run1('D2', '2008-08-31'),",
    "  n1 = run1('D1', NULL), n2 = run1('D2', NULL)) else list(m2 = run1('D2', '2008-08-31'))",
    "saveRDS(res, OUT)"), DRV)
  ENVF <- file.path(SBX, "fixtures", "empty.Renviron"); writeLines(character(0), ENVF)
  JL <- file.path(SBX, ".cache", "test_jlog.jsonl")
  child <- function(mode) {
    out <- file.path(SBX, "fixtures", sprintf("res_%s.rds", mode))
    keep <- Sys.getenv(c("R_ENVIRON_USER", "QM_ROOT", "CLAUDE_PROJECT_DIR", "QVEST_RP_REGISTER", "QVEST_RP_NO_LCODE",
                         "QVEST_NO_LEDGER_OPEN", "QVEST_RUN_CONTEXT", "QVEST_RP_JLOG"), unset = NA)
    on.exit(for (k in names(keep)) if (is.na(keep[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(keep[[k]]), k)), add = TRUE)
    Sys.setenv(R_ENVIRON_USER = ENVF, QM_ROOT = SBX, CLAUDE_PROJECT_DIR = SBX, QVEST_RP_REGISTER = "0", QVEST_RP_NO_LCODE = "1",
               QVEST_NO_LEDGER_OPEN = "1", QVEST_RUN_CONTEXT = "test", QVEST_RP_JLOG = JL)
    rs <- file.path(R.home("bin"), "Rscript")
    log <- suppressWarnings(system2(rs, c(shQuote(DRV), shQuote(SBX), shQuote(out), mode), stdout = TRUE, stderr = TRUE))
    st <- attr(log, "status") %||% 0L
    if (!file.exists(out) || st != 0L) { cat(tail(log, 25), sep = "\n"); return(NULL) }
    readRDS(out)
  }
  t1 <- Sys.time(); R <- child("real")
  cat(sprintf("  (정본 종단 5회 %.0f초)\n", as.numeric(difftime(Sys.time(), t1, units = "secs"))))
  if (is.null(R) || !is.null(R$guard)) ng("C 종단 실행 실패", if (!is.null(R$guard)) R$guard else "자식 로그 위") else {
    same <- function(a, b) identical(a$pr, b$pr) && identical(a$essence, b$essence) && identical(a$grade, b$grade)
    chk(nrow(R$c1$pr) > 500 && max(as.Date(R$c1$pr$date)) <= CUT, "C1a 절단 판 — 수익 창이 cutoff 이하에서 끝난다",
        sprintf("n=%d max=%s", nrow(R$c1$pr), max(as.Date(R$c1$pr$date))))
    chk(same(R$c1, R$c1b), "C1b 같은 데이터·같은 cutoff 두 번 — 일간 수익·essence·등급 identical(비트 동일)")
    chk(same(R$c1, R$c2), "C2 cutoff 뒤 행 추가 사본(09-30 → 12-31) — 결과 불변(비트 동일)")
    chk(!identical(R$n1$pr, R$n2$pr) && max(as.Date(R$n2$pr$date)) > max(as.Date(R$n1$pr$date)),
        "C3 양성 대조 — 절단이 없으면 같은 두 사본의 결과가 갈린다(C2 가 공허하지 않다)")
    p07 <- c("data_cutoff", "data_fingerprint", "raw_rows_dropped", "bm_rows_dropped", "raw_max_date_loaded", "bm_max_date_loaded")
    chk(!any(p07 %in% names(R$n1$mr)) && all(c("selection_type", "exec_price", "harness_md5") %in% names(R$n1$mr)),
        "C4a 기본(NULL) 경로 — auth measurement_regime 에 P0-07 키 0(구판 모양 그대로)", paste(intersect(p07, names(R$n1$mr)), collapse = ","))
    mr <- R$c1$mr
    chk(identical(mr$data_cutoff, "2008-08-31") && identical(mr$raw_max_date_loaded, "2008-09-30") &&
          identical(mr$data_fingerprint$status, "ok") && identical(R$c2$mr$raw_max_date_loaded, "2008-12-31") &&
          all(c("Vol", "Size") %in% unlist(mr$data_fingerprint$raw_cols)),
        "C4b 절단 판 auth — data_cutoff·적재 최대일·지문 status · 소비 열(Vol·Size 포함) 기록",
        paste(unlist(mr$data_fingerprint$raw_cols), collapse = ","))
    ind1 <- FP$pin_fingerprint(CUT, raw_path = file.path(SBX, "fixtures/RAW_D1.parquet"), bm_path = file.path(SBX, "fixtures/BM_D1.parquet"),
                               fdb_dir = file.path(SBX, ".cache/factor_db"), root = SBX, code_root = SBX, engines = ENG)
    ind2 <- FP$pin_fingerprint(CUT, raw_path = file.path(SBX, "fixtures/RAW_D2.parquet"), bm_path = file.path(SBX, "fixtures/BM_D2.parquet"),
                               fdb_dir = file.path(SBX, ".cache/factor_db"), root = SBX, code_root = SBX, engines = ENG)
    chk(identical(mr$data_fingerprint$digest, ind1$digest) && identical(R$c2$mr$data_fingerprint$digest, ind1$digest) &&
          identical(ind1$digest, ind2$digest),
        "C5 auth 지문 = 파일에서 독립 계산한 지문(D1·D2 · 같은 엔진으로 재도출) — 원장 entry 지문과 digest 로 대조 가능",
        paste(mr$data_fingerprint$digest, ind1$digest, ind2$digest))
    M <- child("mutant_nocut")
    if (is.null(M) || !is.null(M$guard)) ng("C6 돌연변이 종단 실행 실패") else
      chk(!identical(M$m2$pr, R$c1$pr), "C6 돌연변이(절단 제거 · .rp_apply_data_cutoff 항등) — C2 불변성이 깨진다(red)")
    jl_ok <- !file.exists(JL) || !any(grepl("vintage", readLines(JL, warn = FALSE)))
    chk(jl_ok, "C7 셀 경로(QVEST_NO_LEDGER_OPEN=1)는 원장·빈티지 저널을 쓰지 않는다")
  }
}
unlink(SBX, recursive = TRUE); unlink(FD, recursive = TRUE)

cat(sprintf("\nTOTAL: %d pass / %d fail / %d skip\n", P, FL, SK))
cat(sprintf('{"test":"pin_fingerprint","pass":%d,"fail":%d,"skipped":%d,"total":%d}\n', P, FL, SK, P + FL + SK))
quit(save = "no", status = if (FL > 0L) 1L else 0L)
