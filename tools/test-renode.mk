TEST_UPDATE_VERSION?=2
WOLFBOOT_VERSION?=0
TMP?=/tmp
RENODE_UART?=$(TMP)/wolfboot.uart
RENODE_LOG?=$(TMP)/wolfboot.log
RENODE_PIDFILE?=$(TMP)/renode.pid


RENODE_PORT=55155
RENODE_OPTIONS=--pid-file=$(RENODE_PIDFILE)
RENODE_OPTIONS+=--disable-xwt -P $(RENODE_PORT)
RENODE_CONFIG=tools/renode/stm32f4_discovery_wolfboot.resc
POFF=131067

EXPVER=tools/test-expect-version/test-expect-version
RENODE_EXPVER=$(EXPVER) $(RENODE_UART)
RENODE_BINASSEMBLE=tools/bin-assemble/bin-assemble

ifneq ("$(wildcard $(WOLFBOOT_ROOT)/tools/keytools/keygen)","")
	KEYGEN_TOOL=$(WOLFBOOT_ROOT)/tools/keytools/keygen
else
	ifneq ("$(wildcard $(WOLFBOOT_ROOT)/tools/keytools/keygen.exe)","")
		KEYGEN_TOOL=$(WOLFBOOT_ROOT)/tools/keytools/keygen.exe
	else
		KEYGEN_TOOL=python3 $(WOLFBOOT_ROOT)/tools/keytools/keygen.py
	endif
endif

ifneq ("$(wildcard $(WOLFBOOT_ROOT)/tools/keytools/sign)","")
	SIGN_TOOL=$(WOLFBOOT_ROOT)/tools/keytools/sign
else
	ifneq ("$(wildcard $(WOLFBOOT_ROOT)/tools/keytools/sign.exe)","")
		SIGN_TOOL=$(WOLFBOOT_ROOT)/tools/keytools/sign.exe
	else
		SIGN_TOOL=python3 $(WOLFBOOT_ROOT)/tools/keytools/sign.py
	endif
endif


ifeq ($(TARGET),stm32f7)
  RENODE_CONFIG=tools/renode/stm32f746_wolfboot.resc
  POFF=393211
endif

ifeq ($(TARGET),hifive1)
  RENODE_CONFIG=tools/renode/sifive_fe310_wolfboot.resc
endif

ifeq ($(TARGET),nrf52)
  RENODE_CONFIG=tools/renode/nrf52840_wolfboot.resc
  POFF=262139
endif

ifeq ($(SIGN),NONE)
  SIGN_ARGS+=--no-sign
endif

ifeq ($(SIGN),ED25519)
  SIGN_ARGS+= --ed25519
endif

ifeq ($(SIGN),ED448)
  SIGN_ARGS+= --ed448
endif

ifeq ($(SIGN),ECC256)
  SIGN_ARGS+= --ecc256
endif

ifeq ($(SIGN),RSA2048)
  SIGN_ARGS+= --rsa2048
endif

ifeq ($(SIGN),RSA4096)
  SIGN_ARGS+= --rsa4096
endif

ifeq ($(HASH),SHA256)
  SIGN_ARGS+= --sha256
endif
ifeq ($(HASH),SHA3)
  SIGN_ARGS+= --sha3
endif

# Testbed actions
#
#
renode-on: FORCE
	${Q}rm -f $(RENODE_UART)
	${Q}renode $(RENODE_OPTIONS) $(RENODE_CONFIG) 2>&1 > $(RENODE_LOG) &
	${Q}while ! (test -e $(RENODE_UART)); do sleep .1; done
	${Q}echo "Renode up: uart port activated"
	${Q}echo "Renode running: renode has been started."

renode-off: FORCE
	${Q}echo "Terminating renode..."
	${Q}(echo && echo quit) | nc -q 1 localhost $(RENODE_PORT) > /dev/null
	${Q}tail --pid=`cat $(RENODE_PIDFILE)` -f /dev/null
	${Q}echo "Renode exited."
	${Q}killall renode 2>/dev/null || true
	${Q}killall mono 2>/dev/null || true
	${Q}rm -f $(RENODE_PIDFILE) $(RENODE_LOG) $(RENODE_UART)


renode-factory: factory.bin test-app/image.bin $(EXPVER) FORCE 
	${Q}rm -f $(RENODE_UART)
	${Q}dd if=/dev/zero bs=$(POFF) count=1 2>/dev/null | tr "\000" "\377" \
		> $(TMP)/renode-test-update.bin
	${Q}$(SIGN_TOOL) $(SIGN_ARGS) test-app/image.bin $(PRIVATE_KEY) 1
	${Q}$(SIGN_TOOL) $(SIGN_ARGS) test-app/image.bin $(PRIVATE_KEY) \
		$(TEST_UPDATE_VERSION)
	${Q}dd if=test-app/image_v$(TEST_UPDATE_VERSION)_signed.bin \
		of=$(TMP)/renode-test-update.bin bs=1 conv=notrunc
	${Q}printf "pBOOT" >> $(TMP)/renode-test-update.bin
	${Q}cp test-app/image_v1_signed.bin $(TMP)/renode-test-v1.bin
	${Q}cp wolfboot.elf $(TMP)/renode-wolfboot.elf
	${Q}make renode-on
	${Q}echo "Expecting version 1:"
	${Q}test `$(RENODE_EXPVER)` -eq 1 || (make renode-off && false)
	${Q}make renode-off
	${Q}rm -f $(TMP)/renode-wolfboot.elf
	${Q}rm -f $(TMP)/renode-test-v1.bin
	${Q}rm -f $(TMP)/renode-test-update.bin
	${Q}echo $@: TEST PASSED

renode-update: factory.bin test-app/image.bin $(EXPVER) FORCE
	${Q} test "$(TARGET)" = "nrf52" || (echo && echo " *** Error: only TARGET=nrf52 supported by $@" \
		&& echo && echo && false)
	${Q}rm -f $(RENODE_UART)
	${Q}dd if=/dev/zero bs=$(POFF) count=1 2>/dev/null | tr "\000" "\377" \
		> $(TMP)/renode-test-update.bin
	${Q}$(SIGN_TOOL) $(SIGN_ARGS) test-app/image.bin $(PRIVATE_KEY) 1
	${Q}$(SIGN_TOOL) $(SIGN_ARGS) test-app/image.bin $(PRIVATE_KEY) \
		$(TEST_UPDATE_VERSION)
	${Q}dd if=test-app/image_v$(TEST_UPDATE_VERSION)_signed.bin \
		of=$(TMP)/renode-test-update.bin bs=1 conv=notrunc
	${Q}printf "pBOOT" >> $(TMP)/renode-test-update.bin
	${Q}cp test-app/image_v1_signed.bin $(TMP)/renode-test-v1.bin
	${Q}cp wolfboot.elf $(TMP)/renode-wolfboot.elf
	${Q}make renode-on
	${Q}echo "Expecting version 1:"
	${Q}test `$(RENODE_EXPVER)` -eq 1 || (make renode-off && false)
	${Q}echo "Expecting version 2:"
	${Q}test `$(RENODE_EXPVER)` -eq $(TEST_UPDATE_VERSION) || \
		(make renode-off && false)
	${Q}make renode-off
	${Q}rm -f $(TMP)/renode-wolfboot.elf
	${Q}rm -f $(TMP)/renode-test-v1.bin
	${Q}rm -f $(TMP)/renode-test-update.bin
	${Q}echo $@: TEST PASSED

renode-factory-ed448: FORCE
	make renode-factory SIGN=ED448

renode-factory-ecc256: FORCE
	make renode-factory SIGN=ECC256

renode-factory-rsa2048: FORCE
	make renode-factory SIGN=RSA2048

renode-factory-rsa4096: FORCE
	make renode-factory SIGN=RSA4096

renode-factory-all: FORCE
	${Q}make clean
	${Q}make renode-factory
	${Q}make clean
	${Q}make renode-factory-ed448 RENODE_PORT=55156
	${Q}make clean
	${Q}make renode-factory-ecc256 RENODE_PORT=55157
	${Q}make clean
	${Q}make renode-factory-rsa2048 RENODE_PORT=55158
	${Q}make clean
	${Q}make renode-factory-rsa4096 RENODE_PORT=55159
	${Q}echo All tests in $@ OK!

renode-update-ed448: FORCE
	make renode-update SIGN=ED448

renode-update-ecc256: FORCE
	make renode-update SIGN=ECC256

renode-update-rsa2048: FORCE
	make renode-update SIGN=RSA2048

renode-update-rsa4096: FORCE
	make renode-update SIGN=RSA4096

renode-update-all: FORCE
	${Q}make clean
	${Q}make renode-update
	${Q}make clean
	${Q}make renode-update-ed448 RENODE_PORT=55156
	${Q}make clean
	${Q}make renode-update-ecc256 RENODE_PORT=55157
	${Q}make clean
	${Q}make renode-update-rsa2048 RENODE_PORT=55158
	${Q}make clean
	${Q}make renode-update-rsa4096 RENODE_PORT=55159
	${Q}echo All tests in $@ OK!
