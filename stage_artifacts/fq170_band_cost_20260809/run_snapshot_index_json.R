## 색인을 JSON 으로 재발행 — .csv 는 .gitignore:24 `*.csv` 로 추적 불가
## (스냅샷의 목적이 '추적 가능하게 만드는 것'인데 색인만 다시 무시되면 자기모순)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
D <- file.path(CODE_ROOT, "06_Registry")
M <- fread(file.path(D, "round_closures_snapshot_20260809_index.csv"))
out <- file.path(D, "round_closures_snapshot_20260809_index.json")
write_json(M, out, pretty = TRUE, auto_unbox = TRUE, digits = NA)
back <- as.data.table(fromJSON(out))
cat(sprintf("색인 JSON: %s\n행 %d → 재읽기 %d · 열 일치 %s\n", out, nrow(M), nrow(back),
            identical(sort(names(M)), sort(names(back)))))
unlink(file.path(D, "round_closures_snapshot_20260809_index.csv"))
cat("csv 색인 제거(추적 불가라 혼동 유발)\n")
## evidence_refs 실측 재확인 — grep 문자열 계수와 의미 계수의 차이
cat(sprintf("\nevidence_refs 비어있지 않은 레코드: %d / %d (grep 으로는 367 로 보였다)\n",
            sum(M$n_evid > 0), nrow(M)))
cat(sprintf("next_probes >= 2: %d / %d\n", sum(M$n_probes >= 2), nrow(M)))
