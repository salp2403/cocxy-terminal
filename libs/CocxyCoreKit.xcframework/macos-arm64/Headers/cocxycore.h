/**
 * CocxyCore — High-performance embeddable terminal engine.
 *
 * C API header. This is the stable public interface for consumers
 * in any language that supports C FFI (Swift, Python, Rust, etc.).
 *
 * Two levels of API:
 *   - Parser API: low-level byte-stream DFA (cocxycore_parser_*)
 *   - Terminal API: high-level wired pipeline (cocxycore_terminal_*)
 *
 * Most consumers should use the Terminal API — it handles parser,
 * screen buffer, executor, and wiring automatically.
 *
 * Version: 0.7.0 (Host Integration + GPU Data Pipeline)
 */

#ifndef COCXYCORE_H
#define COCXYCORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ====================================================================
 * Parser API (low-level)
 * ==================================================================== */

/** Opaque parser handle. Created with cocxycore_parser_create(). */
typedef struct cocxycore_parser cocxycore_parser;

/** Opaque PTY handle. Created with cocxycore_pty_spawn(). */
typedef struct cocxycore_pty cocxycore_pty;

/** Parser states (matches types.State in Zig). */
typedef enum {
    COCXYCORE_STATE_GROUND = 0,
    COCXYCORE_STATE_ESCAPE,
    COCXYCORE_STATE_ESCAPE_INTERMEDIATE,
    COCXYCORE_STATE_CSI_ENTRY,
    COCXYCORE_STATE_CSI_PARAM,
    COCXYCORE_STATE_CSI_INTERMEDIATE,
    COCXYCORE_STATE_CSI_IGNORE,
    COCXYCORE_STATE_OSC_STRING,
    COCXYCORE_STATE_DCS_ENTRY,
    COCXYCORE_STATE_DCS_PARAM,
    COCXYCORE_STATE_DCS_INTERMEDIATE,
    COCXYCORE_STATE_DCS_PASSTHROUGH,
    COCXYCORE_STATE_DCS_IGNORE,
    COCXYCORE_STATE_SOS_PM_APC_STRING,
} cocxycore_state;

/** Parser actions emitted on state transitions. */
typedef enum {
    COCXYCORE_ACTION_NONE = 0,
    COCXYCORE_ACTION_PRINT,
    COCXYCORE_ACTION_EXECUTE,
    COCXYCORE_ACTION_CLEAR,
    COCXYCORE_ACTION_COLLECT,
    COCXYCORE_ACTION_PARAM,
    COCXYCORE_ACTION_ESC_DISPATCH,
    COCXYCORE_ACTION_CSI_DISPATCH,
    COCXYCORE_ACTION_OSC_START,
    COCXYCORE_ACTION_OSC_PUT,
    COCXYCORE_ACTION_OSC_END,
    COCXYCORE_ACTION_HOOK,
    COCXYCORE_ACTION_PUT,
    COCXYCORE_ACTION_UNHOOK,
} cocxycore_action;

/**
 * Action callback invoked by the parser for each non-none action.
 *
 * @param action  The parser action that occurred.
 * @param byte    The byte that triggered the action.
 * @param context User-provided context pointer (passed to set_callback).
 */
typedef void (*cocxycore_action_callback)(
    cocxycore_action action,
    uint8_t byte,
    void* context
);

/* -- Parser lifecycle -- */

/** Create a new parser instance. Returns NULL on allocation failure. */
cocxycore_parser* cocxycore_parser_create(void);

/** Destroy a parser instance and free its memory. */
void cocxycore_parser_destroy(cocxycore_parser* parser);

/** Reset the parser to its initial (ground) state. */
void cocxycore_parser_reset(cocxycore_parser* parser);

/* -- Parser operations -- */

/**
 * Feed raw bytes into the parser.
 *
 * @param parser  Parser instance.
 * @param data    Pointer to byte buffer.
 * @param len     Number of bytes to process.
 */
void cocxycore_parser_feed(
    cocxycore_parser* parser,
    const uint8_t* data,
    size_t len
);

/**
 * Register an action callback.
 *
 * @param parser   Parser instance.
 * @param callback Function to call on each action (NULL to disable).
 * @param context  User context pointer passed to every callback invocation.
 */
void cocxycore_parser_set_callback(
    cocxycore_parser* parser,
    cocxycore_action_callback callback,
    void* context
);

/**
 * Get the current parser state.
 *
 * @param parser  Parser instance.
 * @return Current state as cocxycore_state enum value.
 */
uint8_t cocxycore_parser_get_state(cocxycore_parser* parser);

/* ====================================================================
 * PTY API
 * ==================================================================== */

/** PTY child status values. */
typedef enum {
    COCXYCORE_PTY_RUNNING = 0,
    COCXYCORE_PTY_EXITED,
    COCXYCORE_PTY_SIGNALED,
} cocxycore_pty_status;

/** Non-blocking PTY wait result. */
typedef struct {
    uint8_t status;     /**< cocxycore_pty_status */
    uint8_t exit_code;  /**< Valid when status == EXITED */
    uint8_t signal;     /**< Valid when status == SIGNALED */
    uint8_t _pad;
} cocxycore_pty_wait_result;

/**
 * Spawn a PTY-backed child process.
 *
 * @param rows   Initial terminal rows.
 * @param cols   Initial terminal columns.
 * @param shell  Shell path (NULL = default shell).
 * @return PTY handle, or NULL on failure.
 */
cocxycore_pty* cocxycore_pty_spawn(uint16_t rows, uint16_t cols, const char* shell);

/** Destroy a PTY handle and terminate the child if still running. */
void cocxycore_pty_destroy(cocxycore_pty* pty);

/** Read from the PTY master. Returns bytes read, or 0 on error/EOF. */
size_t cocxycore_pty_read(cocxycore_pty* pty, uint8_t* buf, size_t buf_len);

/** Write to the PTY master. Returns bytes written, or 0 on error. */
size_t cocxycore_pty_write(cocxycore_pty* pty, const uint8_t* data, size_t len);

/** Resize the PTY terminal dimensions. */
void cocxycore_pty_resize(cocxycore_pty* pty, uint16_t rows, uint16_t cols);

/**
 * Poll PTY child status without blocking.
 * Returns false only when pty is NULL.
 */
bool cocxycore_pty_wait_check(cocxycore_pty* pty, cocxycore_pty_wait_result* out);

/** Send a signal to the PTY child. */
void cocxycore_pty_send_signal(cocxycore_pty* pty, int32_t sig);

/** Get the PTY master file descriptor, or -1 when unavailable. */
int32_t cocxycore_pty_master_fd(cocxycore_pty* pty);

/** Get the PTY child PID, or -1 when unavailable. */
int32_t cocxycore_pty_child_pid(cocxycore_pty* pty);

/** Check whether the PTY child is still believed to be alive. */
bool cocxycore_pty_is_alive(cocxycore_pty* pty);

/* ====================================================================
 * Terminal API (high-level — recommended for most consumers)
 * ==================================================================== */

/** Opaque terminal handle. Wraps parser + screen + executor. */
typedef struct cocxycore_terminal cocxycore_terminal;

/* -- Terminal lifecycle -- */

/**
 * Create a terminal instance with the given dimensions.
 * Returns NULL on allocation failure or if rows/cols is 0.
 *
 * @param rows  Number of rows (height).
 * @param cols  Number of columns (width).
 */
cocxycore_terminal* cocxycore_terminal_create(uint16_t rows, uint16_t cols);

/** Destroy a terminal instance and free all memory. */
void cocxycore_terminal_destroy(cocxycore_terminal* term);

/* -- Data flow -- */

/**
 * Feed raw bytes through the full terminal pipeline
 * (parser -> executor -> screen).
 *
 * @param term  Terminal instance.
 * @param data  Pointer to byte buffer.
 * @param len   Number of bytes to process.
 */
void cocxycore_terminal_feed(
    cocxycore_terminal* term,
    const uint8_t* data,
    size_t len
);

/* -- Dimensions & Resize -- */

/** Get the number of rows. */
uint16_t cocxycore_terminal_rows(const cocxycore_terminal* term);

/** Get the number of columns. */
uint16_t cocxycore_terminal_cols(const cocxycore_terminal* term);

/**
 * Resize the terminal. Returns true on success, false on allocation failure.
 *
 * @param term  Terminal instance.
 * @param rows  New number of rows.
 * @param cols  New number of columns.
 */
bool cocxycore_terminal_resize(cocxycore_terminal* term, uint16_t rows, uint16_t cols);

/* -- Cursor -- */

/** Get the cursor row (0-based). */
uint16_t cocxycore_terminal_cursor_row(const cocxycore_terminal* term);

/** Get the cursor column (0-based). */
uint16_t cocxycore_terminal_cursor_col(const cocxycore_terminal* term);

/** Check if the cursor is visible. */
bool cocxycore_terminal_cursor_visible(const cocxycore_terminal* term);

/**
 * Get the cursor shape.
 * 0=block_blink, 1=block_steady, 2=underline_blink,
 * 3=underline_steady, 4=bar_blink, 5=bar_steady.
 */
uint8_t cocxycore_terminal_cursor_shape(const cocxycore_terminal* term);

/* -- Cell access -- */

/** Get the Unicode codepoint at (row, col). Returns 0 if out of bounds. */
uint32_t cocxycore_terminal_cell_char(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col
);

/** Get the cell width: 0=narrow, 1=wide, 2=continuation. */
uint8_t cocxycore_terminal_cell_width(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col
);

/**
 * Get the cell style as a packed byte.
 * bit0=bold, bit1=dim, bit2=italic, bit3=underline,
 * bit4=blink, bit5=reverse, bit6=hidden, bit7=strikethrough.
 */
uint8_t cocxycore_terminal_cell_style(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col
);

/** Color type constants. */
typedef enum {
    COCXYCORE_COLOR_DEFAULT = 0,
    COCXYCORE_COLOR_INDEXED = 1,
    COCXYCORE_COLOR_RGB = 2,
} cocxycore_color_type;

/** Get the foreground color type. */
uint8_t cocxycore_terminal_cell_fg_type(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col
);

/** Get the foreground indexed color (valid when fg_type == INDEXED). */
uint8_t cocxycore_terminal_cell_fg_index(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col
);

/** Get the foreground RGB values (valid when fg_type == RGB). */
void cocxycore_terminal_cell_fg_rgb(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col,
    uint8_t* r,
    uint8_t* g,
    uint8_t* b
);

/** Get the background color type. */
uint8_t cocxycore_terminal_cell_bg_type(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col
);

/** Get the background indexed color (valid when bg_type == INDEXED). */
uint8_t cocxycore_terminal_cell_bg_index(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col
);

/** Get the background RGB values (valid when bg_type == RGB). */
void cocxycore_terminal_cell_bg_rgb(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col,
    uint8_t* r,
    uint8_t* g,
    uint8_t* b
);

/** Get the number of combining marks on a cell. */
uint8_t cocxycore_terminal_cell_combining_count(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col
);

/** Get a combining mark codepoint by index. Returns 0 if out of range. */
uint32_t cocxycore_terminal_cell_combining(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col,
    uint8_t index
);

/* -- Dirty tracking -- */

/** Check if a row has been modified since the last clear. */
bool cocxycore_terminal_is_dirty(const cocxycore_terminal* term, uint16_t row);

/** Clear all dirty flags. Call after rendering. */
void cocxycore_terminal_clear_dirty(cocxycore_terminal* term);

/* -- Scrollback -- */

/**
 * Enable scrollback history. Returns true on success.
 *
 * @param term      Terminal instance.
 * @param capacity  Maximum number of rows to store.
 */
bool cocxycore_terminal_enable_scrollback(cocxycore_terminal* term, uint32_t capacity);

/** Get the number of rows currently in scrollback. */
uint32_t cocxycore_terminal_scrollback_len(const cocxycore_terminal* term);

/**
 * Get a codepoint from a scrollback row.
 * offset 0 = most recently scrolled-off row.
 */
uint32_t cocxycore_terminal_scrollback_cell_char(
    const cocxycore_terminal* term,
    uint32_t offset,
    uint16_t col
);

/* -- Combined history view -- */

/** Get the total row count of scrollback plus visible screen. */
uint32_t cocxycore_terminal_history_rows(const cocxycore_terminal* term);

/** Get the absolute history row where the visible screen begins. */
uint32_t cocxycore_terminal_history_visible_start(const cocxycore_terminal* term);

/** Get the maximum top-row value the viewport can scroll to. */
uint32_t cocxycore_terminal_history_max_visible_start(const cocxycore_terminal* term);

/**
 * Set the absolute history row shown at the top of the viewport.
 * Returns false when the terminal is NULL or the alternate screen is active.
 */
bool cocxycore_terminal_history_set_visible_start(
    cocxycore_terminal* term,
    uint32_t absolute_row
);

/**
 * Scroll the viewport by a signed number of rows.
 * Positive values move upward into older scrollback.
 * Returns false when the terminal is NULL or the alternate screen is active.
 */
bool cocxycore_terminal_history_scroll_viewport(
    cocxycore_terminal* term,
    int32_t delta_rows
);

/** Get a codepoint from the combined history view. */
uint32_t cocxycore_terminal_history_cell_char(
    const cocxycore_terminal* term,
    uint32_t absolute_row,
    uint16_t col
);

/* -- Selection -- */

/** Inclusive range in the combined history view. */
typedef struct {
    uint32_t start_row;
    uint16_t start_col;
    uint32_t end_row;
    uint16_t end_col;
} cocxycore_buffer_range;

/** Check whether a selection is active. */
bool cocxycore_terminal_selection_active(const cocxycore_terminal* term);

/** Clear the active selection. */
void cocxycore_terminal_selection_clear(cocxycore_terminal* term);

/** Set the active selection using absolute history coordinates. */
void cocxycore_terminal_selection_set(
    cocxycore_terminal* term,
    uint32_t start_row,
    uint16_t start_col,
    uint32_t end_row,
    uint16_t end_col
);

/** Get the normalized active selection range. Returns false if none is active. */
bool cocxycore_terminal_selection_get(
    const cocxycore_terminal* term,
    cocxycore_buffer_range* out
);

/** Check whether the selection contains a history cell. */
bool cocxycore_terminal_selection_contains(
    const cocxycore_terminal* term,
    uint32_t absolute_row,
    uint16_t col
);

/**
 * Copy the active selection as UTF-8.
 * Returns the total byte count required; output is truncated to buf_len.
 */
size_t cocxycore_terminal_selection_copy_text(
    const cocxycore_terminal* term,
    uint8_t* buf,
    size_t buf_len
);

/* -- Search -- */

/**
 * Search forward in the combined history view.
 * Returns true and fills out on match.
 */
bool cocxycore_terminal_search_next(
    const cocxycore_terminal* term,
    const uint8_t* query,
    size_t len,
    uint32_t from_row,
    uint16_t from_col,
    bool case_sensitive,
    cocxycore_buffer_range* out
);

/**
 * Search backward in the combined history view.
 * Returns true and fills out on match.
 */
bool cocxycore_terminal_search_prev(
    const cocxycore_terminal* term,
    const uint8_t* query,
    size_t len,
    uint32_t from_row,
    uint16_t from_col,
    bool case_sensitive,
    cocxycore_buffer_range* out
);

/* -- Preedit / IME -- */

/** Check whether host-provided preedit text is active. */
bool cocxycore_terminal_preedit_active(const cocxycore_terminal* term);

/** Set host-provided preedit text anchored at a visible cell. */
void cocxycore_terminal_preedit_set(
    cocxycore_terminal* term,
    uint16_t row,
    uint16_t col,
    const uint8_t* text,
    size_t len,
    uint16_t cursor_bytes
);

/** Clear the active preedit text. */
void cocxycore_terminal_preedit_clear(cocxycore_terminal* term);

/**
 * Copy the active preedit UTF-8 bytes.
 * Returns the total byte count required; output is truncated to buf_len.
 */
size_t cocxycore_terminal_preedit_text(
    const cocxycore_terminal* term,
    uint8_t* buf,
    size_t buf_len
);

/** Get the cursor byte offset within the active preedit string. */
uint16_t cocxycore_terminal_preedit_cursor_bytes(const cocxycore_terminal* term);

/** Get the preedit anchor position. Writes 0/0 when term is NULL. */
void cocxycore_terminal_preedit_anchor(
    const cocxycore_terminal* term,
    uint16_t* out_row,
    uint16_t* out_col
);

/* -- Response buffer (DSR, DECRQSS) -- */

/** Check if there is a pending response to write back to the PTY. */
bool cocxycore_terminal_has_response(const cocxycore_terminal* term);

/**
 * Read the pending response into the provided buffer.
 * Returns the number of bytes written. Consumes the response.
 */
size_t cocxycore_terminal_read_response(
    cocxycore_terminal* term,
    uint8_t* buf,
    size_t buf_len
);

/* -- Terminal modes -- */

/** Check if application cursor keys mode is active (DECCKM). */
bool cocxycore_terminal_mode_app_cursor(const cocxycore_terminal* term);

/** Check if bracketed paste mode is active. */
bool cocxycore_terminal_mode_bracketed_paste(const cocxycore_terminal* term);

/**
 * Get the current mouse tracking mode.
 * 0=none, 1=x10, 2=normal, 3=highlight,
 * 4=button_event, 5=any_event, 6=sgr.
 */
uint8_t cocxycore_terminal_mode_mouse(const cocxycore_terminal* term);

/** Check if the alternate screen buffer is active. */
bool cocxycore_terminal_is_alt_screen(const cocxycore_terminal* term);

/* -- Callbacks -- */

/**
 * Title change callback type.
 * @param title   Pointer to the title string (NOT null-terminated).
 * @param len     Length of the title string.
 * @param context User-provided context pointer.
 */
typedef void (*cocxycore_title_callback)(
    const uint8_t* title,
    size_t len,
    void* context
);

/** Working directory change callback type. */
typedef void (*cocxycore_cwd_callback)(
    const uint8_t* cwd,
    size_t len,
    void* context
);

/** Bell callback type. */
typedef void (*cocxycore_bell_callback)(void* context);

/** Clipboard event payload delivered for OSC 52 traffic. */
typedef struct {
    uint8_t event_type;        /**< 0=set, 1=query */
    uint8_t selection;         /**< 0=primary, 1=clipboard */
    uint8_t _pad[6];
    const uint8_t* text_ptr;   /**< Decoded text for set events, NULL for query */
    size_t text_len;
} cocxycore_clipboard_event;

/** Clipboard callback type. */
typedef void (*cocxycore_clipboard_callback)(
    const cocxycore_clipboard_event* event,
    void* context
);

/** Set the title change callback. Pass NULL to disable. */
void cocxycore_terminal_set_title_callback(
    cocxycore_terminal* term,
    cocxycore_title_callback callback,
    void* context
);

/** Set the working directory change callback. Pass NULL to disable. */
void cocxycore_terminal_set_cwd_callback(
    cocxycore_terminal* term,
    cocxycore_cwd_callback callback,
    void* context
);

/** Set the bell callback. Pass NULL to disable. */
void cocxycore_terminal_set_bell_callback(
    cocxycore_terminal* term,
    cocxycore_bell_callback callback,
    void* context
);

/** Set the OSC 52 clipboard callback. Pass NULL to disable. */
void cocxycore_terminal_set_clipboard_callback(
    cocxycore_terminal* term,
    cocxycore_clipboard_callback callback,
    void* context
);

/* -- Reset -- */

/** Full terminal reset (RIS). Clears screen, resets modes and cursor. */
void cocxycore_terminal_reset(cocxycore_terminal* term);

/* ====================================================================
 * Input Encoding API
 * ==================================================================== */

/** Key identifiers for cocxycore_terminal_encode_key(). */
typedef enum {
    COCXYCORE_KEY_UP = 0,
    COCXYCORE_KEY_DOWN,
    COCXYCORE_KEY_RIGHT,
    COCXYCORE_KEY_LEFT,
    COCXYCORE_KEY_HOME,
    COCXYCORE_KEY_END,
    COCXYCORE_KEY_INSERT,
    COCXYCORE_KEY_DELETE,
    COCXYCORE_KEY_PAGE_UP,
    COCXYCORE_KEY_PAGE_DOWN,
    COCXYCORE_KEY_F1,
    COCXYCORE_KEY_F2,
    COCXYCORE_KEY_F3,
    COCXYCORE_KEY_F4,
    COCXYCORE_KEY_F5,
    COCXYCORE_KEY_F6,
    COCXYCORE_KEY_F7,
    COCXYCORE_KEY_F8,
    COCXYCORE_KEY_F9,
    COCXYCORE_KEY_F10,
    COCXYCORE_KEY_F11,
    COCXYCORE_KEY_F12,
    COCXYCORE_KEY_BACKSPACE,
    COCXYCORE_KEY_TAB,
    COCXYCORE_KEY_ENTER,
    COCXYCORE_KEY_ESCAPE,
    COCXYCORE_KEY_KP_0,
    COCXYCORE_KEY_KP_1,
    COCXYCORE_KEY_KP_2,
    COCXYCORE_KEY_KP_3,
    COCXYCORE_KEY_KP_4,
    COCXYCORE_KEY_KP_5,
    COCXYCORE_KEY_KP_6,
    COCXYCORE_KEY_KP_7,
    COCXYCORE_KEY_KP_8,
    COCXYCORE_KEY_KP_9,
    COCXYCORE_KEY_KP_ENTER,
    COCXYCORE_KEY_KP_PLUS,
    COCXYCORE_KEY_KP_MINUS,
    COCXYCORE_KEY_KP_MULTIPLY,
    COCXYCORE_KEY_KP_DIVIDE,
    COCXYCORE_KEY_KP_DECIMAL,
    COCXYCORE_KEY_KP_SEPARATOR,
} cocxycore_key;

/** Modifier bitmask constants for encode_key/encode_char. */
#define COCXYCORE_MOD_SHIFT 1
#define COCXYCORE_MOD_ALT   2
#define COCXYCORE_MOD_CTRL  4
#define COCXYCORE_MOD_META  8

/**
 * Encode a special key press using the terminal's current mode state.
 * Reads DECCKM, keypad mode, and kitty keyboard flags from the terminal.
 *
 * @param term     Terminal instance.
 * @param key      Key identifier (cocxycore_key enum value).
 * @param mods     Modifier bitmask (COCXYCORE_MOD_*).
 * @param buf      Output buffer for the encoded byte sequence.
 * @param buf_len  Size of the output buffer.
 * @return Number of bytes written. 0 if terminal is NULL or key is invalid.
 */
size_t cocxycore_terminal_encode_key(
    const cocxycore_terminal* term,
    uint8_t key,
    uint8_t mods,
    uint8_t* buf,
    size_t buf_len
);

/**
 * Encode a Unicode character with modifiers.
 * Handles Ctrl+letter, Alt prefix, and kitty disambiguate mode.
 *
 * @param term       Terminal instance.
 * @param codepoint  Unicode codepoint (0-0x10FFFF).
 * @param mods       Modifier bitmask (COCXYCORE_MOD_*).
 * @param buf        Output buffer for the encoded byte sequence.
 * @param buf_len    Size of the output buffer.
 * @return Number of bytes written. 0 if terminal is NULL or codepoint invalid.
 */
size_t cocxycore_terminal_encode_char(
    const cocxycore_terminal* term,
    uint32_t codepoint,
    uint8_t mods,
    uint8_t* buf,
    size_t buf_len
);

/**
 * Get the current kitty keyboard enhancement flags.
 * 0 = legacy mode, bit 0 = disambiguate escape codes.
 */
uint8_t cocxycore_terminal_mode_kitty_keyboard(const cocxycore_terminal* term);

/* ====================================================================
 * Semantic API — AI Semantic Layer
 * ==================================================================== */

/** Semantic event types (matches SemanticEventType in Zig). */
typedef enum {
    COCXYCORE_SEMANTIC_PROMPT_SHOWN = 0,
    COCXYCORE_SEMANTIC_COMMAND_STARTED,
    COCXYCORE_SEMANTIC_COMMAND_FINISHED,
    COCXYCORE_SEMANTIC_AGENT_LAUNCHED,
    COCXYCORE_SEMANTIC_AGENT_OUTPUT,
    COCXYCORE_SEMANTIC_AGENT_WAITING,
    COCXYCORE_SEMANTIC_AGENT_ERROR,
    COCXYCORE_SEMANTIC_AGENT_FINISHED,
    COCXYCORE_SEMANTIC_TOOL_STARTED,
    COCXYCORE_SEMANTIC_TOOL_FINISHED,
    COCXYCORE_SEMANTIC_FILE_PATH_DETECTED,
    COCXYCORE_SEMANTIC_ERROR_DETECTED,
    COCXYCORE_SEMANTIC_PROGRESS_UPDATE,
    COCXYCORE_SEMANTIC_PROTOCOL_V2_EVENT,
} cocxycore_semantic_event_type;

/** Semantic event sources. */
typedef enum {
    COCXYCORE_SOURCE_SHELL_MARK = 0,
    COCXYCORE_SOURCE_PROTOCOL_V2,
    COCXYCORE_SOURCE_NOTIFICATION,
    COCXYCORE_SOURCE_PATTERN_MATCH,
    COCXYCORE_SOURCE_CWD_CHANGE,
} cocxycore_semantic_source;

/** Semantic block types. */
typedef enum {
    COCXYCORE_BLOCK_PROMPT = 0,
    COCXYCORE_BLOCK_COMMAND_INPUT,
    COCXYCORE_BLOCK_COMMAND_OUTPUT,
    COCXYCORE_BLOCK_ERROR_OUTPUT,
    COCXYCORE_BLOCK_TOOL_CALL,
    COCXYCORE_BLOCK_AGENT_STATUS,
    COCXYCORE_BLOCK_UNKNOWN,
} cocxycore_block_type;

/** Semantic states. */
typedef enum {
    COCXYCORE_SEMANTIC_IDLE = 0,
    COCXYCORE_SEMANTIC_PROMPT,
    COCXYCORE_SEMANTIC_COMMAND_INPUT,
    COCXYCORE_SEMANTIC_COMMAND_RUNNING,
    COCXYCORE_SEMANTIC_AGENT_ACTIVE,
} cocxycore_semantic_state_t;

/** Pattern types for heuristic matching. */
typedef enum {
    COCXYCORE_PATTERN_AGENT_LAUNCH = 0,
    COCXYCORE_PATTERN_AGENT_WAITING,
    COCXYCORE_PATTERN_AGENT_ERROR,
    COCXYCORE_PATTERN_AGENT_FINISHED,
    COCXYCORE_PATTERN_TOOL_START,
    COCXYCORE_PATTERN_TOOL_END,
    COCXYCORE_PATTERN_ERROR_GENERIC,
    COCXYCORE_PATTERN_FILE_PATH,
} cocxycore_pattern_type;

/** Pattern match modes. */
typedef enum {
    COCXYCORE_MATCH_PREFIX = 0,
    COCXYCORE_MATCH_CONTAINS,
    COCXYCORE_MATCH_SUFFIX,
} cocxycore_match_mode;

/**
 * Semantic event (passed to callback).
 * Fields are ordered for natural C struct alignment.
 */
typedef struct {
    uint8_t event_type;         /**< cocxycore_semantic_event_type */
    uint8_t source;             /**< cocxycore_semantic_source */
    int16_t exit_code;          /**< Exit code (-1 = unknown) */
    uint32_t row;               /**< Screen row where event occurred */
    uint32_t block_id;          /**< Associated block ID (0 = none) */
    float confidence;           /**< 0.0-1.0 (1.0 = deterministic) */
    uint64_t timestamp;         /**< Nanoseconds */
    const uint8_t* detail_ptr;  /**< Detail text (NOT null-terminated) */
    uint16_t detail_len;        /**< Length of detail text */
    uint16_t _pad;              /**< Explicit padding */
    uint32_t stream_id;         /**< Stream ID (0 = primary/untagged) */
} cocxycore_semantic_event;

/**
 * Semantic block (output from get_block).
 * Represents a classified region of terminal output.
 */
typedef struct {
    uint8_t block_type;             /**< cocxycore_block_type */
    uint8_t detail_len;             /**< Length of detail text */
    int16_t exit_code;              /**< Exit code (-1 = unknown/N/A) */
    uint32_t start_row;             /**< Absolute start row (inclusive) */
    uint32_t end_row;               /**< Absolute end row (inclusive) */
    uint32_t stream_id;             /**< Stream ID (0 = primary/untagged) */
    uint64_t timestamp_start;       /**< When block started (ns) */
    uint64_t timestamp_end;         /**< When block ended (ns, 0 = open) */
    uint8_t detail_buf[128];        /**< Detail text */
} cocxycore_semantic_block;

/**
 * Semantic event callback type.
 *
 * @param event   Pointer to the event (valid only during callback).
 * @param context User-provided context pointer.
 */
typedef void (*cocxycore_semantic_callback)(
    const cocxycore_semantic_event* event,
    void* context
);

/* -- Semantic lifecycle -- */

/**
 * Enable the AI semantic layer with a scrollback block capacity.
 * Must be called before any other semantic API function.
 * Returns false if already enabled or allocation fails.
 *
 * @param term      Terminal instance.
 * @param capacity  Maximum number of semantic blocks to store.
 */
bool cocxycore_terminal_enable_semantic(cocxycore_terminal* term, uint32_t capacity);

/**
 * Set the semantic event callback. Pass NULL to disable.
 *
 * @param term     Terminal instance.
 * @param callback Function called for each semantic event.
 * @param context  User context pointer passed to every invocation.
 */
void cocxycore_terminal_set_semantic_callback(
    cocxycore_terminal* term,
    cocxycore_semantic_callback callback,
    void* context
);

/* -- Pattern management -- */

/**
 * Register a pattern for heuristic line matching.
 * Returns false if the pattern registry is full (max 64).
 *
 * @param term        Terminal instance.
 * @param type        Pattern type (cocxycore_pattern_type).
 * @param mode        Match mode (cocxycore_match_mode).
 * @param text        Pattern text to match.
 * @param len         Length of pattern text.
 * @param confidence  Confidence level (0.0-1.0).
 */
bool cocxycore_terminal_add_pattern(
    cocxycore_terminal* term,
    uint8_t type,
    uint8_t mode,
    const uint8_t* text,
    size_t len,
    float confidence
);

/** Remove all patterns of a specific type. */
void cocxycore_terminal_clear_patterns(cocxycore_terminal* term, uint8_t type);

/** Remove all registered patterns. */
void cocxycore_terminal_clear_all_patterns(cocxycore_terminal* term);

/* -- Semantic scrollback queries -- */

/** Get the total number of semantic blocks. */
uint32_t cocxycore_terminal_semantic_block_count(const cocxycore_terminal* term);

/** Get the number of semantic blocks of a specific type. */
uint32_t cocxycore_terminal_semantic_block_count_by_type(
    const cocxycore_terminal* term,
    uint8_t block_type
);

/**
 * Get a semantic block by offset from newest (0 = most recent).
 * Returns true if the block was found and out_block was filled.
 *
 * @param term      Terminal instance.
 * @param offset    Offset from newest block (0 = most recent).
 * @param out_block Output block structure to fill.
 */
bool cocxycore_terminal_semantic_get_block(
    const cocxycore_terminal* term,
    uint32_t offset,
    cocxycore_semantic_block* out_block
);

/**
 * Find the next block of a given type after from_offset.
 * Searches towards older blocks. Returns the offset, or -1 if not found.
 */
int32_t cocxycore_terminal_semantic_find_next(
    const cocxycore_terminal* term,
    uint8_t block_type,
    uint32_t from_offset
);

/**
 * Find the previous block of a given type before from_offset.
 * Searches towards newer blocks. Returns the offset, or -1 if not found.
 */
int32_t cocxycore_terminal_semantic_find_prev(
    const cocxycore_terminal* term,
    uint8_t block_type,
    uint32_t from_offset
);

/** Clear all semantic blocks (does not free memory). */
void cocxycore_terminal_semantic_clear(cocxycore_terminal* term);

/* -- Semantic state queries -- */

/**
 * Get the current semantic state.
 * 0=idle, 1=prompt, 2=command_input, 3=command_running, 4=agent_active.
 */
uint8_t cocxycore_terminal_semantic_state(const cocxycore_terminal* term);

/**
 * Get the current open block's type.
 * Returns the block type (cocxycore_block_type), or 255 if no block is open.
 */
uint8_t cocxycore_terminal_semantic_current_block_type(const cocxycore_terminal* term);

/* ====================================================================
 * Process Tracking API — Multi-stream PTY
 * ==================================================================== */

/** Process event types. */
typedef enum {
    COCXYCORE_PROCESS_CHILD_SPAWNED = 0,
    COCXYCORE_PROCESS_CHILD_EXITED,
} cocxycore_process_event_type;

/** Process states. */
typedef enum {
    COCXYCORE_PROCESS_RUNNING = 0,
    COCXYCORE_PROCESS_EXITED,
    COCXYCORE_PROCESS_SIGNALED,
} cocxycore_process_state;

/** Process event (passed to callback). */
typedef struct {
    uint8_t event_type;         /**< cocxycore_process_event_type */
    uint8_t _pad[3];
    int32_t pid;                /**< Child PID */
    int32_t parent_pid;         /**< Parent PID */
    uint32_t stream_id;         /**< Assigned stream ID */
    int16_t exit_code;          /**< Exit code (-1 = unknown) */
    uint16_t _pad2;
} cocxycore_process_event;

/** Process info (output from stream_info). */
typedef struct {
    int32_t pid;
    int32_t parent_pid;
    uint32_t stream_id;
    uint8_t state;              /**< cocxycore_process_state */
    uint8_t _pad;
    int16_t exit_code;          /**< Exit code (-1 = unknown) */
} cocxycore_process_info;

/**
 * Process event callback type.
 *
 * @param event   Pointer to the event (valid only during callback).
 * @param context User-provided context pointer.
 */
typedef void (*cocxycore_process_callback)(
    const cocxycore_process_event* event,
    void* context
);

/**
 * Enable process tracking with a fixed-size process table.
 * Monitors root_pid and its descendants using kqueue + libproc.
 * Returns false if already enabled, invalid PID, or allocation failure.
 *
 * @param term      Terminal instance.
 * @param root_pid  PID of the root process (typically the shell).
 * @param capacity  Maximum number of processes to track.
 */
bool cocxycore_terminal_enable_process_tracking(
    cocxycore_terminal* term,
    int32_t root_pid,
    uint32_t capacity
);

/**
 * Set the process event callback. Pass NULL to disable.
 */
void cocxycore_terminal_set_process_callback(
    cocxycore_terminal* term,
    cocxycore_process_callback callback,
    void* context
);

/**
 * Poll for process events (non-blocking).
 * Call periodically in your event loop.
 */
void cocxycore_terminal_poll_processes(cocxycore_terminal* term);

/** Get the number of tracked processes (all states). */
uint32_t cocxycore_terminal_stream_count(const cocxycore_terminal* term);

/**
 * Get process info by stream ID.
 * Returns true if the stream was found and out_info was filled.
 */
bool cocxycore_terminal_stream_info(
    const cocxycore_terminal* term,
    uint32_t stream_id,
    cocxycore_process_info* out_info
);

/**
 * Set the active stream ID for tagging semantic events and blocks.
 * Pass 0 to return to the primary/untagged stream.
 */
void cocxycore_terminal_set_current_stream(cocxycore_terminal* term, uint32_t stream_id);

/* ====================================================================
 * Rendering and GPU API
 * ==================================================================== */

/** RGBA color (4 bytes). */
typedef struct {
    uint8_t r, g, b, a;
} cocxycore_rgba;

/** Font metrics computed from the loaded font. */
typedef struct {
    float cell_width;
    float cell_height;
    float ascent;
    float descent;
    float leading;
    float underline_position;
    float underline_thickness;
    float strikethrough_position;
} cocxycore_font_metrics;

/**
 * Render cell — resolved colors and codepoint for one grid position.
 * flags: bit0=underline, bit1=strikethrough, bit2=italic, bit3=bold,
 *        bit4=wide, bit5=continuation
 */
typedef struct {
    cocxycore_rgba fg;
    cocxycore_rgba bg;
    uint32_t codepoint;
    uint8_t flags;
} cocxycore_render_cell;

/** Render cursor — position, shape, and color for cursor drawing. */
typedef struct {
    uint16_t row;
    uint16_t col;
    uint8_t shape;      /**< CursorShape enum value (0-5) */
    bool visible;
    uint16_t _pad;
    cocxycore_rgba color;
} cocxycore_render_cursor;

/* -- Theme -- */

/**
 * Set the color theme (foreground, background, cursor).
 * Base16 colors can be set individually with set_theme_base16.
 */
void cocxycore_terminal_set_theme(
    cocxycore_terminal* term,
    uint8_t fg_r, uint8_t fg_g, uint8_t fg_b,
    uint8_t bg_r, uint8_t bg_g, uint8_t bg_b,
    uint8_t cursor_r, uint8_t cursor_g, uint8_t cursor_b
);

/** Set a single base16 palette color (index 0-15). */
void cocxycore_terminal_set_theme_base16(
    cocxycore_terminal* term,
    uint8_t index,
    uint8_t r, uint8_t g, uint8_t b
);

/** Set the selection highlight color. */
void cocxycore_terminal_set_selection_color(
    cocxycore_terminal* term,
    uint8_t r,
    uint8_t g,
    uint8_t b,
    uint8_t a
);

/**
 * Resolve a cell's colors to RGBA with theme and style effects.
 * Writes to out_fg and out_bg. Pass NULL to skip either.
 */
void cocxycore_terminal_resolve_cell_colors(
    const cocxycore_terminal* term,
    uint16_t row, uint16_t col,
    cocxycore_rgba* out_fg,
    cocxycore_rgba* out_bg
);

/* -- Font -- */

/**
 * Set the font configuration. Loads via CoreText if available,
 * falls back to size-based estimation. Returns true on success.
 *
 * @param term      Terminal instance.
 * @param family    Font family name (NULL or empty for system default).
 * @param size      Font size in points.
 * @param dpi_scale DPI scale factor (1.0 = standard, 2.0 = Retina).
 * @param ligatures Enable typographic ligatures.
 */
bool cocxycore_terminal_set_font(
    cocxycore_terminal* term,
    const char* family,
    float size,
    float dpi_scale,
    bool ligatures
);

/**
 * Get the current font metrics. Returns false if no font is set.
 */
bool cocxycore_terminal_get_font_metrics(
    const cocxycore_terminal* term,
    cocxycore_font_metrics* out
);

/* -- Frame building -- */

/**
 * Build a render frame from the current screen state.
 * Resolves colors, extracts codepoints, tracks dirty rows.
 * Creates the frame builder on first call. Returns true on success.
 */
bool cocxycore_terminal_build_frame(cocxycore_terminal* term);

/**
 * Get the render data for a cell at (row, col) from the last frame.
 */
void cocxycore_terminal_frame_cell(
    const cocxycore_terminal* term,
    uint16_t row, uint16_t col,
    cocxycore_render_cell* out
);

/**
 * Get the cursor render info.
 */
void cocxycore_terminal_frame_cursor(
    const cocxycore_terminal* term,
    cocxycore_render_cursor* out
);

/* -- Metal-oriented GPU data pipeline -- */

/** Metal-ready per-cell instance data. */
typedef struct {
    float x, y, width, height;
    float glyph_x, glyph_y, glyph_width, glyph_height;
    float u0, v0, u1, v1;
    cocxycore_rgba fg;
    cocxycore_rgba bg;
    uint32_t codepoint;
    uint8_t flags;
    uint8_t _pad[3];
} cocxycore_metal_cell;

/** Metal-ready cursor instance data. */
typedef struct {
    float x, y, width, height;
    uint8_t shape;
    bool visible;
    uint8_t _pad[2];
    cocxycore_rgba color;
} cocxycore_metal_cursor;

/** CPU-side atlas state for the Metal data path. */
typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t generation;
    bool dirty;
    uint8_t _pad[3];
} cocxycore_metal_atlas_info;

/**
 * Build the Metal-oriented GPU data pipeline.
 * Requires a font to be configured first.
 */
bool cocxycore_terminal_build_metal_frame(
    cocxycore_terminal* term,
    uint32_t atlas_width,
    uint32_t atlas_height
);

/** Get Metal-ready per-cell data from the last built frame. */
void cocxycore_terminal_metal_cell(
    const cocxycore_terminal* term,
    uint16_t row,
    uint16_t col,
    cocxycore_metal_cell* out
);

/** Get Metal-ready cursor data from the last built frame. */
void cocxycore_terminal_metal_cursor(
    const cocxycore_terminal* term,
    cocxycore_metal_cursor* out
);

/** Get the current atlas state. Returns false when Metal data was not built yet. */
bool cocxycore_terminal_metal_atlas_info(
    const cocxycore_terminal* term,
    cocxycore_metal_atlas_info* out
);

/**
 * Copy the atlas bitmap into buf.
 * Returns the total byte count required; output is truncated to buf_len.
 */
size_t cocxycore_terminal_metal_copy_atlas_bitmap(
    const cocxycore_terminal* term,
    uint8_t* buf,
    size_t buf_len
);

/** Mark the atlas as uploaded/clean. */
void cocxycore_terminal_metal_clear_atlas_dirty(cocxycore_terminal* term);

/* -- Clipboard / shell integration helpers -- */

/**
 * Encode an OSC 52 clipboard response.
 * Returns the total byte count required; output is truncated to buf_len.
 */
size_t cocxycore_terminal_encode_clipboard_response(
    uint8_t selection,
    const uint8_t* data,
    size_t len,
    uint8_t* buf,
    size_t buf_len
);

/** Get the number of shell integration env vars hosts should inject. */
uint32_t cocxycore_shell_integration_env_count(void);

/** Copy a shell integration env var name by index. */
size_t cocxycore_shell_integration_env_name(uint32_t index, uint8_t* buf, size_t buf_len);

/** Copy a shell integration env var value by index. */
size_t cocxycore_shell_integration_env_value(uint32_t index, uint8_t* buf, size_t buf_len);

#ifdef __cplusplus
}
#endif

#endif /* COCXYCORE_H */
