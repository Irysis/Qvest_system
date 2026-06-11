# Lens1 Step1: inspect aligned_series.rds structure (read-only)
x <- readRDS("../aligned_series.rds")
cat("class:", paste(class(x), collapse=","), "\n")
if (is.list(x) && !is.data.frame(x)) {
  cat("names:", paste(names(x), collapse=","), "\n")
  for (nm in names(x)) {
    el <- x[[nm]]
    cat("--", nm, ":", paste(class(el), collapse=","), "\n")
    if (is.data.frame(el)) {
      cat("   dim:", paste(dim(el), collapse="x"), "| cols:", paste(colnames(el), collapse=","), "\n")
      print(head(el, 3)); print(tail(el, 3))
    } else if (inherits(el, c("xts","zoo"))) {
      cat("   dim:", paste(dim(el), collapse="x"), "| cols:", paste(colnames(el), collapse=","), "\n")
      print(head(el, 3)); print(tail(el, 3))
    } else if (is.atomic(el)) {
      cat("   length:", length(el), "\n"); print(utils::head(el, 5))
    }
  }
} else if (is.data.frame(x)) {
  cat("dim:", paste(dim(x), collapse="x"), "| cols:", paste(colnames(x), collapse=","), "\n")
  print(head(x, 5)); print(tail(x, 5))
  cat("NA counts:\n"); print(colSums(is.na(x)))
} else if (inherits(x, c("xts","zoo"))) {
  cat("dim:", paste(dim(x), collapse="x"), "| cols:", paste(colnames(x), collapse=","), "\n")
  print(head(x, 5)); print(tail(x, 5))
  cat("NA counts:\n"); print(colSums(is.na(x)))
}
