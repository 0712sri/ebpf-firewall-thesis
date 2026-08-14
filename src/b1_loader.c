// SPDX-License-Identifier: GPL-2.0
// src/b1_loader.c
// Loads firewall_b1.bpf.o, wires tail-call jump table, attaches to TC ingress.
//
// Build: gcc -O2 -Wall -o obj/b1_loader src/b1_loader.c -lbpf -lelf -lz
// Run:   sudo ./obj/b1_loader eth0
// Stop:  sudo ./obj/b1_loader eth0 detach

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <bpf/libbpf.h>
#include <bpf/bpf.h>
#include <linux/if_link.h>
#include <net/if.h>
#include <linux/pkt_sched.h>

static volatile int running = 1;
static void handle_sig(int sig) { running = 0; }

static int tc_attach(int ifindex, int prog_fd)
{
    DECLARE_LIBBPF_OPTS(bpf_tc_hook, hook,
        .ifindex      = ifindex,
        .attach_point = BPF_TC_INGRESS,
    );
    DECLARE_LIBBPF_OPTS(bpf_tc_opts, opts,
        .handle   = 1,
        .priority = 1,
        .prog_fd  = prog_fd,
    );
    bpf_tc_hook_create(&hook);
    int err = bpf_tc_attach(&hook, &opts);
    if (err) {
        fprintf(stderr, "bpf_tc_attach failed: %s\n", strerror(-err));
        return err;
    }
    return 0;
}

static int tc_detach(int ifindex)
{
    DECLARE_LIBBPF_OPTS(bpf_tc_hook, hook,
        .ifindex      = ifindex,
        .attach_point = BPF_TC_INGRESS,
    );
    bpf_tc_hook_destroy(&hook);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <iface> [detach]\n", argv[0]);
        return 1;
    }

    const char *iface = argv[1];
    int ifindex = if_nametoindex(iface);
    if (!ifindex) {
        fprintf(stderr, "Interface '%s' not found\n", iface);
        return 1;
    }

    if (argc == 3 && strcmp(argv[2], "detach") == 0) {
        tc_detach(ifindex);
        printf("Detached from %s\n", iface);
        return 0;
    }

    struct bpf_object *obj = bpf_object__open("obj/firewall_b1.bpf.o");
    if (libbpf_get_error(obj)) {
        fprintf(stderr, "Failed to open BPF object\n");
        return 1;
    }

    if (bpf_object__load(obj)) {
        fprintf(stderr, "Failed to load BPF object\n");
        return 1;
    }

    struct bpf_program *prog_input   = bpf_object__find_program_by_name(obj, "chain_input");
    struct bpf_program *prog_forward = bpf_object__find_program_by_name(obj, "chain_forward");
    struct bpf_program *prog_custom  = bpf_object__find_program_by_name(obj, "chain_custom");

    if (!prog_input || !prog_forward || !prog_custom) {
        fprintf(stderr, "Failed to find BPF programs\n");
        return 1;
    }

    int fd_input   = bpf_program__fd(prog_input);
    int fd_forward = bpf_program__fd(prog_forward);
    int fd_custom  = bpf_program__fd(prog_custom);

    printf("  chain_input   fd=%d\n", fd_input);
    printf("  chain_forward fd=%d\n", fd_forward);
    printf("  chain_custom  fd=%d\n", fd_custom);

    struct bpf_map *jump_map = bpf_object__find_map_by_name(obj, "chain_jump_table");
    if (!jump_map) {
        fprintf(stderr, "Failed to find chain_jump_table map\n");
        return 1;
    }

    int map_fd = bpf_map__fd(jump_map);
    int key, err;

    key = 1;
    err = bpf_map_update_elem(map_fd, &key, &fd_forward, BPF_ANY);
    if (err) { fprintf(stderr, "Failed to set jump[1]: %s\n", strerror(-err)); return 1; }

    key = 2;
    err = bpf_map_update_elem(map_fd, &key, &fd_custom, BPF_ANY);
    if (err) { fprintf(stderr, "Failed to set jump[2]: %s\n", strerror(-err)); return 1; }

    printf("  chain_jump_table wired: [1]=forward [2]=custom\n");

    err = tc_attach(ifindex, fd_input);
    if (err) return 1;

    printf("B1 attached to %s ingress\n", iface);
    printf("  Press Ctrl+C to detach and exit\n\n");

    signal(SIGINT,  handle_sig);
    signal(SIGTERM, handle_sig);

    while (running) sleep(1);

    tc_detach(ifindex);
    bpf_object__close(obj);
    printf("\n✓ Detached from %s\n", iface);
    return 0;
}
