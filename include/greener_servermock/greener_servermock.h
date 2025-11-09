#ifndef GREENER_SERVERMOCK_GREENER_SERVERMOCK_H
#define GREENER_SERVERMOCK_GREENER_SERVERMOCK_H

#include <stdint.h>

typedef struct greener_servermock greener_servermock_t;

typedef struct greener_servermock_error {
  const char *message;
} greener_servermock_error_t;

greener_servermock_t *greener_servermock_new();

void greener_servermock_delete(greener_servermock_t *ctx,
                               const greener_servermock_error_t **error);

void greener_servermock_serve(greener_servermock_t *ctx,
                              const char *responses,
                              const greener_servermock_error_t **error);

int greener_servermock_get_port(greener_servermock_t *ctx,
                                const greener_servermock_error_t **error);

void greener_servermock_assert(greener_servermock_t *ctx,
                               const char *calls,
                               const greener_servermock_error_t **error);

void greener_servermock_fixture_names(
    greener_servermock_t *ctx, const char ***names, uint32_t *num_names,
    const greener_servermock_error_t **error);

void greener_servermock_fixture_calls(
    greener_servermock_t *ctx, const char *fixture_name,
    const char **calls, const greener_servermock_error_t **error);

void greener_servermock_fixture_responses(
    greener_servermock_t *ctx, const char *fixture_name,
    const char **responses, const greener_servermock_error_t **error);

void greener_servermock_error_delete(
    const greener_servermock_error_t *error);

#endif // GREENER_SERVERMOCK_GREENER_SERVERMOCK_H
