#!/usr/bin/env Rscript
#==============================================================================
# test_rf_sleeve.R — B7 구조적 방어 슬리브 (도훈 지시 2026-09-21)
#
# 이 검사가 지키는 불변식:
#   ① k 는 정적이고 |SEL| = n_max 가 보존된다 (총노출·종목수 불변 = B5 와 갈리는 지점)
#   ② 팩터 id 는 규칙이 고른다 — as-of 약세장 IC(2026-09-24 P0-08 · 전기간 ic_bad 퇴역). 리터럴·전기간이 스며들면 잡는다.
#   ③ **처치 미전달을 멈춘다** — 방어 k종이 이미 알파 안에 있으면 보유가 그대로다.
#      그 칸을 통과시키면 '처치 없음'을 '처치 있음'으로 기록하게 된다.
#   ④ 대조군 2칸(베타매칭 무작위 · 부호 반전)이 격자에 실제로 있다. 이게 없으면
#      B5 가 137칸을 태우고 아무것도 주장 못 한 것과 같은 결말이 된다.
#
# ★R 문법: 최상위 `if` 다음 줄 `else` 는 파싱이 깨진다 — 단정은 chk() 한 줄로.
# 실행: cd <ROOT> && Rscript 08_Tests/reinforcement/test_rf_sleeve.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_sleeve.R")))

.pass <- 0L; .fail <- 0L
ok <- function(m) { .pass <<- .pass + 1L; cat(sprintf("  [OK] %s\n", m)) }
ng <- function(m, d = "") { .fail <<- .fail + 1L; cat(sprintf("  [NG] %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m_ok, m_ng, detail = "") if (isTRUE(cond)) ok(m_ok) else ng(m_ng, detail)
.err <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))

cat("== B7 방어 슬리브 ==\n")

# ── 픽스처: 12개월 x 60종. Score 와 방어값을 **반대로** 깔아 교체가 실제로 일어나게 한다 ──
set.seed(7)
N <- 60L; M <- 12L; NMAX <- 25L
PANEL <- CJ(Date = seq(as.Date("2020-01-31"), by = "month", length.out = M),
            Ticker = sprintf("T%02d", seq_len(N)))
PANEL[, i := as.integer(sub("T", "", Ticker))]
PANEL[, Score := -i + rnorm(.N, 0, 0.01)]          # i 작을수록 알파 상위
# ★방어값은 Score 와 **독립**이어야 한다. 완전 역순(.zdef = i)으로 깔면 "반방어 하위 k종"이
#   곧 "알파 21~25위" 가 되어 기저 선정과 똑같아지고, 처치 미전달 가드가(옳게) 멈춘다.
#   실데이터에서도 방어 팩터가 알파와 강하게 역상관이면 같은 퇴화가 난다 — 그건 가드가 잡는다.
PANEL[, .zdef := runif(.N)]
PANEL[, .zbeta := i / N]
SEL0 <- PANEL[order(Date, -Score)][, head(.SD, NMAX), by = Date]

# ── 파싱 ────────────────────────────────────────────────────────────────────
chk(is.null(rf_sl_parse(NULL)), "P1 규칙 없음 → NULL (기존 경로 그대로)", "P1")
chk(grepl("미지원 kind", .err(rf_sl_parse(list(kind = "magic", k = 5))) %||% ""),
    "P2 미지원 kind 는 멈춘다(침묵 폴백 금지)", "P2 미지원 kind 통과")
chk(grepl("알 수 없는 인자", .err(rf_sl_parse(list(kind = "factor_topk", k = 5, zzz = 1))) %||% ""),
    "P3 알 수 없는 인자는 멈춘다", "P3")
chk(grepl("k 는", .err(rf_sl_parse(list(kind = "factor_topk", k = 0))) %||% ""),
    "P4 k<1 은 멈춘다", "P4")

RULE5 <- rf_sl_parse(list(kind = "factor_topk", k = 5))
RULE8 <- rf_sl_parse(list(kind = "factor_topk", k = 8))

# ── 선정 ────────────────────────────────────────────────────────────────────
S5 <- rf_sl_select(PANEL, SEL0, RULE5, NMAX, defcol = ".zdef")
chk(all(S5[, .N, by = Date]$N == NMAX),
    sprintf("S1 종목수 보존 — 전 월 %d종(총노출·종목수 불변)", NMAX), "S1 종목수 깨짐",
    paste(unique(S5[, .N, by = Date]$N), collapse = ","))

ov <- rf_sl_turnover_overlap(SEL0, S5)
chk(is.finite(ov) && ov > 0.5 && ov < 1,
    sprintf("S2 보유가 실제로 갈렸다 — 겹침 %.1f%% (전부도 아니고 없지도 않다)", 100 * ov),
    "S2 교체가 없거나 전면", sprintf("%.3f", ov))

# 방어 슬리브가 **알파가 안 고른 이름**에서 왔는가
newnames <- setdiff(S5$Ticker, SEL0$Ticker)
chk(length(newnames) > 0L, sprintf("S3 새 이름 %d종이 알파 밖에서 들어왔다", length(newnames)), "S3 새 이름 없음")

# k 를 키우면 교체가 더 커진다(분할 비율 축이 실제로 작동)
S8 <- rf_sl_select(PANEL, SEL0, RULE8, NMAX, defcol = ".zdef")
chk(rf_sl_turnover_overlap(SEL0, S8) < ov,
    "S4 k=8 이 k=5 보다 더 많이 갈아끼운다(분할 비율이 축으로 작동)", "S4 k 가 안 먹는다")

# ── ★처치 미전달 가드 (양성 대조) ───────────────────────────────────────────
#   방어값을 Score 와 **같은 방향**으로 깔면 방어 상위 k종이 이미 알파 안에 있다 →
#   보유가 그대로다. 그 칸을 통과시키면 '처치 없음'이 '처치 있음'으로 기록된다.
P2 <- copy(PANEL)[, .zdef := Score]
e <- .err(rf_sl_select(P2, SEL0, RULE5, NMAX, defcol = ".zdef"))
chk(!is.na(e) && grepl("처치 미전달", e),
    "S5 [양성 대조] 방어 k종이 이미 알파 안 → 엔진이 멈춘다", "S5 무처치를 통과시켰다", e %||% "오류 없음")

chk(grepl("k .* >= n_max|알파 슬리브가 사라진다", .err(rf_sl_select(PANEL, SEL0, rf_sl_parse(list(kind="factor_topk", k=NMAX)), NMAX, ".zdef")) %||% ""),
    "S6 k >= n_max 는 멈춘다(알파가 사라지는 칸)", "S6")

# ── 대조군 2종 ──────────────────────────────────────────────────────────────
SA <- rf_sl_select(PANEL, SEL0, rf_sl_parse(list(kind = "antidefense", k = 5)), NMAX, ".zdef")
# ★월별로 본다. 12개월을 뭉쳐 setdiff 하면 오귀속이다 — 방어값이 월마다 다시 뽑히므로 한 종목이
#   1월엔 방어 상위, 2월엔 하위일 수 있다(초판 단정이 그래서 빨갛게 나왔다: 코드가 아니라 비교 축의 오류).
.pick <- function(X) X[!SEL0, on = c("Date","Ticker")][, .(t = list(sort(as.character(Ticker)))), by = Date]
.ov_m <- merge(.pick(S5), .pick(SA), by = "Date")
.bad <- sum(vapply(seq_len(nrow(.ov_m)), function(i)
  length(intersect(.ov_m$t.x[[i]], .ov_m$t.y[[i]])), integer(1)))
chk(nrow(.ov_m) > 0L && .bad == 0L,
    sprintf("C1 [부호 반전] 월별로 방어/반방어 슬리브가 한 종목도 안 겹친다 (%d개월)", nrow(.ov_m)),
    "C1 반전이 같은 이름을 골랐다", sprintf("겹친 종목-월 %d", .bad))

RB <- rf_sl_parse(list(kind = "random_beta_matched", k = 5, seed = 11L))
SR1 <- rf_sl_select(PANEL, SEL0, RB, NMAX, ".zdef", betacol = ".zbeta")
SR2 <- rf_sl_select(PANEL, SEL0, RB, NMAX, ".zdef", betacol = ".zbeta")
chk(identical(sort(SR1$Ticker), sort(SR2$Ticker)),
    "C2 [무신호 대조] 같은 seed → 같은 결과(재현 가능)", "C2 대조군이 비결정론")
.ref <- PANEL[order(Date, -.zdef)][, head(.SD, 5), by = Date][, .(lo = min(.zbeta), hi = max(.zbeta)), by = Date]
.got <- merge(SR1[!SEL0, on = c("Date","Ticker")], .ref, by = "Date")
chk(nrow(.got) > 0L && all(.got$.zbeta >= .got$lo & .got$.zbeta <= .got$hi),
    "C3 [무신호 대조] 무작위 슬리브가 방어 슬리브의 **베타 구간 안**에서 뽑힌다", "C3 베타매칭 실패")
chk(grepl("베타", .err(rf_sl_select(PANEL, SEL0, RB, NMAX, ".zdef", betacol = NULL)) %||% ""),
    "C4 베타 컬럼 없이 무신호 대조를 돌리면 멈춘다(조용히 비매칭 금지)", "C4")

# ── 규칙 해석 — 리터럴 금지 · as-of (2026-09-24 P0-08: 구 ic_bad_rank 퇴역 → ic_bad_rank_asof) ──
#   ★축을 옮겼으니 양성 대조도 옮긴다: 등록부의 저장 ic_bad(전기간)가 아니라 as-of 약세장 IC 로 순위가 정해져야 한다.
#   픽스처: DA 는 as-of 이전 약세장에서 IC 가 높고 이후 낮다, DB 는 반대 — 전기간이면 DB, as-of 면 DA 가 1위.
#   저장 ic_bad 는 **일부러 반대로**(DB 가 높게) 깔아 둔다 — 신판이 그 값을 읽으면 R1 이 빨개진다.
.tmp <- file.path(tempdir(), paste0("sl_", paste(sample(letters, 6), collapse = "")))
dir.create(file.path(.tmp, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
write(toJSON(list(factors = list(
  DA = list(category = "defense", lifecycle_status = "active", ic_bad = 0.01, ic_good = 0.01),
  DB = list(category = "defense", lifecycle_status = "active", ic_bad = 0.09, ic_good = 0.02),
  DX = list(category = "defense", lifecycle_status = "deprecated", ic_bad = 0.99, ic_good = 0.0),
  VV = list(category = "value",   lifecycle_status = "active", ic_bad = 0.90, ic_good = 0.5))),
  auto_unbox = TRUE), file.path(.tmp, "06_Registry/factor_evidence.json"))
.wprog <- function(root, cfg = list(bear_quantile = 0.3, min_bear_months = 4L, candidate_categories = c("defense", "risk"),
                                    rank_key = "ic_bad", ic_path = "ic.parquet", bench_path = "bm.parquet",
                                    bench_price_col = "BM_Close"), start = "2004-01-01")
  write(toJSON(list(fixed_axes = list(start_date = start),
                    blocks = list(list(id = "B7", selection_asof = cfg))), auto_unbox = TRUE, null = "null"),
        file.path(root, "06_Registry/reinforce_program.json"))
.wprog(.tmp)
.me <- seq(as.Date("2000-02-01"), by = "month", length.out = 84L) - 1L          # 형성일 = 월말 2000-01..2006-12
.ue <- seq(as.Date("2000-03-01"), by = "month", length.out = 84L) - 1L          # 가용일 = 다음 월말(보유월 말)
.bm <- data.table(hm = format(.ue, "%Y-%m"), ret = ifelse(seq_along(.ue) %% 3L == 0L, -0.08, 0.02), hend = .ue)
.bear <- .bm$ret < 0
.ic <- rbindlist(lapply(c("DA", "DB", "DX", "VV"), function(f) data.table(
  Factor_Name = f, Date = .me, Usable_Date = .ue,
  IC = switch(f, DA = ifelse(.bear, ifelse(.ue <= as.Date("2003-12-31"), 0.20, -0.20), 0),
                 DB = ifelse(.bear, ifelse(.ue <= as.Date("2003-12-31"), -0.10, 0.30), 0),
                 DX = 0.9, VV = 0.9))))
Sys.unsetenv("RF_CELL_SPEC")
chk(grepl("퇴역", .err(rf_sl_parse(list(kind = "factor_topk", k = 5, select = "ic_bad_rank"))) %||% ""),
    "R0 퇴역 select(ic_bad_rank · 전표본 C1) 는 파싱에서 멈춘다", "R0 퇴역 규칙이 통과했다")
chk(is.na(.err(rf_sl_parse(list(kind = "factor_topk", k = 5, select = "ic_bad_rank", factor_id = "D22_Tracking_Error")))),
    "R0b factor_id 고정이면 select 는 안 쓰이므로 통과(과거 칸 재현 경로)", "R0b 재현 경로가 막혔다")
r1 <- rf_sl_resolve(RULE5, .tmp, IC = .ic, BM = .bm); r2 <- rf_sl_resolve(rf_sl_parse(list(kind="factor_topk", k=5, rank=2)), .tmp, IC = .ic, BM = .bm)
chk(identical(r1$id, "DA") && identical(r2$id, "DB") && identical(r1$asof, "2004-01-01"),
    sprintf("R1 as-of(격자 시작일 %s) 약세장 IC 내림차순 — 1위 %s · 2위 %s (저장 ic_bad 는 반대)", r1$asof, r1$id, r2$id),
    "R1 순서 틀림(저장 전기간 ic_bad 를 읽었나)", paste(r1$id, r2$id, r1$asof))
# ★R1b 대조(2026-09-25 R3 개정): 구판은 인자 as-of 2099 로 전기간을 흉내 냈다 — 상한 가드(결정 시점 = 셀·격자 시작일)가
#   그 경로를 막으므로(R1c) 결정 시점 자체를 뒤로 민 격자(시작일 2007-01-01)로 같은 대조를 한다(as-of = 결정 시점 · 통과 경로).
.tmp3 <- file.path(tempdir(), paste0("sl3_", paste(sample(letters, 6), collapse = "")))
dir.create(file.path(.tmp3, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(.tmp, "06_Registry/factor_evidence.json"), file.path(.tmp3, "06_Registry/factor_evidence.json"))
.wprog(.tmp3, start = "2007-01-01")
rF <- tryCatch(rf_sl_resolve(RULE5, .tmp3, IC = .ic, BM = .bm), error = function(e) list(id = paste("ERR", conditionMessage(e))))
chk(identical(rF$id, "DB"), "R1b 대조 — 결정 시점(격자 시작일)을 표본 끝(2007-01)으로 두면 1위가 DB 로 바뀐다(as-of 가 실제로 먹는다)",
    "R1b as-of 가 결과를 안 바꾼다", rF$id)
# R1c~R1f (R3 · 2026-09-25) as-of 상한 가드 — 결정 시점(여기 = 격자 시작일 2004-01-01) 뒤·미래·NA 는 stop
chk(grepl("미래", .err(rf_sl_resolve(RULE5, .tmp, asof = "2099-01-01", IC = .ic, BM = .bm)) %||% ""),
    "R1c 인자 as-of 2099(구 R1b 경로) → stop(미래 · 전기간 선정 금지)", "R1c 미래 as-of 가 통과했다")
chk(grepl("결정 시점", .err(rf_sl_resolve(RULE5, .tmp, asof = "2005-06-30", IC = .ic, BM = .bm)) %||% ""),
    "R1d 인자 as-of 2005-06-30 > 결정 시점 2004-01-01 → stop", "R1d 결정 시점 뒤 as-of 가 통과했다")
chk(grepl("결정 시점", .err(rf_sl_resolve(rf_sl_parse(list(kind = "factor_topk", k = 5, asof = "2006-12-31")), .tmp, IC = .ic, BM = .bm)) %||% ""),
    "R1e 규칙 asof(셀 스펙 defense_sleeve.asof) 2006-12-31 > 결정 시점 → stop", "R1e 규칙 as-of 가 통과했다")
chk(grepl("NA", .err(rf_sl_resolve(RULE5, .tmp, asof = NA, IC = .ic, BM = .bm)) %||% ""),
    "R1f 인자 as-of NA → stop(구판은 조용히 기본값으로 갔다)", "R1f NA as-of 가 통과했다")
rE <- tryCatch(rf_sl_resolve(RULE5, .tmp, asof = "2003-12-31", IC = .ic, BM = .bm), error = function(e) list(id = paste("ERR", conditionMessage(e))))
chk(identical(rE$id, "DA") && identical(rE$asof_bound, "2004-01-01"),
    "R1g [양성] 결정 시점보다 이른 as-of 2003-12-31 → 통과(1위 DA · 상한 = 격자 2004-01-01)", "R1g 이른 as-of 가 막혔거나 상한(asof_bound)이 안 실렸다",
    paste(rE$id, rE$asof_bound))
chk(!("DX" %in% c(r1$id, r2$id)) && !("VV" %in% c(r1$id, r2$id)),
    "R2 deprecated 와 비방어 계열은 후보에서 빠진다", "R2 자격 필터 미작동")
chk(grepl("rank", .err(rf_sl_resolve(rf_sl_parse(list(kind="factor_topk", k=5, rank=99)), .tmp, IC = .ic, BM = .bm)) %||% ""),
    "R3 rank 초과는 멈춘다", "R3")
.tmp2 <- file.path(tempdir(), paste0("sl2_", paste(sample(letters, 6), collapse = "")))
dir.create(file.path(.tmp2, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(.tmp, "06_Registry/factor_evidence.json"), file.path(.tmp2, "06_Registry/factor_evidence.json"))
write(toJSON(list(fixed_axes = list(start_date = "2004-01-01"), blocks = list(list(id = "B7"))), auto_unbox = TRUE),
      file.path(.tmp2, "06_Registry/reinforce_program.json"))
chk(grepl("selection_asof", .err(rf_sl_resolve(RULE5, .tmp2, IC = .ic, BM = .bm)) %||% ""),
    "R4 격자에 B7.selection_asof 가 없으면 멈춘다(분위·표본을 코드에 박지 않는다)", "R4 설정 없이 돌았다")
.wprog(.tmp2, start = NULL)
chk(grepl("as-of 미해석", .err(rf_sl_resolve(RULE5, .tmp2, IC = .ic, BM = .bm)) %||% ""),
    "R5 as-of 를 어디서도 못 정하면 멈춘다(전기간으로 계산하지 않는다 · C1)", "R5 as-of 없이 돌았다")

# ── B7-EXCL 후보 제외 (2026-10-03 · 결정 FLOOR-F1-SEED-B7-OVERLAP · PR-L2-B7-EXCL-UNIT (c) id 단위) ──
#   픽스처(.tmp): as-of 1위 DA · 2위 DB · DX deprecated · VV 비방어. 기저 팩터에 DA 가 있으면 제외 뒤 1위 = DB(rank = 제외 뒤 순위).
cat("-- B7-EXCL 후보 제외 --\n")
RX <- rf_sl_parse(list(kind = "factor_topk", k = 5, exclude = "base_factors"))
chk(identical(RX$exclude, "base_factors") && identical(RULE5$exclude, ""),
    "X0 exclude 파싱 — base_factors 보존 · 키 없으면 ''(구판 거동)", "X0 파싱", paste(RX$exclude, RULE5$exclude))
chk(grepl("미지원 exclude", .err(rf_sl_parse(list(kind = "factor_topk", k = 5, exclude = "family"))) %||% "") &&
      grepl("미지원 exclude", .err(rf_sl_parse(list(kind = "factor_topk", k = 5, exclude = c("base_factors", "x")))) %||% ""),
    "X1 미지원·복수 exclude 값 → stop(계열 단위 'family' 는 결정 (c) 밖 — 조용히 받지 않는다)", "X1 미지원 exclude 통과")
x1 <- tryCatch(rf_sl_resolve(RX, .tmp, IC = .ic, BM = .bm, exclude_ids = c("DA", "IN05_Net_Debt_Issuance")), error = function(e) list(id = paste("ERR", conditionMessage(e))))
chk(identical(x1$id, "DB") && identical(x1$excluded_in_pool, "DA") && setequal(x1$excluded_ids, c("DA", "IN05_Net_Debt_Issuance")) &&
      identical(x1$exclude_rule, "base_factors") && grepl("기저 팩터 제외 2종(풀 안 1: DA)", x1$basis, fixed = TRUE),
    "X2 [양성] 기저 팩터 DA 제외 → 1위 DB · 풀 안 제외 = DA · basis 에 제외 기록", "X2 제외가 순위에 안 먹는다", paste(x1$id, x1$basis))
x3 <- tryCatch(rf_sl_resolve(RX, .tmp, IC = .ic, BM = .bm, exclude_ids = "ZZ_NOT_IN_POOL"), error = function(e) list(id = paste("ERR", conditionMessage(e))))
chk(identical(x3$id, "DA") && !length(x3$excluded_in_pool) && grepl("풀 안 0: 없음", x3$basis, fixed = TRUE),
    "X3 풀 밖 id 만 제외 → 순위 불변(DA) · 풀 안 제외 0 기록", "X3", paste(x3$id, x3$basis))
chk(grepl("받지 못했다", .err(rf_sl_resolve(RX, .tmp, IC = .ic, BM = .bm)) %||% "") &&
      grepl("받지 못했다", .err(rf_sl_resolve(RX, .tmp, IC = .ic, BM = .bm, exclude_ids = character(0))) %||% "") &&
      grepl("받지 못했다", .err(rf_sl_resolve(RX, .tmp, IC = .ic, BM = .bm, exclude_ids = c(NA, ""))) %||% ""),
    "X4 규칙이 있는데 제외 집합이 NULL·빈·결측 → stop(제외를 조용히 건너뛰지 않는다)", "X4 빈 제외 집합이 통과")
r1b <- rf_sl_resolve(RULE5, .tmp, IC = .ic, BM = .bm, exclude_ids = c("DA"))
chk(identical(r1b$id, r1$id) && identical(r1b$basis, r1$basis) && identical(r1b$exclude_rule, ""),
    "X5 [구판 비트 동일] 규칙 없는 칸은 exclude_ids 를 받아도 무시 — id·basis 문자열 구판 그대로", "X5 규칙 없는 칸이 바뀌었다",
    paste(r1b$id, r1b$basis))
chk(grepl("모순 스펙", .err(rf_sl_resolve(rf_sl_parse(list(kind = "factor_topk", k = 5, factor_id = "DA", exclude = "base_factors")),
                                         .tmp, exclude_ids = "DA")) %||% ""),
    "X6 factor_id 고정이 제외 집합에 들면 stop(모순)", "X6 모순 스펙 통과")
chk(grepl("rank", .err(rf_sl_resolve(rf_sl_parse(list(kind = "factor_topk", k = 5, rank = 2, exclude = "base_factors")),
                                    .tmp, IC = .ic, BM = .bm, exclude_ids = "DA")) %||% ""),
    "X7 rank 는 제외 뒤 순위 — 자격 1종(DB)만 남으면 rank 2 는 stop", "X7 rank 가 제외 전 순위로 셌다")
xr <- tryCatch(rf_sl_resolve(rf_sl_parse(list(kind = "random_beta_matched", k = 5, exclude = "base_factors")), .tmp, IC = .ic, BM = .bm,
                             exclude_ids = "DA"), error = function(e) list(id = "ERR"))
xa <- tryCatch(rf_sl_resolve(rf_sl_parse(list(kind = "antidefense", k = 5, exclude = "base_factors")), .tmp, IC = .ic, BM = .bm,
                             exclude_ids = "DA"), error = function(e) list(id = "ERR"))
chk(identical(xr$id, "DB") && identical(xa$id, "DB"),
    "X8 대조(베타매칭 무작위·반방어)도 같은 제외가 걸린다 — 기준 팩터 = 처치와 같은 DB(귀속 성립)", "X8 대조에 제외 미적용", paste(xr$id, xa$id))

# ── 처치 전달량 rf_sl_delivery (결정 PR-L2-B7-EXCL-UNIT (c)) ──
cat("-- 처치 전달량 --\n")
D5 <- rf_sl_delivery(SEL0, S5, RULE5, NMAX)
.nw <- merge(S5[, .(a = list(as.character(Ticker))), by = Date], SEL0[, .(b = list(as.character(Ticker))), by = Date], by = "Date")
.nn <- vapply(seq_len(nrow(.nw)), function(i) length(setdiff(.nw$a[[i]], .nw$b[[i]])), integer(1))
chk(all(D5$rows$n_sleeve == 5L) && all(D5$rows$n_new == .nn) && isTRUE(all.equal(D5$summary$pooled, sum(.nn) / (5 * nrow(.nw)))) &&
      isTRUE(all.equal(D5$summary$mean_by_date, mean(.nn / 5))),
    sprintf("D1 전달량 재도출 — 슬리브 자리 5 · 바닥에 없던 이름 수 = 독립 setdiff · 평균 %.3f · 합산 %.3f", D5$summary$mean_by_date, D5$summary$pooled),
    "D1 전달량 계산 불일치")
# 희석 픽스처: 방어값을 '알파 21~23위'(바닥 하위 자리 3)에 가장 높게 · 24~25위에 가장 낮게 깔면 슬리브 5자리 중 3자리가
#   바닥 이름을 다시 고른다 → 전 시그널일 전달량 = 2/5 · n_kept_floor = 3. 보유는 매달 2종 바뀌므로 처치 미전달 가드(99% 동일)는
#   **통과**한다 — 가드가 못 보는 희석이라 전달량을 따로 잰다(결정 (c)의 존재 이유).
PD <- copy(PANEL); PD[, .rk := frank(-Score, ties.method = "first"), by = Date]
PD[, .zdef := fifelse(.rk > 20L & .rk <= 23L, 10 + runif(.N), fifelse(.rk > 23L & .rk <= 25L, -10, runif(.N)))]
SD0 <- tryCatch(rf_sl_select(PD, SEL0, RULE5, NMAX, defcol = ".zdef"), error = function(e) NULL)
D0 <- if (!is.null(SD0)) rf_sl_delivery(SEL0, SD0, RULE5, NMAX) else NULL
chk(!is.null(D0) && isTRUE(all.equal(D0$summary$mean_by_date, 0.4)) && isTRUE(all.equal(D0$summary$pooled, 0.4)) &&
      all(D0$rows$n_kept_floor == 3L) && isTRUE(D0$summary$share_zero == 0),
    "D2 [희석 양성 대조] 슬리브 5자리 중 3자리가 바닥 하위 이름 재선택 → 전달량 0.4 · n_kept_floor 3 (처치 미전달 가드는 통과하는 희석)",
    "D2 희석을 못 잡는다", if (is.null(D0)) "선정 실패(가드 발화?)" else sprintf("%.3f", D0$summary$mean_by_date))
PZ <- copy(PANEL); PZ[, .rk := frank(-Score, ties.method = "first"), by = Date]
PZ[, .zdef := fifelse(.rk > 20L & .rk <= 25L, 10 + runif(.N), runif(.N))]
chk(grepl("처치 미전달", .err(rf_sl_select(PZ, SEL0, RULE5, NMAX, defcol = ".zdef")) %||% ""),
    "D2b 전 자리 희석(전달량 0 · 보유 100% 동일)은 기존 처치 미전달 가드가 먼저 멈춘다 — 전달량 계기는 그 아래 구간(부분 희석)을 잰다", "D2b")
SF <- rf_sl_select(copy(PANEL)[, .zdef := -Score], SEL0, RULE5, NMAX, defcol = ".zdef")
DF <- rf_sl_delivery(SEL0, SF, RULE5, NMAX)
chk(isTRUE(DF$summary$mean_by_date == 1) && isTRUE(DF$summary$share_full == 1),
    "D3 [완전 전달] 방어 = 알파 역순(비선정 꼬리) → 전 시그널일 전달량 1", "D3", sprintf("%.3f", DF$summary$mean_by_date))
BAD <- copy(S5)[, Ticker := paste0(Ticker, "_x")]          # 알파 슬리브까지 바뀐 '보유' — 슬리브 자리보다 새 이름이 많다
chk(grepl("불변식 위반", .err(rf_sl_delivery(SEL0, BAD, RULE5, NMAX)) %||% ""),
    "D4 n_new > 슬리브 자리(계산 어긋남) → stop", "D4 불변식 위반 통과")

# ── 서명 · 격자 · 배선 (재도출) ─────────────────────────────────────────────
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))
base <- list(factors = list(list(kind = "db", id = "X1")), weighting = list(kind = "ew"))
chk(identical(.spec_sig(base), .spec_sig(base)), "G0 서명 결정론", "G0")
s5 <- base; s5$defense_sleeve <- list(kind = "factor_topk", k = 5)
s8 <- base; s8$defense_sleeve <- list(kind = "factor_topk", k = 8)
chk(!identical(.spec_sig(s5), .spec_sig(s8)), "G1 k=5 와 k=8 이 다른 칸으로 갈린다", "G1 서명이 접힌다")
chk(identical(.spec_sig(base), .spec_sig(base)) && !grepl("defense", .spec_sig(base)),
    "G2 defense_sleeve 없는 스펙 서명은 구판 그대로", "G2 구판 서명 오염")
s5x <- s5; s5x$defense_sleeve$exclude <- "base_factors"
chk(!identical(.spec_sig(s5x), .spec_sig(s5)), "G2b exclude 를 건 칸은 구 B7 칸과 다른 서명(접히지 않는다)", "G2b 제외 칸이 구 칸으로 접힌다")

PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
ids <- vapply(PROG$blocks, function(b) as.character(b$id %||% ""), character(1))
b7 <- Filter(function(b) identical(b$id, "B7"), PROG$blocks)
chk(length(b7) == 1L && identical(b7[[1]]$axis, "structural_defense"),
    "G3 격자에 B7(structural_defense) 블록", "G3 블록 없음", paste(ids, collapse = ","))
chk(which(ids == "B7") < which(ids == "B4"), "G4 B7 이 결합(B4)보다 앞", "G4 순서")
if (length(b7) == 1L) {
  kinds <- vapply(b7[[1]]$cells, function(c) as.character(c$defense_sleeve$kind %||% ""), character(1))
  chk(sum(kinds %in% c("random_beta_matched", "antidefense")) == 2L,
      "G5 대조군 2칸(베타매칭 무작위 · 부호 반전)이 격자에 실재", "G5 대조군 누락", paste(kinds, collapse = ","))
  ks <- vapply(b7[[1]]$cells, function(c) as.integer(c$defense_sleeve$k %||% NA), integer(1))
  chk(length(unique(ks[!is.na(ks)])) >= 2L, "G6 분할 비율 k 가 축으로 스윕된다", "G6 k 단일값")
}

LED <- readLines(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), warn = FALSE)
chk(any(grepl("structural_defense", LED)),
    "G7 원장 축 허용목록에 structural_defense (없으면 블록 등록이 거부된다)", "G7 축 미등록")

NP <- parse(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"))
.has <- function(exprs, want) {
  hit <- FALSE
  walk <- function(x) {
    if (is.call(x)) {
      nm <- names(as.list(x))
      if (length(nm) && want %in% nm) hit <<- TRUE
      for (i in seq_along(x)) if (!is.null(x[[i]])) try(walk(x[[i]]), silent = TRUE)
    } else if (is.pairlist(x) || is.list(x)) {
      for (i in seq_along(x)) if (!is.null(x[[i]])) try(walk(x[[i]]), silent = TRUE)
    }
  }
  for (e in exprs) walk(e)
  hit
}
## ★B4-SIX-AXIS(2026-09-26 · 10-03 차등 회귀): 교체 축(비중·유니버스·집행 주기·방어 슬리브)은 축 등록부(rf_spec_axes.R::rf_axes_cell_init)로 싣는다 —
##   직접 인자(구판) **또는** 러너가 rf_axes_cell_init 을 부르고 등록부가 셀의 defense_sleeve 를 그대로 싣는다(행동 대조). 등록부에서 축을 지우면 red.
.calls <- function(exprs, fn) {
  hit <- FALSE
  walk <- function(x) {
    if (is.call(x)) { if (identical(x[[1]], as.name(fn))) hit <<- TRUE
      for (i in seq_along(x)) if (!is.null(x[[i]])) try(walk(x[[i]]), silent = TRUE)
    } else if (is.pairlist(x) || is.list(x)) for (i in seq_along(x)) if (!is.null(x[[i]])) try(walk(x[[i]]), silent = TRUE)
  }
  for (e in exprs) walk(e)
  hit
}
.ax_ds <- local({ f <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_axes.R")
  if (!file.exists(f)) FALSE else tryCatch({ ae <- new.env(); sys.source(f, envir = ae); ds <- list(kind = "factor_topk", k = 5L, select = "ic_bad_rank_asof")
    identical(ae$rf_axes_cell_init(list(code = "B7_37", defense_sleeve = ds))[["defense_sleeve"]], ds) }, error = function(e) FALSE) })
chk(.has(NP, "defense_sleeve") || (.calls(NP, "rf_axes_cell_init") && isTRUE(.ax_ds)),
    "G8 러너가 SPEC 에 defense_sleeve 를 싣는다(직접 또는 축 등록부 rf_axes_cell_init — 안 실으면 엔진은 알파 단독)", "G8 러너 미배선")

cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail))
# 배터리 요약 계약(run_all_hooks.sh — 요약 JSON 없으면 UNMEASURED) · 2026-09-25 SUITES 편입과 함께 추가
cat(sprintf('{"test":"rf_sleeve","pass":%d,"fail":%d,"total":%d}\n', .pass, .fail, .pass + .fail))
if (.fail > 0L) quit(status = 1L)
