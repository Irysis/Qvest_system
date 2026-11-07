# qv_bash.R — R 에서 bash 를 띄울 때 쓰는 실행 파일 경로 (금칙 ⑦ 의 정본 대체 · 2026-11-07)
#
# 왜: Windows 의 실행 파일 탐색(R system2/system · Python subprocess · cmd)은 System32 를 PATH 보다
#   먼저 본다. WSL 이 깔린 PC(메인 MAINCOMPUTER — Ubuntu · docker-desktop)에는
#   C:\Windows\System32\bash.exe(WSL 런처)가 있어 bare "bash" 가 리눅스 bash 를 띄우고,
#   Windows 경로 스크립트를 열지 못해 실패한다.
#   실측 2026-11-07: Sys.which("bash") = C:\WINDOWS\SYSTEM32\bash.exe(PATH 첫 칸이 Rtools 인데도) ·
#   system2("bash", ...) = /bin/bash(Ubuntu 5.2) status 2. 지문 함수는 그 오류 문구를 반환값으로
#   돌려 '데이터 지문 불일치'로 위장한다. WSL 없는 노트북에선 같은 코드가 Rtools bash 를 집었다.
#
# 해석 순서(처음 실재하는 파일):
#   ① QVEST_BASH — 명시 덮어쓰기(없는 파일을 가리키면 stop — 오타가 조용히 다른 셸로 새지 않게)
#   ② PATH 순서의 첫 bash.exe — Windows 시스템 폴더(System32 · SysWOW64 · Sysnative · Windows 루트)와
#      WindowsApps 는 건너뛴다. = WSL 없는 PC 에서 bare "bash" 가 뜻하던 바로 그 셸
#      (R 안에서는 PATH 첫 칸 Rtools · Git Bash 에서 띄운 프로세스는 Git) → 동작 보존
#   ③ 고정 후보: Rtools45 · Git usr/bin · Git bin
#   비 Windows = "bash" 그대로. Windows 에서 하나도 없으면 stop() — 조용히 WSL 로 떨어지지 않는다.
#
# 사용: source(file.path(<루트>, "02_Infrastructure/ops/qv_bash.R")); system2(qv_bash(), c(...))
# Python 짝 = qv_bash.py(같은 해석 순서). 검사 = 08_Tests/ops/test_qv_bash.R(위반 주입 · 돌연변이 통제) ·
#   bare "bash" 금지 = 08_Tests/hooks/test_r_portability.R 금칙 ⑦ · 계약 = 02_Infrastructure/docs/rules/r-portability.md

.QV_BASH_SKIP <- paste0("(^|[\\\\/])(system32|syswow64|sysnative)([\\\\/]|$)",
                        "|[\\\\/]windowsapps([\\\\/]|$)",
                        "|^[a-z]:[\\\\/]+windows[\\\\/]*$")
.QV_BASH_FIXED <- c("C:/rtools45/usr/bin/bash.exe",
                    "C:/Program Files/Git/usr/bin/bash.exe",
                    "C:/Program Files/Git/bin/bash.exe")

qv_bash <- function(path = Sys.getenv("PATH"), override = Sys.getenv("QVEST_BASH", ""),
                    fixed = .QV_BASH_FIXED, windows = .Platform$OS.type == "windows") {
  if (!isTRUE(windows)) return("bash")
  if (nzchar(override)) {
    if (file.exists(override)) return(gsub("\\\\", "/", override))
    stop(sprintf("QVEST_BASH 가 가리키는 파일이 없다: %s", override), call. = FALSE)
  }
  dirs <- trimws(gsub('"', "", strsplit(path, ";", fixed = TRUE)[[1]], fixed = TRUE))
  dirs <- dirs[nzchar(dirs)]
  dirs <- dirs[!grepl(.QV_BASH_SKIP, dirs, ignore.case = TRUE, perl = TRUE)]
  cands <- c(file.path(sub("[\\\\/]+$", "", dirs), "bash.exe"), fixed)
  hit <- cands[file.exists(cands)]
  if (!length(hit))
    stop("bash.exe 를 찾지 못했다(Git for Windows 또는 Rtools 필요) — System32 의 WSL bash 는 쓰지 않는다",
         call. = FALSE)
  gsub("\\\\", "/", hit[1])
}
