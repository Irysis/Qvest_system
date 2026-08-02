#==============================================================================
# test_factor_dup_scan.R — 팩터 중복 스캐너 + registry de-dup 계약 검사기
#
# 계약:
#   (1) 스캐너는 **주입한 중복을 실제로 잡아야** 한다 (위반 주입 테스트).
#   (2) 스캐너는 중복이 없을 때 **아무것도 만들어내지 않아야** 한다 (음성 대조).
#   (3) 중복과 '그냥 상관 높음'(cor~0.80)을 **구별**해야 한다 — 음성 대조가
#       "완전 무상관 패널"뿐이면 문턱이 망가져도(예: 0.5로) 통과한다.
#   (4) registry 의 dedup 블록은 구조적으로 성립해야 한다 (canonical 실재 /
#       alias 체인 금지 / 양방향 일치).
#   (5) registry 2벌(02_Infrastructure, .cache)은 동일해야 한다.
#
# ★배경: 오탐 제거와 검사 사망은 겉보기가 같다. "중복 0건"이 스캐너가 죽어서인지
#   정말 깨끗해서인지는 주입 없이 구별할 수 없다.
#   적발 계기 = WT-D20260802_003 (D01_IdioVol ~ R12_Idiosyncratic_Risk cor=1.0000).
#==============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a)) b else a

## 자기 스크립트 위치를 **1순위**로 둔다: worktree 에서 이 테스트를 돌리면
## worktree 를 검사해야 한다 (main 을 조용히 검사하면 "초록"이 무의미해진다).
## 그 다음이 CLAUDE_PROJECT_DIR / QM_ROOT. 어느 후보든 marker 로 정체성을 검증한다.
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (!length(f)) return("")
  tryCatch(normalizePath(dirname(f[1]), winslash = "/", mustWork = TRUE), error = function(e) "")
}
.resolve_proj <- function() {
  sd <- .script_dir()
  self_root <- if (nzchar(sd)) normalizePath(file.path(sd, "..", ".."), winslash = "/", mustWork = FALSE) else ""
  cands <- c(self_root,
             Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/factor_db/factor_dup_scan.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 (marker=", marker, ")")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok   <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad  <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
skip <- function(n, m = "") { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP: %s — %s\n", n, m)) }

source(file.path(PROJ, "02_Infrastructure/factor_db/factor_dup_scan.R"))

#==============================================================================
# 합성 패널 loader — 운영 load_month_factors 를 대체 주입
#==============================================================================
# inject=TRUE  : 중복 3종(exact / near~0.97 / mirror=-1) + 대조 1종(mild~0.80)
# inject=FALSE : 독립 노이즈만 (음성 대조)
#
# cor(x, x + k*e) = 1/sqrt(1+k^2)  ->  k = sqrt(1/rho^2 - 1)
.k_for_rho <- function(rho) sqrt(1 / rho^2 - 1)

make_loader <- function(inject = TRUE, n_ticker = 200L, seed = 20260802L,
                        sparse_pair = TRUE) {
  force(inject)
  function(sig_date, factor_names, coverage_min) {
    # 월별 재현 가능한 시드 (월마다 다른 표본, 실행마다 동일)
    set.seed(seed + as.integer(as.Date(sig_date)))
    tick <- sprintf("T%04d", seq_len(n_ticker))
    base <- c("B01", "B02", "B03", "B04", "B05", "B06")
    cols <- list()
    for (b in base) cols[[b]] <- rnorm(n_ticker)

    if (inject) {
      a <- rnorm(n_ticker)
      cols[["F_EXACT_A"]] <- a
      cols[["F_EXACT_B"]] <- a                                   # 완전 중복
      c0 <- rnorm(n_ticker)
      cols[["F_NEAR_A"]]  <- c0
      cols[["F_NEAR_B"]]  <- c0 + .k_for_rho(0.97) * rnorm(n_ticker)   # 근사 중복
      e0 <- rnorm(n_ticker)
      cols[["F_MIRROR_A"]] <- e0
      cols[["F_MIRROR_B"]] <- -e0                                # 부호 반전 중복
      g0 <- rnorm(n_ticker)
      cols[["F_MILD_A"]]  <- g0
      cols[["F_MILD_B"]]  <- g0 + .k_for_rho(0.80) * rnorm(n_ticker)   # 중복 아님(대조)
      if (sparse_pair) {
        # min_obs 게이트 검사용: 공통 관측이 10종목뿐인 완전 중복 쌍
        s <- rep(NA_real_, n_ticker); s[1:10] <- rnorm(10)
        cols[["F_SPARSE_A"]] <- s
        cols[["F_SPARSE_B"]] <- s
      }
    }

    dt <- rbindlist(lapply(names(cols), function(fn)
      data.table(Ticker = tick, Factor_Name = fn, Z_Score_Aligned = cols[[fn]])))
    dt <- dt[!is.na(Z_Score_Aligned)]
    if (!is.null(factor_names)) dt <- dt[Factor_Name %in% factor_names]
    dt[]
  }
}

MONTHS <- seq(as.Date("2020-02-01"), as.Date("2021-01-01"), by = "month") - 1L
GRID_INJ <- c("B01","B02","B03","B04","B05","B06",
              "F_EXACT_A","F_EXACT_B","F_NEAR_A","F_NEAR_B",
              "F_MIRROR_A","F_MIRROR_B","F_MILD_A","F_MILD_B",
              "F_SPARSE_A","F_SPARSE_B")
GRID_CTL <- c("B01","B02","B03","B04","B05","B06")

.verdict_of <- function(tbl, a, b) {
  r <- tbl[(factor_a == a & factor_b == b) | (factor_a == b & factor_b == a)]
  if (!nrow(r)) return(NA_character_)
  r$verdict[1]
}
.stat_of <- function(tbl, a, b, col) {
  r <- tbl[(factor_a == a & factor_b == b) | (factor_a == b & factor_b == a)]
  if (!nrow(r)) return(NA_real_)
  r[[col]][1]
}

#==============================================================================
cat("=== 1) 위반 주입: 심어놓은 중복을 잡는가 ===\n")
#==============================================================================
inj <- scan_signal_dup(months = MONTHS, factor_names = GRID_INJ,
                       loader = make_loader(TRUE), min_obs = 30L,
                       screen_thr = 0.90, verbose = FALSE)
inj <- classify_dup(inj, stat = "median_abs", exact_thr = 0.99, near_thr = 0.95)

v <- .verdict_of(inj, "F_EXACT_A", "F_EXACT_B")
if (identical(v, "EXACT_DUP")) {
  ok("inject_exact_caught",
     sprintf("median_abs=%.4f", .stat_of(inj, "F_EXACT_A", "F_EXACT_B", "median_abs")))
} else {
  bad("inject_exact_caught", sprintf("완전중복 쌍 verdict=%s (기대 EXACT_DUP)", v))
}

v <- .verdict_of(inj, "F_NEAR_A", "F_NEAR_B")
if (identical(v, "NEAR_DUP")) {
  ok("inject_near_caught",
     sprintf("median_abs=%.4f", .stat_of(inj, "F_NEAR_A", "F_NEAR_B", "median_abs")))
} else {
  bad("inject_near_caught", sprintf("근사중복(rho~0.97) verdict=%s (기대 NEAR_DUP)", v))
}

v <- .verdict_of(inj, "F_MIRROR_A", "F_MIRROR_B")
mc <- .stat_of(inj, "F_MIRROR_A", "F_MIRROR_B", "median_cor")
if (identical(v, "EXACT_DUP") && !is.na(mc) && mc < 0) {
  ok("inject_mirror_caught", sprintf("median_cor=%+.4f — 부호반전도 |cor| 로 검거", mc))
} else {
  bad("inject_mirror_caught",
      sprintf("부호반전 중복 verdict=%s median_cor=%s — |cor| 기준이 아니면 놓친다", v, format(mc)))
}

#==============================================================================
cat("=== 2) 판별력: 중복 아닌 고상관(rho~0.80)을 중복으로 부르지 않는가 ===\n")
#==============================================================================
v <- .verdict_of(inj, "F_MILD_A", "F_MILD_B")
if (is.na(v) || identical(v, "OK")) {
  ok("discriminates_merely_correlated",
     sprintf("rho~0.80 쌍 verdict=%s", v %||% "screened-out"))
} else {
  bad("discriminates_merely_correlated",
      sprintf("rho~0.80 을 %s 로 판정 — 문턱이 무너졌다", v))
}

## ★위 판정만으로는 부족하다: 픽스처 이름을 오타내도 똑같이 NA 가 나온다.
## screen_thr 을 낮춰 이 쌍을 **실제로 등장시키고** 상관이 정말 0.80 부근인지 잰다.
## (양성 대조 — 대조군이 살아 있음을 증명)
lo <- scan_signal_dup(months = MONTHS, factor_names = c("F_MILD_A", "F_MILD_B"),
                      loader = make_loader(TRUE), min_obs = 30L,
                      screen_thr = 0.50, verbose = FALSE)
lo <- if (nrow(lo)) classify_dup(lo, stat = "median_abs") else lo
ma <- .stat_of(lo, "F_MILD_A", "F_MILD_B", "median_abs")
vl <- .verdict_of(lo, "F_MILD_A", "F_MILD_B")
if (!is.na(ma) && ma > 0.72 && ma < 0.88 && identical(vl, "OK")) {
  ok("mild_pair_is_alive_and_ok", sprintf("median_abs=%.4f verdict=%s", ma, vl))
} else {
  bad("mild_pair_is_alive_and_ok",
      sprintf("대조 쌍이 살아있지 않거나 상관이 기대 밖 (median_abs=%s verdict=%s)",
              format(ma), vl))
}

#==============================================================================
cat("=== 3) min_obs 게이트: 표본 10개짜리 쌍은 판정하지 않는가 ===\n")
#==============================================================================
v <- .verdict_of(inj, "F_SPARSE_A", "F_SPARSE_B")
if (is.na(v)) {
  ok("min_obs_gate_blocks_thin_pair", "공통관측 10 < min_obs 30 -> 후보에서 배제")
} else {
  bad("min_obs_gate_blocks_thin_pair",
      sprintf("표본 10개 쌍이 %s 로 판정됨 — 얇은 표본이 중복으로 위장", v))
}

#==============================================================================
cat("=== 4) 음성 대조: 중복이 없으면 0건인가 ===\n")
#==============================================================================
ctl <- scan_signal_dup(months = MONTHS, factor_names = GRID_CTL,
                       loader = make_loader(FALSE), min_obs = 30L,
                       screen_thr = 0.90, verbose = FALSE)
ctl <- if (nrow(ctl)) classify_dup(ctl, stat = "median_abs") else ctl
n_hit <- if (nrow(ctl)) sum(ctl$verdict %in% c("EXACT_DUP", "NEAR_DUP")) else 0L
if (n_hit == 0L) {
  ok("negative_control_clean", sprintf("독립 6팩터 -> 적발 %d건", n_hit))
} else {
  bad("negative_control_clean", sprintf("무중복 패널에서 %d건 오탐", n_hit))
}

#==============================================================================
cat("=== 5) classify_dup 경계값 ===\n")
#==============================================================================
bt <- data.table(factor_a = "a", factor_b = "b",
                 median_abs = c(0.9899, 0.99, 0.9499, 0.95, 0.9))
cl <- classify_dup(bt, stat = "median_abs", exact_thr = 0.99, near_thr = 0.95)
expect <- c("NEAR_DUP", "EXACT_DUP", "OK", "NEAR_DUP", "OK")
if (identical(cl$verdict, expect)) {
  ok("classify_boundaries", paste(cl$verdict, collapse = "/"))
} else {
  bad("classify_boundaries", sprintf("got %s / want %s",
      paste(cl$verdict, collapse = "/"), paste(expect, collapse = "/")))
}

#==============================================================================
cat("=== 6) registry dedup 블록 구조 계약 ===\n")
#==============================================================================
REG_A <- file.path(PROJ, "02_Infrastructure/factor_db/factor_registry.json")
REG_B <- file.path(PROJ, ".cache/factor_db/factor_registry.json")
reg <- fromJSON(REG_A, simplifyVector = FALSE)

dd <- Filter(function(k) !is.null(reg[[k]]$dedup), names(reg))
if (length(dd) == 0L) {
  bad("dedup_block_present", "registry 에 dedup 블록이 하나도 없다 — de-dup 미적용 상태")
} else {
  ok("dedup_block_present", sprintf("%d 팩터에 dedup 블록", length(dd)))

  err <- character(0)
  for (k in dd) {
    d <- reg[[k]]$dedup
    role <- d$role %||% "<none>"
    if (!role %in% c("canonical", "alias", "redundant")) {
      err <- c(err, sprintf("%s: role=%s", k, role)); next
    }
    if (identical(role, "redundant")) {
      ## redundant = 구성은 다른데 실측만 겹침. 자동 병합 대상이 아니므로
      ## canonical 역참조는 없지만, **cluster 와 partners 는 반드시 성립**해야 한다
      ## (없으면 "보고만 한다"는 소비 규약이 아무것도 보고하지 못한다).
      cl <- d$cluster %||% NA_character_
      pt <- unlist(d$partners %||% list())
      if (is.na(cl) || !nzchar(cl)) { err <- c(err, sprintf("%s: redundant 인데 cluster 없음", k)); next }
      if (!length(pt))              { err <- c(err, sprintf("%s: redundant 인데 partners 비었음", k)); next }
      if (is.null(d$needs_review))  { err <- c(err, sprintf("%s: needs_review 미표기", k)); next }
      miss <- pt[vapply(pt, function(p) is.null(reg[[p]]), logical(1))]
      if (length(miss)) { err <- c(err, sprintf("%s: partner 미존재 %s", k, paste(miss, collapse=","))); next }
      badc <- pt[vapply(pt, function(p) !identical(reg[[p]]$dedup$cluster %||% "", cl), logical(1))]
      if (length(badc)) err <- c(err, sprintf("%s: partner 가 다른 cluster %s", k, paste(badc, collapse=",")))
      next
    }
    if (identical(role, "alias")) {
      cn <- d$canonical %||% NA_character_
      if (is.na(cn) || is.null(reg[[cn]])) {
        err <- c(err, sprintf("%s: canonical '%s' 이 registry 에 없음", k, cn)); next
      }
      # alias 체인 금지 — canonical 이 또 alias 면 안 된다
      if (identical(reg[[cn]]$dedup$role %||% "", "alias")) {
        err <- c(err, sprintf("%s -> %s 가 또 alias (체인)", k, cn)); next
      }
      # 양방향 일치 — canonical 쪽이 이 alias 를 알고 있어야
      al <- unlist(reg[[cn]]$dedup$aliases %||% list())
      if (!k %in% al) err <- c(err, sprintf("%s: canonical %s 의 aliases 에 역참조 없음", k, cn))
    } else {
      al <- unlist(d$aliases %||% list())
      if (!length(al)) { err <- c(err, sprintf("%s: canonical 인데 aliases 비었음", k)); next }
      for (a in al) {
        if (is.null(reg[[a]])) { err <- c(err, sprintf("%s: alias '%s' 미존재", k, a)); next }
        if (!identical(reg[[a]]$dedup$canonical %||% "", k))
          err <- c(err, sprintf("%s: alias %s 의 canonical 역참조 불일치", k, a))
      }
    }
  }
  if (!length(err)) ok("dedup_block_integrity", "canonical 실재 / 체인 없음 / 양방향 일치")
  else bad("dedup_block_integrity", paste(head(err, 5), collapse = " | "))

  # 적발 사건 자체가 라벨되어 있는가 (회귀 가드)
  inc <- reg[["R12_Idiosyncratic_Risk"]]$dedup
  if (identical(inc$role %||% "", "alias") && identical(inc$canonical %||% "", "D01_IdioVol")) {
    ok("incident_pair_labelled", "R12_Idiosyncratic_Risk -> D01_IdioVol")
  } else {
    bad("incident_pair_labelled",
        sprintf("WT-003 적발 쌍이 라벨되지 않음 (role=%s canonical=%s)",
                inc$role %||% "<none>", inc$canonical %||% "<none>"))
  }
}

#==============================================================================
cat("=== 7) registry 2벌 정합 ===\n")
#==============================================================================
## .cache/factor_db 자체가 없으면 이 트리엔 factor DB 가 설치되지 않은 것(worktree).
## 그때는 '통과'가 아니라 **SKIP 으로 명시**한다 — 결손을 정상값으로 내려앉히지 않는다.
db_installed <- dir.exists(file.path(PROJ, ".cache/factor_db")) &&
  length(list.files(file.path(PROJ, ".cache/factor_db"),
                    pattern = "^factor_db_\\d{6}\\.parquet$")) > 0L
if (!db_installed) {
  skip("registry_two_copies_identical",
       sprintf("%s 에 factor DB 미설치(worktree) — 배포 트리에서 재검사 필요", PROJ))
} else if (!file.exists(REG_B)) {
  bad("registry_two_copies_identical", sprintf("DB 는 설치됐는데 %s 부재", REG_B))
} else {
  ha <- tools::md5sum(REG_A)[[1]]; hb <- tools::md5sum(REG_B)[[1]]
  if (identical(ha, hb)) ok("registry_two_copies_identical", substr(ha, 1, 12))
  else bad("registry_two_copies_identical",
           sprintf("md5 불일치 infra=%s cache=%s — 한쪽만 갱신됨", substr(ha,1,12), substr(hb,1,12)))
}

#==============================================================================
cat(sprintf("\n=== test_factor_dup_scan: %d PASS / %d FAIL / %d SKIP  (root=%s) ===\n",
            PASS, FAIL, SKIP, PROJ))

## ★배터리 집계용 요약 JSON — run_all_hooks.sh 는 **마지막 유효 요약 JSON 라인**을
##   파싱해 총계를 낸다(:303-334). 이 줄이 없으면 등재는 됐는데 집계가 안 되고
##   UNREPORTED 로 빠진다("등재 = 집계"가 아니다). skip 은 pass 에 섞지 않고 별도 필드로
##   내보내 총계가 검사하지 않은 것을 통과로 삼지 않게 한다.
cat(sprintf('{"test":"factor_dup_scan","pass":%d,"fail":%d,"total":%d,"skip":%d}\n',
            PASS, FAIL, PASS + FAIL, SKIP))
if (FAIL > 0L) quit(status = 1L) else quit(status = 0L)
