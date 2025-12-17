/* Test enum */

enum Color {
    RED,
    GREEN,
    BLUE
};

enum Status {
    OK = 0,
    ERROR = -1,
    PENDING = 100
};

int main() {
    int c;
    int s;

    c = RED;
    if (c != 0) return 1;

    c = GREEN;
    if (c != 1) return 2;

    c = BLUE;
    if (c != 2) return 3;

    s = OK;
    if (s != 0) return 4;

    s = ERROR;
    if (s != -1) return 5;

    s = PENDING;
    if (s != 100) return 6;

    return 0;
}
