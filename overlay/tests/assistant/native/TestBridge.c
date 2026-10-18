// Fault injection for the Swift wrapper using the exact pinned C declarations.
#include "TestBridge.h"
#include <string.h>

struct RpPairingFileHandle { uint8_t *bytes; uintptr_t len; };
struct AdapterHandle { int tag; };
struct RsdHandshakeHandle { int tag; };
struct RemoteServerHandle { int tag; };
struct LocationSimulationHandle { struct RemoteServerHandle *borrowed; };
static int failure, live, clients, bad_order, sets;
static struct IdeviceFfiError *make_error(void) { live++; return (struct IdeviceFfiError *)malloc(1); }
void assistant_test_reset(int value) { failure = value; bad_order = 0; sets = 0; }
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
