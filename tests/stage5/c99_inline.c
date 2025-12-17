// Test C99 inline function specifier

inline int square(int x) {
    return x * x;
}

static inline int cube(int x) {
    return x * x * x;
}

int main(void) {
    int a = square(3);  // 9
    int b = cube(2);    // 8

    if (a == 9 && b == 8) return 0;
    return 1;
}
