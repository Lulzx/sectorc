/* Test function calls */

int add(int a, int b) {
    return a + b;
}

int factorial(int n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

int main() {
    int r;

    /* Simple function call */
    r = add(3, 4);
    if (r != 7) return 1;

    /* Recursive function */
    r = factorial(5);
    if (r != 120) return 2;

    return 0;
}
