// Copyright (c) 2026 Said Arturo Lopez. MIT License.

#ifndef COCXY_TREE_SITTER_ABI_H
#define COCXY_TREE_SITTER_ABI_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t row;
    uint32_t column;
} CocxyTreeSitterPoint;

typedef struct {
    uint32_t start_byte;
    uint32_t old_end_byte;
    uint32_t new_end_byte;
    CocxyTreeSitterPoint start_point;
    CocxyTreeSitterPoint old_end_point;
    CocxyTreeSitterPoint new_end_point;
} CocxyTreeSitterInputEdit;

typedef struct {
    uint32_t context[4];
    const void *id;
    const void *tree;
} CocxyTreeSitterNode;

typedef struct {
    CocxyTreeSitterNode node;
    uint32_t index;
} CocxyTreeSitterQueryCapture;

typedef struct {
    uint32_t id;
    uint16_t pattern_index;
    uint16_t capture_count;
    const CocxyTreeSitterQueryCapture *captures;
} CocxyTreeSitterQueryMatch;

typedef enum {
    CocxyTreeSitterQueryErrorNone = 0,
    CocxyTreeSitterQueryErrorSyntax,
    CocxyTreeSitterQueryErrorNodeType,
    CocxyTreeSitterQueryErrorField,
    CocxyTreeSitterQueryErrorCapture,
    CocxyTreeSitterQueryErrorStructure,
    CocxyTreeSitterQueryErrorLanguage,
} CocxyTreeSitterQueryError;

#endif
