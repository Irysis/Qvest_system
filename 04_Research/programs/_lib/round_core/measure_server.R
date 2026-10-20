## round_core · 측정 서버 — 1계층 속도 계획 WP2 §6(도훈 10-20 L1-SPEED-PLAN-20261020)
##
## 무엇: 칸마다 Rscript 를 새로 띄우고 원자료(RAWDATA 1,416만 행 × 21열 · parquet 426MB)를 다시 적재하던 측정을 장수 워커가 대신한다.
##   워커는 원자료를 프로세스당 한 번 적재해 '메모리 판본 스냅샷'으로 두고, 칸 사양 큐를 받아 정본 셀 워커
##   02_Infrastructure/ops/rf_cell_worker.R 를 그 파일 그대로 칸마다 실행한다(→ run_paper_replication 을 그대로 호출).
##
## 결과 동일 원칙 — 칸마다 '새 프로세스'와 같은 출발 상태를 만든다(.ms_reset):
##   전역 환경 비움 · 옵션 · 환경변수 · 작업 디렉터리 · 로캘 · 부착 패키지(search path) · 난수 상태 · 그래픽 장치 · 싱크 · 임시 디렉터리를
##   워커 기동 직후 기준선으로 되돌린다. 셀 워커가 run_paper_replication.R 을 칸마다 다시 source 하므로 코드 상태도 새 프로세스와 같다.
##   새 프로세스와 다른 것은 넷뿐이다(전부 결과 동일 실증 — 08_Tests/programs/test_round_core_measure_server.R · PERF_measure.json):
##     (1) load_rawdata() 가 parquet 대신 스냅샷 사본(압축 스냅샷을 푼 새 표)을 돌려준다(행 · 열 · 형 · 속성 동일 — 기동 때 · 검사가 identical 로 확인).
##     (2) 측정 축 위생 멤버십(ma_membership)을 같은 판본 · 같은 epoch · 같은 계약 파일 · 갓 내준 사본이면 워커 안에서 재사용한다
##         (QVEST_MS_MEMO_AXIS=0 이면 끔 · 원 함수의 전역 부수효과(위생 판정식 적재)는 그대로 재현).
##     (3) 정적 PIT 검사 detect_lookahead(엔진 파일 정적 스캔 — 러너 §4 · 계약 감사가 두 번 부른다)의 결과를 같은 검사 대상 md5 ·
##         검출기 md5 · 가용시점 규칙 md5 · 코드 나무 지문이면 재사용한다(QVEST_MS_MEMO_LOOKAHEAD=0 이면 끔 · 결정론 정적 분석).
##     (4) R 기동 · 패키지 이름공간 적재 · Rcpp 동적 라이브러리 적재를 워커당 한 번만 한다.
##   (선택) QVEST_MS_PROFILE=1 — 단계 시간(본문 tryCatch(finally) 감싸기 · 결과 무관)을 칸 완료 기록 stages 에 남긴다.
##   R 프로세스 안에서만 재정의한다 — 계약 · 러너 · 엔진 · 셀 워커 파일은 읽기만 한다(파일 무수정).
##   보이는 차이 두 가지(측정 경로에 소비자 없음 · grep 확인): search path 의 'ms:hooks'(commandArgs · quit · q · source 갈고리) ·
##   칸 출력 싱크 1개(sink.number() = 1 — 새 프로세스는 stdout 리디렉션이라 0).
##
## 판본(데이터 빈티지) — 워커가 스냅샷을 잡는 순간의 RAWDATA.parquet · benchmark.parquet(경로 · 크기 · mtime · md5 · 적재 전후 md5 같음)이 판본이다.
##   측정 중 데이터 갱신이 끼어도 배치 안 모든 칸이 같은 판본을 쓴다(칸별 시작 · 끝 지문 불일치 재측정이 필요 없다).
##   판본 지문은 칸 산출물 디렉터리(measure_server.json) · 칸 완료 기록 · 배치 요약(ms_batch.json)에 남는다.
##   스냅샷을 잡기 전 리프레시 배리어(refresh_barrier.R · 셀 워커와 같은 대기 상한)를 본다 — 잡혀 있으면 스냅샷 없이 멈춘다(fail-closed).
##   ★워커가 여럿이면 워커마다 스냅샷을 잡는다 — 배치 안 판본이 하나인지 ms_submit 이 대조해 반환 열 data_version 과 배치 요약에 남긴다.
##   ★스냅샷 파수꾼(.ms_sentinel) — 칸에 내준 표는 언제나 새 벡터다(압축 해제 · 원형 열 깊은 사본). 칸의 제자리 변경(setorder · set)이
##     스냅샷에 새면 표본 행 대조가 잡고 그 워커는 칸을 더 받지 않는다(10-20 압축 판 E4 실측 누수 → 수리 · 검사 M1 양성 대조).
##
## API(서명 고정 — 실행기가 부른다 · 서버가 없으면 실행기는 measure_round_cell.R 로 대체):
##   ms_submit(specs, workers = NULL, out_root = NULL) → data.frame(칸별 상태 · 결과 경로)
##     specs    칸 사양 JSON 경로 문자 벡터 · 또는 칸 목록 list(list(spec =, code =, role =, result =, md5 =, env = list(..), skip_if_ok =)) · 또는 같은 열의 data.frame
##              code 없으면 사양의 code · result 없으면 <사양 상위>/results/<code>.json(라운드 디렉터리 관례 — rk_measure_cell 과 같음)
##              role ≠ "variant" 면 QVEST_RP_REGISTER=0 · QVEST_RP_NO_FACTOR_ANALYSIS=1(round_core v1 measure_cell.R 규칙) · env 가 그 위를 덮는다
##              md5 가 있으면 사양 파일 md5 와 대조(R2 · 다르면 측정하지 않는다) · skip_if_ok(기본 TRUE) = 결과 JSON 이 ok 면 건너뜀
##     workers  NULL = 자동 floor((여유 RAM GB − QVEST_MS_RESERVE_GB(3)) ÷ QVEST_MS_GB_PER_WORKER) · 최소 1 · 칸 수 · QVEST_MS_MAX_WORKERS 이하
##     out_root run_paper_replication 산출 루트(NULL = 정본 기본값 <ROOT>/stage_artifacts/replication — 셀 워커와 같음)
##   반환 열: code · ok · status · rc · grade · result · artifacts · log · seconds · worker · attempts · data_version · memo_axis
##   배치 기록: <ROOT>/.cache/round_core/measure_server/<batch_id>/(queue · claimed · done · logs · ms_batch.json) · 시간 = .cache/round_core/perf/measure_server.jsonl
##   진행 출력: 칸이 끝날 때마다 '[측정] <code> rc=<n> · <m>분'(round.sh · rk_measure_cell 과 같은 꼴)
##
## 워커: Rscript --no-environ measure_server.R --worker <batch_dir> <wid> — 호출자 환경변수를 그대로 물려받는다(--no-environ:
##   ~/.Renviron 이 QM_ROOT 를 덮지 않게 · 운영에서는 같은 값). 워커는 큐가 빌 때까지 칸을 하나씩 집어(원자적 rename) 실행한다.
##   워커가 죽으면 그 칸은 한 번 다시 큐에 넣는다(라운드 측정의 '인프라 실패 1회 재측정'과 같은 규칙) · 그래도 실패면 worker_died.
##   워커 안에서 서버 함수는 전역이 아닌 사적 환경(부모 = base)에 둔다 — 칸마다 전역을 비워도 서버는 남는다.
## 메모리: 워커 1개 ≈ 스냅샷 + 칸 작업 집합(실측 = PERF_measure.json). GPU 학습을 일으키는 칸의 배치는 호출자 책임이다.
## 금지: 경로 정규화 함수(한글 경로를 깬다 · 구분자 치환만) · 파일 쓰기는 배치 디렉터리 · 칸 결과 경로(.json · .log · .err.log) · 칸 산출물 사이드카(measure_server.json)뿐.

.ms_or <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.atomic(a) && is.na(a))) b else a
ms_root <- function() {
  r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) r <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  sub("/+$", "", gsub("\\\\", "/", r))
}
.ms_self <- function(root = ms_root()) file.path(root, "04_Research/programs/_lib/round_core/measure_server.R")
.ms_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
.ms_md5 <- function(p) unname(as.character(tools::md5sum(p)))
.ms_abs <- function(p, root) { p <- gsub("\\\\", "/", as.character(p)[1]); if (grepl("^([A-Za-z]:)?/", p)) p else file.path(root, p) }
.ms_json_write <- function(x, p) {
  tmp <- paste0(p, ".tmp", Sys.getpid())
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), tmp, useBytes = TRUE)
  if (!isTRUE(suppressWarnings(file.rename(tmp, p)))) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
  invisible(p)
}
.ms_json_read <- function(p) jsonlite::fromJSON(p, simplifyVector = FALSE)

## 여유 RAM(GB) — 실패하면 NA(자동 워커 수 = 1)
ms_free_gb <- function() {
  v <- tryCatch(suppressWarnings(system2("powershell.exe", c("-NoProfile", "-Command",
         shQuote("[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1KB)")), stdout = TRUE, stderr = FALSE)),
         error = function(e) character(0))
  mb <- suppressWarnings(as.numeric(trimws(utils::tail(v, 1))))
  if (length(mb) == 1L && is.finite(mb)) mb / 1024 else NA_real_
}
## 워커당 GB 기본값 10 = 실측 정점(10-20 · 요인 분석 켠 E1 칸 · 워커 PeakWorkingSet 9.9GB = 스냅샷 2.4GB + 칸 작업 집합) — PERF_measure.json.
##   도훈 10-20 지시 '(여유 GB − 3) ÷ 4 이하'의 상한 안쪽(더 적은 워커). 바꾸기 = QVEST_MS_GB_PER_WORKER.
ms_workers_auto <- function(n_cells, free_gb = ms_free_gb(),
                            gb_per_worker = as.numeric(Sys.getenv("QVEST_MS_GB_PER_WORKER", "10")),
                            reserve_gb = as.numeric(Sys.getenv("QVEST_MS_RESERVE_GB", "3")),
                            max_workers = as.integer(Sys.getenv("QVEST_MS_MAX_WORKERS", "8"))) {
  k <- if (is.finite(free_gb) && is.finite(gb_per_worker) && gb_per_worker > 0) floor((free_gb - reserve_gb) / gb_per_worker) else 1
  as.integer(max(1L, min(k, n_cells, max_workers)))
}

## ---- 칸 사양 정규화 ------------------------------------------------------------------------------------------
.ms_norm_specs <- function(specs, root) {
  L <- if (is.character(specs)) lapply(specs, function(p) list(spec = p)) else
       if (is.data.frame(specs)) lapply(seq_len(nrow(specs)), function(i) lapply(as.list(specs[i, , drop = FALSE]), function(v) if (is.factor(v)) as.character(v) else v)) else
       if (is.list(specs) && !is.null(specs[["spec"]])) list(specs) else specs
  if (!is.list(L) || !length(L)) stop("[measure_server] specs 가 비었다")
  out <- lapply(L, function(c) {
    if (!is.list(c) || is.null(c[["spec"]])) stop("[measure_server] 칸마다 spec(사양 JSON 경로)이 필요하다")
    sp <- .ms_abs(c[["spec"]], root)
    if (!file.exists(sp)) stop("[measure_server] 사양 없음: ", sp)
    J <- tryCatch(.ms_json_read(sp), error = function(e) stop("[measure_server] 사양 JSON 판독 실패: ", sp, " — ", conditionMessage(e)))
    code <- as.character(.ms_or(c[["code"]], .ms_or(J[["code"]], sub("\\.json$", "", basename(sp)))))[1]
    if (is.na(code) || !nzchar(code) || grepl("[^A-Za-z0-9_.+-]", code)) stop("[measure_server] 칸 코드 형식 오류: ", code)
    rs <- .ms_or(c[["result"]], NA_character_)
    res <- if (!is.na(rs)) .ms_abs(rs, root) else
           if (identical(basename(dirname(sp)), "specs")) file.path(dirname(dirname(sp)), "results", paste0(code, ".json")) else NA_character_
    role <- as.character(.ms_or(c[["role"]], NA_character_))[1]
    env <- list()
    ## 요인 분석 = 라운드 칸 기본 끔(10-20 · 라운드 판정 · A 관문 · 모듈 등재가 읽지 않음 · A 띠 사후 실행만 RC_FACTOR_ANALYSIS=1) · 등재 = 변형 칸만
    if (!identical(Sys.getenv("RC_FACTOR_ANALYSIS", "0"), "1")) env$QVEST_RP_NO_FACTOR_ANALYSIS <- "1"
    if (!is.na(role) && !identical(role, "variant")) env$QVEST_RP_REGISTER <- "0"
    if (is.list(c[["env"]]) && length(c[["env"]])) {
      if (is.null(names(c[["env"]])) || any(!nzchar(names(c[["env"]])))) stop("[measure_server] env 는 이름 있는 목록이어야 한다: ", code)
      env[names(c[["env"]])] <- lapply(c[["env"]], function(v) as.character(v)[1])
    }
    list(code = code, spec = sp, result = res, role = role, env = env, md5 = as.character(.ms_or(c[["md5"]], NA_character_))[1],
         skip_if_ok = !isFALSE(as.logical(.ms_or(c[["skip_if_ok"]], TRUE))))
  })
  codes <- vapply(out, function(z) z$code, "")
  if (anyDuplicated(codes)) stop("[measure_server] 칸 코드 중복: ", paste(unique(codes[duplicated(codes)]), collapse = ","))
  out
}

## 결과 JSON 판독(셀 워커 산출 꼴)
.ms_result_ok <- function(p) {
  if (is.na(p) || !file.exists(p)) return(FALSE)
  isTRUE(tryCatch(.ms_json_read(p)$ok, error = function(e) FALSE))
}

## ---- 공개 API ------------------------------------------------------------------------------------------------
ms_submit <- function(specs, workers = NULL, out_root = NULL) {
  root <- ms_root()
  cells <- .ms_norm_specs(specs, root)
  t0 <- Sys.time()
  bid <- sprintf("%s_%d", format(t0, "%Y%m%d_%H%M%S"), Sys.getpid())
  bdir <- file.path(root, ".cache", "round_core", "measure_server", bid)
  for (d in c("queue", "claimed", "done", "logs", "results")) dir.create(file.path(bdir, d), recursive = TRUE, showWarnings = FALSE)
  if (!is.null(out_root)) { out_root <- .ms_abs(out_root, root); dir.create(out_root, recursive = TRUE, showWarnings = FALSE) }
  rows <- list(); todo <- list(); nw <- 0L
  for (i in seq_along(cells)) {
    c <- cells[[i]]
    if (is.na(c$result)) c$result <- file.path(bdir, "results", paste0(c$code, ".json"))
    if (!is.na(c$md5) && !identical(.ms_md5(c$spec), c$md5)) {
      cat(sprintf("[측정] %s 사양 md5 ≠ 사전등록(R2) — 측정하지 않는다\n", c$code))
      rows[[c$code]] <- list(code = c$code, ok = FALSE, status = "spec_md5_mismatch", result = c$result); next
    }
    if (isTRUE(c$skip_if_ok) && .ms_result_ok(c$result)) {
      cat(sprintf("[측정] 이미 있음: %s\n", c$code))
      rows[[c$code]] <- list(code = c$code, ok = TRUE, status = "skipped_ok", rc = 0L, result = c$result); next
    }
    c$seq <- i; c$attempt <- 1L
    todo[[c$code]] <- c
  }
  if (length(todo)) {
    for (c in todo) .ms_json_write(c, file.path(bdir, "queue", sprintf("%04d__%s.json", c$seq, c$code)))
    nw <- if (is.null(workers)) ms_workers_auto(length(todo)) else as.integer(max(1L, min(as.integer(workers), length(todo))))
    .ms_json_write(list(schema = "ms_batch_v1", batch = bid, root = root, out_root = out_root, created = .ms_now(), workers = nw,
                        n_cells = length(todo), caller_pid = Sys.getpid()), file.path(bdir, "batch.json"))
    cat(sprintf("== %s [측정 서버] 칸 %d · 워커 %d · 배치 %s ==\n", format(Sys.time(), "%F %T"), length(todo), nw, bid))
    done <- .ms_run_batch(bdir, todo, nw, root)
    for (k in names(todo)) rows[[k]] <- .ms_or(done[[k]], list(code = k, ok = FALSE, status = "missing", result = todo[[k]]$result))
  }
  cols <- c("code", "ok", "status", "rc", "grade", "result", "artifacts", "log", "seconds", "worker", "attempts", "data_version", "memo_axis")
  na_of <- c(ok = NA, rc = NA_integer_, worker = NA_integer_, attempts = NA_integer_, seconds = NA_real_)
  df <- do.call(rbind, lapply(vapply(cells, function(z) z$code, ""), function(k) {
    r <- rows[[k]]
    as.data.frame(lapply(stats::setNames(cols, cols), function(n) {
      v <- r[[n]]
      if (is.null(v) || !length(v)) (if (n %in% names(na_of)) na_of[[n]] else NA_character_) else v[[1]]
    }), stringsAsFactors = FALSE)
  }))
  vers <- unique(stats::na.omit(df$data_version))
  sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  .ms_json_write(list(schema = "ms_batch_v1", batch = bid, root = root, out_root = out_root, finished = .ms_now(), seconds = sec, workers = nw,
                      data_versions = as.list(vers), single_vintage = length(vers) <= 1L, cells = unname(rows)),
                 file.path(bdir, "ms_batch.json"))
  if (length(vers) > 1L) cat(sprintf("[측정 서버] ★배치 안 판본 %d개(워커별 스냅샷 시점이 갈렸다) — %s\n", length(vers), paste(vers, collapse = ",")))
  pd <- file.path(root, ".cache", "round_core", "perf"); dir.create(pd, recursive = TRUE, showWarnings = FALSE)
  cat(jsonlite::toJSON(list(at = .ms_now(), stage = "ms_submit", batch = bid, seconds = round(sec, 2), n_cells = nrow(df),
                            n_ok = sum(df$ok %in% TRUE), workers = nw, data_versions = as.list(vers)), auto_unbox = TRUE),
      "\n", file = file.path(pd, "measure_server.jsonl"), append = TRUE)
  attr(df, "batch_dir") <- bdir
  df
}

## 배치 실행(호출자 프로세스) — 워커 기동 · 완료 수집 · 죽은 워커의 칸 1회 재큐
.ms_rscript <- function() { b <- R.home("bin"); p <- file.path(b, if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"); if (file.exists(p)) p else "Rscript" }
.ms_spawn <- function(bdir, wid, root) {
  args <- c("--no-environ", .ms_self(root), "--worker", bdir, as.character(wid))
  log <- file.path(bdir, "logs", sprintf("worker_%02d.log", wid))
  if (requireNamespace("processx", quietly = TRUE))
    return(processx::process$new(.ms_rscript(), args, stdout = log, stderr = "2>&1", wd = root, cleanup = TRUE, cleanup_tree = TRUE))
  system2(.ms_rscript(), args, wait = FALSE, stdout = log, stderr = log)
  NULL
}
.ms_alive <- function(p) if (is.null(p)) NA else isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))
.ms_run_batch <- function(bdir, todo, nw, root) {
  P <- lapply(seq_len(nw), function(w) .ms_spawn(bdir, w, root)); names(P) <- as.character(seq_len(nw))
  next_wid <- nw + 1L; restarts <- 0L; max_restarts <- 2L * nw
  done <- list()
  close_rest <- function(status) for (k in setdiff(names(todo), names(done)))
    done[[k]] <<- list(code = k, ok = FALSE, status = status, result = todo[[k]]$result)
  repeat {
    for (f in list.files(file.path(bdir, "done"), pattern = "\\.json$", full.names = TRUE)) {
      code <- sub("\\.json$", "", basename(f))
      if (code %in% names(done)) next
      r <- tryCatch(.ms_json_read(f), error = function(e) NULL); if (is.null(r)) next
      done[[code]] <- r
      cat(sprintf("[측정] %s rc=%s · %.1f분%s\n", code, as.character(.ms_or(r$rc, "NA")), as.numeric(.ms_or(r$seconds, NA_real_)) / 60,
                  if (identical(r$status, "ok")) "" else paste0(" · ", r$status)))
    }
    if (all(names(todo) %in% names(done))) break
    alive <- vapply(P, .ms_alive, NA)
    inf <- list.files(file.path(bdir, "logs"), pattern = "^init_failed_.*\\.json$", full.names = TRUE)
    ## 기동 실패(배리어 · 적재 중 원자료 변경) — 살아 있는 워커가 없으면 남은 칸을 그 사유로 닫는다(fail-closed)
    if (length(inf) && !any(alive %in% TRUE)) {
      why <- tryCatch(.ms_json_read(inf[1]), error = function(e) list(reason = "init_failed"))
      close_rest(paste0("init_failed:", sub(" .*$", "", .ms_or(why$reason, "?")))); break
    }
    ## 죽은 워커가 잡고 있던 칸 — 한 번 재큐 · 두 번째면 worker_died
    for (w in names(P)) if (isFALSE(alive[[w]])) {
      for (cf in list.files(file.path(bdir, "claimed"), pattern = paste0("\\.w", w, "$"), full.names = TRUE)) {
        code <- sub("^[0-9]+__(.*)\\.json\\.w[0-9]+$", "\\1", basename(cf))
        if (!(code %in% names(done)) && !file.exists(file.path(bdir, "done", paste0(code, ".json")))) {
          j <- tryCatch(.ms_json_read(cf), error = function(e) NULL)
          att <- as.integer(.ms_or(j$attempt, 1L))
          if (!is.null(j) && att < 2L) { j$attempt <- att + 1L; .ms_json_write(j, file.path(bdir, "queue", sub("\\.w[0-9]+$", "", basename(cf)))) }
          else done[[code]] <- list(code = code, ok = FALSE, status = "worker_died", result = todo[[code]]$result, attempts = att)
        }
        unlink(cf)
      }
      P[[w]] <- NULL
    }
    alive <- vapply(P, .ms_alive, NA)
    pending <- length(list.files(file.path(bdir, "queue"), pattern = "\\.json$"))
    if (pending > 0L && !any(alive %in% TRUE) && !length(inf)) {
      if (restarts >= max_restarts) { close_rest("workers_exhausted"); break }
      P[[as.character(next_wid)]] <- .ms_spawn(bdir, next_wid, root); next_wid <- next_wid + 1L; restarts <- restarts + 1L
    }
    if (pending == 0L && !any(alive %in% TRUE) && !length(list.files(file.path(bdir, "claimed")))) {
      Sys.sleep(1)                                          # 마지막 완료 기록을 한 번 더 줍는다
      for (f in list.files(file.path(bdir, "done"), pattern = "\\.json$", full.names = TRUE)) {
        code <- sub("\\.json$", "", basename(f)); if (!(code %in% names(done))) done[[code]] <- tryCatch(.ms_json_read(f), error = function(e) NULL)
      }
      close_rest("missing"); break
    }
    Sys.sleep(1)
  }
  for (p in P) if (isTRUE(.ms_alive(p))) tryCatch(p$wait(30000), error = function(e) NULL)
  done
}

## ---- 워커 -----------------------------------------------------------------------------------------------------
## 기준선 — 워커 기동 직후(아무것도 적재하기 전) 상태 = 새 Rscript 프로세스의 출발 상태
.ms_capture_baseline <- function() {
  list(options = options(), env = Sys.getenv(), wd = getwd(), search = search(),
       locale = vapply(c("LC_COLLATE", "LC_CTYPE", "LC_MONETARY", "LC_NUMERIC", "LC_TIME"), Sys.getlocale, ""),
       rng = RNGkind())
}
## 옵션 복원 — 기준선에 있던 이름은 기준선 값 · 기준선 뒤 생긴 이름은 이름공간 적재(.onLoad)와 함께 생긴 것만 그 값으로 남긴다
.ms_restore_options <- function(W) {
  cur <- options(); base <- W$baseline$options
  set <- list()
  for (n in names(base)) if (!identical(cur[[n]], base[[n]])) set[n] <- list(base[[n]])
  for (n in setdiff(names(cur), c(names(base), W$opt_pkg))) set[n] <- list(NULL)
  for (n in intersect(W$opt_pkg, names(cur))) if (!identical(cur[[n]], W$opt_pkg_val[[n]])) set[n] <- list(W$opt_pkg_val[[n]])
  if (length(set)) options(set)
  invisible(length(set))
}
## 칸 사이 정리 — 새 프로세스와 같은 출발 상태로
.ms_reset <- function(W) {
  while (sink.number() > 0L) sink()
  if (sink.number(type = "message") != 2L) try(sink(type = "message"), silent = TRUE)
  try(grDevices::graphics.off(), silent = TRUE)
  ## 이름공간 적재로 생긴 옵션을 기준선 예외로 기록(그 이름공간은 다시 .onLoad 하지 않는다)
  ns_new <- setdiff(loadedNamespaces(), W$ns_seen)
  if (length(ns_new)) {
    cur <- options(); nn <- setdiff(names(cur), c(names(W$baseline$options), W$opt_pkg))
    W$opt_pkg <- c(W$opt_pkg, nn); W$opt_pkg_val[nn] <- cur[nn]; W$ns_seen <- loadedNamespaces()
  }
  ## 부착 패키지 · 환경 — 기준선 뒤에 붙은 것을 위(최근)부터 뗀다(이름공간은 남는다 · 다음 library() 가 같은 순서로 다시 붙인다)
  for (s in setdiff(search(), W$baseline$search))
    if (s %in% search()) try(suppressWarnings(detach(s, character.only = TRUE, unload = FALSE, force = TRUE)), silent = TRUE)
  rm(list = ls(globalenv(), all.names = TRUE), envir = globalenv())     # .Random.seed 포함 — 새 프로세스의 빈 전역
  if (!identical(RNGkind(), W$baseline$rng)) {
    suppressWarnings(RNGkind(W$baseline$rng[1], W$baseline$rng[2], W$baseline$rng[3]))
    if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv())
  }
  .ms_restore_options(W)
  ## 환경변수 — 기준선 그대로(늘어난 것 지움 · 바뀐 것 되돌림)
  cur <- Sys.getenv(); be <- W$baseline$env
  extra <- setdiff(names(cur), names(be)); if (length(extra)) Sys.unsetenv(extra)
  cur <- Sys.getenv()
  fix <- names(be)[vapply(names(be), function(n) !identical(as.character(cur[n]), as.character(be[n])), NA)]   # 없는 이름 = NA → 다시 넣는다
  for (n in fix) do.call(Sys.setenv, stats::setNames(list(as.character(be[n])), n))
  for (k in names(W$baseline$locale)) if (!identical(Sys.getlocale(k), W$baseline$locale[[k]])) suppressWarnings(Sys.setlocale(k, W$baseline$locale[[k]]))
  setwd(W$baseline$wd)
  tf <- list.files(tempdir(), full.names = TRUE, all.files = TRUE, no.. = TRUE)
  if (length(tf)) suppressWarnings(unlink(tf, recursive = TRUE, force = TRUE))
  invisible(gc(verbose = FALSE))
}

## 스냅샷 압축(정수 키 · 기본 켬 · QVEST_MS_PACK=0 = 원형) — 문자 열 = 정수 키 + 수준 · 정수값 실수 열(0/1 표식 등) · Date = 정수 일.
##   NaN · −0 · int 범위 밖 · 비정수 · 속성 있는 열은 원형 그대로. 꺼낸 표 = 원형 identical(기동 때 한 번 풀어 대조 · 실패면 원형).
##   10-20 실측: RAWDATA 2.22GB → 1.58GB(−29%) · 꺼내기 0.8초(원형 copy 1.0초) · 압축 10.3초(워커당 1회) — PERF_measure.json snapshot_pack
.ms_pack_col <- function(x) {
  a <- attributes(x)
  if (is.character(x) && is.null(a)) { lv <- unique(x); return(list(k = "chr", codes = match(x, lv), lv = lv)) }
  if (is.double(x) && (is.null(a) || identical(a, list(class = "Date")))) {
    u <- unclass(x)
    if (!any(is.nan(u)) && all(is.na(u) | (abs(u) <= .Machine$integer.max & u == trunc(u))) && !any(u == 0 & 1 / u < 0, na.rm = TRUE))
      return(list(k = "dbl_int", v = as.integer(u), a = a))
  }
  list(k = "raw", v = x)
}
## ★원형 열(raw)은 반드시 깊은 사본으로 꺼낸다 — 그대로 넘기면 칸의 data.table 이 스냅샷과 벡터를 공유하고, 엔진의 setorder · set 같은
##   제자리 변경이 스냅샷을 바꾼다(10-20 실측: 압축 판 E4 에서 둘째 칸부터 산출이 달라졌다 → 이 사본 + 스냅샷 파수꾼으로 막음).
.ms_unpack_col <- function(p) switch(p$k,
  chr = p$lv[p$codes],
  dbl_int = { v <- as.double(p$v); if (!is.null(p$a)) attributes(v) <- p$a; v },
  raw = data.table::copy(p$v))
.MS_TATTR_SKIP <- c("names", "row.names", "class", ".internal.selfref")
.ms_pack <- function(dt) {
  ta <- attributes(dt); ta <- ta[setdiff(names(ta), .MS_TATTR_SKIP)]
  list(cols = lapply(dt, .ms_pack_col), names = names(dt), nrow = nrow(dt), tattr = ta, class = class(dt))
}
.ms_unpack <- function(pk) {
  l <- lapply(pk$cols, .ms_unpack_col); names(l) <- pk$names
  data.table::setDT(l)
  for (n in names(pk$tattr)) data.table::setattr(l, n, pk$tattr[[n]])
  l
}
.ms_snap_nrow <- function(W) if (isTRUE(W$packed)) W$snap$RAWDATA$nrow else nrow(W$snap$RAWDATA)
## 스냅샷 파수꾼 — 고정 격자 표본 행(4,096)의 모든 열 값 + 벤치 전체. 기동 때 적고, 칸을 집기 전 · 사본을 내주기 전마다 대조한다.
##   어긋나면 앞 칸이 스냅샷을 제자리 변경한 것 — 그 워커는 칸을 더 받지 않고 끝난다(호출자가 새 워커 = 새 스냅샷으로 잇는다 · fail-closed).
.ms_sentinel <- function(W) {
  s <- W$snap$RAWDATA; n <- .ms_snap_nrow(W)
  ix <- unique(as.integer(round(seq(1, max(1, n), length.out = min(4096L, max(1L, n))))))
  cols <- if (isTRUE(W$packed)) lapply(s$cols, function(p) switch(p$k, chr = p$codes[ix], dbl_int = p$v[ix], raw = p$v[ix])) else lapply(s, function(v) v[ix])
  list(n = n, cols = cols, bm = lapply(W$snap$BM_DT, function(v) v[seq_along(v)]))
}
.ms_snap_intact <- function(W) identical(.ms_sentinel(W), W$sentinel)
.ms_handout <- function(W) {
  if (!.ms_snap_intact(W)) { W$corrupt <- TRUE; stop("[measure_server] 스냅샷 파수꾼 불일치 — 앞 칸이 스냅샷을 제자리 변경했다(이 칸 측정 중단 · fail-closed)") }
  R <- if (isTRUE(W$packed)) .ms_unpack(W$snap$RAWDATA) else data.table::copy(W$snap$RAWDATA)
  n <- nrow(R); ix <- unique(pmax(1L, pmin(n, c(seq_len(64L), (n %/% 2L) + seq_len(64L), n - 64L + seq_len(64L)))))
  W$handout <- list(addr = data.table::address(R), nrow = n, ix = ix,
                    sig = if ("Ticker" %in% names(R)) R$Ticker[ix] else NULL, dsig = if ("Date" %in% names(R)) R$Date[ix] else NULL)
  R
}
## 갓 내준 사본 그대로인가(같은 객체 · 행 수 · 표본 행의 종목 · 날짜 순서 — 엔진이 정렬하기 전)
.ms_is_handout <- function(W, DT) {
  h <- W$handout
  !is.null(h) && identical(data.table::address(DT), h$addr) && identical(nrow(DT), h$nrow) &&
    (is.null(h$sig) || identical(DT$Ticker[h$ix], h$sig)) && (is.null(h$dsig) || identical(DT$Date[h$ix], h$dsig))
}

## 데이터 판본 — 파일 지문(적재 전후 md5 대조)
.ms_file_fp <- function(p) { fi <- file.info(p); list(path = p, size = as.numeric(fi$size), mtime = format(fi$mtime, "%Y-%m-%dT%H:%M:%OS3"), md5 = .ms_md5(p)) }
.ms_md5_text <- function(s) { f <- tempfile(); on.exit(unlink(f)); writeLines(s, f, useBytes = TRUE); .ms_md5(f) }
.ms_data_version <- function(fp) substr(.ms_md5_text(paste(fp$raw$md5, fp$bm$md5, fp$raw$size, fp$bm$size, sep = "|")), 1, 16)

## 워커 기동 — 배리어 → 코드 예열(run_paper_replication.R source · 이름공간 · Rcpp) → 스냅샷(원본 load_rawdata 1회) → 지문
.ms_init_fail <- function(msg) stop(structure(class = c("ms_init_failed", "error", "condition"), list(message = msg, call = NULL)))
.ms_worker_init <- function(W) {
  root <- W$root
  rb <- new.env(parent = globalenv())
  sys.source(file.path(root, "02_Infrastructure/ops/refresh_barrier.R"), envir = rb, keep.source = FALSE)
  w <- rb$rb_wait(rb$rb_cell_wait_s(), root = root)
  if (!isTRUE(w$proceed)) .ms_init_fail(sprintf("refresh_lock 배리어 %s초 대기 뒤에도 %s", w$waited_s, .ms_or(w$status$state, "?")))
  pr <- file.path(root, ".cache", "RAWDATA.parquet"); pb <- file.path(root, ".cache", "benchmark.parquet")
  fp0 <- list(raw = .ms_file_fp(pr), bm = .ms_file_fp(pb))
  suppressMessages(source(file.path(root, "02_Infrastructure/alpha_search/run_paper_replication.R")))
  res <- get("load_rawdata", envir = globalenv())(use_cache = TRUE)
  fp1 <- list(raw = .ms_file_fp(pr), bm = .ms_file_fp(pb))
  if (!identical(fp0$raw$md5, fp1$raw$md5) || !identical(fp0$bm$md5, fp1$bm$md5))
    .ms_init_fail("data_changed_during_snapshot 적재 중 원자료가 바뀌었다")
  ## 압축(정수 키 · 기본 켬 — QVEST_MS_PACK=0 이면 원형) — 압축본을 한 번 풀어 원형과 identical 일 때만 쓴다(아니면 원형 · 사유 기록)
  W$packed <- FALSE; W$pack_note <- "off"
  if (!identical(Sys.getenv("QVEST_MS_PACK", "1"), "0")) {
    pk <- .ms_pack(res$RAWDATA); u <- .ms_unpack(pk)
    sa <- function(x) { a <- attributes(x); a[[".internal.selfref"]] <- NULL; a[order(names(a))] }
    if (identical(as.list(u), as.list(res$RAWDATA)) && identical(sa(u), sa(res$RAWDATA))) {
      W$packed <- TRUE; W$pack_note <- "verified_identical"; res$RAWDATA <- pk
    } else W$pack_note <- "verify_failed_raw_kept"
    rm(pk, u); invisible(gc(verbose = FALSE))
  }
  W$snap <- list(RAWDATA = res$RAWDATA, BM_DT = res$BM_DT)
  rm(res); invisible(gc(verbose = FALSE))
  W$sentinel <- .ms_sentinel(W); W$corrupt <- FALSE
  W$fp <- fp1; W$data_version <- .ms_data_version(fp1)
  W$axis_memo <- list(); W$axis_memo_on <- !identical(Sys.getenv("QVEST_MS_MEMO_AXIS", "1"), "0")
  W$la_memo <- list(); W$la_memo_on <- !identical(Sys.getenv("QVEST_MS_MEMO_LOOKAHEAD", "1"), "0")
  wp <- file.path(root, "02_Infrastructure/ops/rf_cell_worker.R")
  W$worker_exprs <- parse(wp, keep.source = FALSE, encoding = "UTF-8"); W$worker_md5 <- .ms_md5(wp)
  invisible(W)
}

## 정적 PIT 검사(detect_lookahead) 재사용 키 — 검사 대상 파일 md5 · 검출기 md5 · 가용시점 규칙 파일 md5 ·
##   코드 나무 지문(02_Infrastructure 아래 .R/.py 전부의 경로 · 크기 · mtime — 검출기가 따라 읽는 source 대상 · 파이썬 모듈이 바뀌면 키가 바뀐다)
.ms_code_tree_fp <- function(root) {
  f <- list.files(file.path(root, "02_Infrastructure"), pattern = "\\.(R|r|py)$", recursive = TRUE, full.names = TRUE)
  fi <- file.info(f, extra_cols = FALSE)
  .ms_md5_text(paste(f, fi$size, format(fi$mtime, "%Y%m%d%H%M%OS3"), collapse = "\n"))
}
.ms_la_key <- function(W, path, det_file) {
  p <- gsub("\\\\", "/", as.character(path)[1])
  if (is.na(p) || !file.exists(p) || !file.exists(det_file)) return(NA_character_)
  rules <- file.path(W$root, "06_Registry", "fred_availability_rules.json")
  paste(p, .ms_md5(p), .ms_md5(det_file), if (file.exists(rules)) .ms_md5(rules) else "-", .ms_code_tree_fp(W$root),
        Sys.getenv("QM_ROOT"), as.character(.ms_or(getOption("lookahead.c11_rules"), "")), sep = "|")
}
## 검출기를 실은 환경의 detect_lookahead 를 재사용 판으로 감싼다(형식 인자 · 환경 그대로 · 결과 객체 그대로 재사용)
.ms_wrap_lookahead <- function(W, envir, det_file) {
  if (!isTRUE(W$la_memo_on) || !exists("detect_lookahead", envir = envir, inherits = FALSE)) return(invisible())
  orig <- get("detect_lookahead", envir = envir, inherits = FALSE)
  if (isTRUE(attr(orig, "ms_memo"))) return(invisible())
  wrapped <- function(run_all_path, verbose = TRUE) {
    key <- tryCatch(.ms_la_key(W, run_all_path, det_file), error = function(e) NA_character_)
    if (is.na(key)) return(orig(run_all_path, verbose = verbose))
    hit <- W$la_memo[[key]]
    if (!is.null(hit)) { W$la_hits <- W$la_hits + 1L; return(hit) }
    v <- orig(run_all_path, verbose = verbose)
    W$la_memo[[key]] <- v; W$la_miss <- W$la_miss + 1L
    v
  }
  if (!identical(names(formals(orig)), names(formals(wrapped)))) return(invisible())   # 서명이 바뀌면 감싸지 않는다(원본 그대로)
  attr(wrapped, "ms_memo") <- TRUE
  assign("detect_lookahead", wrapped, envir = envir)
  invisible()
}

## 측정 축 멤버십 재사용 키 — epoch 의 판정 입력 · 계약 파일 md5 · 데이터 판본
.ms_axis_key <- function(W, ep) {
  fz <- file.path(W$root, "02_Infrastructure", "factor_db", "factor_z_standard.R")
  ma <- file.path(W$root, "02_Infrastructure", "contracts", "measurement_axis.R")
  paste(W$data_version, .ms_md5(fz), .ms_md5(ma), as.character(.ms_or(ep$id, "")), isTRUE(ep$hygiene),
        paste(sort(as.character(ep$excluded_flags)), collapse = "+"),
        format(as.numeric(.ms_or(ep$liq_min, NA_real_)), digits = 17), format(as.numeric(.ms_or(ep$price_min, NA_real_)), digits = 17), sep = "|")
}

## 칸 1개 — 셀 워커 파일을 그대로 평가한다(전역 환경 · 'Rscript rf_cell_worker.R <spec> 1 <code> <result>' 와 같은 인자)
.ms_run_job <- function(W, job) {
  .ms_reset(W)
  W$job_code <- job$code; W$handout <- NULL; W$memo_axis <- "off"
  for (k in names(job$env)) do.call(Sys.setenv, stats::setNames(list(as.character(job$env[[k]])), k))
  dir.create(dirname(job$result), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(job$result)) unlink(job$result)
  args <- c(job$spec, "1", job$code, job$result)
  wpath <- file.path(W$root, "02_Infrastructure/ops/rf_cell_worker.R")
  out_root <- W$batch$out_root
  W$la_hits <- 0L; W$la_miss <- 0L; W$prof <- list(); W$pstack <- list()
  prof_on <- identical(Sys.getenv("QVEST_MS_PROFILE", "0"), "1")
  ## (선택) 단계 시간 — 본문을 tryCatch(finally) 로 감싼다(형식 인자 · 환경 · on.exit · return 그대로 · 결과 무관). QVEST_MS_PROFILE=1 일 때만.
  ##   기록 함수는 이름이 아니라 함수 객체를 본문에 박는다 — 감쌀 함수의 환경(전역 · 서버 틀)과 무관하게 찾히고 search path 에 이름을 늘리지 않는다.
  penter <- function(fn) { W$pstack[[length(W$pstack) + 1L]] <- list(fn = fn, t = proc.time()[["elapsed"]]); invisible() }
  pexit <- function(fn) {
    n <- length(W$pstack); k <- n; while (k >= 1L && !identical(W$pstack[[k]]$fn, fn)) k <- k - 1L
    if (k >= 1L) { W$prof[[length(W$prof) + 1L]] <- list(fn = fn, s = proc.time()[["elapsed"]] - W$pstack[[k]]$t, depth = k)
                   W$pstack <- if (k > 1L) W$pstack[seq_len(k - 1L)] else list() }
    invisible()
  }
  prof_wrap <- function(fns) for (fn in fns) if (exists(fn, envir = globalenv(), inherits = FALSE)) {
    f <- get(fn, envir = globalenv(), inherits = FALSE)
    if (!is.function(f) || is.primitive(f) || isTRUE(attr(f, "ms_prof"))) next
    b <- body(f); body(f) <- bquote({ .(penter)(.(fn)); tryCatch(.(b), finally = .(pexit)(.(fn))) }); attr(f, "ms_prof") <- TRUE
    assign(fn, f, envir = globalenv())
  }
  PROF_FUNS <- list(run_paper_replication.R = c("ma_inject_universe", "ma_membership", "detect_lookahead", ".rp_build_weights", "ma_effective_start",
                                                 "run_replication_simulation", ".rp_paper_summary", "build_bt_result", "audit_bt_result", "save_bt_result",
                                                 "essence_score", "ma_signal_coverage", "generate_charts", "run_paper_replication", "load_rawdata"),
                    strategy_analyzer.R = "run_analysis",
                    backtest_result_contract.R = c("build_rolling_metrics", "build_metrics", "build_benchmark_compare", "build_drawdowns"))
  ## 숨은 갈고리 — source 사후 처리: load_rawdata 스냅샷 · out_root 기본값 · 축 멤버십 재사용 · 정적 PIT 검사 재사용 · (선택) 단계 시간
  after_source <- function(file, envir = globalenv()) {
    b <- basename(as.character(file)[1])
    if (identical(b, "lookahead_detector.R")) .ms_wrap_lookahead(W, envir, if (file.exists(file)) file else .ms_abs(file, W$root))
    if (!identical(envir, globalenv())) return(invisible())
    if (prof_on && b %in% names(PROF_FUNS)) prof_wrap(PROF_FUNS[[b]])
    if (identical(b, "backtest_harness.R") && exists("load_rawdata", envir = globalenv(), inherits = FALSE)) {
      orig <- get("load_rawdata", envir = globalenv())
      lr <- function(use_cache = TRUE) {
        if (!isTRUE(use_cache)) return(orig(use_cache = use_cache))
        cat("[load_rawdata] Loading from Parquet cache...\n")
        R <- .ms_handout(W); B <- data.table::copy(W$snap$BM_DT)
        cat(sprintf("[load_rawdata] Cache loaded: %d rows | %s ~ %s\n", nrow(R), min(R$Date), max(R$Date)))
        cat(sprintf("[measure_server] 메모리 판본 스냅샷 %s (RAWDATA md5 %s)\n", W$data_version, substr(W$fp$raw$md5, 1, 12)))
        list(RAWDATA = R, BM_DT = B)
      }
      assign("load_rawdata", lr, envir = globalenv())
    } else if (identical(b, "run_paper_replication.R") && !is.null(out_root) && exists("run_paper_replication", envir = globalenv(), inherits = FALSE)) {
      f <- get("run_paper_replication", envir = globalenv())
      formals(f)$out_root <- out_root
      assign("run_paper_replication", f, envir = globalenv())
    } else if (identical(b, "measurement_axis.R") && isTRUE(W$axis_memo_on) && exists("ma_membership", envir = globalenv(), inherits = FALSE)) {
      orig <- get("ma_membership", envir = globalenv())
      wrapped <- function(DT, ep) {
        if (!.ms_is_handout(W, DT)) { W$memo_axis <- "bypass"; return(orig(DT, ep)) }
        key <- tryCatch(.ms_axis_key(W, ep), error = function(e) NA_character_)
        if (is.na(key)) { W$memo_axis <- "bypass"; return(orig(DT, ep)) }
        hit <- W$axis_memo[[key]]
        if (is.null(hit)) { v <- orig(DT, ep); W$axis_memo[[key]] <- v; W$memo_axis <- "miss"; return(v) }
        ## 원 함수의 전역 부수효과(위생 판정식 적재 — 원 함수 프레임 → 전역 → search path 로 찾는다)를 그대로 재현
        if (!exists("corp_action_member", envir = globalenv(), mode = "function")) {
          f <- file.path(W$root, "02_Infrastructure", "factor_db", "factor_z_standard.R")
          invisible(utils::capture.output(suppressMessages(sys.source(f, envir = globalenv(), keep.source = FALSE))))
        }
        W$memo_axis <- "hit"
        hit
      }
      assign("ma_membership", wrapped, envir = globalenv())
    }
    invisible()
  }
  hooks <- new.env()
  hooks$commandArgs <- function(trailingOnly = FALSE) if (isTRUE(trailingOnly)) args else
    c(.ms_rscript(), "--no-echo", "--no-restore", paste0("--file=", wpath), "--args", args)
  qfun <- function(save = "default", status = 0, runLast = TRUE)
    stop(structure(class = c("ms_quit", "condition"), list(message = "quit", call = NULL, status = as.integer(status))))
  hooks$quit <- qfun; hooks$q <- qfun
  hooks$source <- function(file, local = FALSE, ...) {
    if (isTRUE(local)) local <- parent.frame()
    r <- base::source(file, local = local, ...)
    after_source(file, if (is.environment(local)) local else globalenv())
    invisible(r)
  }
  hooks$sys.source <- function(file, envir = baseenv(), ...) {
    r <- base::sys.source(file, envir = envir, ...)
    if (identical(basename(as.character(file)[1]), "lookahead_detector.R")) .ms_wrap_lookahead(W, envir, file)
    invisible(r)
  }
  log_o <- file(sub("\\.json$", ".log", job$result), open = "wt", encoding = "UTF-8")
  log_e <- file(sub("\\.json$", ".err.log", job$result), open = "wt", encoding = "UTF-8")
  t0 <- Sys.time()
  attach(hooks, pos = 2L, name = "ms:hooks", warn.conflicts = FALSE)
  sink(log_o); sink(log_e, type = "message")
  rc <- tryCatch({
    for (e in W$worker_exprs) eval(e, envir = globalenv())
    0L
  }, ms_quit = function(q) as.integer(q$status),
     error = function(e) { cat("Error:", conditionMessage(e), "\n", file = stderr()); 1L })
  while (sink.number() > 0L) sink()
  if (sink.number(type = "message") != 2L) sink(type = "message")
  close(log_o); close(log_e)
  if ("ms:hooks" %in% search()) detach("ms:hooks", character.only = TRUE)
  sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  R <- if (file.exists(job$result)) tryCatch(.ms_json_read(job$result), error = function(e) NULL) else NULL
  art <- as.character(.ms_or(R$artifacts, NA_character_))[1]
  rec <- list(code = job$code, ok = isTRUE(R$ok), status = if (isTRUE(R$ok)) "ok" else if (is.null(R)) "no_result" else "cell_failed",
              rc = rc, grade = as.character(.ms_or(R$grade, NA_character_))[1], result = job$result, artifacts = art,
              log = sub("\\.json$", ".log", job$result), seconds = sec, worker = W$wid, attempts = as.integer(.ms_or(job$attempt, 1L)),
              data_version = W$data_version, memo_axis = W$memo_axis, memo_lookahead = list(hits = W$la_hits, miss = W$la_miss),
              started = format(t0, "%Y-%m-%dT%H:%M:%S%z"), finished = .ms_now(), rf_cell_worker_md5 = W$worker_md5)
  if (length(W$prof)) rec$stages <- W$prof
  if (!is.na(art) && dir.exists(art))
    .ms_json_write(list(schema = "ms_cell_vintage_v1", mode = "measure_server", batch = W$batch$batch, worker = W$wid, code = job$code,
                        data_version = W$data_version, raw = W$fp$raw, bm = W$fp$bm, packed = isTRUE(W$packed), pack_note = W$pack_note,
                        memo_axis = W$memo_axis, memo_lookahead = list(hits = W$la_hits, miss = W$la_miss),
                        rf_cell_worker_md5 = W$worker_md5, recorded = .ms_now()),
                   file.path(art, "measure_server.json"))
  rec
}

## 큐에서 칸 하나 집기(원자적 rename — 다른 워커와 경합해도 한쪽만 성공)
.ms_claim <- function(bdir, wid) {
  for (f in sort(list.files(file.path(bdir, "queue"), pattern = "\\.json$", full.names = TRUE))) {
    to <- file.path(bdir, "claimed", paste0(basename(f), ".w", wid))
    if (isTRUE(suppressWarnings(file.rename(f, to)))) return(list(path = to, job = .ms_json_read(to)))
  }
  NULL
}

ms_worker_main <- function(bdir, wid) {
  W <- new.env()
  W$baseline <- .ms_capture_baseline()
  W$wid <- as.integer(wid); W$bdir <- bdir
  W$batch <- .ms_json_read(file.path(bdir, "batch.json"))
  W$root <- W$batch$root
  W$opt_pkg <- character(0); W$opt_pkg_val <- list(); W$ns_seen <- loadedNamespaces()
  init <- tryCatch({ .ms_worker_init(W); NULL }, error = function(e) e)
  if (!is.null(init)) {
    .ms_json_write(list(worker = W$wid, at = .ms_now(), reason = conditionMessage(init)), file.path(bdir, "logs", sprintf("init_failed_%02d.json", W$wid)))
    cat("[measure_server] 워커 기동 실패:", conditionMessage(init), "\n")
    base::quit(save = "no", status = 3)
  }
  cat(sprintf("[measure_server] 워커 %d 준비 — 판본 %s · RAWDATA %d행%s\n", W$wid, W$data_version, .ms_snap_nrow(W),
              if (isTRUE(W$packed)) " · 압축 스냅샷" else ""))
  n <- 0L
  repeat {
    if (isTRUE(W$corrupt) || !.ms_snap_intact(W)) {          # 앞 칸이 스냅샷을 바꿨다 — 칸을 더 받지 않는다(새 워커가 새 스냅샷으로 잇는다)
      .ms_json_write(list(worker = W$wid, at = .ms_now(), reason = "snapshot_sentinel_mismatch", after_cells = n),
                     file.path(bdir, "logs", sprintf("snapshot_corrupt_%02d.json", W$wid)))
      cat("[measure_server] 스냅샷 파수꾼 불일치 — 워커 종료(칸", n, "개 뒤)\n")
      base::quit(save = "no", status = 4)
    }
    cl <- .ms_claim(bdir, W$wid)
    if (is.null(cl)) break
    rec <- tryCatch(.ms_run_job(W, cl$job), error = function(e) {
      while (sink.number() > 0L) sink()
      list(code = cl$job$code, ok = FALSE, status = paste0("server_error:", conditionMessage(e)), result = cl$job$result,
           worker = W$wid, attempts = as.integer(.ms_or(cl$job$attempt, 1L)), data_version = W$data_version)
    })
    .ms_reset(W)
    .ms_json_write(rec, file.path(bdir, "done", paste0(cl$job$code, ".json")))
    unlink(cl$path)
    n <- n + 1L
  }
  cat(sprintf("[measure_server] 워커 %d 끝 — 칸 %d\n", W$wid, n))
  base::quit(save = "no", status = 0)
}

## CLI — 워커 진입(Rscript --no-environ measure_server.R --worker <batch_dir> <wid>)
##   서버 함수를 전역에서 사적 환경(부모 = base)으로 옮긴 뒤 전역을 비우고 워커를 돈다(칸마다 전역을 비워도 서버는 남는다).
if (sys.nframe() == 0L && length(commandArgs(trailingOnly = TRUE)) >= 3L && identical(commandArgs(trailingOnly = TRUE)[1], "--worker")) {
  local({
    a <- commandArgs(trailingOnly = TRUE)
    MS <- new.env(parent = baseenv())
    for (n in ls(globalenv(), all.names = TRUE)) if (grepl("^\\.?(ms|MS)_", n)) {
      f <- get(n, envir = globalenv())
      if (is.function(f)) environment(f) <- MS
      assign(n, f, envir = MS)
    }
    rm(list = ls(globalenv(), all.names = TRUE), envir = globalenv())
    MS$ms_worker_main(a[2], a[3])
  })
}
