// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownPreviewView+MessageHandler.swift - WKScriptMessageHandler bridge for markdown preview interactions.

import Foundation
import WebKit

final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var handler: WKScriptMessageHandler?

    init(handler: WKScriptMessageHandler? = nil) {
        self.handler = handler
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handler?.userContentController(userContentController, didReceive: message)
    }
}

extension MarkdownPreviewView: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "cocxy",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let payload = body["payload"] as? [String: Any] else {
            return
        }

        switch type {
        case "checkboxToggle":
            guard let index = payload["index"] as? Int,
                  let checked = payload["checked"] as? Bool else {
                return
            }
            onCheckboxToggle?(index, checked)

        case "clickToSource":
            guard let sourceLine = payload["sourceLine"] as? Int else { return }
            onClickToSource?(sourceLine)

        case "copyToClipboard":
            guard let text = payload["text"] as? String else { return }
            onCopyToClipboard?(text)

        default:
            break
        }
    }
}
