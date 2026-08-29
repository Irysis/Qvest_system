# test_mode_rename_strategy_rotation.R — 모드 개명 + prefix 부채 계약 (v9.21 축 3-a)
#
# 대상: 02_Infrastructure/axiom/lcode_schema.R      (enum · alias)
#       02_Infrastructure/axiom/lcode_emit.R        (.LCODE_MODE_PREFIX)
#       02_Infrastructure/axiom/promote.R           (.MODE_PREFIX)
#       02_Infrastructure/axiom/cluster_extractor.py (DIST_MODE_PREFIX)
#
# ★개명에서 진짜 위험한 것은 새 이름이 아니라 **옛 이름이 끊기는 것**이다.
#   이 저장소의 원장은 append-only 이고 과거 L-code 는 옛 라벨을 갖는다. enum 에서 옛
#   값을 빼면 `validate_lcode` 가 **과거 기록을 무효로 만든다** — 역사는 판정이 아니다.
#   그래서 이 시험은 양방향이다: 새 이름이 작동하는가 ∧ 옛 이름이 살아 있는가.
#
# ★그리고 같은 자리에서 **선행 부채**를 닫았다: `overlay_research` 가 세 prefix 맵 중
#   `lcode_emit.R` 에만 있었다. 나머지 둘에 없어서 OVL L-code **11건**이 승격·distill
#   경로에서 `GEN` 폴백으로 떨어졌다 — 모드는 있는데 prefix 가 없으면 그 계열이
#   **조용히 다른 계급으로 집계된다**(이 저장소가 반복한 "생산자만 있고 소비자 0" 의 변형).

suppressPackageStartupMessages({ })

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- list()
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", d, "\n") }
sk <- function(a, r, mi) { SKIP <<- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = a, reason = r, missing = mi)
  cat("  SKIP ", a, " — ", r, "\n") }
emit <- function() {
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, SKIP))
  j <- sprintf('{"test":"mode_rename_strategy_rotation","pass":%d,"fail":%d,"total":%d,"skipped":%d',
               PASS, FAIL, PASS + FAIL, SKIP)
  if (SKIP > 0L) j <- paste0(j, ',"skips":[', paste(vapply(SKIPS, function(s)
    sprintf('{"axis":"%s","reason":"%s","missing":"%s"}', s$axis, s$reason, s$missing),
    character(1)), collapse = ","), "]")
  cat(paste0(j, "}\n")); quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
SCH <- file.path(ROOT, "02_Infrastructure", "axiom", "lcode_schema.R")
EMI <- file.path(ROOT, "02_Infrastructure", "axiom", "lcode_emit.R")
PRO <- file.path(ROOT, "02_Infrastructure", "axiom", "promote.R")
CLU <- file.path(ROOT, "02_Infrastructure", "axiom", "cluster_extractor.py")

cat("=== 모드 개명 factor_rotation → strategy_rotation (v9.21) ===\n")
if (!file.exists(SCH)) { sk("schema_present", "lcode_schema.R 부재", SCH); emit() }

e <- new.env(parent = globalenv())
loaded <- tryCatch({ suppressMessages(sys.source(SCH, envir = e)); TRUE },
                   error = function(x) { ng("lcode_schema 로드", conditionMessage(x)); FALSE })

# ══ A. enum · alias ═════════════════════════════════════════════════════════
cat("\n── A. enum · alias ─────────────────────────────────────────\n")
if (!loaded) sk("A_enum", "schema 미로드", SCH) else {
  VM <- e$LCODE_VALID_MODES; AL <- e$LCODE_MODE_ALIASES

  # A1 — 새 이름이 enum 에 있는가
  if ("strategy_rotation" %in% VM)
    ok("strategy_rotation 이 enum 에 있다") else
    ng("★새 모드명이 enum 에 없다 — validate_lcode 가 신규 적립을 막는다")

  # A2 — ★옛 이름이 **살아 있는가** (원장 1건이 이 값을 갖는다)
  if ("factor_rotation" %in% VM)
    ok("factor_rotation 이 역사 라벨로 존치 — 과거 L-code 가 무효화되지 않는다") else
    ng("★옛 라벨을 enum 에서 뺐다 — 기존 원장 기록이 검증 실패로 뒤집힌다")

  # A3 — alias 가 신규 발행을 새 이름으로 정규화하는가
  if (identical(unname(AL[["factor_rotation"]]), "strategy_rotation"))
    ok("alias factor_rotation → strategy_rotation") else
    ng("★alias 가 없다 — 신규 발행이 옛 이름으로 계속 쌓인다")

  # A4 — 기존 alias(qepm)를 깨지 않았는가 (선례 보존)
  if (identical(unname(AL[["qepm"]]), "qepm_legacy"))
    ok("기존 alias qepm → qepm_legacy 불변") else
    ng("★기존 alias 가 깨졌다")
}

# ══ B. prefix 맵 3종 정합 ═══════════════════════════════════════════════════
cat("\n── B. prefix 맵 3종 ────────────────────────────────────────\n")
.txt <- function(p) if (file.exists(p)) paste(readLines(p, warn = FALSE), collapse = "\n") else NA_character_
maps <- list(lcode_emit = .txt(EMI), promote = .txt(PRO), cluster_extractor = .txt(CLU))

for (nm in names(maps)) {
  j <- maps[[nm]]
  if (is.na(j)) { sk(paste0("B_", nm), "파일 부재", nm); next }

  # B-a — 새 이름이 FR 로 매핑되는가 (prefix 유지 = 기존 id 불변)
  has_new <- grepl('strategy_rotation"?\\s*[:=]\\s*"FR"', j)
  # B-b — ★부채: overlay_research 가 OVL 로 매핑되는가
  has_ovl <- grepl('overlay_research"?\\s*[:=]\\s*"OVL"', j)
  # B-c — 옛 이름도 남아 있는가
  has_old <- grepl('factor_rotation"?\\s*[:=]\\s*"FR"', j)

  if (has_new && has_old)
    ok(sprintf("%s: strategy_rotation·factor_rotation 둘 다 FR (id 불투명성 유지)", nm)) else
    ng(sprintf("★%s: 개명 매핑 누락", nm), sprintf("new=%s old=%s", has_new, has_old))

  if (has_ovl)
    ok(sprintf("%s: overlay_research → OVL (부채 봉합 — OVL 11건이 GEN 으로 안 떨어진다)", nm)) else
    ng(sprintf("★%s: overlay_research 가 없다 — OVL 계열이 GEN 으로 조용히 집계된다", nm))
}

# ══ C. 원장 무손상 (개명이 과거를 끊지 않았는가) ════════════════════════════
cat("\n── C. 원장 무손상 ──────────────────────────────────────────\n")
cp <- file.path(ROOT, ".cache", "lcode_corpus.json")
if (!requireNamespace("jsonlite", quietly = TRUE) || !file.exists(cp)) {
  sk("C_corpus", "corpus 또는 jsonlite 부재", cp)
} else {
  co <- tryCatch(jsonlite::fromJSON(cp, simplifyVector = FALSE), error = function(x) NULL)
  if (is.null(co$lcodes)) sk("C_corpus", "corpus 파싱 실패", cp) else {
    ids <- vapply(co$lcodes, function(x) as.character(x$l_code %||% "")[1], "")
    n_fr  <- sum(grepl("^L-FR-",  ids))
    n_ovl <- sum(grepl("^L-OVL-", ids))
    if (n_fr >= 1L)
      ok(sprintf("기존 L-FR-* %d건 조회 가능 — prefix 유지가 실제로 지켰다", n_fr)) else
      ng("★L-FR-* 가 사라졌다")
    if (n_ovl >= 1L)
      ok(sprintf("L-OVL-* %d건 존재 — 부채 봉합의 실제 대상 규모", n_ovl)) else
      sk("C_ovl", "OVL L-code 0건", "corpus")

    # ★모드 라벨이 enum 밖으로 나간 것이 없는가 (개명이 기존 값을 무효화했는지 직접 확인)
    if (loaded) {
      modes <- unique(vapply(co$lcodes, function(x) as.character(x$research_mode %||% "")[1], ""))
      modes <- modes[nzchar(modes)]
      known <- modes %in% e$LCODE_VALID_MODES | modes %in% names(e$LCODE_MODE_ALIASES)
      unknown <- modes[!known]
      ## ★불변식은 "0" 이 아니라 "늘지 않았다" 다 — corpus 에는 개명과 무관한 구 라벨
      ##   (ar/QPM/judge_gate/method_frontier 등)이 이미 있다. 그걸 이 개명의 책임으로
      ##   세면 검사가 거짓 경보를 내고, 상시 경보는 아무도 안 읽는다.
      if (!any(c("factor_rotation", "strategy_rotation", "overlay_research") %in% unknown))
        ok(sprintf("개명 대상 3종이 전부 enum/alias 로 해소 (그 외 미등재 라벨 %d종은 선행 사안)",
                   length(unknown))) else
        ng("★개명이 기존 라벨을 enum 밖으로 밀어냈다", paste(unknown, collapse = ","))
    }
  }
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

emit()
