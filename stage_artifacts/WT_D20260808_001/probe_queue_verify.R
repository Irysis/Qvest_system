suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
f <- "06_Registry/alpha_frontier_queue.json"
x <- try(fromJSON(f, simplifyVector = FALSE), silent = TRUE)
cat("JSON parse:", ifelse(inherits(x, "try-error"), "FAIL", "OK"), "\n")
if (inherits(x, "try-error")) { cat(as.character(x), "\n"); quit(status = 1) }
# 큐 배열 찾기
arr <- NULL
for (k in names(x)) if (is.list(x[[k]]) && length(x[[k]]) > 5 &&
    !is.null(x[[k]][[1]]$id)) { arr <- x[[k]]; cat("큐 배열 키:", k, "· 항목", length(arr), "\n"); break }
if (is.null(arr)) { cat("★큐 배열을 못 찾음 — 구조 확인 필요. 최상위 키:", paste(names(x), collapse=","), "\n"); quit(status=1) }
ids <- vapply(arr, function(e) as.character(e$id %||% ""), character(1))
cat("FQ-122 존재:", "FQ-122" %in% ids, "\n")
r <- arr[[which(ids == "FQ-122")[1]]]
cat("owner:", substr(r$owner, 1, 70), "\n")
cat("status 앞 80자:", substr(r$status, 1, 80), "\n")
cat("in_flight_since:", if (is.null(r$in_flight_since)) "null" else as.character(r$in_flight_since), "\n")
cat("next_probe 건수:", length(r$next_probe), "\n")
cat("revival_conditions 건수:", length(r$revival_conditions), "\n")
cat("measurement_integrity 존재:", !is.null(r$measurement_integrity), "\n")
cat("consumption_faces_swept 존재:", !is.null(r$consumption_faces_swept), "\n")
# 양성 대조: 존재하지 않아야 할 값
cat("[양성대조] 구 status 문자열 잔존:", identical(r$status, "frontier_open"), "(FALSE 여야 정상)\n")
# 타 항목 무손상 census
cat("전체 항목 수:", length(arr), "· id 결측:", sum(!nzchar(ids)), "\n")
