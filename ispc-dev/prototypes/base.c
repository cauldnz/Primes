// Scalar C reference, same algorithm shape (1-bit odds-only, clear from p*p)
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <time.h>
#define LIMIT 1000000
static double now(){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+1e-9*t.tv_nsec;}
int main(){
  int nbits=LIMIT/2, nw=(nbits+63)>>6; long passes=0; double s=now(); int q=(int)sqrt(LIMIT);
  while(now()-s<5.0){
    uint64_t*w=calloc(nw,8);
    for(int i=1;2*i+1<=q;i++){ if((w[i>>6]>>(i&63))&1)continue; int p=2*i+1;
      for(int j=(p*p)>>1;j<nbits;j+=p) w[j>>6]|=1ULL<<(j&63); }
    if(!passes){int c=1;for(int i=1;i<nbits;i++)c+=!((w[i>>6]>>(i&63))&1); fprintf(stderr,"count=%d\n",c);}
    free(w); passes++;
  }
  printf("c-ref;%ld;%f;1\n",passes,now()-s);
}
