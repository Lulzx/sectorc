// Test C99 _Bool type

_Bool check(int x) {
    if (x > 0) return 1;
    return 0;
}

int main(void) {
    _Bool a = 1;
    _Bool b = 0;
    _Bool c = check(5);
    _Bool d = check(-3);

    if (a && c && !b && !d)
        return 0;
    return 1;
}
