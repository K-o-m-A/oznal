# One-shot sanitizer: replace all non-ASCII chars in app.R with ASCII.
txt <- readLines("app.R", warn = FALSE, encoding = "UTF-8")

repl <- list(
  "\u2014" = "-",    # em dash
  "\u2013" = "-",    # en dash
  "\u2026" = "...",  # ellipsis
  "\u00d7" = "x",    # multiplication sign
  "\u00b1" = "+/-",  # plus-minus
  "\u2265" = ">=",   # >=
  "\u2264" = "<=",   # <=
  "\u2192" = "->",   # right arrow
  "\u00a7" = "S",    # section
  "\u2022" = "*",    # bullet
  "\u201c" = "\"",   # left double quote
  "\u201d" = "\"",   # right double quote
  "\u2018" = "'",    # left single quote
  "\u2019" = "'"     # right single quote
)
for (k in names(repl)) txt <- gsub(k, repl[[k]], txt, fixed = TRUE)
# Drop any remaining non-ASCII bytes as a safety net.
txt <- iconv(txt, "UTF-8", "ASCII", sub = "")
writeLines(txt, "app.R", useBytes = TRUE)
cat("Sanitized app.R: all chars now ASCII.\n")

