// Test C99 for-loop declarations

int main(void) {
    int sum = 0;

    // C99 style: declare loop variable in for statement
    for (int i = 0; i < 5; i = i + 1) {
        sum = sum + i;
    }

    // 0+1+2+3+4 = 10
    if (sum == 10) return 0;
    return 1;
}
