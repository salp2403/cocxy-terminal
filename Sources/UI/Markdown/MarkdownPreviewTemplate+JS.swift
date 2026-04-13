// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownPreviewTemplate+JS.swift - JavaScript for markdown preview interactions.

import Foundation

extension MarkdownPreviewTemplate {
    static var updateScript: String {
        """
        function postPreviewMessage(type, payload) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cocxy) {
                window.webkit.messageHandlers.cocxy.postMessage({ type: type, payload: payload });
            }
        }

        function renderMermaid(root) {
            if (typeof mermaid === 'undefined') return;
            try {
                root.querySelectorAll('.mermaid[data-processed]').forEach(function(node) {
                    node.removeAttribute('data-processed');
                });
                mermaid.run({ nodes: root.querySelectorAll('.mermaid') });
            } catch (error) {
                console.log('Mermaid render error:', error);
            }
        }

        function renderMath(root) {
            if (typeof renderMathInElement === 'undefined') return;
            try {
                renderMathInElement(root, {
                    delimiters: [
                        { left: '$$', right: '$$', display: true },
                        { left: '$', right: '$', display: false }
                    ],
                    throwOnError: false
                });
            } catch (error) {
                console.log('KaTeX render error:', error);
            }
        }

        function decorateCodeBlocks(root) {
            root.querySelectorAll('.code-block').forEach(function(block) {
                var pre = block.querySelector('pre');
                var code = block.querySelector('code');
                var rawText = code ? code.textContent : (pre ? pre.textContent : '');
                var lineCount = rawText.length === 0 ? 1 : rawText.split('\\n').length;
                var gutter = block.querySelector('.code-line-numbers');
                if (!gutter) return;
                var numbers = [];
                for (var i = 1; i <= lineCount; i++) {
                    numbers.push(String(i));
                }
                gutter.textContent = numbers.join('\\n');
            });
        }

        function highlightCode(root) {
            if (typeof hljs !== 'undefined') {
                root.querySelectorAll('pre code').forEach(function(code) {
                    hljs.highlightElement(code);
                });
            }
            decorateCodeBlocks(root);
        }

        function isInteractiveTable(table) {
            if (!table) return false;
            return !table.closest('.mermaid, .katex, .footnotes, .frontmatter');
        }

        function tableToTSV(table) {
            var rows = [];
            table.querySelectorAll('tr').forEach(function(row) {
                var cells = Array.from(row.querySelectorAll('th, td')).map(function(cell) {
                    return (cell.textContent || '')
                        .replace(/\\t/g, ' ')
                        .replace(/\\n+/g, ' ')
                        .trim();
                });
                if (cells.length > 0) {
                    rows.push(cells.join('\\t'));
                }
            });
            return rows.join('\\n');
        }

        function makeSortable(table) {
            if (!isInteractiveTable(table) || table.dataset.sortReady === '1') return;

            var headers = table.querySelectorAll('thead th');
            if (headers.length === 0) return;

            table.dataset.sortReady = '1';

            headers.forEach(function(th, colIndex) {
                var indicator = document.createElement('span');
                indicator.className = 'sort-indicator';
                th.appendChild(indicator);
                th.dataset.sortState = '0';

                th.addEventListener('click', function() {
                    var tbody = table.querySelector('tbody');
                    if (!tbody) return;

                    if (!table._originalRows) {
                        table._originalRows = Array.from(tbody.querySelectorAll('tr')).map(function(row) {
                            return row.cloneNode(true);
                        });
                    }

                    headers.forEach(function(other, index) {
                        if (index !== colIndex) {
                            other.dataset.sortState = '0';
                            other.classList.remove('sort-asc', 'sort-desc');
                            var otherIndicator = other.querySelector('.sort-indicator');
                            if (otherIndicator) otherIndicator.textContent = '';
                        }
                    });

                    var state = (parseInt(th.dataset.sortState || '0', 10) + 1) % 3;
                    th.dataset.sortState = String(state);

                    if (state === 0) {
                        th.classList.remove('sort-asc', 'sort-desc');
                        indicator.textContent = '';
                        tbody.innerHTML = '';
                        table._originalRows.forEach(function(row) {
                            tbody.appendChild(row.cloneNode(true));
                        });
                        return;
                    }

                    var asc = state === 1;
                    indicator.textContent = asc ? ' ▲' : ' ▼';
                    th.classList.toggle('sort-asc', asc);
                    th.classList.toggle('sort-desc', !asc);

                    var rows = Array.from(tbody.querySelectorAll('tr'));
                    rows.sort(function(a, b) {
                        var aText = (a.children[colIndex] ? a.children[colIndex].textContent : '') || '';
                        var bText = (b.children[colIndex] ? b.children[colIndex].textContent : '') || '';
                        var result = aText.trim().localeCompare(
                            bText.trim(),
                            undefined,
                            { numeric: true, sensitivity: 'base' }
                        );
                        return asc ? result : -result;
                    });
                    rows.forEach(function(row) { tbody.appendChild(row); });
                });
            });
        }

        function enhanceTables(root) {
            root.querySelectorAll('table').forEach(function(table) {
                if (!isInteractiveTable(table)) return;

                if (!table.previousElementSibling || !table.previousElementSibling.classList.contains('table-tools')) {
                    var tools = document.createElement('div');
                    tools.className = 'table-tools';

                    var copyButton = document.createElement('button');
                    copyButton.type = 'button';
                    copyButton.className = 'table-copy';
                    copyButton.textContent = 'Copy TSV';
                    copyButton.addEventListener('click', function() {
                        postPreviewMessage('copyToClipboard', {
                            text: tableToTSV(table)
                        });
                    });

                    tools.appendChild(copyButton);
                    table.parentNode.insertBefore(tools, table);
                }

                makeSortable(table);
            });
        }

        function updateContent(html) {
            var content = document.getElementById('content');
            if (!content) return;

            var savedY = window.scrollY;
            content.innerHTML = html;

            renderMermaid(content);
            renderMath(content);
            highlightCode(content);
            enhanceTables(content);

            window.scrollTo(0, savedY);

            var tocPanel = document.getElementById('toc-panel');
            if (tocPanel && tocPanel.classList.contains('visible')) {
                buildTOC();
            }
        }

        function scrollToHeading(title) {
            var headings = document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6');
            for (var i = 0; i < headings.length; i++) {
                if (headings[i].textContent.trim() === title) {
                    headings[i].scrollIntoView({ behavior: 'smooth', block: 'start' });
                    return true;
                }
            }
            return false;
        }

        function buildTOC() {
            var panel = document.getElementById('toc-panel');
            if (!panel) return;
            while (panel.firstChild) panel.removeChild(panel.firstChild);

            var headings = document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6');
            if (headings.length === 0) {
                var empty = document.createElement('div');
                empty.className = 'toc-empty';
                empty.textContent = 'No headings';
                panel.appendChild(empty);
                return;
            }

            headings.forEach(function(heading, index) {
                var level = heading.tagName.toLowerCase();
                var id = 'toc-heading-' + index;
                heading.id = id;

                var link = document.createElement('a');
                link.href = '#';
                link.className = 'toc-' + level;
                link.textContent = heading.textContent.trim();
                link.addEventListener('click', function(event) {
                    event.preventDefault();
                    heading.scrollIntoView({ behavior: 'smooth', block: 'start' });
                });
                panel.appendChild(link);
            });
        }

        function closeLightbox() {
            var overlay = document.getElementById('lightbox-overlay');
            if (!overlay) return;
            overlay.hidden = true;
            overlay.classList.remove('visible');
        }

        function showLightbox(src, alt) {
            var overlay = document.getElementById('lightbox-overlay');
            var image = document.getElementById('lightbox-img');
            if (!overlay || !image) return;
            image.src = src;
            image.alt = alt || '';
            overlay.hidden = false;
            overlay.classList.add('visible');
        }

        function copyCode(button) {
            var block = button.closest('.code-block');
            if (!block) return;
            var pre = block.querySelector('pre');
            var text = pre ? pre.textContent : '';
            if (!text) return;

            var finish = function(success) {
                var previous = button.textContent;
                button.textContent = success ? 'Copied' : 'Copy failed';
                window.setTimeout(function() {
                    button.textContent = previous;
                }, 1200);
            };

            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(function() {
                    finish(true);
                }).catch(function() {
                    finish(false);
                });
                return;
            }

            try {
                var textarea = document.createElement('textarea');
                textarea.value = text;
                textarea.style.position = 'fixed';
                textarea.style.opacity = '0';
                document.body.appendChild(textarea);
                textarea.select();
                var copied = document.execCommand('copy');
                document.body.removeChild(textarea);
                finish(copied);
            } catch (_) {
                finish(false);
            }
        }

        function showFootnotePopover(anchor) {
            var preview = anchor.getAttribute('data-footnote-preview');
            if (!preview) return;
            var popover = document.getElementById('footnote-popover');
            if (!popover) return;
            popover.textContent = preview;
            popover.hidden = false;
            var rect = anchor.getBoundingClientRect();
            popover.style.left = Math.max(12, rect.left + window.scrollX) + 'px';
            popover.style.top = (rect.bottom + window.scrollY + 10) + 'px';
        }

        function hideFootnotePopover() {
            var popover = document.getElementById('footnote-popover');
            if (!popover) return;
            popover.hidden = true;
            popover.textContent = '';
        }

        if (typeof mermaid !== 'undefined') {
            mermaid.initialize({
                startOnLoad: false,
                theme: 'dark',
                themeVariables: {
                    darkMode: true,
                    background: '#1e1e2e',
                    primaryColor: '#89b4fa',
                    primaryTextColor: '#cdd6f4',
                    primaryBorderColor: '#585b70',
                    lineColor: '#6c7086',
                    secondaryColor: '#cba6f7',
                    tertiaryColor: '#313244',
                    noteBkgColor: '#313244',
                    noteTextColor: '#cdd6f4',
                    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace'
                }
            });
        }

        document.addEventListener('click', function(event) {
            var tocToggle = event.target.closest('#toc-toggle');
            if (tocToggle) {
                var panel = document.getElementById('toc-panel');
                if (!panel) return;
                var isVisible = panel.classList.toggle('visible');
                tocToggle.classList.toggle('active', isVisible);
                if (isVisible) buildTOC();
                return;
            }

            var codeButton = event.target.closest('.code-copy');
            if (codeButton) {
                event.preventDefault();
                copyCode(codeButton);
                return;
            }

            var image = event.target.closest('#content img');
            if (image) {
                event.preventDefault();
                showLightbox(image.getAttribute('src'), image.getAttribute('alt'));
                return;
            }

            if (event.target.id === 'lightbox-overlay') {
                closeLightbox();
            }
        });

        document.addEventListener('change', function(event) {
            var checkbox = event.target.closest('input[data-checkbox-index]');
            if (!checkbox) return;
            var index = parseInt(checkbox.getAttribute('data-checkbox-index'), 10);
            if (Number.isNaN(index)) return;
            postPreviewMessage('checkboxToggle', {
                index: index,
                checked: checkbox.checked
            });
        });

        document.addEventListener('dblclick', function(event) {
            var node = event.target;
            while (node && node !== document.body) {
                if (node.dataset && node.dataset.sourceLine !== undefined) {
                    var sourceLine = parseInt(node.dataset.sourceLine, 10);
                    if (!Number.isNaN(sourceLine)) {
                        postPreviewMessage('clickToSource', { sourceLine: sourceLine });
                    }
                    return;
                }
                node = node.parentElement;
            }
        });

        document.addEventListener('mouseover', function(event) {
            var anchor = event.target.closest('.footnote-ref a[data-footnote-preview]');
            if (anchor) showFootnotePopover(anchor);
        });

        document.addEventListener('mouseout', function(event) {
            var anchor = event.target.closest('.footnote-ref a[data-footnote-preview]');
            if (anchor) hideFootnotePopover();
        });

        document.addEventListener('keydown', function(event) {
            if (event.key === 'Escape') {
                closeLightbox();
                hideFootnotePopover();
            }
        });

        function scrollToFraction(fraction) {
            var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
            window.scrollTo(0, Math.round(maxScroll * fraction));
        }
        """
    }
}
