/* ASOS example: cross-compiled program for NanoPi (aarch64).
 * Prints the board model, kernel and SoC temperature. */
#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>

static void print_file(const char *label, const char *path, double scale)
{
	FILE *f = fopen(path, "r");
	char buf[256] = {0};
	if (!f) return;
	if (fgets(buf, sizeof buf, f)) {
		buf[strcspn(buf, "\n")] = 0;
		if (scale > 0) {
			double v = 0;
			sscanf(buf, "%lf", &v);
			printf("%-12s %.1f\n", label, v / scale);
		} else {
			printf("%-12s %s\n", label, buf);
		}
	}
	fclose(f);
}

int main(void)
{
	struct utsname u;
	uname(&u);
	printf("Hello from ASOS cross-compiler!\n");
	printf("%-12s %s %s (%s)\n", "kernel", u.sysname, u.release, u.machine);
	print_file("model", "/proc/device-tree/model", 0);
	print_file("soc temp,C", "/sys/class/thermal/thermal_zone0/temp", 1000.0);
	return 0;
}
