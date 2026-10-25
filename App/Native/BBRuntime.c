#include "BBRuntime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <Python.h>

/* The runtime's probe.c main(), renamed by patches/runtime/0003-probe-entry.patch. Weak: the app
 * still builds and shows a clear message when the runtime library is not linked. */
extern int bb_probe_main(int argc, char **argv) __attribute__((weak_import));

int bb_runtime_available(void) { return bb_probe_main != NULL; }

static void set_err(char *err, size_t n, const char *what) {
    if (err && n) snprintf(err, n, "%s", what);
}

/* Fetches the active Python exception as text into err and clears it. */
static void python_error(char *err, size_t n, const char *prefix) {
    PyObject *exc = PyErr_GetRaisedException();
    const char *text = "unknown error";
    PyObject *str = exc ? PyObject_Str(exc) : NULL;
    if (str) { const char *u = PyUnicode_AsUTF8(str); if (u) text = u; }
    if (err && n) snprintf(err, n, "%s: %s", prefix, text);
    Py_XDECREF(str);
    Py_XDECREF(exc);
    PyErr_Clear();
}

static int python_start(const char *home, const char *stdlib, const char *scripts, char *err, size_t n) {
    if (Py_IsInitialized()) return 0;
    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    PyStatus status = PyConfig_SetBytesString(&config, &config.home, home);
    if (PyStatus_Exception(status)) goto fail;
    config.module_search_paths_set = 1;
    char dynload[2048], bridge[2048];
    snprintf(dynload, sizeof dynload, "%s/lib-dynload", stdlib);
    snprintf(bridge, sizeof bridge, "%s/../..", scripts); /* bb_pipeline.py sits in bbpy/, beside runtime/ */
    const char *paths[] = {stdlib, dynload, scripts, bridge};
    for (size_t i = 0; i < sizeof paths / sizeof *paths; ++i) {
        wchar_t *w = Py_DecodeLocale(paths[i], NULL);
        if (!w) { set_err(err, n, "Python path could not be decoded"); PyConfig_Clear(&config); return -1; }
        status = PyWideStringList_Append(&config.module_search_paths, w);
        PyMem_RawFree(w);
        if (PyStatus_Exception(status)) goto fail;
    }
    status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        if (err && n) snprintf(err, n, "Python did not start: %s", status.err_msg ? status.err_msg : "?");
        return -1;
    }
    return 0;
fail:
    if (err && n) snprintf(err, n, "Python configuration failed: %s", status.err_msg ? status.err_msg : "?");
    PyConfig_Clear(&config);
    return -1;
}

static char **probe_argv;
static int probe_argc;

int bb_runtime_prepare(const char *python_home, const char *stdlib, const char *scripts_dir,
                       const char *game_dir, const char *data_dir, const char *fps,
                       const char *log_path, char *err, size_t errlen) {
    if (!bb_probe_main) { set_err(err, errlen, "The game runtime is not linked into this build."); return -1; }
    if (log_path && *log_path) {
        /* The runtime prints to stdout and stderr: the app's Log tab reads this file. */
        freopen(log_path, "w", stdout);
        freopen(log_path, "a", stderr);
        setvbuf(stdout, NULL, _IONBF, 0);
    }
    if (python_start(python_home, stdlib, scripts_dir, err, errlen) != 0) return -2;

    PyObject *module = PyImport_ImportModule("bb_pipeline");
    if (!module) { python_error(err, errlen, "bb_pipeline"); return -3; }
    PyObject *list = PyObject_CallMethod(module, "prepare", "(ssss)", scripts_dir, game_dir, data_dir, fps);
    Py_DECREF(module);
    if (!list) { python_error(err, errlen, "Preparing the game failed"); return -4; }
    if (!PyList_Check(list)) { Py_DECREF(list); set_err(err, errlen, "bb_pipeline.prepare returned no argument list"); return -5; }

    Py_ssize_t count = PyList_Size(list);
    char **argv = calloc((size_t)count + 2, sizeof *argv);
    if (!argv) { Py_DECREF(list); set_err(err, errlen, "out of memory"); return -6; }
    argv[0] = strdup("bb-probe");
    for (Py_ssize_t i = 0; i < count; ++i) {
        const char *s = PyUnicode_AsUTF8(PyList_GetItem(list, i));
        argv[i + 1] = strdup(s ? s : "");
    }
    Py_DECREF(list);
    probe_argv = argv;
    probe_argc = (int)count + 1;
    return 0;
}

int bb_runtime_run(char *err, size_t errlen) {
    if (!bb_probe_main || !probe_argv) { set_err(err, errlen, "The game was not prepared."); return -1; }
    int rc = bb_probe_main(probe_argc, probe_argv);
    if (rc != 0 && err && errlen) snprintf(err, errlen, "The game exited with code %d.", rc);
    return rc;
}
