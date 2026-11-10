#!/usr/bin/env Rscript
#==============================================================================
# test_factor_db_vintage.R — 팩터 DB 판 표식 계약(v10.2 · 수리 이전 측정을 기계가 가린다)
#   대상: 02_Infrastructure/contracts/factor_db_vintage.R · 정본 06_Registry/factor_db_vintage.json
#   본다: 측정 시각 판독(실행 id 우선 · 보유 재측정 시각은 쓰지 않는다) · 전체 범위 수리 앞뒤 · 팩터 목록 범위 수리(선언한 칸만 비켜 간다 ·
#         엔진 기저 · 선언 없음은 닿은 것으로) · 진행 중 수리 · 시각 모름 = NA · 원장 형식 위반 · 운영 원장의 현행 판정 · A 자격 관문 상시 보류.
#         (G2 수리 11-10) 진행 중 항목(completed_at null) 허용 · 판 표식 in_progress · 완료 시각 엄격 해석(오프셋 적용 · 분 단위) ·
#         측정 기록의 선언 팩터(declared_factors) · 칸 사양 → 선언 규칙 · 돌연변이 3종.
#         (G2 재수리 11-10) cap_core 베타 짝 위성의 베타 팩터 선언 · 비켜 간 측정의 사유 문구 · 돌연변이 1종 더.
#   격리: 임시 원장(path 인자)과 임시 폴더. 운영 원장은 읽기만.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)][1])
ROOT <- NA_character_
for (p in c(dirname(dirname(dirname(me))), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.na(p) || !nzchar(p)) next
  p <- gsub("\\\\", "/", p)
  if (file.exists(file.path(p, "02_Infrastructure", "contracts", "factor_db_vintage.R"))) { ROOT <- p; break }
}
if (is.na(ROOT)) stop("저장소 루트를 찾지 못했다")
E <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure", "contracts", "factor_db_vintage.R"), envir = E, keep.source = FALSE)
pass <- 0L; fail <- 0L
chk <- function(name, cond) {
  ok <- isTRUE(tryCatch(cond, error = function(e) { cat("     오류:", conditionMessage(e), "\n"); FALSE }))
  if (ok) pass <<- pass + 1L else fail <<- fail + 1L
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", name))
}
TD <- tempfile("fdv_test_"); dir.create(TD)
LP <- file.path(TD, "ledger.json")
wl <- function(entries) { writeLines(toJSON(list(schema = "factor_db_vintage_v1", entries = entries), auto_unbox = TRUE, null = "null"), LP); E$fdv_ledger(path = LP) }
L <- wl(list(list(id = "ALL-1", completed_at = "2026-11-10T01:38:00+09:00", scope = "all"),
             list(id = "SUB-1", completed_at = "2026-11-10T11:26:00+09:00", scope = list(factors = list("Q16_X", "R17_Y")))))
mk <- function(name, auth = NULL, spec = NULL) {
  d <- file.path(TD, name); dir.create(d, recursive = TRUE)
  if (!is.null(auth)) writeLines(toJSON(auth, auto_unbox = TRUE), file.path(d, "authoritative_remeasure.json"))
  if (!is.null(spec)) writeLines(toJSON(spec, auto_unbox = TRUE), file.path(d, "cell_spec.json"))
  d
}
st <- function(d) E$fdv_stale(d, ledger = L)

d_old <- mk("20261105_101010_111", list(run_id = "20261105_101010_111"))
chk("T01 전체 범위 수리보다 앞선 측정은 낡았다(두 수리 모두에 걸린다)", isTRUE(st(d_old)$stale) && setequal(st(d_old)$hits, c("ALL-1", "SUB-1")))
d_new <- mk("20261110_120000_222", list(run_id = "20261110_120000_222"))
chk("T02 마지막 수리 뒤 측정은 낡지 않았다", identical(st(d_new)$stale, FALSE) && !length(st(d_new)$hits))
d_mid <- mk("20261110_050000_333", list(run_id = "20261110_050000_333"))
chk("T03 두 수리 사이 측정 — 선언이 없으면(임의 코드 엔진) 팩터 목록 범위 수리에도 닿은 것으로 본다", isTRUE(st(d_mid)$stale) && identical(st(d_mid)$hits, "SUB-1"))
d_decl <- mk("20261110_050001_444", list(run_id = "20261110_050001_444"), list(factors = list(list(kind = "db", id = "M01_A"), list(kind = "db", id = "V10_B"))))
chk("T04 두 수리 사이 측정 — 팩터를 선언했고 겹치지 않으면 비켜 간다", identical(st(d_decl)$stale, FALSE) && identical(st(d_decl)$declared_factors, 2L))
d_hit <- mk("20261110_050002_555", list(run_id = "20261110_050002_555"), list(factors = list(list(kind = "db", id = "M01_A"), list(kind = "db", id = "Q16_X"))))
chk("T05 선언한 팩터가 수리 범위와 겹치면 낡았다", isTRUE(st(d_hit)$stale))
d_eng <- mk("20261110_050003_666", list(run_id = "20261110_050003_666"), list(base_signal = list(kind = "engine", path = "x/engine.R"), factors = list(list(id = "M01_A"))))
chk("T06 엔진 기저 칸은 선언이 있어도 닿은 것으로 본다(엔진이 읽은 팩터를 알 수 없다)", isTRUE(st(d_eng)$stale))
d_rem <- mk("x/20260905_095537_777/remeasure_a", list(run_id = "20260905_095537_777", remeasured_at = "2026-11-10T12:00:00+0900"))
chk("T07 보유에서 다시 잰 기록은 원 실행 시각으로 판정한다(재측정 시각이 수리 뒤여도 낡았다)", isTRUE(st(d_rem)$stale) && grepl("2026-09-05", st(d_rem)$measured_at))
d_path <- mk("stage/20261110_130000_888/sub")
chk("T08 권위 기록에 실행 id 가 없으면 폴더 경로의 실행 id 로 읽는다", identical(st(d_path)$stale, FALSE) && grepl("2026-11-10T13:00:00", st(d_path)$measured_at))
d_unk <- mk("no_time", list(strategy_id = "S"))
chk("T09 측정 시각을 알 수 없으면 NA(판정 불가)다 — 통과로 치지 않는다", is.na(st(d_unk)$stale))
L2 <- wl(list(list(id = "RUN-1", completed_at = NULL, scope = "all")))
chk("T10 완료 시각이 없는 수리(진행 중)는 범위에 닿는 측정을 전부 낡은 것으로 본다", isTRUE(E$fdv_stale(d_new, ledger = L2)$stale))
bad <- function(entries) inherits(try(wl(entries), silent = TRUE), "try-error")
chk("T11 원장 형식 위반(범위 어휘 밖 · 빈 팩터 목록 · 시각 형식 · id 없음)은 멈춘다",
    bad(list(list(id = "X", completed_at = "2026-11-10T01:00:00+09:00", scope = "some"))) &&
      bad(list(list(id = "X", completed_at = "2026-11-10T01:00:00+09:00", scope = list(factors = list())))) &&
      bad(list(list(id = "X", completed_at = "어제", scope = "all"))) && bad(list(list(completed_at = "2026-11-10T01:00:00+09:00", scope = "all"))))

## 운영 원장 — 형식 · 순서 · 현행 판정 (원장 규약: completed_at 을 비우면 진행 중 — 완료 항목만 순서를 단정하고 진행 중 항목은 null 만 허용)
LO <- E$fdv_ledger(ROOT)
ids <- vapply(LO$entries, function(e) e$id, character(1))
isdone <- vapply(LO$entries, function(e) !is.null(e$completed_at), logical(1))
tms <- vapply(LO$entries, function(e) if (is.null(e$completed_at)) NA_real_ else as.numeric(E$.fdv_time(e$completed_at, strict = TRUE)), numeric(1))
ID3 <- c("FUND-V2-FULL-REBUILD-20261109", "FACTOR-DIRECTION-STORAGE-REPAIR-20261109", "FACTOR-DB-TOTALDEBT-ZERO-REPAIR-20261110")
chk("T12 운영 원장: 세 수리(재무 v2 전체 재빌드 · 방향/저장 규약 · 총부채 0)가 완료 시각 순서로 있다 · 진행 중 항목은 completed_at = null 만",
    all(ID3 %in% ids) && all(isdone[match(ID3, ids)]) && all(is.finite(tms[isdone])) && !is.unsorted(tms[isdone]) &&
      all(vapply(LO$entries[!isdone], function(e) is.null(e$completed_at), logical(1))))
tot <- LO$entries[[which(ids == "FACTOR-DB-TOTALDEBT-ZERO-REPAIR-20261110")]]
chk("T13 운영 원장: 총부채 수리의 범위 = 수리 명세의 영향 팩터 27개와 같다", {
  sp <- fromJSON(file.path(ROOT, "04_Research/01_reports/factor_db_debt_fix_20261110/repair_spec.json"), simplifyVector = FALSE)
  setequal(unlist(tot$scope$factors), unlist(sp$targets)) && length(unlist(tot$scope$factors)) == 27L })
real <- file.path(ROOT, "stage_artifacts/replication/20260905_095537_1276/remeasure_close_t1_5562284e")
if (dir.exists(real)) chk("T14 운영 원장: 9월에 잰 실측 산출물은 낡은 것으로 판정된다(재측정 전 소비 금지)", isTRUE(E$fdv_stale(real, ROOT)$stale)) else
  cat("  [skip] T14 실측 산출물 없음\n")
SO <- E$fdv_stamp(ROOT)
chk("T15 판 표식: 진행 중 수리가 있으면 유효 시작 = NA · in_progress = 그 id 들 / 없으면 유효 시작 = 마지막 수리 완료 시각",
    if (any(!isdone)) is.na(SO$valid_from) && setequal(unlist(SO$in_progress), ids[!isdone]) else
      identical(SO$valid_from, format(max(as.POSIXct(tms, origin = "1970-01-01", tz = "Asia/Seoul")), "%Y-%m-%dT%H:%M:%S")) && is.null(SO$in_progress))

## ── 진행 중 수리 · 판 표식(합성 원장) ──
Lp <- wl(list(list(id = "A-1", completed_at = "2026-11-10T01:38:00+09:00", scope = "all"),
              list(id = "RUN-2", completed_at = NULL, scope = list(factors = list("Q16_X")))))
vp <- E$fdv_stale(d_new, ledger = Lp)
chk("T16 진행 중 수리가 있으면 fdv_stale 의 valid_from = NA · in_progress = id · last_completed = 완료 항목 최댓값",
    is.na(vp$valid_from) && identical(vp$in_progress, "RUN-2") && identical(vp$last_completed, "2026-11-10T01:38:00") && isTRUE(vp$stale))
mkroot <- function(name, entries) {
  r <- file.path(TD, name); dir.create(file.path(r, "06_Registry"), recursive = TRUE)
  writeLines(toJSON(list(schema = "factor_db_vintage_v1", entries = entries), auto_unbox = TRUE, null = "null"), file.path(r, "06_Registry", "factor_db_vintage.json"))
  r
}
sp_ip <- E$fdv_stamp(mkroot("root_ip", list(list(id = "A-1", completed_at = "2026-11-10T01:38:00+09:00", scope = "all"), list(id = "RUN-2", completed_at = NULL, scope = "all"))))
sp_dn <- E$fdv_stamp(mkroot("root_dn", list(list(id = "A-1", completed_at = "2026-11-10T01:38:00+09:00", scope = "all"))))
chk("T17 fdv_stamp: 진행 중 수리를 in_progress 로 싣고 valid_from = NA / 완료뿐이면 in_progress 키 없음(종전 모양 그대로 — 판 표식 지문 불변)",
    identical(unlist(sp_ip$in_progress), "RUN-2") && is.na(sp_ip$valid_from) &&
      is.null(sp_dn$in_progress) && identical(sp_dn$valid_from, "2026-11-10T01:38:00") && identical(names(sp_dn), c("schema", "valid_from", "repairs")))

## ── 완료 시각 해석(시간대 · 분 단위 표기) — 원장은 엄격(명시 오프셋 · T 구분) · 해석 못 하면 멈춘다 ──
tz <- function(x) format(E$.fdv_time(x, strict = TRUE), "%Y-%m-%dT%H:%M:%S", tz = "Asia/Seoul")
chk("T18 오프셋을 실제로 적용한다 — Z · +00:00 = UTC(→ KST +9h) · +09:00 · +0900 = KST 그대로 · 분 단위 + 오프셋 · 음수 오프셋",
    identical(tz("2026-11-10T02:26:00Z"), "2026-11-10T11:26:00") && identical(tz("2026-11-10T02:26:00+00:00"), "2026-11-10T11:26:00") &&
      identical(tz("2026-11-10T11:26:00+09:00"), "2026-11-10T11:26:00") && identical(tz("2026-11-10T12:00:00+0900"), "2026-11-10T12:00:00") &&
      identical(tz("2026-11-10T11:26+09:00"), "2026-11-10T11:26:00") && identical(tz("2026-11-09T21:26:00-05:00"), "2026-11-10T11:26:00"))
chk("T19 원장 완료 시각 — 초 없는 공백 표기 · 날짜만 · 오프셋 없음 · 공백 구분 · 소수 초 · 없는 날짜 · 꼬리 문자 · 숫자형 · 범위 밖 오프셋은 멈춘다",
    bad(list(list(id = "X", completed_at = "2026-11-10 11:26", scope = "all"))) &&
      bad(list(list(id = "X", completed_at = "2026-11-10", scope = "all"))) &&
      bad(list(list(id = "X", completed_at = "2026-11-10T11:26:00", scope = "all"))) &&
      bad(list(list(id = "X", completed_at = "2026-11-10 11:26:00+09:00", scope = "all"))) &&
      bad(list(list(id = "X", completed_at = "2026-11-10T11:26:00.5+09:00", scope = "all"))) &&
      bad(list(list(id = "X", completed_at = "2026-02-30T11:26:00+09:00", scope = "all"))) &&
      bad(list(list(id = "X", completed_at = "2026-11-10T11:26:00+09:00x", scope = "all"))) &&
      bad(list(list(id = "X", completed_at = 20261110, scope = "all"))) &&
      bad(list(list(id = "X", completed_at = "2026-11-10T11:26:00+25:00", scope = "all"))))
Lz <- wl(list(list(id = "Z-1", completed_at = "2026-11-10T02:26:00Z", scope = "all")))
d_z <- mk("20261110_050000_901", list(run_id = "20261110_050000_901"))
chk("T20 UTC 로 적은 완료 시각(02:26Z = 11:26 KST)보다 앞선 KST 05:00 측정은 낡았다(시간대 무시 = 9시간 앞당김 fail-open 차단)",
    isTRUE(E$fdv_stale(d_z, ledger = Lz)$stale))
d_hm <- mk("hm_measured", list(measured_at = "2026-11-10 11:20"))
L1126 <- wl(list(list(id = "S-1", completed_at = "2026-11-10T11:26:00+09:00", scope = "all")))
chk("T21 측정 시각 'YYYY-MM-DD HH:MM'(초 없음)은 그 분으로 읽는다(자정으로 떨어지지 않음 · 오프셋 없는 측정 시각 = KST)",
    identical(E$fdv_stale(d_hm, ledger = L1126)$measured_at, "2026-11-10T11:20:00") && isTRUE(E$fdv_stale(d_hm, ledger = L1126)$stale))

## ── 선언 팩터 — 측정 기록(권위 기록 factor_db_vintage.declared_factors)에서 읽는다 ──
rec <- function(name, df, basis = "cell_spec") {
  rid <- paste0("20261110_0501", sprintf("%02d", match(name, c("r1", "r2", "r3", "r4", "r5"))), "_", name)
  fv <- list(status = "ok", declared_factors = df); if (!is.null(basis)) fv$declared_factors_basis <- basis
  mk(rid, list(run_id = rid, factor_db_vintage = fv))
}
d_r1 <- rec("r1", list("M01_A", "V10_B"))
d_r2 <- rec("r2", list())
d_r3 <- rec("r3", list("Q16_X"))
d_r4 <- rec("r4", list("M01_A"), basis = NULL)
d_r5 <- rec("r5", NA)
chk("T22 기록이 선언한 팩터가 팩터 목록 수리 범위 밖 → 비켜 간다(낡지 않음 · 선언 2개)",
    identical(st(d_r1)$stale, FALSE) && identical(st(d_r1)$declared_factors, 2L))
chk("T23 기록이 '팩터 DB 팩터를 읽지 않음'(빈 선언 · 칸 사양 근거)을 남긴 칸 → 팩터 목록 수리를 비켜 간다 · 전체 범위 · 진행 중 수리에는 여전히 닿는다",
    identical(st(d_r2)$stale, FALSE) && identical(st(d_r2)$declared_factors, 0L) && isTRUE(E$fdv_stale(d_r2, ledger = L2)$stale))
chk("T24 기록 선언이 범위와 겹치면 낡았다 · 근거(declared_factors_basis) 없는 선언 · NA 선언 = 알 수 없음(닿은 것으로)",
    isTRUE(st(d_r3)$stale) && isTRUE(st(d_r4)$stale) && is.null(st(d_r4)$declared_factors) && isTRUE(st(d_r5)$stale))
sd <- E$fdv_spec_declared_factors
chk("T25 칸 사양 → 선언: 기저 모멘텀 + db 팩터 + 가격 팩터 = db id 만 · 팩터 DB 를 따로 읽을 수 있는 부품(엔진 · 엔진 결합 · 방어 슬리브 · 오버레이 · 요인 Σ · 모르는 팩터 종류 · 모르는 기저)은 NULL",
    identical(sd(list(base_signal = list(kind = "mom_12_1"), factors = list(list(kind = "db", id = "A1"), list(kind = "price", id = "lowvol60")))), "A1") &&
      identical(sd(list(factors = list(list(kind = "none")))), character(0)) &&
      identical(sd(list(factor2 = list(kind = "db", id = "B2"))), "B2") &&
      is.null(sd(list(base_signal = list(kind = "engine", path = "x.R"), factors = list(list(kind = "db", id = "A1"))))) &&
      is.null(sd(list(base_signal = list(kind = "engine_blend"), factors = list()))) &&
      is.null(sd(list(engine_blend = list("a"), factors = list(list(kind = "db", id = "A1"))))) &&
      is.null(sd(list(defense_sleeve = list(kind = "lowvol"), factors = list(list(kind = "db", id = "A1"))))) &&
      is.null(sd(list(overlay = list(kind = "pg2_risk_overlay"), factors = list(list(kind = "db", id = "A1"))))) &&
      identical(sd(list(overlay = list(kind = "none"), factors = list(list(kind = "db", id = "A1")))), "A1") &&
      is.null(sd(list(overlay_cell = list(list(kind = "vol_scale")), factors = list()))) &&
      is.null(sd(list(weighting = list(sigma_provider = "factor:ts:base"), factors = list()))) &&
      identical(sd(list(weighting = list(sigma_provider = "sample"), factors = list())), character(0)) &&
      is.null(sd(list(factors = list(list(kind = "custom", id = "A1"))))) &&
      is.null(sd(list(factors = list(list(kind = "db"))))) &&
      is.null(sd(list(base_signal = list(kind = "factors"), factors = list(list(kind = "db", id = "A1"))))) &&
      is.null(sd(NULL)) && is.null(sd("x")))
## (G2 재수리 11-10) cap_core 베타 짝 위성은 셀 엔진 §5.4 가 팩터 DB 에서 베타 팩터를 읽는다(beta_kind 기본 = db)
cc_r <- function(...) list(base_signal = list(kind = "mom_12_1"), factors = list(list(kind = "db", id = "A1")), cap_core = list(...))
chk("T29 칸 사양 → 선언: cap_core random_beta_matched(beta_kind db · 생략 = db)는 베타 팩터를 더한다 · floor(생략 포함)는 더하지 않는다 · 가격 베타는 더하지 않는다 · 모르는 위성 · 모르는 beta_kind · 베타 id 없음 · 목록 아님 = NULL",
    setequal(sd(cc_r(k = 5, satellite = "random_beta_matched", beta_factor = "BETA_X", beta_kind = "db", seed = 7)), c("A1", "BETA_X")) &&
      setequal(sd(cc_r(k = 5, satellite = "random_beta_matched", beta_factor = "BETA_X", seed = 7)), c("A1", "BETA_X")) &&
      identical(sd(cc_r(k = 5, satellite = "floor")), "A1") && identical(sd(cc_r(k = 5)), "A1") &&
      identical(sd(cc_r(k = 5, satellite = "random_beta_matched", beta_factor = "beta60", beta_kind = "price", seed = 7)), "A1") &&
      is.null(sd(cc_r(k = 5, satellite = "mystery"))) &&
      is.null(sd(cc_r(k = 5, satellite = "random_beta_matched", beta_factor = "BETA_X", beta_kind = "custom", seed = 7))) &&
      is.null(sd(cc_r(k = 5, satellite = "random_beta_matched", seed = 7))) &&
      is.null(sd(list(factors = list(list(kind = "db", id = "A1")), cap_core = "random_beta_matched"))))
Lb <- wl(list(list(id = "BETA-REPAIR", completed_at = "2026-11-10T11:00:00+09:00", scope = list(factors = list("BETA_X")))))
d_cc <- mk("20261110_050000_cc1", list(run_id = "20261110_050000_cc1",
           factor_db_vintage = list(status = "ok", declared_factors_basis = "cell_spec",
                                    declared_factors = as.list(sd(cc_r(k = 5, satellite = "random_beta_matched", beta_factor = "BETA_X", seed = 7))))))
chk("T30 베타 팩터 범위 수리(11:00)보다 앞선 cap_core 베타 짝 측정(05:00)은 낡았다(검증자 재현 — 수리 전 선언은 A1 뿐이라 현행으로 통과했다)",
    isTRUE(E$fdv_stale(d_cc, ledger = Lb)$stale) && identical(E$fdv_stale(d_cc, ledger = Lb)$hits, "BETA-REPAIR"))
v_by <- st(d_r1); v_af <- st(d_new)
chk("T31 사유 문구: 선언으로 비켜 간 측정은 '앞서거나 진행 중이지만 범위 밖'으로 적고 '마지막 수리 뒤'라고 적지 않는다 · 정말 뒤인 측정만 '뒤다' · bypassed = 비켜 간 수리 id",
    identical(v_by$stale, FALSE) && identical(v_by$bypassed, "SUB-1") && grepl("범위(팩터 목록) 밖", v_by$reason, fixed = TRUE) && !grepl("뒤다", v_by$reason, fixed = TRUE) &&
      identical(v_af$stale, FALSE) && !length(v_af$bypassed) && grepl("마지막 수리(2026-11-10T11:26:00) 뒤다", v_af$reason, fixed = TRUE))

## ── [돌연변이] 소스 텍스트 치환 · 치환 성사 단정 ──
srcv <- readLines(file.path(ROOT, "02_Infrastructure", "contracts", "factor_db_vintage.R"), encoding = "UTF-8", warn = FALSE)
mut_env <- function(pat, rep, tag) {
  h <- sum(srcv == pat); m <- srcv; m[srcv == pat] <- rep
  f <- file.path(TD, paste0("fdv_mut_", tag, ".R")); writeLines(enc2utf8(m), f, useBytes = TRUE)
  en <- new.env(parent = globalenv()); sys.source(f, envir = en, keep.source = FALSE); list(hit = h, env = en)
}
MT <- mut_env("  if (identical(off, \"\")) return(.fdv_kst(loc))", "  return(.fdv_kst(loc))   # MUTANT: 오프셋 무시", "tz")
LzM <- MT$env$fdv_ledger(path = { writeLines(toJSON(list(schema = "factor_db_vintage_v1", entries = list(list(id = "Z-1", completed_at = "2026-11-10T02:26:00Z", scope = "all"))), auto_unbox = TRUE), LP); LP })
chk("T26 [돌연변이] 오프셋을 버리는 사본(치환 1곳 성사)은 02:26Z 를 KST 02:26 으로 읽어 05:00 측정을 '현행'으로 통과시킨다 — T20 이 그 차이를 본다",
    MT$hit == 1L && identical(MT$env$fdv_stale(d_z, ledger = LzM)$stale, FALSE))
MD <- mut_env("  if (identical(basis, \"cell_spec\")) {", "  if (FALSE) {   # MUTANT: 기록 선언 무시", "decl")
chk("T27 [돌연변이] 기록 선언을 읽지 않는 사본(치환 1곳 성사)은 비부채 칸(d_r1)을 팩터 목록 수리로 낡음 처리한다 — T22 가 그 차이를 본다",
    MD$hit == 1L && isTRUE(MD$env$fdv_stale(d_r1, ledger = L)$stale))
MS <- mut_env("  if (strict && (!identical(sep, \"T\") || !nzchar(off) || nzchar(frac))) return(.fdv_na())", "  # MUTANT: 엄격 해석 해제", "strict")
chk("T28 [돌연변이] 원장 엄격 해석을 끈 사본(치환 1곳 성사)은 '2026-11-10 11:26'(오프셋 없음)을 받아들인다 — T19 가 그 차이를 본다",
    MS$hit == 1L && !inherits(try(MS$env$fdv_ledger(path = { writeLines(toJSON(list(schema = "factor_db_vintage_v1", entries = list(list(id = "X", completed_at = "2026-11-10 11:26", scope = "all"))), auto_unbox = TRUE), LP); LP }), silent = TRUE), "try-error"))
MC <- mut_env("        ids <- c(ids, bf)", "        NULL   # MUTANT: cap_core 베타 팩터 누락", "capcore")
chk("T32 [돌연변이] cap_core 베타 팩터를 선언에 넣지 않는 사본(치환 1곳 성사)은 베타 팩터 수리 앞 측정을 '현행'으로 통과시킨다 — T29 · T30 이 그 차이를 본다",
    MC$hit == 1L && identical(MC$env$fdv_spec_declared_factors(cc_r(k = 5, satellite = "random_beta_matched", beta_factor = "BETA_X", seed = 7)), "A1") && {
      d_ccm <- mk("20261110_050000_cc2", list(run_id = "20261110_050000_cc2", factor_db_vintage = list(status = "ok", declared_factors_basis = "cell_spec",
        declared_factors = as.list(MC$env$fdv_spec_declared_factors(cc_r(k = 5, satellite = "random_beta_matched", beta_factor = "BETA_X", seed = 7))))))
      identical(MC$env$fdv_stale(d_ccm, ledger = Lb)$stale, FALSE) })

unlink(TD, recursive = TRUE)
cat(sprintf("\n%s\n", toJSON(list(test = "test_factor_db_vintage", pass = pass, fail = fail, total = pass + fail), auto_unbox = TRUE)))
quit(status = if (fail > 0L) 1L else 0L)
