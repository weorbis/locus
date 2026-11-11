# Locus SQLCipher source distribution

Both CocoaPods (`locus/SQLCipher`) and SwiftPM (`LocusSQLCipher`) compile
`LocusSQLCipher.c`. The Swift module may be named `locus` or `Locus`; the C
implementation and database format are identical.

This vendors current stable SQLCipher Community Edition **4.20.0**, SQLite
3.54.1, from tag `v4.20.0`, commit
`355d4db92d3404e71faa8088d071a71d767807f4`:
<https://github.com/sqlcipher/sqlcipher/tree/355d4db92d3404e71faa8088d071a71d767807f4>.
The BSD license is in `LICENSE.md`. CocoaPods includes it in acknowledgements;
SwiftPM host applications must reproduce it in their third-party notices.

## Packaging decision

SQLCipher ended CocoaPods publishing in 4.11.0. Its official Swift package
4.20.0 distributes an XCFramework with unprefixed SQLite symbols, so combining
that binary with a separate CocoaPods dependency cannot provide identical,
isolated linkage. Host apps may also use system SQLite, sqflite, or another
SQLCipher library. Locus must not replace those libraries' SQLite functions.

The source wrapper therefore prefixes all exported C symbols, including globals
and `xoshiro_next`, with `locus_` (private `LocusSQLCipherSymbols.h`). The only
public header, `include/LocusSQLCipher.h`, hand-declares the ~25 functions
Locus uses under their prefixed names with `LOCUS_SQLITE_*` constants, so
importing the CocoaPods `locus` module or the SwiftPM `LocusSQLCipher` module
never exposes unprefixed SQLite declarations or macros to a host. The wrapper
`.c` includes that header after the amalgamation, so the compiler checks every
prototype against the implementation. It never changes host compiler flags or
system SQLite imports. Only the wrapper C file is compiled; the amalgamation is
included, never compiled a second time, and its warnings are silenced because
the file is vendored with one patch (below).

`LocusSQLCipherConfiguration.h` contains the official Apple source-integration
flags, including CommonCrypto, codec, in-memory temporary storage, thread safety,
and SQLCipher initialization/shutdown. It also mirrors all nondefault SQLite
feature settings reported by `sqlite3_compileoption_get` in the official
4.20.0 XCFramework (both macOS and iOS arm64). The manifest itself exposes only
a binary target, so its unpublished compiler/optimization flags cannot be
reproduced. `NDEBUG=1` is also passed at compilation in both manifests and the
podspec so Apple's precompiled system modules see the same assertion setting.
JSON functions remain enabled for history queries.

References:

- <https://github.com/sqlcipher/SQLCipher.swift/blob/4.20.0/Package.swift>
- <https://www.zetetic.net/sqlcipher/sqlcipher-apple-community/>
- <https://www.zetetic.net/sqlcipher/sqlcipher-apple-integrators/>
- <https://www.zetetic.net/blog/2025/10/08/sqlcipher-4.11.0-release/>

## Updating SQLCipher

This is a reproducible source snapshot, not a dependency on the discontinued
4.10 CocoaPod. Review new stable upstream releases with each Locus release;
update both package paths together. Never fetch moving upstream sources while
building a consuming app.

1. Check out the new stable SQLCipher tag, record its peeled commit, and run
   `./configure --with-tempstore=yes --disable-readline --disable-tcl` followed
   by `make sqlite3.c`. Native C tools and Tcl/JimTcl are needed only to refresh
   the vendored source. Apple's system Tcl can fail to create temporary files
   inside a sandbox; compiling the supplied `autosetup/jimsh0.c` as `jimsh0`
   before configuring uses the upstream bootstrap interpreter instead.
2. Copy `sqlite3.c` to `vendor/`. Retain the upstream license.
3. Compare the official XCFramework's `sqlite3_compileoption_get` output and
   update the shared configuration header. Compile an unprefixed object with
   that header, for example:

   ```sh
   clang -Os -include LocusSQLCipherConfiguration.h -c vendor/sqlite3.c -o /tmp/locus-sqlcipher.o
   nm -gU /tmp/locus-sqlcipher.o
   ```

4. Regenerate `LocusSQLCipherSymbols.h` from every C identifier starting with
   `sqlite3` or `sqlcipher` in upstream's `sqlite3.h` plus every global
   definition reported by `nm -gU` (remove Mach-O's leading underscore),
   each as `#define name locus_name`. Include non-SQLite names such as
   `xoshiro_next`. Review the exported-symbol list on device and simulator
   slices with `nm -gU`; all definitions must have the `locus_` prefix. If
   Locus starts using another SQLite function, declare it in
   `include/LocusSQLCipher.h`.
5. Run the existing helper suites under both module names and build the Flutter
   example with CocoaPods and SwiftPM. Check plaintext migration, encrypted
   reopening, failed-key preservation, WAL recovery, and native JSON/history
   queries by hand. Also link a host using system SQLite and verify both
   libraries independently. Measure a release simulator/device host before
   and after the update; source size is not application download size.

## Local patch

`sqlcipher_atexit` and `sqlcipher_fini` in `vendor/sqlite3.c` are empty (marked
`LOCUS PATCH`). Upstream frees SQLCipher's heap and mutexes at process exit even
while other threads are still using it, which crashes the process. The OS
reclaims that memory, and `sqlite3_shutdown()` still runs the full cleanup.
Re-apply this patch when updating the amalgamation.

