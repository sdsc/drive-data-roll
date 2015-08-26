#!/bin/sh

ROCKS_VERSION=`cat /etc/rocks-release 2>/dev/null | awk '{print $3}'`
DESC_CMD="git describe --match 'v${ROCKS_VERSION}' 2>/dev/null | sed \"s/v\([0-9\.]*\)-*\([0-9]*\)-*\([0-9a-z]*\)/\1 \2 \3/\""
DESC=`eval ${DESC_CMD}`
#DESC=`git describe --match 'v*' 2>/dev/null | sed "s/v\([0-9\.]*\)-*\([0-9]*\)-*\([0-9a-z]*\)/\1 \2 \3/"`

if [ ! -d "./.git" ] && [ -z "${DESC}" ]
then
    # Try to support using the tagged downloads
    DESC=`pwd | grep -oe 'drive-data-roll-.\+' | sed 's/drive-data-roll-//g'`
    LOCAL_REV="-github_archive"
fi

VERSION=`echo ${DESC} | awk '{ print $1 }' | tr "." " "`
COMMIT=`echo ${DESC} | awk '{ print $2 }'`
HASH=`echo ${DESC} | awk '{ print $3}'`

VERSION_MAJ=`echo ${VERSION} | awk '{ print $1 }'`
if [ -z "${VERSION_MAJ}" ]; then
    VERSION_MAJ="0"
fi

VERSION_MIN=`echo ${VERSION} | awk '{ print $2 }'`
if [ -z "${VERSION_MIN}" ]; then
    VERSION_MIN="0"
fi

VERSION_DOT=`echo ${VERSION} | awk '{ print $3 }'`
if [ -n "${VERSION_DOT}" ]; then
    VERSION_DOT="."${VERSION_DOT}
fi

VERSION_REV=${COMMIT}
if [ -z "${VERSION_REV}" ]; then
    VERSION_REV="0"
fi

VERSION_HASH=${HASH}
if [ -z "${VERSION_HASH}" ]; then
    VERSION_HASH="g"
fi


#Allow local revision identifiers
#mimicing backports this is "-<identifier>"
if [ -e localversion ]; then
    LOCAL_REV=$(cat localversion)
    if [ -n "${LOCAL_REV}" ];
    then
        LOCAL_REV="-${LOCAL_REV}"
    fi
fi

while getopts "avmndrh" opt; do
    case $opt in
	a)
	   # Major.Minor-Release.Hash
	   echo "${VERSION_MAJ}.${VERSION_MIN}${VERSION_DOT}-${VERSION_REV}.${VERSION_HASH}"
	   exit 0
	   ;;
	v)
	   # Major.Minor.Dot Version
	   echo "${VERSION_MAJ}.${VERSION_MIN}${VERSION_DOT}"
	   exit 0
	   ;;
        m)
            # Major Version
            echo "${VERSION_MAJ}"
            exit 0
            ;;
        n)
            # Minor Version
            echo "${VERSION_MIN}"
            exit 0
            ;;
	d)
	    # Dot Version
	    echo `echo ${VERSION_DOT} | cut -d. -f2`
	    exit 0
	    ;;
        r)
            # Revision Version
            echo "${VERSION_REV}"
            exit 0
            ;;
	h)
	    # Revision Hash
	    echo "${VERSION_REV}.${VERSION_HASH}"
	    exit 0
	    ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

VERSION="${VERSION_MAJ}.${VERSION_MIN}.${VERSION_REV}${LOCAL_REV}"

echo $VERSION

