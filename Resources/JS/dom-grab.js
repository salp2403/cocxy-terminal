// Copyright (c) 2026 Said Arturo Lopez. MIT License.
//
// dom-grab.js - In-page bridge for the browser panel's DOM grab feature.
//
// The host installs this script as a `WKUserScript` injected at document
// start. When the user toggles "grab mode" from the toolbar the host
// dispatches `cocxyDOMGrab.enable()` / `cocxyDOMGrab.disable()` via
// `evaluateJavaScript`. While enabled, a click anywhere on the page is
// captured (no navigation, no default submit) and reported back as a
// structured payload through `window.webkit.messageHandlers.cocxyDOMGrab`.
//
// Zero dependencies: vanilla DOM + Webkit messageHandlers. No npm, no
// bundler, no external script load. Drops in unchanged on any page.

(function () {
    "use strict";

    if (window.cocxyDOMGrab) {
        // Already installed — re-injection is a no-op so multiple
        // navigations within the same WKWebView do not stack handlers.
        return;
    }

    var enabled = false;
    var overlay = null;
    var hoveredElement = null;

    // ----- Selector generation -----
    //
    // Priority order (matches the doc-comment on
    // `BrowserDOMGrabPayload.selector`):
    //   1. unique `id` attribute (`#myId`)
    //   2. `[data-testid="..."]`
    //   3. `tag.classList[0]` when unique on the page
    //   4. recursive `:nth-of-type` chain anchored at the closest
    //      ancestor with a stable id, or `<body>` as last resort.
    function buildSelector(el) {
        if (!(el instanceof Element)) return "";
        if (el.id && document.querySelectorAll("#" + cssEscape(el.id)).length === 1) {
            return "#" + cssEscape(el.id);
        }
        var testid = el.getAttribute && el.getAttribute("data-testid");
        if (testid) {
            return "[data-testid=\"" + testid.replace(/"/g, "\\\"") + "\"]";
        }
        if (el.classList.length > 0) {
            var tagClass = el.tagName.toLowerCase() + "." + cssEscape(el.classList[0]);
            try {
                if (document.querySelectorAll(tagClass).length === 1) {
                    return tagClass;
                }
            } catch (e) {
                // Some class names are not CSS-valid — fall through to
                // the nth-of-type chain instead of throwing.
            }
        }
        return nthOfTypeChain(el);
    }

    function nthOfTypeChain(el) {
        var parts = [];
        var node = el;
        while (node && node.nodeType === 1 && node !== document.body) {
            var tag = node.tagName.toLowerCase();
            var idx = 1;
            var sib = node.previousElementSibling;
            while (sib) {
                if (sib.tagName === node.tagName) idx += 1;
                sib = sib.previousElementSibling;
            }
            parts.unshift(tag + ":nth-of-type(" + idx + ")");
            if (node.parentElement && node.parentElement.id) {
                parts.unshift("#" + cssEscape(node.parentElement.id));
                break;
            }
            node = node.parentElement;
        }
        if (parts.length === 0) return "body";
        return parts.join(" > ");
    }

    function cssEscape(value) {
        if (window.CSS && typeof window.CSS.escape === "function") {
            return window.CSS.escape(value);
        }
        // Conservative fallback for very old WebKit. Escapes the
        // characters CSS.escape would: ASCII non-alphanumerics that are
        // not `_` or `-`.
        return String(value).replace(/([^\w-])/g, "\\$1");
    }

    // ----- Visible text -----
    //
    // `innerText` honours layout (collapsed whitespace, hidden
    // elements). Capped at 4 KB so the host-side formatter can rely on
    // a payload that fits in a single message even on extreme nodes.
    function visibleText(el) {
        var raw = el.innerText || el.textContent || "";
        if (raw.length > 4096) {
            raw = raw.slice(0, 4096);
        }
        return raw;
    }

    // ----- Overlay highlight -----
    //
    // A 1-px outline drawn over the hovered element so the user knows
    // exactly which node will be captured on click. The overlay is a
    // floating <div> placed by absolute coordinates; it is never made a
    // child of the hovered element so DOM mutations on the page cannot
    // displace or strip it.
    function ensureOverlay() {
        if (overlay) return overlay;
        overlay = document.createElement("div");
        overlay.setAttribute("data-cocxy-dom-grab-overlay", "true");
        overlay.style.position = "fixed";
        overlay.style.pointerEvents = "none";
        overlay.style.boxSizing = "border-box";
        overlay.style.border = "2px solid #4F8CFF";
        overlay.style.background = "rgba(79, 140, 255, 0.10)";
        overlay.style.borderRadius = "4px";
        overlay.style.transition = "all 60ms ease-out";
        overlay.style.zIndex = "2147483646";
        overlay.style.display = "none";
        document.documentElement.appendChild(overlay);
        return overlay;
    }

    function moveOverlayTo(el) {
        var ov = ensureOverlay();
        if (!el || !(el instanceof Element)) {
            ov.style.display = "none";
            return;
        }
        var r = el.getBoundingClientRect();
        if (r.width === 0 && r.height === 0) {
            ov.style.display = "none";
            return;
        }
        ov.style.left = r.left + "px";
        ov.style.top = r.top + "px";
        ov.style.width = r.width + "px";
        ov.style.height = r.height + "px";
        ov.style.display = "block";
    }

    function hideOverlay() {
        if (overlay) overlay.style.display = "none";
    }

    // ----- Event handlers -----

    function onMouseMove(event) {
        if (!enabled) return;
        var target = event.target;
        if (target === hoveredElement) return;
        hoveredElement = target;
        moveOverlayTo(target);
    }

    function onClick(event) {
        if (!enabled) return;
        // Stop the page from interpreting the click — the user wants to
        // capture, not navigate.
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();

        var el = event.target;
        var payload = {
            selector: buildSelector(el),
            url: location.href,
            title: document.title || "",
            text: visibleText(el),
        };

        try {
            window.webkit.messageHandlers.cocxyDOMGrab.postMessage(payload);
        } catch (e) {
            // No host bridge present (e.g. running outside the Cocxy
            // browser panel). Fail silently so the page stays usable.
        }
    }

    function attachListeners() {
        document.addEventListener("mousemove", onMouseMove, true);
        document.addEventListener("click", onClick, true);
    }

    function detachListeners() {
        document.removeEventListener("mousemove", onMouseMove, true);
        document.removeEventListener("click", onClick, true);
    }

    // ----- Public API -----

    window.cocxyDOMGrab = {
        enable: function () {
            if (enabled) return;
            enabled = true;
            attachListeners();
        },
        disable: function () {
            if (!enabled) return;
            enabled = false;
            detachListeners();
            hideOverlay();
            hoveredElement = null;
        },
        isEnabled: function () {
            return enabled;
        },
    };
})();
