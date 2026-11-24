/*
 * EasyTier caphelper — setuid-root helper applying file caps to easytier-core on DSM.
 * Unsigned SPKs reject conf/privilege tool[].capabilities; DSM accepts a 4550 root helper.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/xattr.h>
#include <unistd.h>

#ifndef O_NOFOLLOW
#define O_NOFOLLOW 0x20000
#endif

#define PKG_TARGET "/var/packages/EasyTier/target"
#define PKG_BASENAME "EasyTier"
#define CORE_NAME "easytier-core"
#define HELPER_TMP ".easytier-cap-stage"

#ifndef EASYTIER_CORE_SHA256
#define EASYTIER_CORE_SHA256 "0000000000000000000000000000000000000000000000000000000000000000"
#endif

/* Linux VFS cap v2: cap_net_admin (bit 12) + cap_net_raw (bit 13), effective+permitted. */
static const unsigned char k_cap_blob[] = {
	0x02, 0x00, 0x00, 0x01,
	0x00, 0x00, 0x30, 0x00,
	0x00, 0x00, 0x00, 0x00,
};

static void emit_fail(const char *what)
{
	printf("EasyTierCapHelper: RESULT=fail WHAT=%s\n", what ? what : "unknown");
}

static void emit_ok(void)
{
	printf("EasyTierCapHelper: RESULT=ok\n");
}

static int secure_env(void)
{
	if (geteuid() != 0) {
		emit_fail("euid_not_root");
		return -1;
	}
	if (setresuid(0, 0, 0) != 0) {
		emit_fail("setresuid");
		return -1;
	}
	umask(022);
	clearenv();
	return 0;
}

static int read_exe_gid(gid_t *out_gid)
{
	struct stat st;
	if (fstatat(AT_FDCWD, "/proc/self/exe", &st, AT_SYMLINK_NOFOLLOW) != 0) {
		emit_fail("stat_exe");
		return -1;
	}
	if (st.st_uid != 0) {
		emit_fail("exe_not_root_owned");
		return -1;
	}
	if (st.st_gid == 0) {
		emit_fail("exe_gid_root");
		return -1;
	}
	*out_gid = st.st_gid;
	return 0;
}

/* ---- SHA-256 ---- */
static const uint32_t k256[64] = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc0e17b22, 0xe1d4b6e2, 0xf27c7c5d, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

#define rotr(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

typedef struct {
	uint8_t data[64];
	uint32_t datalen;
	uint64_t bitlen;
	uint32_t state[8];
} sha256_ctx;

static void sha256_transform(sha256_ctx *ctx, const uint8_t *data)
{
	uint32_t m[64], a, b, c, d, e, f, g, h, t1, t2;
	int i, j;
	for (i = 0, j = 0; i < 16; ++i, j += 4)
		m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j + 1] << 16) |
		       ((uint32_t)data[j + 2] << 8) | ((uint32_t)data[j + 3]);
	for (i = 16; i < 64; ++i)
		m[i] = m[i - 16] + m[i - 7] + (rotr(m[i - 15], 7) ^ rotr(m[i - 15], 18) ^ (m[i - 15] >> 3)) +
		       (rotr(m[i - 2], 17) ^ rotr(m[i - 2], 19) ^ (m[i - 2] >> 10));
	a = ctx->state[0];
	b = ctx->state[1];
	c = ctx->state[2];
	d = ctx->state[3];
	e = ctx->state[4];
	f = ctx->state[5];
	g = ctx->state[6];
	h = ctx->state[7];
	for (i = 0; i < 64; ++i) {
		t1 = h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ ((~e) & g)) + k256[i] + m[i];
		t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
		h = g;
		g = f;
		f = e;
		e = d + t1;
		d = c;
		c = b;
		b = a;
		a = t1 + t2;
	}
	ctx->state[0] += a;
	ctx->state[1] += b;
	ctx->state[2] += c;
	ctx->state[3] += d;
	ctx->state[4] += e;
	ctx->state[5] += f;
	ctx->state[6] += g;
	ctx->state[7] += h;
}

static void sha256_init(sha256_ctx *ctx)
{
	ctx->datalen = 0;
	ctx->bitlen = 0;
	ctx->state[0] = 0x6a09e667;
	ctx->state[1] = 0xbb67ae85;
	ctx->state[2] = 0x3c6ef372;
	ctx->state[3] = 0xa54ff53a;
	ctx->state[4] = 0x510e527f;
	ctx->state[5] = 0x9b05688c;
	ctx->state[6] = 0x1f83d9ab;
	ctx->state[7] = 0x5be0cd19;
}

static void sha256_update(sha256_ctx *ctx, const uint8_t *data, size_t len)
{
	size_t i;
	for (i = 0; i < len; ++i) {
		ctx->data[ctx->datalen] = data[i];
		ctx->datalen++;
		if (ctx->datalen == 64) {
			sha256_transform(ctx, ctx->data);
			ctx->bitlen += 512;
			ctx->datalen = 0;
		}
	}
}

static void sha256_final(sha256_ctx *ctx, uint8_t hash[32])
{
	uint32_t i;

	i = ctx->datalen;
	if (ctx->datalen < 56) {
		ctx->data[i++] = 0x80;
		while (i < 56)
			ctx->data[i++] = 0x00;
	} else {
		ctx->data[i++] = 0x80;
		while (i < 64)
			ctx->data[i++] = 0x00;
		sha256_transform(ctx, ctx->data);
		memset(ctx->data, 0, 56);
	}
	ctx->bitlen += ctx->datalen * 8;
	ctx->data[63] = (uint8_t)(ctx->bitlen);
	ctx->data[62] = (uint8_t)(ctx->bitlen >> 8);
	ctx->data[61] = (uint8_t)(ctx->bitlen >> 16);
	ctx->data[60] = (uint8_t)(ctx->bitlen >> 24);
	ctx->data[59] = (uint8_t)(ctx->bitlen >> 32);
	ctx->data[58] = (uint8_t)(ctx->bitlen >> 40);
	ctx->data[57] = (uint8_t)(ctx->bitlen >> 48);
	ctx->data[56] = (uint8_t)(ctx->bitlen >> 56);
	sha256_transform(ctx, ctx->data);
	for (i = 0; i < 4; ++i) {
		hash[i] = (uint8_t)((ctx->state[0] >> (24 - i * 8)) & 0xff);
		hash[i + 4] = (uint8_t)((ctx->state[1] >> (24 - i * 8)) & 0xff);
		hash[i + 8] = (uint8_t)((ctx->state[2] >> (24 - i * 8)) & 0xff);
		hash[i + 12] = (uint8_t)((ctx->state[3] >> (24 - i * 8)) & 0xff);
		hash[i + 16] = (uint8_t)((ctx->state[4] >> (24 - i * 8)) & 0xff);
		hash[i + 20] = (uint8_t)((ctx->state[5] >> (24 - i * 8)) & 0xff);
		hash[i + 24] = (uint8_t)((ctx->state[6] >> (24 - i * 8)) & 0xff);
		hash[i + 28] = (uint8_t)((ctx->state[7] >> (24 - i * 8)) & 0xff);
	}
}

static void sha256_hexdigest(sha256_ctx *ctx, char *out65)
{
	uint8_t hash[32];
	static const char hexd[] = "0123456789abcdef";
	int i;

	sha256_final(ctx, hash);
	for (i = 0; i < 32; ++i) {
		out65[i * 2] = hexd[(hash[i] >> 4) & 0xf];
		out65[i * 2 + 1] = hexd[hash[i] & 0xf];
	}
	out65[64] = '\0';
}

static int hex_eq_ci(const char *a, const char *b)
{
	int i;
	for (i = 0; i < 64; ++i) {
		char ca = a[i];
		char cb = b[i];
		if (ca >= 'A' && ca <= 'Z')
			ca = (char)(ca + 32);
		if (cb >= 'A' && cb <= 'Z')
			cb = (char)(cb + 32);
		if (ca != cb)
			return 0;
	}
	return 1;
}

static int hash_fd(int fd, char *out65)
{
	sha256_ctx ctx;
	char buf[65536];

	sha256_init(&ctx);
	for (;;) {
		ssize_t nr = read(fd, buf, sizeof(buf));
		if (nr < 0)
			return -1;
		if (nr == 0)
			break;
		sha256_update(&ctx, (const uint8_t *)buf, (size_t)nr);
	}
	sha256_hexdigest(&ctx, out65);
	return 0;
}

static int caps_match_fd(int fd)
{
	unsigned char got[32];
	ssize_t n = fgetxattr(fd, "security.capability", got, sizeof(got));
	if (n != (ssize_t)sizeof(k_cap_blob))
		return 0;
	return memcmp(got, k_cap_blob, sizeof(k_cap_blob)) == 0;
}

static int harden_dirat(int parent_fd, const char *name, gid_t gid)
{
	int fd = openat(parent_fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
	DIR *dir;
	struct dirent *ent;

	if (fd < 0)
		return -1;
	if (fchown(fd, 0, gid) != 0 || fchmod(fd, 0755) != 0) {
		close(fd);
		return -1;
	}
	dir = fdopendir(fd);
	if (!dir) {
		close(fd);
		return -1;
	}
	while ((ent = readdir(dir)) != NULL) {
		struct stat st;
		if (ent->d_name[0] == '.' &&
		    (ent->d_name[1] == '\0' || (ent->d_name[1] == '.' && ent->d_name[2] == '\0')))
			continue;
		if (fstatat(fd, ent->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0)
			continue;
		if (S_ISDIR(st.st_mode))
			(void)harden_dirat(fd, ent->d_name, gid);
	}
	closedir(dir);
	return 0;
}

static int core_already_ok(int bin_fd, gid_t gid)
{
	struct stat st;
	char hex[65];
	int fd;

	if (fstatat(bin_fd, CORE_NAME, &st, AT_SYMLINK_NOFOLLOW) != 0)
		return 0;
	if (st.st_uid != 0 || st.st_gid != gid || (st.st_mode & 07777) != 0750)
		return 0;
	fd = openat(bin_fd, CORE_NAME, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
	if (fd < 0)
		return 0;
	if (hash_fd(fd, hex) != 0) {
		close(fd);
		return 0;
	}
	if (!hex_eq_ci(hex, EASYTIER_CORE_SHA256)) {
		close(fd);
		return 0;
	}
	if (!caps_match_fd(fd)) {
		close(fd);
		return 0;
	}
	close(fd);
	return 1;
}

static int copy_hash_stream(int in_fd, int out_fd, char *hex_out)
{
	sha256_ctx ctx;
	char buf[65536];

	sha256_init(&ctx);
	for (;;) {
		ssize_t nr = read(in_fd, buf, sizeof(buf));
		if (nr < 0)
			return -1;
		if (nr == 0)
			break;
		if (write(out_fd, buf, (size_t)nr) != nr)
			return -1;
		sha256_update(&ctx, (const uint8_t *)buf, (size_t)nr);
	}
	sha256_hexdigest(&ctx, hex_out);
	return 0;
}

static int apply_core_caps(int bin_fd, gid_t gid)
{
	int in_fd = -1;
	int tmp_fd = -1;
	char hex[65];

	in_fd = openat(bin_fd, CORE_NAME, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
	if (in_fd < 0) {
		emit_fail("open_core");
		return -1;
	}
	(void)unlinkat(bin_fd, HELPER_TMP, 0);
	tmp_fd = openat(bin_fd, HELPER_TMP, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
	if (tmp_fd < 0) {
		close(in_fd);
		emit_fail("temp_open");
		return -1;
	}
	if (copy_hash_stream(in_fd, tmp_fd, hex) != 0) {
		close(in_fd);
		close(tmp_fd);
		(void)unlinkat(bin_fd, HELPER_TMP, 0);
		emit_fail("copy_hash");
		return -1;
	}
	close(in_fd);
	in_fd = -1;

	if (!hex_eq_ci(hex, EASYTIER_CORE_SHA256)) {
		close(tmp_fd);
		(void)unlinkat(bin_fd, HELPER_TMP, 0);
		emit_fail("hash_mismatch");
		return -1;
	}
	if (fchown(tmp_fd, 0, gid) != 0) {
		close(tmp_fd);
		(void)unlinkat(bin_fd, HELPER_TMP, 0);
		emit_fail("fchown");
		return -1;
	}
	if (fchmod(tmp_fd, 0750) != 0) {
		close(tmp_fd);
		(void)unlinkat(bin_fd, HELPER_TMP, 0);
		emit_fail("fchmod");
		return -1;
	}
	if (fsetxattr(tmp_fd, "security.capability", k_cap_blob, sizeof(k_cap_blob), 0) != 0) {
		close(tmp_fd);
		(void)unlinkat(bin_fd, HELPER_TMP, 0);
		emit_fail("fsetxattr");
		return -1;
	}
	if (fsync(tmp_fd) != 0) {
		close(tmp_fd);
		(void)unlinkat(bin_fd, HELPER_TMP, 0);
		emit_fail("fsync_file");
		return -1;
	}
	if (renameat(bin_fd, HELPER_TMP, bin_fd, CORE_NAME) != 0) {
		close(tmp_fd);
		(void)unlinkat(bin_fd, HELPER_TMP, 0);
		emit_fail("rename");
		return -1;
	}
	close(tmp_fd);
	if (fsync(bin_fd) != 0) {
		emit_fail("fsync_dir");
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	gid_t pkg_gid;
	char *resolved;
	const char *base;
	int tgt;
	int bin_fd;

	(void)argv;
	if (argc != 1) {
		emit_fail("argc");
		return 1;
	}
	if (secure_env() != 0)
		return 1;
	if (read_exe_gid(&pkg_gid) != 0)
		return 1;

	resolved = realpath(PKG_TARGET, NULL);
	if (!resolved) {
		emit_fail("realpath_target");
		return 1;
	}
	base = strrchr(resolved, '/');
	base = base ? base + 1 : resolved;
	if (strcmp(base, PKG_BASENAME) != 0) {
		free(resolved);
		emit_fail("target_basename");
		return 1;
	}
	free(resolved);

	tgt = open(PKG_TARGET, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
	if (tgt < 0) {
		emit_fail("open_target");
		return 1;
	}
	if (fchown(tgt, 0, pkg_gid) != 0 || fchmod(tgt, 0755) != 0) {
		close(tgt);
		emit_fail("harden_target");
		return 1;
	}
	if (harden_dirat(tgt, "bin", pkg_gid) != 0) {
		close(tgt);
		emit_fail("harden_bin");
		return 1;
	}
	bin_fd = openat(tgt, "bin", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
	if (bin_fd < 0) {
		close(tgt);
		emit_fail("open_bin");
		return 1;
	}
	(void)harden_dirat(bin_fd, "helper", pkg_gid);

	if (core_already_ok(bin_fd, pkg_gid)) {
		close(bin_fd);
		close(tgt);
		emit_ok();
		return 0;
	}
	if (apply_core_caps(bin_fd, pkg_gid) != 0) {
		close(bin_fd);
		close(tgt);
		return 1;
	}
	close(bin_fd);
	close(tgt);
	emit_ok();
	return 0;
}