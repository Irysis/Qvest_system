#!/usr/bin/env Rscript
#==============================================================================
# test_ae_consumer_freshness.R — D3 배포 생성기의 AE 신선도 하드 검사 위반 주입
#   대상: 02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R §2b (AE fire_seq 블록)
#   신설: 2026-08-30 (PG2 9월 리밸 오버레이 배관 결함 ① 수리 동반)
#
# ## 무엇을 재는가
# 배포 생성기가 **당월(AS_OF) AE 결정행을 요구**하는가, 없을 때 **직전 달을 조용히
# 재사용하지 않고 멈추는가**.
#
# ## 왜
# 구판: `aer <- ae[decision_date<=AS_OF][which.max(decision_date)]`.
# AS_OF 행이 없으면 직전 달 행을 말없이 썼다. 위쪽 PIT 가드(`last_feat < AS_OF`)는
# 낡음을 **구조적으로** 못 잡는다 — 신호가 오래될수록 last_feat 이 AS_OF 에서 멀어져
# 오히려 **더 잘 통과한다**. 생산자(ae_regime_monthly.py)에 호출자가 0건이라
# 신호가 2026-08-01 에 멈췄는데도 배포는 매달 초록이었다. 2026-09 는 m4 미발화라
# gate=1.00 고정으로 무해했을 뿐, m4 발화월(실측 37개월 중 36 = 97.3%)에는
# **30% de-risk 오판**이 된다.
#
# ## 방법 — 재구현이 아니라 **배포 파일 텍스트를 직접 평가**한다
# 블록을 복사해 테스트에 다시 짜면 검사와 배포가 갈라진다(이 저장소의 반복 병).
# 배포 파일에서 §2b 블록을 잘라 fixture 위에서 eval 한다. 선례: generator_pins.json
# note_20260813_gapfix ("배포 파일 텍스트 직접 평가 — 재구현 아님").
#
# ## 검출력 실증 (돌연변이)
# 축 MUT-1 이 **구판 블록**을 같은 입력에 돌려 조용히 통과한다는 것을 보인다.
#
# 실행: Rscript 08_Tests/portfolio/test_ae_consumer_freshness.R
#==============================================================================
suppressPackageStartupMessages({ library(arrow); library(data.table) })

## ── 루트 앵커 = self 최우선 (r-portability.md ④-b) ───────────────────────────
.self <- tryCatch(normalizePath(dirname(sub("^--file=", "",
           grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), winslash = "/"),
         error = function(e) NA_character_)
GEN_REL <- "02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R"
.pick_root <- function() {
  for (c in c(if (!is.na(.self)) file.path(.self, "..", ".."),
              Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (!nzchar(c)) next
    c <- gsub("\\\\", "/", c)
    if (file.exists(file.path(c, GEN_REL))) return(normalizePath(c, winslash = "/"))
  }
  NULL
}
ROOT_REPO <- .pick_root()
if (is.null(ROOT_REPO)) { cat("PROJECT_ROOT 해석 실패 — 표지", GEN_REL, "없음\n"); quit(status = 2) }

PASS <- 0L; FAILS <- character(0)
ok  <- function(n, note = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n          %s\n", n, note)) }
bad <- function(n, m) { FAILS <<- c(FAILS, n); cat(sprintf("  ★FAIL %s\n          %s\n", n, m)) }
chk <- function(n, expr) {
  r <- tryCatch(expr, error = function(e) structure(conditionMessage(e), class = "terr"))
  if (inherits(r, "terr")) bad(n, r) else ok(n, r)
}

## ── 배포 파일에서 §2b 블록 추출 ──────────────────────────────────────────────
GEN_LINES <- readLines(file.path(ROOT_REPO, GEN_REL), warn = FALSE, encoding = "UTF-8")
i0 <- grep("^## --- 2b\\.", GEN_LINES)
i1 <- grep("^## --- 2c\\.", GEN_LINES)
if (length(i0) != 1L || length(i1) != 1L || i1 <= i0) {
  cat(sprintf("§2b 블록 경계 해석 실패 (2b:%s 2c:%s) — 배포 파일 구조 변경 의심\n",
              paste(i0, collapse = ","), paste(i1, collapse = ",")))
  quit(status = 2)
}
AE_BLOCK <- paste(GEN_LINES[i0:(i1 - 1L)], collapse = "\n")
AE_EXPR  <- parse(text = AE_BLOCK)

## 구판(수리 전) 블록 — 돌연변이용. 커밋 65a3289e 시점 원문.
LEGACY_BLOCK <- paste(c(
  'ae_path <- file.path(ROOT,"stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet")',
  'if(!file.exists(ae_path)) stop("[AE] parquet 부재")',
  'ae <- as.data.table(read_parquet(ae_path)); ae[, decision_date:=as.Date(decision_date)]',
  'aer <- ae[decision_date<=AS_OF][which.max(decision_date)]',
  'ae_fire <- if(nrow(aer)) as.integer(aer$fire_seq[1]) else 0L',
  'ae_lfd <- if(nrow(aer)) as.character(aer$last_feat_date[1]) else NA',
  'stopifnot(is.na(ae_lfd) || as.Date(ae_lfd) < AS_OF)'), collapse = "\n")
LEGACY_EXPR <- parse(text = LEGACY_BLOCK)

## ── fixture ──────────────────────────────────────────────────────────────────
TD <- file.path(tempdir(), paste0("aecons_", Sys.getpid()))
AE_SUB <- "stage_artifacts/WT_D20260718_007"

#' rows = data.frame(decision_date, fire_seq, last_feat_date) → fixture ROOT 반환
mk_root <- function(tag, rows) {
  r <- file.path(TD, tag); dir.create(file.path(r, AE_SUB), recursive = TRUE, showWarnings = FALSE)
  write_parquet(as.data.frame(rows), file.path(r, AE_SUB, "ae_regime_signal_ext.parquet"))
  r
}
#' 블록을 격리 환경에서 실행. 성공이면 list(fire, lfd), 실패면 error 전파.
run_block <- function(expr, root, as_of) {
  env <- new.env(parent = globalenv())
  assign("ROOT", root, envir = env); assign("AS_OF", as.Date(as_of), envir = env)
  utils::capture.output(eval(expr, envir = env))
  list(fire = get("ae_fire", envir = env), lfd = get("ae_lfd", envir = env))
}
AS_OF <- "2026-09-01"
rows_full <- data.frame(
  decision_date  = as.Date(c("2026-07-01", "2026-08-01", "2026-09-01")),
  fire_seq       = c(1L, 0L, 1L),
  last_feat_date = as.Date(c("2026-06-30", "2026-07-31", "2026-08-28")))
rows_stale <- rows_full[rows_full$decision_date < as.Date(AS_OF), ]   # 당월 행 없음

cat(strrep("=", 78), "\n")
cat("test_ae_consumer_freshness — D3 생성기 §2b AE 신선도 하드 검사\n")
cat(strrep("=", 78), "\n")

## ── A. 정상 경로 — 차단이 정상 운용을 막지 않는다 ────────────────────────────
chk("A1  당월 결정행 있음 → 통과, 당월 값을 쓴다", {
  r <- run_block(AE_EXPR, mk_root("a1", rows_full), AS_OF)
  if (!identical(r$fire, 1L)) stop(sprintf("fire_seq=%s (기대 1 — 당월 행)", r$fire))
  if (!identical(as.character(as.Date(r$lfd)), "2026-08-28")) stop(sprintf("last_feat=%s", r$lfd))
  sprintf("fire_seq=%d last_feat=%s (당월 2026-09-01 행)", r$fire, as.Date(r$lfd))
})

chk("A2  ★회귀 아님 — 당월 행이 있을 때 산출이 구판과 동일", {
  root <- mk_root("a2", rows_full)
  n <- run_block(AE_EXPR, root, AS_OF); l <- run_block(LEGACY_EXPR, root, AS_OF)
  if (!identical(n$fire, l$fire) || !identical(as.Date(n$lfd), as.Date(l$lfd)))
    stop(sprintf("신/구 산출 불일치: %s/%s vs %s/%s", n$fire, n$lfd, l$fire, l$lfd))
  sprintf("신 fire=%d == 구 fire=%d (비중 로직 무변경 실증)", n$fire, l$fire)
})

chk("A3  당월 행이 fire_seq=0 이어도 통과한다 (차단 축은 신선도지 발화 아님)", {
  rw <- rows_full; rw$fire_seq[3] <- 0L
  r <- run_block(AE_EXPR, mk_root("a3", rw), AS_OF)
  if (!identical(r$fire, 0L)) stop(sprintf("fire_seq=%s (기대 0)", r$fire))
  "fire_seq=0 정상 통과"
})

## ── B. 위반 주입 — 낡음/결측/중복 ────────────────────────────────────────────
chk("B1  ★당월 행 없음(직전 달만) → 차단 (침묵 재사용 금지)", {
  e <- tryCatch({ run_block(AE_EXPR, mk_root("b1", rows_stale), AS_OF); NULL },
                error = function(e) conditionMessage(e))
  if (is.null(e)) stop("낡은 AE 가 통과됨 — 신선도 가드 사망")
  if (!grepl("신선도 FAIL", e)) stop(sprintf("다른 사유로 실패: %s", substr(e, 1, 120)))
  if (!grepl("ae_regime_monthly.py", e)) stop("조치 명령이 메시지에 없음 — 진단만 하고 처방이 없다")
  sprintf("차단됨: %s", substr(gsub("\n", " / ", e), 1, 96))
})

chk("B2  ★빈 패널 → 차단", {
  e <- tryCatch({ run_block(AE_EXPR, mk_root("b2", rows_full[0, ]), AS_OF); NULL },
                error = function(e) conditionMessage(e))
  if (is.null(e)) stop("빈 패널이 통과됨")
  if (!grepl("신선도 FAIL", e)) stop(sprintf("다른 사유: %s", substr(e, 1, 100)))
  "차단됨 (빈 결과 = 합격 금지)"
})

chk("B3  ★당월 행 중복 2건 → 차단 (임의 선택 금지)", {
  rw <- rbind(rows_full, rows_full[3, ])
  e <- tryCatch({ run_block(AE_EXPR, mk_root("b3", rw), AS_OF); NULL },
                error = function(e) conditionMessage(e))
  if (is.null(e)) stop("중복 결정행이 통과됨 — 어느 행을 썼는지 불명확해진다")
  if (!grepl("신선도 FAIL", e)) stop(sprintf("다른 사유: %s", substr(e, 1, 100)))
  "차단됨 (2건 → stop)"
})

chk("B4  ★last_feat_date 결측 → 차단 (구판은 NA 를 통과시켰다)", {
  rw <- rows_full; rw$last_feat_date[3] <- as.Date(NA)
  e <- tryCatch({ run_block(AE_EXPR, mk_root("b4", rw), AS_OF); NULL },
                error = function(e) conditionMessage(e))
  if (is.null(e)) stop("NA last_feat 가 통과됨 — 미측정을 합격으로 접는 형태")
  if (!grepl("결측", e)) stop(sprintf("다른 사유: %s", substr(e, 1, 100)))
  "차단됨 (PIT 판정 불가 = 통과 아님)"
})

chk("B5  ★PIT 위반(last_feat >= AS_OF) → 여전히 차단", {
  rw <- rows_full; rw$last_feat_date[3] <- as.Date("2026-09-02")
  e <- tryCatch({ run_block(AE_EXPR, mk_root("b5", rw), AS_OF); NULL },
                error = function(e) conditionMessage(e))
  if (is.null(e)) stop("미래참조가 통과됨 — PIT 가드 사망")
  "차단됨 (신선도 축 신설이 PIT 축을 덮지 않았다)"
})

## ── MUT. 검출력 실증 ─────────────────────────────────────────────────────────
chk("MUT-1  ★구판은 같은 입력(B1)에서 조용히 직전 달을 쓴다", {
  root <- mk_root("mut1", rows_stale)
  l <- tryCatch(run_block(LEGACY_EXPR, root, AS_OF), error = function(e) NULL)
  if (is.null(l)) stop("구판이 차단함 — 돌연변이 무효(검사가 아무것도 시험 못 함)")
  if (!identical(as.character(as.Date(l$lfd)), "2026-07-31"))
    stop(sprintf("구판이 예상 밖 행 사용: last_feat=%s", l$lfd))
  # 그리고 구판의 PIT 가드는 그 낡은 행에 대해 **통과**한다 = 낡음을 못 잡는다는 실증
  n <- tryCatch({ run_block(AE_EXPR, root, AS_OF); "통과" }, error = function(e) "차단")
  if (n != "차단") stop("신판이 안 막음")
  "구판: 2026-08-01 행(last_feat 2026-07-31)을 조용히 사용 · PIT 가드도 통과 → 신판: 차단"
})

## ── D. 배선 도달 ─────────────────────────────────────────────────────────────
chk("D1  배포 파일에 구판 패턴(which.max 폴백)이 남아 있지 않다", {
  # ★주석 제외 — 수리 주석이 구판 패턴을 **인용**하고 있어서 원문 검사는 자기 설명에 걸린다
  #   (초판 실측 오탐). 코드 라인만 본다.
  bl   <- GEN_LINES[i0:(i1 - 1L)]
  code <- sub("#.*$", "", bl[!grepl("^\\s*#", bl)])
  cs   <- paste(code, collapse = "\n")
  if (grepl("decision_date<=AS_OF", cs, fixed = TRUE) ||
      grepl("which.max(decision_date)", cs, fixed = TRUE))
    stop("§2b 코드에 구판 폴백이 잔존")
  if (!grepl("decision_date == AS_OF", cs, fixed = TRUE))
    stop("당월 요구(decision_date == AS_OF)가 없음")
  # 음성 대조: 주석 제거가 검사까지 눈멀게 하지 않았는지
  if (!grepl("which.max(decision_date)",
             paste(c(code, "aer <- ae[decision_date<=AS_OF][which.max(decision_date)]"),
                   collapse = "\n"), fixed = TRUE))
    stop("돌연변이 무효 — 주석 제거가 검사기까지 눈멀게 함")
  "구판 폴백 0 · 당월 요구 존재 (돌연변이 대조 통과)"
})

chk("D2  생성기 핀 정합 — 미러 sha1 == generator_pins.json", {
  pj <- file.path(ROOT_REPO, "02_Infrastructure/ops/generator_pins.json")
  if (!file.exists(pj)) stop("generator_pins.json 부재")
  j <- jsonlite::fromJSON(pj, simplifyVector = FALSE)
  e <- j[["STR_1715_on_M4gAE_R05_noLayer4_PG2"]]
  if (is.null(e)) stop("D3 슬롯 핀 항목 부재")
  act <- as.character(tools::md5sum(file.path(ROOT_REPO, e$mirror)))  # 존재 확인용
  if (is.na(act)) stop(sprintf("핀된 미러 부재: %s", e$mirror))
  dg <- digest::digest(file = file.path(ROOT_REPO, e$mirror), algo = "sha1")
  if (!identical(dg, e$sha1))
    stop(sprintf("핀 불일치 — 미러를 고치고 핀을 안 갱신하면 러너 [1b] 가 exit 12 로 죽는다 (핀 %s vs 실측 %s)",
                 substr(e$sha1, 1, 12), substr(dg, 1, 12)))
  sprintf("sha1 %s 일치", substr(dg, 1, 12))
})

unlink(TD, recursive = TRUE, force = TRUE)

cat(strrep("-", 78), "\n")
NT <- PASS + length(FAILS)
cat(sprintf("  %d/%d PASS\n", PASS, NT))
if (length(FAILS)) cat("  ★실패:", paste(FAILS, collapse = ", "), "\n")
cat(sprintf('{"test":"ae_consumer_freshness","pass":%d,"fail":%d,"total":%d,"skipped":0}\n',
            PASS, length(FAILS), NT))
quit(status = if (length(FAILS)) 1L else 0L)
