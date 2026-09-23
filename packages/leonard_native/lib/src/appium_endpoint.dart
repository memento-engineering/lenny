/// Request-URL construction shared by the Appium-backed native backends.
library;

/// Joins the root-relative Appium endpoint [path] onto [server], keeping any
/// base path the server is mounted under (Appium 1.x `/wd/hub`, a Selenium
/// Grid, a reverse proxy).
///
/// `Uri.resolve` cannot do this: a root-relative reference replaces the base
/// path, so `http://h:4723/wd/hub` resolving `/session` loses `/wd/hub`. For a
/// server with an empty or `/` path the result equals `server.resolve(path)`.
Uri appiumEndpoint(Uri server, String path) {
  final String base = server.path.endsWith('/')
      ? server.path.substring(0, server.path.length - 1)
      : server.path;
  return server.replace(path: '$base$path');
}
