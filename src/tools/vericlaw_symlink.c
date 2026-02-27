/* Portable symlink check used by Tools.File_IO. */
#include <sys/stat.h>

int vericlaw_is_symlink(const char *path) {
    struct stat st;
    return (lstat(path, &st) == 0 && S_ISLNK(st.st_mode)) ? 1 : 0;
}
