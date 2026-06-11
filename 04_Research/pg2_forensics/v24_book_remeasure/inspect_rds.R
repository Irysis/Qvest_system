bt <- readRDS("C:/Users/99922/OneDrive/Quant_Module_Moltbot/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result_layer5_R05.rds")
cat("top-level names:\n"); print(names(bt))
for (nm in names(bt)) {
  x <- bt[[nm]]
  cat("\n===", nm, "=== class:", paste(class(x), collapse=","), "\n")
  if (is.data.frame(x)) { cat("dim:", dim(x), "| cols:", paste(head(colnames(x),30), collapse=", "), "\n"); print(utils::head(x,2)) }
  else if (is.list(x)) { cat("names:", paste(head(names(x),40), collapse=", "), "\n") }
  else { cat("len:", length(x), "\n"); print(utils::head(x,3)) }
}
