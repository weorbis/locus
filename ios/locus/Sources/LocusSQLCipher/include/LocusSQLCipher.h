#ifndef LOCUS_SQLCIPHER_H
#define LOCUS_SQLCIPHER_H

// The SQLCipher surface Locus uses. Every symbol is namespaced so it cannot
// collide with the system SQLite or another SQLite copy in the host app.
// LocusSQLCipher.c includes this header to check each prototype against the
// vendored implementation.

typedef struct locus_sqlite3 locus_sqlite3;
typedef struct locus_sqlite3_stmt locus_sqlite3_stmt;
typedef struct locus_sqlite3_value locus_sqlite3_value;
typedef struct locus_sqlite3_context locus_sqlite3_context;
typedef long long int locus_sqlite3_int64;
typedef void (*locus_sqlite3_destructor_type)(void *);

#define LOCUS_SQLITE_OK 0
#define LOCUS_SQLITE_ERROR 1
#define LOCUS_SQLITE_BUSY 5
#define LOCUS_SQLITE_ROW 100
#define LOCUS_SQLITE_DONE 101
#define LOCUS_SQLITE_OPEN_READONLY 0x00000001
#define LOCUS_SQLITE_OPEN_READWRITE 0x00000002
#define LOCUS_SQLITE_OPEN_CREATE 0x00000004
#define LOCUS_SQLITE_UTF8 1
#define LOCUS_SQLITE_DETERMINISTIC 0x000000800

int locus_sqlite3_open_v2(const char *filename, locus_sqlite3 **ppDb, int flags, const char *zVfs);
int locus_sqlite3_close(locus_sqlite3 *db);
int locus_sqlite3_key(locus_sqlite3 *db, const void *pKey, int nKey);
int locus_sqlite3_busy_timeout(locus_sqlite3 *db, int ms);
int locus_sqlite3_exec(locus_sqlite3 *db, const char *sql, int (*callback)(void *, int, char **, char **), void *arg, char **errmsg);
const char *locus_sqlite3_errmsg(locus_sqlite3 *db);

int locus_sqlite3_prepare_v2(locus_sqlite3 *db, const char *zSql, int nByte, locus_sqlite3_stmt **ppStmt, const char **pzTail);
int locus_sqlite3_step(locus_sqlite3_stmt *stmt);
int locus_sqlite3_finalize(locus_sqlite3_stmt *stmt);

int locus_sqlite3_bind_int(locus_sqlite3_stmt *stmt, int index, int value);
int locus_sqlite3_bind_int64(locus_sqlite3_stmt *stmt, int index, locus_sqlite3_int64 value);
int locus_sqlite3_bind_null(locus_sqlite3_stmt *stmt, int index);
int locus_sqlite3_bind_text(locus_sqlite3_stmt *stmt, int index, const char *value, int length, void (*destructor)(void *));

int locus_sqlite3_column_int(locus_sqlite3_stmt *stmt, int column);
locus_sqlite3_int64 locus_sqlite3_column_int64(locus_sqlite3_stmt *stmt, int column);
const unsigned char *locus_sqlite3_column_text(locus_sqlite3_stmt *stmt, int column);
int locus_sqlite3_column_bytes(locus_sqlite3_stmt *stmt, int column);

int locus_sqlite3_create_function_v2(
    locus_sqlite3 *db,
    const char *zFunctionName,
    int nArg,
    int eTextRep,
    void *pApp,
    void (*xFunc)(locus_sqlite3_context *, int, locus_sqlite3_value **),
    void (*xStep)(locus_sqlite3_context *, int, locus_sqlite3_value **),
    void (*xFinal)(locus_sqlite3_context *),
    void (*xDestroy)(void *));
void *locus_sqlite3_user_data(locus_sqlite3_context *context);
const unsigned char *locus_sqlite3_value_text(locus_sqlite3_value *value);
int locus_sqlite3_value_bytes(locus_sqlite3_value *value);
void locus_sqlite3_result_error(locus_sqlite3_context *context, const char *message, int length);
void locus_sqlite3_result_int64(locus_sqlite3_context *context, locus_sqlite3_int64 value);
void locus_sqlite3_result_null(locus_sqlite3_context *context);

#endif
