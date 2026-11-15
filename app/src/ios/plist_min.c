#include "plist_min.h"

#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "util/log.h"
#include "util/strbuf.h"

struct sc_plist_parser {
    const char *p;
    const char *end;
};

static void
skip_space(struct sc_plist_parser *ps) {
    while (ps->p < ps->end
            && (*ps->p == ' ' || *ps->p == '\n' || *ps->p == '\r'
                || *ps->p == '\t')) {
        ++ps->p;
    }
}

static bool
starts_with(struct sc_plist_parser *ps, const char *s) {
    size_t n = strlen(s);
    return (size_t) (ps->end - ps->p) >= n && !memcmp(ps->p, s, n);
}

// Skip prolog items: <?xml ...?>, <!DOCTYPE ...> and comments
static void
skip_prolog(struct sc_plist_parser *ps) {
    for (;;) {
        skip_space(ps);
        if (starts_with(ps, "<?") || starts_with(ps, "<!")) {
            const char *close = memchr(ps->p, '>', ps->end - ps->p);
            if (!close) {
                ps->p = ps->end;
                return;
            }
            ps->p = close + 1;
        } else {
            return;
        }
    }
}

// Read a tag "<name>", "<name/>" or "</name>" (attributes are skipped)
static bool
read_tag(struct sc_plist_parser *ps, char *name, size_t name_size,
         bool *closing, bool *empty) {
    skip_space(ps);
    if (ps->p >= ps->end || *ps->p != '<') {
        return false;
    }
    ++ps->p;
    *closing = false;
    if (ps->p < ps->end && *ps->p == '/') {
        *closing = true;
        ++ps->p;
    }
    size_t i = 0;
    while (ps->p < ps->end && *ps->p != '>' && *ps->p != '/'
            && *ps->p != ' ') {
        if (i + 1 >= name_size) {
            return false;
        }
        name[i++] = *ps->p++;
    }
    name[i] = '\0';
    const char *close = memchr(ps->p, '>', ps->end - ps->p);
    if (!close) {
        return false;
    }
    *empty = close > ps->p && close[-1] == '/';
    ps->p = close + 1;
    return i > 0;
}

// Read the text up to the closing tag, decoding XML entities
static char *
read_text(struct sc_plist_parser *ps, const char *name) {
    const char *start = ps->p;
    const char *lt = memchr(start, '<', ps->end - start);
    if (!lt) {
        return NULL;
    }
    size_t n = lt - start;
    char *text = malloc(n + 1);
    if (!text) {
        LOG_OOM();
        return NULL;
    }
    size_t j = 0;
    for (size_t i = 0; i < n; ++i) {
        if (start[i] == '&') {
            static const struct { const char *e; char c; } entities[] = {
                {"&amp;", '&'}, {"&lt;", '<'}, {"&gt;", '>'},
                {"&quot;", '"'}, {"&apos;", '\''},
            };
            bool found = false;
            for (size_t k = 0; k < ARRAY_LEN(entities); ++k) {
                size_t len = strlen(entities[k].e);
                if (n - i >= len && !memcmp(start + i, entities[k].e, len)) {
                    text[j++] = entities[k].c;
                    i += len - 1;
                    found = true;
                    break;
                }
            }
            if (!found) {
                text[j++] = '&';
            }
        } else {
            text[j++] = start[i];
        }
    }
    text[j] = '\0';
    ps->p = lt;

    char tag[32];
    bool closing, empty;
    if (!read_tag(ps, tag, sizeof(tag), &closing, &empty) || !closing
            || strcmp(tag, name)) {
        free(text);
        return NULL;
    }
    return text;
}

static struct sc_plist_node *
parse_value(struct sc_plist_parser *ps, unsigned depth);

static struct sc_plist_node *
new_node(enum sc_plist_type type) {
    struct sc_plist_node *node = calloc(1, sizeof(*node));
    if (!node) {
        LOG_OOM();
        return NULL;
    }
    node->type = type;
    return node;
}

static struct sc_plist_node *
parse_container(struct sc_plist_parser *ps, struct sc_plist_node *node,
                const char *name, unsigned depth) {
    bool is_dict = node->type == SC_PLIST_DICT;
    struct sc_plist_node **tail = &node->children;
    for (;;) {
        skip_space(ps);
        if (starts_with(ps, "</")) {
            char tag[32];
            bool closing, empty;
            if (!read_tag(ps, tag, sizeof(tag), &closing, &empty)
                    || strcmp(tag, name)) {
                goto error;
            }
            return node;
        }
        char *key = NULL;
        if (is_dict) {
            char tag[32];
            bool closing, empty;
            if (!read_tag(ps, tag, sizeof(tag), &closing, &empty) || closing
                    || strcmp(tag, "key")) {
                goto error;
            }
            key = empty ? strdup("") : read_text(ps, "key");
            if (!key) {
                goto error;
            }
        }
        struct sc_plist_node *child = parse_value(ps, depth + 1);
        if (!child) {
            free(key);
            goto error;
        }
        child->key = key;
        *tail = child;
        tail = &child->next;
    }

error:
    sc_plist_free(node);
    return NULL;
}

static struct sc_plist_node *
parse_value(struct sc_plist_parser *ps, unsigned depth) {
    if (depth > 16) {
        return NULL;
    }
    char tag[32];
    bool closing, empty;
    if (!read_tag(ps, tag, sizeof(tag), &closing, &empty) || closing) {
        return NULL;
    }

    if (!strcmp(tag, "dict") || !strcmp(tag, "array")) {
        bool dict = tag[0] == 'd';
        struct sc_plist_node *node =
            new_node(dict ? SC_PLIST_DICT : SC_PLIST_ARRAY);
        if (!node || empty) {
            return node;
        }
        return parse_container(ps, node, dict ? "dict" : "array", depth);
    }

    if (!strcmp(tag, "true") || !strcmp(tag, "false")) {
        struct sc_plist_node *node = new_node(SC_PLIST_BOOL);
        if (node) {
            node->integer = tag[0] == 't';
        }
        if (node && !empty) {
            // <true></true> is unusual but valid
            char t[32];
            if (!read_tag(ps, t, sizeof(t), &closing, &empty) || !closing) {
                sc_plist_free(node);
                return NULL;
            }
        }
        return node;
    }

    bool is_string = !strcmp(tag, "string");
    bool is_integer = !strcmp(tag, "integer");
    struct sc_plist_node *node = new_node(is_string ? SC_PLIST_STRING
                                        : is_integer ? SC_PLIST_INTEGER
                                        : SC_PLIST_OTHER);
    if (!node) {
        return NULL;
    }
    char *text = empty ? strdup("") : read_text(ps, tag);
    if (!text) {
        sc_plist_free(node);
        return NULL;
    }
    if (is_string) {
        node->string = text;
    } else {
        if (is_integer) {
            char *endptr;
            node->integer = strtoll(text, &endptr, 10);
            if (endptr == text) {
                free(text);
                sc_plist_free(node);
                return NULL;
            }
        }
        free(text);
    }
    return node;
}

struct sc_plist_node *
sc_plist_parse(const char *xml, size_t len) {
    struct sc_plist_parser ps = {.p = xml, .end = xml + len};
    skip_prolog(&ps);

    char tag[32];
    bool closing, empty;
    if (!read_tag(&ps, tag, sizeof(tag), &closing, &empty) || closing
            || strcmp(tag, "plist") || empty) {
        return NULL;
    }
    struct sc_plist_node *root = parse_value(&ps, 0);
    if (!root) {
        return NULL;
    }
    if (!read_tag(&ps, tag, sizeof(tag), &closing, &empty) || !closing
            || strcmp(tag, "plist")) {
        sc_plist_free(root);
        return NULL;
    }
    return root;
}

void
sc_plist_free(struct sc_plist_node *node) {
    while (node) {
        struct sc_plist_node *next = node->next;
        sc_plist_free(node->children);
        free(node->key);
        free(node->string);
        free(node);
        node = next;
    }
}

const struct sc_plist_node *
sc_plist_dict_get(const struct sc_plist_node *dict, const char *key) {
    if (!dict || dict->type != SC_PLIST_DICT) {
        return NULL;
    }
    for (const struct sc_plist_node *n = dict->children; n; n = n->next) {
        if (n->key && !strcmp(n->key, key)) {
            return n;
        }
    }
    return NULL;
}

int64_t
sc_plist_dict_get_int(const struct sc_plist_node *dict, const char *key,
                      int64_t def) {
    const struct sc_plist_node *n = sc_plist_dict_get(dict, key);
    if (n && (n->type == SC_PLIST_INTEGER || n->type == SC_PLIST_BOOL)) {
        return n->integer;
    }
    return def;
}

const char *
sc_plist_dict_get_string(const struct sc_plist_node *dict, const char *key) {
    const struct sc_plist_node *n = sc_plist_dict_get(dict, key);
    return n && n->type == SC_PLIST_STRING ? n->string : NULL;
}

static bool
append_escaped(struct sc_strbuf *buf, const char *s) {
    for (; *s; ++s) {
        bool ok;
        switch (*s) {
            case '&': ok = sc_strbuf_append_staticstr(buf, "&amp;"); break;
            case '<': ok = sc_strbuf_append_staticstr(buf, "&lt;"); break;
            case '>': ok = sc_strbuf_append_staticstr(buf, "&gt;"); break;
            default: ok = sc_strbuf_append_char(buf, *s); break;
        }
        if (!ok) {
            return false;
        }
    }
    return true;
}

char *
sc_plist_write_dict(const struct sc_plist_entry *entries, size_t count,
                    size_t *len) {
    struct sc_strbuf buf;
    if (!sc_strbuf_init(&buf, 512)) {
        LOG_OOM();
        return NULL;
    }
    bool ok = sc_strbuf_append_staticstr(&buf,
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        "<plist version=\"1.0\">\n<dict>\n");
    for (size_t i = 0; ok && i < count; ++i) {
        const struct sc_plist_entry *e = &entries[i];
        ok = sc_strbuf_append_staticstr(&buf, "\t<key>")
          && append_escaped(&buf, e->key)
          && sc_strbuf_append_staticstr(&buf, "</key>\n");
        if (!ok) {
            break;
        }
        if (e->type == SC_PLIST_ENTRY_STRING) {
            ok = sc_strbuf_append_staticstr(&buf, "\t<string>")
              && append_escaped(&buf, e->string)
              && sc_strbuf_append_staticstr(&buf, "</string>\n");
        } else {
            char number[32];
            snprintf(number, sizeof(number), "%" PRId64, e->integer);
            ok = sc_strbuf_append_staticstr(&buf, "\t<integer>")
              && sc_strbuf_append_str(&buf, number)
              && sc_strbuf_append_staticstr(&buf, "</integer>\n");
        }
    }
    ok = ok && sc_strbuf_append_staticstr(&buf, "</dict>\n</plist>\n");
    if (!ok) {
        LOG_OOM();
        free(buf.s);
        return NULL;
    }
    *len = buf.len;
    return buf.s;
}
