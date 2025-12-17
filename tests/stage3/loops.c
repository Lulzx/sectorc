/* Test loop constructs */

int main() {
    int i;
    int sum;

    /* While loop */
    sum = 0;
    i = 1;
    while (i <= 10) {
        sum = sum + i;
        i = i + 1;
    }
    if (sum != 55) return 1;

    /* For loop */
    sum = 0;
    for (i = 1; i <= 10; i = i + 1) {
        sum = sum + i;
    }
    if (sum != 55) return 2;

    return 0;
}
