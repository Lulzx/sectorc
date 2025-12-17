/* Test arithmetic operations */

int main() {
    int a;
    int b;
    int c;

    a = 10;
    b = 3;

    /* Addition */
    c = a + b;
    if (c != 13) return 1;

    /* Subtraction */
    c = a - b;
    if (c != 7) return 2;

    /* Multiplication */
    c = a * b;
    if (c != 30) return 3;

    /* Division */
    c = a / b;
    if (c != 3) return 4;

    /* Modulo */
    c = a % b;
    if (c != 1) return 5;

    return 0;
}
