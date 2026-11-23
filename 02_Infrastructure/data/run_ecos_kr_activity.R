## run_ecos_kr_activity.R — 밤 갱신 [4ka] 가 부르는 실행 스크립트: 한국 경기 지표(ECOS 9계열) 수집.
##   작업 폴더 = 02_Infrastructure (daily_refresh.sh 가 cd "$INFRA" 뒤에 부른다). 손으로 돌릴 때도 같다:
##     cd 02_Infrastructure && Rscript --no-save data/run_ecos_kr_activity.R
##   수집기 · 쓰는 파일 · 가용일 규칙 = data/data_collector_ecos_activity.R 머리말.
##   run_r 블록으로 두지 않은 이유: 스텝 번호(r<N>)가 밀려 뒤 단계의 실패 서명이 흔들리지 않게 하고, 연구용(3등급) 계열의 실패를 단계 실패로 세지 않기 위해서다.
source("config.R")
source("data/data_collector_ecos_activity.R")
ecos_fetch_kr_activity()
