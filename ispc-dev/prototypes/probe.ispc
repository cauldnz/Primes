// Probe: can ISPC own main, timing, stdout and threads with zero C source?
struct timespec { int64 tv_sec; int64 tv_nsec; };
extern "C" uniform int clock_gettime(uniform int clk, uniform timespec * uniform ts);
extern "C" uniform int64 write(uniform int fd, void * uniform buf, uniform int64 n);
extern "C" uniform int pthread_create(uniform int64 * uniform tid, void * uniform attr,
                                      void * uniform fn, void * uniform arg);
extern "C" uniform int pthread_join(uniform int64 tid, void * uniform * uniform ret);

export void * uniform worker(void * uniform arg) {
    uniform int * uniform p = (uniform int * uniform)arg;
    varying int v = programIndex;          // SIMD lanes inside a pthread
    *p = reduce_add(v);
    return NULL;
}

export uniform int main() {
    uniform timespec ts;
    clock_gettime(1, &ts);
    uniform int64 tid;
    uniform int result = 0;
    pthread_create(&tid, NULL, (void * uniform)worker, &result);
    pthread_join(tid, NULL);
    uniform int8 msg[32];
    uniform int n = 0;
    msg[n++] = 111; msg[n++] = 107; msg[n++] = 32;
    msg[n++] = 48 + (result / 10) % 10; msg[n++] = 48 + result % 10;
    msg[n++] = 10;
    write(1, msg, n);
    return 0;
}
