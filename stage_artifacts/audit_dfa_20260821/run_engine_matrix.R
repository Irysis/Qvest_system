## run_engine_matrix.R — 엔진 전체 실행 프로브 (P5/P6/P8) — 기존 파이프라인 파일 무수정, env로만 제어.
## verify 하네스의 run_engine 패턴(임시 .R에 Sys.setenv 기입 — r-portability 금칙① 준수)을 그대로 차용.
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
AD<-"stage_artifacts/audit_dfa_20260821"
run_engine<-function(kv, tag){
  tf<-tempfile(fileext=".R")
  writeLines(c(sprintf('Sys.setenv(%s="%s")',names(kv),unlist(kv)),
               'source("02_Infrastructure/ramp/run_ramp_shumulvey_v5_daily.R")'), tf)
  t0<-Sys.time()
  out<-system2("Rscript", args=tf, stdout=TRUE, stderr=TRUE)
  unlink(tf)
  ok<-any(grepl("V5_DONE",out))
  cat(sprintf("[%s] %s (%.1fs)\n", tag, ifelse(ok,"V5_DONE","FAILED"), as.numeric(difftime(Sys.time(),t0,units="secs"))))
  if(!ok) cat("  tail:", paste(tail(out,5),collapse=" | "),"\n")
  invisible(ok)
}
base<-list(SMV_FEATSET="f15", SMV_TUNE="roll", SMV_LAMMULT="1", SMV_TE="3", SMV_MINY="3", SMV_ARMS="M0,D1")

jobs<-list(
  list(kv=c(base, SMV_IDXFILE=file.path(AD,"synth_A.parquet"),   SMV_KEY="audit_a"),   tag="A"),
  list(kv=c(base, SMV_IDXFILE=file.path(AD,"synth_B1.parquet"),  SMV_KEY="audit_b1"),  tag="B1(t*=2010-06-30 이후 치환)"),
  list(kv=c(base, SMV_IDXFILE=file.path(AD,"synth_B2.parquet"),  SMV_KEY="audit_b2"),  tag="B2(t*=2012-03-30 이후 치환)"),
  list(kv=c(base, SMV_IDXFILE=file.path(AD,"synth_P8.parquet"),  SMV_KEY="audit_p8"),  tag="P8(Value만 치환)"),
  list(kv=c(base, SMV_IDXFILE=file.path(AD,"synth_A.parquet"),   SMV_KEY="audit_sh0", SMV_SHIFT="0", SMV_ARMS="D1"), tag="SH0"),
  list(kv=c(base, SMV_IDXFILE=file.path(AD,"synth_A.parquet"),   SMV_KEY="audit_sh3", SMV_SHIFT="3", SMV_ARMS="D1"), tag="SH3"),
  list(kv=c(base, SMV_IDXFILE=file.path(AD,"synth_M0D.parquet"), SMV_KEY="audit_m0d", SMV_ARMS="M0"), tag="M0D(2010-05-14 단일일 교란)")
)
for(j in jobs) run_engine(j$kv, j$tag)
cat("ENGINE_MATRIX_DONE\n")
