/* Fun Linux FFI test helper library.
 * Build with:  gcc -O2 -fPIC -shared -o libffitest.so libffitest.c
 * Exercises every FFI feature path supported by src/lib/lffi.pas:
 *   int/double/float/string returns and args, 64-bit 'l', callbacks
 *   ('c') of every type, void returns, repeated callbacks, mixed regs.
 */

#include <string.h>

/* ---- plain scalar calls ------------------------------------------------- */
double five(void){ return 5.0; }
double summ(double a, double b){ return a + b; }
double ident(double a){ return a; }
int    addi(int a, int b){ return a + b; }
float  fsum(float a, float b){ return a + b; }
float  fdbl(float a){ return a * 2.0f; }
double dfromf(float a){ return (double)a * 2.0; }

/* mixed register classes: int(GPR) double(XMM) int(GPR) -> double */
double mixsum(int a, double b, int c){ return a + b + c; }

/* ---- 64-bit int ('l') --------------------------------------------------- */
long long addll(long long a, long long b){ return a + b; }
long long big64(void){ return 0x100000005LL; }   /* 4294967301 */
long long passll(long long x){ return x; }
long long applyll(long long x, long long(*cb)(long long)){ return cb(x); }

/* ---- strings ('s') ------------------------------------------------------ */
int strl(const char* s){ int n=0; while(s && s[n]) n++; return n; }
int applyStr(const char* s, int(*cb)(const char*)){ return cb(s); }

/* callbacks return a string */
char* make(int x, char*(*cb)(int)){ static char buf[256]; char* r = cb(x);
  strncpy(buf, r ? r : "", 255); buf[255] = 0; return buf; }

/* ---- int / double callbacks --------------------------------------------- */
int apply1(int x, int(*cb)(int)){ return cb(x); }
double dapply(double x, double(*cb)(double)){ return cb(x); }
int sumvia(int n, int(*cb)(int,int)){ int i,s=0; for(i=0;i<n;i++) s+=cb(i,i+1); return s; }
int cb2(int a,int b,int(*cb)(int,int)){ return cb(a,b); }
int twice_cb(int x, int(*fa)(int), int(*fb)(int)){ return fa(x)+fb(x); }

/* void callback called n times, no return */
void walk(int n, void(*cb)(int)){ int i; for(i=0;i<n;i++) cb(i); }

/* double callback called repeatedly, accumulated in C */
double acc(double x, int n, double(*cb)(double)){ int i; double s=0;
  for(i=0;i<n;i++) s += cb(x+i); return s; }

/* float callback */
float fc(float x, float(*cb)(float)){ return cb(x); }

/* zero-arg callbacks */
int fire0i(int(*cb)(void)){ return cb(); }
void fire0(void(*cb)(void)){ cb(); }

/* ---- OUT / INOUT pointer args ('p' with a bare `var`) ------------------- */
int setout(int *p, int v){ if(!p) return -1; *p = v; return 0; }
int addout(int *p, int v){ if(!p) return -2; *p += v; return 0; }
