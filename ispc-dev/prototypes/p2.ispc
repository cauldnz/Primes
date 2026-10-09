export void * uniform worker(void * uniform arg) {
    uniform int * uniform p = (uniform int * uniform)arg;
    unmasked { *p = reduce_add(programIndex) + 1000 * programCount; }
    return NULL;
}
extern "C" uniform int pthread_create(uniform int64 * uniform tid, void * uniform attr, void * uniform fn, void * uniform arg);
extern "C" uniform int pthread_join(uniform int64 tid, void * uniform * uniform ret);
export uniform int main() {
    uniform int r = 0;
    worker(&r); print("direct: %\n", r);
    uniform int r2 = 0; uniform int64 tid;
    pthread_create(&tid, NULL, (void * uniform)worker, &r2);
    pthread_join(tid, NULL);
    print("thread: %\n", r2);
    return 0;
}
