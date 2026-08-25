// Central error handler — normalizes anything thrown by a route
// (including EversendClient's normalized errors) into one JSON shape,
// and never leaks stack traces or raw axios internals to the app.
function errorHandler(err, req, res, next) {
  const status = err.status && err.status >= 400 && err.status < 600 ? err.status : 500;
  if (process.env.NODE_ENV !== 'production') {
    console.error(err);
  }
  res.status(status).json({
    error: err.message || 'Something went wrong.',
    ...(err.details ? { details: err.details } : {}),
    // Lets the app detect "you need a virtual account first" (see
    // paymentRouter.js executePayout) and redirect to that flow,
    // rather than just showing the error text.
    ...(err.needsVirtualAccount ? { needsVirtualAccount: true, virtualAccountCurrency: err.virtualAccountCurrency } : {}),
  });
}

module.exports = { errorHandler };
