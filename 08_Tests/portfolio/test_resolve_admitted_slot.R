## ============================================================================
## test_resolve_admitted_slot.R — 운용 슬롯 해석기의 **위반 주입 테스트**
##
## 왜 이 테스트가 있는가:
##   해석기가 조용히 틀린 슬롯/보유파일을 고르면 라이브 성과추적 전체가 어긋난다.
##   그런데 틀린 선택은 **에러를 내지 않는다** — 그래서 "경고 0"이 안전의 증거가 못 된다.
##   반복 학습된 계통: *검사가 잘못된 것을 잰다*. 여기서는 일부러 틀린 입력을 넣어
##   해석기가 **실제로 발화하는지**를 본다. 통과(양성) 케이스만 있는 테스트는 무효.
##
## 실행: Rscript 08_Tests/portfolio/test_resolve_admitted_slot.R
## 종료코드 0 = 전건 통과 / 1 = 실패
## ============================================================================
suppressPackageStartupMessages({library(jsonlite)})
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT",
          "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT, "02_Infrastructure/portfolio/resolve_admitted_slot.R"))

PASS <- 0L; FAIL <- 0L
ok <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}

## ── 가짜 저장소 만들기 (실제 05_Production 은 건드리지 않는다) ───────────────
mk_root <- function(slots, holdings = c("20260701_M4_weights_cap_0p20.csv",
                                        "20260801_M4gAE_weights_cap_0p20.csv"),
                    admitted = "STR_X", bs_extra = list(), write_bs = TRUE,
                    hold_in = NULL) {
  r <- file.path(tempdir(), paste0("slotfx_", paste(sample(letters, 8, TRUE), collapse = "")))
  dir.create(file.path(r, "05_Production/2.Factor_Model"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "qepm/mailbox/governor"), recursive = TRUE, showWarnings = FALSE)
  for (s in slots) {
    hu <- file.path(r, "05_Production/2.Factor_Model", s, "02_holdings_universe")
    dir.create(hu, recursive = TRUE, showWarnings = FALSE)
    if (is.null(hold_in) || s %in% hold_in)
      for (h in holdings) writeLines("Ticker,Weight\nA005930,1.0", file.path(hu, h))
  }
  if (write_bs) {
    bs <- c(list(admitted_ids = admitted), bs_extra)
    write_json(bs, file.path(r, "qepm/mailbox/governor/book_state.json"), auto_unbox = TRUE)
  }
  r
}
GOOD <- "2-4.STR_X"

cat("\n[1] 양성 — 정상 해석\n")
r <- mk_root(c("2-3.STR_OTHER", GOOD))
res <- resolve_admitted_slot(root = r, quiet = TRUE)
ok("슬롯 = 2-4",            identical(res$slot, "2-4"))
ok("보유 = 최신(0801)",     identical(basename(res$holdings), "20260801_M4gAE_weights_cap_0p20.csv"))
ok("태그 = 파일명 파생",    identical(res$tag, "M4gAE"))
ok("as_of = 2026-08-01",    identical(res$as_of, as.Date("2026-08-01")))

cat("\n[2] 주입 — substring 함정 슬롯 (정확일치가 아니면 물어온다)\n")
r <- mk_root(c(GOOD, "2-5.STR_X_v2", "2-6.OLD_STR_X", "2-7.STR_X_DEPRECATED"))
res <- resolve_admitted_slot(root = r, quiet = TRUE)
ok("함정 3개 있어도 2-4 단일 선택", identical(res$slot, "2-4"))
## 순진한 substring 이었다면 몇 건을 물어오는가 — 함정이 실제로 함정인지 확인
naive <- grep("STR_X", list.dirs(file.path(r, "05_Production/2.Factor_Model"),
                                 full.names = FALSE, recursive = FALSE), value = TRUE)
ok("함정 실효 확인 (순진 매칭이면 4건)", length(naive) == 4L, sprintf("(실측 %d건)", length(naive)))

cat("\n[3] 주입 — admitted_ids 가 어떤 슬롯과도 불일치 → 중단해야\n")
r <- mk_root(c("2-3.STR_OTHER"), admitted = "STR_GHOST")
e <- tryCatch({ resolve_admitted_slot(root = r, quiet = TRUE); "발화안함" },
              error = function(e) conditionMessage(e))
ok("0건 매칭 = stop", grepl("슬롯 0건", e), sprintf("(%s)", e))

cat("\n[4] 주입 — 슬롯 중복 등록 → 임의 선택 금지, 중단해야\n")
r <- mk_root(c("2-3.STR_X", "2-9.STR_X"))
e <- tryCatch({ resolve_admitted_slot(root = r, quiet = TRUE); "발화안함" },
              error = function(e) conditionMessage(e))
ok("2건 매칭 = stop", grepl("슬롯 2건", e), sprintf("(%s)", e))

cat("\n[5] 주입 — admitted_ids 복수 (북 2개) → 호출부 명시 요구\n")
r <- mk_root(c(GOOD), admitted = c("STR_X", "STR_Y"))
e <- tryCatch({ resolve_admitted_slot(root = r, quiet = TRUE); "발화안함" },
              error = function(e) conditionMessage(e))
ok("복수 admitted = stop", grepl("admitted_ids 가 2건", e), sprintf("(%s)", e))

cat("\n[6] 주입 — 형제 키 admitted_ids_prior_* 오염 (grep 이었으면 물었을 것)\n")
r <- mk_root(c(GOOD), admitted = "STR_X",
             bs_extra = list(admitted_ids_prior_pre_d3_swapin = "STR_OLD",
                             admitted_ids_history = c("STR_A", "STR_B")))
res <- resolve_admitted_slot(root = r, quiet = TRUE)
ok("키 접근이라 STR_X 단일", identical(res$id, "STR_X"))

cat("\n[7] 주입 — book_state 부재 · fallback 없음 → 중단\n")
r <- mk_root(c(GOOD), write_bs = FALSE)
e <- tryCatch({ resolve_admitted_slot(root = r, quiet = TRUE); "발화안함" },
              error = function(e) conditionMessage(e))
ok("book_state 부재 = stop", grepl("fallback_id 미지정", e), sprintf("(%s)", e))

cat("\n[8] 주입 — book_state 부재 + fallback 지정 → 경고 후 진행\n")
r <- mk_root(c(GOOD), write_bs = FALSE)
res <- resolve_admitted_slot(root = r, fallback_id = "STR_X", quiet = TRUE)
ok("fallback 경로 동작", identical(res$slot, "2-4") && identical(res$source, "fallback"))

cat("\n[9] 주입 — 보유 파일 0건 → 중단 (빈손으로 진행 금지)\n")
r <- mk_root(c(GOOD), holdings = character(0))
e <- tryCatch({ resolve_admitted_slot(root = r, quiet = TRUE); "발화안함" },
              error = function(e) conditionMessage(e))
ok("보유 0건 = stop", grepl("보유 파일 0건", e), sprintf("(%s)", e))

cat("\n[10] 주입 — 파일명 규약 위반 → 중단 (태그/날짜를 추측하지 않는다)\n")
## ★픽스처 주의: 목록 패턴이 `_weights_cap_0p20.csv$` 라 접두 `_` 가 없으면 목록에조차
##   안 잡혀 "보유 0건"으로 빠진다(=9번과 같은 경로). 규약 검사에 **도달하는** 이름을 써야
##   이 검사가 실제로 시험된다 — 날짜/태그 자리가 규약과 다른 이름으로 주입.
r <- mk_root(c(GOOD), holdings = "final_weights_cap_0p20.csv")
e <- tryCatch({ resolve_admitted_slot(root = r, quiet = TRUE); "발화안함" },
              error = function(e) conditionMessage(e))
ok("규약 위반 = stop (0건 경로 아님)", grepl("규약", e), sprintf("(%s)", e))

cat("\n[10b] 주입 — 날짜가 8자리지만 실재하지 않는 날 → 중단\n")
r <- mk_root(c(GOOD), holdings = "20260231_M4_weights_cap_0p20.csv")
e <- tryCatch({ resolve_admitted_slot(root = r, quiet = TRUE); "발화안함" },
              error = function(e) conditionMessage(e))
ok("불가능 날짜 = stop", grepl("날짜 파싱 불가", e), sprintf("(%s)", e))

cat("\n[11] 주입 — 최신 판별이 사전순인가 (mtime 역전 주입)\n")
r <- mk_root(c(GOOD))
hu <- file.path(r, "05_Production/2.Factor_Model", GOOD, "02_holdings_universe")
## 구 파일(0701)의 mtime 을 미래로 — mtime 기준이면 여기서 틀린다
Sys.setFileTime(file.path(hu, "20260701_M4_weights_cap_0p20.csv"), Sys.time() + 86400)
res <- resolve_admitted_slot(root = r, quiet = TRUE)
ok("mtime 역전에도 0801 선택",
   identical(basename(res$holdings), "20260801_M4gAE_weights_cap_0p20.csv"),
   sprintf("(선택 %s)", basename(res$holdings)))

cat("\n[12] 음성 통제 — 정상 입력에서 오발화하지 않는가\n")
r <- mk_root(c("2-1.STR_A", "2-2.STR_B", "2-3.STR_OTHER", GOOD))
res <- tryCatch(resolve_admitted_slot(root = r, quiet = TRUE), error = function(e) NULL)
ok("정상 4슬롯에서 무중단", !is.null(res) && identical(res$slot, "2-4"))

cat(sprintf("\n=== test_resolve_admitted_slot: %d PASS / %d FAIL ===\n", PASS, FAIL))
# run_all_hooks.sh 배터리 규약 — 마지막 줄 JSON 요약 (없으면 UNREPORTED 로 계측 사망 처리)
cat(sprintf('{"test":"resolve_admitted_slot","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
