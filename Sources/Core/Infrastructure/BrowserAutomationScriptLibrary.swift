// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserAutomationScriptLibrary.swift - Pure browser automation scripts and response helpers.

import Foundation

enum BrowserAutomationKeyMode {
    case press
    case down
    case up

    var status: String {
        switch self {
        case .press: return "pressed"
        case .down: return "keydown"
        case .up: return "keyup"
        }
    }
}

enum BrowserAutomationFindSelectorMode {
    case first
    case last
    case nth
}

enum BrowserAutomationStorageArea: String {
    case local
    case session

    var accessor: String {
        switch self {
        case .local: return "window.localStorage"
        case .session: return "window.sessionStorage"
        }
    }
}

struct BrowserAutomationNetworkEntry {
    let url: String
    let method: String
    let initiatorType: String
    let duration: Double
    let transferSize: Int
}

enum BrowserAutomationScriptLibrary {
    static let defaultActionTimeoutMilliseconds = 5_000

    static func isValidRef(_ ref: String) -> Bool {
        guard !ref.isEmpty, ref.count <= 64 else { return false }
        return ref.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }

    static func isValidScrollDelta(_ value: Int) -> Bool {
        value >= -100_000 && value <= 100_000
    }

    static func isValidAttributeName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128 else { return false }
        return name.allSatisfy { character in
            character.isLetter || character.isNumber
                || character == "-" || character == "_" || character == ":"
        }
    }

    static func isValidStyleName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128 else { return false }
        return name.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-"
        }
    }

    static func isValidKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= 32 else { return false }
        return key.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }

    static func isValidFindQuery(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && query.count <= 512
    }

    static func isSafeCookieName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 256 else { return false }
        return !name.contains { character in
            character == "=" || character == ";" || character.isWhitespace || character.isNewline
        }
    }

    static func isValidStorageKey(_ key: String) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && key.count <= 512
    }

    static func flatJSONData(from jsonString: String) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["status": "invalid-response"]
        }
        var result: [String: String] = [:]
        for (key, value) in raw {
            result[key] = stringValue(value)
        }
        return result
    }

    static func findResultData(from jsonString: String) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let rawResults = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ["status": "invalid-response", "count": "0"]
        }
        var dataMap: [String: String] = [
            "status": "ok",
            "count": "\(rawResults.count)"
        ]
        for (index, raw) in rawResults.prefix(50).enumerated() {
            dataMap["ref_\(index)"] = stringValue(raw["ref"] ?? "")
            dataMap["role_\(index)"] = stringValue(raw["role"] ?? "")
            dataMap["name_\(index)"] = stringValue(raw["name"] ?? "")
        }
        return dataMap
    }

    static func frameTreeData(from jsonString: String) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let rawFrames = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ["status": "invalid-response", "count": "0"]
        }
        var dataMap: [String: String] = [
            "status": "ok",
            "count": "\(rawFrames.count)"
        ]
        for (index, raw) in rawFrames.prefix(100).enumerated() {
            dataMap["frame_\(index)_path"] = stringValue(raw["path"] ?? "")
            dataMap["frame_\(index)_name"] = stringValue(raw["name"] ?? "")
            dataMap["frame_\(index)_url"] = stringValue(raw["url"] ?? "")
            dataMap["frame_\(index)_title"] = stringValue(raw["title"] ?? "")
            dataMap["frame_\(index)_isMain"] = stringValue(raw["isMain"] ?? "")
            dataMap["frame_\(index)_sameOrigin"] = stringValue(raw["sameOrigin"] ?? "")
        }
        return dataMap
    }

    static func browserStateSummary(from jsonString: String) -> [String: String]? {
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return [
            "url": stringValue(raw["url"] ?? ""),
            "origin": stringValue(raw["origin"] ?? ""),
            "title": stringValue(raw["title"] ?? ""),
            "cookies": "\((raw["cookies"] as? [Any])?.count ?? 0)",
            "localStorage": "\((raw["localStorage"] as? [Any])?.count ?? 0)",
            "sessionStorage": "\((raw["sessionStorage"] as? [Any])?.count ?? 0)"
        ]
    }

    static func clickScript(
        ref: String,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
            """
            element.click();
            return finish('clicked');
            """
        }
    }

    static func doubleClickScript(
        ref: String,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
            """
            const rect = element.getBoundingClientRect();
            const eventOptions = {
                bubbles: true,
                cancelable: true,
                view: window,
                clientX: Math.round(rect.left + rect.width / 2),
                clientY: Math.round(rect.top + rect.height / 2)
            };
            element.dispatchEvent(new MouseEvent('mouseover', eventOptions));
            element.dispatchEvent(new MouseEvent('mousemove', eventOptions));
            element.dispatchEvent(new MouseEvent('mousedown', {...eventOptions, detail: 1}));
            element.dispatchEvent(new MouseEvent('mouseup', {...eventOptions, detail: 1}));
            element.dispatchEvent(new MouseEvent('click', {...eventOptions, detail: 1}));
            element.dispatchEvent(new MouseEvent('mousedown', {...eventOptions, detail: 2}));
            element.dispatchEvent(new MouseEvent('mouseup', {...eventOptions, detail: 2}));
            element.dispatchEvent(new MouseEvent('click', {...eventOptions, detail: 2}));
            element.dispatchEvent(new MouseEvent('dblclick', {...eventOptions, detail: 2}));
            return finish('dblclicked');
            """
        }
    }

    static func hoverScript(
        ref: String,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
            """
            const rect = element.getBoundingClientRect();
            const eventOptions = {
                bubbles: true,
                cancelable: true,
                view: window,
                clientX: Math.round(rect.left + rect.width / 2),
                clientY: Math.round(rect.top + rect.height / 2)
            };
            element.dispatchEvent(new MouseEvent('mouseover', eventOptions));
            element.dispatchEvent(new MouseEvent('mouseenter', eventOptions));
            element.dispatchEvent(new MouseEvent('mousemove', eventOptions));
            return finish('hovered');
            """
        }
    }

    static func focusScript(
        ref: String,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
            """
            if (typeof element.focus !== 'function') { return fail('not-focusable', 'not-focusable'); }
            element.focus({preventScroll: false});
            return document.activeElement === element
                ? finish('focused')
                : fail('not-focusable', 'not-focusable');
            """
        }
    }

    static func fillScript(
        ref: String,
        text: String,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        let escapedText = javaScriptStringLiteral(text)
        return actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
            """
            if (element.isContentEditable) {
                element.textContent = \(escapedText);
            } else if ('value' in element) {
                element.value = \(escapedText);
            } else {
                return fail('not-editable', 'not-editable');
            }
            element.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: \(escapedText)}));
            element.dispatchEvent(new Event('change', {bubbles: true}));
            return finish('filled');
            """
        }
    }

    static func uploadFileScript(
        ref: String,
        fileName: String,
        mimeType: String,
        base64Data: String,
        byteCount: Int,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        let escapedFileName = javaScriptStringLiteral(fileName)
        let escapedMimeType = javaScriptStringLiteral(mimeType)
        let escapedBase64Data = javaScriptStringLiteral(base64Data)
        return actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
            """
            if (typeof File !== 'function') { return fail('unsupported', 'file-api-unavailable'); }
            if (typeof DataTransfer !== 'function') { return fail('unsupported', 'data-transfer-unavailable'); }
            const fileName = \(escapedFileName);
            const mimeType = \(escapedMimeType) || 'application/octet-stream';
            const base64 = \(escapedBase64Data);
            const binary = atob(base64);
            const bytes = new Uint8Array(binary.length);
            for (let index = 0; index < binary.length; index += 1) {
                bytes[index] = binary.charCodeAt(index);
            }
            const file = new File([bytes], fileName, {type: mimeType});
            const transfer = new DataTransfer();
            transfer.items.add(file);
            const eventOptions = {bubbles: true, cancelable: true};
            const tagName = String(element.tagName || '').toLowerCase();
            const inputType = String(element.getAttribute('type') || '').toLowerCase();
            const isFileInput = tagName === 'input' && inputType === 'file';
            if (isFileInput) {
                try {
                    element.files = transfer.files;
                } catch (error) {
                    return fail('not-uploadable', String(error?.message || error));
                }
            }
            if (typeof element.focus === 'function') {
                try { element.focus({preventScroll: false}); } catch (_) {}
            }
            element.dispatchEvent(new Event('input', eventOptions));
            element.dispatchEvent(new Event('change', eventOptions));
            let dropEvent;
            try {
                dropEvent = new DragEvent('drop', {...eventOptions, dataTransfer: transfer});
            } catch (_) {
                dropEvent = new Event('drop', eventOptions);
                try {
                    Object.defineProperty(dropEvent, 'dataTransfer', {value: transfer});
                } catch (_) {}
            }
            element.dispatchEvent(dropEvent);
            return finish('uploaded', {
                fileName: fileName,
                bytes: String(\(byteCount)),
                fileCount: String(transfer.files.length),
                drop: 'true'
            });
            """
        }
    }

    static func typeScript(
        ref: String?,
        text: String,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        let escapedText = javaScriptStringLiteral(text)
        if let ref {
            return actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
                """
                const text = \(escapedText);
                if (typeof element.focus === 'function') {
                    element.focus({preventScroll: false});
                }
                element.dispatchEvent(new KeyboardEvent('keydown', {key: text, bubbles: true, cancelable: true}));
                if (element.isContentEditable) {
                    const inserted = document.execCommand('insertText', false, text);
                    if (!inserted) {
                        element.textContent = (element.textContent || '') + text;
                    }
                } else if ('value' in element) {
                    const start = Number.isInteger(element.selectionStart) ? element.selectionStart : String(element.value || '').length;
                    const end = Number.isInteger(element.selectionEnd) ? element.selectionEnd : start;
                    const current = String(element.value || '');
                    element.value = current.slice(0, start) + text + current.slice(end);
                    const cursor = start + text.length;
                    if (typeof element.setSelectionRange === 'function') {
                        element.setSelectionRange(cursor, cursor);
                    }
                } else {
                    return fail('not-editable', 'not-editable');
                }
                element.dispatchEvent(new InputEvent('beforeinput', {bubbles: true, inputType: 'insertText', data: text}));
                element.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: text}));
                element.dispatchEvent(new KeyboardEvent('keyup', {key: text, bubbles: true, cancelable: true}));
                return finish('typed');
                """
            }
        }
        let elementExpression: String
        elementExpression = "document.activeElement"
        return pageActionScript(fallbackRef: "active", targetExpression: elementExpression) {
            """
            const text = \(escapedText);
            if (!element || element === document.body || element === document.documentElement) {
                return fail('no-active-element', 'no-active-element');
            }
            if (typeof element.focus === 'function') {
                element.focus({preventScroll: false});
            }
            element.dispatchEvent(new KeyboardEvent('keydown', {key: text, bubbles: true, cancelable: true}));
            if (element.isContentEditable) {
                const inserted = document.execCommand('insertText', false, text);
                if (!inserted) {
                    element.textContent = (element.textContent || '') + text;
                }
            } else if ('value' in element) {
                const start = Number.isInteger(element.selectionStart) ? element.selectionStart : String(element.value || '').length;
                const end = Number.isInteger(element.selectionEnd) ? element.selectionEnd : start;
                const current = String(element.value || '');
                element.value = current.slice(0, start) + text + current.slice(end);
                const cursor = start + text.length;
                if (typeof element.setSelectionRange === 'function') {
                    element.setSelectionRange(cursor, cursor);
                }
            } else {
                return fail('not-editable', 'not-editable');
            }
            element.dispatchEvent(new InputEvent('beforeinput', {bubbles: true, inputType: 'insertText', data: text}));
            element.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: text}));
            element.dispatchEvent(new KeyboardEvent('keyup', {key: text, bubbles: true, cancelable: true}));
            return finish('typed');
            """
        }
    }

    static func keyScript(key: String, mode: BrowserAutomationKeyMode) -> String {
        let escapedKey = javaScriptStringLiteral(key)
        let events: [String]
        switch mode {
        case .press:
            events = ["keydown", "keyup"]
        case .down:
            events = ["keydown"]
        case .up:
            events = ["keyup"]
        }
        let eventDispatches = events.map { eventName in
            "target.dispatchEvent(new KeyboardEvent('\(eventName)', options));"
        }.joined(separator: "\n            ")
        return pageActionScript(
            fallbackRef: "active",
            targetExpression: "document.activeElement || document.body || document.documentElement"
        ) {
            """
            const key = \(escapedKey);
            const target = element || document.body || document;
            const options = {key: key, code: key, bubbles: true, cancelable: true};
            \(eventDispatches)
            return finish('\(mode.status)');
            """
        }
    }

    static func checkedStateScript(
        ref: String,
        checked: Bool,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        let checkedLiteral = checked ? "true" : "false"
        let successStatus = checked ? "checked" : "unchecked"
        let invalidStatus = checked ? "not-checkable" : "not-uncheckable"
        return actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
            """
            if (!('checked' in element)) { return fail('\(invalidStatus)', '\(invalidStatus)'); }
            const type = (element.getAttribute('type') || '').toLowerCase();
            if (!\(checkedLiteral) && type === 'radio') { return fail('not-uncheckable', 'not-uncheckable'); }
            element.checked = \(checkedLiteral);
            element.dispatchEvent(new Event('input', {bubbles: true}));
            element.dispatchEvent(new Event('change', {bubbles: true}));
            return element.checked === \(checkedLiteral)
                ? finish('\(successStatus)')
                : fail('\(invalidStatus)', '\(invalidStatus)');
            """
        }
    }

    static func selectScript(
        ref: String,
        value: String,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        let escapedValue = javaScriptStringLiteral(value)
        return actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
            """
            if (!(element instanceof HTMLSelectElement)) { return fail('not-select', 'not-select'); }
            const desired = \(escapedValue);
            const options = Array.from(element.options);
            let option = options.find((candidate) => candidate.value === desired);
            if (!option) {
                option = options.find((candidate) => {
                    const label = candidate.label || '';
                    const text = (candidate.textContent || '').trim();
                    return label === desired || text === desired;
                });
            }
            if (!option && /^\\d+$/.test(desired)) {
                option = options[Number(desired)];
            }
            if (!option) { return fail('option-not-found', 'option-not-found'); }
            option.selected = true;
            element.value = option.value;
            element.dispatchEvent(new Event('input', {bubbles: true}));
            element.dispatchEvent(new Event('change', {bubbles: true}));
            return element.value === option.value
                ? finish('selected')
                : fail('option-not-found', 'option-not-found');
            """
        }
    }

    static func scrollScript(x: Int, y: Int) -> String {
        pageActionScript(
            fallbackRef: "page",
            targetExpression: "document.scrollingElement || document.documentElement || document.body"
        ) {
            """
            window.scrollBy({left: \(x), top: \(y), behavior: 'instant'});
            return finish('scrolled');
            """
        }
    }

    static func scrollIntoViewScript(
        ref: String,
        timeoutMilliseconds: Int = defaultActionTimeoutMilliseconds
    ) -> String {
        actionableElementScript(ref: ref, timeoutMilliseconds: timeoutMilliseconds) {
            """
            element.scrollIntoView({block: 'center', inline: 'center'});
            return finish('scrolled');
            """
        }
    }

    static func htmlScript(ref: String?) -> String {
        if let ref {
            return """
            (function() {
                \(stableReferencePrelude)
                const element = cocxyResolveStableRef(\(javaScriptStringLiteral(ref)));
                if (!element) { return 'not-found'; }
                return element.outerHTML || '';
            })();
            """
        }
        return """
        (function() {
            return document.documentElement ? document.documentElement.outerHTML : '';
        })();
        """
    }

    static func valueScript(ref: String) -> String {
        """
        (function() {
            \(stableReferencePrelude)
            const element = cocxyResolveStableRef(\(javaScriptStringLiteral(ref)));
            if (!element) { return 'not-found'; }
            if (element.isContentEditable) {
                return element.textContent || '';
            }
            if ('value' in element) {
                return element.value == null ? '' : String(element.value);
            }
            return element.textContent || '';
        })();
        """
    }

    static func attrScript(ref: String, name: String) -> String {
        let escapedName = javaScriptStringLiteral(name)
        return """
        (function() {
            \(stableReferencePrelude)
            const element = cocxyResolveStableRef(\(javaScriptStringLiteral(ref)));
            if (!element) { return JSON.stringify({status: 'not-found'}); }
            const value = element.getAttribute(\(escapedName));
            if (value === null) { return JSON.stringify({status: 'missing'}); }
            return JSON.stringify({status: 'ok', value: value});
        })();
        """
    }

    static func countScript(selector: String) -> String {
        let escapedSelector = javaScriptStringLiteral(selector)
        return """
        (function() {
            try {
                return String(document.querySelectorAll(\(escapedSelector)).length);
            } catch (error) {
                return '0';
            }
        })();
        """
    }

    static func boxScript(ref: String) -> String {
        """
        (function() {
            \(stableReferencePrelude)
            const element = cocxyResolveStableRef(\(javaScriptStringLiteral(ref)));
            if (!element) { return JSON.stringify({status: 'not-found'}); }
            const rect = element.getBoundingClientRect();
            return JSON.stringify({
                status: 'ok',
                x: String(Math.round(rect.x)),
                y: String(Math.round(rect.y)),
                width: String(Math.round(rect.width)),
                height: String(Math.round(rect.height))
            });
        })();
        """
    }

    static func stylesScript(ref: String, names: [String]) -> String {
        let styleNames = names.isEmpty
            ? ["display", "visibility", "opacity", "color", "background-color", "font-size", "position"]
            : names
        let namesLiteral = "[\(styleNames.map(javaScriptStringLiteral).joined(separator: ","))]"
        return """
        (function() {
            \(stableReferencePrelude)
            const element = cocxyResolveStableRef(\(javaScriptStringLiteral(ref)));
            if (!element) { return JSON.stringify({status: 'not-found'}); }
            const computed = window.getComputedStyle(element);
            const names = \(namesLiteral);
            const styles = {};
            for (const name of names) {
                styles[name] = computed.getPropertyValue(name) || '';
            }
            return JSON.stringify({status: 'ok', styles: JSON.stringify(styles)});
        })();
        """
    }

    static func visibleScript(ref: String) -> String {
        """
        (function() {
            \(stableReferencePrelude)
            const element = cocxyResolveStableRef(\(javaScriptStringLiteral(ref)));
            if (!element) { return JSON.stringify({status: 'not-found', visible: 'false', reason: 'not-found'}); }
            const rect = element.getBoundingClientRect();
            const style = window.getComputedStyle(element);
            const visible = !!(rect.width || rect.height)
                && style.visibility !== 'hidden'
                && style.display !== 'none'
                && Number(style.opacity || 1) > 0;
            return JSON.stringify({
                status: 'ok',
                visible: visible ? 'true' : 'false',
                reason: visible ? 'visible' : 'not-visible'
            });
        })();
        """
    }

    static func enabledScript(ref: String) -> String {
        """
        (function() {
            \(stableReferencePrelude)
            const element = cocxyResolveStableRef(\(javaScriptStringLiteral(ref)));
            if (!element) { return JSON.stringify({status: 'not-found', enabled: 'false', reason: 'not-found'}); }
            const disabled = !!element.disabled || element.getAttribute('aria-disabled') === 'true';
            return JSON.stringify({
                status: 'ok',
                enabled: disabled ? 'false' : 'true',
                reason: disabled ? 'disabled' : 'enabled'
            });
        })();
        """
    }

    static func checkedScript(ref: String) -> String {
        """
        (function() {
            \(stableReferencePrelude)
            const element = cocxyResolveStableRef(\(javaScriptStringLiteral(ref)));
            if (!element) { return JSON.stringify({status: 'not-found', checked: 'false'}); }
            if (!('checked' in element)) { return JSON.stringify({status: 'not-checkable', checked: 'false'}); }
            return JSON.stringify({status: 'ok', checked: element.checked ? 'true' : 'false'});
        })();
        """
    }

    static func findRoleScript(role: String, name: String?) -> String {
        let escapedRole = javaScriptStringLiteral(role)
        let escapedName = name.map { javaScriptStringLiteral($0) } ?? "null"
        return """
        (function() {
            \(findPrelude)
            const wantedRole = \(escapedRole);
            const wantedName = \(escapedName);
            const nodes = Array.from(document.querySelectorAll('body *')).filter(visible);
            const results = nodes.filter((element) => {
                const roleMatches = normalized(roleFor(element)) === normalized(wantedRole);
                const nameMatches = wantedName === null || normalized(textFor(element)).includes(normalized(wantedName));
                return roleMatches && nameMatches;
            }).slice(0, 50);
            return JSON.stringify(results.map(resultFor));
        })();
        """
    }

    static func findTextScript(text: String) -> String {
        let escapedText = javaScriptStringLiteral(text)
        return """
        (function() {
            \(findPrelude)
            const query = \(escapedText);
            const nodes = Array.from(document.querySelectorAll('body *')).filter(visible);
            const results = nodes.filter((element) => normalized(textFor(element)).includes(normalized(query))).slice(0, 50);
            return JSON.stringify(results.map(resultFor));
        })();
        """
    }

    static func findAttributeTextScript(attribute: String, text: String) -> String {
        let escapedText = javaScriptStringLiteral(text)
        if attribute == "label" {
            return """
            (function() {
                \(findPrelude)
                const query = \(escapedText);
                const labels = Array.from(document.querySelectorAll('label')).filter(visible);
                const controls = labels.map((label) => {
                    if (!normalized(textFor(label)).includes(normalized(query))) { return null; }
                    return label.control || document.getElementById(label.getAttribute('for')) || label;
                }).filter(Boolean);
                return JSON.stringify(controls.slice(0, 50).map(resultFor));
            })();
            """
        }
        let escapedAttribute = javaScriptStringLiteral(attribute)
        return """
        (function() {
            \(findPrelude)
            const query = \(escapedText);
            const attr = \(escapedAttribute);
            const nodes = Array.from(document.querySelectorAll('[' + attr + ']')).filter(visible);
            const results = nodes.filter((element) => normalized(element.getAttribute(attr)).includes(normalized(query))).slice(0, 50);
            return JSON.stringify(results.map(resultFor));
        })();
        """
    }

    static func findTestIDScript(id: String) -> String {
        let escapedID = javaScriptStringLiteral(id)
        return """
        (function() {
            \(findPrelude)
            const query = \(escapedID);
            const nodes = Array.from(document.querySelectorAll('[data-testid], [data-test-id], [data-cy]')).filter(visible);
            const results = nodes.filter((element) => {
                return normalized(element.getAttribute('data-testid')) === normalized(query)
                    || normalized(element.getAttribute('data-test-id')) === normalized(query)
                    || normalized(element.getAttribute('data-cy')) === normalized(query);
            }).slice(0, 50);
            return JSON.stringify(results.map(resultFor));
        })();
        """
    }

    static func findSelectorScript(
        selector: String,
        mode: BrowserAutomationFindSelectorMode,
        index: Int?
    ) -> String {
        let escapedSelector = javaScriptStringLiteral(selector)
        let modeLiteral: String
        switch mode {
        case .first:
            modeLiteral = "first"
        case .last:
            modeLiteral = "last"
        case .nth:
            modeLiteral = "nth"
        }
        let nthIndex = index ?? 0
        return """
        (function() {
            \(findPrelude)
            const selector = \(escapedSelector);
            const mode = '\(modeLiteral)';
            const nthIndex = \(nthIndex);
            try {
                const nodes = Array.from(document.querySelectorAll(selector)).filter(visible);
                let element = null;
                if (mode === 'first') {
                    element = nodes[0] || null;
                } else if (mode === 'last') {
                    element = nodes[nodes.length - 1] || null;
                } else {
                    element = nodes[nthIndex] || null;
                }
                return JSON.stringify(element ? [resultFor(element, 0)] : []);
            } catch (error) {
                return JSON.stringify([]);
            }
        })();
        """
    }

    static func waitScript(selector: String) -> String {
        let escapedSelector = javaScriptStringLiteral(selector)
        return """
        (function() {
            try {
                return document.querySelector(\(escapedSelector)) ? 'found' : 'missing';
            } catch (error) {
                return 'missing';
            }
        })();
        """
    }

    static func setCookieScript(
        name: String,
        value: String,
        path: String?,
        domain: String?,
        secure: Bool,
        sameSite: String?,
        maxAge: Int?
    ) -> String {
        let cookie = cookieAssignment(
            name: name,
            value: value,
            path: path,
            domain: domain,
            secure: secure,
            sameSite: sameSite,
            maxAge: maxAge
        )
        return """
        (function() {
            document.cookie = \(javaScriptStringLiteral(cookie));
            return 'ok';
        })();
        """
    }

    static func deleteCookieScript(name: String, path: String?, domain: String?) -> String {
        let cookie = cookieAssignment(
            name: name,
            value: "",
            path: path,
            domain: domain,
            secure: false,
            sameSite: nil,
            maxAge: 0
        )
        return """
        (function() {
            document.cookie = \(javaScriptStringLiteral(cookie));
            return 'ok';
        })();
        """
    }

    static func cookiePairs(from cookieString: String) -> [(name: String, value: String)] {
        cookieString
            .split(separator: ";", omittingEmptySubsequences: true)
            .compactMap { rawPair -> (name: String, value: String)? in
                let pair = rawPair.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separator = pair.firstIndex(of: "=") else { return nil }
                let name = String(pair[..<separator])
                let value = String(pair[pair.index(after: separator)...])
                guard !name.isEmpty else { return nil }
                return (name, value)
            }
    }

    static var networkScript: String {
        """
        (function() {
            const entries = performance.getEntriesByType('resource').map(function(entry) {
                const initiatorType = entry.initiatorType || 'other';
                return {
                    url: entry.name || '',
                    method: (initiatorType === 'fetch' || initiatorType === 'xmlhttprequest') ? 'XHR' : 'GET',
                    initiatorType: initiatorType,
                    duration: entry.duration || 0,
                    transferSize: entry.transferSize || 0
                };
            });
            return JSON.stringify(entries);
        })();
        """
    }

    static func contextPackScript(targetRef: String?, around: Int, networkTail: Int) -> String {
        let targetLiteral = targetRef.map(javaScriptStringLiteral) ?? "null"
        let boundedAround = min(max(around, 0), 20)
        let boundedNetworkTail = min(max(networkTail, 0), 100)
        return """
        (function() {
            \(stableReferencePrelude)
            const targetRef = \(targetLiteral);
            const around = \(boundedAround);
            const networkTail = \(boundedNetworkTail);
            const visible = (element) => {
                if (!element || typeof element.getBoundingClientRect !== 'function') { return false; }
                const rect = element.getBoundingClientRect();
                const style = window.getComputedStyle(element);
                return (rect.width > 0 || rect.height > 0)
                    && style.visibility !== 'hidden'
                    && style.display !== 'none'
                    && Number(style.opacity || 1) > 0;
            };
            const textFor = (element) => {
                if (!element || typeof element.getAttribute !== 'function') { return ''; }
                if (isSensitiveValueElement(element)) { return '[redacted]'; }
                return String(
                    element.getAttribute('aria-label') ||
                    element.getAttribute('title') ||
                    element.getAttribute('alt') ||
                    element.getAttribute('placeholder') ||
                    element.innerText ||
                    element.textContent ||
                    ''
                ).trim().replace(/\\s+/g, ' ').slice(0, 240);
            };
            const sensitiveAttributePattern = /(password|passwd|pwd|token|secret|apikey|api[-_]?key|authorization|auth|session|cookie|credential|bearer)/i;
            const attributeFingerprint = (element) => {
                if (!element || typeof element.getAttribute !== 'function') { return ''; }
                return [
                    element.getAttribute('type') || '',
                    element.getAttribute('name') || '',
                    element.getAttribute('id') || '',
                    element.getAttribute('autocomplete') || '',
                    element.getAttribute('aria-label') || '',
                    element.getAttribute('title') || ''
                ].join(' ');
            };
            const isSensitiveValueElement = (element) => {
                if (!element || typeof element.getAttribute !== 'function') { return false; }
                const type = String(element.getAttribute('type') || '').toLowerCase();
                return type === 'password' || sensitiveAttributePattern.test(attributeFingerprint(element));
            };
            const valueFor = (element) => {
                if (!element || !('value' in element)) { return ''; }
                if (isSensitiveValueElement(element)) { return '[redacted]'; }
                return String(element.value || '').slice(0, 160);
            };
            const sanitizeHTML = (element) => {
                if (!element || typeof element.cloneNode !== 'function') { return ''; }
                const clone = element.cloneNode(true);
                const sanitizeNode = (node) => {
                    if (!node || node.nodeType !== 1) { return; }
                    const tag = node.tagName ? node.tagName.toLowerCase() : '';
                    const formControl = tag === 'input' || tag === 'textarea' || tag === 'select' || tag === 'option';
                    for (const attribute of Array.from(node.attributes || [])) {
                        const name = String(attribute.name || '').toLowerCase();
                        if (sensitiveAttributePattern.test(name)) {
                            node.setAttribute(attribute.name, '[redacted]');
                        } else if (formControl && name === 'value') {
                            node.setAttribute(attribute.name, '[redacted]');
                        }
                    }
                    if (tag === 'textarea') {
                        node.textContent = '[redacted]';
                    }
                    Array.from(node.children || []).forEach(sanitizeNode);
                };
                sanitizeNode(clone);
                return String(clone.outerHTML || '').replace(/\\s+/g, ' ').slice(0, 800);
            };
            const nodeSummary = (element, index) => {
                if (!element || typeof element.getBoundingClientRect !== 'function') {
                    return {present: 'false'};
                }
                const rect = element.getBoundingClientRect();
                return {
                    present: 'true',
                    ref: cocxyEnsureStableRef(element, index || 0),
                    tag: element.tagName ? element.tagName.toLowerCase() : '',
                    id: element.id || '',
                    role: element.getAttribute('role') || (element.tagName ? element.tagName.toLowerCase() : ''),
                    name: textFor(element),
                    value: valueFor(element),
                    checked: ('checked' in element) ? (element.checked ? 'true' : 'false') : '',
                    disabled: (element.disabled || element.getAttribute('aria-disabled') === 'true') ? 'true' : 'false',
                    visible: visible(element) ? 'true' : 'false',
                    rect: {
                        x: String(Math.round(rect.x)),
                        y: String(Math.round(rect.y)),
                        width: String(Math.round(rect.width)),
                        height: String(Math.round(rect.height))
                    },
                    html: sanitizeHTML(element)
                };
            };
            const addUnique = (list, seen, element) => {
                if (!element || element.nodeType !== 1 || seen.has(element)) { return; }
                seen.add(element);
                list.push(element);
            };
            const focusedElement = document.activeElement && document.activeElement !== document.body
                && document.activeElement !== document.documentElement ? document.activeElement : null;
            let targetElement = targetRef ? cocxyResolveStableRef(targetRef) : focusedElement;
            if (!targetElement) {
                targetElement = document.querySelector('[autofocus], input, textarea, select, button, a[href], [role], [tabindex]');
            }
            const domNodes = [];
            const seen = new Set();
            if (targetElement) {
                const ancestors = [];
                let current = targetElement;
                while (current && current.nodeType === 1 && current !== document.documentElement && ancestors.length < 6) {
                    ancestors.unshift(current);
                    current = current.parentElement;
                }
                ancestors.forEach((element) => addUnique(domNodes, seen, element));
                const parent = targetElement.parentElement;
                if (parent) {
                    const siblings = Array.from(parent.children);
                    const targetIndex = siblings.indexOf(targetElement);
                    const start = Math.max(0, targetIndex - around);
                    const end = Math.min(siblings.length, targetIndex + around + 1);
                    siblings.slice(start, end).forEach((element) => addUnique(domNodes, seen, element));
                }
                Array.from(targetElement.children).slice(0, Math.max(around, 1) * 2).forEach((element) => {
                    addUnique(domNodes, seen, element);
                });
            }
            if (domNodes.length === 0) {
                Array.from(document.querySelectorAll('a[href], button, input, textarea, select, [role], [tabindex]'))
                    .filter(visible)
                    .slice(0, 25)
                    .forEach((element) => addUnique(domNodes, seen, element));
            }
            const favicon = document.querySelector('link[rel~="icon"], link[rel="shortcut icon"]');
            const resources = performance.getEntriesByType('resource');
            const networkEntries = resources.slice(networkTail > 0 ? -networkTail : resources.length).map((entry) => ({
                url: String(entry.name || '').slice(0, 512),
                initiatorType: String(entry.initiatorType || 'other'),
                duration: String(Math.round(entry.duration || 0)),
                transferSize: String(Math.round(entry.transferSize || 0))
            }));
            return JSON.stringify({
                status: 'ok',
                capturedAt: new Date().toISOString(),
                page: {
                    url: String(window.location.href || ''),
                    origin: String(window.location.origin || ''),
                    title: String(document.title || ''),
                    readyState: String(document.readyState || ''),
                    favicon: favicon ? String(favicon.href || favicon.getAttribute('href') || '') : ''
                },
                visual: {
                    viewportWidth: String(window.innerWidth || 0),
                    viewportHeight: String(window.innerHeight || 0),
                    scrollX: String(Math.round(window.scrollX || 0)),
                    scrollY: String(Math.round(window.scrollY || 0)),
                    devicePixelRatio: String(window.devicePixelRatio || 1)
                },
                focused: nodeSummary(focusedElement, 0),
                target: nodeSummary(targetElement, 0),
                dom: domNodes.slice(0, 60).map(nodeSummary),
                network: {
                    resourceCount: String(resources.length),
                    entries: networkEntries
                }
            });
        })();
        """
    }

    static var framesScript: String {
        """
        (function() {
            const frames = [{
                path: 'main',
                name: window.name || '',
                url: window.location.href || '',
                title: document.title || '',
                isMain: 'true',
                sameOrigin: 'true'
            }];
            const iframes = Array.from(document.querySelectorAll('iframe'));
            for (let index = 0; index < iframes.length && index < 100; index++) {
                const iframe = iframes[index];
                const frame = window.frames[index];
                let url = iframe.getAttribute('src') || '';
                let title = '';
                let name = iframe.getAttribute('name') || '';
                let sameOrigin = 'false';
                try {
                    if (frame) {
                        name = name || frame.name || '';
                        url = frame.location && frame.location.href ? frame.location.href : url;
                        title = frame.document && frame.document.title ? frame.document.title : '';
                        sameOrigin = 'true';
                    }
                } catch (_) {}
                frames.push({
                    path: String(index),
                    name: name,
                    url: url,
                    title: title,
                    isMain: 'false',
                    sameOrigin: sameOrigin
                });
            }
            return JSON.stringify(frames);
        })();
        """
    }

    static var stateSnapshotScript: String {
        """
        (function() {
            const readStorage = (storage) => {
                const entries = [];
                for (let index = 0; index < storage.length; index += 1) {
                    const key = storage.key(index);
                    if (key === null) { continue; }
                    entries.push({key: key, value: storage.getItem(key) || ''});
                }
                return entries;
            };
            const cookies = (document.cookie || '')
                .split(';')
                .map((pair) => pair.trim())
                .filter(Boolean)
                .map((pair) => {
                    const separator = pair.indexOf('=');
                    if (separator < 0) { return null; }
                    return {
                        name: pair.slice(0, separator),
                        value: pair.slice(separator + 1),
                        path: '/'
                    };
                })
                .filter(Boolean);
            return JSON.stringify({
                version: '1',
                capturedAt: new Date().toISOString(),
                url: window.location.href || '',
                origin: window.location.origin || '',
                title: document.title || '',
                cookies: cookies,
                localStorage: readStorage(window.localStorage),
                sessionStorage: readStorage(window.sessionStorage)
            });
        })();
        """
    }

    static func stateLoadScript(snapshotJSON: String) -> String {
        let snapshotLiteral = javaScriptStringLiteral(snapshotJSON)
        return """
        (function() {
            const snapshot = JSON.parse(\(snapshotLiteral));
            const expectedOrigin = String(snapshot.origin || '');
            const currentOrigin = String(window.location.origin || '');
            if (expectedOrigin && currentOrigin && expectedOrigin !== currentOrigin) {
                return JSON.stringify({
                    status: 'origin-mismatch',
                    expectedOrigin: expectedOrigin,
                    currentOrigin: currentOrigin,
                    url: String(snapshot.url || '')
                });
            }
            const safeCookiePart = (value) => String(value || '').replace(/[;\\r\\n]/g, '');
            let cookieCount = 0;
            for (const cookie of Array.isArray(snapshot.cookies) ? snapshot.cookies : []) {
                const name = safeCookiePart(cookie.name);
                if (!name) { continue; }
                let assignment = `${name}=${safeCookiePart(cookie.value)}`;
                assignment += `; Path=${safeCookiePart(cookie.path || '/') || '/'}`;
                if (cookie.domain) { assignment += `; Domain=${safeCookiePart(cookie.domain)}`; }
                if (cookie.maxAge !== undefined && cookie.maxAge !== null) {
                    assignment += `; Max-Age=${Number(cookie.maxAge) || 0}`;
                }
                if (cookie.secure === true || cookie.secure === 'true') { assignment += '; Secure'; }
                if (cookie.sameSite) { assignment += `; SameSite=${safeCookiePart(cookie.sameSite)}`; }
                document.cookie = assignment;
                cookieCount += 1;
            }
            let localStorageCount = 0;
            for (const entry of Array.isArray(snapshot.localStorage) ? snapshot.localStorage : []) {
                if (entry && entry.key !== undefined && entry.key !== null) {
                    window.localStorage.setItem(String(entry.key), String(entry.value ?? ''));
                    localStorageCount += 1;
                }
            }
            let sessionStorageCount = 0;
            for (const entry of Array.isArray(snapshot.sessionStorage) ? snapshot.sessionStorage : []) {
                if (entry && entry.key !== undefined && entry.key !== null) {
                    window.sessionStorage.setItem(String(entry.key), String(entry.value ?? ''));
                    sessionStorageCount += 1;
                }
            }
            return JSON.stringify({
                status: 'loaded',
                cookies: String(cookieCount),
                localStorage: String(localStorageCount),
                sessionStorage: String(sessionStorageCount),
                url: String(snapshot.url || '')
            });
        })();
        """
    }

    static func addScriptScript(source: String) -> String {
        let sourceLiteral = javaScriptStringLiteral(source)
        return """
        (function() {
            const root = document.head || document.documentElement || document.body;
            if (!root) { return JSON.stringify({status: 'missing-root', type: 'script'}); }
            const index = document.querySelectorAll('[data-cocxy-added-script]').length + 1;
            const id = `cocxy-script-${index}`;
            const element = document.createElement('script');
            element.id = id;
            element.setAttribute('data-cocxy-added-script', 'true');
            element.textContent = \(sourceLiteral);
            root.appendChild(element);
            return JSON.stringify({status: 'added', type: 'script', id: id});
        })();
        """
    }

    static func addStyleScript(css: String) -> String {
        let cssLiteral = javaScriptStringLiteral(css)
        return """
        (function() {
            const root = document.head || document.documentElement || document.body;
            if (!root) { return JSON.stringify({status: 'missing-root', type: 'style'}); }
            const index = document.querySelectorAll('[data-cocxy-added-style]').length + 1;
            const id = `cocxy-style-${index}`;
            const element = document.createElement('style');
            element.id = id;
            element.setAttribute('data-cocxy-added-style', 'true');
            element.textContent = \(cssLiteral);
            root.appendChild(element);
            return JSON.stringify({status: 'added', type: 'style', id: id});
        })();
        """
    }

    static func networkEntries(
        from jsonString: String,
        filter: String?,
        tail: Int?
    ) -> [BrowserAutomationNetworkEntry] {
        guard let data = jsonString.data(using: .utf8),
              let rawEntries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let normalizedFilter = filter?.lowercased()
        var entries = rawEntries.compactMap { raw -> BrowserAutomationNetworkEntry? in
            let url = (raw["url"] ?? raw["name"]) as? String ?? ""
            guard !url.isEmpty else { return nil }
            let method = raw["method"] as? String
                ?? (((raw["initiatorType"] as? String) == "fetch"
                    || (raw["initiatorType"] as? String) == "xmlhttprequest") ? "XHR" : "GET")
            let initiatorType = raw["initiatorType"] as? String ?? "other"
            let duration = raw["duration"] as? Double
                ?? (raw["duration"] as? Int).map(Double.init)
                ?? 0
            let transferSize = raw["transferSize"] as? Int
                ?? (raw["transferSize"] as? Double).map(Int.init)
                ?? 0
            return BrowserAutomationNetworkEntry(
                url: url,
                method: method,
                initiatorType: initiatorType,
                duration: duration,
                transferSize: transferSize
            )
        }
        if let normalizedFilter, !normalizedFilter.isEmpty {
            entries = entries.filter {
                $0.url.lowercased().contains(normalizedFilter)
                    || $0.method.lowercased().contains(normalizedFilter)
                    || $0.initiatorType.lowercased().contains(normalizedFilter)
            }
        }
        if let tail, tail > 0, entries.count > tail {
            entries = Array(entries.suffix(tail))
        }
        return entries
    }

    static func storageListScript(area: BrowserAutomationStorageArea) -> String {
        let accessor = area.accessor
        return """
        (function() {
            const storage = \(accessor);
            const entries = [];
            for (let index = 0; index < storage.length; index += 1) {
                const key = storage.key(index);
                if (key === null) { continue; }
                entries.push({key: key, value: storage.getItem(key) || ''});
            }
            return JSON.stringify(entries);
        })();
        """
    }

    static func storageGetScript(area: BrowserAutomationStorageArea, key: String) -> String {
        let accessor = area.accessor
        let escapedKey = javaScriptStringLiteral(key)
        return """
        (function() {
            const storage = \(accessor);
            const key = \(escapedKey);
            const value = storage.getItem(key);
            if (value === null) { return JSON.stringify({status: 'missing'}); }
            return JSON.stringify({status: 'ok', value: value});
        })();
        """
    }

    static func storageSetScript(area: BrowserAutomationStorageArea, key: String, value: String) -> String {
        let accessor = area.accessor
        let escapedKey = javaScriptStringLiteral(key)
        let escapedValue = javaScriptStringLiteral(value)
        return """
        (function() {
            const storage = \(accessor);
            storage.setItem(\(escapedKey), \(escapedValue));
            return 'set';
        })();
        """
    }

    static func storageDeleteScript(area: BrowserAutomationStorageArea, key: String) -> String {
        let accessor = area.accessor
        let escapedKey = javaScriptStringLiteral(key)
        return """
        (function() {
            const storage = \(accessor);
            storage.removeItem(\(escapedKey));
            return 'deleted';
        })();
        """
    }

    static func storageEntriesData(from jsonString: String, area: BrowserAutomationStorageArea) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let rawEntries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ["status": "invalid-response", "area": area.rawValue, "count": "0"]
        }
        var dataMap: [String: String] = [
            "status": "ok",
            "area": area.rawValue,
            "count": "\(rawEntries.count)"
        ]
        for (index, raw) in rawEntries.prefix(100).enumerated() {
            dataMap["key_\(index)"] = stringValue(raw["key"] ?? "")
            dataMap["value_\(index)"] = stringValue(raw["value"] ?? "")
        }
        return dataMap
    }

    static func hybridSnapshotData(from jsonString: String) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) else {
            return ["status": "captured", "snapshot": "[]"]
        }

        if let rawArray = raw as? [[String: Any]] {
            return [
                "status": "captured",
                "snapshot": compactJSONString(rawArray),
                "accessibilityCount": "\(rawArray.count)"
            ]
        }

        guard let rawObject = raw as? [String: Any] else {
            return ["status": "captured", "snapshot": "[]"]
        }

        let accessibility = rawObject["accessibility"] as? [[String: Any]] ?? []
        let dom = rawObject["dom"] as? [[String: Any]] ?? []
        let visual = rawObject["visual"] as? [String: Any] ?? [:]
        let page = rawObject["page"] as? [String: Any] ?? [:]
        let network = rawObject["network"] as? [String: Any] ?? [:]

        return [
            "status": "captured",
            "snapshot": compactJSONString(accessibility),
            "dom": compactJSONString(dom),
            "visual": compactJSONString(visual),
            "page": compactJSONString(page),
            "network": compactJSONString(network),
            "accessibilityCount": "\(accessibility.count)",
            "domCount": "\(dom.count)"
        ]
    }

    static func contextPackData(from jsonString: String) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["status": "invalid-response"]
        }

        let page = raw["page"] as? [String: Any] ?? [:]
        let visual = raw["visual"] as? [String: Any] ?? [:]
        let focused = raw["focused"] as? [String: Any] ?? [:]
        let target = raw["target"] as? [String: Any] ?? [:]
        let dom = raw["dom"] as? [[String: Any]] ?? []
        let network = raw["network"] as? [String: Any] ?? [:]

        var dataMap: [String: String] = [
            "status": stringValue(raw["status"] ?? "ok"),
            "capturedAt": stringValue(raw["capturedAt"] ?? ""),
            "page": compactJSONString(page),
            "visual": compactJSONString(visual),
            "focused": compactJSONString(focused),
            "target": compactJSONString(target),
            "dom": compactJSONString(dom),
            "network": compactJSONString(network),
            "domCount": "\(dom.count)"
        ]
        dataMap["url"] = stringValue(page["url"] ?? "")
        dataMap["title"] = stringValue(page["title"] ?? "")
        dataMap["favicon"] = stringValue(page["favicon"] ?? "")
        dataMap["targetRef"] = stringValue(target["ref"] ?? "")
        dataMap["focusedRef"] = stringValue(focused["ref"] ?? "")
        return dataMap
    }

    static func numberString(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.3f", value)
    }

    static var snapshotScript: String {
        """
        (function() {
            \(stableReferencePrelude)
            const selector = [
                'a[href]',
                'button',
                'input',
                'textarea',
                'select',
                '[role]',
                '[tabindex]',
                '[contenteditable="true"]'
            ].join(',');
            const visible = (element) => {
                const rect = element.getBoundingClientRect();
                const style = window.getComputedStyle(element);
                return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
            };
            const textFor = (element) => {
                return (
                    element.getAttribute('aria-label') ||
                    element.getAttribute('title') ||
                    element.innerText ||
                    element.value ||
                    element.getAttribute('placeholder') ||
                    ''
                ).trim().slice(0, 160);
            };
            const nodes = Array.from(document.querySelectorAll(selector)).filter(visible).slice(0, 500);
            const accessibility = nodes.map((element, index) => {
                const cocxyRef = cocxyEnsureStableRef(element, index);
                const rect = element.getBoundingClientRect();
                return {
                    ref: cocxyRef,
                    role: element.getAttribute('role') || element.tagName.toLowerCase(),
                    name: textFor(element),
                    x: Math.round(rect.x),
                    y: Math.round(rect.y),
                    width: Math.round(rect.width),
                    height: Math.round(rect.height)
                };
            });
            const dom = Array.from(document.body ? document.body.querySelectorAll('*') : [])
                .slice(0, 300)
                .map((element, index) => {
                    const rect = element.getBoundingClientRect();
                    return {
                        index: String(index),
                        ref: element.getAttribute('data-cocxy-ref') || '',
                        tag: element.tagName.toLowerCase(),
                        id: element.id || '',
                        role: element.getAttribute('role') || '',
                        name: textFor(element),
                        children: String(element.children.length),
                        visible: visible(element) ? 'true' : 'false',
                        x: String(Math.round(rect.x)),
                        y: String(Math.round(rect.y)),
                        width: String(Math.round(rect.width)),
                        height: String(Math.round(rect.height))
                    };
                });
            const resources = performance.getEntriesByType('resource');
            const resourceTail = resources.slice(-20).map((entry) => ({
                url: String(entry.name || '').slice(0, 512),
                initiatorType: String(entry.initiatorType || ''),
                duration: String(Math.round(entry.duration || 0)),
                transferSize: String(Math.round(entry.transferSize || 0))
            }));
            return JSON.stringify({
                accessibility: accessibility,
                dom: dom,
                visual: {
                    viewportWidth: String(window.innerWidth || 0),
                    viewportHeight: String(window.innerHeight || 0),
                    scrollX: String(Math.round(window.scrollX || 0)),
                    scrollY: String(Math.round(window.scrollY || 0)),
                    devicePixelRatio: String(window.devicePixelRatio || 1)
                },
                page: {
                    url: String(window.location.href || ''),
                    title: String(document.title || ''),
                    readyState: String(document.readyState || ''),
                    activeRef: document.activeElement ? (document.activeElement.getAttribute('data-cocxy-ref') || document.activeElement.id || '') : ''
                },
                network: {
                    resourceCount: String(resources.length),
                    resources: resourceTail
                }
            });
        })();
        """
    }

    private static func actionableElementScript(
        ref: String,
        timeoutMilliseconds: Int,
        actionBody: () -> String
    ) -> String {
        """
        (async function() {
            const ref = \(javaScriptStringLiteral(ref));
            const selector = '[data-cocxy-ref="\(ref)"]';
            const timeoutMs = \(timeoutMilliseconds);
            const started = Date.now();
            let attempts = 0;
            let lastReason = 'not-found';
            let actionElement = null;
            let beforeState = null;
            \(stableReferencePrelude)

            const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
            const elapsed = () => String(Math.max(0, Date.now() - started));
            const textFor = (element) => {
                if (!element) { return ''; }
                return String(
                    element.getAttribute('aria-label') ||
                    element.getAttribute('title') ||
                    element.innerText ||
                    element.textContent ||
                    ''
                ).trim().replace(/\\s+/g, ' ').slice(0, 160);
            };
            const valueFor = (element) => {
                if (!element || !('value' in element)) { return ''; }
                const type = String(element.getAttribute('type') || '').toLowerCase();
                if (type === 'password') { return '[redacted]'; }
                return String(element.value || '').slice(0, 160);
            };
            const refFor = (element) => {
                if (!element) { return ''; }
                return element.getAttribute('data-cocxy-ref') ||
                    element.getAttribute('data-testid') ||
                    element.id ||
                    cocxyStableRefForElement(element) ||
                    '';
            };
            const targetSnapshot = (element) => {
                if (!element) {
                    return {present: 'false'};
                }
                const rect = element.getBoundingClientRect();
                const style = window.getComputedStyle(element);
                return {
                    present: 'true',
                    ref: refFor(element),
                    tag: element.tagName.toLowerCase(),
                    role: element.getAttribute('role') || element.tagName.toLowerCase(),
                    name: textFor(element),
                    value: valueFor(element),
                    checked: ('checked' in element) ? (element.checked ? 'true' : 'false') : '',
                    disabled: (element.disabled || element.getAttribute('aria-disabled') === 'true') ? 'true' : 'false',
                    display: style.display || '',
                    visibility: style.visibility || '',
                    rect: {
                        x: String(Math.round(rect.x)),
                        y: String(Math.round(rect.y)),
                        width: String(Math.round(rect.width)),
                        height: String(Math.round(rect.height))
                    }
                };
            };
            const summarizeState = (target) => ({
                url: String(window.location.href || ''),
                title: String(document.title || ''),
                activeRef: refFor(document.activeElement),
                focusedTag: document.activeElement ? document.activeElement.tagName.toLowerCase() : '',
                target: targetSnapshot(target),
                counts: {
                    elements: String(document.querySelectorAll('body *').length),
                    inputs: String(document.querySelectorAll('input,textarea,select,[contenteditable="true"]').length),
                    buttons: String(document.querySelectorAll('button,[role="button"],input[type="button"],input[type="submit"]').length),
                    invalid: String(document.querySelectorAll('[aria-invalid="true"],input:invalid,textarea:invalid,select:invalid').length)
                }
            });
            const diffStates = (before, after) => {
                const changes = [];
                const compare = (path, fromValue, toValue) => {
                    if (String(fromValue ?? '') !== String(toValue ?? '')) {
                        changes.push({path: path, before: String(fromValue ?? ''), after: String(toValue ?? '')});
                    }
                };
                compare('url', before?.url, after?.url);
                compare('title', before?.title, after?.title);
                compare('activeRef', before?.activeRef, after?.activeRef);
                compare('target.name', before?.target?.name, after?.target?.name);
                compare('target.value', before?.target?.value, after?.target?.value);
                compare('target.checked', before?.target?.checked, after?.target?.checked);
                compare('target.disabled', before?.target?.disabled, after?.target?.disabled);
                compare('target.rect.width', before?.target?.rect?.width, after?.target?.rect?.width);
                compare('target.rect.height', before?.target?.rect?.height, after?.target?.rect?.height);
                compare('counts.elements', before?.counts?.elements, after?.counts?.elements);
                compare('counts.inputs', before?.counts?.inputs, after?.counts?.inputs);
                compare('counts.buttons', before?.counts?.buttons, after?.counts?.buttons);
                compare('counts.invalid', before?.counts?.invalid, after?.counts?.invalid);
                return {
                    changed: changes.length > 0 ? 'true' : 'false',
                    count: String(changes.length),
                    changes: changes.slice(0, 20)
                };
            };
            const explanationFor = (status, actionable, reason, diff) => {
                if (!actionable) {
                    return `Action ${status} on ${ref} failed before execution: ${reason}.`;
                }
                const count = Number(diff?.count || '0');
                if (count > 0) {
                    const first = diff.changes?.[0]?.path || 'page';
                    return `Action ${status} on ${ref} completed with ${count} observable change(s); first change: ${first}.`;
                }
                return `Action ${status} on ${ref} completed; no observable DOM summary change.`;
            };
            const payload = (status, actionable, reason, afterState, diff, extra) => Object.assign({
                status: status,
                ref: ref,
                actionable: actionable ? 'true' : 'false',
                reason: reason,
                attempts: String(attempts),
                elapsedMs: elapsed(),
                before: JSON.stringify(beforeState || summarizeState(null)),
                after: JSON.stringify(afterState),
                diff: JSON.stringify(diff),
                explanation: explanationFor(status, actionable, reason, diff)
            }, extra || {});
            const finish = async (status, extra) => {
                await sleep(50);
                const afterState = summarizeState(actionElement);
                const diff = diffStates(beforeState || summarizeState(null), afterState);
                return JSON.stringify(payload(status, true, 'ok', afterState, diff, extra));
            };
            const fail = async (status, reason, extra) => {
                const afterState = summarizeState(actionElement);
                const diff = diffStates(beforeState || summarizeState(null), afterState);
                return JSON.stringify(payload(status, false, reason, afterState, diff, extra));
            };

            function waitForCocxyActionable(element) {
                if (document.readyState === 'loading') { return 'document-loading'; }
                if (!element || !element.isConnected) { return 'not-found'; }
                try {
                    element.scrollIntoView({block: 'center', inline: 'center'});
                } catch (_) {}
                const rect = element.getBoundingClientRect();
                const style = window.getComputedStyle(element);
                if ((!rect.width && !rect.height) || style.display === 'none' || style.visibility === 'hidden') {
                    return 'not-visible';
                }
                if (Number(style.opacity || 1) <= 0) { return 'not-visible'; }
                if (style.pointerEvents === 'none') { return 'pointer-events-none'; }
                if (element.disabled || element.getAttribute('aria-disabled') === 'true') { return 'disabled'; }
                return 'ok';
            }

            async function waitForElement() {
                const deadline = Date.now() + timeoutMs;
                const delay = Math.min(100, Math.max(25, Math.floor(timeoutMs / 20)));
                while (Date.now() <= deadline) {
                    attempts += 1;
                    let element = document.querySelector(selector);
                    if (!element) {
                        element = cocxyResolveStableRef(ref);
                    }
                    lastReason = waitForCocxyActionable(element);
                    if (lastReason === 'ok') { return element; }
                    await sleep(delay);
                }
                return null;
            }

            actionElement = await waitForElement();
            const element = actionElement;
            if (!element) { return fail('timeout', lastReason); }
            beforeState = summarizeState(element);
            \(actionBody())
        })();
        """
    }

    private static func pageActionScript(
        fallbackRef: String,
        targetExpression: String,
        actionBody: () -> String
    ) -> String {
        """
        (function() {
            const fallbackRef = \(javaScriptStringLiteral(fallbackRef));
            const started = Date.now();
            const attempts = 1;
            const actionElement = \(targetExpression);
            \(stableReferencePrelude)

            const elapsed = () => String(Math.max(0, Date.now() - started));
            const textFor = (element) => {
                if (!element) { return ''; }
                return String(
                    element.getAttribute('aria-label') ||
                    element.getAttribute('title') ||
                    element.innerText ||
                    element.textContent ||
                    ''
                ).trim().replace(/\\s+/g, ' ').slice(0, 160);
            };
            const valueFor = (element) => {
                if (!element || !('value' in element)) { return ''; }
                const type = String(element.getAttribute('type') || '').toLowerCase();
                if (type === 'password') { return '[redacted]'; }
                return String(element.value || '').slice(0, 160);
            };
            const refFor = (element) => {
                if (!element || typeof element.getAttribute !== 'function') { return ''; }
                return element.getAttribute('data-cocxy-ref') ||
                    element.getAttribute('data-testid') ||
                    element.id ||
                    cocxyStableRefForElement(element) ||
                    '';
            };
            const actionRef = () => refFor(actionElement) || fallbackRef;
            const targetSnapshot = (element) => {
                if (!element || typeof element.getBoundingClientRect !== 'function') {
                    return {present: 'false'};
                }
                const rect = element.getBoundingClientRect();
                const style = window.getComputedStyle(element);
                return {
                    present: 'true',
                    ref: refFor(element),
                    tag: element.tagName ? element.tagName.toLowerCase() : '',
                    role: element.getAttribute('role') || (element.tagName ? element.tagName.toLowerCase() : ''),
                    name: textFor(element),
                    value: valueFor(element),
                    checked: ('checked' in element) ? (element.checked ? 'true' : 'false') : '',
                    disabled: (element.disabled || element.getAttribute('aria-disabled') === 'true') ? 'true' : 'false',
                    display: style.display || '',
                    visibility: style.visibility || '',
                    rect: {
                        x: String(Math.round(rect.x)),
                        y: String(Math.round(rect.y)),
                        width: String(Math.round(rect.width)),
                        height: String(Math.round(rect.height))
                    }
                };
            };
            const summarizeState = (target) => ({
                url: String(window.location.href || ''),
                title: String(document.title || ''),
                activeRef: refFor(document.activeElement),
                focusedTag: document.activeElement ? document.activeElement.tagName.toLowerCase() : '',
                target: targetSnapshot(target),
                counts: {
                    elements: String(document.querySelectorAll('body *').length),
                    inputs: String(document.querySelectorAll('input,textarea,select,[contenteditable="true"]').length),
                    buttons: String(document.querySelectorAll('button,[role="button"],input[type="button"],input[type="submit"]').length),
                    invalid: String(document.querySelectorAll('[aria-invalid="true"],input:invalid,textarea:invalid,select:invalid').length)
                },
                scroll: {
                    x: String(Math.round(window.scrollX || 0)),
                    y: String(Math.round(window.scrollY || 0))
                }
            });
            const diffStates = (before, after) => {
                const changes = [];
                const compare = (path, fromValue, toValue) => {
                    if (String(fromValue ?? '') !== String(toValue ?? '')) {
                        changes.push({path: path, before: String(fromValue ?? ''), after: String(toValue ?? '')});
                    }
                };
                compare('url', before?.url, after?.url);
                compare('title', before?.title, after?.title);
                compare('activeRef', before?.activeRef, after?.activeRef);
                compare('target.name', before?.target?.name, after?.target?.name);
                compare('target.value', before?.target?.value, after?.target?.value);
                compare('target.checked', before?.target?.checked, after?.target?.checked);
                compare('target.disabled', before?.target?.disabled, after?.target?.disabled);
                compare('target.rect.width', before?.target?.rect?.width, after?.target?.rect?.width);
                compare('target.rect.height', before?.target?.rect?.height, after?.target?.rect?.height);
                compare('scroll.x', before?.scroll?.x, after?.scroll?.x);
                compare('scroll.y', before?.scroll?.y, after?.scroll?.y);
                compare('counts.elements', before?.counts?.elements, after?.counts?.elements);
                compare('counts.inputs', before?.counts?.inputs, after?.counts?.inputs);
                compare('counts.buttons', before?.counts?.buttons, after?.counts?.buttons);
                compare('counts.invalid', before?.counts?.invalid, after?.counts?.invalid);
                return {
                    changed: changes.length > 0 ? 'true' : 'false',
                    count: String(changes.length),
                    changes: changes.slice(0, 20)
                };
            };
            const explanationFor = (status, actionable, reason, diff) => {
                if (!actionable) {
                    return `Action ${status} on ${actionRef()} failed before execution: ${reason}.`;
                }
                const count = Number(diff?.count || '0');
                if (count > 0) {
                    const first = diff.changes?.[0]?.path || 'page';
                    return `Action ${status} on ${actionRef()} completed with ${count} observable change(s); first change: ${first}.`;
                }
                return `Action ${status} on ${actionRef()} completed; no observable DOM summary change.`;
            };
            const beforeState = summarizeState(actionElement);
            const payload = (status, actionable, reason, afterState, diff, extra) => Object.assign({
                status: status,
                ref: actionRef(),
                actionable: actionable ? 'true' : 'false',
                reason: reason,
                attempts: String(attempts),
                elapsedMs: elapsed(),
                before: JSON.stringify(beforeState),
                after: JSON.stringify(afterState),
                diff: JSON.stringify(diff),
                explanation: explanationFor(status, actionable, reason, diff)
            }, extra || {});
            const finish = (status, extra) => {
                const afterState = summarizeState(actionElement);
                const diff = diffStates(beforeState, afterState);
                return JSON.stringify(payload(status, true, 'ok', afterState, diff, extra));
            };
            const fail = (status, reason, extra) => {
                const afterState = summarizeState(actionElement);
                const diff = diffStates(beforeState, afterState);
                return JSON.stringify(payload(status, false, reason, afterState, diff, extra));
            };
            const element = actionElement;
            \(actionBody())
        })();
        """
    }

    private static var findPrelude: String {
        """
        \(stableReferencePrelude)
        const visible = (element) => {
            const rect = element.getBoundingClientRect();
            const style = window.getComputedStyle(element);
            return rect.width > 0 && rect.height > 0
                && style.visibility !== 'hidden'
                && style.display !== 'none';
        };
        const textFor = (element) => {
            return (
                element.getAttribute('aria-label') ||
                element.getAttribute('title') ||
                element.innerText ||
                element.value ||
                element.getAttribute('placeholder') ||
                element.getAttribute('alt') ||
                ''
            ).trim().slice(0, 160);
        };
        const roleFor = (element) => {
            return (element.getAttribute('role') || element.tagName.toLowerCase()).trim();
        };
        const ensureRef = (element, index) => {
            return cocxyEnsureStableRef(element, index);
        };
        const resultFor = (element, index) => ({
            ref: ensureRef(element, index),
            role: roleFor(element),
            name: textFor(element)
        });
        const normalized = (value) => String(value || '').trim().toLowerCase();
        """
    }

    private static var stableReferencePrelude: String {
        """
        const cocxyHash = (value) => {
            let hash = 2166136261;
            const text = String(value || '');
            for (let index = 0; index < text.length; index += 1) {
                hash ^= text.charCodeAt(index);
                hash = Math.imul(hash, 16777619);
            }
            return (hash >>> 0).toString(16);
        };
        const cocxySafePart = (value) => {
            const safe = String(value || '')
                .trim()
                .toLowerCase()
                .replace(/[^a-z0-9_-]+/g, '-')
                .replace(/^-+|-+$/g, '')
                .slice(0, 48);
            return safe || cocxyHash(value);
        };
        const cocxyElementPath = (element) => {
            const parts = [];
            let current = element;
            while (current && current.nodeType === 1 && current !== document.body && parts.length < 8) {
                const tag = current.tagName ? current.tagName.toLowerCase() : 'node';
                const parent = current.parentElement;
                const siblings = parent ? Array.from(parent.children).filter((candidate) => candidate.tagName === current.tagName) : [];
                const ordinal = siblings.indexOf(current) + 1;
                parts.unshift(`${tag}:${Math.max(ordinal, 1)}`);
                current = parent;
            }
            return parts.join('/');
        };
        const cocxyAccessibleNameForRef = (element) => {
            if (!element || typeof element.getAttribute !== 'function') { return ''; }
            const role = (element.getAttribute('role') || element.tagName || '').toLowerCase();
            const explicit = element.getAttribute('aria-label') ||
                element.getAttribute('title') ||
                element.getAttribute('alt') ||
                element.getAttribute('placeholder') ||
                '';
            if (explicit) { return String(explicit).trim().replace(/\\s+/g, ' ').slice(0, 160); }
            if (['a', 'button', 'label'].includes((element.tagName || '').toLowerCase()) ||
                ['button', 'link', 'menuitem', 'tab', 'checkbox', 'radio'].includes(role)) {
                return String(element.innerText || element.textContent || '')
                    .trim()
                    .replace(/\\s+/g, ' ')
                    .slice(0, 160);
            }
            return '';
        };
        const cocxyStableRefBase = (element) => {
            if (!element || typeof element.getAttribute !== 'function') { return 'missing'; }
            const id = element.id || '';
            if (id) { return `id-${cocxySafePart(id)}`.slice(0, 64); }
            const testID = element.getAttribute('data-testid') ||
                element.getAttribute('data-test-id') ||
                element.getAttribute('data-cy') ||
                '';
            if (testID) { return `test-${cocxySafePart(testID)}`.slice(0, 64); }
            const role = (element.getAttribute('role') || element.tagName || '').toLowerCase();
            const name = cocxyAccessibleNameForRef(element);
            if (name) { return `name-${cocxyHash(`${role}:${name}`)}`.slice(0, 64); }
            return `path-${cocxyHash(cocxyElementPath(element))}`.slice(0, 64);
        };
        const cocxyStableRefForElement = (element) => {
            if (!element || typeof element.getAttribute !== 'function') { return ''; }
            const base = cocxyStableRefBase(element);
            const candidates = Array.from(document.body ? document.body.querySelectorAll('*') : []);
            const peers = candidates.filter((candidate) => cocxyStableRefBase(candidate) === base);
            const peerIndex = peers.indexOf(element);
            if (peerIndex <= 0) { return base; }
            return `${base}-${peerIndex + 1}`.slice(0, 64);
        };
        const cocxyEnsureStableRef = (element, index) => {
            if (!element || typeof element.getAttribute !== 'function') { return `missing-${index || 0}`; }
            const existing = element.getAttribute('data-cocxy-ref') || '';
            if (/^[A-Za-z0-9_-]{1,64}$/.test(existing)) { return existing; }
            const ref = cocxyStableRefForElement(element);
            element.setAttribute('data-cocxy-ref', ref);
            return ref;
        };
        const cocxyResolveStableRef = (ref) => {
            const wanted = String(ref || '');
            if (!wanted) { return null; }
            const attributed = Array.from(document.querySelectorAll('[data-cocxy-ref]'))
                .find((candidate) => candidate.getAttribute('data-cocxy-ref') === wanted);
            if (attributed) { return attributed; }
            const candidates = Array.from(document.body ? document.body.querySelectorAll('*') : []);
            for (const candidate of candidates) {
                const candidateRef = cocxyStableRefForElement(candidate);
                if (candidateRef === wanted) {
                    candidate.setAttribute('data-cocxy-ref', candidateRef);
                    return candidate;
                }
            }
            return null;
        };
        """
    }

    private static func cookieAssignment(
        name: String,
        value: String,
        path: String?,
        domain: String?,
        secure: Bool,
        sameSite: String?,
        maxAge: Int?
    ) -> String {
        var parts = ["\(name)=\(value)"]
        if let path, !path.isEmpty { parts.append("Path=\(path)") }
        if let domain, !domain.isEmpty { parts.append("Domain=\(domain)") }
        if let maxAge { parts.append("Max-Age=\(maxAge)") }
        if secure { parts.append("Secure") }
        if let sameSite, !sameSite.isEmpty { parts.append("SameSite=\(sameSite)") }
        return parts.joined(separator: "; ")
    }

    private static func stringValue(_ value: Any) -> String {
        switch value {
        case let value as String:
            return value
        case let value as Bool:
            return value ? "true" : "false"
        case let value as Int:
            return "\(value)"
        case let value as Double:
            return numberString(value)
        case let value as NSNumber:
            return "\(value)"
        case _ as NSNull:
            return ""
        default:
            guard JSONSerialization.isValidJSONObject([value]),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "\(value)"
            }
            return encoded
        }
    }

    static func compactJSONString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }

    private static func javaScriptStringLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
        guard let data,
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "''"
        }
        return String(encoded.dropFirst().dropLast())
    }
}
