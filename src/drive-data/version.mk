ifndef ROLLCOMPILER
  ROLLCOMPILER = gnu
endif
COMPILERNAME := $(firstword $(subst /, ,$(ROLLCOMPILER)))

NAME           = sdsc-seagate
VERSION        = 6.2
RELEASE        = 1
PKGROOT        = /opt/seagate

SRC_SUBDIR     = seagate

RPMS           = sdsc-seagate-private-6.2-0.x86_64.rpm

RPM.EXTRAS     = AutoReq:No
