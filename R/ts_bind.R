#' Bind Time Series
#'
#' Combine time series to a new, single time series. `ts_bind` combines time
#' series as they are, `ts_chain` chains them together, using percentage change
#' rates.
#'
#' @seealso [ts_c] to collect multiple time series
#' @param ... ts-boxable time series, objects of class `ts`, `xts`, `data.frame`, `data.table`, or `tibble`. Or a numeric vector (see examples).
#'
#' @return A ts-boxable object of the same class as the input.
#' If series of different classes are combined, the class of the first series is
#' used (if possible).
#'
#' @examples
#' ts_bind(ts_span(mdeaths, end = "1975-12-01"), fdeaths)
#' ts_bind(mdeaths, c(2, 2))
#' ts_bind(mdeaths, 3, ts_bind(fdeaths, c(99, 2)))
#' ts_bind(ts_dt(mdeaths), AirPassengers)
#' 
#' # numeric vectors
#' ts_bind(12, AirPassengers, c(2, 3))
#' 
#' @export
ts_bind <- function(...) {
  ll <- list(...)

  tsboxable <- vapply(ll, ts_boxable, TRUE)
  desired.class <- desired_class(ll[tsboxable])

  z <- Reduce(bind_two, ll)

  as_class(desired.class)(z)
}


bind_numeric <- function(a, b, backwards = FALSE) {

  if (!ts_boxable(a)) {stop("at least one object must be ts-boxable")}

  a <- ts_dts(copy(a))
  cname <- dts_cname(a)

  # allow logical NAs
  if (all(is.na(b)) && is.logical(b)) b <- as.numeric(b)

  stopifnot(is.numeric(b))
  a <- ts_regular(a)

  add_scalar_one <- function(x) {
    per.to.add <- length(b)

    if (!backwards){
      # having at least 5 obs allows time_shift to detect frequency
      shft <- time_shift(x$time[(length(x$time) - per.to.add - 5):length(x$time)], per.to.add)
      new.time.stamps <- shft[(length(shft) - per.to.add + 1):length(shft)]
    } else {
      shft <- time_shift(x$time[1:(per.to.add + 5)], -per.to.add)
      new.time.stamps <- shft[1:per.to.add]
    }

    new.x <- data.table(
      time = new.time.stamps,
      value = b
    )

    z <- rbind(x, new.x)

    if (backwards){
      setorder(z, time)
    } 
    z
  }

  setnames(a, cname$time, "time")
  setnames(a, cname$value, "value")
  .by <- parse(text = paste0("list(", paste(cname$id, collapse = ", "), ")"))
  z <- a[
    ,
    add_scalar_one(.SD),
    by = eval(.by)
  ]
  setnames(z, "value", cname$value)
  setnames(z, "time", cname$time)

  return(z)
}



# Bind two dts objects
bind_two <- function(a, b) {
  value <- NULL
  value_b <- NULL

  # append numeric to dts object
  if (!ts_boxable(b)) {
    return(bind_numeric(a, b))
  }
  if (!ts_boxable(a)) {
    return(bind_numeric(b, a, backwards = TRUE))
  }

  a <- ts_dts(copy(a))
  b <- ts_dts(copy(b))

  cname <- dts_cname(a)

  setnames(a, cname$time, "time")
  setnames(b, dts_cname(b)$time, "time")

  setnames(a, cname$value, "value")
  setnames(b, cname$value, "value_b")

  if (!identical(cname$id, dts_cname(b)$id)) {
    stop(
      "Series do not have the same ids: ",
      paste(cname$id, collapse = ", "),
      "and",
      paste(dts_cname(b)$id, collapse = ", ")
    )
  }

  z <- merge(a, b, by = c(cname$id, "time"), all = TRUE)
  # remove key added by merge
  setkey(z, NULL)
  z <- z[is.na(value), value := value_b]
  z[, value_b := NULL]

  # canonical col order
  setcolorder(z, c(setdiff(names(z), c("time", "value")), c("time", "value")))

  setnames(z, "time", cname$time)
  setnames(z, "value", cname$value)
  z[]
}
