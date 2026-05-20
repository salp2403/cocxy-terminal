const express = require("express");
const compression = require("compression");
const helmet = require("helmet");
const fs = require("fs");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const PUBLIC_SUBDIR = path.join(__dirname, "public");
const PUBLIC_ROOT = fs.existsSync(path.join(PUBLIC_SUBDIR, "index.html"))
  ? PUBLIC_SUBDIR
  : __dirname;
const REDIRECTS = Object.freeze({
  "/getting-started.html": "/docs/first-run.html",
  "/es/getting-started.html": "/es/docs/first-run.html",
});
const PUBLIC_ROOT_FILES = new Set([
  "/",
  "/health",
  "/index.html",
  "/llms.txt",
  "/manifest.webmanifest",
  "/robots.txt",
  "/sitemap.xml",
]);
const PUBLIC_ROOT_DIRECTORIES = Object.freeze([
  "/css/",
  "/docs/",
  "/es/",
  "/features/",
  "/images/",
  "/js/",
  "/og/",
  "/videos/",
]);

function isPublicRequestPath(requestPath) {
  if (PUBLIC_ROOT_FILES.has(requestPath)) return true;
  if (/^\/[^/]+\.html$/.test(requestPath)) return true;
  return PUBLIC_ROOT_DIRECTORIES.some((prefix) => requestPath.startsWith(prefix));
}

app.use(compression());

app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        fontSrc: ["'self'"],
        imgSrc: ["'self'", "data:"],
        scriptSrc: ["'self'", "'unsafe-inline'"],
        connectSrc: ["'self'"],
        frameAncestors: ["'none'"],
      },
    },
    crossOriginEmbedderPolicy: false,
    frameguard: {
      action: "deny",
    },
  })
);

app.use((_req, res, next) => {
  res.setHeader(
    "Permissions-Policy",
    "geolocation=(), microphone=(), camera=(), payment=(), usb=()"
  );
  next();
});

app.use((req, res, next) => {
  const target = REDIRECTS[req.path];
  if (target) {
    return res.redirect(301, target);
  }
  return next();
});

app.use((req, res, next) => {
  if (!isPublicRequestPath(req.path)) {
    return res.status(404).type("text/plain").send("Not found");
  }
  return next();
});

app.use(
  express.static(PUBLIC_ROOT, {
    dotfiles: "ignore",
    index: "index.html",
    maxAge: process.env.NODE_ENV === "production" ? "1y" : 0,
    etag: true,
  })
);

app.get("/health", (_req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

app.use((_req, res) => {
  res.status(404).sendFile(path.join(PUBLIC_ROOT, "index.html"), (error) => {
    if (error && !res.headersSent) {
      res.status(404).type("text/plain").send("Not found");
    }
  });
});

app.listen(PORT, () => {
  console.log(`Cocxy web running on http://localhost:${PORT}`);
});
