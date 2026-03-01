/*
 * POSIX stub functions for Windows (MinGW) builds.
 *
 * openlog/syslog and setrlimit are POSIX-only.  The Ada code guards
 * their runtime use with OS detection, but the linker still needs the
 * symbols because the declarations use Ada's Import pragma.  These
 * no-op stubs satisfy the linker on Windows without changing any Ada
 * source.
 *
 * The #ifdef _WIN32 guard means this file is a no-op on Linux/macOS,
 * where libc supplies the real implementations.
 */

#ifdef _WIN32

/* ---- syslog ---- */

void openlog(const char *ident, int option, int facility)
{
    (void)ident; (void)option; (void)facility;
}

/* syslog is variadic; Ada calls it as (priority, "%s", message). */
void syslog(int priority, const char *fmt, const char *msg)
{
    (void)priority; (void)fmt; (void)msg;
}

/* ---- resource limits ---- */

struct rlimit_stub { unsigned long rlim_cur; unsigned long rlim_max; };

int setrlimit(int resource, const struct rlimit_stub *rlim)
{
    (void)resource; (void)rlim;
    return 0;  /* pretend success */
}

#endif /* _WIN32 */
