/* Portable symlink check used by Tools.File_IO. */
#ifdef _WIN32
int vericlaw_is_symlink(const char *path) {
    (void)path;
    return 0; /* Windows MinGW lacks lstat/S_ISLNK; symlinks unsupported */
}
#else
#include <sys/stat.h>
int vericlaw_is_symlink(const char *path) {
    struct stat st;
    return (lstat(path, &st) == 0 && S_ISLNK(st.st_mode)) ? 1 : 0;
}
#endif
