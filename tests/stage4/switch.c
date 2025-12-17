/* Test switch statement */

int test_switch(int x) {
    int result;
    result = 0;
    switch (x) {
        case 1:
            result = 10;
            break;
        case 2:
            result = 20;
            break;
        case 3:
            result = 30;
            break;
        default:
            result = 99;
    }
    return result;
}

int main() {
    if (test_switch(1) != 10) return 1;
    if (test_switch(2) != 20) return 2;
    if (test_switch(3) != 30) return 3;
    if (test_switch(5) != 99) return 4;
    return 0;
}
