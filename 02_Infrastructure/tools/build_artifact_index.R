# =============================================================================
# build_artifact_index.R — Qvest 전체 산출물 인덱스 + 루트 대시보드 빌더
#
# 목적: "산출물 파악이 안 된다" 해결 — 존별 항해용 지도 생성 (전체 재귀 나열 아님).
# 산출:
#   1) <registry>/artifact_index.json  (기계가독 인덱스 — registry 존은
#      06_Registry 존재 시 06_Registry, 아니면 07_Registry 동적 선택)
#   2) <root>/ARTIFACTS.md             (사람용 한국어 대시보드, 1화면)
#
# 실행: Rscript 02_Infrastructure/tools/build_artifact_index.R
#       (daily_refresh.sh 말미에서 fail-soft 자동 재생성)
#
# 설계 원칙 (도훈 mandate 2026-07-04 저장 4원칙):
#   ① stage_artifacts/<mode>/<run_id>/ = 실험 런 (불변·이동금지)
#   ② outputs/<pipeline>/              = canonical 데이터 (최신본만)
#   ③ 06_Registry/                     = 기계가독 상태·큐·인덱스
#   ④ 04_Research/<topic>/             = 사람용 보고서
# 본 스크립트는 읽기 전용 스캔 + 위 2개 파일 쓰기만 수행. 이동/수정 없음.
# 스캔은 실존 디렉토리 기준 동적 (재편 진행 중 경로 변화에 견딤).
# =============================================================================

suppressWarnings(suppressMessages(library(jsonlite)))

# ---- 경로 해석 (하드코딩 최소화: QM_ROOT env 우선) --------------------------
root <- Sys.getenv("QM_ROOT", "")
if (!nzchar(root)) {
  # fallback: 스크립트 위치에서 유도 (02_Infrastructure/tools/ 기준 2단 상위)
  args <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", args, value = TRUE)
  if (length(fa) == 1) {
    root <- normalizePath(file.path(dirname(sub("^--file=", "", fa)), "..", ".."),
                          winslash = "/", mustWork = FALSE)
  } else {
    root <- getwd()
  }
}
root <- gsub("\\\\", "/", root)
if (!dir.exists(file.path(root, "02_Infrastructure"))) {
  stop("[artifact_index] project root 미해석: ", root)
}

# registry 존: 06_Registry 존재 시 그것, 아니면 07_Registry (재편 전환기 동적 대응)
registry_zone <- if (dir.exists(file.path(root, "06_Registry"))) "06_Registry" else "07_Registry"

# ---- 공용 헬퍼 ---------------------------------------------------------------
fmt_size <- function(bytes) {
  bytes <- sum(bytes, na.rm = TRUE)
  if (is.na(bytes) || bytes <= 0) return("0B")
  if (bytes >= 1024^3) return(sprintf("%.1fGB", bytes / 1024^3))
  if (bytes >= 1024^2) return(sprintf("%.1fMB", bytes / 1024^2))
  if (bytes >= 1024)   return(sprintf("%.0fKB", bytes / 1024))
  sprintf("%dB", as.integer(bytes))
}
fmt_date <- function(t) {
  if (all(is.na(t))) return(NA_character_)
  format(as.Date(as.POSIXct(t, origin = "1970-01-01")), "%Y-%m-%d")
}

# 존 1-depth 엔트리별 통계 (단일 재귀 워크 1회 → top-level로 집계.
#  JSON에는 엔트리 요약만 담고 개별 파일은 나열하지 않는다 — 항해용 지도)
scan_zone <- function(zone_rel, mode_fn = NULL) {
  zone_path <- file.path(root, zone_rel)
  if (!dir.exists(zone_path)) return(NULL)
  tops <- list.files(zone_path, all.files = FALSE, no.. = TRUE)
  if (length(tops) == 0) {
    return(list(zone = zone_rel, n_entries = 0L, n_files = 0L,
                size = "0B", size_bytes = 0, entries = list()))
  }
  af <- list.files(zone_path, recursive = TRUE, full.names = TRUE)
  fi <- if (length(af)) file.info(af, extra_cols = FALSE) else
        data.frame(size = numeric(0), mtime = as.POSIXct(character(0)))
  rel  <- substring(af, nchar(zone_path) + 2L)
  topc <- sub("/.*$", "", rel)
  base <- basename(af)

  ent <- lapply(tops, function(nm) {
    idx <- which(topc == nm)
    p   <- file.path(zone_path, nm)
    isd <- dir.exists(p)
    if (length(idx) == 0) {
      di <- file.info(p, extra_cols = FALSE)
      sz <- if (isd) 0 else di$size
      mt <- di$mtime
      nf <- if (isd) 0L else 1L
      man <- FALSE
    } else {
      sz  <- sum(fi$size[idx], na.rm = TRUE)
      mt  <- fi$mtime[idx]
      nf  <- length(idx)
      man <- any(grepl("manifest", base[idx], ignore.case = TRUE))
    }
    out <- list(
      name        = nm,
      is_dir      = isd,
      n_files     = nf,
      size        = fmt_size(sz),
      size_bytes  = sum(sz, na.rm = TRUE),
      mtime_min   = fmt_date(suppressWarnings(min(mt, na.rm = TRUE))),
      mtime_max   = fmt_date(suppressWarnings(max(mt, na.rm = TRUE))),
      has_manifest = man
    )
    if (!is.null(mode_fn)) out$mode <- mode_fn(nm, isd)
    out
  })
  # 최근 활동 순 정렬 (항해 편의)
  mt_max <- vapply(ent, function(e) ifelse(is.na(e$mtime_max), "", e$mtime_max), "")
  ent <- ent[order(mt_max, decreasing = TRUE)]
  list(zone       = zone_rel,
       n_entries  = length(ent),
       n_files    = length(af),
       size_bytes = sum(fi$size, na.rm = TRUE),
       size       = fmt_size(fi$size),
       mtime_max  = fmt_date(suppressWarnings(max(fi$mtime, na.rm = TRUE))),
       entries    = ent)
}

# ---- (a) stage_artifacts: mode 추정 휴리스틱 ---------------------------------
guess_stage_mode <- function(nm, isd) {
  if (grepl("^WT[-_]", nm))                          return("worktask_run")
  if (grepl("^S0_VERDICT|^[sS][0-7][_-]", nm))       return("legacy_stage_S0_S7")
  if (grepl("^l_code|^L[-_]?[0-9]", nm))             return("l_code")
  if (grepl("^(judge|governor|forge|architect|blender|scout|alpha_pkg|optimizer|risk)", nm, ignore.case = TRUE))
                                                     return("agent_artifact")
  if (grepl("^alpha_search", nm))                    return("alpha_search")
  if (grepl("^(ramp|RAMP)", nm))                     return("ramp")
  if (grepl("^(fr_|FR[-_])", nm))                    return("factor_rotation")
  if (grepl("^pg2", nm, ignore.case = TRUE))         return("pg2")
  if (nm %in% c("reports") || grepl("\\.md$", nm))   return("report")
  if (grepl("^ax_|^AX", nm))                         return("axiom")
  "other"
}

# ---- 스캔 실행 ---------------------------------------------------------------
cat("[artifact_index] scanning zones under", root, "...\n")
z_stage    <- scan_zone("stage_artifacts", mode_fn = guess_stage_mode)
z_research <- scan_zone("04_Research")
z_outputs  <- scan_zone("outputs")

# (c) outputs: canonical 데이터 존 — 파이프라인별 depth-1 파일명까지 (소량)
if (!is.null(z_outputs)) {
  z_outputs$pipelines <- lapply(
    Filter(function(e) e$is_dir, z_outputs$entries),
    function(e) {
      p <- file.path(root, "outputs", e$name)
      c(e[c("name", "n_files", "size", "mtime_max")],
        list(files_depth1 = list.files(p)))
    })
}

# (d) registry 존: 파일별 정체 1줄 (알려진 것 수록, 미상은 "(미기재)")
registry_desc <- c(
  "module_catalog.json"           = "모듈 풀 카탈로그 — register_module 표준화 산출 전체 (FR/RAMP 소비원)",
  "hypothesis_index.json"         = "가설 이력 인덱스 (H_XXXX 전수 — 중복가설 방지 조회처)",
  "overlay_candidate_queue.json"  = "오버레이 후보 큐 (screening tier screen_route=OVERLAY_CANDIDATE)",
  "overlay_ab_results"            = "오버레이 A/B 실측 결과",
  "module_performance.json"       = "FR input-floor allowlist 모듈 성과 (build_module_performance 산출)",
  "module_performance.FULL_B.json" = "module_performance FULL_B 스냅샷 (백업)",
  "module_quarantine.json"        = "계약 floor 미충족 모듈 격리 보존",
  "module_regime_admission.json"  = "RCMA 국면조건부 모듈 admission 결과",
  "factor_rotation_registry.json" = "FR_XXXX 운용체계 레지스트리",
  "factor_rotation_registry.json.pre_c2ab_backup" = "FR 레지스트리 백업 (pre_c2ab)",
  "paper_registry.json"           = "논문 수집 레지스트리 (paper research 파이프라인)",
  "strategy_registry.json"        = "legacy 전략 레지스트리 (STR_XXX, v55 계보)",
  "strategy_registry.json.backup_phaseE_20260425_220537" = "legacy 전략 레지스트리 백업",
  "strategy_grades.json"          = "legacy 전략 등급표",
  "idea_registry.json"            = "아이디어 레지스트리 (legacy)",
  "briefing_config.json"          = "모닝브리핑 설정",
  "quant_profile.md"              = "퀀트 프로필 문서",
  "hook_skip_audit.log"           = "hook skip 감사 로그",
  "live_track"                    = "라이브 트래킹 (holdout_interval 사전등록 + 월간 대조)",
  "book_carrier"                  = "book carrier 상태 산출",
  "ramp"                          = "RAMP 모드 레지스트리 산출 (RAMP_XXXX)",
  "artifact_index.json"           = "본 빌더 산출 — 전체 산출물 인덱스"
)
z_registry <- scan_zone(registry_zone)
if (!is.null(z_registry)) {
  z_registry$entries <- lapply(z_registry$entries, function(e) {
    e$desc <- if (e$name %in% names(registry_desc)) unname(registry_desc[[e$name]]) else "(미기재)"
    e
  })
}

# (e) qepm/mailbox/worktask: WT 수 요약 (읽기만 — qepm 내부 불변)
wt_dir <- file.path(root, "qepm", "mailbox", "worktask")
z_wt <- NULL
if (dir.exists(wt_dir)) {
  wts <- list.files(wt_dir, no.. = TRUE)
  wti <- file.info(file.path(wt_dir, wts), extra_cols = FALSE)
  ord <- order(wti$mtime, decreasing = TRUE)
  z_wt <- list(
    zone      = "qepm/mailbox/worktask",
    n_worktasks = length(wts),
    breakdown = as.list(table(ifelse(grepl("^WT-D", wts), "WT-D*",
                        ifelse(grepl("^WT-P", wts), "WT-P*",
                        ifelse(grepl("^WT",   wts), "WT*",
                        ifelse(grepl("^FR",   wts), "FR*", "other")))))),
    latest    = lapply(head(ord, 5), function(i)
      list(name = wts[i], mtime = fmt_date(wti$mtime[i])))
  )
}

# ---- artifact_index.json 쓰기 -----------------------------------------------
index <- list(
  generated_at   = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  generator      = "02_Infrastructure/tools/build_artifact_index.R",
  project_root   = root,
  registry_zone  = registry_zone,
  storage_principles = c(
    "stage_artifacts/<mode>/<run_id>/ = 실험 런 (불변·이동금지)",
    "outputs/<pipeline>/ = canonical 데이터 (최신본만)",
    paste0(registry_zone, "/ = 기계가독 상태·큐·인덱스"),
    "04_Research/<topic>/ = 사람용 보고서"),
  zones = list(
    stage_artifacts  = z_stage,
    research         = z_research,
    outputs          = z_outputs,
    registry         = z_registry,
    worktask_mailbox = z_wt
  )
)
idx_path <- file.path(root, registry_zone, "artifact_index.json")
write_json(index, idx_path, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
cat("[artifact_index] wrote", idx_path, "\n")

# ---- ARTIFACTS.md (사람용 대시보드, 1화면) ------------------------------------
zone_row <- function(z, what, entry) {
  if (is.null(z)) return(NULL)
  top_recent <- if (length(z$entries)) z$entries[[1]]$name else "-"
  sprintf("| `%s/` | %s | %d항목 / %s파일 | %s | %s (`%s`) | %s |",
          z$zone, what, z$n_entries, format(z$n_files, big.mark = ","),
          z$size, ifelse(is.na(z$mtime_max), "-", z$mtime_max), top_recent, entry)
}
mode_tab <- ""
if (!is.null(z_stage)) {
  mt <- sort(table(vapply(z_stage$entries, function(e) e$mode, "")), decreasing = TRUE)
  mode_tab <- paste(sprintf("%s %d", names(mt), as.integer(mt)), collapse = " · ")
}
lines <- c(
  "# Qvest 산출물 지도 (ARTIFACTS.md)",
  "",
  sprintf("> 자동 생성 %s — 기계가독 원본: `%s/artifact_index.json` · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동)",
          index$generated_at, registry_zone),
  "",
  paste0("**저장 4원칙**: ① `stage_artifacts/<mode>/<run_id>/` 실험 런(불변·이동금지) ",
         "② `outputs/<pipeline>/` canonical 데이터(최신본만) ",
         "③ `", registry_zone, "/` 기계가독 상태·큐·인덱스 ",
         "④ `04_Research/<topic>/` 사람용 보고서"),
  "",
  "## 존별 현황",
  "",
  "| 존 | 무엇 | 규모 | 크기 | 최근 활동 | 대표 진입점 |",
  "|---|---|---|---|---|---|",
  zone_row(z_stage,    "실험 런 원본 (WT·legacy S0~S7·L-code·agent 산출)", "`reports/` + 최근 WT 디렉토리"),
  zone_row(z_outputs,  "파이프라인 canonical 데이터 (최신본)",              "`outputs/ramp/` (RAMP 순수팩터·팩터군 parquet)"),
  zone_row(z_registry, "기계가독 상태·큐·인덱스 (JSON)",                    "`module_catalog.json` / `hypothesis_index.json`"),
  zone_row(z_research, "사람용 리서치 보고서·분석 (토픽별)",                "`architecture_audit_*` / `pg2_forensics/`"),
  if (!is.null(z_wt)) sprintf("| `qepm/mailbox/worktask/` | QEPM WT 핸드오프 mailbox (불변 기록) | %d WT | - | %s (`%s`) | 최근 WT의 `output/` |",
                              z_wt$n_worktasks, z_wt$latest[[1]]$mtime, z_wt$latest[[1]]$name),
  "",
  if (nzchar(mode_tab)) sprintf("`stage_artifacts` mode 구성: %s", mode_tab),
  "",
  "## 자주 찾는 것",
  "",
  "- **현 book 성과 (noLayer4 PG2)** → `qepm/mailbox/worktask/WT-D20260702_002/output/`",
  "- **감사 보고서** → `04_Research/architecture_audit_*`",
  sprintf("- **가설 이력** → `%s/hypothesis_index.json`", registry_zone),
  sprintf("- **모듈 풀** → `%s/module_catalog.json` (격리분 `module_quarantine.json`)", registry_zone),
  "- **RAMP canonical** → `outputs/ramp/`",
  sprintf("- **오버레이 후보 큐** → `%s/overlay_candidate_queue.json`", registry_zone),
  sprintf("- **라이브 트래킹 (holdout 봉인)** → `%s/live_track/`", registry_zone),
  "",
  "## 갱신",
  "",
  "```bash",
  "Rscript 02_Infrastructure/tools/build_artifact_index.R   # index JSON + 본 파일 동시 재생성",
  "```",
  ""
)
lines <- Filter(Negate(is.null), lines)
md_path <- file.path(root, "ARTIFACTS.md")
con <- file(md_path, open = "w", encoding = "UTF-8")
writeLines(unlist(lines), con)
close(con)
cat("[artifact_index] wrote", md_path, "\n")
cat("[artifact_index] done —",
    sprintf("stage %d entries / research %d / outputs %d / registry(%s) %d / WT mailbox %d\n",
            ifelse(is.null(z_stage), 0L, z_stage$n_entries),
            ifelse(is.null(z_research), 0L, z_research$n_entries),
            ifelse(is.null(z_outputs), 0L, z_outputs$n_entries),
            registry_zone,
            ifelse(is.null(z_registry), 0L, z_registry$n_entries),
            ifelse(is.null(z_wt), 0L, z_wt$n_worktasks)))
