#ifndef SC_PLIST_MIN_H
#define SC_PLIST_MIN_H

#include "common.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Minimal XML property list support, only what the usbmuxd protocol needs:
// dict, array, key, string, integer, true and false (other values are kept as
// SC_PLIST_OTHER). Written from scratch for Lente (no libplist or libusbmuxd).

enum sc_plist_type {
    SC_PLIST_DICT,
    SC_PLIST_ARRAY,
    SC_PLIST_STRING,
    SC_PLIST_INTEGER,
    SC_PLIST_BOOL,
    SC_PLIST_OTHER,
};

struct sc_plist_node {
    enum sc_plist_type type;
    char *key; // set when the node is a value inside a dict
    char *string; // SC_PLIST_STRING
    int64_t integer; // SC_PLIST_INTEGER and SC_PLIST_BOOL (0 or 1)
    struct sc_plist_node *children; // SC_PLIST_DICT and SC_PLIST_ARRAY
    struct sc_plist_node *next; // next sibling
};

// Parse an XML plist document. Return NULL on error.
struct sc_plist_node *
sc_plist_parse(const char *xml, size_t len);

void
sc_plist_free(struct sc_plist_node *node);

// Value for a key in a dict, or NULL
const struct sc_plist_node *
sc_plist_dict_get(const struct sc_plist_node *dict, const char *key);

// Integer value for a key in a dict, or def if absent or not an integer
int64_t
sc_plist_dict_get_int(const struct sc_plist_node *dict, const char *key,
                      int64_t def);

// String value for a key in a dict, or NULL
const char *
sc_plist_dict_get_string(const struct sc_plist_node *dict, const char *key);

enum sc_plist_entry_type {
    SC_PLIST_ENTRY_STRING,
    SC_PLIST_ENTRY_INTEGER,
};

struct sc_plist_entry {
    const char *key;
    enum sc_plist_entry_type type;
    const char *string;
    int64_t integer;
};

// Write a flat dict as an XML plist document. The result must be freed.
char *
sc_plist_write_dict(const struct sc_plist_entry *entries, size_t count,
                    size_t *len);

#endif
