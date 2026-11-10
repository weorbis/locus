#include "LocusSQLCipherConfiguration.h"
#include "LocusSQLCipherSymbols.h"

// Upstream's amalgamation is vendored unmodified; its warnings are not ours to fix.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include "vendor/sqlite3.c"
#pragma clang diagnostic pop

#include "include/LocusSQLCipher.h"
