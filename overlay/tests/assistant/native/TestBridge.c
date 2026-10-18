// Fault injection for the Swift wrapper using the exact pinned C declarations.
#include "TestBridge.h"
#include <string.h>

struct RpPairingFileHandle { uint8_t *bytes; uintptr_t len; };
struct AdapterHandle { int tag; };
struct RsdHandshakeHandle { int tag; };
struct RemoteServerHandle { int tag; };
struct LocationSimulationHandle { struct RemoteServerHandle *borrowed; };
static int failure, live, clients, bad_order, sets, mounts, mounted = 1;
static struct IdeviceFfiError *make_error(void) { live++; return calloc(1, sizeof(struct IdeviceFfiError)); }
void assistant_test_reset(int value) { failure = value; bad_order = 0; sets = 0; mounts = 0; mounted = 1; }
int assistant_test_mount_calls(void) { return mounts; }
void assistant_test_set_mounted(int value) { mounted = value; }
int assistant_test_live_count(void) { return live; }
int assistant_test_bad_free_order(void) { return bad_order; }
int assistant_test_set_calls(void) { return sets; }
void idevice_error_free(struct IdeviceFfiError *e) { if (e) { live--; free(e); } }
void idevice_data_free(uint8_t *bytes, uintptr_t len) { if (bytes) { live--; free(bytes); } }

struct IdeviceFfiError *rp_pairing_file_from_bytes(const uint8_t *bytes, uintptr_t len, struct RpPairingFileHandle **out) {
    if (failure == 1) return make_error();
    struct RpPairingFileHandle *p = calloc(1, sizeof(*p));
    p->bytes = calloc(len + 1, 1); memcpy(p->bytes, bytes, len); p->len = len;
    *out = p; live++; return NULL;
}
void rp_pairing_file_free(struct RpPairingFileHandle *p) { if (p) { free(p->bytes); free(p); live--; } }
struct IdeviceFfiError *rp_pairing_file_to_bytes(struct RpPairingFileHandle *p, uint8_t **out, uintptr_t *len) {
    if (failure == 8) return make_error();
    *out = calloc(p->len + 1, 1); memcpy(*out, p->bytes, p->len); *len = p->len; live++;
    if (failure == 9) { char *key = strstr((char *)*out, "host-one"); if (key) key[0] = 'x'; }
    return NULL;
}
struct IdeviceFfiError *tunnel_create_rppairing(const idevice_sockaddr *addr, idevice_socklen_t len,
    const char *host, struct RpPairingFileHandle *pairing, const char *(*pin)(void *), void *context,
    struct AdapterHandle **adapter, struct RsdHandshakeHandle **handshake) {
    if (failure == 10) { *adapter = NULL; *handshake = NULL; return NULL; }
    *adapter = calloc(1, sizeof(**adapter)); *handshake = calloc(1, sizeof(**handshake)); live += 2;
    return failure == 2 ? make_error() : NULL;
}
void adapter_free(struct AdapterHandle *p) { if (p) { live--; free(p); } }
void rsd_handshake_free(struct RsdHandshakeHandle *p) { if (p) { live--; free(p); } }
struct IdeviceFfiError *remote_server_connect_rsd(struct AdapterHandle *p, struct RsdHandshakeHandle *h, struct RemoteServerHandle **out) {
    if (failure == 11) { *out = NULL; return NULL; }
    if (failure == 3) return make_error();
    *out = calloc(1, sizeof(**out)); live++; return NULL;
}
void remote_server_free(struct RemoteServerHandle *p) { if (p) { if (clients) bad_order++; live--; free(p); } }
struct IdeviceFfiError *location_simulation_new(struct RemoteServerHandle *server, struct LocationSimulationHandle **out) {
    if (failure == 4) return make_error();
    if (failure == 5) { *out = NULL; return NULL; }
    *out = calloc(1, sizeof(**out)); (*out)->borrowed = server; live++; clients++; return NULL;
}
void location_simulation_free(struct LocationSimulationHandle *p) { if (p) { clients--; live--; free(p); } }
struct IdeviceFfiError *location_simulation_set(struct LocationSimulationHandle *p, double latitude, double longitude) {
    sets++; return failure == 6 ? make_error() : NULL;
}
struct IdeviceFfiError *location_simulation_clear(struct LocationSimulationHandle *p) { return failure == 7 ? make_error() : NULL; }

struct ImageMounterHandle { int tag; };
struct LockdowndClientHandle { int tag; };
struct Cryptex1AssetsHandle { int tag; };
struct IdeviceFfiError *image_mounter_connect_rsd(struct AdapterHandle *p, struct RsdHandshakeHandle *h, struct ImageMounterHandle **out) {
    if (failure == 12) return make_error();
    if (failure == 13) { *out = NULL; return NULL; }
    *out = calloc(1, sizeof(**out)); live++; return NULL;
}
void image_mounter_free(struct ImageMounterHandle *p) { if (p) { live--; free(p); } }
struct IdeviceFfiError *image_mounter_query_developer_mode_status(struct ImageMounterHandle *p, int *out) {
    if (failure == 14) return make_error();
    *out = failure == 15 ? 0 : 1; return NULL;
}
struct IdeviceFfiError *image_mounter_lookup_image(struct ImageMounterHandle *p, const char *type, uint8_t **out, size_t *len) {
    if (failure == 16) return make_error();
    if (!mounted) { struct IdeviceFfiError *e = make_error(); e->code = 20; return e; }
    *out = calloc(1,1); *len = 1; live++; return NULL;
}
struct IdeviceFfiError *lockdownd_connect_rsd(struct AdapterHandle *p, struct RsdHandshakeHandle *h, struct LockdowndClientHandle **out) {
    if (failure == 17) return make_error();
    if (failure == 18) { *out = NULL; return NULL; }
    *out = calloc(1,sizeof(**out)); live++; return NULL;
}
void lockdownd_client_free(struct LockdowndClientHandle *p) { if (p) { live--; free(p); } }
struct IdeviceFfiError *lockdownd_get_value(struct LockdowndClientHandle *p, const char *key, const char *domain, plist_t *out) {
    if (failure == 19) return make_error();
    *out = calloc(1,1); live++; return NULL;
}
void plist_get_uint_val(plist_t p, uint64_t *value) { *value = failure == 20 ? 0 : 123; }
void plist_free(plist_t p) { if (p) { live--; free(p); } }
struct IdeviceFfiError *image_mounter_mount_personalized_rsd(struct ImageMounterHandle *c, struct AdapterHandle *a,
    struct RsdHandshakeHandle *h, const uint8_t *im, size_t il, const uint8_t *tc, size_t tl,
    const uint8_t *bm, size_t bl, const void *info, uint64_t chip) {
    mounts++; if (failure == 21) return make_error(); if (failure != 22) mounted = 1; return NULL;
}
struct IdeviceFfiError *cryptexd_installed_ddi(struct AdapterHandle *a, struct RsdHandshakeHandle *h, struct InstalledCryptexC **out) {
    if (failure == 23) return make_error();
    if (mounted) { *out = calloc(1,sizeof(**out)); live++; } else *out = NULL;
    return NULL;
}
void cryptexd_free_installed_cryptex(struct InstalledCryptexC *p) { if (p) { live--; free(p); } }
struct IdeviceFfiError *cryptex1_assets_load(const char *path, struct Cryptex1AssetsHandle **out) {
    if (failure == 24) return make_error();
    if (failure == 25) { *out = NULL; return NULL; }
    *out = calloc(1,sizeof(**out)); live++; return NULL;
}
void cryptex1_assets_free(struct Cryptex1AssetsHandle *p) { if (p) { live--; free(p); } }
struct IdeviceFfiError *cryptexd_install_ddi(struct AdapterHandle *a, struct RsdHandshakeHandle *h, struct Cryptex1AssetsHandle *assets, struct InstalledCryptexC **out) {
    mounts++; if (failure == 26) return make_error(); if (failure != 22) mounted = 1; return NULL;
}
