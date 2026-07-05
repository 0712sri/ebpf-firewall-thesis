CLANG   := clang-18
BPFTOOL := bpftool
ARCH    := $(shell uname -m | sed 's/x86_64/x86/' | sed 's/aarch64/arm64/')
KERN_HEADERS := /usr/include/$(shell uname -m)-linux-gnu

BPF_CFLAGS := -O2 -g -Wall -target bpf \
    -D__TARGET_ARCH_$(ARCH) \
    -I$(KERN_HEADERS) -I/usr/include

SRCS  := $(wildcard src/*.bpf.c)
OBJS  := $(patsubst src/%.bpf.c, obj/%.bpf.o, $(SRCS))
SKELS := $(patsubst src/%.bpf.c, obj/%.skel.h, $(SRCS))

.PHONY: all skels clean

all: $(OBJS) obj/b1_loader
	@echo "\n✓ Built:"; ls -lh obj/

skels: $(SKELS)

obj/%.bpf.o: src/%.bpf.c | obj
	$(CLANG) $(BPF_CFLAGS) -c $< -o $@

obj/%.skel.h: obj/%.bpf.o
	$(BPFTOOL) gen skeleton $< > $@

obj/b1_loader: src/b1_loader.c | obj
	gcc -O2 -Wall -o $@ $< -lbpf -lelf -lz
	@echo "  built $@"

obj:
	mkdir -p obj

clean:
	rm -rf obj