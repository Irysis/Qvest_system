# ============================================================================
# test_module_registry_exclusivity.R — 모듈 원장 상호배타 계약 위반 주입 테스트
# ----------------------------------------------------------------------------
# 신설 2026-08-02. 대상(읽기 전용):
#   02_Infrastructure/contracts/register_module.R
#   02_Infrastructure/tools/reconcile_module_registries.R
#
# ★계약: 하나의 strategy_id 는 module_catalog.modules 와 module_quarantine.modules
#   중 최대 한 곳에만 존재한다.
#
# ★왜 필요한가 (실사고): 구판 .upsert_registry() 는 catalog 승격 시 기존 quarantine
#   행을 회수하지 않았다. run_alpha_search 는 같은 전략을 두 번 등록한다 —
#   6c(:297 재측정 전 proxy → quarantine) → 6e(:374 권위 재측정 후 backtested → catalog).
#   두 행이 공존하면 quarantine 만 읽는 소비자가 최종상태를 **정반대로** 읽는다.
#   실측 피해 5건(Chen-Welch STR_AS_20260709_074129_30048 = quarantine 상 fr_eligible=FALSE
#   라 기각처럼 보이나 실제 최종은 catalog 의 FR_ELIGIBLE). 2026-08-02 STANDALONE_TRACK
#   배관 수리의 "quarantine 에 유실" 오진단이 이 중복 때문이었다.
#
# ★검사 구조 — 오탐 제거와 검사 사망은 겉보기가 같으므로 양방향으로 잰다:
#   A 양성 대조 : 수리된 코드가 실제로 회수하는가
#   B 위반 주입 : 수리를 **되돌린 돌연변이**를 주입해 중복이 되살아나는가 +
#                 상시 스크린(reconcile)이 그 중복에 실제로 발화하는가(차단 실효)
#   C 음성 통제 : 정상 입력에 오발화하지 않는가 (격리 기능 자체를 죽이지 않았나)
#   D 거울상   : 강등 방향(catalog 존재 + 하위 tier 등록)도 닫혀 있는가
#   E 복원     : 서로소가 되돌아오는가
#   F 배선 실측: 호출부가 실재하는가 (모듈만 초록이고 배선이 죽은 상태 방지)
#
# 실행: Rscript 08_Tests/contract_regression/test_module_registry_exclusivity.R
# 실 원장은 절대 건드리지 않는다 — 대상 파일을 tempdir 샌드박스 루트로 복사해 돌린다.
# ============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table); library(xts) })

PASS <- 0L; FAIL <- 0L
ok <- function(cond, name, detail = "") {
  res <- tryCatch(isTRUE(cond), error = function(e) { detail <<- conditionMessage(e); FALSE })
  if (res) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}

# ── 앵커: self-first (2026-08-02 교훈) ───────────────────────────────────────
# 러너 앵커를 env-first 로 잡으면 worktree 에서 돌린 배터리가 **main 을 검사**한다.
# 실행 중인 이 파일의 위치가 유일한 판별자다 — env 는 fallback 으로만 쓴다.
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.is_root <- function(p) !is.na(p) && nzchar(p) &&
  file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))
REAL_ROOT <- if (!is.na(.self) && nzchar(.self))
  normalizePath(file.path(dirname(.self), "..", ".."), winslash = "/", mustWork = FALSE) else NA_character_
if (!.is_root(REAL_ROOT)) {
  for (cand in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (nzchar(cand)) { p <- normalizePath(cand, winslash = "/", mustWork = FALSE)
      if (.is_root(p)) { REAL_ROOT <- p; break } }
  }
}
if (!.is_root(REAL_ROOT)) stop("[test] project root 판별 실패")

SRC_REG <- file.path(REAL_ROOT, "02_Infrastructure/contracts/register_module.R")
SRC_REC <- file.path(REAL_ROOT, "02_Infrastructure/tools/reconcile_module_registries.R")

# ── 샌드박스 루트 (실 원장 격리) ─────────────────────────────────────────────
SBX <- file.path(tempdir(), paste0("mod_excl_", Sys.getpid()))
for (d in c("06_Registry", "04_Research/strategies", "02_Infrastructure/contracts",
            "02_Infrastructure/tools", "stage_artifacts"))
  dir.create(file.path(SBX, d), recursive = TRUE, showWarnings = FALSE)
writeLines("# sandbox marker", file.path(SBX, "CLAUDE.md"))
SBX_REG <- file.path(SBX, "02_Infrastructure/contracts/register_module.R")
SBX_REC <- file.path(SBX, "02_Infrastructure/tools/reconcile_module_registries.R")
stopifnot(file.copy(SRC_REG, SBX_REG, overwrite = TRUE),
          file.copy(SRC_REC, SBX_REC, overwrite = TRUE))

CATP <- file.path(SBX, "06_Registry/module_catalog.json")
QUAP <- file.path(SBX, "06_Registry/module_quarantine.json")
PROJECT_ROOT <- SBX          # register_module.R 의 .RM_ROOT() 가 이 값을 우선 사용
source(SBX_REG)

rd  <- function(p) if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL
mods <- function(p) { o <- rd(p); if (is.null(o) || is.null(o$modules)) character(0) else names(o$modules) }
sups <- function(p) { o <- rd(p); if (is.null(o) || is.null(o$superseded)) character(0) else names(o$superseded) }
both <- function() intersect(mods(CATP), mods(QUAP))

mk_sim <- function(shift = 0) {
  n <- 80L
  r <- rep(c(0.002, -0.001, 0.0015, 0.0005), 20) + shift
  d <- seq(as.Date("2024-01-01"), by = "day", length.out = n)
  list(DAILY_NAV_DT = data.table(Date = d, NAV = cumprod(1 + r), Strategy_Ret = r),
       bm_xts = xts(rep(1e-4, n), order.by = d))
}
AUTH <- list(metric_type = "backtested", contract_pass = TRUE, frozen = TRUE,
             source_contract_id = "SRC_T", module_hash = "hash_t",
             build_version = "bv_t", cost_model_version = "v2.4_kr_retail_15bps")
# 6c 재현: 계약 인자 없는 proxy 등록.  6e 재현: 권위 인자 동반 등록.
reg_proxy <- function(id) register_module(mk_sim(), id, grade = "B", origin_mode = "alpha_search",
                                          catalog_path = CATP, quarantine_path = QUAP,
                                          metric_type = "proxy")
reg_auth  <- function(id, grade = "C") do.call(register_module,
  c(list(sim_result = mk_sim(), strategy_id = id, grade = grade, origin_mode = "alpha_search",
         catalog_path = CATP, quarantine_path = QUAP), AUTH))

sink_quiet <- function(expr) { tc <- textConnection(NULL, "w"); sink(tc)
  on.exit({ sink(); close(tc) }, add = TRUE); force(expr) }

# ============================================================================
cat("--- A. 양성 대조: 승격이 격리행을 실제로 회수하는가 (6c → 6e 재현) ---\n")
ID <- "TST_CHEN_WELCH"
r_q <- sink_quiet(reg_proxy(ID))
ok(ID %in% mods(QUAP) && !(ID %in% mods(CATP)),
   "A1 6c(proxy) 등록 후 quarantine.modules 에만 존재")
r_c <- sink_quiet(reg_auth(ID, grade = "B"))
ok(ID %in% mods(CATP), "A2 6e(backtested) 승격 후 catalog.modules 에 존재")
ok(!(ID %in% mods(QUAP)),
   "A3 ★승격 후 quarantine.modules 에서 회수됨 (구판 결함의 직접 반증)")
ok(ID %in% sups(QUAP), "A4 quarantine.superseded 에 tombstone 보존 (삭제 아님)")
tb <- rd(QUAP)$superseded[[ID]]$superseded_by
ok(identical(tb$mode, "promoted") && identical(tb$registry, "module_catalog") &&
   isTRUE(tb$catalog_fr_eligible),
   "A5 tombstone 이 최종상태를 가리킴 (mode=promoted · registry=module_catalog · fr=TRUE)")
ok(isTRUE(r_c$quarantine_reclaimed), "A6 반환값 quarantine_reclaimed=TRUE")
ok(length(both()) == 0L, "A7 상호배타 불변식 유지 (양쪽 modules 교집합 0)")
# 격리행에만 있던 proxy 단계 진단(grade 등)이 보존되는지 — tombstone 의 존재이유
ok(identical(as.character(rd(QUAP)$superseded[[ID]]$metric_type), "proxy"),
   "A8 proxy 단계 기록 보존 (연구·진단용 — 격리소의 존재이유)")

# ============================================================================
cat("--- B. 위반 주입: 수리를 되돌리면 중복이 되살아나고 스크린이 발화하는가 ---\n")
MUT <- file.path(SBX, "02_Infrastructure/contracts/register_module_MUTANT.R")
src <- readLines(SBX_REG, warn = FALSE)
NEEDLE <- '.supersede_quarantine(quarantine_path, strategy_id, entry, mode = "promoted")'
hits <- sum(grepl(NEEDLE, src, fixed = TRUE))
# ★needle 이 안 잡히면 돌연변이가 무해해져 B 축 전체가 공허해진다(거짓 초록).
#   "주입했다"를 자기신고하지 않고 치환 건수를 실측해 단언한다.
ok(hits == 1L, sprintf("B0 돌연변이 needle 정확히 1건 매치 (실측 %d)", hits))
writeLines(sub(NEEDLE, 'list(moved = FALSE, n_modules = 0L, n_superseded = 0L)',
               src, fixed = TRUE), MUT)
ID2 <- "TST_MUTANT_DUP"
sink_quiet({ source(MUT, local = FALSE); reg_proxy(ID2); reg_auth(ID2) })
ok(ID2 %in% mods(CATP) && ID2 %in% mods(QUAP),
   "B1 돌연변이(회수 제거)에서 중복이 재현됨 — 검사가 공허하지 않음")
ok(length(both()) == 1L, "B2 상호배타 위반이 정확히 1건 존재하는 상태 구성")

# 상시 스크린(reconcile)이 이 상태에 실제로 발화하는가 = 차단 실효.
# 샌드박스 사본을 별 프로세스로 돌린다(스크립트는 quit() 호출 → 세션 내 source 불가).
rscript <- Sys.which("Rscript"); if (!nzchar(rscript)) rscript <- "Rscript"
run_screen <- function(args = character(0)) {
  out <- suppressWarnings(system2(rscript, c(shQuote(SBX_REC), args),
                                  stdout = TRUE, stderr = TRUE))
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}
scr <- run_screen()
ok(scr$status == 1L, sprintf("B3 스크린이 중복 상태에서 비정상 종료(exit=1) — 실측 %s", scr$status))
ok(grepl("중복(양쪽 modules 동시 등재) = 1건", scr$out, fixed = TRUE),
   "B4 스크린이 중복 1건을 이름 붙여 보고")
ok(grepl(ID2, scr$out, fixed = TRUE), "B5 스크린 출력에 해당 strategy_id 노출")

# 수리본 복원 → 같은 스크린이 --apply 로 해소하는가
source(SBX_REG)
scr_fix <- run_screen("--apply")
ok(scr_fix$status == 0L, "B6 --apply 후 스크린 exit=0 (해소)")
ok(length(both()) == 0L && ID2 %in% sups(QUAP),
   "B7 소급 정리 결과 원장 재검증 — 교집합 0 + tombstone 등재")

# ============================================================================
cat("--- C. 음성 통제: 정상 입력에 오발화하지 않는가 ---\n")
scr_clean <- run_screen()
ok(scr_clean$status == 0L, "C1 중복 없는 원장에서 스크린 exit=0 (오발화 없음)")
ok(grepl("정리할 항목 없음", scr_clean$out, fixed = TRUE), "C2 스크린이 '항목 없음'을 명시 보고")
ID3 <- "TST_QUAR_ONLY"
r3 <- sink_quiet(reg_proxy(ID3))
ok(ID3 %in% mods(QUAP) && isTRUE(r3$quarantined),
   "C3 격리-only 등록은 여전히 quarantine.modules 에 남음 (격리 기능 미손상)")
ID4 <- "TST_CAT_ONLY"
r4 <- sink_quiet(reg_auth(ID4))
ok(identical(r4$quarantine_reclaimed, FALSE),
   "C4 격리 이력 없는 승격은 reclaimed=FALSE (TRUE/NA 아님 — 결손과 무대상 구분)")
ok(!(ID4 %in% sups(QUAP)), "C5 무대상 승격이 헛 tombstone 을 만들지 않음")

# ============================================================================
cat("--- D. 거울상 결함: 강등 방향(catalog 존재 + 하위 tier 등록)도 닫혀 있나 ---\n")
r5 <- sink_quiet(reg_proxy(ID4))   # ID4 는 이미 catalog 권위 등재
ok(!(ID4 %in% mods(QUAP)),
   "D1 catalog 등재 id 의 proxy 재등록이 quarantine.modules 에 들어가지 않음")
ok(ID4 %in% sups(QUAP) &&
   identical(rd(QUAP)$superseded[[ID4]]$superseded_by$mode, "shadowed"),
   "D2 superseded(mode=shadowed) 로 기록 — 침묵 무시 아님")
ok(isTRUE(r5$shadowed), "D3 반환값 shadowed=TRUE")
ok(ID4 %in% mods(CATP) &&
   identical(as.character(rd(CATP)$modules[[ID4]]$metric_type), "backtested"),
   "D4 proxy 가 backtested catalog 행을 뒤집지 못함 (measurement-graduation §1)")
ok(length(both()) == 0L, "D5 강등 경로에서도 상호배타 유지")

# ============================================================================
cat("--- E. 복원: catalog 행이 사라지면 격리가 live 로 되돌아오나 ---\n")
co <- rd(CATP); co$modules[[ID4]] <- NULL; co$n_modules <- length(co$modules)
write_json(co, CATP, auto_unbox = TRUE, pretty = TRUE, na = "null")
r6 <- sink_quiet(reg_proxy(ID4))
ok(ID4 %in% mods(QUAP), "E1 catalog 행 부재 시 정상 격리로 복귀")
ok(!(ID4 %in% sups(QUAP)), "E2 낡은 tombstone 제거 — modules ↔ superseded 서로소")

# ============================================================================
cat("--- F. 배선 실측: 호출부가 실재하는가 (모듈만 초록인 상태 방지) ---\n")
rsrc <- readLines(SRC_REG, warn = FALSE)
csrc <- readLines(SRC_REC, warn = FALSE)
# 호출은 줄바꿈으로 감싸질 수 있다 — 줄 단위 needle 은 순전한 서식 변경에도 깨져
# "결함"이 아니라 "needle 갱신 필요"로 오진된다. 본문을 이어붙여 본다.
rflat <- paste(rsrc, collapse = " ")
ok(grepl("\\.supersede_quarantine\\([^)]*mode = \"promoted\"", rflat),
   "F1 register_module 승격 경로에 회수 호출 존재")
ok(grepl("\\.supersede_quarantine\\([^)]*mode = \"shadowed\"", rflat),
   "F2 register_module 강등 경로에 차폐 호출 존재")
ok(any(grepl("\\.supersede_quarantine\\(", csrc)),
   "F3 reconcile 이 tombstone 모양을 재구현하지 않고 공용 함수 재사용")
ok(any(grepl("source\\(file\\.path\\(ROOT, \"02_Infrastructure\", \"contracts\", \"register_module\\.R\"\\)\\)", csrc)),
   "F4 reconcile 이 대상 계약 파일을 직접 source (사본 정의 아님)")

# ============================================================================
cat("--- G. 축2 위반 주입: register_module 밖 writer 가 서로소를 깨면 스크린이 잡나 ---\n")
# 원장을 쓰는 writer 는 register_module 뿐이 아니다 — batch434 감사도구
# (patch_catalog_label_annotations.R:68-84)는 catalog→quarantine 직접 이동을 하며
# .upsert_registry 를 우회한다(이동 자체는 정상이나 낡은 tombstone 을 못 지운다).
# 모든 writer 를 쫓는 대신, 누가 깼든 스크린이 잡는지를 시험한다.
GID <- "TST_STALE_TOMB"
sink_quiet({ reg_proxy(GID); reg_auth(GID) })            # → catalog + superseded(promoted)
ok(GID %in% sups(QUAP) && !(GID %in% mods(QUAP)), "G0 tombstone 상태 구성")
# batch434 도구의 이동을 그대로 흉내: catalog 행 제거 + quarantine.modules 삽입.
# 이동 자체는 정상(상호배타 유지)이나 .upsert_registry 를 우회하므로 낡은 tombstone 이 남는다.
# ★축1(중복)은 건드리지 않는 **순수 축2** 상태여야 이 검사가 축2 를 재는 것이 된다.
co0 <- rd(CATP); co0$modules[[GID]] <- NULL
co0$n_modules <- length(co0$modules)
write_json(co0, CATP, auto_unbox = TRUE, pretty = TRUE, na = "null")
qo <- rd(QUAP); qo$modules[[GID]] <- qo$superseded[[GID]]
qo$n_modules <- length(qo$modules)
write_json(qo, QUAP, auto_unbox = TRUE, pretty = TRUE, na = "null")
ok(GID %in% mods(QUAP) && GID %in% sups(QUAP) && !(GID %in% mods(CATP)),
   "G1 순수 축2 주입 성공 (modules ∧ superseded, catalog 무관 — 축1 미오염)")
g_scr <- run_screen()
ok(g_scr$status == 1L, sprintf("G2 스크린이 축2 위반에 발화(exit=1) — 실측 %s", g_scr$status))
ok(grepl("낡은 tombstone(modules ∧ superseded 동시) = 1건", g_scr$out, fixed = TRUE),
   "G3 스크린이 축2 를 이름 붙여 보고")
ok(grepl("중복(양쪽 modules 동시 등재) = 0건", g_scr$out, fixed = TRUE),
   "G3b 축1 은 0건으로 정확히 보고 (축이 서로 오염되지 않음)")
g_fix <- run_screen("--apply")
ok(g_fix$status == 0L && !(GID %in% sups(QUAP)) && GID %in% mods(QUAP),
   "G4 --apply 가 낡은 tombstone 만 제거(live 격리행은 보존 — 권위는 modules)")
g_clean <- run_screen()
ok(g_clean$status == 0L && grepl("정리할 항목 없음", g_clean$out, fixed = TRUE),
   "G5 음성 통제: 정상 복귀 후 오발화 없음")

unlink(SBX, recursive = TRUE, force = TRUE)
cat(sprintf("\nPASS=%d FAIL=%d\n", PASS, FAIL))
cat(sprintf('{"test":"module_registry_exclusivity","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
