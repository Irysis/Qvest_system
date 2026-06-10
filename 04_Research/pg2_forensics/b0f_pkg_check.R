# b0f_pkg_check.R — package availability
for (p in c("data.table","arrow","jsonlite","xts","zoo","PerformanceAnalytics","sandwich","lmtest")) {
  cat(sprintf("%-22s %s\n", p, ifelse(requireNamespace(p, quietly=TRUE), "OK", "MISSING")))
}
