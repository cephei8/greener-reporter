#ifndef GREENER_REPORTER_GREENER_REPORTER_H
#define GREENER_REPORTER_GREENER_REPORTER_H

typedef struct greener_reporter greener_reporter_t;

typedef struct greener_reporter_session {
  const char *id;
} greener_reporter_session_t;

typedef struct greener_reporter_error {
  int code;
  int ingress_code;
  const char *message;
} greener_reporter_error_t;

greener_reporter_t *
greener_reporter_new(const char *endpoint, const char *api_key,
                     const greener_reporter_error_t **error);

void greener_reporter_delete(greener_reporter_t *reporter,
                             const greener_reporter_error_t **error);

void greener_reporter_report_error_pop(
    greener_reporter_t *reporter,
    const greener_reporter_error_t **error);

const greener_reporter_session_t *
greener_reporter_session_create(greener_reporter_t *reporter,
                                const char *session_id, const char *description,
                                const char *baggage, const char *labels,
                                const greener_reporter_error_t **error);

void greener_reporter_testcase_create(
    greener_reporter_t *reporter, const char *session_id,
    const char *testcase_name, const char *testcase_classname,
    const char *testcase_file, const char *testsuite, const char *status,
    const char *output, const char *baggage,
    const greener_reporter_error_t **error);

void greener_reporter_session_delete(
    const greener_reporter_session_t *session);

void greener_reporter_error_delete(const greener_reporter_error_t *error);

enum {
  GREENER_REPORTER_ERROR = 1,
  GREENER_REPORTER_ERROR_INVALID_ARGUMENT = 2,
  GREENER_REPORTER_ERROR_INGRESS = 3,
};

#endif // GREENER_REPORTER_GREENER_REPORTER_H
