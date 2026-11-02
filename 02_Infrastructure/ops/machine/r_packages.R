#!/usr/bin/env Rscript
# r_packages.R — 두 기계의 R 패키지 판을 맞춘다 (2026-11-01 두 대 운용 · 1_laptop.ps1 / 2_main.ps1 이 부른다)
#
#   Rscript r_packages.R inventory <out.csv>
#       이 기계 설치 목록(.libPaths() 전부 · 원격 설치 정보 포함). Effective = 그 이름이 처음 나오는 라이브러리 = R 이 실제로
#       쓰는 판.
#   Rscript r_packages.R bundle <out_dir> [other.csv]
#       묶을 패키지 목록을 쓴다: base 제외 · R 본체 라이브러리의 recommended 제외(같은 R 판이면 같다) · other.csv(받는 기계의
#       inventory)에 같은 판이 있으면 제외. out_dir/libs.tsv(번호 · 라이브러리 · 개수 · 바이트) + lib<번호>.txt(이름, LF).
#       묶기(tar -czf … -C <라이브러리> -T lib<번호>.txt)는 호출 쪽.
#   Rscript r_packages.R restore <inventory.csv> <extract_dir>
#       보내는 기계 목록에 이 기계를 맞춘다: 없거나 판이 다른 패키지 → extract_dir(묶음을 푼 곳)에 있으면 R_LIBS_USER 로
#       복사(같은 이름 폴더는 바꿔 넣음), 없으면 CRAN 바이너리. 종료 3 = 여전히 없거나 복사 실패한 패키지가 있음.
# 왜 묶음인가: 연구 결과 재현 — CRAN 최신판이 아니라 정본 기계에서 쓰던 판을 그대로 가져온다(같은 R 4.5 · x64 바이너리).

args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args)) args[1] else ""

current <- function() {
  ip <- installed.packages(noCache = TRUE)
  ip <- ip[!duplicated(ip[, "Package"]), , drop = FALSE]
  setNames(ip[, "Version"], ip[, "Package"])
}

write_lf <- function(lines, path) {
  con <- file(path, "wb")
  on.exit(close(con))
  writeLines(lines, con, sep = "\n", useBytes = TRUE)
}

inventory <- function(out) {
  ip <- installed.packages(noCache = TRUE,
                           fields = c("RemoteType", "RemoteUsername", "RemoteRepo", "RemoteRef", "RemoteSha", "Repository"))
  cols <- c("Package", "LibPath", "Version", "Priority", "Built", "Repository",
            "RemoteType", "RemoteUsername", "RemoteRepo", "RemoteRef", "RemoteSha")
  df <- as.data.frame(ip[, intersect(cols, colnames(ip)), drop = FALSE], stringsAsFactors = FALSE)
  df$Effective <- !duplicated(df$Package)
  write.csv(df, out, row.names = FALSE)
  cat(sprintf("INVENTORY %s packages=%d effective=%d R=%s libs=%s\n", out, nrow(df), sum(df$Effective),
              getRversion(), paste(.libPaths(), collapse = ";")))
}

bundle <- function(out_dir, other = NA) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ip <- installed.packages(noCache = TRUE)
  df <- data.frame(Package = ip[, "Package"], LibPath = ip[, "LibPath"], Version = ip[, "Version"],
                   Priority = ip[, "Priority"], stringsAsFactors = FALSE)
  df <- df[!duplicated(df$Package), ]
  rh <- tolower(normalizePath(R.home("library"), winslash = "/", mustWork = FALSE))
  lib <- normalizePath(df$LibPath, winslash = "/", mustWork = FALSE)
  # translations = R 본체 라이브러리의 번역 묶음(Priority 가 NA 라 걸러 내야 한다 — R 판마다 따로 온다)
  keep <- (is.na(df$Priority) | (df$Priority == "recommended" & tolower(lib) != rh)) & df$Package != "translations"
  same_n <- 0
  if (!is.na(other) && file.exists(other)) {
    o <- read.csv(other, stringsAsFactors = FALSE)
    o <- o[as.logical(o$Effective), ]
    have <- setNames(o$Version, o$Package)
    same <- !is.na(have[df$Package]) & have[df$Package] == df$Version
    same_n <- sum(keep & same)
    keep <- keep & !same
  }
  df <- df[keep, ]
  lib <- lib[keep]
  libs <- unique(lib)
  rows <- character()
  total <- 0
  for (i in seq_along(libs)) {
    p <- sort(df$Package[lib == libs[i]])
    write_lf(p, file.path(out_dir, sprintf("lib%d.txt", i)))
    f <- list.files(file.path(libs[i], p), recursive = TRUE, full.names = TRUE, all.files = TRUE)
    b <- sum(as.numeric(file.info(f)$size), na.rm = TRUE)
    total <- total + b
    rows <- c(rows, sprintf("%d\t%s\t%d\t%.0f", i, libs[i], length(p), b))
  }
  write_lf(c("n\tlib\tpackages\tbytes", rows), file.path(out_dir, "libs.tsv"))
  cat(sprintf("BUNDLE packages=%d libs=%d same_version_on_other=%d bytes=%.0f (%.2f GB)\n",
              nrow(df), length(libs), same_n, total, total / 1024^3))
}

restore <- function(inv_csv, ex) {
  lib <- Sys.getenv("R_LIBS_USER")
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(lib, .libPaths()))
  inv <- read.csv(inv_csv, stringsAsFactors = FALSE)
  inv <- inv[as.logical(inv$Effective) & (is.na(inv$Priority) | inv$Priority != "base") & inv$Package != "translations", ]
  have <- current()
  need <- inv$Package[is.na(have[inv$Package]) | have[inv$Package] != inv$Version]
  cat(sprintf("RESTORE lib=%s source_packages=%d missing_or_different=%d\n", lib, nrow(inv), length(need)))
  from_bundle <- need[file.exists(file.path(ex, need, "DESCRIPTION"))]
  bad <- character()
  for (p in from_bundle) {
    unlink(file.path(lib, p), recursive = TRUE)
    if (!isTRUE(all(file.copy(file.path(ex, p), lib, recursive = TRUE)))) bad <- c(bad, p)
  }
  left <- setdiff(need, from_bundle)
  if (length(left)) {
    cat("CRAN:", paste(left, collapse = " "), "\n")
    try(install.packages(left, lib = lib, repos = "https://cloud.r-project.org", type = "binary", quiet = TRUE))
  }
  have <- current()
  miss <- inv$Package[is.na(have[inv$Package])]
  diffv <- inv$Package[!is.na(have[inv$Package]) & have[inv$Package] != inv$Version]
  cat(sprintf("RESULT from_bundle=%d copy_fail=%d cran_tried=%d still_missing=%d version_differs=%d\n",
              length(from_bundle), length(bad), length(left), length(miss), length(diffv)))
  if (length(bad)) cat("COPY_FAIL:", paste(bad, collapse = " "), "\n")
  if (length(miss)) cat("MISSING:", paste(miss, collapse = " "), "\n")
  if (length(diffv)) cat("VERSION_DIFF:", paste(head(diffv, 60), collapse = " "), "\n")
  quit(status = if (length(miss) || length(bad)) 3 else 0)
}

switch(mode,
  inventory = inventory(args[2]),
  bundle    = bundle(args[2], if (length(args) >= 3) args[3] else NA),
  restore   = restore(args[2], args[3]),
  { cat("usage: Rscript r_packages.R inventory <out.csv> | bundle <out_dir> [other.csv] | restore <inventory.csv> <extract_dir>\n"); quit(status = 2) }
)
