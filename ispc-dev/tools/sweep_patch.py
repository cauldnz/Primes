import sys
p=sys.argv[1]; s=open(p).read()
i=s.index('static void self_test(uniform int dense_max) {'); j=s.index('\n}\n',i)+3
new='''static void self_test(uniform int dense_max) {
    for (uniform int64 n = 1; n < 400000; n = (n < 5000) ? n + 1 : n + 997) {
        uniform Sieve s;
        sieve_create(&s, n, dense_max);
        run_sieve(&s);
        print("% %\\n", n, count_primes(&s));
        sieve_destroy(&s);
    }
    exit(0);
}
'''
open(sys.argv[2],'w').write(s[:i]+new+s[j:])
