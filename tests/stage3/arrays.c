/* Test array and pointer indexing */

int main() {
    int a[3];
    a[0] = 1;
    a[1] = 2;
    a[2] = 3;

    if (a[0] + a[2] != 4) return 1;

    int x;
    int *p;
    x = 5;
    p = &x;
    if (p[0] != 5) return 2;

    return 0;
}

