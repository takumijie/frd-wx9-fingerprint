// SPDX-License-Identifier: GPL-2.0
// 只读探测 v2：用 ioremap_cache 映射 ACPI NVS，读取 GFPS/GFPI。
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/io.h>
#include <linux/types.h>

#define GNVS_PHYS 0x8FB83298ULL
#define GNVS_LEN  0x800
#define OFF_GFPS  0x465
#define OFF_GFPI  0x469

static int __init gnvsread2_init(void)
{
	void __iomem *base;
	u32 gfps, gfpi;

	base = ioremap_cache(GNVS_PHYS, GNVS_LEN);
	if (!base) {
		pr_err("gnvsread2: ioremap_cache failed\n");
		return -ENOMEM;
	}

	gfps = readl(base + OFF_GFPS);
	gfpi = readl(base + OFF_GFPI);

	pr_info("gnvsread2: GFPS=0x%08X group=%u offset=%u\n",
		gfps, (gfps >> 16) & 0xff, gfps & 0xffff);
	pr_info("gnvsread2: GFPI=0x%08X group=%u offset=%u\n",
		gfpi, (gfpi >> 16) & 0xff, gfpi & 0xffff);

	iounmap(base);
	return 0;
}

static void __exit gnvsread2_exit(void) {}

module_init(gnvsread2_init);
module_exit(gnvsread2_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Read-only ACPI GNVS GFPI/GFPS probe v2");
