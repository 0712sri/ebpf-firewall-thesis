CLANG   := clang
BPFTOOL := bpftool
ARCH    := $(shell uname -m | sed 's/x86_64/x86/' | sed 's/aarch64/arm64/')
KERN_HEADERS := /usr/include/$(shell uname -m)-linux-gnu

BPF_CFLAGS := -O2 -g -Wall -target bpf \
    -D__TARGET_ARCH_$(ARCH) \
    -I$(KERN_HEADERS) -I/usr/include

SRCS  := $(wildcard src/*.bpf.c)
OBJS  := $(patsubst src/%.bpf.c, obj/%.bpf.o, $(SRCS))
HDRS  := src/fw_common.h src/fw_rules.h

# Rule-set sizes: rules/config_a_N.rules -> src/rules/fw_rules_N.h -> obj/nN/firewall_b{0,1,2}.bpf.o
RULESETS := 10 100 1000
FW_PROGS := firewall_b0 firewall_b1 firewall_b2
NOBJS    := $(foreach n,$(RULESETS),$(foreach b,$(FW_PROGS),obj/n$(n)/$(b).bpf.o))
SKELS := $(patsubst src/%.bpf.c, obj/%.skel.h, $(SRCS))

.PHONY: all skels clean rules

all: $(OBJS) $(NOBJS) obj/b1_loader
	@echo "\n✓ Built:"; ls -lh obj/

skels: $(SKELS)

obj/%.bpf.o: src/%.bpf.c $(HDRS) | obj
	$(CLANG) $(BPF_CFLAGS) -c $< -o $@

# one object per rule-set size; the size is chosen with -DFW_RULES_FILE
define BUILD_RULESET
obj/n$(1)/%.bpf.o: src/%.bpf.c $(HDRS) src/rules/fw_rules_$(1).h
	@mkdir -p obj/n$(1)
	$$(CLANG) $$(BPF_CFLAGS) -DFW_RULES_FILE='"rules/fw_rules_$(1).h"' -c $$< -o $$@
endef
$(foreach n,$(RULESETS),$(eval $(call BUILD_RULESET,$(n))))

# regenerate the rule sets (A) and translate them for B (only needed when the generator changes)
rules:
	python3 scripts/rule_generator.py $(RULESETS)
	for n in $(RULESETS); do python3 scripts/rule_compiler.py rules/config_a_$$n.rules; done

obj/%.skel.h: obj/%.bpf.o
	$(BPFTOOL) gen skeleton $< > $@

obj/b1_loader: src/b1_loader.c | obj
	gcc -O2 -Wall -o $@ $< -lbpf -lelf -lz
	@echo "  built $@"

obj:
	mkdir -p obj

clean:
	rm -rf obj