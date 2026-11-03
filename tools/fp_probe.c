// fp_probe.c — 独立探针：复位 + 发 A8 命令 + 观察 IRQ + 读原始 MISO
// 用法: sudo ./fp_probe <assert_level 0|1> <cs_high 0|1>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>
#include <linux/gpio.h>

#define RESET_LINE 259
#define IRQ_LINE   79

static int req_output(int chip, uint32_t line, int value)
{
	struct gpio_v2_line_request req = { 0 };
	req.num_lines = 1;
	req.offsets[0] = line;
	req.config.flags = GPIO_V2_LINE_FLAG_OUTPUT;
	req.config.num_attrs = 1;
	req.config.attrs[0].attr.id = GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES;
	req.config.attrs[0].attr.values = value;
	req.config.attrs[0].mask = 1;
	strcpy(req.consumer, "fp_probe");
	if (ioctl(chip, GPIO_V2_GET_LINE_IOCTL, &req) < 0) {
		perror("GPIO output request");
		return -1;
	}
	return req.fd;
}

static int req_input(int chip, uint32_t line)
{
	struct gpio_v2_line_request req = { 0 };
	req.num_lines = 1;
	req.offsets[0] = line;
	req.config.flags = GPIO_V2_LINE_FLAG_INPUT;
	strcpy(req.consumer, "fp_probe-irq");
	if (ioctl(chip, GPIO_V2_GET_LINE_IOCTL, &req) < 0) {
		perror("GPIO input request");
		return -1;
	}
	return req.fd;
}

static int set_val(int fd, int v)
{
	struct gpio_v2_line_values val = { .bits = v, .mask = 1 };
	return ioctl(fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &val);
}

static int get_val(int fd)
{
	struct gpio_v2_line_values val = { .mask = 1 };
	if (ioctl(fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &val) < 0)
		return -1;
	return val.bits & 1;
}

int main(int argc, char **argv)
{
	int assert_level = argc > 1 ? atoi(argv[1]) : 0;
	int cs_high = argc > 2 ? atoi(argv[2]) : 1;
	int release_level = !assert_level;
	uint8_t hdr[4], body[6] = { 0xA8, 0x03, 0x00, 0x00, 0x00, 0xFF };
	uint8_t rx[64] = { 0 };
	int chip, ofd, ifd, sfd, i, hi_count = 0, transitions = 0, last = -1;

	hdr[0] = 0xA0; hdr[1] = 0x06; hdr[2] = 0x00; hdr[3] = 0xA6;

	chip = open("/dev/gpiochip0", O_RDWR);
	if (chip < 0) { perror("gpiochip0"); return 1; }
	ofd = req_output(chip, RESET_LINE, release_level);
	if (ofd < 0) return 1;
	ifd = req_input(chip, IRQ_LINE);
	if (ifd < 0) return 1;

	printf("== assert_level=%d cs_high=%d ==\n", assert_level, cs_high);
	printf("初始 IRQ 电平: %d\n", get_val(ifd));

	set_val(ofd, assert_level);
	usleep(300000);
	set_val(ofd, release_level);
	usleep(600000);
	printf("复位后 IRQ 电平: %d\n", get_val(ifd));

	sfd = open("/dev/spidev1.0", O_RDWR);
	if (sfd < 0) { perror("spidev1.0"); return 1; }
	{
		uint8_t mode = SPI_MODE_0 | (cs_high ? SPI_CS_HIGH : 0);
		uint32_t speed = 1000000;
		uint8_t bits = 8;
		ioctl(sfd, SPI_IOC_WR_MODE, &mode);
		ioctl(sfd, SPI_IOC_WR_MAX_SPEED_HZ, &speed);
		ioctl(sfd, SPI_IOC_WR_BITS_PER_WORD, &bits);
	}

	for (i = 0; i < 2; i++) {
		struct spi_ioc_transfer x = { 0 };
		x.tx_buf = (unsigned long)(i == 0 ? hdr : body);
		x.len = (uint32_t)(i == 0 ? 4 : 6);
		x.speed_hz = 1000000;
		x.bits_per_word = 8;
		if (ioctl(sfd, SPI_IOC_MESSAGE(1), &x) < 0)
			perror("spi write");
		if (i == 0)
			usleep(2000);
	}

	for (i = 0; i < 600; i++) {
		int v = get_val(ifd);
		if (v != last) {
			transitions++;
			last = v;
		}
		if (v == 1)
			hi_count++;
		usleep(1000);
	}
	printf("IRQ 采样 600ms: 变跳=%d 高电平次数=%d 最终=%d\n",
	       transitions, hi_count, last);

	{
		struct spi_ioc_transfer r = { 0 };
		r.rx_buf = (unsigned long)rx;
		r.len = sizeof rx;
		r.speed_hz = 1000000;
		r.bits_per_word = 8;
		if (ioctl(sfd, SPI_IOC_MESSAGE(1), &r) < 0)
			perror("spi read");
	}
	printf("MISO 前 32 字节: ");
	for (i = 0; i < 32; i++)
		printf("%02X ", rx[i]);
	printf("\n");
	return 0;
}
